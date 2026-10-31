-- Reset only drawing results; keep ticket registrations and privately retain previous draws.
alter table private.arc_raffle_draws
 add column if not exists reset_at timestamptz,
 add column if not exists reset_by uuid;
alter table private.arc_raffle_draws drop constraint if exists arc_raffle_draws_event_id_ticket_key;
create unique index if not exists arc_raffle_draws_active_ticket_key
 on private.arc_raffle_draws(event_id,ticket) where reset_at is null;

CREATE OR REPLACE FUNCTION private.arc_raffle_impl(p_slug text, p_action text, p_payload jsonb)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
declare
 c private.arc_raffle_config%rowtype;
 e private.arc_raffle_entries%rowtype;
 d private.arc_raffle_draws%rowtype;
 uid uuid:=auth.uid();
 adm boolean:=coalesce(private.tg_is_admin(),false);
 team uuid;
 reset_snapshot jsonb;
begin
 select r.* into c from private.arc_raffle_config r join public.tg_events v on v.id=r.event_id where v.slug=p_slug for update of r;
 if not found then raise exception 'EVENT_NOT_FOUND'; end if;
 if p_action not in ('board','join','admin','close','open','draw','claim','absent','reset') then raise exception 'INVALID_ACTION'; end if;
 if p_action not in ('board','join') and not adm then raise exception 'ADMIN_REQUIRED'; end if;
 if p_action='join' then
  if uid is null then raise exception 'AUTH_REQUIRED'; end if;
  if not c.is_open or now()>=c.closes_at then raise exception 'ENTRY_CLOSED'; end if;
  team:=(p_payload->>'team_id')::uuid;
  if not exists(select 1 from public.tg_teams t where t.id=team and t.event_id=c.event_id and t.status='confirmed') then raise exception 'INVALID_TEAM'; end if;
  select * into e from private.arc_raffle_entries where event_id=c.event_id and user_id=uid;
  if found then
   update private.arc_raffle_entries set team_id=team where id=e.id;
  else
   update private.arc_raffle_config set counter=counter+1 where event_id=c.event_id returning counter into c.counter;
   insert into private.arc_raffle_entries(event_id,user_id,team_id,ticket) values(c.event_id,uid,team,c.counter);
  end if;
 elsif p_action='close' then
  update private.arc_raffle_config set is_open=false where event_id=c.event_id;
 elsif p_action='open' then
  if exists(select 1 from private.arc_raffle_draws where event_id=c.event_id and reset_at is null) then raise exception 'DRAW_ALREADY_STARTED'; end if;
  if now()>=c.closes_at then raise exception 'ENTRY_CLOSED'; end if;
  update private.arc_raffle_config set is_open=true where event_id=c.event_id;
 elsif p_action='draw' then
  if (p_payload->>'request_id') is null then raise exception 'REQUEST_ID_REQUIRED'; end if;
  select * into d from private.arc_raffle_draws where request_id=(p_payload->>'request_id')::uuid;
  if found then
   if d.event_id<>c.event_id then raise exception 'INVALID_REQUEST'; end if;
   if d.reset_at is not null then raise exception 'DRAW_RESET'; end if;
   return to_jsonb(d)-'drawn_by'-'entry_id'-'request_id'-'reset_at'-'reset_by';
  end if;
  if c.is_open and now()<c.closes_at then raise exception 'CLOSE_ENTRIES_FIRST'; end if;
  if exists(select 1 from private.arc_raffle_draws where event_id=c.event_id and reset_at is null and status='pending') then raise exception 'RESOLVE_PREVIOUS_DRAW'; end if;
  select x.* into e from private.arc_raffle_entries x where x.event_id=c.event_id and not exists(select 1 from private.arc_raffle_draws y where y.event_id=c.event_id and y.ticket=x.ticket and y.reset_at is null) order by random() limit 1;
  if not found then raise exception 'NO_ELIGIBLE_ENTRIES'; end if;
  update private.arc_raffle_config set is_open=false where event_id=c.event_id;
  insert into private.arc_raffle_draws(event_id,entry_id,ticket,request_id,drawn_by) values(c.event_id,e.id,e.ticket,(p_payload->>'request_id')::uuid,uid) returning * into d;
  return to_jsonb(d)-'drawn_by'-'entry_id'-'request_id'-'reset_at'-'reset_by';
 elsif p_action='reset' then
  if uid is null then raise exception 'AUTH_REQUIRED'; end if;
  if p_payload->>'confirm_reset' is distinct from 'true' then raise exception 'RESET_CONFIRMATION_REQUIRED'; end if;
  select coalesce(jsonb_agg(jsonb_build_object('id',x.id,'status',x.status) order by x.id),'[]'::jsonb)
   into reset_snapshot from private.arc_raffle_draws x where x.event_id=c.event_id and x.reset_at is null;
  if p_payload->'expected_draws' is distinct from reset_snapshot then raise exception 'RAFFLE_CHANGED'; end if;
  -- Archive active results. Entries, ticket numbers, support choices and entry controls stay intact.
  update private.arc_raffle_draws set reset_at=clock_timestamp(),reset_by=uid
   where event_id=c.event_id and reset_at is null;
 elsif p_action in ('claim','absent') then
  select * into d from private.arc_raffle_draws where id=(p_payload->>'draw_id')::uuid and event_id=c.event_id and reset_at is null for update;
  if not found then raise exception 'DRAW_NOT_FOUND'; end if;
  if d.status<>'pending' then raise exception 'DRAW_ALREADY_RESOLVED'; end if;
  if p_action='absent' and now()<d.created_at+interval '60 seconds' then raise exception 'WAIT_60_SECONDS'; end if;
  update private.arc_raffle_draws set status=case when p_action='claim' then 'claimed' else 'absent' end,resolved_at=now() where id=d.id;
 end if;
 return jsonb_build_object(
 'server_time',now(),
 'is_open',(select is_open and now()<closes_at from private.arc_raffle_config where event_id=c.event_id),
 'closes_at',c.closes_at,
 'total',(select count(*) from private.arc_raffle_entries where event_id=c.event_id),
 'mine',(select jsonb_build_object('ticket',x.ticket,'team_id',x.team_id,'team_name',t.team_name) from private.arc_raffle_entries x join public.tg_teams t on t.id=x.team_id where x.event_id=c.event_id and x.user_id=uid),
 'teams',coalesce((select jsonb_agg(jsonb_build_object('id',t.id,'name',t.team_name,'division',t.division,'category',t.category,
 'players',coalesce((select jsonb_agg(coalesce(nullif(btrim(f.display_name),''),nullif(btrim(a.display_name),''),nullif(btrim(a.handle),''),'NAME PENDING') order by case when m.member_role='captain' then 0 else 1 end,m.created_at) from public.tg_team_members m join public.tg_athletes a on a.id=m.athlete_id left join public.tg_fan_profiles f on f.user_id=m.athlete_id where m.team_id=t.id and m.active),jsonb_build_array(nullif(t.player_1,''),case when t.player_2='팀원 초대 예정' then null else nullif(t.player_2,'') end)),
 'support_count',(select count(*) from private.arc_raffle_entries r where r.event_id=c.event_id and r.team_id=t.id),
 'is_my_team',exists(select 1 from public.tg_team_members m where m.team_id=t.id and m.athlete_id=uid and m.active)) order by t.team_name) from public.tg_teams t where t.event_id=c.event_id and t.status='confirmed'),'[]'::jsonb),
 'draws',coalesce((select jsonb_agg(jsonb_build_object('id',x.id,'ticket',x.ticket,'status',x.status,'created_at',x.created_at) order by x.created_at desc) from private.arc_raffle_draws x where x.event_id=c.event_id and x.reset_at is null),'[]'::jsonb),
 'entries',case when p_action='admin' and adm then coalesce((select jsonb_agg(jsonb_build_object('ticket',x.ticket,'name',coalesce(a.display_name,f.display_name,'MEMBER'),'team',t.team_name) order by x.ticket) from private.arc_raffle_entries x left join public.tg_athletes a on a.id=x.user_id left join public.tg_fan_profiles f on f.user_id=x.user_id join public.tg_teams t on t.id=x.team_id where x.event_id=c.event_id),'[]'::jsonb) else null end);
end $function$
;
notify pgrst,'reload schema';

