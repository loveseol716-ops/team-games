-- User-authorized NOLTO prediction reset; preserve accounting history.
begin;
-- Serialize against incoming submissions before inspecting/refunding bets.
select m.id from public.tg_prediction_markets m join public.tg_events e on e.id=m.event_id
where e.slug='team-games-001' order by m.id for update of m;
update public.tg_events set picks_open=false where slug='team-games-001';
do $$
declare rec record; v_before integer; v_after integer;
begin
 if exists(select 1 from public.tg_prediction_bets b join public.tg_prediction_markets m on m.id=b.market_id join public.tg_events e on e.id=m.event_id where e.slug='team-games-001' and b.status in ('won','lost')) then raise exception 'SETTLED_PICKS_REQUIRE_REVIEW';end if;
 for rec in select b.*,m.event_id from public.tg_prediction_bets b join public.tg_prediction_markets m on m.id=b.market_id join public.tg_events e on e.id=m.event_id where e.slug='team-games-001' and b.status='open' order by b.user_id,b.id for update of b loop
  select balance into strict v_before from public.tg_fan_wallets where user_id=rec.user_id for update;
  update public.tg_fan_wallets set balance=balance+rec.stake,updated_at=now() where user_id=rec.user_id returning balance into v_after;
  insert into public.tg_fan_point_ledger(user_id,event_id,bet_id,kind,amount,balance_before,balance_after,note)
  values(rec.user_id,rec.event_id,rec.id,'admin_adjustment',rec.stake,v_before,v_after,'FAN PICK reset: full stake returned; awaiting final team lineups. Original pick '||rec.id);
 end loop;
 -- Remove selections so everyone can pick afresh after the future reopening.
 -- Existing stake and refund ledger rows remain; FK sets bet_id to NULL.
 delete from public.tg_prediction_bets b using public.tg_prediction_markets m,public.tg_events e where b.market_id=m.id and m.event_id=e.id and e.slug='team-games-001' and b.status in ('open','refunded');
end $$;
update public.tg_prediction_markets m set status='locked',winning_team_id=null,settled_at=null from public.tg_events e where e.id=m.event_id and e.slug='team-games-001';
commit;
