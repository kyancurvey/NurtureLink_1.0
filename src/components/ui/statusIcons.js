import { CircleCheck, Info, TriangleAlert, RefreshCw } from 'lucide-react';

/** Every status has an icon and a text label; colour is never the only signal. */
export const STATUS_ICONS = {
  normal: CircleCheck,
  attention: Info,
  alert: TriangleAlert,
  info: RefreshCw,
  neutral: Info,
};
