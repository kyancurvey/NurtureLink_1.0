import i18next from 'i18next';
import { initReactI18next } from 'react-i18next';

import enCommon from './locales/en/common.json';
import enAuth from './locales/en/auth.json';
import enConsent from './locales/en/consent.json';
import enDevices from './locales/en/devices.json';
import enHome from './locales/en/home.json';
import enSchedule from './locales/en/schedule.json';
import enConsult from './locales/en/consult.json';
import enProfile from './locales/en/profile.json';
import enHele from './locales/en/hele.json';
import enMonitor from './locales/en/monitor.json';
import enTracker from './locales/en/tracker.json';
import enAlerts from './locales/en/alerts.json';
import enVideo from './locales/en/video.json';
import enPresenter from './locales/en/presenter.json';

import filCommon from './locales/fil/common.json';
import filAuth from './locales/fil/auth.json';
import filConsent from './locales/fil/consent.json';
import filDevices from './locales/fil/devices.json';
import filHome from './locales/fil/home.json';
import filSchedule from './locales/fil/schedule.json';
import filConsult from './locales/fil/consult.json';
import filProfile from './locales/fil/profile.json';
import filHele from './locales/fil/hele.json';
import filMonitor from './locales/fil/monitor.json';
import filTracker from './locales/fil/tracker.json';
import filAlerts from './locales/fil/alerts.json';
import filVideo from './locales/fil/video.json';
import filPresenter from './locales/fil/presenter.json';

export const LANG_KEY = 'nurturelink.lang';
export const LANGUAGES = ['en', 'fil'];

const resources = {
  en: {
    common: enCommon, auth: enAuth, consent: enConsent, devices: enDevices, home: enHome,
    schedule: enSchedule, consult: enConsult, profile: enProfile, hele: enHele, monitor: enMonitor,
    tracker: enTracker, alerts: enAlerts, video: enVideo, presenter: enPresenter,
  },
  fil: {
    common: filCommon, auth: filAuth, consent: filConsent, devices: filDevices, home: filHome,
    schedule: filSchedule, consult: filConsult, profile: filProfile, hele: filHele, monitor: filMonitor,
    tracker: filTracker, alerts: filAlerts, video: filVideo, presenter: filPresenter,
  },
};

function readSavedLanguage() {
  try {
    const saved = window.localStorage.getItem(LANG_KEY);
    return LANGUAGES.includes(saved) ? saved : 'en';
  } catch {
    return 'en';
  }
}

function applyDocumentLanguage(lng) {
  document.documentElement.lang = lng;
}

/** Switch language, remember it before sign-in (the account setting arrives in Prompt 3). */
export function setLanguage(lng) {
  if (!LANGUAGES.includes(lng)) return;
  try {
    window.localStorage.setItem(LANG_KEY, lng);
  } catch {
    /* storage unavailable: the choice still applies for this visit */
  }
  applyDocumentLanguage(lng);
  return i18next.changeLanguage(lng);
}

const initial = readSavedLanguage();
applyDocumentLanguage(initial);

i18next.use(initReactI18next).init({
  resources,
  lng: initial,
  fallbackLng: 'en',
  supportedLngs: LANGUAGES,
  ns: Object.keys(resources.en),
  defaultNS: 'common',
  interpolation: { escapeValue: false },
  react: { useSuspense: false },
});

export default i18next;
