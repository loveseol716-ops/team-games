create table private.arc_raffle_config (
 event_id uuid primary key references public.tg_events(id),
 is_open boolean not null default true,
 closes_at timestamptz not null,
 counter integer not null default 0
);
create table private.arc_raffle_entries (
 id uuid primary key default gen_random_uuid(),
 event_id uuid not null references private.arc_raffle_config(event_id),
 user_id uuid not null references auth.users(id) on delete cascade,
 team_id uuid not null references public.tg_teams(id),
 ticket integer not null check(ticket>0),
 created_at timestamptz not null default now(),
 unique(event_id,user_id),unique(event_id,ticket)
);
create table private.arc_raffle_draws (
 id uuid primary key default gen_random_uuid(),
 event_id uuid not null references private.arc_raffle_config(event_id),
 entry_id uuid references private.arc_raffle_entries(id) on delete set null,
 ticket integer not null,
 request_id uuid not null unique,
 status text not null default 'pending' check(status in ('pending','claimed','absent')),
 drawn_by uuid not null,
 created_at timestamptz not null default now(),
 resolved_at timestamptz,
 unique(event_id,ticket)
);
alter table private.arc_raffle_config enable row level security;
alter table private.arc_raffle_entries enable row level security;
alter table private.arc_raffle_draws enable row level security;
revoke all on private.arc_raffle_config,private.arc_raffle_entries,private.arc_raffle_draws from public,anon,authenticated;
insert into private.arc_raffle_config(event_id,closes_at)
select id,'2026-10-31 12:23:00+09' from public.tg_events where slug='team-games-001';

create function private.arc_raffle_impl(p_slug text,p_action text,p_payload jsonb)
returns jsonb language plpgsql security definer set search_path='' as $$
declare
 c private.arc_raffle_config%rowtype;
 e private.arc_raffle_entries%rowtype;
 d private.arc_raffle_draws%rowtype;
 uid uuid:=auth.uid();
 adm boolean:=coalesce(private.tg_is_admin(),false);
 team uuid;
begin
 select r.* into c from private.arc_raffle_config r join public.tg_events v on v.id=r.event_id where v.slug=p_slug for update of r;
 if not found then raise exception 'EVENT_NOT_FOUND'; end if;
 if p_action not in ('board','join','admin','close','open','draw','claim','absent') then raise exception 'INVALID_ACTION'; end if;
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
  if exists(select 1 from private.arc_raffle_draws where event_id=c.event_id) then raise exception 'DRAW_ALREADY_STARTED'; end if;
  if now()>=c.closes_at then raise exception 'ENTRY_CLOSED'; end if;
  update private.arc_raffle_config set is_open=true where event_id=c.event_id;
 elsif p_action='draw' then
  if (p_payload->>'request_id') is null then raise exception 'REQUEST_ID_REQUIRED'; end if;
  select * into d from private.arc_raffle_draws where request_id=(p_payload->>'request_id')::uuid;
  if found then
   if d.event_id<>c.event_id then raise exception 'INVALID_REQUEST'; end if;
   return to_jsonb(d)-'drawn_by'-'entry_id'-'request_id';
  end if;
  if c.is_open and now()<c.closes_at then raise exception 'CLOSE_ENTRIES_FIRST'; end if;
  if exists(select 1 from private.arc_raffle_draws where event_id=c.event_id and status='pending') then raise exception 'RESOLVE_PREVIOUS_DRAW'; end if;
  select x.* into e from private.arc_raffle_entries x where x.event_id=c.event_id and not exists(select 1 from private.arc_raffle_draws y where y.event_id=c.event_id and y.ticket=x.ticket) order by random() limit 1;
  if not found then raise exception 'NO_ELIGIBLE_ENTRIES'; end if;
  update private.arc_raffle_config set is_open=false where event_id=c.event_id;
  insert into private.arc_raffle_draws(event_id,entry_id,ticket,request_id,drawn_by) values(c.event_id,e.id,e.ticket,(p_payload->>'request_id')::uuid,uid) returning * into d;
  return to_jsonb(d)-'drawn_by'-'entry_id'-'request_id';
 elsif p_action in ('claim','absent') then
  select * into d from private.arc_raffle_draws where id=(p_payload->>'draw_id')::uuid and event_id=c.event_id for update;
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
 'teams',coalesce((select jsonb_agg(jsonb_build_object('id',t.id,'name',t.team_name,'division',t.division,'category',t.category) order by t.team_name) from public.tg_teams t where t.event_id=c.event_id and t.status='confirmed'),'[]'::jsonb),
 'draws',coalesce((select jsonb_agg(jsonb_build_object('id',x.id,'ticket',x.ticket,'status',x.status,'created_at',x.created_at) order by x.created_at desc) from private.arc_raffle_draws x where x.event_id=c.event_id),'[]'::jsonb),
 'entries',case when p_action='admin' and adm then coalesce((select jsonb_agg(jsonb_build_object('ticket',x.ticket,'name',coalesce(a.display_name,f.display_name,'MEMBER'),'team',t.team_name) order by x.ticket) from private.arc_raffle_entries x left join public.tg_athletes a on a.id=x.user_id left join public.tg_fan_profiles f on f.user_id=x.user_id join public.tg_teams t on t.id=x.team_id where x.event_id=c.event_id),'[]'::jsonb) else null end);
end $$;
revoke all on function private.arc_raffle_impl(text,text,jsonb) from public;

create function public.arc_raffle(p_slug text,p_action text default 'board',p_payload jsonb default '{}') returns jsonb language sql security definer set search_path='' as $$select private.arc_raffle_impl(p_slug,p_action,p_payload)$$;
revoke all on function public.arc_raffle(text,text,jsonb) from public;
grant execute on function public.arc_raffle(text,text,jsonb) to anon,authenticated;
-- Preserve old ledgers, but disable staking for this edition.
update public.tg_events set picks_open=false where slug='team-games-001';
update public.tg_prediction_markets set status='locked' where event_id in(select id from public.tg_events where slug='team-games-001') and status='open';
notify pgrst,'reload schema';
