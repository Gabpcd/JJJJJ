import { Link, useLocation } from 'react-router-dom';
import { HelpCircle } from 'lucide-react';

export function BoutonAideGlobal() {
  const location = useLocation();

  // Cacher sur les pages d'aide elles-mêmes
  if (location.pathname.startsWith('/aide')) return null;

  return (
    <Link
      to="/aide"
      aria-label="Centre d'aide"
      title="Centre d'aide"
      className="fixed bottom-24 right-4 md:bottom-6 md:right-6 z-40 h-12 w-12 rounded-full bg-primary text-primary-foreground shadow-lg hover:scale-110 transition-transform flex items-center justify-center"
    >
      <HelpCircle className="h-6 w-6" />
    </Link>
  );
}
