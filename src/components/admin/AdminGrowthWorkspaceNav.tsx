import { Link } from 'react-router-dom';
import { ListChecks, MapPinned, Megaphone, Target } from 'lucide-react';
import { cn } from '@/lib/utils';

export type AdminGrowthWorkspaceStep = 'opportunites' | 'cibles' | 'actions' | 'ressources';

const ETAPES = [
  {
    id: 'opportunites',
    libelle: 'Besoins externes',
    aide: 'Où la demande existe',
    route: '/admin/fondateur/acquisition',
    icone: MapPinned,
  },
  {
    id: 'cibles',
    libelle: 'Cibles à qualifier',
    aide: 'Qui ajouter à la liste',
    route: '/admin/fondateur/sales?tab=sourcing',
    icone: Target,
  },
  {
    id: 'actions',
    libelle: 'Suivi',
    aide: 'Que faire aujourd’hui',
    route: '/admin/fondateur/sales?tab=crm',
    icone: ListChecks,
  },
  {
    id: 'ressources',
    libelle: 'Ressources',
    aide: 'Canaux et contenus',
    route: '/admin/fondateur/sales?tab=groupes',
    icone: Megaphone,
  },
] as const;

interface AdminGrowthWorkspaceNavProps {
  active: AdminGrowthWorkspaceStep;
}

export function AdminGrowthWorkspaceNav({ active }: AdminGrowthWorkspaceNavProps) {
  return (
    <nav
      aria-label="Parcours de développement commercial"
      className="w-full min-w-0 max-w-full overflow-x-auto overscroll-x-contain [contain:inline-size] rounded-xl border border-border bg-muted/30 p-1"
    >
      <ol className="flex min-w-max items-center gap-1">
        {ETAPES.map((etape) => {
          const estActive = etape.id === active;
          const Icone = etape.icone;
          return (
            <li key={etape.id}>
              <Link
                to={etape.route}
                aria-current={estActive ? 'page' : undefined}
                className={cn(
                  'inline-flex min-h-[44px] items-center gap-2 rounded-lg px-3 py-2 text-sm font-medium whitespace-nowrap transition-colors',
                  'focus-visible:outline-none focus-visible:ring-2 focus-visible:ring-primary focus-visible:ring-offset-1',
                  estActive
                    ? 'bg-card text-primary shadow-sm'
                    : 'text-muted-foreground hover:bg-card/70 hover:text-foreground',
                )}
              >
                <Icone className="h-4 w-4 shrink-0" aria-hidden="true" />
                <span>{etape.libelle}</span>
                <span className="sr-only"> — {etape.aide}</span>
              </Link>
            </li>
          );
        })}
      </ol>
    </nav>
  );
}
