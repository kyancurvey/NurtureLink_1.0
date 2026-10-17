import { StrictMode } from 'react'
import { createRoot } from 'react-dom/client'
import './styles/tokens.css'
import './styles/app.css'
import './styles/components.css'
import './features/design/design.css'
import './lib/i18n.js' // starts i18n before the first render
import App from './App.jsx'
import './lib/supabase.js' // loads the client at startup so a missing-config warning shows

createRoot(document.getElementById('root')).render(
  <StrictMode>
    <App />
  </StrictMode>,
)
