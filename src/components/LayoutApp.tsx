import { useEffect, useMemo } from 'react';
import { useLocation } from 'react-router-dom';
import { BarreNavigation } from '@/components/BarreNavigation';
import { DemandePermissionPush } from '@/components/DemandePermissionPush';
import { BandeauHorsLigne } from '@/components/BandeauHorsLigne';
import { SyncHorsLigne } from '@/components/SyncHorsLigne';
import { BandeauInstallerPWA } from '@/components/BandeauInstallerPWA';
import { BandeauOnboardingEtab } from '@/components/BandeauOnboardingEtab';
import { UserRole } from '@/lib/types';
import { toast } from 'sonner';

interface LayoutAppProps {
  role: UserRole;
  children: React.ReactNode;
  /**
   * Mode plein écran sans scroll (deck de swipe) : fige la hauteur à 100dvh,
   * retire le padding de contenu et le footer légal, pour qu'une vue
   * (carte + barre d'action) tienne dans un viewport sans scroll.
   */
  pleinEcran?: boolean;
}

// Direction de navigation (Lot 6b.1 — transitions entre écrans, pas de
// « rechargement sec ») : react-router incrémente un idx dans
// window.history.state à chaque push. idx qui recule = retour arrière.
// Module-level : survit aux remounts de LayoutApp (chaque page l'instancie).
let dernierIdxHistorique = -1;

function useDirectionNavigation(): 'forward' | 'back' | 'none' {
  const location = useLocation();
  return useMemo(() => {
    const idx = typeof (window.history.state as any)?.idx === 'number'
      ? (window.history.state as any).idx : 0;
    const precedent = dernierIdxHistorique;
    dernierIdxHistorique = idx;
    if (precedent === -1) return 'none'; // premier écran : pas d'animation
    return idx < precedent ? 'back' : 'forward';
    // eslint-disable-next-line react-hooks/exhaustive-deps
  }, [location.key]);
}

/**
 * Unified layout for Capacitor native app AND mobile Safari web.
 * Same structure, same safe-area insets, same height handling.
 * The only difference is the presence of Safari's browser chrome on web.
 */
export function LayoutApp({ role, children, pleinEcran = false }: LayoutAppProps) {
  const direction = useDirectionNavigation();
  const classeTransition =
    direction === 'forward' ? 'route-slide-forward' : direction === 'back' ? 'route-slide-back' : '';
  useEffect(() => {
    let mounted = true;
    let cleanup: (() => void) | undefined;

    import('@/lib/firebase').then(({ ecouterMessagesForeground }) => {
      if (!mounted) return;
      cleanup = ecouterMessagesForeground((payload) => {
        toast.info(payload.title || 'Notification', { description: payload.body });
      });
    });

    return () => {
      mounted = false;
      cleanup?.();
    };
  }, []);

  return (
    <div
      className="flex flex-col bg-background"
      style={pleinEcran ? { height: '100dvh', overflow: 'hidden' } : { minHeight: '100dvh' }}
    >
      <a href="#main-content" className="skip-to-main">Aller au contenu principal</a>
      <BarreNavigation role={role} />
      {/* Bandeaux + main décalés à droite de la sidebar desktop (260px).
          Bandeaux placés ICI (pas en flex-column root) pour ne PAS être
          recouverts par la sidebar fixed left-0 top-0 z-40. */}
      <div className="flex-1 md:ml-[260px] flex flex-col min-w-0 min-h-0">
        <BandeauHorsLigne />
        <SyncHorsLigne />
        {role === 'ADMIN_ETABLISSEMENT' && <BandeauOnboardingEtab />}
        <main
          id="main-content"
          role="main"
          className={`flex-1 min-w-0${pleinEcran ? ' flex flex-col min-h-0 overflow-hidden' : ''}`}
          style={{
            paddingBottom: pleinEcran
              ? 'calc(4rem + env(safe-area-inset-bottom))'
              : 'calc(5rem + env(safe-area-inset-bottom))',
          }}
        >
          {pleinEcran ? (
            <div className={`flex-1 min-h-0 min-w-0 flex flex-col px-3 pt-2 ${classeTransition}`}>
              {children}
            </div>
          ) : (
            <div className={`max-w-6xl mx-auto px-4 py-6 md:pb-6 min-w-0 ${classeTransition}`}>
              {children}
            </div>
          )}
          {/* Footer légal retiré des écrans authentifiés (Lot 6b.1) : les liens
              CGU/CGV/Mentions vivent dans Profil > Aide & légal. Le footer complet
              reste sur les pages publiques/SEO. */}
        </main>
      </div>
      <DemandePermissionPush />
      <BandeauInstallerPWA />
      {/* FAB « ? » retiré (Lot 6a.4) et FAB « Publier » retiré (Lot 11) : tout
          élément flottant finit par recouvrir un CTA (KPI, Enregistrer GPS,
          exports, contrat). Publier vit dans la nav et le dashboard. */}
    </div>
  );
}
