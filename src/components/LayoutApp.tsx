import { createContext, Suspense, useContext, useEffect, useLayoutEffect, useMemo, useState } from 'react';
import { Outlet } from 'react-router-dom';
import { ChargementPage } from '@/components/ChargementPage';
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

// Le cadre reste monté entre deux routes ; les LayoutApp des pages ne rendent
// que leur contenu. Ainsi navigation, notifications et abonnements sont stables.
const CadreContext = createContext<{ setPleinEcran: (value: boolean) => void } | null>(null);

export function AppShell({ role }: { role: UserRole }) {
  const [pleinEcran, setPleinEcran] = useState(false);
  const contexte = useMemo(() => ({ setPleinEcran }), []);
  return (
    <CadreContext.Provider value={contexte}>
      <CadreApplication role={role} pleinEcran={pleinEcran}>
        <Suspense fallback={<ChargementPage />}><Outlet /></Suspense>
      </CadreApplication>
    </CadreContext.Provider>
  );
}

export function LayoutApp({ role, children, pleinEcran = false }: LayoutAppProps) {
  const cadre = useContext(CadreContext);
  useLayoutEffect(() => {
    if (!cadre) return;
    cadre.setPleinEcran(pleinEcran);
    return () => cadre.setPleinEcran(false);
  }, [cadre, pleinEcran]);
  const contenu = (
    <div className={pleinEcran
      ? 'flex-1 min-h-0 min-w-0 flex flex-col px-3 pt-2'
      : 'max-w-6xl mx-auto w-full px-4 py-4 md:py-6 md:pb-6 min-w-0'}>
      {children}
    </div>
  );
  return cadre ? contenu : <CadreApplication role={role} pleinEcran={pleinEcran}>{contenu}</CadreApplication>;
}

function CadreApplication({ role, children, pleinEcran = false }: LayoutAppProps) {
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
              : 'calc(6rem + env(safe-area-inset-bottom))',
          }}
        >
          {children}
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
