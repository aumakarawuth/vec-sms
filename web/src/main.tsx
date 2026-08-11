import { StrictMode } from 'react';
import { createRoot } from 'react-dom/client';
import { App } from './app';
import { SessionProvider } from './core/session';
import './ui/styles.css';

const root = document.getElementById('root');
if (!root) throw new Error('ไม่พบ #root ใน index.html');

createRoot(root).render(
  <StrictMode>
    <SessionProvider>
      <App />
    </SessionProvider>
  </StrictMode>,
);
