/** Loading placeholder block. width and height accept any CSS length or token, e.g. "60%" or "var(--space-6)". */
export default function Skeleton({ width, height, round = false }) {
  const style = {};
  if (width) style['--skeleton-w'] = width;
  if (height) style['--skeleton-h'] = height;
  return <span className={`skeleton${round ? ' skeleton--round' : ''}`} style={style} aria-hidden="true" />;
}
