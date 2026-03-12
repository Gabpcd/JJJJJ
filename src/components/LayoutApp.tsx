import { useEffect } from 'react';
import { BarreNavigation } from '@/components/BarreNavigation';
import { FooterLegal } from '@/components/FooterLegal';
import { DemandePermissionPush } from '@/components/DemandePermissionPush';
import { UserRole } from '@/lib/types';
import { ecouterMessagesForeground } from '@/lib/firebase';
import { useToast } from '@/hooks/use-toast';

interface LayoutAppProps {
  role: UserRole;
  children: React.ReactNode;
}

export function LayoutApp({ role, children }: LayoutAppProps) {
  const { toast } = useToast();

  useEffect(() => {
    let unsubscribe: (() => void) | undefined;

    ecouterMessagesForeground((payload) => {
      toast({
        title: payload.title || 'Notification',
        description: payload.body,
      });
    }).then((unsub) => {
      if (typeof unsub === 'function') unsubscribe = unsub;
    });

    return () => {
      unsubscribe?.();
    };
  }, [toast]);

  return (
    <div className="min-h-screen bg-background flex flex-col">
      <BarreNavigation role={role} />
      <main className="page-container flex-1">
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
