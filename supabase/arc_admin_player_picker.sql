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
 elsif p_action='players' then
  select * into ev from public.tg_events where slug=p_payload->>'event_slug';
  if ev.id is null then raise exception 'EVENT_NOT_FOUND'; end if;
  select coalesce(jsonb_agg(to_jsonb(x) order by x.display_name,x.athlete_id),'[]'::jsonb) into res from (
   select au.id as athlete_id,au.email,
    coalesce(nullif(a.display_name,''),nullif(pr.full_name,''),nullif(ap.display_name,''),au.email,'ARC ACCOUNT') as display_name,
    a.handle,a.gym,a.gender,
    (a.id is null or a.gender not in ('male','female') or length(trim(a.display_name)) not between 2 and 50 or length(regexp_replace(coalesce(p.phone,''),'[^0-9]','','g')) not between 10 and 11) as needs_profile,
    exists(select 1 from public.tg_team_members m where m.event_id=ev.id and m.athlete_id=au.id and m.active) as locked_in
   from auth.users au left join public.arc_profiles ap on ap.user_id=au.id
   left join public.arc_account_private pr on pr.user_id=au.id
   left join public.tg_athletes a on a.id=au.id
   left join public.tg_athlete_private p on p.athlete_id=au.id
  ) x;
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
 if p_action='save_profile' then why:=null;
 elsif length(why) not between 3 and 300 then raise exception 'REASON_REQUIRED'; end if;
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
end $function$
;
