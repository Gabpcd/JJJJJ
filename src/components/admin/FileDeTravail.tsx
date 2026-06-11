import { ReactNode, useState } from 'react';
import { ChevronDown, CheckCircle2, History } from 'lucide-react';
import { EmptyState } from '@/components/ui/EmptyState';
import { cn } from '@/lib/utils';

/**
 * Pattern « file de travail » (Session D) : ce qui demande une action admin
 * apparaît en premier, le reste est relégué dans un historique replié.
 *
 * Usage :
 *   <FileDeTravail
 *     nbATraiter={aTraiter.length}
 *     aTraiter={aTraiter.map(x => <Carte … />)}
 *     nbHistorique={historique.length}
 *     historique={historique.map(x => <Carte … />)}
 *   />
 *
 * Les pages gardent leurs filtres/chips existants à l'intérieur des sections
 * si besoin — ce composant ne gère que la structure macro (priorité + repli).
 */
export function FileDeTravail({
  nbATraiter,
  aTraiter,
  nbHistorique,
  historique,
  labelATraiter = 'À traiter',
  labelHistorique = 'Historique',
  titreVide = 'Tout est traité',
  descriptionVide = 'Aucune action en attente sur cette page.',
  iconeVide,
  className,
}: {
  nbATraiter: number;
  aTraiter: ReactNode;
  nbHistorique: number;
  historique: ReactNode;
  labelATraiter?: string;
  labelHistorique?: string;
  titreVide?: string;
  descriptionVide?: string;
  iconeVide?: ReactNode;
  className?: string;
}) {
  const [historiqueOuvert, setHistoriqueOuvert] = useState(false);

  return (
    <div className={cn('space-y-6', className)}>
      {/* ── Section « À traiter » : toujours visible, en tête ── */}
      <section aria-label={labelATraiter}>
        <h2 className="flex items-center gap-2 text-sm font-bold text-foreground mb-3">
          {nbATraiter > 0 ? (
            <span className="inline-flex items-center justify-center min-w-5 h-5 px-1.5 rounded-full bg-destructive text-destructive-foreground text-[11px] font-bold">
              {nbATraiter}
            </span>
          ) : (
            <CheckCircle2 className="h-4 w-4 text-emerald-500" />
          )}
          {labelATraiter}
        </h2>
        {nbATraiter === 0 ? (
          <EmptyState
            icone={iconeVide ?? <CheckCircle2 />}
            titre={titreVide}
            description={descriptionVide}
            variant="success"
          />
        ) : (
          aTraiter
        )}
      </section>

      {/* ── Section « Historique » : repliée par défaut ── */}
      {nbHistorique > 0 && (
        <section aria-label={labelHistorique}>
          <button
            type="button"
            onClick={() => setHistoriqueOuvert(o => !o)}
            aria-expanded={historiqueOuvert}
            className="flex items-center gap-2 text-sm font-semibold text-muted-foreground hover:text-foreground transition-colors mb-3"
          >
            <History className="h-4 w-4" />
            {labelHistorique}
            <span className="inline-flex items-center justify-center min-w-5 h-5 px-1.5 rounded-full bg-muted text-muted-foreground text-[11px] font-semibold">
              {nbHistorique}
            </span>
            <ChevronDown className={cn('h-4 w-4 transition-transform', historiqueOuvert && 'rotate-180')} />
          </button>
          {historiqueOuvert && historique}
        </section>
      )}
    </div>
  );
}
