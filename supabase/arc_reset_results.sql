begin;
create or replace function public.arc_reset_results(p_event uuid,p_team uuid default null)
returns integer language plpgsql security invoker set search_path='' as $$
declare affected integer;
begin
 if not coalesce(private.tg_is_admin(),false) then raise exception 'ADMIN_REQUIRED'; end if;
 perform pg_advisory_xact_lock(hashtextextended(p_event::text,0));
 update public.tg_results set workout_a_seconds=null,workout_a_reps=null,workout_b_seconds=null,workout_b_meters=null,
 workout_a_rank=null,workout_b_rank=null,workout_a_points=null,workout_b_points=null,rank=null,
 finish_seconds=null,reps_completed=null,status='Not Started',updated_at=now()
 where event_id=p_event and (p_team is null or team_id=p_team);
 get diagnostics affected=row_count;
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

 return affected;
end; $$;
revoke all on function public.arc_reset_results(uuid,uuid) from public,anon;
grant execute on function public.arc_reset_results(uuid,uuid) to authenticated;
notify pgrst,'reload schema';
commit;
