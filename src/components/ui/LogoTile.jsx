import Logo from './Logo.jsx';

/** White rounded tile so the cut-out figure stays white on tinted or purple surfaces. size: sm | md | lg */
export default function LogoTile({ size = 'md', float = false, alt = '' }) {
  const classes = ['logo-tile', `logo-tile--${size}`, float ? 'logo-tile--float' : ''].filter(Boolean).join(' ');
  return (
    <span className={classes}>
      <Logo alt={alt} />
    </span>
  );
}
