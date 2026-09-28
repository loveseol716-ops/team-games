begin;
-- Preserve the current event deadline/pricing logic and discount both athletes.
create or replace function private.arc_entry_quote(p_event_id uuid,p_captain_code text,p_partner_code text)
returns jsonb language plpgsql security definer set search_path='' as $$
declare base integer; code text:=upper(trim(coalesce(nullif(trim(p_captain_code),''),nullif(trim(p_partner_code),''),''))); discounted boolean;
begin
 if auth.uid() is null then raise exception 'AUTH_REQUIRED'; end if;
 if code<>'' and code not in ('NOLTO01','UNG01') then raise exception 'INVALID_DISCOUNT_CODE'; end if;
 base:=(private.arc_event_terms(p_event_id)->>'base_fee')::integer;
 discounted:=code in ('NOLTO01','UNG01');
 return jsonb_build_object('base_fee',base,'captain_fee',case when discounted then base/2 else base end,
 'partner_fee',case when discounted then base/2 else base end,'amount_due',case when discounted then base else base*2 end,
 'pricing_tier',case when base=20000 then 'early_bird' else 'regular' end,'discount_percent',case when discounted then 50 else 0 end,
 'captain_code_id',null,'partner_code_id',null);
end; $$;
-- Keep existing table RLS: only admins write; public reads begin on event day.
alter table public.tg_results
 add column if not exists workout_a_seconds numeric check(workout_a_seconds between 0 and 480),
 add column if not exists workout_b_seconds numeric check(workout_b_seconds between 0 and 480),
 add column if not exists workout_a_rank integer check(workout_a_rank > 0),
 add column if not exists workout_b_rank integer check(workout_b_rank > 0),
 add column if not exists workout_a_points numeric check(workout_a_points >= 0 and workout_a_points < 1000000),
 add column if not exists workout_b_points numeric check(workout_b_points >= 0 and workout_b_points < 1000000),
 add column if not exists total_points numeric generated always as (workout_a_points+workout_b_points) stored;
comment on column public.tg_results.rank is 'Official combined-points placing. Enter after the published scoring and tie rules are applied; do not rank by a single finish time.';
notify pgrst, 'reload schema';
commit;
