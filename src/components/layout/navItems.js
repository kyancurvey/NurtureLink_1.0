import { Home, CalendarDays, MessagesSquare, Sparkles, User, Activity, MessageCircle, ClipboardList } from 'lucide-react';

/** Tabs per role (spec Appendix A). `art` picks the illustration on the TEMP screens. */
export const NAV = {
  patient: [
    { path: 'home', key: 'home', icon: Home, art: 'heart' },
    { path: 'schedule', key: 'schedule', icon: CalendarDays, art: 'calendar' },
    { path: 'consult', key: 'consult', icon: MessagesSquare, art: 'chat' },
    { path: 'hele', key: 'hele', icon: Sparkles, art: 'hele' },
    { path: 'profile', key: 'profile', icon: User, art: 'shield' },
  ],
  barangay: [
    { path: 'monitor', key: 'monitor', icon: Activity, art: 'band' },
    { path: 'chat', key: 'chat', icon: MessageCircle, art: 'chat' },
    { path: 'calendar', key: 'calendar', icon: CalendarDays, art: 'calendar' },
    { path: 'profile', key: 'profile', icon: User, art: 'shield' },
  ],
  super: [
    { path: 'tracker', key: 'tracker', icon: ClipboardList, art: 'belt' },
    { path: 'consult', key: 'consult', icon: MessagesSquare, art: 'chat' },
    { path: 'schedule', key: 'schedule', icon: CalendarDays, art: 'calendar' },
    { path: 'profile', key: 'profile', icon: User, art: 'shield' },
  ],
};
