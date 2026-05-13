/**
 * Banner d'avertissement smartphone admin Sprint 8 PR 6 (chantier 6.3).
 *
 * Affiché uniquement sur smartphone < 640px (sm).
 * Dismissible avec localStorage (`jolene_banner_admin_mobile_ferme`).
 * Sprint 8.5 traitera l'admin mobile-first complet.
 */
import { useEffect, useState } from 'react';
import { Info, X } from 'lucide-react';

const CLE_STORAGE = 'jolene_banner_admin_mobile_ferme';
const BREAKPOINT_SMARTPHONE = 640;

export function BannerAdminMobile() {
  const [visible, setVisible] = useState(false);

  useEffect(() => {
    const verifierAffichage = () => {
      if (typeof window === 'undefined') return;
      const dejaFerme = window.localStorage.getItem(CLE_STORAGE) === '1';
      const estSmartphone = window.innerWidth < BREAKPOINT_SMARTPHONE;
      setVisible(!dejaFerme && estSmartphone);
    };
    verifierAffichage();
    const onResize = () => verifierAffichage();
    window.addEventListener('resize', onResize, { passive: true });
    return () => window.removeEventListener('resize', onResize);
  }, []);

  const fermer = () => {
    try {
      window.localStorage.setItem(CLE_STORAGE, '1');
    } catch {
      /* localStorage indisponible (privacy mode) — fermeture juste pour la session */
    }
    setVisible(false);
  };

  if (!visible) return null;

  return (
    <div
      role="status"
      aria-live="polite"
      className="mb-4 flex items-start gap-3 rounded-xl border border-warning/30 bg-warning/5 p-3"
    >
      <Info className="h-5 w-5 text-warning flex-shrink-0 mt-0.5" aria-hidden="true" />
      <div className="flex-1 min-w-0">
        <p className="text-sm font-semibold text-foreground">
          Vue admin optimisée pour ordinateur
        </p>
        <p className="text-xs text-muted-foreground mt-0.5">
          Toutes les actions restent disponibles. Sprint 8.5 améliorera
          l'expérience mobile admin.
        </p>
      </div>
      <button
        type="button"
        onClick={fermer}
        aria-label="Fermer l'avertissement"
        className="flex-shrink-0 p-1 text-muted-foreground hover:text-foreground rounded focus:outline-none focus-visible:ring-2 focus-visible:ring-primary min-h-[24px] min-w-[24px] flex items-center justify-center"
      >
        <X className="h-4 w-4" aria-hidden="true" />
      </button>
    </div>
  );
}

export default BannerAdminMobile;
