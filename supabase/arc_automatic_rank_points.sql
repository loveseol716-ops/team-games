begin;
create or replace function public.arc_save_workout(p_event uuid,p_team uuid,p_workout text,p_seconds numeric default null,p_reps integer default null,p_meters integer default null)
returns void language plpgsql security invoker set search_path='' as $$
begin
 if not coalesce(private.tg_is_admin(),false) then raise exception 'ADMIN_REQUIRED'; end if;
 if not exists(select 1 from public.tg_teams where id=p_team and event_id=p_event and status='confirmed') then raise exception 'CONFIRMED_TEAM_REQUIRED'; end if;
 perform pg_advisory_xact_lock(hashtextextended(p_event::text,0));
 if p_workout='a' then
  if p_reps is null or p_reps<0 or p_reps>168 or (p_reps=168 and (p_seconds is null or p_seconds<=0 or p_seconds>480)) or (p_reps<168 and p_seconds is not null) then raise exception 'INVALID_A_RESULT'; end if;
  insert into public.tg_results(event_id,team_id,workout_a_seconds,workout_a_reps,status) values(p_event,p_team,p_seconds,p_reps,'Running')
  on conflict(event_id,team_id) do update set workout_a_seconds=excluded.workout_a_seconds,workout_a_reps=excluded.workout_a_reps,rank=null,workout_a_rank=null,workout_b_rank=null,workout_a_points=null,workout_b_points=null;
 elsif p_workout='b' then
  if p_meters is null or p_meters<0 or p_meters>100000 then raise exception 'INVALID_B_RESULT'; end if;
  insert into public.tg_results(event_id,team_id,workout_b_meters,status) values(p_event,p_team,p_meters,'Running')
  on conflict(event_id,team_id) do update set workout_b_meters=excluded.workout_b_meters,workout_b_seconds=null,rank=null,workout_a_rank=null,workout_b_rank=null,workout_a_points=null,workout_b_points=null;
 else raise exception 'INVALID_WORKOUT'; end if;
 update public.tg_results set status=case when workout_a_reps is null or workout_b_meters is null then 'Running' when workout_a_reps=168 then 'Finished' else 'Time Cap' end,updated_at=now() where event_id=p_event and team_id=p_team;

 -- Re-rank every recorded team in its own division/category, atomically.
 with workout_ranks as (
  select r.id,r.workout_a_reps,r.workout_b_meters,t.division,t.category,
   case when r.workout_a_reps is not null then rank() over(partition by t.division,t.category order by (r.workout_a_seconds is null),r.workout_a_seconds asc nulls last,r.workout_a_reps desc nulls last) end as ar,
   case when r.workout_b_meters is not null then rank() over(partition by t.division,t.category order by r.workout_b_meters desc nulls last) end as br
  from public.tg_results r join public.tg_teams t on t.id=r.team_id and t.event_id=r.event_id
  where r.event_id=p_event and t.status='confirmed'
 ), standings as (
  select *,case when ar is not null and br is not null then rank() over(partition by division,category order by (ar+br) asc nulls last,ar asc nulls last) end as final_rank
  from workout_ranks
 )
 update public.tg_results r set workout_a_rank=s.ar,workout_b_rank=s.br,workout_a_points=s.ar,workout_b_points=s.br,rank=s.final_rank,updated_at=now()
 from standings s where r.id=s.id and
 (r.workout_a_rank,r.workout_b_rank,r.workout_a_points,r.workout_b_points,r.rank) is distinct from (s.ar,s.br,s.ar,s.br,s.final_rank);
end; $$;
revoke all on function public.arc_save_workout(uuid,uuid,text,numeric,integer,integer) from public,anon;
grant execute on function public.arc_save_workout(uuid,uuid,text,numeric,integer,integer) to authenticated;

notify pgrst,'reload schema';
commit;
