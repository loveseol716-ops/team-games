# ARC STATION account and roster controls

Target: ARC project `pyqyywxeduwzsusirkja` only. No NTAC configuration changes.

## Behavior

- Pending partner names appear in Team Control, clearly marked as invited.
- A paid team's captain may confirm an existing pending invitation. The partner needs an ARC player profile (name, category gender, phone), but does not need to accept separately. Confirmation records its actor and method; it does not manufacture the partner's consent.
- Account Control searches account names, emails and phone numbers with pagination. Administrators can update nickname, player name, gender, phone, gym and Instagram. Active roster names and captain contact are synchronized.
- Manual entry selects an event, division, category and two account holders. It records a complimentary team (0 KRW, no bank transfer timestamp). Duplicate membership, gender/category and capacity checks remain active. Administrators can complete player profiles first.
- Changes require a reason and produce an audit record. Administrators cannot delete themselves or administrator accounts. Team, prediction and non-signup point history blocks account deletion. Other accounts require an exact email confirmation and use the Supabase Auth Admin API. An Auth deletion trigger rechecks history within the deletion transaction. Owned Storage objects may also block deletion.
- Existing access JWTs may remain cryptographically valid until expiration after an Auth deletion. The deleted identity and FK-dependent private records are removed; Auth `getUser` no longer resolves the account. The deletion endpoint always validates with `getUser` and checks the database administrator table.

## Deployment and verification

Apply `arc_admin_controls.sql` via Supabase migration tooling, then deploy `functions/arc-admin-accounts/index.ts`. The function implements explicit JWT validation and administrator checks; gateway legacy JWT verification is disabled to support project signing keys. Never expose the service role key to the browser.

Run `tests/arc_admin_controls.sql`; it uses synthetic accounts inside a rolled-back transaction. Coverage includes authorization, pending names, captain confirmation, profile synchronization, complimentary entry, duplicates, category mismatches, consent preservation, deletion guards and auditing.

Validated on 2026-09-23: SQL suite passed; unauthenticated deletion endpoint returned 401; JavaScript syntax and DOM integration checks passed for initialization, account editing, pending roster rendering and manual registration. No test accounts were retained. Mobile visual verification was blocked by the cloud browser's URL policy for the isolated fixture; no claim of device-level visual testing is made.

Security advisor review: private audit table intentionally has RLS with no direct policies/grants; authenticated SECURITY DEFINER RPCs explicitly verify administrator/captain authority. References: [RLS policies](https://supabase.com/docs/guides/database/database-linter?lint=0008_rls_enabled_no_policy), [RPC permissions](https://supabase.com/docs/guides/database/database-linter?lint=0029_authenticated_security_definer_function_executable). Existing project password protection setting remains unchanged; [Supabase password protection](https://supabase.com/docs/guides/auth/password-security#password-strength-and-leaked-password-protection).
