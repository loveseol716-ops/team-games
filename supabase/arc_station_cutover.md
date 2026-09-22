# ARC STATION authentication separation

Status: destination prepared; production cutover NOT performed.

- Source project: tdhdmlhwahxcadoeywxi (NTAC shared backend).
- Destination project: pyqyywxeduwzsusirkja (arc-station).
- Production config.js still targets source intentionally.
- 24 ARC tables, 55 functions, 35 policies and 8 application triggers copied.
- 5 related auth accounts and 7 identities copied, preserving account IDs/password hashes; no sessions copied.
- All 24 application tables matched source counts and checksums after migration.
- Registration SQL regression passed, including shared discount, payment and invitation permissions.
- Destination tg-athlete-signup deployed with signup_source=arc_station.
- NTAC auth.users profile-creation trigger is absent from destination.

## Required before cutover

1. Configure destination Auth Site URL as https://arcstation.kr and allowed redirect https://arcstation.kr/account.html (www only if supported).
2. Enable Google and Kakao providers. Current public Auth settings confirm both are disabled.
3. Register https://pyqyywxeduwzsusirkja.supabase.co/auth/v1/callback with the relevant provider apps; retain NTAC callback for NTAC.
4. Copy ARC athlete photo bucket, scoped storage policies, and referenced files. Three current photo URLs still reference source tg-athlete-photos. Do not copy NTAC assets.
5. Refresh ARC data/accounts changed since initial copy; verify all foreign keys, permissions and totals.
6. Update only ARC frontend backend configuration and deploy. Preserve existing NTAC config/data.
7. Verify actual Google/Kakao/email login, registration and admin access. Confirm new ARC signup does not create an NTAC profile. Sessions must be re-established.

## Security notes

RLS is enabled on all copied application tables. Private registration tables intentionally expose no direct client policies. Public SECURITY DEFINER RPCs must expose summary data only. Destination advisor reports leaked-password protection disabled; review Auth protection settings before opening password signups.

No credentials, user data, or password hashes are included in this document.
