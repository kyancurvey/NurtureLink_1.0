// Turns any error from Supabase into calm, translated text.
//
//   const { text, detail } = friendlyError(t, error)
//
// "detail" is only filled for permission problems. It holds the database's own
// words (for example: permission denied for table profiles) so a missing grant
// or policy is easy to spot. Nothing else is shown raw to the person.
//
// Errors come in three shapes:
//  - our own database functions raise short codes as the message
//    (not_signed_in, invalid_invite, ...),
//  - Supabase Auth gives a "code" (invalid_credentials, ...) and a status,
//  - the Data API gives a Postgres code ("42501" = permission denied).
export function friendlyError(t, error) {
  const message = String(error?.message ?? '')
  const code = String(error?.code ?? error?.error_code ?? '')
  const status = Number(error?.status ?? 0)

  // 1. Codes raised by our own functions and triggers (migrations 002, 008, 009).
  switch (message) {
    case 'not_signed_in':
      return { text: t('errors:not_signed_in') }
    case 'no_profile':
      return { text: t('errors:no_profile') }
    case 'not_eligible':
      return { text: t('errors:not_eligible') }
    case 'invalid_invite':
      return { text: t('errors:invalid_invite') }
    case 'invalid_language':
      return { text: t('errors:invalid_language') }
    case 'role_change_not_allowed':
      return { text: t('errors:role_change_not_allowed') }
    // Migration 008: a reading dated more than 5 minutes ahead of the server clock.
    case 'reading_time_in_future':
      return { text: t('errors:reading_time_in_future') }
    // Migration 009: a second SOS within 5 minutes of the patient's last one.
    case 'sos_rate_limited':
      return { text: t('errors:sos_rate_limited') }
    default:
      break
  }

  // 2. Supabase Auth codes.
  switch (code) {
    case 'invalid_credentials':
      return { text: t('errors:invalid_credentials') }
    case 'email_not_confirmed':
      return { text: t('errors:email_not_confirmed') }
    case 'user_already_exists':
    case 'email_exists':
      return { text: t('errors:account_exists') }
    case 'weak_password':
      return { text: t('errors:weak_password') }
    case 'same_password':
      return { text: t('errors:same_password') }
    case 'email_address_not_authorized':
      return { text: t('errors:email_not_authorized') }
    case 'over_email_send_rate_limit':
      return { text: t('errors:email_rate_limit') }
    case 'over_request_rate_limit':
      return { text: t('errors:rate_limit') }
    case 'session_not_found':
    case 'refresh_token_not_found':
    case 'session_expired':
      return { text: t('errors:not_signed_in') }
    default:
      break
  }
  if (status === 429) return { text: t('errors:rate_limit') }

  // 3. Missing grant or row rule: Postgres 42501, or the words themselves.
  if (code === '42501' || /permission denied|row-level security/i.test(message)) {
    return { text: t('errors:permission_denied'), detail: message }
  }

  // 4. Cannot reach the server.
  if (
    error?.name === 'AuthRetryableFetchError' ||
    /failed to fetch|networkerror|load failed/i.test(message) ||
    (typeof navigator !== 'undefined' && navigator.onLine === false)
  ) {
    return { text: t('errors:offline') }
  }

  return { text: t('errors:unknown') }
}
