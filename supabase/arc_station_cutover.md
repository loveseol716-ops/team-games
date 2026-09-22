# ARC STATION authentication separation

Status: frontend cutover committed on 2026-09-22; verify deployed config before declaring live.

- Source: tdhdmlhwahxcadoeywxi (NTAC). Destination: pyqyywxeduwzsusirkja (ARC).
- config.js now targets the ARC project with its publishable key.
- 24 ARC tables, 55 functions, 35 application policies and 8 triggers copied.
- 5 related accounts and 7 identities preserved; old sessions were not copied.
- Source and destination application data matched again immediately before cutover, prior to rewriting photo URLs.
- 3 athlete photos copied with byte count and SHA-256 verification. Photo URLs now use ARC storage.
- All 4 scoped photo storage policies copied, including owner checks on writes.
- Temporary storage migration endpoint replaced by an inert HTTP 410 response; JWT verification remains enabled.
- Google/Kakao providers enabled. Both authorize endpoints return the new project's callback.
- User confirmed provider callback and Site URL/redirect settings configured.
- Destination email signup and password login returned HTTP 200 in an isolated fixture test. Session revoked; fixture removed.
- Source contained zero corresponding test accounts, confirming independent signup storage.
- Registration regression passed again: captain-first signup, 40k/20k pricing, reusable team discount, ownership, payment-before-invite and admin guards.
- NTAC automatic profile trigger is absent from destination. Existing NTAC data remains intact.

## Remaining user verification

Complete Google and Kakao consent with a real account and confirm return to ARC. Provider credential exchange cannot be fully verified from the initial authorize redirect alone. Existing users must log in again.

## Security notes

RLS is enabled on all ARC tables. Private entry tables intentionally have no direct client policies. SECURITY DEFINER warnings cover application RPCs and require ongoing authorization review.
Leaked-password protection remains disabled: https://supabase.com/docs/guides/auth/password-security#password-strength-and-leaked-password-protection

No credentials, user records, or password hashes are included here.
