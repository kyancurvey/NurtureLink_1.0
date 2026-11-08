/** Raised, matte surface. `interactive` adds the press-and-lift; pass onClick or render as a link/button. */
export default function Card({ as: Tag = 'div', interactive = false, flush = false, className = '', children, ...rest }) {
  const classes = ['card', interactive ? 'card--interactive' : '', flush ? 'card--flush' : '', className]
    .filter(Boolean)
    .join(' ');
  return (
    <Tag className={classes} {...rest}>
      {children}
    </Tag>
  );
}
