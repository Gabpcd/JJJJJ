import { useState } from 'react';
import { Link, useLocation } from 'react-router-dom';
import { HelpCircle, BookOpen, Mail, X } from 'lucide-react';
import { ModalContacterJolene } from '@/components/ModalContacterJolene';

export function BoutonAideGlobal() {
  const location = useLocation();
  const [open, setOpen] = useState(false);
  const [contactOpen, setContactOpen] = useState(false);

  // Cacher sur les pages d'aide elles-mêmes
  if (location.pathname.startsWith('/aide')) return null;

  return (
    <>
      {/* Menu déroulant */}
      {open && (
        <>
          <div className="fixed inset-0 z-40" onClick={() => setOpen(false)} aria-hidden="true" />
          <div className="fixed bottom-40 right-4 md:bottom-20 md:right-6 z-40 w-56 rounded-2xl border border-border bg-card shadow-xl overflow-hidden">
            <button
              onClick={() => { setOpen(false); setContactOpen(true); }}
              className="w-full flex items-center gap-3 px-4 py-3 text-sm font-medium text-foreground hover:bg-muted text-left border-b border-border"
            >
              <Mail className="h-4 w-4 text-primary" /> Contacter Jolene
            </button>
            <Link
              to="/aide"
              onClick={() => setOpen(false)}
              className="w-full flex items-center gap-3 px-4 py-3 text-sm font-medium text-foreground hover:bg-muted text-left"
            >
              <BookOpen className="h-4 w-4 text-muted-foreground" /> Centre d'aide
            </Link>
          </div>
        </>
      )}

      <button
        onClick={() => setOpen(o => !o)}
        aria-label="Aide et contact"
        title="Aide et contact"
        aria-expanded={open}
        className="fixed bottom-24 right-4 md:bottom-6 md:right-6 z-40 h-12 w-12 rounded-full bg-primary text-primary-foreground shadow-lg hover:scale-110 transition-transform flex items-center justify-center"
      >
        {open ? <X className="h-6 w-6" /> : <HelpCircle className="h-6 w-6" />}
      </button>

      <ModalContacterJolene open={contactOpen} onClose={() => setContactOpen(false)} source={`aide ${location.pathname}`} />
    </>
  );
}
