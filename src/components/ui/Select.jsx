import { useId } from 'react';
import { ChevronDown, TriangleAlert } from 'lucide-react';

/** Native select (works with every phone keyboard). options: [{ value, label }] */
export default function Select({ label, hint, error, options = [], id, className = '', ...selectProps }) {
  const autoId = useId();
  const selectId = id ?? autoId;
  const hintId = hint ? `${selectId}-hint` : undefined;
  const errorId = error ? `${selectId}-error` : undefined;
  const describedBy = [hintId, errorId].filter(Boolean).join(' ') || undefined;
  return (
    <div className={['field', 'field--select', error ? 'field--error' : '', className].filter(Boolean).join(' ')}>
      <label className="field__label" htmlFor={selectId}>
        {label}
      </label>
      <div className="field__control">
        <select
          id={selectId}
          className="field__input"
          aria-invalid={error ? true : undefined}
          aria-describedby={describedBy}
          {...selectProps}
        >
          {options.map((option) => (
            <option key={option.value} value={option.value}>
              {option.label}
            </option>
          ))}
        </select>
        <ChevronDown className="field__chevron" size={20} aria-hidden="true" />
      </div>
      {hint ? (
        <p className="field__hint" id={hintId}>
          {hint}
        </p>
      ) : null}
      {error ? (
        <p className="field__error" id={errorId}>
          <TriangleAlert size={16} aria-hidden="true" />
          <span>{error}</span>
        </p>
      ) : null}
    </div>
  );
}
