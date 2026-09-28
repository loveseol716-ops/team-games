begin;
create or replace function private.arc_admin_rosters(p_event_slug text)
returns jsonb language plpgsql security definer set search_path='' as $$
begin
 if auth.uid() is null or not exists(select 1 from public.tg_admins where user_id=auth.uid()) then raise exception 'ADMIN_ONLY'; end if;
 return (select coalesce(jsonb_agg(jsonb_build_object('team_id',t.id,
 'member_count',(select count(*) from public.tg_team_members m where m.team_id=t.id and m.active),
 'captain_id',(select m.athlete_id from public.tg_team_members m where m.team_id=t.id and m.active and m.member_role='captain' limit 1),
 'partner_id',(select m.athlete_id from public.tg_team_members m where m.team_id=t.id and m.active and m.member_role='partner' limit 1),
 'pending_player_id',(select i.invitee_id from private.arc_entry_invites i where i.team_id=t.id and i.status='pending' limit 1))),'[]'::jsonb)
 from public.tg_teams t join public.tg_events e on e.id=t.event_id where e.slug=p_event_slug);
end $$;
create or replace function public.arc_admin_rosters(p_event_slug text)
returns jsonb language sql security invoker set search_path='' as $$ select private.arc_admin_rosters(p_event_slug); $$;
create or replace function private.arc_admin_add_partner(p_team_id uuid,p_partner_id uuid)
returns jsonb language plpgsql security definer set search_path='' as $$
declare u uuid:=auth.uid(); t public.tg_teams%rowtype; a public.tg_athletes%rowtype; ca public.tg_athletes%rowtype; ev uuid;
begin
 if u is null or not exists(select 1 from public.tg_admins where user_id=u) then raise exception 'ADMIN_ONLY'; end if;
 select event_id into ev from public.tg_teams where id=p_team_id;
 if ev is null then raise exception 'TEAM_NOT_FOUND'; end if;
 perform pg_advisory_xact_lock(hashtextextended(ev::text,0));
 select * into t from public.tg_teams where id=p_team_id for update;
 if t.id is null then raise exception 'TEAM_NOT_FOUND'; end if;
 if t.status<>'confirmed' or t.payment_status is distinct from 'paid' then raise exception 'PAYMENT_NOT_CONFIRMED'; end if;
 if p_partner_id is null then raise exception 'INVALID_PLAYERS'; end if;
 -- Lock profiles in a consistent order with profile/team editing operations.
 perform 1 from public.tg_athletes where id=p_partner_id or id in(select athlete_id from public.tg_team_members where team_id=t.id and active) order by id for update;
 select * into a from public.tg_athletes where id=p_partner_id;
 select p.* into ca from public.tg_athletes p join public.tg_team_members m on m.athlete_id=p.id where m.team_id=t.id and m.active and m.member_role='captain';
 if ca.id is null then raise exception 'CAPTAIN_PROFILE_REQUIRED'; end if;
 if a.id is null or coalesce(a.gender,'') not in ('male','female') or length(trim(coalesce(a.display_name,''))) not between 2 and 50 or not exists(select 1 from public.tg_athlete_private where athlete_id=a.id and length(regexp_replace(coalesce(phone,''),'[^0-9]','','g')) between 10 and 11) then raise exception 'PARTNER_PROFILE_REQUIRED'; end if;
 if exists(select 1 from public.tg_team_members where team_id=t.id and athlete_id=a.id and active and member_role='partner') then return jsonb_build_object('team_id',t.id,'partner',a.display_name,'already_added',true); end if;
 if a.id=ca.id then raise exception 'CANNOT_ADD_CAPTAIN'; end if;
 if (select count(*) from public.tg_team_members where team_id=t.id and active)>=2 then raise exception 'TEAM_FULL'; end if;
 if exists(select 1 from public.tg_team_members where event_id=t.event_id and athlete_id=a.id and active) then raise exception 'PARTNER_ALREADY_REGISTERED'; end if;
 if coalesce(t.category,'') not in ('MM','WW','MIXED') then raise exception 'INVALID_CATEGORY'; end if;
 if (t.category='MM' and a.gender<>'male') or (t.category='WW' and a.gender<>'female') or (t.category='MIXED' and (ca.gender not in ('male','female') or ca.gender is null or a.gender=ca.gender)) then raise exception 'CATEGORY_GENDER_MISMATCH'; end if;
 insert into public.tg_team_members(team_id,event_id,athlete_id,member_role) values(t.id,t.event_id,a.id,'partner') on conflict(team_id,athlete_id) do update set active=true,member_role='partner';
 update public.tg_teams set player_2=a.display_name where id=t.id;
 update private.arc_entry_invites set status='accepted',responded_at=now(),confirmed_by=u,confirmation_method='admin' where team_id=t.id and invitee_id=a.id and status='pending';
 update private.arc_entry_invites set status='cancelled',responded_at=now() where status='pending' and (team_id=t.id or (invitee_id=a.id and team_id in(select id from public.tg_teams where event_id=t.event_id)));
 insert into private.arc_admin_audit(actor_id,target_id,action,details) values(u,a.id,'admin_add_partner',jsonb_build_object('team_id',t.id,'captain_id',ca.id));
 return jsonb_build_object('team_id',t.id,'partner',a.display_name);
end $$;
create or replace function public.arc_admin_add_partner(p_team_id uuid,p_partner_id uuid)
returns jsonb language sql security invoker set search_path='' as $$ select private.arc_admin_add_partner(p_team_id,p_partner_id); $$;
revoke all on function private.arc_admin_rosters(text),public.arc_admin_rosters(text),private.arc_admin_add_partner(uuid,uuid),public.arc_admin_add_partner(uuid,uuid) from public,anon;
grant execute on function private.arc_admin_rosters(text),public.arc_admin_rosters(text),private.arc_admin_add_partner(uuid,uuid),public.arc_admin_add_partner(uuid,uuid) to authenticated;
notify pgrst,'reload schema';
commit;
