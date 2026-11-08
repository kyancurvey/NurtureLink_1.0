import Logo from './Logo.jsx';

/** Hele AI's profile picture: the logo emblem in a round white frame with a gradient ring. size: sm | md | lg */
export default function HeleAvatar({ size = 'md', alt = 'Hele AI' }) {
  return (
    <span className={`hele-avatar avatar--${size}`}>
      <span className="hele-avatar__face">
        <Logo alt={alt} />
      </span>
    </span>
  );
}
