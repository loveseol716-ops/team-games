create table if not exists public.arc_account_private (
  user_id uuid primary key references auth.users(id) on delete cascade,
  full_name text not null check (char_length(trim(full_name)) between 2 and 50),
  phone text not null check (char_length(regexp_replace(phone, '[^0-9]', '', 'g')) between 8 and 15),
  terms_accepted_at timestamptz not null default now(),
  privacy_accepted_at timestamptz not null default now(),
  marketing_accepted_at timestamptz,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

alter table public.arc_account_private enable row level security;

create policy "arc_account_private_self_read"
on public.arc_account_private
for select
to authenticated
using (user_id = (select auth.uid()));

create policy "arc_account_private_self_update"
on public.arc_account_private
for update
to authenticated
using (user_id = (select auth.uid()))
with check (user_id = (select auth.uid()));

grant select, update on public.arc_account_private to authenticated;

comment on table public.arc_account_private is 'Private contact and consent records for ARC email signups.';
comment on column public.arc_account_private.marketing_accepted_at is 'Null when optional marketing consent was not granted.';
