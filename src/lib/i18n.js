import i18n from 'i18next'
import { initReactI18next } from 'react-i18next'
import en from '../locales/en.json'
import fil from '../locales/fil.json'

// Each top-level key in a locale file is a namespace. "common" is the default,
// so t('ui.back') means common:ui.back. Other namespaces use a prefix, for
// example t('patient:tabs.home').
export const LANGUAGES = ['en', 'fil']
export const NAMESPACES = ['common', 'auth', 'terms', 'patient', 'provider', 'alerts', 'errors']

const STORAGE_KEY = 'nurturelink.language'

// localStorage can be blocked (private mode, strict settings), so never let it throw.
function readSaved() {
  try {
    const saved = localStorage.getItem(STORAGE_KEY)
    return LANGUAGES.includes(saved) ? saved : null
  } catch {
    return null
  }
}

// First browser language that is English or Filipino. 'tl' is Tagalog, which
// some Android phones report for Filipino. Anything else falls back to English.
function fromBrowser() {
  const prefs = navigator.languages?.length ? navigator.languages : [navigator.language]
  for (const tag of prefs) {
    const base = String(tag).toLowerCase().split('-')[0]
    if (base === 'en') return 'en'
    if (base === 'fil' || base === 'tl') return 'fil'
  }
  return 'en'
}

i18n.use(initReactI18next).init({
  resources: { en, fil },
  lng: readSaved() ?? fromBrowser(),
  fallbackLng: 'en',
  supportedLngs: LANGUAGES,
  ns: NAMESPACES,
  defaultNS: 'common',
  interpolation: { escapeValue: false }, // React already escapes
  react: { useSuspense: false }, // resources are bundled, nothing to wait for
  // Development only: log a missing key instead of silently showing it.
  saveMissing: import.meta.env.DEV,
  missingKeyHandler: (_langs, ns, key) => console.warn(`[NurtureLink] Missing i18n key: ${ns}:${key}`),
})

// Keep <html lang> in step with the UI language (screen readers, hyphenation).
document.documentElement.lang = i18n.language
i18n.on('languageChanged', (lng) => {
  document.documentElement.lang = lng
})

// Signed-in users also save their language to their profile. AuthProvider
// registers the function that does that (kept out of this file so i18n has no
// dependency on Supabase). The function never throws.
let languageSaver = null
export function registerLanguageSaver(fn) {
  languageSaver = fn
  return () => {
    if (languageSaver === fn) languageSaver = null
  }
}

// The one place a language is chosen. Saves it on this device, switches, and
// (when signed in) saves it to the profile. Pass { saveToProfile: false } when
// the language came FROM the profile, so it is not written straight back.
export async function setLanguage(code, { saveToProfile = true } = {}) {
  if (!LANGUAGES.includes(code)) return
  try {
    localStorage.setItem(STORAGE_KEY, code)
  } catch {
    // Not saved this time; the switch below still works for this visit.
  }
  await i18n.changeLanguage(code)
  if (saveToProfile && languageSaver) await languageSaver(code)
}

export default i18n
