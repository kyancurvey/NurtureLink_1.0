import { useId } from 'react';

/*
 * SoftArt: eight soft, matte illustrations drawn as inline SVG (heart, belt, band, phone, calendar,
 * chat, bell, shield). Rounded forms, brand-gradient fills, a soft highlight and a ground shadow.
 * Decorative only: aria-hidden, never the sole carrier of meaning or status. No people, no images.
 */

const HEART = 'M60 102C20 74 10 46 28 28C42 15 57 22 60 36C63 22 78 15 92 28C110 46 100 74 60 102Z';

function Heart({ p }) {
  return (
    <>
      <path d={HEART} fill={`url(#${p}a)`} />
      <ellipse cx="40" cy="40" rx="10" ry="5" transform="rotate(-35 40 40)" fill="var(--surface)" opacity="0.4" />
    </>
  );
}

function Belt({ p }) {
  return (
    <>
      <path d="M22 58Q60 90 98 58" fill="none" stroke={`url(#${p}a)`} strokeWidth="24" strokeLinecap="round" />
      <path d="M26 51Q60 79 94 51" fill="none" stroke="var(--surface)" strokeWidth="5" strokeLinecap="round" opacity="0.3" />
      <rect x="43" y="60" width="34" height="28" rx="9" fill={`url(#${p}c)`} />
      <circle cx="60" cy="74" r="7" fill={`url(#${p}b)`} />
    </>
  );
}

function Band({ p }) {
  return (
    <>
      <ellipse cx="60" cy="64" rx="36" ry="28" fill="none" stroke={`url(#${p}a)`} strokeWidth="16" />
      <rect x="42" y="34" width="36" height="24" rx="8" fill={`url(#${p}b)`} />
      <path d="M49 47h6l3-7 4 14 3-7h6" fill="none" stroke="var(--surface)" strokeWidth="2.5" strokeLinecap="round" strokeLinejoin="round" />
      <ellipse cx="46" cy="40" rx="5" ry="2.5" fill="var(--surface)" opacity="0.35" />
    </>
  );
}

function Phone({ p }) {
  return (
    <>
      <rect x="35" y="12" width="50" height="92" rx="13" fill={`url(#${p}a)`} />
      <rect x="40" y="22" width="40" height="70" rx="8" fill={`url(#${p}c)`} />
      <g transform="translate(60 54) scale(0.26) translate(-60 -64)">
        <path d={HEART} fill={`url(#${p}b)`} />
      </g>
      <rect x="52" y="96" width="16" height="3" rx="1.5" fill="var(--surface)" opacity="0.6" />
    </>
  );
}

function CalendarArt({ p }) {
  return (
    <>
      <rect x="18" y="26" width="84" height="74" rx="15" fill={`url(#${p}c)`} />
      <path d="M18 46V41A15 15 0 0 1 33 26H87A15 15 0 0 1 102 41V46Z" fill={`url(#${p}a)`} />
      <rect x="35" y="16" width="7" height="17" rx="3.5" fill={`url(#${p}b)`} />
      <rect x="78" y="16" width="7" height="17" rx="3.5" fill={`url(#${p}b)`} />
      <circle cx="40" cy="64" r="6" fill="var(--lilac-400)" opacity="0.55" />
      <circle cx="60" cy="64" r="6" fill="var(--coral-400)" />
      <circle cx="80" cy="64" r="6" fill="var(--lilac-400)" opacity="0.55" />
      <circle cx="40" cy="82" r="6" fill="var(--lilac-400)" opacity="0.55" />
      <circle cx="60" cy="82" r="6" fill="var(--lilac-400)" opacity="0.55" />
    </>
  );
}

function Chat({ p }) {
  return (
    <>
      <rect x="13" y="20" width="94" height="64" rx="22" fill={`url(#${p}a)`} />
      <path d="M36 80L28 104L62 82Z" fill={`url(#${p}b)`} />
      <circle cx="40" cy="52" r="6" fill="var(--surface)" opacity="0.92" />
      <circle cx="60" cy="52" r="6" fill="var(--surface)" opacity="0.92" />
      <circle cx="80" cy="52" r="6" fill="var(--surface)" opacity="0.92" />
      <ellipse cx="34" cy="32" rx="11" ry="4.5" transform="rotate(-12 34 32)" fill="var(--surface)" opacity="0.35" />
    </>
  );
}

function Bell({ p }) {
  return (
    <>
      <circle cx="60" cy="14" r="6" fill={`url(#${p}b)`} />
      <path d="M60 18C40 18 32 33 32 50V68L21 83H99L88 68V50C88 33 80 18 60 18Z" fill={`url(#${p}a)`} />
      <circle cx="60" cy="93" r="9" fill={`url(#${p}b)`} />
      <ellipse cx="46" cy="38" rx="6" ry="11" transform="rotate(18 46 38)" fill="var(--surface)" opacity="0.35" />
    </>
  );
}

function Shield({ p }) {
  return (
    <>
      <path d="M60 12L96 26V56C96 80 80 96 60 106C40 96 24 80 24 56V26Z" fill={`url(#${p}a)`} />
      <path d="M43 58L55 70L78 46" fill="none" stroke="var(--surface)" strokeWidth="8" strokeLinecap="round" strokeLinejoin="round" />
      <ellipse cx="42" cy="34" rx="9" ry="4" transform="rotate(-20 42 34)" fill="var(--surface)" opacity="0.35" />
    </>
  );
}

const DRAWINGS = {
  heart: Heart,
  belt: Belt,
  band: Band,
  phone: Phone,
  calendar: CalendarArt,
  chat: Chat,
  bell: Bell,
  shield: Shield,
};

export const SOFT_ART_NAMES = Object.keys(DRAWINGS);

/** name: heart | belt | band | phone | calendar | chat | bell | shield. size: sm | md | lg */
export default function SoftArt({ name = 'heart', size, float = false, className = '' }) {
  const prefix = `${useId().replace(/:/g, '')}-`;
  const Drawing = DRAWINGS[name] ?? Heart;
  const classes = ['softart', size ? `softart--${size}` : '', float ? 'softart--float' : '', className]
    .filter(Boolean)
    .join(' ');
  return (
    <svg className={classes} viewBox="0 0 120 120" aria-hidden="true" focusable="false">
      <defs>
        <linearGradient id={`${prefix}a`} x1="0" y1="0" x2="1" y2="1">
          <stop offset="0" stopColor="var(--coral-400)" />
          <stop offset="0.5" stopColor="var(--lilac-400)" />
          <stop offset="1" stopColor="var(--primary-600)" />
        </linearGradient>
        <linearGradient id={`${prefix}b`} x1="0" y1="0" x2="1" y2="1">
          <stop offset="0" stopColor="var(--lilac-400)" />
          <stop offset="1" stopColor="var(--primary-600)" />
        </linearGradient>
        <linearGradient id={`${prefix}c`} x1="0" y1="0" x2="0" y2="1">
          <stop offset="0" stopColor="var(--surface)" />
          <stop offset="1" stopColor="var(--primary-100)" />
        </linearGradient>
        <radialGradient id={`${prefix}s`}>
          <stop offset="0" stopColor="var(--primary-600)" stopOpacity="0.28" />
          <stop offset="1" stopColor="var(--primary-600)" stopOpacity="0" />
        </radialGradient>
      </defs>
      <ellipse cx="60" cy="110" rx="34" ry="6" fill={`url(#${prefix}s)`} />
      <Drawing p={prefix} />
    </svg>
  );
}
