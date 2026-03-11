import { BarreNavigation } from '@/components/BarreNavigation';
import { UserRole } from '@/lib/types';

interface LayoutAppProps {
  role: UserRole;
  children: React.ReactNode;
}

export function LayoutApp({ role, children }: LayoutAppProps) {
  return (
    <div className="min-h-screen bg-background">
      <BarreNavigation role={role} />
      <main className="page-container">
        <div className="max-w-6xl mx-auto px-4 py-6">
          {children}
        </div>
      </main>
    </div>
  );
}
