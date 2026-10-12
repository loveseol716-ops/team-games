begin;
-- Grant only the column this invoker RPC changes; existing admin RLS still applies.
grant update (division) on public.tg_teams to authenticated;
create or replace function public.arc_admin_change_division(p_team uuid,p_division text)
returns void language plpgsql security invoker set search_path='' as $$
declare p_event uuid;
begin
 if not coalesce(private.tg_is_admin(),false) then raise exception 'ADMIN_REQUIRED'; end if;
 if p_division is null or p_division not in ('OPEN','PRO') then raise exception 'INVALID_DIVISION'; end if;
 select event_id into p_event from public.tg_teams where id=p_team;
 if p_event is null then raise exception 'TEAM_NOT_FOUND'; end if;
 perform pg_advisory_xact_lock(hashtextextended(p_event::text,0));
 update public.tg_teams set division=p_division where id=p_team;
 if not found then raise exception 'TEAM_NOT_FOUND'; end if;
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
revoke all on function public.arc_admin_change_division(uuid,text) from public,anon;
grant execute on function public.arc_admin_change_division(uuid,text) to authenticated;
notify pgrst,'reload schema';
commit;
