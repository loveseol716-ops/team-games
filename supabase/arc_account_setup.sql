create or replace function private.arc_account_setup_state()
returns jsonb language plpgsql security definer set search_path='' as $$
declare u uuid:=auth.uid(); r jsonb;
begin
 if u is null then raise exception 'AUTH_REQUIRED'; end if;
 select jsonb_build_object(
 'nickname',coalesce(ap.display_name,''),'full_name',coalesce(a.display_name,pr.full_name,''),
 'gender',coalesce(a.gender,''),'phone',coalesce(p.phone,pr.phone,''),
 'gym',coalesce(a.gym,''),'instagram',coalesce(a.instagram,''),
 'terms_accepted',pr.terms_accepted_at is not null,'privacy_accepted',pr.privacy_accepted_at is not null,
 'complete',coalesce(length(trim(ap.display_name)) between 2 and 30
 and length(trim(a.display_name)) between 2 and 50 and a.gender in ('male','female')
 and length(regexp_replace(coalesce(p.phone,''),'[^0-9]','','g')) between 10 and 11
 and p.privacy_consent_at is not null and pr.terms_accepted_at is not null and pr.privacy_accepted_at is not null,false))
 into r from auth.users au
 left join public.arc_profiles ap on ap.user_id=au.id
 left join public.arc_account_private pr on pr.user_id=au.id
 left join public.tg_athletes a on a.id=au.id
 left join public.tg_athlete_private p on p.athlete_id=au.id where au.id=u;
 if r is null then raise exception 'ACCOUNT_NOT_FOUND'; end if;
 return r;
end $$;
create or replace function public.arc_account_setup_state()
returns jsonb language sql security invoker set search_path='' as $$
 select private.arc_account_setup_state();
$$;
create or replace function private.arc_complete_account(p_nickname text,p_full_name text,p_gender text,p_phone text,p_terms_consent boolean,p_privacy_consent boolean,p_instagram text default null,p_gym text default null)
returns jsonb language plpgsql security definer set search_path='' as $$
declare u uuid:=auth.uid(); nick text:=trim(coalesce(p_nickname,'')); nm text:=trim(coalesce(p_full_name,'')); ph text:=regexp_replace(coalesce(p_phone,''),'[^0-9]','','g');
begin
 if u is null then raise exception 'AUTH_REQUIRED'; end if;
 if length(nick) not between 2 and 30 then raise exception 'INVALID_NICKNAME'; end if;
 if length(nm) not between 2 and 50 then raise exception 'NAME_REQUIRED'; end if;
 if coalesce(p_gender,'') not in ('male','female') then raise exception 'GENDER_REQUIRED'; end if;
 if length(ph) not between 10 and 11 then raise exception 'INVALID_PHONE'; end if;
 if not coalesce(p_terms_consent,false) or not coalesce(p_privacy_consent,false) then raise exception 'CONSENT_REQUIRED'; end if;
 perform 1 from auth.users where id=u for update;
 perform 1 from public.tg_athletes where id=u for update;
 if exists(select 1 from public.tg_team_members m join public.tg_teams t on t.id=m.team_id where m.athlete_id=u and m.active and
 ((t.category='MM' and p_gender<>'male') or (t.category='WW' and p_gender<>'female') or (t.category='MIXED' and exists(select 1 from public.tg_team_members pm join public.tg_athletes pa on pa.id=pm.athlete_id where pm.team_id=t.id and pm.active and pm.athlete_id<>u and pa.gender=p_gender)))) then raise exception 'CATEGORY_GENDER_MISMATCH'; end if;
 perform public.arc_account_bootstrap(nick);
 perform public.arc_save_player_profile(nm,p_gender,ph,p_instagram,p_gym,true);
 insert into public.arc_account_private(user_id,full_name,phone,terms_accepted_at,privacy_accepted_at)
 values(u,nm,ph,now(),now())
 on conflict(user_id) do update set full_name=excluded.full_name,phone=excluded.phone,updated_at=now();
 update public.tg_teams t set player_1=case when m.member_role='captain' then nm else t.player_1 end,
 player_2=case when m.member_role='partner' then nm else t.player_2 end,
 phone=case when m.member_role='captain' then ph else t.phone end
 from public.tg_team_members m where m.team_id=t.id and m.athlete_id=u and m.active;
 update private.arc_entries set captain_gender=p_gender where captain_id=u;
 return private.arc_account_setup_state();
end $$;
create or replace function public.arc_complete_account(p_nickname text,p_full_name text,p_gender text,p_phone text,p_terms_consent boolean,p_privacy_consent boolean,p_instagram text default null,p_gym text default null)
returns jsonb language sql security invoker set search_path='' as $$
 select private.arc_complete_account(p_nickname,p_full_name,p_gender,p_phone,p_terms_consent,p_privacy_consent,p_instagram,p_gym);
$$;
revoke all on function private.arc_account_setup_state(),public.arc_account_setup_state(),private.arc_complete_account(text,text,text,text,boolean,boolean,text,text),public.arc_complete_account(text,text,text,text,boolean,boolean,text,text) from public,anon;
grant execute on function private.arc_account_setup_state(),public.arc_account_setup_state(),private.arc_complete_account(text,text,text,text,boolean,boolean,text,text),public.arc_complete_account(text,text,text,text,boolean,boolean,text,text) to authenticated;
