// Runs BEFORE React and before the Supabase client (main.jsx imports it first).
//
// When a link in an email is expired or already used, Supabase sends the person
// back to the site with the error in the URL (in the part after "#", or after
// "?"). HashRouter would read that text as a page name and find nothing. So we
// read the error once here, remove it from the address bar, and point the
// router at the login page. The AuthProvider shows a calm message for it.
//
// This file never touches tokens. Sessions are handled only by supabase-js.

// Where email links should bring people back to: the site root, for example
// https://kyancurvey.github.io/NurtureLink_1.0/ . It must be in the Supabase
// redirect allow-list (Authentication > URL Configuration).
export const SITE_URL = `${window.location.origin}${import.meta.env.BASE_URL}`

let linkError = null // 'expired' | 'invalid' | null

function capture() {
  try {
    const url = new URL(window.location.href)
    const fromHash = new URLSearchParams(url.hash.replace(/^#/, ''))
    const fromQuery = url.searchParams
    const code = fromHash.get('error_code') || fromQuery.get('error_code')
    const hasError = code || fromHash.get('error') || fromQuery.get('error')
    if (!hasError) return
    linkError = code === 'otp_expired' ? 'expired' : 'invalid'
    for (const k of ['error', 'error_code', 'error_description']) fromQuery.delete(k)
    const search = fromQuery.toString()
    window.history.replaceState(
      null,
      '',
      `${url.pathname}${search ? `?${search}` : ''}#/login`,
    )
  } catch {
    // If the address cannot be read, the app still loads normally.
  }
}
capture()

export function getLinkError() {
  return linkError
}
