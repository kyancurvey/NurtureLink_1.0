import { HashRouter, Routes, Route, Navigate } from 'react-router-dom'
import { AppHeader } from './components/layout/index.js'
import Splash from './components/Splash.jsx'
import DesignPage from './features/design/DesignPage.jsx'

// HashRouter keeps deep links working on GitHub Pages, which has no
// server-side routing. Later steps add the patient and provider routes here.
// AppHeader sits above the routes so the language switch is on every screen.
// The wrapper div is what lets the sticky header stay put for the whole page
// (#root is only one screen tall).
export default function App() {
  return (
    <HashRouter>
      <div>
        <AppHeader />
        <Routes>
          <Route path="/" element={<Splash />} />
          <Route path="/design/*" element={<DesignPage />} />
          <Route path="*" element={<Navigate to="/" replace />} />
        </Routes>
      </div>
    </HashRouter>
  )
}
