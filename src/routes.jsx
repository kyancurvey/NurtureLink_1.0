import { Navigate, Route, Routes } from 'react-router-dom';
import Splash from './components/layout/Splash.jsx';
import AppShell from './components/layout/AppShell.jsx';
import TempPage from './components/layout/TempPage.jsx';
import TempSignIn from './components/layout/TempSignIn.jsx';
import { NAV } from './components/layout/navItems.js';

export default function AppRoutes() {
  return (
    <Routes>
      <Route path="/" element={<Splash />} />
      <Route path="/sign-in" element={<TempSignIn /> /* TEMP: real sign-in in Prompt 3 */} />
      {/* TEMP: each role is reached directly at #/patient/home, #/barangay/monitor and #/super/tracker until the guards arrive in Prompt 3. */}
      {Object.entries(NAV).map(([role, items]) => (
        <Route key={role} path={`/${role}`} element={<AppShell role={role} />}>
          <Route index element={<Navigate to={items[0].path} replace />} />
          {items.map((item) => (
            <Route key={item.path} path={item.path} element={<TempPage titleKey={`nav.${item.key}`} art={item.art} />} />
          ))}
        </Route>
      ))}
      <Route path="*" element={<Navigate to="/" replace />} />
    </Routes>
  );
}
