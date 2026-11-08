import { createContext, useCallback, useContext, useMemo, useRef, useState } from 'react';
import { STATUS_ICONS } from './statusIcons.js';

const ToastContext = createContext({ show: () => {} });

const DISMISS_AFTER_MS = 4000;

/** Wrap the app once; call useToast().show({ message, status }) from anywhere inside. */
export function ToastProvider({ children }) {
  const [toasts, setToasts] = useState([]);
  const nextId = useRef(0);

  const show = useCallback(({ message, status = 'neutral' }) => {
    const id = (nextId.current += 1);
    setToasts((current) => [...current, { id, message, status }]);
    window.setTimeout(() => {
      setToasts((current) => current.filter((toast) => toast.id !== id));
    }, DISMISS_AFTER_MS);
  }, []);

  const value = useMemo(() => ({ show }), [show]);

  return (
    <ToastContext.Provider value={value}>
      {children}
      <div className="toast-region" role="status" aria-live="polite">
        {toasts.map((toast) => {
          const Icon = STATUS_ICONS[toast.status] ?? STATUS_ICONS.neutral;
          return (
            <div className="toast" key={toast.id}>
              <Icon className="toast__icon" size={20} aria-hidden="true" />
              <span>{toast.message}</span>
            </div>
          );
        })}
      </div>
    </ToastContext.Provider>
  );
}

export function useToast() {
  return useContext(ToastContext);
}
