import { BarreNavigation } from '@/components/BarreNavigation';
import { FooterLegal } from '@/components/FooterLegal';
import { UserRole } from '@/lib/types';

interface LayoutAppProps {
  role: UserRole;
  children: React.ReactNode;
}

export function LayoutApp({ role, children }: LayoutAppProps) {
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
    </div>
  );
}
