-- NOLTO 2026: open free predictions and increase participant season points.
begin;
update public.tg_prediction_markets m set lock_at=e.event_date
from public.tg_events e where e.id=m.event_id and e.slug='team-games-001' and m.status='open';
update public.tg_events set picks_open=true where slug='team-games-001';
insert into public.tg_point_rules(season_id,place,points)
select e.season_id,n,case n when 1 then 3000 when 2 then 2000 when 3 then 1500 else case when n<=8 then 1000 else 500 end end
from public.tg_events e cross join generate_series(1,24) n
where e.slug='team-games-001'
on conflict(season_id,place) do update set points=excluded.points;

-- Result corrections replace earned season points instead of awarding twice.
-- Only active members of a confirmed team receive points; PLAY POINT is separate.
create or replace function private.tg_sync_athlete_points()
returns trigger language plpgsql security definer set search_path='' as $$
declare v_points integer;
begin
 delete from public.tg_athlete_points where event_id=new.event_id and team_id=new.team_id;
 if new.rank is null or new.status not in ('Finished','Time Cap') then return new; end if;
 if not exists(select 1 from public.tg_teams where id=new.team_id and event_id=new.event_id and status='confirmed') then return new; end if;
 select pr.points into v_points from public.tg_events e
 join public.tg_point_rules pr on pr.season_id=e.season_id and pr.place=new.rank where e.id=new.event_id;
 insert into public.tg_athlete_points(athlete_id,event_id,team_id,place,points,updated_at)
 select tm.athlete_id,new.event_id,new.team_id,new.rank,coalesce(v_points,0),now()
 from public.tg_team_members tm where tm.team_id=new.team_id and tm.event_id=new.event_id and tm.active
 on conflict(athlete_id,event_id) do update set team_id=excluded.team_id,place=excluded.place,points=excluded.points,updated_at=now();
 return new;
end $$;
revoke all on function private.tg_sync_athlete_points() from public,anon,authenticated;
commit;
