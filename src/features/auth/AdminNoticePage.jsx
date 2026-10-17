import { Toast } from '../../components/ui/index.js'
import { useT } from '../../lib/useT.js'
import AuthLayout from './AuthLayout.jsx'

// The admin (project owner) works in the Supabase SQL Editor, not in the app.
// This page only stops an admin login from ending in a loop or a blank screen.
export default function AdminNoticePage() {
  const t = useT()
  return (
    <AuthLayout title={t('auth:admin.title')}>
      <Toast variant="info">{t('auth:admin.body')}</Toast>
    </AuthLayout>
  )
}
