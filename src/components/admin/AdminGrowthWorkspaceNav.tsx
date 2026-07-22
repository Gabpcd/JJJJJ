import { Link } from 'react-router-dom';
import { ListChecks, MapPinned, Megaphone, Target } from 'lucide-react';
import { cn } from '@/lib/utils';

export type AdminGrowthWorkspaceStep = 'opportunites' | 'cibles' | 'actions' | 'ressources';

const ETAPES = [
  {
    id: 'opportunites',
    numero: '1',
    libelle: 'Opportunités',
    aide: 'Où prospecter',
    route: '/admin/fondateur/acquisition',
    icone: MapPinned,
  },
  {
    id: 'cibles',
    numero: '2',
    libelle: 'Cibles',
    aide: 'Qui qualifier',
    route: '/admin/fondateur/sales?tab=sourcing',
    icone: Target,
  },
  {
    id: 'actions',
    numero: '3',
    libelle: 'Actions',
    aide: 'Que faire aujourd’hui',
    route: '/admin/fondateur/sales?tab=crm',
    icone: ListChecks,
  },
  {
    id: 'ressources',
    numero: '4',
    libelle: 'Canaux',
    aide: 'Contenus et relais',
    route: '/admin/fondateur/sales?tab=groupes',
    icone: Megaphone,
  },
] as const;

interface AdminGrowthWorkspaceNavProps {
  active: AdminGrowthWorkspaceStep;
}

export function AdminGrowthWorkspaceNav({ active }: AdminGrowthWorkspaceNavProps) {
  return (
    <nav aria-label="Parcours de développement commercial">
      <ol className="grid gap-2 sm:grid-cols-2 xl:grid-cols-4">
        {ETAPES.map((etape) => {
          const estActive = etape.id === active;
          const Icone = etape.icone;
          return (
            <li key={etape.id}>
              <Link
                to={etape.route}
                aria-current={estActive ? 'step' : undefined}
                className={cn(
                  'flex min-h-[64px] items-center gap-3 rounded-xl border px-3 py-2 text-left transition-colors',
                  'focus-visible:outline-none focus-visible:ring-2 focus-visible:ring-primary focus-visible:ring-offset-2',
                  estActive
                    ? 'border-primary bg-primary/10 text-foreground shadow-sm'
                    : 'border-border bg-card text-muted-foreground hover:border-primary/40 hover:bg-muted/50 hover:text-foreground',
                )}
              >
                <span
                  className={cn(
                    'flex h-9 w-9 shrink-0 items-center justify-center rounded-full text-sm font-bold',
                    estActive ? 'bg-primary text-primary-foreground' : 'bg-muted text-foreground',
                  )}
                  aria-hidden="true"
                >
                  {etape.numero}
                </span>
                <span className="min-w-0 flex-1">
                  <span className="flex items-center gap-1.5 font-semibold">
                    <Icone className="h-4 w-4" aria-hidden="true" /> {etape.libelle}
                  </span>
                  <span className="block text-sm">{etape.aide}</span>
                </span>
              </Link>
            </li>
          );
        })}
      </ol>
    </nav>
  );
}
