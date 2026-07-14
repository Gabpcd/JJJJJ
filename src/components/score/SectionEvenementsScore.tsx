import { useEffect, useState } from 'react';
import { AlertTriangle } from 'lucide-react';
import { format } from 'date-fns';
import { fr } from 'date-fns/locale';
import { supabase } from '@/integrations/supabase/client';
import { ModaleReclamationScore } from '@/components/score/ModaleReclamationScore';

interface Evenement {
  id: string;
  type_evenement: string;
  points: number;
  points_corriges: number | null;
  motif: string;
  contestable: boolean;
  decision_admin: string | null;
  cree_le: string;
  mission_id?: string | null;
}

interface Props {
  /** SOIGNANT ou ETAB — détermine l'evenementType passé à ModaleReclamationScore */
  type: 'SOIGNANT' | 'ETAB';
  /** Limite événements affichés (default 20) */
  limit?: number;
}

/**
 * Section "Événements impactant le score (12 derniers mois)".
 *
 * Sprint 6 PR 4 — Fix P1-9 audit Sprint 5 (générique soignant + étab).
 *
 * Liste les événements de score avec bouton "Contester" sur ceux contestables.
 * Ouvre ModaleReclamationScore Sprint 3.5 (déjà générique).
 */
export function SectionEvenementsScore({ type, limit = 20 }: Props) {
  const [evenements, setEvenements] = useState<Evenement[]>([]);
  const [loading, setLoading] = useState(true);
  const [evenementSelectionne, setEvenementSelectionne] = useState<Evenement | null>(null);
  const possessifScore = type === 'ETAB' ? 'votre score' : 'ton score';
  const phraseContestation = type === 'ETAB'
    ? 'Vous pourrez contester toute pénalité contestable.'
    : 'Tu pourras contester toute pénalité contestable.';

  async function charger() {
    setLoading(true);
    const { data } = await supabase.rpc('fn_mes_evenements_score' as any, { p_limit: limit });
    const result = data as any;
    if (Array.isArray(result?.events)) {
      setEvenements(result.events as Evenement[]);
    }
    setLoading(false);
  }

  useEffect(() => { charger(); }, [limit]);

  if (loading) {
    return <p className="text-xs text-muted-foreground italic">Chargement des événements…</p>;
  }

  if (evenements.length === 0) {
    return (
      <div className="card-base">
        <h3 className="text-sm font-semibold text-foreground mb-2 flex items-center gap-2">
          <AlertTriangle className="h-4 w-4 text-warning" /> Aucun événement récent
        </h3>
        <p className="text-xs text-muted-foreground">
          Les événements impactant {possessifScore} (annulations, retards de paiement, évaluations exceptionnelles) apparaîtront ici.
          {' '}{phraseContestation}
        </p>
      </div>
    );
  }

  return (
    <>
      <section>
        <h2 className="text-lg font-bold text-foreground mb-3 inline-flex items-center gap-2">
          <AlertTriangle className="h-5 w-5 text-warning" /> Événements impactant {possessifScore} (12 derniers mois)
        </h2>
        <div className="space-y-2">
          {evenements.map((ev) => {
            const pts = Number(ev.points_corriges ?? ev.points);
            const estPenalite = pts < 0;
            return (
              <div key={ev.id} className="card-base flex flex-col sm:flex-row sm:items-center justify-between gap-3 py-3">
                <div className="flex-1 min-w-0">
                  <p className="text-sm font-medium text-foreground">{ev.type_evenement}</p>
                  {ev.motif && <p className="text-xs text-muted-foreground truncate">{ev.motif}</p>}
                  <p className="text-[11px] text-muted-foreground mt-0.5">
                    {format(new Date(ev.cree_le), "d MMMM yyyy 'à' HH:mm", { locale: fr })}
                  </p>
                  {ev.decision_admin && (
                    <p className="text-[11px] text-primary mt-0.5">
                      ✔️ Décision admin : {ev.decision_admin}
                    </p>
                  )}
                </div>
                <div className="flex items-center gap-3 sm:gap-4 shrink-0">
                  <span className={`text-base font-bold ${estPenalite ? 'text-destructive' : 'text-success'}`}>
                    {pts > 0 ? '+' : ''}{pts} pts
                  </span>
                  {ev.contestable ? (
                    <button
                      type="button"
                      onClick={() => setEvenementSelectionne(ev)}
                      className="btn-secondary text-xs py-1.5 px-3 whitespace-nowrap"
                    >
                      ⚖️ Contester
                    </button>
                  ) : (
                    <span className="text-[11px] text-muted-foreground italic whitespace-nowrap">
                      {ev.decision_admin ? 'Traitée' : 'Non contestable'}
                    </span>
                  )}
                </div>
              </div>
            );
          })}
        </div>
        <p className="text-[11px] text-muted-foreground italic mt-2">
          Les événements contestables peuvent être soumis à un admin Jolene qui décidera MAINTENIR / RÉDUIRE / ANNULER la pénalité sous 72h.
        </p>
      </section>

      {evenementSelectionne && (
        <ModaleReclamationScore
          ouvert={true}
          onFermer={() => setEvenementSelectionne(null)}
          onCreee={() => { setEvenementSelectionne(null); charger(); }}
          evenementId={evenementSelectionne.id}
          evenementType={type}
          evenementInfo={{
            type_evenement: evenementSelectionne.type_evenement,
            points: Number(evenementSelectionne.points_corriges ?? evenementSelectionne.points),
            motif: evenementSelectionne.motif,
            cree_le: evenementSelectionne.cree_le,
          }}
        />
      )}
    </>
  );
}
