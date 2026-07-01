import { useEffect } from 'react';
import { BarreNavigation } from '@/components/BarreNavigation';
import { FooterLegal } from '@/components/FooterLegal';
import { DemandePermissionPush } from '@/components/DemandePermissionPush';
import { BandeauHorsLigne } from '@/components/BandeauHorsLigne';
import { SyncHorsLigne } from '@/components/SyncHorsLigne';
import { BandeauInstallerPWA } from '@/components/BandeauInstallerPWA';
import { BandeauOnboardingEtab } from '@/components/BandeauOnboardingEtab';
import { BoutonAideGlobal } from '@/components/BoutonAideGlobal';
import { FABCreerMission } from '@/components/FABCreerMission';
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

/**
 * Unified layout for Capacitor native app AND mobile Safari web.
 * Same structure, same safe-area insets, same height handling.
 * The only difference is the presence of Safari's browser chrome on web.
 */
export function LayoutApp({ role, children, pleinEcran = false }: LayoutAppProps) {
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
            <div className="flex-1 min-h-0 min-w-0 flex flex-col px-3 pt-2">
              {children}
            </div>
          ) : (
            <div className="max-w-6xl mx-auto px-4 py-6 md:pb-6 min-w-0">
              {children}
            </div>
          )}
          {!pleinEcran && <FooterLegal variant="restreint" />}
        </main>
      </div>
      <DemandePermissionPush />
      <BandeauInstallerPWA />
      <BoutonAideGlobal />
      {/* FAB "Publier une mission" : action n°1 étab, toujours visible mobile */}
      {role === 'ADMIN_ETABLISSEMENT' && <FABCreerMission />}
    </div>
  );
}
