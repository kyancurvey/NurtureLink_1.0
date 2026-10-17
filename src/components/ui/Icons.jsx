// Small inline icons. Decorative: the text next to them carries the meaning.
function Svg({ children, size = 20 }) {
  return (
    <svg
      width={size}
      height={size}
      viewBox="0 0 24 24"
      fill="none"
      stroke="currentColor"
      strokeWidth="2.2"
      strokeLinecap="round"
      strokeLinejoin="round"
      aria-hidden="true"
      focusable="false"
      className="nl-icon"
    >
      {children}
    </svg>
  )
}

export const CheckIcon = (p) => (
  <Svg {...p}>
    <path d="M5 12.5l4.5 4.5L19 7.5" />
  </Svg>
)
export const CheckCircleIcon = (p) => (
  <Svg {...p}>
    <circle cx="12" cy="12" r="9.5" />
    <path d="M7.5 12.5l3 3 6-6.5" />
  </Svg>
)
export const AlertTriangleIcon = (p) => (
  <Svg {...p}>
    <path d="M12 3.5L2.5 20h19L12 3.5z" />
    <path d="M12 10v4.5M12 17.4v.1" />
  </Svg>
)
export const AlertOctagonIcon = (p) => (
  <Svg {...p}>
    <path d="M8 2.8h8L21.2 8v8L16 21.2H8L2.8 16V8L8 2.8z" />
    <path d="M9 9l6 6M15 9l-6 6" />
  </Svg>
)
export const InfoIcon = (p) => (
  <Svg {...p}>
    <circle cx="12" cy="12" r="9.5" />
    <path d="M12 11v6M12 7.6v.1" />
  </Svg>
)
export const CloseIcon = (p) => (
  <Svg {...p}>
    <path d="M6 6l12 12M18 6L6 18" />
  </Svg>
)
export const ChevronLeftIcon = (p) => (
  <Svg {...p}>
    <path d="M15 5l-7 7 7 7" />
  </Svg>
)
export const HomeIcon = (p) => (
  <Svg size={24} {...p}>
    <path d="M3.5 11L12 3.5 20.5 11M5.5 9.5V20h13V9.5" />
  </Svg>
)
export const ActivityIcon = (p) => (
  <Svg size={24} {...p}>
    <path d="M2.5 12h4l3-7 5 14 3-7h4" />
  </Svg>
)
export const BellIcon = (p) => (
  <Svg size={24} {...p}>
    <path d="M6 16.5V11a6 6 0 1112 0v5.5l1.5 2h-15l1.5-2zM10 21h4" />
  </Svg>
)
export const HeartIcon = (p) => (
  <Svg size={24} {...p}>
    <path d="M12 20.5S3.5 15 3.5 8.9A4.6 4.6 0 0112 7a4.6 4.6 0 018.5 1.9C20.5 15 12 20.5 12 20.5z" />
  </Svg>
)
export const UserIcon = (p) => (
  <Svg size={24} {...p}>
    <circle cx="12" cy="8" r="4" />
    <path d="M4.5 20.5c1-4 4-5.5 7.5-5.5s6.5 1.5 7.5 5.5" />
  </Svg>
)
