begin;
create temp table arc_deadline_test_results(result text);
do $$
declare ev uuid; live_ev uuid; adm uuid:=gen_random_uuid(); c uuid; p uuid; tid uuid; q jsonb; slug text:='qa-cap-'||gen_random_uuid(); n integer;
begin
 insert into auth.users(id,email) values(adm,adm||'@example.invalid');
 insert into public.tg_admins(user_id) values(adm);
 perform set_config('request.jwt.claim.sub',adm::text,true);
 insert into public.tg_events(slug,title,event_date,max_teams,early_bird_ends_at,registration_closes_at)
 values(slug,'QA capacity',now()+interval '90 days',24,'2026-10-11 00:00+09','2026-10-25 00:00+09') returning id into ev;
 if (private.arc_event_terms(ev,'2026-10-10 23:59:59.999+09')->>'base_fee')::int<>20000 or (private.arc_event_terms(ev,'2026-10-11 00:00+09')->>'base_fee')::int<>25000 then raise exception 'FAIL_EARLY_BOUNDARY';end if;
 if not (private.arc_event_terms(ev,'2026-10-24 23:59:59.999+09')->>'registration_open')::bool or (private.arc_event_terms(ev,'2026-10-25 00:00+09')->>'registration_open')::bool then raise exception 'FAIL_CLOSE_BOUNDARY';end if;
 for n in 1..25 loop
  c:=gen_random_uuid();p:=gen_random_uuid();
  insert into auth.users(id,email) values(c,c||'@example.invalid'),(p,p||'@example.invalid');
  perform public.arc_admin_action('save_profile',jsonb_build_object('user_id',c,'nickname','QA captain','full_name','QA captain','gender','male','phone','0199000'||lpad(n::text,4,'0'),'reason','QA only'));
  perform public.arc_admin_action('save_profile',jsonb_build_object('user_id',p,'nickname','QA partner','full_name','QA partner','gender','male','phone','0198000'||lpad(n::text,4,'0'),'reason','QA only'));
  if n<=24 then
   q:=public.arc_admin_action('add_team',jsonb_build_object('event_slug',slug,'team_name','QA '||n,'captain_id',c,'partner_id',p,'division','OPEN','category','MM','reason','QA only'));
  else
   begin
    perform public.arc_admin_action('add_team',jsonb_build_object('event_slug',slug,'team_name','QA 25','captain_id',c,'partner_id',p,'division','PRO','category','MM','reason','QA only'));
    raise exception 'FAIL_25TH_TEAM';
   exception when others then if sqlerrm<>'REGISTRATION_FULL' then raise;end if;end;
  end if;
 end loop;
 if(select count(*) from public.tg_teams where event_id=ev and division='OPEN' and category='MM')<>24 then raise exception 'FAIL_CATEGORY_QUOTA';end if;
 if(select max(heat_no) from public.tg_teams where event_id=ev)<>12 then raise exception 'FAIL_12_HEATS';end if;
 if(select capacity from public.tg_event_capacity(slug))<>24 or(select filled from public.tg_event_capacity(slug))<>24 then raise exception 'FAIL_CAPACITY_API';end if;
 begin
  insert into public.tg_teams(event_id,team_name,player_1,player_2,phone,photo_url,status,payment_status,payment_deadline) values(ev,'QA overflow','A','B','01970000000','https://arcstation.kr/favicon.png','pending_payment','unpaid',now()+interval '1 day');
  raise exception 'FAIL_TRIGGER_CAP';
 exception when others then if sqlerrm<>'REGISTRATION_FULL' then raise;end if;end;
 -- A payment confirmation must not reapply the old four-team quota.
 select id into tid from public.tg_teams where event_id=ev limit 1;
 update public.tg_teams set status='pending_payment',payment_status='payment_check',heat_no=null,station_no=null where id=tid;
 perform public.tg_admin_confirm_payment(tid);
 select e.id into live_ev from public.tg_events e where e.slug='team-games-001';
 update public.tg_events set early_bird_ends_at=now()-interval '1 second' where id=live_ev;
 q:=private.arc_entry_quote(live_ev,null,null);
 if(q->>'amount_due')::int<>50000 then raise exception 'FAIL_REGULAR_PRICE';end if;
 q:=private.arc_entry_quote(live_ev,'NOLTO01',null);
 if(q->>'amount_due')::int<>25000 then raise exception 'FAIL_REGULAR_DISCOUNT';end if;
 update public.tg_events set registration_closes_at=now()-interval '1 second' where id=live_ev;
 perform set_config('request.jwt.claim.sub',c::text,true);
 begin perform public.arc_entry_action('register','{}');raise exception 'FAIL_DEADLINE_GATE';exception when others then if sqlerrm<>'REGISTRATION_CLOSED' then raise;end if;end;
 if(public.arc_entry_action('state','{}')->>'registration_open')::bool then raise exception 'FAIL_DEADLINE_STATE';end if;
 if not has_function_privilege('anon','public.arc_event_status(text)','execute') then raise exception 'FAIL_PUBLIC_STATUS';end if;
 if has_function_privilege('authenticated','private.arc_event_terms(uuid,timestamptz)','execute') then raise exception 'FAIL_PRIVATE_CLOCK';end if;
 insert into arc_deadline_test_results values('PASS: KST date boundaries, 24 teams in one category, 12 heats, 25th rejection in RPC and trigger, payment confirmation beyond four, regular and discount prices, closed registration RPC/state, public/private grants');
end $$;
select * from arc_deadline_test_results;
rollback;
