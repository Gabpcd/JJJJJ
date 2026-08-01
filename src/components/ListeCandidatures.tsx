import React, { useState, useEffect } from 'react';
import { AlertTriangle, CheckCircle, Clock, RefreshCw, Scale, XCircle } from 'lucide-react';
import { supabase } from '@/integrations/supabase/client';
import { extraireMessageErreur } from '@/lib/erreurs';
import { PopoverScoreSoignant } from '@/components/score/PopoverScoreSoignant';
import { getLabelProfession } from '@/lib/constantes';
import { EmptyState } from '@/components/ui/EmptyState';
import { BoutonY2K } from '@/components/y2k/BoutonY2K';
import {
  DialogResponsive,
  DialogResponsiveBody,
  DialogResponsiveContent,
  DialogResponsiveDescription,
  DialogResponsiveFooter,
  DialogResponsiveHeader,
  DialogResponsiveTitle,
} from '@/components/ui/DialogResponsive';
import { creneauxPrevisionnels, type CreneauPointage } from '@/lib/disponibilite-pointage';
import { formatParis, instantJolene, memeJourParis } from '@/lib/date-heure-paris';

function scoreBadge(score: number) {
  if (score >= 70) return 'bg-success/10 text-success';
  if (score >= 40) return 'bg-warning/10 text-warning';
  return 'bg-destructive/10 text-destructive';
}

interface ListeCandidaturesProps {
  missionId: string;
  missionIntitule?: string;
  missionCreneaux?: CreneauPointage[];
  missionNbCreneaux?: number | null;
  planningIndisponible?: boolean;
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

type CreneauExact = CreneauPointage & { fin: string };

interface VerificationPlanningExact {
  creneaux: CreneauExact[];
  erreur: string | null;
}

function verifierPlanningExact(
  creneaux: CreneauPointage[],
  nbCreneauxAttendus: number | null | undefined,
  indisponible = false,
): VerificationPlanningExact {
  if (indisponible) {
    return { creneaux: [], erreur: 'Le planning détaillé est momentanément indisponible.' };
  }

  const attendus = Number(nbCreneauxAttendus);
  if (!Number.isInteger(attendus) || attendus <= 0) {
    return { creneaux: [], erreur: 'Le nombre de créneaux contractuels doit être confirmé.' };
  }

  const planifies = creneaux.filter((creneau) => (
    creneau.type_creneau === 'PREVISIONNEL' && !creneau.est_pause
  ));
  if (planifies.length !== attendus) {
    return {
      creneaux: [],
      erreur: `Planning incomplet : ${attendus} créneau${attendus > 1 ? 'x' : ''} attendu${attendus > 1 ? 's' : ''}, ${planifies.length} chargé${planifies.length > 1 ? 's' : ''}.`,
    };
  }
  if (planifies.some((creneau) => !creneau.fin)) {
    return { creneaux: [], erreur: 'Chaque créneau doit comporter une date et une heure de fin exactes.' };
  }

  try {
    const complets = creneauxPrevisionnels(planifies) as CreneauExact[];
    if (complets.length !== attendus || complets.some((creneau) => (
      instantJolene(creneau.fin).getTime() <= instantJolene(creneau.debut).getTime()
    ))) {
      return { creneaux: [], erreur: 'Le planning contient un créneau dont les horaires sont invalides.' };
    }
    return { creneaux: complets, erreur: null };
  } catch {
    return { creneaux: [], erreur: 'Le planning contient une date ou une heure invalide.' };
  }
}

function empreintePlanning(creneaux: CreneauExact[]): string {
  return JSON.stringify(creneaux.map((creneau) => ({
    id: creneau.id ?? null,
    debut: creneau.debut,
    fin: creneau.fin,
  })));
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

export function ListeCandidatures({
  missionId,
  missionIntitule,
  missionCreneaux = [],
  missionNbCreneaux,
  planningIndisponible = false,
  missionProfession,
  missionSpecialiteMedicale,
  onAccepted,
  onError,
  onSuccess,
}: ListeCandidaturesProps) {
  const [candidatures, setCandidatures] = useState<any[]>([]);
  const [loading, setLoading] = useState(true);
  const [erreurChargement, setErreurChargement] = useState<string | null>(null);
  const [traitement, setTraitement] = useState<string | null>(null);
  const [candidatureAConfirmer, setCandidatureAConfirmer] = useState<any | null>(null);
  const [planningConfirmation, setPlanningConfirmation] = useState<CreneauExact[]>([]);
  const [alerteReconfirmation, setAlerteReconfirmation] = useState<string | null>(null);

  const verificationInitiale = verifierPlanningExact(
    missionCreneaux,
    missionNbCreneaux,
    planningIndisponible,
  );
  const planningPretPourAcceptation = verificationInitiale.erreur === null;
  const dureeTotaleConfirmation = planningConfirmation.reduce((total, creneau) => (
    total + Math.max(0, (instantJolene(creneau.fin).getTime() - instantJolene(creneau.debut).getTime()) / 3_600_000)
  ), 0);

  useEffect(() => {
    charger();
  }, [missionId]);

  const charger = async () => {
    setLoading(true);
    setErreurChargement(null);
    try {
      const { data, error } = await supabase
        .from('candidatures')
        .select('id, soignant_id, message, statut, cree_le')
        .eq('mission_id', missionId)
        .order('cree_le', { ascending: true });
      if (error) throw error;

      const enriched = await Promise.all(
        (data ?? []).map(async (c: any) => {
          const { data: sg, error: erreurSoignant } = await supabase.rpc(
            'fn_soignant_pour_etablissement' as any,
            { p_soignant_id: c.soignant_id },
          );
          if (erreurSoignant) throw erreurSoignant;
          return { ...c, soignant: sg || null };
        }),
      );
      setCandidatures(enriched);
    } catch (err) {
      setErreurChargement(extraireMessageErreur(err));
    } finally {
      setLoading(false);
    }
  };

  const chargerPlanningExactServeur = async (): Promise<CreneauExact[]> => {
    const { data, error } = await supabase
      .from('mission_creneaux')
      .select('id, mission_id, debut, fin, est_pause, type_creneau')
      .eq('mission_id', missionId)
      .eq('type_creneau', 'PREVISIONNEL')
      .eq('est_pause', false)
      .order('debut', { ascending: true });
    if (error) throw error;

    const verification = verifierPlanningExact(
      (data ?? []) as CreneauPointage[],
      missionNbCreneaux,
    );
    if (verification.erreur) throw new Error(verification.erreur);
    return verification.creneaux;
  };

  const fermerConfirmation = () => {
    setCandidatureAConfirmer(null);
    setPlanningConfirmation([]);
    setAlerteReconfirmation(null);
  };

  const ouvrirConfirmationAcceptation = async (candidatureId: string) => {
    if (!planningPretPourAcceptation) {
      onError(verificationInitiale.erreur ?? 'Le planning détaillé doit être confirmé avant d’accepter une candidature.');
      return;
    }

    setTraitement(candidatureId);
    try {
      const planningRelu = await chargerPlanningExactServeur();
      const candidature = candidatures.find((item) => item.id === candidatureId);
      setPlanningConfirmation(planningRelu);
      setAlerteReconfirmation(null);
      setCandidatureAConfirmer(candidature ?? { id: candidatureId });
    } catch (err) {
      onError(extraireMessageErreur(err));
    } finally {
      setTraitement(null);
    }
  };

  const confirmerAcceptation = async () => {
    const candidatureId = candidatureAConfirmer?.id;
    if (!candidatureId || traitement) return;

    setTraitement(candidatureId);
    setAlerteReconfirmation(null);
    try {
      // Une deuxième lecture juste avant la mutation évite de confirmer un
      // récapitulatif devenu obsolète pendant que la boîte de dialogue était ouverte.
      const planningRelu = await chargerPlanningExactServeur();
      if (empreintePlanning(planningRelu) !== empreintePlanning(planningConfirmation)) {
        setPlanningConfirmation(planningRelu);
        setAlerteReconfirmation(
          'Le planning a changé depuis l’ouverture. Vérifiez les nouveaux horaires puis confirmez de nouveau.',
        );
        return;
      }

      const { data, error } = await supabase.rpc('fn_traiter_candidature_planning_v1' as any, {
        p_candidature_id: candidatureId,
        p_decision: 'ACCEPTEE',
        p_creneaux_confirmes: planningRelu.map(({ debut, fin }) => ({ debut, fin })) as any,
        p_motif: null,
      });
      if (error) throw error;
      if (data?.error) {
        setAlerteReconfirmation(data.error);
        onError(data.error);
        return;
      }

      fermerConfirmation();
      onSuccess('Candidature acceptée ! Le soignant est assigné.');
      onAccepted();
      await charger();
    } catch (err) {
      onError(extraireMessageErreur(err));
    } finally {
      setTraitement(null);
    }
  };

  const traiterCandidature = async (candidatureId: string, decision: 'ACCEPTEE' | 'REFUSEE') => {
    if (decision === 'ACCEPTEE') {
      await ouvrirConfirmationAcceptation(candidatureId);
      return;
    }

    setTraitement(candidatureId);
    try {
      const { data, error } = await supabase.rpc('fn_traiter_candidature_planning_v1' as any, {
        p_candidature_id: candidatureId,
        p_decision: 'REFUSEE',
        p_creneaux_confirmes: null,
        p_motif: 'Refusé par l\'établissement',
      });
      if (error) throw error;
      if (data?.error) { onError(data.error); return; }
      onSuccess('Candidature refusée.');
      await charger();
    } catch (err) {
      onError(extraireMessageErreur(err));
    } finally {
      setTraitement(null);
    }
  };

  if (loading) return <p className="text-sm text-muted-foreground text-center py-6">Chargement des candidatures…</p>;

  if (erreurChargement) {
    return (
      <div className="rounded-xl border border-destructive/30 bg-destructive/5 p-4" role="alert">
        <p className="flex items-center gap-2 text-sm font-semibold text-destructive">
          <AlertTriangle className="h-4 w-4 shrink-0" aria-hidden="true" />
          Impossible de charger les candidatures
        </p>
        <p className="mt-1 text-xs text-muted-foreground">{erreurChargement}</p>
        <button type="button" onClick={() => void charger()} className="mt-3 inline-flex items-center gap-1.5 text-xs font-semibold text-primary hover:underline">
          <RefreshCw className="h-3.5 w-3.5" aria-hidden="true" /> Réessayer
        </button>
      </div>
    );
  }

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
          {!planningPretPourAcceptation && (
            <div className="rounded-xl border border-warning/30 bg-warning/5 p-3 text-xs text-warning" role="alert">
              <p className="font-semibold">Planning détaillé à confirmer avant toute acceptation.</p>
              <p className="mt-1 text-muted-foreground">
                Aucun candidat ne sera assigné tant que chaque créneau ne comporte pas une date et une heure de fin exactes.
              </p>
              {verificationInitiale.erreur && (
                <p className="mt-1 font-medium">{verificationInitiale.erreur}</p>
              )}
            </div>
          )}
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
                    disabled={Boolean(traitement) || !planningPretPourAcceptation}
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
                    disabled={Boolean(traitement)}
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

      <DialogResponsive
        open={Boolean(candidatureAConfirmer)}
        onOpenChange={(open) => { if (!open && !traitement) fermerConfirmation(); }}
      >
        <DialogResponsiveContent maxWidth="lg">
          <DialogResponsiveHeader>
            <DialogResponsiveTitle>Confirmer l’acceptation</DialogResponsiveTitle>
            <DialogResponsiveDescription>
              Vérifiez le planning contractuel avant d’assigner définitivement ce candidat.
            </DialogResponsiveDescription>
          </DialogResponsiveHeader>
          <DialogResponsiveBody>
            <div className="space-y-3">
              <div className="rounded-xl border border-border bg-muted/30 p-3 text-sm">
                <p className="font-semibold text-foreground">
                  {candidatureAConfirmer?.soignant?.prenom} {candidatureAConfirmer?.soignant?.nom}
                </p>
                {missionIntitule && <p className="text-xs text-muted-foreground">{missionIntitule}</p>}
              </div>
              <div>
                <p className="text-sm font-semibold text-foreground">
                  {planningConfirmation.length} créneau{planningConfirmation.length > 1 ? 'x' : ''} · {dureeTotaleConfirmation.toLocaleString('fr-FR', { maximumFractionDigits: 2 })} h au total
                </p>
                <ul className="mt-2 divide-y divide-border rounded-xl border border-border px-3">
                  {planningConfirmation.map((creneau) => (
                    <li key={creneau.id ?? creneau.debut} className="py-2 text-xs">
                      <span className="font-medium text-foreground">{formatParis(creneau.debut, 'EEEE d MMMM yyyy')}</span>
                      <span className="mt-0.5 block text-muted-foreground">
                        {formatParis(creneau.debut, 'HH:mm')} → {memeJourParis(creneau.debut, creneau.fin)
                          ? formatParis(creneau.fin, 'HH:mm')
                          : formatParis(creneau.fin, 'EEE d MMM · HH:mm')}
                      </span>
                    </li>
                  ))}
                </ul>
              </div>
              <p className="text-xs text-muted-foreground">
                En confirmant, ce soignant sera assigné à l’ensemble de ce planning.
              </p>
              {alerteReconfirmation && (
                <div className="rounded-xl border border-warning/30 bg-warning/5 p-3 text-xs font-medium text-warning" role="alert">
                  {alerteReconfirmation}
                </div>
              )}
            </div>
          </DialogResponsiveBody>
          <DialogResponsiveFooter>
            <BoutonY2K variant="secondary" onClick={fermerConfirmation} disabled={Boolean(traitement)}>
              Annuler
            </BoutonY2K>
            <BoutonY2K
              variant="primary"
              onClick={() => void confirmerAcceptation()}
              disabled={Boolean(traitement) || planningConfirmation.length === 0}
              loading={Boolean(traitement)}
            >
              Confirmer et assigner
            </BoutonY2K>
          </DialogResponsiveFooter>
        </DialogResponsiveContent>
      </DialogResponsive>

    </div>
  );
}
