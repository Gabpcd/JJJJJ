import { useEffect, useMemo } from 'react';
import { BarreNavigation } from '@/components/BarreNavigation';
import { FooterLegal } from '@/components/FooterLegal';
import { DemandePermissionPush } from '@/components/DemandePermissionPush';
import { BandeauHorsLigne } from '@/components/BandeauHorsLigne';
import { SyncHorsLigne } from '@/components/SyncHorsLigne';
import { UserRole } from '@/lib/types';
import { toast } from 'sonner';
import { Capacitor } from '@capacitor/core';

interface LayoutAppProps {
  role: UserRole;
  children: React.ReactNode;
}

export function LayoutApp({ role, children }: LayoutAppProps) {
  const isNative = useMemo(() => Capacitor.isNativePlatform(), []);

  useEffect(() => {
    let cleanup: (() => void) | undefined;

    import('@/lib/firebase').then(({ ecouterMessagesForeground }) => {
      cleanup = ecouterMessagesForeground((payload) => {
        toast.info(payload.title || 'Notification', { description: payload.body });
      });
    });

    return () => {
      cleanup?.();
    };
  }, []);

  return (
    <div className={isNative ? "h-screen flex flex-col overflow-hidden bg-background" : "flex-1 flex flex-col min-h-screen bg-background"}>
      <a href="#main-content" className="skip-to-main">Aller au contenu principal</a>
      <BandeauHorsLigne />
      <SyncHorsLigne />
      <BarreNavigation role={role} />
      <main
        id="main-content"
        role="main"
        className={isNative
          ? "flex-1 overflow-y-auto md:ml-[260px]"
          : "flex-1 md:ml-[260px]"
        }
        style={isNative ? { paddingBottom: 'calc(5rem + env(safe-area-inset-bottom))' } : { paddingBottom: '5rem' }}
      >
        <div className="max-w-6xl mx-auto px-4 py-6 md:pb-6">
          {children}
        </div>
        <FooterLegal />
      </main>
      <DemandePermissionPush />
    </div>
  );
}
