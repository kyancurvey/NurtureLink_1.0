import { createClient } from '@supabase/supabase-js'

const url = import.meta.env.VITE_SUPABASE_URL
const key = import.meta.env.VITE_SUPABASE_ANON_KEY // holds the sb_publishable_... key

const missing = []
if (!url) missing.push('VITE_SUPABASE_URL')
if (!key) missing.push('VITE_SUPABASE_ANON_KEY')

if (missing.length > 0) {
  console.warn(
    `[NurtureLink] Missing ${missing.join(' and ')}. Supabase is disabled. ` +
      'Locally, copy .env.example to .env. On GitHub, add them under ' +
      'Settings > Secrets and variables > Actions > Variables.',
  )
} else if (key.startsWith('sb_secret_')) {
  // Hard rule: a secret key must never reach the browser.
  console.error(
    '[NurtureLink] VITE_SUPABASE_ANON_KEY contains a secret key. Supabase is ' +
      'disabled. Use the publishable key (sb_publishable_...) and rotate the secret key.',
  )
}

const usable = missing.length === 0 && !key.startsWith('sb_secret_')

// null when not configured, so the app still loads instead of crashing.
//
// Auth settings (supabase-js stores and refreshes the session itself; this app
// never stores or reads tokens):
//  - flowType 'pkce': email links come back as "?code=..." (a query string),
//    not as tokens in the "#" part, so they cannot clash with HashRouter.
//  - storageKey: kyancurvey.github.io is one browser origin shared by all of
//    the owner's repos, so this app uses its own storage name.
export const supabase = usable
  ? createClient(url, key, {
      auth: {
        flowType: 'pkce',
        storageKey: 'nurturelink.auth',
        persistSession: true,
        autoRefreshToken: true,
        detectSessionInUrl: true,
      },
    })
  : null
