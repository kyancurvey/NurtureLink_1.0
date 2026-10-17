import { HashRouter, Routes, Route, Navigate } from 'react-router-dom'
import Splash from './components/Splash.jsx'
import DesignPage from './features/design/DesignPage.jsx'

// HashRouter keeps deep links working on GitHub Pages, which has no
// server-side routing. Later steps add the patient and provider routes here.
export default function App() {
  return (
    <HashRouter>
      <Routes>
        <Route path="/" element={<Splash />} />
        <Route path="/design/*" element={<DesignPage />} />
        <Route path="*" element={<Navigate to="/" replace />} />
      </Routes>
    </HashRouter>
  )
}
