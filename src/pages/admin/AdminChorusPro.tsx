import { usePageTitle } from '@/hooks/usePageTitle';
import { LayoutAdmin } from '@/components/LayoutAdmin';
import { BreadcrumbAdmin } from '@/components/BreadcrumbAdmin';
import { FileStack } from 'lucide-react';

export default function AdminChorusPro() {
  usePageTitle('Chorus Pro — Admin');

  return (
    <LayoutAdmin>
      <BreadcrumbAdmin items={[{ label: 'Chorus Pro' }]} />
      <div className="flex items-center gap-3 mb-6">
        <FileStack className="h-7 w-7 text-primary" />
        <h1 className="text-2xl font-bold text-foreground">Chorus Pro</h1>
      </div>
      <div className="card-base p-6 text-center">
        <p className="text-muted-foreground">
          Interface de monitoring Chorus Pro en cours de construction (C5-D.2).
        </p>
        <p className="text-xs text-muted-foreground/70 mt-2">
          Dashboard, suivi des soumissions et configuration par établissement arrivent dans la prochaine micro-passe.
        </p>
      </div>
    </LayoutAdmin>
  );
}
