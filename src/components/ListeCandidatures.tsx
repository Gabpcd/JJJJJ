import React, { useState, useEffect } from 'react';
import { CheckCircle, XCircle, Clock, Send, Loader2, Scale } from 'lucide-react';
import { supabase } from '@/integrations/supabase/client';
import { extraireMessageErreur } from '@/lib/erreurs';
import { PopoverScoreSoignant } from '@/components/score/PopoverScoreSoignant';
import { getLabelProfession } from '@/lib/constantes';
import { EmptyState } from '@/components/ui/EmptyState';
import { BoutonY2K } from '@/components/y2k/BoutonY2K';

function scoreBadge(score: number) {
  if (score >= 70) return 'bg-success/10 text-success';
  if (score >= 40) return 'bg-warning/10 text-warning';
  return 'bg-destructive/10 text-destructive';
}

interface ListeCandidaturesProps {
  missionId: string;
  /** Profession requise par la mission — sert à signaler les candidats hors profession exacte (hiérarchie/souplesse). */
  missionProfession?: string | null;
  /** Spécialité médicale requise (code) — sert à signaler les médecins sans la spécialité exacte. */
  missionSpecialiteMedicale?: string | null;
  /** Flag accepte_non_specialises — sert au calcul du label badge. */
  missionAccepteNonSpecialises?: boolean | null;
  modePaiement?: string;
  onAccepted: () => void;
  onError: (msg: string) => void;
  onSuccess: (msg: string) => void;
}

function getCandidatMatchBadge(
  candidatProfession: string | null | undefined,
  candidatSpecialite: string | null | undefined,
  missionProfession: string | null | undefined,
  missionSpecialite: string | null | undefined,
): { label: string; classes: string; tooltip: string } | null {
  if (!candidatProfession || !missionProfession) return null;

  if (candidatProfession === missionProfession) {
    if (
      missionProfession === 'MEDECIN' &&
      missionSpecialite &&
      (candidatSpecialite || '') !== missionSpecialite
    ) {
      return {
        label: '🩺 Médecin sans la spécialité requise',
        classes: 'bg-violet-500/10 text-violet-700 dark:text-violet-300',
        tooltip: 'Ce candidat est médecin mais sans la spécialité ciblée — la mission accepte les non-spécialisés.',
      };
    }
    return null;
  }

  if (missionProfession === 'IDE' && (candidatProfession === 'IBODE' || candidatProfession === 'IADE')) {
    return {
      label: `↑ ${candidatProfession} qualifié IDE`,
      classes: 'bg-success/10 text-success',
      tooltip: `Diplôme ${candidatProfession} couvre les missions IDE (hiérarchie naturelle).`,
    };
  }

  return null;
}

export function ListeCandidatures({ missionId, missionProfession, missionSpecialiteMedicale, missionAccepteNonSpecialises, onAccepted, onError, onSuccess }: ListeCandidaturesProps) {
  const [candidatures, setCandidatures] = useState<any[]>([]);
  const [loading, setLoading] = useState(true);
  const [traitement, setTraitement] = useState<string | null>(null);

  useEffect(() => {
    charger();
  }, [missionId]);

  const charger = async () => {
    setLoading(true);
    const { data } = await supabase
      .from('candidatures')
      .select('id, soignant_id, message, statut, cree_le')
      .eq('mission_id', missionId)
      .order('cree_le', { ascending: true });

    if (data && data.length > 0) {
      const enriched = await Promise.all(
        data.map(async (c: any) => {
          const { data: sg } = await supabase.rpc('fn_soignant_pour_etablissement' as any, { p_soignant_id: c.soignant_id });
          return { ...c, soignant: sg || null };
        })
      );
      setCandidatures(enriched);
    } else {
      setCandidatures([]);
    }
    setLoading(false);
  };

  const accepterAvecPaiement = async (candidatureId: string) => {
    await finaliserAcceptation(candidatureId);
  };

  const finaliserAcceptation = async (candidatureId: string) => {
    setTraitement(candidatureId);
    try {
      const { data, error } = await supabase.rpc('fn_traiter_candidature' as any, {
        p_candidature_id: candidatureId,
        p_decision: 'ACCEPTEE',
        p_motif: null,
      });
      if (error) throw error;
      if (data?.error) { onError(data.error); return; }
      onSuccess('Candidature acceptée ! Le soignant est assigné.');
      onAccepted();
      await charger();
    } catch (err: any) {
      onError(extraireMessageErreur(err));
    }
    setTraitement(null);
  };

  const traiterCandidature = async (candidatureId: string, decision: 'ACCEPTEE' | 'REFUSEE') => {
    if (decision === 'ACCEPTEE') {
      await accepterAvecPaiement(candidatureId);
      return;
    }
    setTraitement(candidatureId);
    try {
      const { data, error } = await supabase.rpc('fn_traiter_candidature' as any, {
        p_candidature_id: candidatureId,
        p_decision: decision,
        p_motif: 'Refusé par l\'établissement',
      });
      if (error) throw error;
      if (data?.error) { onError(data.error); return; }
      onSuccess('Candidature refusée.');
      await charger();
    } catch (err: any) {
      onError(extraireMessageErreur(err));
    }
    setTraitement(null);
  };

  if (loading) return <p className="text-sm text-muted-foreground text-center py-6">Chargement des candidatures…</p>;

  if (candidatures.length === 0) {
    return (
      <EmptyState
        icone={<Clock />}
        mascotte="thinking"
        titre="En attente de candidats"
        description="Les soignants qualifiés peuvent postuler à cette mission. Vérifiez que les critères (profession, taux, dates) sont cohérents avec le marché."
        variant="info"
      />
    );
  }

  // Une candidature issue d'un super-like porte ce message système.
  const estSuperLike = (c: any) => (c.message || '').includes('super-like');
  const enAttente = candidatures
    .filter(c => c.statut === 'EN_ATTENTE')
    // Super-likes en tête (tri stable : conserve l'ordre cree_le au sein de chaque groupe)
    .sort((a, b) => (estSuperLike(b) ? 1 : 0) - (estSuperLike(a) ? 1 : 0));
  const traitees = candidatures.filter(c => c.statut !== 'EN_ATTENTE');

  return (
    <div className="space-y-4">
      {enAttente.length > 0 && (
        <div className="space-y-3">
          <p className="text-sm font-semibold text-foreground">En attente ({enAttente.length})</p>
          {/* Lot 16 (Couche 2) : rappel contractuel au moment de la sélection —
              les clauses existent (CGV art. 8.2/8.3) mais n'étaient jamais
              surfacées dans le flux. Ton factuel, pas de mur. */}
          <p className="text-[11px] text-muted-foreground flex items-start gap-1.5">
            <Scale aria-hidden="true" className="h-3.5 w-3.5 shrink-0 mt-0.5" />
            <span>
              En acceptant un candidat, la mission reste opérée via Jolene (
              <a href="/cgv#art8" target="_blank" rel="noopener noreferrer" className="underline underline-offset-2 hover:text-primary">
                non-contournement & recrutement direct — CGV art. 8
              </a>
              ). Recruter en CDI un soignant rencontré ici ? La grille dégressive 15/10/5/0 % s'applique — souvent moins cher qu'un cabinet.
            </span>
          </p>
          {enAttente.map((c: any) => (
            <div key={c.id} className={`card-base ${estSuperLike(c) ? 'border-2 border-amber-400 bg-amber-50/30 dark:bg-amber-950/10' : 'border-primary/20'}`}>
              <div className="flex flex-col sm:flex-row sm:items-start sm:justify-between gap-3">
                <div className="flex-1 min-w-0">
                  <p className="font-semibold text-sm text-foreground flex items-center gap-1.5 flex-wrap">
                    👤 {c.soignant?.prenom} {c.soignant?.nom}
                    {estSuperLike(c) && (
                      <span className="badge-base text-[10px] bg-gradient-celebrate text-white font-bold" title="Ce soignant a montré un fort intérêt (super-like)">
                        ⭐ Super-like
                      </span>
                    )}
                    {c.soignant?.profession && (
                      <span className="badge-base text-[10px] bg-muted text-muted-foreground" title="Profession du candidat">
                        {getLabelProfession(c.soignant.profession)}
                      </span>
                    )}
                    {c.soignant?.est_etudiant && (
                      <span className="badge-base text-[10px] bg-violet-500/10 text-violet-700 dark:text-violet-300" title={c.soignant?.etudiant_details || 'Étudiant(e) en santé'}>
                        🎓 Étudiant{c.soignant?.etudiant_details ? ` · ${c.soignant.etudiant_details}` : ''}
                      </span>
                    )}
                    {c.soignant?.type_exercice && (
                      <span className={`badge-base text-[10px] ${c.soignant.type_exercice === 'LIBERAL' ? 'bg-info/10 text-info' : c.soignant.type_exercice === 'MIXTE' ? 'bg-rose/10 text-rose' : 'bg-muted text-muted-foreground'}`}>
                        {c.soignant.type_exercice === 'MIXTE' ? 'Salarié + Libéral' : c.soignant.type_exercice === 'LIBERAL' ? 'Libéral' : 'Salarié'}
                      </span>
                    )}
                    {(() => {
                      const badge = getCandidatMatchBadge(
                        c.soignant?.profession,
                        c.soignant?.specialite_medicale,
                        missionProfession,
                        missionSpecialiteMedicale,
                      );
                      return badge ? (
                        <span className={`badge-base text-[10px] ${badge.classes}`} title={badge.tooltip}>
                          {badge.label}
                        </span>
                      ) : null;
                    })()}
                  </p>
                  {c.soignant?.bio && (
                    <p className="text-xs text-muted-foreground mt-1 line-clamp-2">{c.soignant.bio}</p>
                  )}
                  <div className="flex items-center gap-2 mt-1.5 flex-wrap">
                    {c.soignant?.tous_documents_valides ? (
                      <span className="badge-base text-[10px] bg-success/10 text-success" title="CNI, diplôme et justificatifs vérifiés">
                        ✅ Documents validés
                      </span>
                    ) : (
                      <span className="badge-base text-[10px] bg-warning/10 text-warning" title="Le soignant a été notifié — la vérification automatique prend quelques minutes après téléversement. L'acceptation sera possible dès validation si la mission démarre sous 7 jours.">
                        📄 Documents en vérification
                      </span>
                    )}
                    {c.soignant?.score_fiabilite != null && c.soignant?.total_missions_terminees >= 3 ? (
                      <span className={`badge-base text-[10px] ${scoreBadge(c.soignant.score_fiabilite)} inline-flex items-center gap-1`}>
                        ⭐ {c.soignant.score_fiabilite}/100
                        <PopoverScoreSoignant soignantId={c.soignant.id} scoreFiabilite={c.soignant.score_fiabilite} />
                      </span>
                    ) : (
                      <span className="badge-base text-[10px] bg-muted text-muted-foreground">Pas encore d'évaluation</span>
                    )}
                    {c.soignant?.note_moyenne != null && c.soignant?.nb_evaluations > 0 && (
                      <span className="text-[10px] text-muted-foreground">{Number(c.soignant.note_moyenne).toFixed(1)}/5 ({c.soignant.nb_evaluations} avis)</span>
                    )}
                    {c.soignant?.annees_experience > 0 && (
                      <span className="text-[10px] text-muted-foreground">{c.soignant.annees_experience} ans d'exp.</span>
                    )}
                    {c.soignant?.specialites && (
                      <span className="text-[10px] text-muted-foreground">{
                        (Array.isArray(c.soignant.specialites) ? c.soignant.specialites : []).slice(0, 3).join(', ')
                      }</span>
                    )}
                  </div>
                  {c.message && (
                    <div className="mt-2 bg-muted/50 rounded-lg p-2">
                      <p className="text-xs text-muted-foreground italic">"{c.message}"</p>
                    </div>
                  )}
                </div>
                <div className="flex gap-2 shrink-0 w-full sm:w-auto">
                  <BoutonY2K
                    size="sm"
                    variant="primary"
                    onClick={() => traiterCandidature(c.id, 'ACCEPTEE')}
                    disabled={traitement === c.id}
                    loading={traitement === c.id}
                    iconeGauche={<CheckCircle className="h-4 w-4" />}
                    className="flex-1 sm:flex-none"
                    aria-label="Accepter cette candidature"
                  >
                    Accepter
                  </BoutonY2K>
                  <BoutonY2K
                    size="sm"
                    variant="destructive"
                    onClick={() => traiterCandidature(c.id, 'REFUSEE')}
                    disabled={traitement === c.id}
                    iconeGauche={<XCircle className="h-4 w-4" />}
                    className="flex-1 sm:flex-none"
                    aria-label="Refuser cette candidature"
                  >
                    Refuser
                  </BoutonY2K>
                </div>
              </div>
            </div>
          ))}
        </div>
      )}

      {traitees.length > 0 && (
        <div className="space-y-2">
          <p className="text-sm font-semibold text-muted-foreground">Traitées ({traitees.length})</p>
          {traitees.map((c: any) => (
            <div key={c.id} className="flex items-center justify-between p-3 bg-muted/30 rounded-xl">
              <span className="text-sm text-muted-foreground">
                {c.soignant?.prenom} {c.soignant?.nom}
              </span>
              <span className={`badge-base text-[10px] ${c.statut === 'ACCEPTEE' ? 'bg-success/10 text-success' : 'bg-destructive/10 text-destructive'}`}>
                {c.statut === 'ACCEPTEE' ? '✅ Acceptée' : '❌ Refusée'}
              </span>
            </div>
          ))}
        </div>
      )}

    </div>
  );
}
