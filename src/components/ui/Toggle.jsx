/** Switch with a visible label. Controlled: pass checked and onChange(nextChecked). */
export default function Toggle({ label, checked, onChange, disabled = false }) {
  return (
    <button
      type="button"
      role="switch"
      aria-checked={checked}
      className="toggle"
      disabled={disabled}
      onClick={() => onChange(!checked)}
    >
      <span>{label}</span>
      <span className="toggle__track" aria-hidden="true">
        <span className="toggle__knob" />
      </span>
    </button>
  );
}
