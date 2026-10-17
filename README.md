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

## Rules

- Only the Supabase publishable key is ever used. Never commit `sb_secret_...`
  or `service_role` keys.
- No real patient data in this repo. Synthetic data only.
