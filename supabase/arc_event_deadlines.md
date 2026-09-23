# NOLTO capacity and deadlines

- Shared event capacity: 24 teams across BEGINNER / ATHLETE and all three categories. No category quotas. Reservations include confirmed teams, payments awaiting review, and unexpired payment holds.
- Early bird ends at 2026-10-11 00:00 Asia/Seoul. Base price changes from 20,000 to 25,000 KRW per athlete; the existing team discount remains 50%. Existing valid payment holds keep their quoted amounts.
- New public applications close at 2026-10-25 00:00 Asia/Seoul. Existing entries may still report a timely transfer, receive staff payment confirmation and complete their roster. Staff complimentary entries remain possible subject to overall capacity.
- All admissions, including older APIs and staff entry, pass a total-capacity trigger using the same event lock. Public entry state and pricing read the server-side event terms.
- `arc_event_status` intentionally permits anonymous reads of public dates, base price and aggregate capacity only. It does not expose member information or allow caller-supplied clock overrides. The private date helper is not executable by API roles. [Supabase advisor reference](https://supabase.com/docs/guides/database/database-linter?lint=0028_anon_security_definer_function_executable).
- The EVENTS highlight and entry price strip use server time and update while the page stays open. Date fallbacks use explicit Korean timezone offsets.
- Deletion uses a separate reason input and error message inside the deletion section; profile-edit reasons remain separate.

Apply `arc_event_deadlines.sql` after the initial admin-controls migration. The rollback-only `tests/arc_event_deadlines.sql` passed: date boundaries, 24 same-category teams, 12 heats, 25th-team rejection, payment confirmation beyond four teams, regular/discount pricing, deadline rejection, and permissions. DOM tests passed for badge expiry, price changes, closure and separate delete reasons. No real accounts or registrations were modified during tests.
