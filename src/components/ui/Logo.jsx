import { asset } from '../../lib/assets.js';

/** The supplied logo, used unchanged (never recoloured or cropped). Decorative unless `alt` is given. */
export default function Logo({ size, alt = '', className = '' }) {
  const classes = ['logo', size ? `logo--${size}` : '', className].filter(Boolean).join(' ');
  return <img className={classes} src={asset('logo.png')} width="512" height="503" alt={alt} draggable="false" />;
}
