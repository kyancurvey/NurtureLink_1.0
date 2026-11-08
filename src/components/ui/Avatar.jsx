import SoftArt from './SoftArt.jsx';

function initialsOf(name = '') {
  const parts = name.trim().split(/\s+/).filter(Boolean);
  if (parts.length === 0) return '';
  const first = parts[0][0];
  const last = parts.length > 1 ? parts[parts.length - 1][0] : '';
  return `${first}${last}`.toUpperCase();
}

function toneOf(name = '') {
  let sum = 0;
  for (const char of name) sum += char.codePointAt(0);
  return sum % 3;
}

/** Drawn avatar: initials on a soft tint, or a SoftArt illustration. Never a photograph. size: sm | md | lg */
export default function Avatar({ name = '', illustration, size = 'md' }) {
  const classes = ['avatar', `avatar--${size}`, `avatar--tone-${toneOf(name)}`].join(' ');
  return (
    <span className={classes} role="img" aria-label={name || undefined} aria-hidden={name ? undefined : true}>
      {illustration ? (
        <SoftArt name={illustration} className="avatar__art" />
      ) : (
        <span aria-hidden="true">{initialsOf(name)}</span>
      )}
    </span>
  );
}
