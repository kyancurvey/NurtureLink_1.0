export default function Card({ title, as: Tag = 'section', className = '', children }) {
  return (
    <Tag className={`nl-card ${className}`.trim()}>
      {title && <h2 className="nl-card__title">{title}</h2>}
      {children}
    </Tag>
  )
}
