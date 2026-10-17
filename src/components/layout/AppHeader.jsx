import LanguageToggle from '../ui/LanguageToggle.jsx'
import Button from '../ui/Button.jsx'
import { useT } from '../../lib/useT.js'
import { useAuth } from '../../lib/auth.jsx'

// Slim top bar rendered once in App.jsx, above every route, so the language
// switch (and, when signed in, Log out) is on every screen.
export default function AppHeader() {
  const t = useT()
  const { session, signOut } = useAuth()
  return (
    <header className="nl-appheader">
      <LanguageToggle />
      {session && (
        <Button variant="secondary" onClick={signOut}>
          {t('auth:logout')}
        </Button>
      )}
    </header>
  )
}
