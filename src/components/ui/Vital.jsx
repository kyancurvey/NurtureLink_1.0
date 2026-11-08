/** A reading: Roboto, fixed-width numerals, 24 px or larger, with a smaller unit. */
export default function Vital({ label, value, unit }) {
  return (
    <div className="vital">
      {label ? <span className="vital__label">{label}</span> : null}
      <span className="vital__reading">
        <span className="vital__value">{value}</span>
        {unit ? <span className="vital__unit">{unit}</span> : null}
      </span>
    </div>
  );
}
