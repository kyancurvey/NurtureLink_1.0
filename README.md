# NurtureLink

> Nurture Lives, Linking Hearts

Installable (PWA) web app for pregnant patients and healthcare providers.
Monitoring and screening prototype only. **Not a diagnostic device.**

Live site: https://kyancurvey.github.io/NurtureLink_1.0/

## Stack

React + Vite, vite-plugin-pwa, react-router (HashRouter), Supabase, GitHub Pages.

## Run locally

```bash
cp .env.example .env   # fill in the project URL and publishable key
npm install
npm run dev
```

The app is served under `/NurtureLink_1.0/`, so open the URL that Vite prints.

## Deploy

Pushing to `main` runs `.github/workflows/deploy.yml`, which builds the app and
publishes it to GitHub Pages. The build reads `VITE_SUPABASE_URL` and
`VITE_SUPABASE_ANON_KEY` from the repository variables
(Settings > Secrets and variables > Actions > Variables).

## Database

SQL lives in `supabase/migrations/` and is run by hand, in order, in the Supabase
SQL Editor (000 to 005). They are not applied automatically.

- `supabase/tests/002_verify_setup.sql`: read-only checks after 000 to 003.
- `supabase/tests/access_tests.sql`: access tests (anon denied, patient isolation,
  provider assignment). Everything rolls back. Re-run after any change to 004 or 005.
- `docs/ADMIN_SQL.md`: copy-paste snippets for the project owner (promote admin,
  invites, assign a patient to a provider, confirm thresholds, demo mode).
- `docs/ATTACKER_REVIEW_2.2.md`: security review of the grants and policies.

## Rules

- Only the Supabase publishable key is ever used. Never commit `sb_secret_...`
  or `service_role` keys.
- No real patient data in this repo. Synthetic data only.
