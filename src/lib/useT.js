import { useTranslation } from 'react-i18next'

// Translation hook used across the UI kit. Returns react-i18next's t function,
// which re-renders the component when the language changes.
// Default namespace is "common". For others use a prefix: t('patient:tabs.home').
export function useT() {
  return useTranslation().t
}
