// Placeholder translation hook (step 1.2). It returns the key itself so the
// kit shows its i18n keys until step 1.3 adds react-i18next. In step 1.3 this
// file becomes:  import { useTranslation } from 'react-i18next'
//                export const useT = () => useTranslation().t
// and nothing else needs to change.
export function useT() {
  return (key) => key
}
