# TEAM GAMES — LIVE Supabase Build

Connected Supabase project:
- Project: `ntac-platform`
- Project URL: `https://tdhdmlhwahxcadoeywxi.supabase.co`
- TEAM GAMES data is isolated with `tg_` table prefixes.
- Storage bucket: `tg-team-photos`

## Live storage
- `tg_events`
- `tg_teams`
- `tg_winner_picks`
- `tg_podium_picks`
- `tg_pick_totals`
- `tg_results`
- `tg_admins`

## Current event
- TEAM GAMES #01
- 2026-10-31 14:00 KST
- 12 teams maximum
- Event slug: `team-games-001`

## Security
- Team phone numbers are stored but not selectable by public roles.
- Raw Winner Pick voter tokens are not publicly readable.
- Public fan percentages come from `tg_pick_totals`.
- Results are publicly readable but writable only by authenticated TEAM GAMES admins.
- Existing `owner` and `admin` profiles in this Supabase project were added as TEAM GAMES admins.
- Team photo upload is limited to JPG/JPEG/PNG/WEBP, max 5 MB.

## Files
Open `index.html` for the site.
Use `admin.html` for result entry with an existing Supabase owner/admin login.
