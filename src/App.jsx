import { HashRouter } from 'react-router-dom';
import { ToastProvider } from './components/ui/Toast.jsx';
import AppRoutes from './routes.jsx';

export default function App() {
  return (
    <HashRouter>
      <ToastProvider>
        <AppRoutes />
      </ToastProvider>
    </HashRouter>
  );
}
