import React, { useEffect, useState } from 'react';
import { useNavigate } from 'react-router-dom';
import { ArrowLeft, ShieldCheck, MessageSquare, AlertCircle, CheckCircle2, TrendingDown } from 'lucide-react';
import { LayoutApp } from '@/components/LayoutApp';
import { ChargementPage } from '@/components/ChargementPage';
import { usePageTitle } from '@/hooks/usePageTitle';
import { supabase } from '@/integrations/supabase/client';
import { useEtablissementScope } from '@/hooks/useEtablissementScope';
import { BadgeNiveauV2 } from '@/components/BadgeNiveauV2';
import { NotationsRecues } from '@/components/NotationsRecues';
import { SectionEvenementsScore } from '@/components/score/SectionEvenementsScore';

interface ScoreEtab {
  score_qualite: number | null;
  niveau: 'BRONZE' | 'ARGENT' | 'OR' | 'PLATINE' | null;
  composantes: {
    notation_pct: number | null;
    nb_notations: number;
    paiement_pct: number | null;
    nb_factures: number;
    nb_litiges_perdus: number;
  };
}

export default function PageScoreEtablissement() {
  usePageTitle('Score qualité');
  const navigate = useNavigate();
  const { etablissementId } = useEtablissementScope();
  const [loading, setLoading] = useState(true);
  const [score, setScore] = useState<ScoreEtab | null>(null);

  useEffect(() => {
    if (!etablissementId) return;
    supabase.rpc('fn_mon_score_etab' as any).then(({ data }) => {
      setScore(data as ScoreEtab);
      setLoading(false);
    });
  }, [etablissementId]);

  if (loading || !score) {
    return <LayoutApp role="ADMIN_ETABLISSEMENT"><ChargementPage /></LayoutApp>;
  }

  const scoreNum = score.score_qualite != null ? Math.round(Number(score.score_qualite)) : null;
  const niveau = score.niveau;
  const c = score.composantes;
  const nonNote = (c.nb_notations < 3) && (c.nb_factures === 0);

  return (
    <LayoutApp role="ADMIN_ETABLISSEMENT">
      <button onClick={() => navigate(-1)} className="app-inline-back flex items-center gap-1 text-sm text-primary hover:underline mb-2">
        <ArrowLeft className="h-4 w-4" /> Retour
      </button>

      <div className="mb-6">
        <h1 className="text-2xl font-bold text-foreground inline-flex items-center gap-2">
          <ShieldCheck className="h-6 w-6 text-primary" /> Score qualité
        </h1>
        <p className="text-sm text-muted-foreground mt-1">
          Score calculé à partir de 3 composantes : notations soignants, paiement à temps, litiges (12 mois). Mis à jour automatiquement.
        </p>
      </div>

      {/* Score visible */}
      <div className="card-base mb-6 text-center py-6">
        {nonNote ? (
          /* Lot 11 : vrai état vide — jamais de « — / 100 » qui ressemble à un
             zéro. Le badge « Nouveau » + la condition d'obtention suffisent. */
          <>
            <div className="mb-2"><BadgeNiveauV2 nonNote /></div>
            <p className="text-sm font-medium text-foreground">Pas encore de score</p>
            <p className="text-xs text-muted-foreground mt-1">
              Votre score apparaîtra après 3 notations de soignants ou 1 facture payée.
            </p>
          </>
        ) : (
          <>
            <div className="mb-3"><BadgeNiveauV2 niveau={niveau} /></div>
            <p className="text-5xl font-extrabold text-primary">
              {scoreNum ?? '—'}<span className="text-xl text-muted-foreground"> / 100</span>
            </p>
          </>
        )}
      </div>

      {/* Composantes */}
      <section className="mb-6">
        <h2 className="text-lg font-bold text-foreground mb-3">Détail par composante</h2>
        <div className="space-y-2">
          {/* Notations */}
          <article className="card-base">
            <div className="flex items-start justify-between gap-3 mb-1">
              <div>
                <p className="text-sm font-semibold text-foreground">Notations reçues (50%)</p>
                <p className="text-xs text-muted-foreground">Moyenne 4 critères pondérée récence ({c.nb_notations} notation{c.nb_notations > 1 ? 's' : ''} 12 mois)</p>
              </div>
              <p className={`text-2xl font-extrabold ${c.notation_pct == null ? 'text-muted-foreground' : c.notation_pct >= 80 ? 'text-success' : c.notation_pct >= 60 ? 'text-foreground' : 'text-warning'}`}>
                {c.notation_pct != null ? `${Math.round(c.notation_pct)}%` : '—'}
              </p>
            </div>
            {c.notation_pct == null && (
              <p className="text-xs text-muted-foreground">Encouragez vos soignants à vous noter après chaque mission terminée. Seuil 3 notations pour activer cette composante.</p>
            )}
            {c.notation_pct != null && c.notation_pct < 60 && (
              <div className="mt-2 rounded-xl bg-warning/5 border border-warning/20 p-2.5">
                <p className="text-xs inline-flex items-start gap-1.5">
                  <TrendingDown className="h-3.5 w-3.5 text-warning shrink-0 mt-0.5" />
                  <span><strong>Améliorez :</strong> les soignants évaluent l'accueil, l'encadrement, la clarté des consignes et le paiement à temps. Travaillez ces 4 points.</span>
                </p>
              </div>
            )}
          </article>

          {/* Paiement à temps */}
          <article className="card-base">
            <div className="flex items-start justify-between gap-3 mb-1">
              <div>
                <p className="text-sm font-semibold text-foreground">Paiement à temps (30%)</p>
                <p className="text-xs text-muted-foreground">% factures Jolene payées avant échéance ({c.nb_factures} facture{c.nb_factures > 1 ? 's' : ''} 12 mois)</p>
              </div>
              <p className={`text-2xl font-extrabold ${c.paiement_pct == null ? 'text-muted-foreground' : c.paiement_pct >= 80 ? 'text-success' : c.paiement_pct >= 60 ? 'text-foreground' : 'text-warning'}`}>
                {c.paiement_pct != null ? `${Math.round(c.paiement_pct)}%` : '—'}
              </p>
            </div>
            {c.paiement_pct != null && c.paiement_pct < 80 && (
              <div className="mt-2 rounded-xl bg-warning/5 border border-warning/20 p-2.5">
                <p className="text-xs inline-flex items-start gap-1.5">
                  <TrendingDown className="h-3.5 w-3.5 text-warning shrink-0 mt-0.5" />
                  <span><strong>Améliorez :</strong> activez le paiement automatique ou rapprochez-vous de la facturation pour respecter les échéances.</span>
                </p>
              </div>
            )}
          </article>

          {/* Litiges malus */}
          {c.nb_litiges_perdus > 0 && (
            <article className="card-base border-l-4 border-l-warning bg-warning/5">
              <div className="flex items-start gap-3">
                <AlertCircle className="h-5 w-5 text-warning shrink-0 mt-0.5" />
                <div>
                  <p className="text-sm font-semibold text-foreground">Litiges contre vous : {c.nb_litiges_perdus}</p>
                  <p className="text-xs text-muted-foreground mt-0.5">
                    -10 pts par litige résolu en faveur du soignant (cap -20 pts). Évitez les litiges en respectant les consignes mission et le contrat de travail.
                  </p>
                </div>
              </div>
            </article>
          )}

          {c.nb_litiges_perdus === 0 && (
            <article className="card-base border-l-4 border-l-success bg-success/5">
              <div className="flex items-start gap-3">
                <CheckCircle2 className="h-5 w-5 text-success shrink-0 mt-0.5" />
                <div>
                  <p className="text-sm font-semibold text-foreground">Aucun litige perdu — bravo !</p>
                  <p className="text-xs text-muted-foreground mt-0.5">Continuez à respecter les consignes mission et le paiement à temps.</p>
                </div>
              </div>
            </article>
          )}
        </div>
      </section>

      {/* Notations reçues */}
      <section className="mb-6">
        <h2 className="text-lg font-bold text-foreground mb-3 inline-flex items-center gap-2">
          <MessageSquare className="h-5 w-5 text-primary" /> Notations reçues récemment
        </h2>
        <NotationsRecues audience="ETAB" />
      </section>

      {/* Événements impactants + contestation (Sprint 6 PR 4 — Fix P1-9) */}
      <section className="mb-6">
        <SectionEvenementsScore type="ETAB" />
      </section>

      <div className="rounded-xl bg-muted/30 border border-border p-4 text-xs text-muted-foreground">
        <p className="font-semibold text-foreground mb-1">À propos du calcul</p>
        <ul className="list-disc list-inside space-y-1">
          <li>3 composantes : Notations soignants (50%) · Paiement à temps (30%) · Bonus base 20% — Malus litiges</li>
          <li>Notations : pondérées récence linéaire 12 mois, moyenne 4 critères convertie 0-100%</li>
          <li>Litiges : -10 par litige perdu (cap -20)</li>
          <li>Composantes inactives (pas assez de données) redistribuées proportionnellement</li>
          <li>Score borné [0, 100]. Niveau : Bronze (&lt;50) · Argent (50-69) · Or (70-89) · Platine (≥90)</li>
        </ul>
      </div>
    </LayoutApp>
  );
}
