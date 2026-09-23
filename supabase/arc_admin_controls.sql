-- ARC STATION only. Staff operations use database-verified administrator roles.
create table if not exists private.arc_admin_audit (
 id bigint generated always as identity primary key,
 actor_id uuid, target_id uuid, action text not null, reason text,
 details jsonb not null default '{}'::jsonb, created_at timestamptz not null default now()
);
alter table private.arc_admin_audit enable row level security;
revoke all on private.arc_admin_audit from public, anon, authenticated;
alter table private.arc_entry_invites add column if not exists confirmed_by uuid;
alter table private.arc_entry_invites add column if not exists confirmation_method text;

create or replace function public.arc_confirm_partner(p_invite_id uuid)
returns jsonb language plpgsql security definer set search_path='' as $$
declare i private.arc_entry_invites%rowtype; t public.tg_teams%rowtype;
 a public.tg_athletes%rowtype; c public.tg_athletes%rowtype; ev public.tg_events%rowtype;
begin
 if auth.uid() is null then raise exception 'AUTH_REQUIRED'; end if;
 select * into i from private.arc_entry_invites where id=p_invite_id;
 if i.id is null then raise exception 'INVITE_NOT_FOUND'; end if;
 select * into t from public.tg_teams where id=i.team_id;
 if not exists(select 1 from public.tg_team_members where team_id=t.id and athlete_id=auth.uid() and active and member_role='captain') then raise exception 'CAPTAIN_ONLY'; end if;
 perform pg_advisory_xact_lock(hashtextextended(t.event_id::text,0));
 select * into i from private.arc_entry_invites where id=p_invite_id for update;
 select * into t from public.tg_teams where id=i.team_id for update;
 if i.status<>'pending' then raise exception 'INVITE_NOT_PENDING'; end if;
 if t.status<>'confirmed' or t.payment_status is distinct from 'paid' then raise exception 'PAYMENT_NOT_CONFIRMED'; end if;
 select * into ev from public.tg_events where id=t.event_id;
 if now()>=ev.event_date then raise exception 'REGISTRATION_CLOSED'; end if;
 select * into a from public.tg_athletes where id=i.invitee_id for update;
 select ca.* into c from public.tg_athletes ca join public.tg_team_members m on m.athlete_id=ca.id where m.team_id=t.id and m.active and m.member_role='captain';
 if a.id is null or not exists(select 1 from public.tg_athlete_private where athlete_id=a.id and length(regexp_replace(phone,'[^0-9]','','g')) between 10 and 11) then raise exception 'PARTNER_PROFILE_REQUIRED'; end if;
 if exists(select 1 from public.tg_team_members where event_id=t.event_id and athlete_id=a.id and active) then raise exception 'PARTNER_ALREADY_REGISTERED'; end if;
 if (select count(*) from public.tg_team_members where team_id=t.id and active)>=2 then raise exception 'TEAM_FULL'; end if;
 if t.category not in ('MM','WW','MIXED') or t.category is null then raise exception 'INVALID_CATEGORY'; end if;
 if (t.category='MM' and a.gender<>'male') or (t.category='WW' and a.gender<>'female') or (t.category='MIXED' and a.gender=c.gender) then raise exception 'CATEGORY_GENDER_MISMATCH'; end if;
 insert into public.tg_team_members(team_id,event_id,athlete_id,member_role) values(t.id,t.event_id,a.id,'partner')
 on conflict(team_id,athlete_id) do update set active=true,member_role='partner';
 update public.tg_teams set player_2=a.display_name where id=t.id;
 update private.arc_entry_invites set status='accepted',responded_at=now(),confirmed_by=auth.uid(),confirmation_method='captain' where id=i.id;
 update private.arc_entry_invites set status='cancelled',responded_at=now() where invitee_id=a.id and status='pending' and team_id in(select id from public.tg_teams where event_id=t.event_id);
 insert into private.arc_admin_audit(actor_id,target_id,action,details) values(auth.uid(),a.id,'captain_confirm_partner',jsonb_build_object('team_id',t.id,'invite_id',i.id));
 return jsonb_build_object('team_id',t.id,'partner',a.display_name);
end $$;

create or replace function private.arc_delete_blocker(p_user uuid)
returns text language sql stable security definer set search_path='' as $$
 select case
 when exists(select 1 from public.tg_admins where user_id=p_user) then 'ADMIN_ACCOUNT_PROTECTED'
 when exists(select 1 from public.tg_team_members where athlete_id=p_user) or exists(select 1 from private.arc_entries where captain_id=p_user) then 'ACCOUNT_HAS_TEAM_HISTORY'
 when exists(select 1 from public.tg_prediction_bets where user_id=p_user) or exists(select 1 from public.tg_fan_point_ledger where user_id=p_user and kind<>'signup_bonus') then 'ACCOUNT_HAS_POINT_HISTORY'
 when exists(select 1 from private.arc_entry_codes where issued_by=p_user) then 'ACCOUNT_HAS_ADMIN_HISTORY'
 else null end;
$$;

create or replace function public.arc_admin_action(p_action text,p_payload jsonb default '{}'::jsonb)
returns jsonb language plpgsql security definer set search_path='' as $$
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
  if (select count(*) from public.tg_teams where event_id=ev.id and division=divn and category=cat and(status='confirmed' or(status='pending_payment' and(payment_status='payment_check' or payment_deadline>now()))))>=4 then raise exception 'CATEGORY_FULL'; end if;
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
end $$;

-- Check again inside the Auth deletion transaction, before cascading records.
create or replace function private.arc_protect_account_history()
returns trigger language plpgsql security definer set search_path='' as $$
declare blocker text; audit_row private.arc_admin_audit%rowtype;
begin
 blocker:=private.arc_delete_blocker(old.id); if blocker is not null then raise exception '%',blocker; end if;
 select * into audit_row from private.arc_admin_audit where target_id=old.id and action='delete_requested' and created_at>now()-interval '5 minutes' order by id desc limit 1;
 insert into private.arc_admin_audit(actor_id,target_id,action,reason) values(audit_row.actor_id,old.id,'delete_account',audit_row.reason);
 return old;
end $$;
drop trigger if exists arc_protect_account_history on auth.users;
create trigger arc_protect_account_history before delete on auth.users for each row execute function private.arc_protect_account_history();

revoke all on function private.arc_delete_blocker(uuid), private.arc_protect_account_history() from public,anon,authenticated;
revoke all on function public.arc_admin_action(text,jsonb),public.arc_confirm_partner(uuid) from public,anon;
grant execute on function public.arc_admin_action(text,jsonb),public.arc_confirm_partner(uuid) to authenticated;
