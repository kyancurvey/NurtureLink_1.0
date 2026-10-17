import BottomTabBar from './BottomTabBar.jsx'
import Sidebar from './Sidebar.jsx'

// Wraps a page with the right navigation for the screen width. Both navs are
// in the DOM; CSS hides one (switch at 900px) so there is no resize flicker.
// phoneTabs is optional: when a role has more tabs than fit in a phone tab bar
// (the provider has seven), pass the shorter list here. Default: same as tabs.
export default function AppShell({ tabs, phoneTabs, sidebarFooter, children }) {
  return (
    <div className="nl-shell">
      <Sidebar tabs={tabs} footer={sidebarFooter} />
      <main className="nl-shell__main">{children}</main>
      <BottomTabBar tabs={phoneTabs ?? tabs} />
    </div>
  )
}
