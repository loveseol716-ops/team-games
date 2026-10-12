begin;
-- Heat columns cannot be fetched through the public team listing.
revoke select on public.tg_teams from public,anon,authenticated;
revoke select(heat_no,station_no) on public.tg_teams from public,anon,authenticated;
do $$ declare cols text; definition text; begin
 select string_agg(quote_ident(column_name),',') into cols from information_schema.columns where table_schema='public' and table_name='tg_teams' and column_name not in ('heat_no','station_no');
 execute 'grant select('||cols||') on public.tg_teams to anon,authenticated';
 -- Retain the explicit admin check in a non-exposed privileged implementation.
 select pg_get_functiondef('public.arc_admin_assign_heat(uuid,integer,integer,uuid)'::regprocedure) into definition;
 definition:=replace(definition,'FUNCTION public.arc_admin_assign_heat','FUNCTION private.arc_admin_assign_heat');
 definition:=replace(definition,'LANGUAGE plpgsql','LANGUAGE plpgsql SECURITY DEFINER');
 execute definition;
end $$;
revoke all on function private.arc_admin_assign_heat(uuid,integer,integer,uuid) from public,anon;
grant execute on function private.arc_admin_assign_heat(uuid,integer,integer,uuid) to authenticated;
create or replace function public.arc_admin_assign_heat(p_team uuid,p_heat integer,p_station integer,p_expected_target uuid default null)
returns void language sql security invoker set search_path='' as $$ select private.arc_admin_assign_heat(p_team,p_heat,p_station,p_expected_target); $$;

create or replace function private.arc_my_heat(p_event_slug text)
returns jsonb language plpgsql security definer set search_path='' as $$
declare t public.tg_teams; start_at timestamptz;
begin
 if auth.uid() is null then raise exception 'AUTH_REQUIRED'; end if;
 select tm.* into t from public.tg_teams tm join public.tg_events e on e.id=tm.event_id
 where e.slug=p_event_slug and tm.status='confirmed'
 and exists(select 1 from public.tg_team_members m where m.team_id=tm.id and m.active and m.athlete_id=auth.uid())
 limit 1;
 if t.id is null then return jsonb_build_object('status','no_team'); end if;
 if (select count(*) from public.tg_team_members m where m.team_id=t.id and m.active)<>2
 or not exists(select 1 from public.tg_team_members m where m.team_id=t.id and m.active and m.member_role='partner')
 then return jsonb_build_object('status','partner_needed'); end if;
 if t.heat_no is null or t.station_no is null then return jsonb_build_object('status','unassigned'); end if;
 select event_date+make_interval(mins=>(t.heat_no-1)*13) into start_at from public.tg_events where id=t.event_id;
 return jsonb_build_object('status','ready','team_id',t.id,'team_name',t.team_name,'heat',t.heat_no,'lane',t.station_no,'starts_at',start_at,'ends_at',start_at+interval '8 minutes');
end $$;
revoke all on function private.arc_my_heat(text) from public,anon;
grant execute on function private.arc_my_heat(text) to authenticated;
create or replace function public.arc_my_heat(p_event_slug text)
returns jsonb language sql security invoker set search_path='' as $$ select private.arc_my_heat(p_event_slug); $$;
revoke all on function public.arc_my_heat(text) from public,anon;
grant execute on function public.arc_my_heat(text) to authenticated;
notify pgrst,'reload schema';
commit;