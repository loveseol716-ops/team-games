create or replace function private.arc_entry_quote(p_event_id uuid,p_captain_code text,p_partner_code text)
returns jsonb language plpgsql security definer set search_path='' as $$
declare base integer; code text:=upper(trim(coalesce(nullif(trim(p_captain_code),''),nullif(trim(p_partner_code),''),''))); discounted boolean;
begin
 if auth.uid() is null then raise exception 'AUTH_REQUIRED'; end if;
 if code<>'' and code<>'NOLTO01' then raise exception 'INVALID_DISCOUNT_CODE'; end if;
 base:=case when now()<timestamptz '2026-10-11 00:00:00+09' then 20000 else 25000 end;
 discounted:=code='NOLTO01';
 return jsonb_build_object('base_fee',base,'captain_fee',case when discounted then base/2 else base end,
 'partner_fee',case when discounted then base/2 else base end,'amount_due',case when discounted then base else base*2 end,
 'pricing_tier',case when base=20000 then 'early_bird' else 'regular' end,'discount_percent',case when discounted then 50 else 0 end,
 'captain_code_id',null,'partner_code_id',null);
end; $$;
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
     'captain_fee',en.captain_fee,'partner_fee',en.partner_fee,'is_captain',en.captain_id=u,'player_1',tm.player_1,'player_2',tm.player_2,
     'roster_complete',(select count(*)=2 from public.tg_team_members m where m.team_id=tm.id and m.active),
     'partner_discount_name',(select ap.display_name from private.arc_entry_codes c join public.arc_profiles ap on ap.user_id=c.user_id where c.id=en.partner_code_id),
     'pending_invite',(select jsonb_build_object('id',i.id,'name',ap.display_name) from private.arc_entry_invites i join public.arc_profiles ap on ap.user_id=i.invitee_id where i.team_id=tm.id and i.status='pending'))
     from private.arc_entries en join public.tg_teams tm on tm.id=en.team_id
     where tm.event_id=ev.id and tm.status in ('pending_payment','confirmed') and (en.captain_id=u or exists(select 1 from public.tg_team_members m where m.team_id=tm.id and m.athlete_id=u and m.active))
     order by tm.created_at desc limit 1),
   'invites',(select coalesce(jsonb_agg(jsonb_build_object('id',i.id,'team_name',tm.team_name,'division',tm.division,'category',tm.category,'captain',tm.player_1)),'[]'::jsonb)
     from private.arc_entry_invites i join public.tg_teams tm on tm.id=i.team_id where i.invitee_id=u and i.status='pending' and tm.status='confirmed'),
   'code',null,
   'registration_open',ev.registration_open and now()<ev.event_date,
   'base_fee',case when now()<timestamptz '2026-10-11 00:00:00+09' then 20000 else 25000 end)
  into res;
  return res;
 elsif p_action='quote' then
  q:=private.arc_entry_quote(ev.id,coalesce(p_payload->>'discount_code',p_payload->>'captain_code'),p_payload->>'partner_code');
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