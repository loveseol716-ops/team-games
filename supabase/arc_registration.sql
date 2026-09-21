
-- ARC #01 captain-first entry; all privileged entry logic stays in private.
create table private.arc_entry_codes (
 id uuid primary key default gen_random_uuid(),
 event_id uuid not null references public.tg_events(id) on delete cascade,
 user_id uuid not null references auth.users(id) on delete cascade,
 code text not null unique,
 active boolean not null default true,
 issued_by uuid not null references auth.users(id),
 created_at timestamptz not null default now(),
 unique(event_id,user_id)
);
create table private.arc_entries (
 team_id uuid primary key references public.tg_teams(id) on delete cascade,
 captain_id uuid not null references auth.users(id),
 captain_gender text not null check(captain_gender in ('male','female')),
 base_fee integer not null check(base_fee in (20000,25000)),
 captain_fee integer not null,
 partner_fee integer not null,
 captain_code_id uuid references private.arc_entry_codes(id),
 partner_code_id uuid references private.arc_entry_codes(id),
 consent_at timestamptz not null default now(),
 consent_version text not null default '2026-09-21',
 created_at timestamptz not null default now()
);
create table private.arc_entry_invites (
 id uuid primary key default gen_random_uuid(),
 team_id uuid not null references public.tg_teams(id) on delete cascade,
 invitee_id uuid not null references auth.users(id) on delete cascade,
 status text not null default 'pending' check(status in ('pending','accepted','declined','cancelled')),
 created_at timestamptz not null default now(),
 responded_at timestamptz
);
create unique index arc_entry_pending_invite on private.arc_entry_invites(team_id) where status='pending';
create index arc_entry_invitee on private.arc_entry_invites(invitee_id,status);
alter table private.arc_entry_codes enable row level security;
alter table private.arc_entries enable row level security;
alter table private.arc_entry_invites enable row level security;
revoke all on private.arc_entry_codes,private.arc_entries,private.arc_entry_invites from public,anon,authenticated;

create function private.arc_entry_quote(p_event_id uuid,p_captain_code text,p_partner_code text)
returns jsonb language plpgsql security definer set search_path = '' as $$
declare u uuid:=auth.uid(); base integer; c private.arc_entry_codes%rowtype; p private.arc_entry_codes%rowtype;
begin
 if u is null then raise exception 'AUTH_REQUIRED'; end if;
 base:=case when now()<timestamptz '2026-10-11 00:00:00+09' then 20000 else 25000 end;
 if nullif(trim(p_captain_code),'') is not null then
  select * into c from private.arc_entry_codes where event_id=p_event_id and code=upper(trim(p_captain_code)) and active;
  if c.id is null or c.user_id<>u then raise exception 'INVALID_CAPTAIN_CODE'; end if;
 end if;
 if nullif(trim(p_partner_code),'') is not null then
  select * into p from private.arc_entry_codes where event_id=p_event_id and code=upper(trim(p_partner_code)) and active;
  if p.id is null or p.user_id=u then raise exception 'INVALID_PARTNER_CODE'; end if;
 end if;
 if exists(select 1 from private.arc_entries e join public.tg_teams t on t.id=e.team_id
  where (e.captain_code_id in(c.id,p.id) or e.partner_code_id in(c.id,p.id))
  and (t.status='confirmed' or (t.status='pending_payment' and (t.payment_status='payment_check' or t.payment_deadline>now()))))
 then raise exception 'CODE_ALREADY_USED'; end if;
 return jsonb_build_object('base_fee',base,'captain_fee',case when c.id is null then base else base/2 end,
 'partner_fee',case when p.id is null then base else base/2 end,
 'amount_due',(case when c.id is null then base else base/2 end)+(case when p.id is null then base else base/2 end),
 'pricing_tier',case when base=20000 then 'early_bird' else 'regular' end,
 'captain_code_id',c.id,'partner_code_id',p.id,
 'partner_name',(select display_name from public.arc_profiles where user_id=p.user_id));
end; $$;
revoke all on function private.arc_entry_quote(uuid,text,text) from public,anon,authenticated;

create function private.arc_entry_action(p_action text,p_payload jsonb)
returns jsonb language plpgsql security definer set search_path = '' as $$
declare u uuid:=auth.uid(); ev public.tg_events%rowtype; t public.tg_teams%rowtype;
 e private.arc_entries%rowtype; inv private.arc_entry_invites%rowtype; athlete public.tg_athletes%rowtype;
 q jsonb; tid uuid; target uuid; codeid uuid; cnt integer; phone text; cat text; codeval text; res jsonb; profile jsonb;
begin
 if u is null then raise exception 'AUTH_REQUIRED'; end if;
 select * into ev from public.tg_events where slug='team-games-001';
 if ev.id is null then raise exception 'EVENT_NOT_FOUND'; end if;
 if p_action like 'admin_%' then
  if not exists(select 1 from public.tg_admins where user_id=u) then raise exception 'ADMIN_ONLY'; end if;
  if p_action='admin_issue_code' then
   select a.user_id into target from public.arc_profiles a join auth.users au on au.id=a.user_id
    where lower(au.email)=lower(trim(p_payload->>'email'));
   if target is null then raise exception 'ARC_ACCOUNT_NOT_FOUND'; end if;
   perform pg_advisory_xact_lock(hashtextextended(ev.id::text,0));
   insert into private.arc_entry_codes(event_id,user_id,code,issued_by)
    values(ev.id,target,'NOLTO-'||upper(substr(replace(gen_random_uuid()::text,'-',''),1,20)),u)
    on conflict(event_id,user_id) do update set active=true
    returning code into codeval;
   return jsonb_build_object('code',codeval);
  elsif p_action='admin_revoke_code' then
   perform pg_advisory_xact_lock(hashtextextended(ev.id::text,0));
   codeid:=(p_payload->>'code_id')::uuid;
   if exists(select 1 from private.arc_entries en join public.tg_teams tm on tm.id=en.team_id
     where codeid in(en.captain_code_id,en.partner_code_id) and tm.status in ('confirmed','pending_payment'))
    then raise exception 'CODE_ALREADY_USED'; end if;
   update private.arc_entry_codes set active=false where id=codeid and event_id=ev.id;
   return '{}'::jsonb;
  elsif p_action='admin_codes' then
   select coalesce(jsonb_agg(jsonb_build_object('id',c.id,'code',c.code,'active',c.active,'name',a.display_name,'email',au.email,
   'used',exists(select 1 from private.arc_entries en join public.tg_teams tm on tm.id=en.team_id where c.id in(en.captain_code_id,en.partner_code_id) and tm.status in ('confirmed','pending_payment'))) order by c.created_at desc),'[]'::jsonb)
   into res from private.arc_entry_codes c join public.arc_profiles a on a.user_id=c.user_id join auth.users au on au.id=c.user_id where c.event_id=ev.id;
   return res;
  else raise exception 'INVALID_ACTION'; end if;
 end if;
 if p_action='state' then
  select jsonb_build_object(
   'entry',(select jsonb_build_object('id',tm.id,'team_name',tm.team_name,'division',tm.division,'category',tm.category,'status',tm.status,
     'payment_status',tm.payment_status,'amount_due',tm.amount_due,'deadline',tm.payment_deadline,'depositor_name',tm.depositor_name,
     'captain_fee',en.captain_fee,'partner_fee',en.partner_fee,'is_captain',en.captain_id=u,'player_1',tm.player_1,'player_2',tm.player_2,
     'roster_complete',(select count(*)=2 from public.tg_team_members m where m.team_id=tm.id and m.active),
     'partner_discount_name',(select ap.display_name from private.arc_entry_codes c join public.arc_profiles ap on ap.user_id=c.user_id where c.id=en.partner_code_id),
     'pending_invite',(select jsonb_build_object('id',i.id,'name',ap.display_name) from private.arc_entry_invites i join public.arc_profiles ap on ap.user_id=i.invitee_id where i.team_id=tm.id and i.status='pending'))
     from private.arc_entries en join public.tg_teams tm on tm.id=en.team_id
     where tm.event_id=ev.id and tm.status in ('pending_payment','confirmed') and (en.captain_id=u or exists(select 1 from public.tg_team_members m where m.team_id=tm.id and m.athlete_id=u and m.active))
     order by tm.created_at desc limit 1),
   'invites',(select coalesce(jsonb_agg(jsonb_build_object('id',i.id,'team_name',tm.team_name,'division',tm.division,'category',tm.category,'captain',tm.player_1)),'[]'::jsonb)
     from private.arc_entry_invites i join public.tg_teams tm on tm.id=i.team_id where i.invitee_id=u and i.status='pending' and tm.status='confirmed'),
   'code',(select code from private.arc_entry_codes where user_id=u and event_id=ev.id and active),
   'registration_open',ev.registration_open and now()<ev.event_date,
   'base_fee',case when now()<timestamptz '2026-10-11 00:00:00+09' then 20000 else 25000 end)
  into res;
  return res;
 elsif p_action='quote' then
  q:=private.arc_entry_quote(ev.id,p_payload->>'captain_code',p_payload->>'partner_code');
  return q-'captain_code_id'-'partner_code_id';
 elsif p_action='register' then
  if not ev.registration_open or now()>=ev.event_date then raise exception 'REGISTRATION_CLOSED'; end if;
  if not coalesce((p_payload->>'consent')::boolean,false) then raise exception 'CONSENT_REQUIRED'; end if;
  if length(trim(coalesce(p_payload->>'team_name',''))) not between 1 and 60 then raise exception 'TEAM_NAME_REQUIRED'; end if;
  if coalesce(p_payload->>'division','') not in ('OPEN','PRO') then raise exception 'INVALID_DIVISION'; end if;
  cat:=p_payload->>'category';
  if coalesce(cat,'') not in ('MM','WW','MIXED') then raise exception 'INVALID_CATEGORY'; end if;
  select to_jsonb(p) into profile from public.arc_player_profile() p;
  if not coalesce((profile->>'profile_complete')::boolean,false) then raise exception 'PROFILE_REQUIRED'; end if;
  select * into athlete from public.tg_athletes where id=u;
  if (cat='MM' and athlete.gender<>'male') or (cat='WW' and athlete.gender<>'female') then raise exception 'CATEGORY_GENDER_MISMATCH'; end if;
  perform pg_advisory_xact_lock(hashtextextended(ev.id::text,0));
  -- Expired unpaid reservations release capacity and membership before the next application.
  update public.tg_teams tm set status='cancelled',payment_status='cancelled' where tm.event_id=ev.id and tm.status='pending_payment'
   and tm.payment_status='unpaid' and tm.payment_deadline<=now() and exists(select 1 from private.arc_entries en where en.team_id=tm.id);
  if exists(select 1 from public.tg_team_members where event_id=ev.id and athlete_id=u and active) then raise exception 'ALREADY_REGISTERED'; end if;
  select count(*) into cnt from public.tg_teams where event_id=ev.id and division=p_payload->>'division' and category=cat
   and (status='confirmed' or (status='pending_payment' and (payment_status='payment_check' or payment_deadline>now())));
  if cnt>=4 then raise exception 'CATEGORY_FULL'; end if;
  select count(*) into cnt from public.tg_teams where event_id=ev.id and (status='confirmed' or (status='pending_payment' and (payment_status='payment_check' or payment_deadline>now())));
  if cnt>=ev.max_teams then raise exception 'REGISTRATION_FULL'; end if;
  q:=private.arc_entry_quote(ev.id,p_payload->>'captain_code',p_payload->>'partner_code');
  if (q->>'amount_due')::integer is distinct from (p_payload->>'expected_amount')::integer then raise exception 'PRICE_CHANGED'; end if;
  if q->>'partner_code_id' is not null then
   select c.user_id into target from private.arc_entry_codes c where c.id=(q->>'partner_code_id')::uuid;
   if exists(select 1 from public.tg_team_members where event_id=ev.id and athlete_id=target and active) then raise exception 'PARTNER_ALREADY_REGISTERED'; end if;
   if exists(select 1 from public.tg_athletes a where a.id=target and
    ((cat='MM' and a.gender<>'male') or (cat='WW' and a.gender<>'female') or (cat='MIXED' and a.gender=athlete.gender)))
    then raise exception 'CATEGORY_GENDER_MISMATCH'; end if;
  end if;
  select p.phone into phone from public.tg_athlete_private p where p.athlete_id=u;
  insert into public.tg_teams(event_id,team_name,player_1,player_2,phone,photo_url,status,division,category,payment_status,pricing_tier,amount_due,payment_deadline)
   values(ev.id,trim(p_payload->>'team_name'),athlete.display_name,'팀원 초대 예정',phone,athlete.photo_url,'pending_payment',p_payload->>'division',cat,'unpaid',q->>'pricing_tier',(q->>'amount_due')::integer,least(now()+interval '24 hours',ev.event_date))
   returning id into tid;
  insert into private.arc_entries(team_id,captain_id,captain_gender,base_fee,captain_fee,partner_fee,captain_code_id,partner_code_id)
   values(tid,u,athlete.gender,(q->>'base_fee')::integer,(q->>'captain_fee')::integer,(q->>'partner_fee')::integer,(q->>'captain_code_id')::uuid,(q->>'partner_code_id')::uuid);
  insert into public.tg_team_members(team_id,event_id,athlete_id,member_role) values(tid,ev.id,u,'captain');
  return jsonb_build_object('team_id',tid);
 elsif p_action='respond' then
  select * into inv from private.arc_entry_invites where id=(p_payload->>'invite_id')::uuid;
  if inv.id is null or inv.invitee_id<>u then raise exception 'INVITE_NOT_FOUND'; end if;
  perform pg_advisory_xact_lock(hashtextextended(ev.id::text,0));
  select * into inv from private.arc_entry_invites where id=inv.id for update;
  if inv.status<>'pending' then raise exception 'INVITE_NOT_PENDING'; end if;
  if not coalesce((p_payload->>'accept')::boolean,false) then
   update private.arc_entry_invites set status='declined',responded_at=now() where id=inv.id;
   return '{}'::jsonb;
  end if;
  select * into t from public.tg_teams where id=inv.team_id for update;
  select * into e from private.arc_entries where team_id=t.id;
  if t.status<>'confirmed' or t.payment_status<>'paid' then raise exception 'PAYMENT_NOT_CONFIRMED'; end if;
  if now()>=ev.event_date then raise exception 'REGISTRATION_CLOSED'; end if;
  if not coalesce((p_payload->>'consent')::boolean,false) then raise exception 'CONSENT_REQUIRED'; end if;
  select to_jsonb(p) into profile from public.arc_player_profile() p;
  if not coalesce((profile->>'profile_complete')::boolean,false) then raise exception 'PROFILE_REQUIRED'; end if;
  if exists(select 1 from public.tg_team_members where event_id=ev.id and athlete_id=u and active) then raise exception 'ALREADY_REGISTERED'; end if;
  if (select count(*) from public.tg_team_members where team_id=t.id and active)>=2 then raise exception 'TEAM_FULL'; end if;
  select * into athlete from public.tg_athletes where id=u;
  if (t.category='MM' and athlete.gender<>'male') or (t.category='WW' and athlete.gender<>'female') or (t.category='MIXED' and athlete.gender=e.captain_gender) then raise exception 'CATEGORY_GENDER_MISMATCH'; end if;
  if e.partner_code_id is not null and not exists(select 1 from private.arc_entry_codes where id=e.partner_code_id and user_id=u) then raise exception 'DISCOUNT_PARTNER_ONLY'; end if;
  insert into public.tg_team_members(team_id,event_id,athlete_id,member_role) values(t.id,ev.id,u,'partner');
  update public.tg_teams set player_2=athlete.display_name where id=t.id;
  update private.arc_entry_invites set status='accepted',responded_at=now() where id=inv.id;
  update private.arc_entry_invites set status='cancelled',responded_at=now() where invitee_id=u and status='pending';
  return '{}'::jsonb;
 else
  tid:=(p_payload->>'team_id')::uuid;
  perform pg_advisory_xact_lock(hashtextextended(ev.id::text,0));
  select * into e from private.arc_entries where team_id=tid;
  if e.team_id is null or e.captain_id<>u then raise exception 'CAPTAIN_ONLY'; end if;
  select * into t from public.tg_teams where id=tid for update;
  if p_action='report_payment' then
   perform public.tg_report_bank_payment(tid,p_payload->>'depositor_name');
   return '{}'::jsonb;
  elsif p_action='cancel' then
   if t.status<>'pending_payment' or t.payment_status<>'unpaid' then raise exception 'CONTACT_FOR_CANCELLATION'; end if;
   update public.tg_teams set status='cancelled',payment_status='cancelled' where id=tid;
   return '{}'::jsonb;
  elsif p_action in ('invite','cancel_invite') then
   if t.status<>'confirmed' or t.payment_status<>'paid' then raise exception 'PAYMENT_NOT_CONFIRMED'; end if;
   if now()>=ev.event_date then raise exception 'REGISTRATION_CLOSED'; end if;
   if p_action='cancel_invite' then
    update private.arc_entry_invites set status='cancelled',responded_at=now() where team_id=tid and status='pending';
    return '{}'::jsonb;
   end if;
   if (select count(*) from public.tg_team_members where team_id=tid and active)>=2 then raise exception 'TEAM_FULL'; end if;
   select a.user_id into target from public.arc_profiles a join auth.users au on au.id=a.user_id where lower(au.email)=lower(trim(p_payload->>'email'));
   if target is null then raise exception 'ARC_ACCOUNT_NOT_FOUND'; end if;
   if target=u then raise exception 'CANNOT_INVITE_SELF'; end if;
   if e.partner_code_id is not null and not exists(select 1 from private.arc_entry_codes where id=e.partner_code_id and user_id=target) then raise exception 'DISCOUNT_PARTNER_ONLY'; end if;
   if exists(select 1 from public.tg_team_members where event_id=ev.id and athlete_id=target and active) then raise exception 'PARTNER_ALREADY_REGISTERED'; end if;
   update private.arc_entry_invites set status='cancelled',responded_at=now() where team_id=tid and status='pending';
   insert into private.arc_entry_invites(team_id,invitee_id) values(tid,target);
   return '{}'::jsonb;
  else raise exception 'INVALID_ACTION'; end if;
 end if;
end; $$;
revoke all on function private.arc_entry_action(text,jsonb) from public,anon,authenticated;
grant execute on function private.arc_entry_action(text,jsonb) to authenticated;
create function public.arc_entry_action(p_action text,p_payload jsonb default '{}'::jsonb)
returns jsonb language sql security invoker set search_path = '' as $$
 select private.arc_entry_action(p_action,p_payload);
$$;
revoke all on function public.arc_entry_action(text,jsonb) from public,anon;
grant execute on function public.arc_entry_action(text,jsonb) to authenticated;

-- Block the old invite-before-payment pricing path for this event.
create or replace function public.tg_send_team_invite(p_event_slug text,p_invitee_id uuid,p_team_name text,p_division text)
returns uuid language plpgsql security invoker set search_path = '' as $$
begin
 if p_event_slug='team-games-001' then raise exception 'USE_ENTRY_PAGE'; end if;
 return private.tg_send_team_invite_core(p_event_slug,p_invitee_id,p_team_name,p_division);
end; $$;
create or replace function public.tg_respond_team_invite(p_invite_id uuid,p_accept boolean)
returns uuid language plpgsql security invoker set search_path = '' as $$
begin
 if exists(select 1 from public.tg_team_invites i join public.tg_events ev on ev.id=i.event_id where i.id=p_invite_id and ev.slug='team-games-001') then raise exception 'USE_ENTRY_PAGE'; end if;
 return private.tg_respond_team_invite_core(p_invite_id,p_accept);
end; $$;

CREATE OR REPLACE FUNCTION public.tg_admin_confirm_payment(p_team_id uuid)
 RETURNS void
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $function$
declare v_team public.tg_teams%rowtype; v_event public.tg_events%rowtype; v_slot integer; v_count integer;
begin
  if exists(select 1 from private.arc_entries where team_id=p_team_id) then
    if exists(select 1 from public.tg_teams where id=p_team_id and status='pending_payment' and payment_status<>'payment_check') then raise exception 'PAYMENT_NOT_REPORTED'; end if;
  end if;
  if not exists(select 1 from public.tg_admins where user_id=auth.uid()) then raise exception 'ADMIN_ONLY'; end if;
  select * into v_team from public.tg_teams where id=p_team_id for update;
  if not found then raise exception 'TEAM_NOT_FOUND'; end if;
  if v_team.status='confirmed' and v_team.payment_status='paid' then return; end if;
  if v_team.status<>'pending_payment' then raise exception 'PAYMENT_NOT_PENDING'; end if;
  perform pg_advisory_xact_lock(hashtextextended(v_team.event_id::text,23));
  select * into v_event from public.tg_events where id=v_team.event_id;
  select count(*) into v_count from public.tg_teams t where t.event_id=v_team.event_id and t.id<>v_team.id and t.division=v_team.division and t.category=v_team.category and t.status='confirmed';
  if v_count>=4 then raise exception 'CATEGORY_FULL'; end if;
  select s.slot_no into v_slot from generate_series(1,v_event.max_teams) s(slot_no)
  where not exists(select 1 from public.tg_teams t where t.event_id=v_team.event_id and t.status='confirmed' and ((t.heat_no-1)*2+t.station_no)=s.slot_no)
  order by s.slot_no limit 1;
  if v_slot is null then raise exception 'REGISTRATION_FULL'; end if;
  update public.tg_teams set heat_no=((v_slot-1)/2)+1,station_no=((v_slot-1)%2)+1,status='confirmed',payment_status='paid',paid_at=now() where id=p_team_id;
end; $function$;

CREATE OR REPLACE FUNCTION public.tg_cancel_my_team(p_team_id uuid)
 RETURNS void
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $function$
begin
  if exists(select 1 from private.arc_entries where team_id=p_team_id) then
    if exists(select 1 from public.tg_teams where id=p_team_id and payment_status<>'unpaid') then raise exception 'CONTACT_FOR_CANCELLATION'; end if;
  end if;
  if auth.uid() is null then raise exception 'AUTH_REQUIRED'; end if;
  if not exists(select 1 from public.tg_team_members where team_id=p_team_id and athlete_id=auth.uid() and active=true) then raise exception 'TEAM_MEMBER_ONLY'; end if;
  update public.tg_teams set status='cancelled',payment_status='cancelled' where id=p_team_id and status='pending_payment';
end; $function$;

CREATE OR REPLACE FUNCTION public.tg_reopen_payment_hold(p_team_id uuid)
 RETURNS void
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $function$
declare v_team public.tg_teams%rowtype; v_count integer; v_amount integer; v_tier text;
begin
  if exists(select 1 from private.arc_entries where team_id=p_team_id) then
    raise exception 'USE_ENTRY_PAGE';
  end if;
  if auth.uid() is null then raise exception 'AUTH_REQUIRED'; end if;
  if not exists(select 1 from public.tg_team_members where team_id=p_team_id and athlete_id=auth.uid() and active=true) then raise exception 'TEAM_MEMBER_ONLY'; end if;
  select * into v_team from public.tg_teams where id=p_team_id for update;
  if v_team.status<>'pending_payment' then raise exception 'PAYMENT_NOT_PENDING'; end if;
  perform pg_advisory_xact_lock(hashtextextended(v_team.event_id::text,22));
  select count(*) into v_count from public.tg_teams t
  where t.event_id=v_team.event_id and t.id<>v_team.id and t.division=v_team.division and t.category=v_team.category
    and (t.status='confirmed' or (t.status='pending_payment' and (t.payment_status='payment_check' or t.payment_deadline>now())));
  if v_count>=4 then raise exception 'CATEGORY_FULL'; end if;
  if now() <= timestamptz '2026-10-10 23:59:59+09' then v_amount:=20000; v_tier:='early_bird'; else v_amount:=30000; v_tier:='regular'; end if;
  update public.tg_teams set payment_status='unpaid',pricing_tier=v_tier,amount_due=v_amount,payment_deadline=now()+interval '24 hours',depositor_name=null,payment_reported_at=null where id=p_team_id;
end; $function$;