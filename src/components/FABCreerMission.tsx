import { Plus } from 'lucide-react';
import { useNavigate, useLocation } from 'react-router-dom';

/**
 * Bouton flottant "Publier une mission" — l'action n°1 d'un établissement,
 * toujours visible (mobile) au lieu d'être cachée dans le menu.
 * Positionné au-dessus de la bottom nav + du bouton d'aide pour éviter les
 * collisions. Masqué sur la page de création elle-même.
 */
export function FABCreerMission() {
  const navigate = useNavigate();
  const location = useLocation();

  // Ne pas afficher sur la page de création (redondant)
  if (location.pathname.startsWith('/etablissement/missions/creer')) return null;

  return (
    <button
      onClick={() => navigate('/etablissement/missions/creer')}
      className="md:hidden fixed right-4 z-40 bg-primary text-primary-foreground rounded-full h-14 pl-4 pr-5 shadow-xl flex items-center gap-2 hover:scale-105 active:scale-95 transition-transform font-semibold"
      style={{ bottom: 'calc(4rem + env(safe-area-inset-bottom) + 4.5rem)' }}
      aria-label="Publier une mission"
    >
      <Plus className="h-6 w-6" />
      <span className="text-sm">Publier</span>
    </button>
  );
}
