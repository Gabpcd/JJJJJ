import React, { useEffect, useState } from 'react';
import { useNavigate } from 'react-router-dom';
import { ArrowLeft, ShieldCheck, AlertTriangle, MessageSquare } from 'lucide-react';
import { LayoutApp } from '@/components/LayoutApp';
import { ChargementPage } from '@/components/ChargementPage';
import { usePageTitle } from '@/hooks/usePageTitle';
import { supabase } from '@/integrations/supabase/client';
import { useAuth } from '@/contexts/AuthContext';
import { BadgeNiveauV2 } from '@/components/BadgeNiveauV2';
import { BreakdownScore } from '@/components/BreakdownScore';
import { GraphiqueEvolutionScore } from '@/components/GraphiqueEvolutionScore';
import { NotationsRecues } from '@/components/NotationsRecues';
import { ModaleReclamationScore } from '@/components/score/ModaleReclamationScore';
import { format } from 'date-fns';
import { fr } from 'date-fns/locale';

interface EvenementScore {
  id: string;
  type_evenement: string;
  points: number;
  points_corriges: number | null;
  motif: string;
  contestable: boolean;
  decision_admin: string | null;
  cree_le: string;
  mission_id: string | null;
}

export default function PageScoreSoignant() {
  return (
    <LayoutApp role="SOIGNANT">
      <ScoreContent />
    </LayoutApp>
  );
}

export function ScoreContent() {
  usePageTitle('Mon score');
  const navigate = useNavigate();
  const { user } = useAuth();
  const [loading, setLoading] = useState(true);
  const [breakdown, setBreakdown] = useState<any>(null);
  const [totalMissions, setTotalMissions] = useState<number>(0);
  const [evenements, setEvenements] = useState<EvenementScore[]>([]);
  const [evenementSelectionne, setEvenementSelectionne] = useState<EvenementScore | null>(null);

  function rechargerEvenements() {
    supabase.rpc('fn_mes_evenements_score' as any, { p_limit: 20 }).then(({ data }) => {
      const res = data as any;
      if (Array.isArray(res?.evenements)) {
        setEvenements(res.evenements as EvenementScore[]);
      } else if (Array.isArray(res)) {
        setEvenements(res as EvenementScore[]);
      }
    });
  }

  useEffect(() => {
    if (!user) return;
    Promise.all([
      supabase.rpc('fn_mon_breakdown_actuel' as any),
      supabase.from('soignants').select('total_missions_terminees, score_fiabilite, niveau, en_periode_probatoire').eq('id', user.id).maybeSingle(),
      supabase.rpc('fn_mes_evenements_score' as any, { p_limit: 20 }),
    ]).then(([{ data: bd }, { data: sg }, { data: ev }]) => {
      const evRes = ev as any;
      if (Array.isArray(evRes?.evenements)) {
        setEvenements(evRes.evenements as EvenementScore[]);
      } else if (Array.isArray(evRes)) {
        setEvenements(evRes as EvenementScore[]);
      }
      const bdObj = (bd as any);
      // Si breakdown vide (pas de snapshot), on construit un breakdown minimal depuis la table soignants
      if (!bdObj || !bdObj.score_total) {
        setBreakdown({
          score_total: Number(sg?.score_fiabilite ?? 50),
          niveau: sg?.niveau ?? 'BRONZE',
          en_periode_probatoire: sg?.en_periode_probatoire ?? true,
          notation_etab_soignant_pct: null,
          presentisme_pct: null, ponctualite_pct: null, reactivite_pct: null,
          anciennete_volume_pct: null, notation_soignant_etab_pct: null,
          notation_etab_soignant_poids: null, presentisme_poids: null, ponctualite_poids: null,
          reactivite_poids: null, anciennete_volume_poids: null, notation_soignant_etab_poids: null,
          litiges_malus: 0, absence_sans_prevenir_malus: 0, bonus_super_actif: 0,
          composantes_actives_count: 0, composantes_inactives_json: [],
        });
      } else {
        setBreakdown(bdObj);
      }
      setTotalMissions(Number(sg?.total_missions_terminees ?? 0));
      setLoading(false);
    });
  }, [user]);

  if (loading || !breakdown) {
    return <ChargementPage />;
  }

  const score = Math.round(Number(breakdown.score_total));
  const niveau = breakdown.niveau as 'BRONZE' | 'ARGENT' | 'OR' | 'PLATINE';
  const nonNote = totalMissions < 3;

  return (
    <>
      <button onClick={() => navigate(-1)} className="flex items-center gap-1 text-sm text-primary hover:underline mb-2">
        <ArrowLeft className="h-4 w-4" /> Retour
      </button>

      <div className="mb-6">
        <h1 className="text-2xl font-bold text-foreground inline-flex items-center gap-2">
          <ShieldCheck className="h-6 w-6 text-primary" /> Mon score de fiabilité
        </h1>
        <p className="text-sm text-muted-foreground mt-1">
          Score calculé à partir de 6 composantes pondérées sur les 12 derniers mois. Mis à jour automatiquement après chaque nouvelle notation, mission terminée ou litige résolu.
        </p>
      </div>

      {/* Score visible en grand */}
      <div className="card-base mb-6 text-center py-6">
        {nonNote ? (
          <>
            <div className="mb-2"><BadgeNiveauV2 nonNote /></div>
            <p className="text-4xl font-extrabold text-muted-foreground/40">— / 100</p>
            <p className="text-xs text-muted-foreground mt-2">
              Score disponible après {Math.max(0, 3 - totalMissions)} mission{Math.max(0, 3 - totalMissions) > 1 ? 's' : ''} terminée{Math.max(0, 3 - totalMissions) > 1 ? 's' : ''} de plus.
            </p>
          </>
        ) : (
          <>
            <div className="mb-3"><BadgeNiveauV2 niveau={niveau} /></div>
            <p className="text-5xl font-extrabold text-primary">{score}<span className="text-xl text-muted-foreground"> / 100</span></p>
            {breakdown.en_periode_probatoire && (
              <p className="text-xs text-warning mt-2 inline-flex items-center gap-1">
                <AlertTriangle className="h-3 w-3" /> Période probatoire (score indicatif)
              </p>
            )}
          </>
        )}
      </div>

      {/* Onglets */}
      <div className="space-y-6">
        {/* Breakdown détaillé */}
        <section>
          <h2 className="text-lg font-bold text-foreground mb-3">Détail par composante</h2>
          <BreakdownScore breakdown={breakdown} />
        </section>

        {/* Évolution 6 mois */}
        <section>
          <GraphiqueEvolutionScore />
        </section>

        {/* Notations reçues */}
        <section>
          <h2 className="text-lg font-bold text-foreground mb-3 inline-flex items-center gap-2">
            <MessageSquare className="h-5 w-5 text-primary" /> Notations reçues récemment
          </h2>
          <NotationsRecues audience="SOIGNANT" />
        </section>

        {/* Événements impactants récents avec bouton "Contester" par événement (Sprint 3.5) */}
        {evenements.length > 0 && (
          <section>
            <h2 className="text-lg font-bold text-foreground mb-3 inline-flex items-center gap-2">
              <AlertTriangle className="h-5 w-5 text-warning" /> Événements impactant votre score (12 derniers mois)
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
        )}

        {evenements.length === 0 && (
          <div className="card-base">
            <h3 className="text-sm font-semibold text-foreground mb-2 flex items-center gap-2">
              <AlertTriangle className="h-4 w-4 text-warning" /> Vous pensez qu'une pénalité est injuste ?
            </h3>
            <p className="text-xs text-muted-foreground">
              Aucun événement impactant votre score n'a été enregistré sur les 12 derniers mois. Si vous constatez une erreur, contactez le support Jolene.
            </p>
          </div>
        )}

        <div className="rounded-xl bg-muted/30 border border-border p-4 text-xs text-muted-foreground">
          <p className="font-semibold text-foreground mb-1">À propos du calcul</p>
          <ul className="list-disc list-inside space-y-1">
            <li>6 composantes pondérées : Notation reçue (35%) · Présentéisme (20%) · Ponctualité (15%) · Réactivité (10%) · Ancienneté & volume (10%) · Vous notez les étabs (10%)</li>
            <li>Malus jusqu'à -20 pts (litiges) et -30 pts (absence sans prévenir)</li>
            <li>Bonus +5 pts si plus de 50 missions terminées sur 12 mois</li>
            <li>Composantes inactives (pas assez de données) redistribuées proportionnellement</li>
            <li>Score borné [0, 100]. Niveau : Bronze (&lt;50) · Argent (50-69) · Or (70-89) · Platine (≥90)</li>
          </ul>
        </div>
      </div>

      {evenementSelectionne && (
        <ModaleReclamationScore
          ouvert={true}
          onFermer={() => setEvenementSelectionne(null)}
          onCreee={() => {
            setEvenementSelectionne(null);
            rechargerEvenements();
          }}
          evenementId={evenementSelectionne.id}
          evenementType="SOIGNANT"
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
