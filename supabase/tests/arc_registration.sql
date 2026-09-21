
begin;
update public.tg_events set registration_open=true where slug='team-games-001';
create temporary table arc_test_results(label text);
do $test$
declare a uuid:=gen_random_uuid(); b uuid:=gen_random_uuid(); outsider uuid:=gen_random_uuid(); adm uuid;
 ac text; bc text; tid uuid; iid uuid; q jsonb;
begin
 select user_id into adm from public.tg_admins limit 1;
 insert into auth.users(id,email,raw_user_meta_data) values
 (a,'arc-test-'||a||'@example.invalid','{"signup_source":"team_games"}'),
 (b,'arc-test-'||b||'@example.invalid','{"signup_source":"team_games"}'),
 (outsider,'arc-test-'||outsider||'@example.invalid','{"signup_source":"team_games"}');
 perform set_config('request.jwt.claim.sub',a::text,true);
 perform public.arc_account_bootstrap('Test Captain');
 perform public.arc_save_player_profile('Test Captain','male','01099887701',null,null,true);
 perform set_config('request.jwt.claim.sub',b::text,true);
 perform public.arc_account_bootstrap('Test Partner');
 perform public.arc_save_player_profile('Test Partner','female','01099887702',null,null,true);
 perform set_config('request.jwt.claim.sub',outsider::text,true);
 perform public.arc_account_bootstrap('Test Outsider');
 begin perform public.arc_entry_action('admin_codes','{}'); raise exception 'TEST_FAILED_ADMIN_GUARD'; exception when others then if sqlerrm<>'ADMIN_ONLY' then raise; end if; end;
 perform set_config('request.jwt.claim.sub',adm::text,true);
 ac:=public.arc_entry_action('admin_issue_code',jsonb_build_object('email','arc-test-'||a||'@example.invalid'))->>'code';
 bc:=public.arc_entry_action('admin_issue_code',jsonb_build_object('email','arc-test-'||b||'@example.invalid'))->>'code';
 perform set_config('request.jwt.claim.sub',a::text,true);
 q:=public.arc_entry_action('quote','{}');
 if (q->>'amount_due')::int<>40000 then raise exception 'TEST_FAILED_BASE_PRICE'; end if;
 q:=public.arc_entry_action('quote',jsonb_build_object('captain_code',ac));
 if (q->>'amount_due')::int<>30000 then raise exception 'TEST_FAILED_SINGLE_CODE'; end if;
 q:=public.arc_entry_action('quote',jsonb_build_object('captain_code',ac,'partner_code',bc));
 if (q->>'amount_due')::int<>20000 then raise exception 'TEST_FAILED_TWO_CODES'; end if;
 begin perform public.arc_entry_action('quote',jsonb_build_object('captain_code',bc)); raise exception 'TEST_FAILED_CODE_OWNER'; exception when others then if sqlerrm<>'INVALID_CAPTAIN_CODE' then raise; end if; end;
 tid:=(public.arc_entry_action('register',jsonb_build_object('team_name','ARC Transaction Test','division','OPEN','category','MIXED','captain_code',ac,'partner_code',bc,'expected_amount',20000,'consent',true))->>'team_id')::uuid;
 if (select count(*) from public.tg_team_members where team_id=tid)<>1 then raise exception 'TEST_FAILED_SOLO_REGISTRATION'; end if;
 begin perform public.arc_entry_action('invite',jsonb_build_object('team_id',tid,'email','arc-test-'||b||'@example.invalid')); raise exception 'TEST_FAILED_PAYMENT_GATE'; exception when others then if sqlerrm<>'PAYMENT_NOT_CONFIRMED' then raise; end if; end;
 begin perform public.tg_reopen_payment_hold(tid); raise exception 'TEST_FAILED_LEGACY_PRICE'; exception when others then if sqlerrm<>'USE_ENTRY_PAGE' then raise; end if; end;
 perform public.arc_entry_action('report_payment',jsonb_build_object('team_id',tid,'depositor_name','Test Captain'));
 perform set_config('request.jwt.claim.sub',outsider::text,true);
 begin perform public.arc_entry_action('report_payment',jsonb_build_object('team_id',tid,'depositor_name','Intruder')); raise exception 'TEST_FAILED_OWNERSHIP'; exception when others then if sqlerrm<>'CAPTAIN_ONLY' then raise; end if; end;
 perform set_config('request.jwt.claim.sub',adm::text,true);
 perform public.tg_admin_confirm_payment(tid);
 perform set_config('request.jwt.claim.sub',a::text,true);
 perform public.arc_entry_action('invite',jsonb_build_object('team_id',tid,'email','arc-test-'||b||'@example.invalid'));
 select id into iid from private.arc_entry_invites where team_id=tid and status='pending';
 perform set_config('request.jwt.claim.sub',b::text,true);
 perform public.arc_entry_action('respond',jsonb_build_object('invite_id',iid,'accept',true,'consent',true));
 if (select count(*) from public.tg_team_members where team_id=tid and active)<>2 then raise exception 'TEST_FAILED_ROSTER'; end if;
 q:=public.arc_entry_action('state','{}');
 if not (q->'entry'->>'roster_complete')::boolean then raise exception 'TEST_FAILED_STATE'; end if;
 if has_function_privilege('anon','public.arc_entry_action(text,jsonb)','execute') then raise exception 'TEST_FAILED_ANON_GRANT'; end if;
 if has_table_privilege('authenticated','private.arc_entry_codes','select') then raise exception 'TEST_FAILED_CODE_PRIVACY'; end if;
 execute 'set local role authenticated';
 q:=public.arc_entry_action('state','{}');
 if not (q->'entry'->>'roster_complete')::boolean then raise exception 'TEST_FAILED_AUTHENTICATED_RPC'; end if;
 execute 'reset role';
 insert into arc_test_results values('PASS: captain-first registration; 40k/30k/20k pricing; account-bound codes; admin-only issuance; payment-before-invite; ownership; legacy-price guard; paid team invite acceptance; anonymous/table grants');
end; $test$;
select * from arc_test_results;
rollback;