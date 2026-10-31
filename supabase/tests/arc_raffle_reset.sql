-- Synthetic event and identities only; all fixture changes are rolled back.
begin;
create temporary table raffle_reset_checks(result text);
do $test$
declare
 admin_id uuid:=gen_random_uuid(); member_id uuid:=gen_random_uuid(); ev uuid; other_ev uuid; team uuid;
 slug text:='qa-raffle-'||gen_random_uuid(); other_slug text:='qa-raffle-'||gen_random_uuid();
 j jsonb; draw jsonb; snapshot jsonb; request_id uuid; old_id uuid; kind text;
begin
 insert into auth.users(id,email,raw_user_meta_data) values(admin_id,admin_id||'@example.invalid','{}'),(member_id,member_id||'@example.invalid','{}');
 insert into public.tg_admins(user_id) values(admin_id);
 insert into public.tg_events(slug,title,event_date,max_teams) values(slug,'QA ONLY',now()+interval '1 day',24) returning id into ev;
 insert into public.tg_events(slug,title,event_date,max_teams) values(other_slug,'QA ONLY',now()+interval '1 day',24) returning id into other_ev;
 insert into private.arc_raffle_config(event_id,is_open,closes_at,counter) values(ev,false,now()+interval '1 day',1),(other_ev,false,now()+interval '1 day',1);
 insert into public.tg_teams(event_id,team_name,player_1,player_2,phone,division,category,photo_url) values(ev,'QA TEAM','QA ONE','QA TWO','01000000000','OPEN','WW','https://example.invalid/qa.jpg') returning id into team;
 insert into private.arc_raffle_entries(event_id,user_id,team_id,ticket) values(ev,member_id,team,1);
 insert into private.arc_raffle_draws(event_id,ticket,request_id,drawn_by,status) values(other_ev,1,gen_random_uuid(),admin_id,'claimed');
 perform set_config('request.jwt.claim.sub',member_id::text,true);execute 'set local role authenticated';
 begin perform public.arc_raffle(slug,'reset','{"confirm_reset":true,"expected_draws":[]}');raise exception 'FAIL_MEMBER_GUARD';exception when others then if sqlerrm<>'ADMIN_REQUIRED' then raise;end if;end;
 execute 'reset role';perform set_config('request.jwt.claim.sub','',true);execute 'set local role anon';
 begin perform public.arc_raffle(slug,'reset','{"confirm_reset":true,"expected_draws":[]}');raise exception 'FAIL_ANON_GUARD';exception when others then if sqlerrm<>'ADMIN_REQUIRED' then raise;end if;end;
 execute 'reset role';perform set_config('request.jwt.claim.sub',admin_id::text,true);
 foreach kind in array array['pending','claimed','absent'] loop
  request_id:=gen_random_uuid();execute 'set local role authenticated';
  draw:=public.arc_raffle(slug,'draw',jsonb_build_object('request_id',request_id));execute 'reset role';
  old_id:=(draw->>'id')::uuid;
  if draw->>'ticket'<>'1' or draw ? 'reset_by' or draw ? 'drawn_by' then raise exception 'FAIL_DRAW_OR_PRIVACY';end if;
  if kind='claimed' then perform public.arc_raffle(slug,'claim',jsonb_build_object('draw_id',old_id));
  elsif kind='absent' then update private.arc_raffle_draws set created_at=now()-interval '61 seconds' where id=old_id;perform public.arc_raffle(slug,'absent',jsonb_build_object('draw_id',old_id));end if;
  snapshot:=jsonb_build_array(jsonb_build_object('id',old_id,'status',kind));
  begin perform public.arc_raffle(slug,'reset',jsonb_build_object('expected_draws',snapshot));raise exception 'FAIL_CONFIRMATION';exception when others then if sqlerrm<>'RESET_CONFIRMATION_REQUIRED' then raise;end if;end;
  begin perform public.arc_raffle(slug,'reset','{"confirm_reset":true,"expected_draws":[]}');raise exception 'FAIL_STALE_GUARD';exception when others then if sqlerrm<>'RAFFLE_CHANGED' then raise;end if;end;
  execute 'set local role authenticated';
  j:=public.arc_raffle(slug,'reset',jsonb_build_object('confirm_reset',true,'expected_draws',snapshot));execute 'reset role';
  if jsonb_array_length(j->'draws')<>0 or (j->>'is_open')::boolean or (j->>'total')::int<>1 then raise exception 'FAIL_RESET_BOARD';end if;
  if not exists(select 1 from private.arc_raffle_draws where id=old_id and reset_at is not null and reset_by=admin_id and status=kind) then raise exception 'FAIL_ARCHIVE';end if;
  begin perform public.arc_raffle(slug,'draw',jsonb_build_object('request_id',request_id));raise exception 'FAIL_OLD_REQUEST';exception when others then if sqlerrm<>'DRAW_RESET' then raise;end if;end;
  begin perform public.arc_raffle(slug,'claim',jsonb_build_object('draw_id',old_id));raise exception 'FAIL_OLD_CLAIM';exception when others then if sqlerrm<>'DRAW_NOT_FOUND' then raise;end if;end;
  begin perform public.arc_raffle(slug,'reset',jsonb_build_object('confirm_reset',true,'expected_draws',snapshot));raise exception 'FAIL_STALE_RESET';exception when others then if sqlerrm<>'RAFFLE_CHANGED' then raise;end if;end;
 end loop;
 if (select count(*) from private.arc_raffle_entries where event_id=ev and ticket=1 and team_id=team)<>1 then raise exception 'FAIL_ENTRIES';end if;
 if not exists(select 1 from private.arc_raffle_config where event_id=ev and counter=1 and not is_open and closes_at=now()+interval '1 day') then raise exception 'FAIL_CONFIG';end if;
 if (select count(*) from private.arc_raffle_draws where event_id=other_ev and reset_at is null)<>1 then raise exception 'FAIL_EVENT_SCOPE';end if;
 j:=public.arc_raffle(slug,'board');if (j->'teams'->0->>'support_count')::int<>1 then raise exception 'FAIL_SUPPORT';end if;
 if (select count(*) from private.arc_raffle_draws where event_id=ev and reset_at is not null)<>3 then raise exception 'FAIL_HISTORY';end if;
 j:=public.arc_raffle(slug,'draw',jsonb_build_object('request_id',gen_random_uuid()));if j->>'ticket'<>'1' then raise exception 'FAIL_REDRAW';end if;
 if has_table_privilege('authenticated','private.arc_raffle_draws','select') or has_table_privilege('anon','private.arc_raffle_draws','update') then raise exception 'FAIL_TABLE_PRIVACY';end if;
 insert into raffle_reset_checks values('PASS: admin-only reset; confirmation and stale-state guards; pending/claimed/absent reset; archived audit; replay and stale-claim rejection; same ticket eligible again; entries/support/deadline/counter preserved; event isolation; private-table access.');
end $test$;
select * from raffle_reset_checks;
rollback;
