begin;
alter table public.tg_results
 add column if not exists workout_a_reps integer check (workout_a_reps between 0 and 168),
 add column if not exists workout_b_meters integer check (workout_b_meters between 0 and 100000);
alter table public.tg_results add constraint arc_a_result_consistent check (
 (workout_a_seconds is null and (workout_a_reps is null or workout_a_reps < 168)) or
 (workout_a_seconds > 0 and workout_a_seconds <= 480 and workout_a_reps is not null and workout_a_reps = 168));
create or replace function public.arc_save_workout(p_event uuid,p_team uuid,p_workout text,p_seconds numeric default null,p_reps integer default null,p_meters integer default null)
returns void language plpgsql security invoker set search_path='' as $$
begin
 if not coalesce(private.tg_is_admin(),false) then raise exception 'ADMIN_REQUIRED'; end if;
 if not exists(select 1 from public.tg_teams where id=p_team and event_id=p_event and status='confirmed') then raise exception 'CONFIRMED_TEAM_REQUIRED'; end if;
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
end; $$;
revoke all on function public.arc_save_workout(uuid,uuid,text,numeric,integer,integer) from public,anon;
grant execute on function public.arc_save_workout(uuid,uuid,text,numeric,integer,integer) to authenticated;
-- An administrator's saved result is public immediately, including partial A/B records.
alter policy tg_results_public_read on public.tg_results using (workout_a_reps is not null or workout_b_meters is not null);
do $$ begin
 if not exists(select 1 from pg_publication_tables where pubname='supabase_realtime' and schemaname='public' and tablename='tg_results') then
 alter publication supabase_realtime add table public.tg_results;
 end if;
end $$;
notify pgrst,'reload schema';
commit;
