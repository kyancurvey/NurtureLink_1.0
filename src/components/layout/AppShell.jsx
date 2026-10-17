import BottomTabBar from './BottomTabBar.jsx'
import Sidebar from './Sidebar.jsx'

// Wraps a page with the right navigation for the screen width. Both navs are
// in the DOM; CSS hides one (switch at 900px) so there is no resize flicker.
export default function AppShell({ tabs, sidebarFooter, children }) {
  return (
    <div className="nl-shell">
      <Sidebar tabs={tabs} footer={sidebarFooter} />
      <main className="nl-shell__main">{children}</main>
      <BottomTabBar tabs={tabs} />
    </div>
  )
}
