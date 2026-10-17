// variant: 'primary' (gradient) | 'secondary' (outline) | 'danger'.
// Pass already-translated text as children.
export default function Button({
  variant = 'primary',
  full = false,
  type = 'button',
  className = '',
  children,
  ...rest
}) {
  const cls = ['nl-btn', `nl-btn--${variant}`, full && 'nl-btn--full', className]
    .filter(Boolean)
    .join(' ')
  return (
    <button type={type} className={cls} {...rest}>
      {children}
    </button>
  )
}
