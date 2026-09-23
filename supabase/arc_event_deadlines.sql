alter table public.tg_events add column if not exists early_bird_ends_at timestamptz;
alter table public.tg_events add column if not exists registration_closes_at timestamptz;
update public.tg_events set max_teams=24,early_bird_ends_at='2026-10-11 00:00:00+09',registration_closes_at='2026-10-25 00:00:00+09' where slug='team-games-001';

create or replace function private.arc_event_terms(p_event_id uuid,p_at timestamptz default now())
returns jsonb language sql stable security definer set search_path='' as $$
 select jsonb_build_object('server_now',p_at,'max_teams',e.max_teams,
 'early_bird_ends_at',e.early_bird_ends_at,'registration_closes_at',coalesce(e.registration_closes_at,e.event_date),
 'early_bird',p_at<coalesce(e.early_bird_ends_at,'2026-10-11 00:00:00+09'::timestamptz),
 'base_fee',case when p_at<coalesce(e.early_bird_ends_at,'2026-10-11 00:00:00+09'::timestamptz) then 20000 else 25000 end,
 'registration_open',e.registration_open and p_at<least(coalesce(e.registration_closes_at,e.event_date),e.event_date),
 'filled',(select count(*) from public.tg_teams t where t.event_id=e.id and (t.status='confirmed' or(t.status='pending_payment' and(t.payment_status='payment_check' or t.payment_deadline>p_at)))))
 from public.tg_events e where e.id=p_event_id;
$$;
revoke all on function private.arc_event_terms(uuid,timestamptz) from public,anon,authenticated;

create or replace function public.arc_event_status(p_event_slug text)
returns jsonb language sql stable security definer set search_path='' as $$
 select private.arc_event_terms(id) from public.tg_events where slug=p_event_slug;
$$;
revoke all on function public.arc_event_status(text) from public;
grant execute on function public.arc_event_status(text) to anon,authenticated;

create or replace function public.tg_event_capacity(p_event_slug text)
returns table(division text,category text,filled integer,capacity integer)
language sql stable security definer set search_path='' as $$
 select null::text,null::text,(private.arc_event_terms(id)->>'filled')::integer,max_teams from public.tg_events where slug=p_event_slug;
$$;

-- All admissions share the event lock and the same total capacity. Existing
-- paid teams may finish their roster after the public application deadline.
create or replace function private.arc_guard_event_admission()
returns trigger language plpgsql security definer set search_path='' as $$
declare was_reserved boolean:=false; is_reserved boolean; e public.tg_events%rowtype; used integer;
begin
 perform pg_advisory_xact_lock(hashtextextended(new.event_id::text,0));
 select * into e from public.tg_events where id=new.event_id;
 is_reserved:=new.status='confirmed' or(new.status='pending_payment' and(new.payment_status='payment_check' or new.payment_deadline>now()));
 if tg_op='UPDATE' then
  was_reserved:=old.event_id=new.event_id and(old.status='confirmed' or(old.status='pending_payment' and(old.payment_status='payment_check' or old.payment_deadline>now())));
 end if;
 if coalesce(is_reserved,false) and not coalesce(was_reserved,false) then
  if not private.tg_is_admin() and not (private.arc_event_terms(new.event_id)->>'registration_open')::boolean then raise exception 'REGISTRATION_CLOSED'; end if;
  select count(*) into used from public.tg_teams t where t.event_id=new.event_id and t.id<>new.id and(t.status='confirmed' or(t.status='pending_payment' and(t.payment_status='payment_check' or t.payment_deadline>now())));
  if used>=e.max_teams then raise exception 'REGISTRATION_FULL'; end if;
 end if;
 return new;
end $$;
revoke all on function private.arc_guard_event_admission() from public,anon,authenticated;
drop trigger if exists arc_guard_event_admission on public.tg_teams;
create trigger arc_guard_event_admission before insert or update of status,payment_status,payment_deadline,event_id on public.tg_teams for each row execute function private.arc_guard_event_admission();
CREATE OR REPLACE FUNCTION private.tg_respond_team_invite_core(p_invite_id uuid, p_accept boolean)
 RETURNS uuid
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'private', 'pg_temp'
AS $function$
declare
  v_uid uuid:=(select auth.uid()); v_inv public.tg_team_invites%rowtype; v_event public.tg_events%rowtype;
  v_captain public.tg_athletes%rowtype; v_invitee public.tg_athletes%rowtype; v_phone text; v_team_id uuid;
  v_category text; v_count integer; v_amount integer; v_tier text;
begin
  if v_uid is null then raise exception 'AUTH_REQUIRED'; end if;
  select * into v_inv from public.tg_team_invites where id=p_invite_id for update;
  if not found then raise exception 'INVITE_NOT_FOUND'; end if;
  if v_inv.invitee_id<>v_uid then raise exception 'INVITEE_ONLY'; end if;
  if v_inv.status<>'pending' then raise exception 'INVITE_NOT_PENDING'; end if;
  if not p_accept then
    update public.tg_team_invites set status='declined',responded_at=now() where id=p_invite_id;
    return null;
  end if;
  select * into v_event from public.tg_events where id=v_inv.event_id;
  if not (private.arc_event_terms(v_event.id)->>'registration_open')::boolean then raise exception 'REGISTRATION_CLOSED'; end if;
  perform pg_advisory_xact_lock(hashtextextended(v_inv.event_id::text,21));
  if exists(select 1 from public.tg_team_members where event_id=v_inv.event_id and athlete_id in(v_inv.captain_id,v_inv.invitee_id) and active=true) then raise exception 'ATHLETE_ALREADY_LOCKED_IN'; end if;
  select * into v_captain from public.tg_athletes where id=v_inv.captain_id;
  select * into v_invitee from public.tg_athletes where id=v_inv.invitee_id;
  if v_captain.id is null or v_invitee.id is null then raise exception 'ATHLETE_NOT_FOUND'; end if;
  v_category:=case when v_captain.gender='male' and v_invitee.gender='male' then 'MM' when v_captain.gender='female' and v_invitee.gender='female' then 'WW' else 'MIXED' end;

  select phone into v_phone from public.tg_athlete_private where athlete_id=v_inv.captain_id;
  if v_phone is null then raise exception 'CAPTAIN_PHONE_REQUIRED'; end if;
  if (private.arc_event_terms(v_event.id)->>'early_bird')::boolean then v_amount:=40000; v_tier:='early_bird'; else v_amount:=50000; v_tier:='regular'; end if;
  insert into public.tg_teams(event_id,team_name,player_1,player_2,phone,photo_url,status,division,category,payment_status,pricing_tier,amount_due,payment_deadline)
  values(v_inv.event_id,v_inv.team_name,v_captain.display_name,v_invitee.display_name,v_phone,coalesce(v_captain.photo_url,v_invitee.photo_url),'pending_payment',v_inv.division,v_category,'unpaid',v_tier,v_amount,now()+interval '24 hours')
  returning id into v_team_id;
  insert into public.tg_team_members(team_id,event_id,athlete_id,member_role,active)
  values(v_team_id,v_inv.event_id,v_inv.captain_id,'captain',true),(v_team_id,v_inv.event_id,v_inv.invitee_id,'partner',true);
  update public.tg_team_invites set status='accepted',responded_at=now() where id=p_invite_id;
  update public.tg_team_invites set status='cancelled',responded_at=now()
  where event_id=v_inv.event_id and status='pending' and id<>p_invite_id
    and (captain_id in(v_inv.captain_id,v_inv.invitee_id) or invitee_id in(v_inv.captain_id,v_inv.invitee_id));
  return v_team_id;
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
  if not (private.arc_event_terms(v_team.event_id)->>'registration_open')::boolean then raise exception 'REGISTRATION_CLOSED'; end if;
  perform pg_advisory_xact_lock(hashtextextended(v_team.event_id::text,22));

  if (private.arc_event_terms(v_team.event_id)->>'early_bird')::boolean then v_amount:=40000; v_tier:='early_bird'; else v_amount:=50000; v_tier:='regular'; end if;
  update public.tg_teams set payment_status='unpaid',pricing_tier=v_tier,amount_due=v_amount,payment_deadline=now()+interval '24 hours',depositor_name=null,payment_reported_at=null where id=p_team_id;
end; $function$;

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

  select s.slot_no into v_slot from generate_series(1,v_event.max_teams) s(slot_no)
  where not exists(select 1 from public.tg_teams t where t.event_id=v_team.event_id and t.status='confirmed' and ((t.heat_no-1)*2+t.station_no)=s.slot_no)
  order by s.slot_no limit 1;
  if v_slot is null then raise exception 'REGISTRATION_FULL'; end if;
  update public.tg_teams set heat_no=((v_slot-1)/2)+1,station_no=((v_slot-1)%2)+1,status='confirmed',payment_status='paid',paid_at=now() where id=p_team_id;
end; $function$;

CREATE OR REPLACE FUNCTION public.tg_admin_add_team(p_event_slug text, p_team_name text, p_captain_id uuid, p_partner_id uuid, p_division text)
 RETURNS uuid
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'private', 'pg_temp'
AS $function$
declare v_event public.tg_events%rowtype; v_c public.tg_athletes%rowtype; v_p public.tg_athletes%rowtype; v_phone text; v_photo text; v_team_id uuid; v_cat text; v_count integer;
begin
  if not private.tg_is_admin() then raise exception 'ADMIN_ONLY'; end if;
  if p_division not in ('OPEN','PRO') then raise exception 'INVALID_DIVISION'; end if;
  if p_captain_id is null or p_partner_id is null or p_captain_id=p_partner_id then raise exception 'INVALID_PLAYERS'; end if;
  if length(trim(coalesce(p_team_name,'')))=0 then raise exception 'TEAM_NAME_REQUIRED'; end if;
  select * into v_event from public.tg_events where slug=p_event_slug; if not found then raise exception 'EVENT_NOT_FOUND'; end if;
  if exists(select 1 from public.tg_team_members where event_id=v_event.id and athlete_id in(p_captain_id,p_partner_id) and active=true) then raise exception 'ATHLETE_ALREADY_LOCKED_IN'; end if;
  select * into v_c from public.tg_athletes where id=p_captain_id; select * into v_p from public.tg_athletes where id=p_partner_id;
  if v_c.id is null or v_p.id is null then raise exception 'ATHLETE_NOT_FOUND'; end if;
  v_cat:=case when v_c.gender='male' and v_p.gender='male' then 'MM' when v_c.gender='female' and v_p.gender='female' then 'WW' else 'MIXED' end;

  select phone into v_phone from public.tg_athlete_private where athlete_id=p_captain_id; if v_phone is null then raise exception 'CAPTAIN_PHONE_REQUIRED'; end if;
  v_photo:=coalesce(nullif(v_c.photo_url,''),nullif(v_p.photo_url,'')); if v_photo is null then raise exception 'ATHLETE_PHOTO_REQUIRED'; end if;
  insert into public.tg_teams(event_id,team_name,player_1,player_2,phone,photo_url,status,division,category,payment_status,pricing_tier,amount_due,paid_at)
  values(v_event.id,trim(p_team_name),v_c.display_name,v_p.display_name,v_phone,v_photo,'confirmed',p_division,v_cat,'paid','admin',0,now()) returning id into v_team_id;
  insert into public.tg_team_members(team_id,event_id,athlete_id,member_role,active) values(v_team_id,v_event.id,p_captain_id,'captain',true),(v_team_id,v_event.id,p_partner_id,'partner',true);
  return v_team_id;
end; $function$;

CREATE OR REPLACE FUNCTION private.arc_entry_action(p_action text, p_payload jsonb)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
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
   raise exception 'SHARED_CODE_ONLY';
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
     'captain_fee',coalesce(en.captain_fee,tm.amount_due/2,0),'partner_fee',coalesce(en.partner_fee,tm.amount_due-tm.amount_due/2,0),'legacy_entry',en.team_id is null,'is_captain',exists(select 1 from public.tg_team_members cm where cm.team_id=tm.id and cm.athlete_id=u and cm.member_role='captain' and cm.active),'player_1',tm.player_1,'player_2',tm.player_2,
     'roster_complete',(select count(*)=2 from public.tg_team_members m where m.team_id=tm.id and m.active),
     'partner_discount_name',(select ap.display_name from private.arc_entry_codes c join public.arc_profiles ap on ap.user_id=c.user_id where c.id=en.partner_code_id),
     'pending_invite',(select jsonb_build_object('id',i.id,'name',ap.display_name) from private.arc_entry_invites i join public.arc_profiles ap on ap.user_id=i.invitee_id where i.team_id=tm.id and i.status='pending'))
     from public.tg_teams tm left join private.arc_entries en on en.team_id=tm.id
     where tm.event_id=ev.id and tm.status in ('pending_payment','confirmed') and (en.captain_id=u or exists(select 1 from public.tg_team_members m where m.team_id=tm.id and m.athlete_id=u and m.active))
     order by tm.created_at desc limit 1),
   'invites',(select coalesce(jsonb_agg(jsonb_build_object('id',i.id,'team_name',tm.team_name,'division',tm.division,'category',tm.category,'captain',tm.player_1)),'[]'::jsonb)
     from private.arc_entry_invites i join public.tg_teams tm on tm.id=i.team_id where i.invitee_id=u and i.status='pending' and tm.status='confirmed'),
   'code',null,
   'registration_open',(private.arc_event_terms(ev.id)->>'registration_open')::boolean,
   'base_fee',(private.arc_event_terms(ev.id)->>'base_fee')::integer)
  into res;
  return res;
 elsif p_action='quote' then
  q:=private.arc_entry_quote(ev.id,coalesce(p_payload->>'discount_code',p_payload->>'captain_code'),p_payload->>'partner_code');
  return q-'captain_code_id'-'partner_code_id';
 elsif p_action='register' then
  if not (private.arc_event_terms(ev.id)->>'registration_open')::boolean then raise exception 'REGISTRATION_CLOSED'; end if;
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

  select count(*) into cnt from public.tg_teams where event_id=ev.id and (status='confirmed' or (status='pending_payment' and (payment_status='payment_check' or payment_deadline>now())));
  if cnt>=ev.max_teams then raise exception 'REGISTRATION_FULL'; end if;
  q:=private.arc_entry_quote(ev.id,coalesce(p_payload->>'discount_code',p_payload->>'captain_code'),p_payload->>'partner_code');
  if (q->>'amount_due')::integer is distinct from (p_payload->>'expected_amount')::integer then raise exception 'PRICE_CHANGED'; end if;
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

   if exists(select 1 from public.tg_team_members where event_id=ev.id and athlete_id=target and active) then raise exception 'PARTNER_ALREADY_REGISTERED'; end if;
   update private.arc_entry_invites set status='cancelled',responded_at=now() where team_id=tid and status='pending';
   insert into private.arc_entry_invites(team_id,invitee_id) values(tid,target);
   return '{}'::jsonb;
  else raise exception 'INVALID_ACTION'; end if;
 end if;
end; $function$;

CREATE OR REPLACE FUNCTION public.arc_admin_action(p_action text, p_payload jsonb DEFAULT '{}'::jsonb)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
declare u uuid:=auth.uid(); target uuid; res jsonb; nm text; nick text; ph text; gen text; why text;
 ev public.tg_events%rowtype; ca public.tg_athletes%rowtype; pa public.tg_athletes%rowtype;
 cid uuid; pid uuid; tid uuid; cat text; divn text; blocker text; lim integer; offst integer;
begin
 if u is null or not exists(select 1 from public.tg_admins where user_id=u) then raise exception 'ADMIN_ONLY'; end if;
 if p_action='accounts' then
  lim:=least(100,greatest(1,coalesce((p_payload->>'limit')::int,25))); offst:=greatest(0,coalesce((p_payload->>'offset')::int,0));
  with matches as (
   select au.id,au.email,ap.display_name as nickname,coalesce(a.display_name,pr.full_name,'') as full_name,
    a.gender,coalesce(p.phone,pr.phone,'') as phone,a.gym,a.instagram,au.created_at,au.last_sign_in_at,
    exists(select 1 from public.tg_admins where user_id=au.id) as is_admin,
    private.arc_delete_blocker(au.id) as delete_blocker,
    (select coalesce(jsonb_agg(jsonb_build_object('name',t.team_name,'event',e.slug,'active',m.active)),'[]') from public.tg_team_members m join public.tg_teams t on t.id=m.team_id join public.tg_events e on e.id=t.event_id where m.athlete_id=au.id) as teams
   from auth.users au left join public.arc_profiles ap on ap.user_id=au.id
   left join public.tg_athletes a on a.id=au.id left join public.tg_athlete_private p on p.athlete_id=au.id left join public.arc_account_private pr on pr.user_id=au.id
   where coalesce(p_payload->>'search','')='' or concat_ws(' ',au.email,ap.display_name,a.display_name,pr.full_name,p.phone,pr.phone) ilike '%'||(p_payload->>'search')||'%'
  ) select jsonb_build_object('total',(select count(*) from matches),'accounts',coalesce((select jsonb_agg(to_jsonb(x)) from(select * from matches order by created_at desc,id limit lim offset offst)x),'[]')) into res;
  return res;
 elsif p_action='teams' then
  select coalesce(jsonb_agg(to_jsonb(t)||jsonb_build_object('pending_invite',(select jsonb_build_object('id',i.id,'name',coalesce(a.display_name,ap.display_name,au.email)) from private.arc_entry_invites i join auth.users au on au.id=i.invitee_id left join public.arc_profiles ap on ap.user_id=au.id left join public.tg_athletes a on a.id=au.id where i.team_id=t.id and i.status='pending')) order by t.created_at),'[]') into res
  from public.tg_teams t join public.tg_events e on e.id=t.event_id where e.slug=p_payload->>'event_slug'; return res;
 elsif p_action='events' then
  select coalesce(jsonb_agg(jsonb_build_object('id',id,'slug',slug,'date',event_date) order by event_date desc),'[]') into res from public.tg_events; return res;
 elsif p_action='audit' then
  select coalesce(jsonb_agg(to_jsonb(x)),'[]') into res from(select action,reason,details,created_at,actor_id,target_id from private.arc_admin_audit order by id desc limit 30)x; return res;
 end if;
 why:=trim(coalesce(p_payload->>'reason',''));
 if length(why) not between 3 and 300 then raise exception 'REASON_REQUIRED'; end if;
 if p_action='save_profile' then
  target:=(p_payload->>'user_id')::uuid;
  perform 1 from auth.users where id=target for update; if not found then raise exception 'ACCOUNT_NOT_FOUND'; end if;
  nick:=trim(coalesce(p_payload->>'nickname','')); nm:=trim(coalesce(p_payload->>'full_name','')); gen:=coalesce(p_payload->>'gender',''); ph:=regexp_replace(coalesce(p_payload->>'phone',''),'[^0-9]','','g');
  if length(nick) not between 1 and 30 then raise exception 'NICKNAME_REQUIRED'; end if;
  if gen<>'' or exists(select 1 from public.tg_athletes where id=target) then
   if length(nm) not between 2 and 50 then raise exception 'NAME_REQUIRED'; end if;
   if gen not in ('male','female') then raise exception 'GENDER_REQUIRED'; end if;
   if length(ph) not between 10 and 11 then raise exception 'INVALID_PHONE'; end if;
   -- Lock athlete before checking category; joins use the same row lock.
   perform 1 from public.tg_athletes where id=target for update;
   if exists(select 1 from public.tg_team_members m join public.tg_teams t on t.id=m.team_id where m.athlete_id=target and m.active and
    ((t.category='MM' and gen<>'male') or (t.category='WW' and gen<>'female') or (t.category='MIXED' and exists(select 1 from public.tg_team_members pm join public.tg_athletes partner_profile on partner_profile.id=pm.athlete_id where pm.team_id=t.id and pm.active and pm.athlete_id<>target and partner_profile.gender=gen)))) then raise exception 'CATEGORY_GENDER_MISMATCH'; end if;
   insert into public.tg_athletes(id,display_name,handle,photo_url,gender,gym,instagram,profile_public)
   values(target,nm,'arc_'||substr(replace(target::text,'-',''),1,20),'https://arcstation.kr/favicon.png',gen,nullif(left(trim(p_payload->>'gym'),80),''),nullif(left(trim(p_payload->>'instagram'),80),''),false)
   on conflict(id) do update set display_name=excluded.display_name,gender=excluded.gender,gym=excluded.gym,instagram=excluded.instagram,updated_at=now();
   insert into public.tg_athlete_private(athlete_id,phone) values(target,ph) on conflict(athlete_id) do update set phone=excluded.phone,updated_at=now();
   update public.tg_teams t set player_1=case when m.member_role='captain' then nm else t.player_1 end,player_2=case when m.member_role='partner' then nm else t.player_2 end,phone=case when m.member_role='captain' then ph else t.phone end
   from public.tg_team_members m where m.team_id=t.id and m.athlete_id=target and m.active;
   update private.arc_entries set captain_gender=gen where captain_id=target;
  elsif nm<>'' or ph<>'' then
   if length(nm) not between 2 and 50 or length(ph) not between 10 and 11 then raise exception 'PROFILE_FIELDS_REQUIRED'; end if;
  end if;
  insert into public.arc_profiles(user_id,display_name) values(target,nick) on conflict(user_id) do update set display_name=excluded.display_name,updated_at=now();
  insert into public.tg_fan_profiles(user_id,display_name) values(target,nick) on conflict(user_id) do update set display_name=excluded.display_name,updated_at=now();
  -- Never create or backfill participant consent on behalf of a user.
  if nm<>'' and ph<>'' then update public.arc_account_private set full_name=nm,phone=ph,updated_at=now() where user_id=target; end if;
  insert into private.arc_admin_audit(actor_id,target_id,action,reason) values(u,target,p_action,why);
  return jsonb_build_object('saved',true);
 elsif p_action='add_team' then
  cid:=(p_payload->>'captain_id')::uuid; pid:=(p_payload->>'partner_id')::uuid; divn:=p_payload->>'division'; cat:=p_payload->>'category';
  if cid is null or pid is null or cid=pid then raise exception 'INVALID_PLAYERS'; end if;
  if coalesce(divn,'') not in ('OPEN','PRO') then raise exception 'INVALID_DIVISION'; end if;
  if coalesce(cat,'') not in ('MM','WW','MIXED') then raise exception 'INVALID_CATEGORY'; end if;
  if length(trim(coalesce(p_payload->>'team_name',''))) not between 1 and 60 then raise exception 'TEAM_NAME_REQUIRED'; end if;
  select * into ev from public.tg_events where slug=p_payload->>'event_slug'; if ev.id is null then raise exception 'EVENT_NOT_FOUND'; end if;
  perform pg_advisory_xact_lock(hashtextextended(ev.id::text,0));
  perform 1 from public.tg_athletes where id in(cid,pid) order by id for update;
  select * into ca from public.tg_athletes where id=cid; select * into pa from public.tg_athletes where id=pid;
  if ca.id is null or pa.id is null then raise exception 'PROFILE_FIELDS_REQUIRED'; end if;
  if cat<>(case when ca.gender='male' and pa.gender='male' then 'MM' when ca.gender='female' and pa.gender='female' then 'WW' else 'MIXED' end) then raise exception 'CATEGORY_GENDER_MISMATCH'; end if;
  select phone into ph from public.tg_athlete_private where athlete_id=cid; if ph is null or length(regexp_replace(ph,'[^0-9]','','g')) not between 10 and 11 then raise exception 'CAPTAIN_PHONE_REQUIRED'; end if;
  if exists(select 1 from public.tg_team_members where event_id=ev.id and athlete_id in(cid,pid) and active) then raise exception 'ATHLETE_ALREADY_LOCKED_IN'; end if;
  if (select count(*) from public.tg_teams where event_id=ev.id and (status='confirmed' or (status='pending_payment' and(payment_status='payment_check' or payment_deadline>now()))))>=ev.max_teams then raise exception 'REGISTRATION_FULL'; end if;

  insert into public.tg_teams(event_id,team_name,player_1,player_2,phone,photo_url,status,division,category,payment_status,pricing_tier,amount_due)
  values(ev.id,trim(p_payload->>'team_name'),ca.display_name,pa.display_name,ph,ca.photo_url,'confirmed',divn,cat,'paid','admin',0) returning id into tid;
  insert into public.tg_team_members(team_id,event_id,athlete_id,member_role) values(tid,ev.id,cid,'captain'),(tid,ev.id,pid,'partner');
  update private.arc_entry_invites set status='cancelled',responded_at=now() where invitee_id in(cid,pid) and status='pending' and team_id in(select id from public.tg_teams where event_id=ev.id);
  insert into private.arc_admin_audit(actor_id,target_id,action,reason,details) values(u,cid,p_action,why,jsonb_build_object('team_id',tid,'event_slug',ev.slug,'partner_id',pid,'amount_due',0));
  return jsonb_build_object('team_id',tid);
 elsif p_action='delete_check' then
  target:=(p_payload->>'user_id')::uuid;
  if target=u then raise exception 'CANNOT_DELETE_SELF'; end if;
  if not exists(select 1 from auth.users where id=target and lower(email)=lower(trim(p_payload->>'email'))) then raise exception 'EMAIL_CONFIRMATION_MISMATCH'; end if;
  blocker:=private.arc_delete_blocker(target); if blocker is not null then raise exception '%',blocker; end if;
  insert into private.arc_admin_audit(actor_id,target_id,action,reason) values(u,target,'delete_requested',why);
  return jsonb_build_object('allowed',true);
 end if;
 raise exception 'INVALID_ACTION';
end $function$;

CREATE OR REPLACE FUNCTION private.arc_entry_quote(p_event_id uuid, p_captain_code text, p_partner_code text)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
declare base integer; code text:=upper(trim(coalesce(nullif(trim(p_captain_code),''),nullif(trim(p_partner_code),''),''))); discounted boolean;
begin
 if auth.uid() is null then raise exception 'AUTH_REQUIRED'; end if;
 if code<>'' and code<>'NOLTO01' then raise exception 'INVALID_DISCOUNT_CODE'; end if;
 base:=(private.arc_event_terms(p_event_id)->>'base_fee')::integer;
 discounted:=code='NOLTO01';
 return jsonb_build_object('base_fee',base,'captain_fee',case when discounted then base/2 else base end,
 'partner_fee',case when discounted then base/2 else base end,'amount_due',case when discounted then base else base*2 end,
 'pricing_tier',case when base=20000 then 'early_bird' else 'regular' end,'discount_percent',case when discounted then 50 else 0 end,
 'captain_code_id',null,'partner_code_id',null);
end; $function$;
