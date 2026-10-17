import { HeartIcon } from './Icons.jsx'

// Placeholder for a screen that has nothing to show yet. Icon plus text.
// Pass already-translated text. Optional children go under the text.
export default function EmptyState({ title, body, children }) {
  return (
    <div className="nl-empty">
      <HeartIcon size={40} />
      <h2 className="nl-empty__title">{title}</h2>
      {body && <p className="nl-empty__body">{body}</p>}
      {children}
    </div>
  )
}
