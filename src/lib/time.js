// Locale helpers. Times are always Asia/Manila, 12-hour, formatted through Intl (CLAUDE.md, Locale).
export const TIME_ZONE = 'Asia/Manila';

const LOCALES = { en: 'en-PH', fil: 'fil-PH' };

/** Date and time for the top bar, for example { date: 'Sun, Nov 8', time: '3:45 pm' }. */
export function formatManilaNow(date, lang = 'en') {
  const locale = LOCALES[lang] ?? LOCALES.en;
  const day = new Intl.DateTimeFormat(locale, {
    timeZone: TIME_ZONE,
    weekday: 'short',
    month: 'short',
    day: 'numeric',
  }).format(date);
  const time = new Intl.DateTimeFormat(locale, {
    timeZone: TIME_ZONE,
    hour: 'numeric',
    minute: '2-digit',
    hour12: true,
  }).format(date);
  return { date: day, time, label: `${day}, ${time}` };
}
