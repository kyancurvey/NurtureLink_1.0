// The whole row is the touch target (44px minimum).
export default function Checkbox({ label, className = '', ...rest }) {
  return (
    <label className={`nl-check ${className}`.trim()}>
      <input type="checkbox" className="nl-check__box" {...rest} />
      <span>{label}</span>
    </label>
  )
}
