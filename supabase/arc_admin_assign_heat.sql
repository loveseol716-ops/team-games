begin;
grant update (heat_no,station_no) on public.tg_teams to authenticated;
create or replace function public.arc_admin_assign_heat(p_team uuid,p_heat integer,p_station integer,p_expected_target uuid default null)
returns void language plpgsql security invoker set search_path='' as $$
declare t public.tg_teams; target_id uuid; ev uuid;
begin
 if not coalesce(private.tg_is_admin(),false) then raise exception 'ADMIN_REQUIRED'; end if;
 if p_heat is null or p_heat<1 or p_heat>12 then raise exception 'INVALID_HEAT'; end if;
 if p_station is null or p_station not in (1,2) then raise exception 'INVALID_STATION'; end if;
 select event_id into ev from public.tg_teams where id=p_team and status='confirmed';
 if ev is null then raise exception 'CONFIRMED_TEAM_REQUIRED'; end if;
 perform pg_advisory_xact_lock(hashtextextended(ev::text,0));
 select * into t from public.tg_teams where id=p_team and status='confirmed' for update;
 if not found then raise exception 'CONFIRMED_TEAM_REQUIRED'; end if;
 select id into target_id from public.tg_teams where event_id=ev and status='confirmed' and heat_no=p_heat and station_no=p_station and id<>p_team for update;
 if target_id is distinct from p_expected_target then raise exception 'SLOT_CHANGED_REFRESH'; end if;
 if target_id is not null then
  update public.tg_teams set heat_no=null,station_no=null where id=p_team;
  update public.tg_teams set heat_no=t.heat_no,station_no=t.station_no where id=target_id;
 end if;
 update public.tg_teams set heat_no=p_heat,station_no=p_station where id=p_team;
end; $$;
revoke all on function public.arc_admin_assign_heat(uuid,integer,integer,uuid) from public,anon;
grant execute on function public.arc_admin_assign_heat(uuid,integer,integer,uuid) to authenticated;
notify pgrst,'reload schema';
commit;