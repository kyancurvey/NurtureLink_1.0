import { Outlet } from 'react-router-dom';
import TopBar from './TopBar.jsx';
import BottomTabs from './BottomTabs.jsx';
import SideNav from './SideNav.jsx';
import { NAV } from './navItems.js';

/**
 * Three layouts (COM-06): patient and barangay are a phone-width column with bottom tabs, centred on wide
 * screens; the super account has bottom tabs under 1024 px and a side navigation from 1024 px.
 */
export default function AppShell({ role }) {
  const items = NAV[role];
  const isSuper = role === 'super';
  return (
    <div className={`shell ${isSuper ? 'shell--super' : 'shell--phone'}`}>
      {isSuper ? <SideNav role={role} items={items} /> : null}
      <div className="shell__column">
        <TopBar unreadCount={0 /* TEMP: real unread count in Prompt 5 */} />
        <main className="shell__main">
          <Outlet />
        </main>
        <BottomTabs role={role} items={items} />
      </div>
    </div>
  );
}
