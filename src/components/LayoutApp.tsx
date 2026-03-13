import { useEffect } from 'react';
import { BarreNavigation } from '@/components/BarreNavigation';
import { FooterLegal } from '@/components/FooterLegal';
import { DemandePermissionPush } from '@/components/DemandePermissionPush';
import { BandeauHorsLigne } from '@/components/BandeauHorsLigne';
import { SyncHorsLigne } from '@/components/SyncHorsLigne';
import { UserRole } from '@/lib/types';
import { useToast } from '@/hooks/use-toast';

interface LayoutAppProps {
  role: UserRole;
  children: React.ReactNode;
}

export function LayoutApp({ role, children }: LayoutAppProps) {
  const { toast } = useToast();

  useEffect(() => {
    let cleanup: (() => void) | undefined;

    // Lazy import — no Firebase SDK at module level
    import('@/lib/firebase').then(({ ecouterMessagesForeground }) => {
      cleanup = ecouterMessagesForeground((payload) => {
        toast({
          title: payload.title || 'Notification',
          description: payload.body,
        });
      });
    });

    return () => {
      cleanup?.();
    };
  }, [toast]);

  return (
    <div className="min-h-screen bg-background flex flex-col">
      <a href="#main-content" className="skip-to-main">Aller au contenu principal</a>
      <BandeauHorsLigne />
      <SyncHorsLigne />
      <BarreNavigation role={role} />
      <main id="main-content" role="main" className="page-container flex-1">
        <div className="max-w-6xl mx-auto px-4 py-6">
          {children}
        </div>
      </main>
      <div className="page-container">
        <FooterLegal />
      </div>
      <DemandePermissionPush />
    </div>
  );
}
