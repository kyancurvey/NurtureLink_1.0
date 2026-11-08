/** variant: primary | secondary (calm, non-clinical actions only) | ghost */
export default function Button({
  variant = 'primary',
  block = false,
  loading = false,
  type = 'button',
  disabled = false,
  className = '',
  children,
  ...rest
}) {
  const classes = ['btn', `btn--${variant}`, block ? 'btn--block' : '', className].filter(Boolean).join(' ');
  return (
    <button type={type} className={classes} disabled={disabled || loading} aria-busy={loading || undefined} {...rest}>
      {loading ? <span className="btn__spinner" aria-hidden="true" /> : null}
      {children}
    </button>
  );
}
