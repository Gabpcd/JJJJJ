import { Clock, Banknote, XCircle, Percent, Layers, CheckCircle2 } from 'lucide-react';
import { format } from 'date-fns';
import { fr } from 'date-fns/locale';

interface Props {
  /** Payload jsonb stocké dans litiges.payload_modifications après résolution Sprint 3.5 */
  payload: any;
}

const TYPES_INFO: Record<string, { titre: string; icone: typeof Clock; couleur: string }> = {
  HORAIRES: { titre: 'Modification des horaires', icone: Clock, couleur: 'text-info' },
  MONTANT: { titre: 'Ajustement du montant', icone: Banknote, couleur: 'text-warning' },
  ANNULATION: { titre: 'Annulation totale', icone: XCircle, couleur: 'text-destructive' },
  ANNULATION_TOTALE: { titre: 'Annulation totale', icone: XCircle, couleur: 'text-destructive' },
  COMPENSATION: { titre: 'Compensation partielle', icone: Percent, couleur: 'text-warning' },
  COMPENSATION_PARTIELLE: { titre: 'Compensation partielle', icone: Percent, couleur: 'text-warning' },
  MIXTE: { titre: 'Modification mixte', icone: Layers, couleur: 'text-primary' },
  SIMPLE: { titre: 'Accord simple', icone: CheckCircle2, couleur: 'text-success' },
  ACCORD_SANS_MODIFICATION: { titre: 'Accord sans modification', icone: CheckCircle2, couleur: 'text-success' },
};

function formatEur(v: any): string {
  const n = Number(v);
  if (isNaN(n)) return '—';
  return new Intl.NumberFormat('fr-FR', { style: 'currency', currency: 'EUR' }).format(n);
}

function formatDateTime(s: any): string {
  if (!s) return '—';
  try { return format(new Date(s), "d MMM yyyy 'à' HH:mm", { locale: fr }); }
  catch { return String(s); }
}

/**
 * Affiche le détail du payload d'accord exécuté Sprint 3.5 dans le fil litige.
 *
 * Sprint 6 PR 7 — Fix P1-8 audit Sprint 5.
 *
 * Décompose les 6 types Sprint 3.5 : HORAIRES, MONTANT, ANNULATION, COMPENSATION,
 * MIXTE, SIMPLE. Format lisible humain avec icônes + couleurs sémantiques.
 */
export function PayloadAccordExecute({ payload }: Props) {
  if (!payload || typeof payload !== 'object') return null;

  const type: string = payload.type || payload.type_modification || 'SIMPLE';
  const info = TYPES_INFO[type] || TYPES_INFO.SIMPLE;
  const Icone = info.icone;

  return (
    <div className="rounded-xl border border-border bg-card p-4 space-y-3">
      <div className="flex items-start gap-2">
        <Icone className={`h-5 w-5 ${info.couleur} shrink-0 mt-0.5`} />
        <div>
          <p className="text-sm font-semibold text-foreground">{info.titre}</p>
          {payload.motif && <p className="text-xs text-muted-foreground mt-0.5">{payload.motif}</p>}
        </div>
      </div>

      <dl className="grid grid-cols-1 sm:grid-cols-2 gap-x-4 gap-y-2 text-xs">
        {/* Horaires */}
        {payload.ancien_horaire_debut && (
          <div>
            <dt className="text-muted-foreground">Ancien horaire début</dt>
            <dd className="font-medium">{formatDateTime(payload.ancien_horaire_debut)}</dd>
          </div>
        )}
        {payload.nouveau_horaire_debut && (
          <div>
            <dt className="text-muted-foreground">Nouvel horaire début</dt>
            <dd className="font-medium text-success">{formatDateTime(payload.nouveau_horaire_debut)}</dd>
          </div>
        )}
        {payload.ancien_horaire_fin && (
          <div>
            <dt className="text-muted-foreground">Ancien horaire fin</dt>
            <dd className="font-medium">{formatDateTime(payload.ancien_horaire_fin)}</dd>
          </div>
        )}
        {payload.nouveau_horaire_fin && (
          <div>
            <dt className="text-muted-foreground">Nouvel horaire fin</dt>
            <dd className="font-medium text-success">{formatDateTime(payload.nouveau_horaire_fin)}</dd>
          </div>
        )}

        {/* Montants */}
        {payload.ancien_montant != null && (
          <div>
            <dt className="text-muted-foreground">Ancien montant</dt>
            <dd className="font-medium">{formatEur(payload.ancien_montant)}</dd>
          </div>
        )}
        {payload.nouveau_montant != null && (
          <div>
            <dt className="text-muted-foreground">Nouveau montant</dt>
            <dd className="font-medium text-success">{formatEur(payload.nouveau_montant)}</dd>
          </div>
        )}

        {/* Compensation */}
        {payload.pourcentage_compensation != null && (
          <div>
            <dt className="text-muted-foreground">Compensation</dt>
            <dd className="font-medium">{payload.pourcentage_compensation} %</dd>
          </div>
        )}
        {payload.montant_compensation != null && (
          <div>
            <dt className="text-muted-foreground">Montant compensation</dt>
            <dd className="font-medium text-success">{formatEur(payload.montant_compensation)}</dd>
          </div>
        )}

        {/* Annulation */}
        {payload.indemnite_annulation != null && (
          <div>
            <dt className="text-muted-foreground">Indemnité annulation</dt>
            <dd className="font-medium">{formatEur(payload.indemnite_annulation)}</dd>
          </div>
        )}
      </dl>

      {payload.executee_le && (
        <p className="text-[11px] text-muted-foreground italic pt-1 border-t border-border">
          ✔️ Exécuté le {formatDateTime(payload.executee_le)}
          {payload.executee_par && ` par ${payload.executee_par === 'SYSTEME' ? 'le système' : payload.executee_par}`}
        </p>
      )}
    </div>
  );
}
