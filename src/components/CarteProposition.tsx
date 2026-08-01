import React, { useState, useEffect } from 'react';
import { useNavigate } from 'react-router-dom';
import { supabase } from '@/integrations/supabase/client';
import { useAuth } from '@/contexts/AuthContext';
import { differenceInSeconds } from 'date-fns';
import { toast } from '@/hooks/use-toast';
import { BoutonY2K } from '@/components/y2k/BoutonY2K';
import { ModalAttestationHebdo } from '@/components/ModalAttestationHebdo';
import { PlanningMissionCandidat } from '@/components/planning/PlanningMissionCandidat';
import { RecapitulatifCandidatureDialog } from '@/components/planning/RecapitulatifCandidatureDialog';
import {
  associerCreneauxAuxMissions,
  construirePlanningCandidat,
  creneauxConfirmesPourAction,
} from '@/components/planning/planning-candidat';
import { chargerCreneauxMissionsPagines } from '@/lib/mission-creneaux-pagines';
import { debutSemaineParis, semaineSuivanteParis } from '@/lib/date-heure-paris';
import {
  calculerSemainesAttestationProposition,
  type SemaineAttestationProposition,
} from '@/lib/semaines-attestation-proposition';
import type {
  CreneauMissionPourCalculHebdomadaire,
  MissionPourCalculHebdomadaire,
} from '@/lib/heures-hebdomadaires-mission';

const EXPIRATION_MINUTES = 120; // 2h

interface MissionProposee {
  id?: string;
  intitule?: string;
  debut_le?: string;
  fin_le?: string;
  duree_heures?: number | null;
  taux_horaire_base?: number | null;
  net_estime?: number | null;
  type_contrat_recherche?: string | null;
  etablissement_id?: string;
  est_urgente?: boolean | null;
  etab_nom?: string | null;
  nb_creneaux?: number | null;
  creneaux_planifies?: any[];
  planning_exact?: boolean;
  erreur_planning?: boolean;
}

export interface PropositionMission extends MissionProposee {
  id: string;
  mission_id: string;
  cree_le: string;
  type_contrat_choisi?: string | null;
  missions?: MissionProposee | null;
}

interface ReponseProposition {
  success?: boolean;
  error?: string;
}

interface Props {
  proposition: PropositionMission;
  onTraitee: (id: string) => void;
}

export function CarteProposition({ proposition, onTraitee }: Props) {
  const navigate = useNavigate();
  const { user } = useAuth();
  const [loading, setLoading] = useState<'accept' | 'refuse' | null>(null);
  const [restant, setRestant] = useState('');
  const [expiree, setExpiree] = useState(false);
  const [showRecap, setShowRecap] = useState(false);
  const [verificationAttestation, setVerificationAttestation] = useState(false);
  const [attestationsACompleter, setAttestationsACompleter] = useState<SemaineAttestationProposition[]>([]);
  const [indexAttestation, setIndexAttestation] = useState(0);

  // Le dashboard canonique renvoie la relation dans `missions`. Le repli sur
  // l'objet lui-même garde la carte compatible avec une réponse mise en cache
  // produite par l'ancienne version aplatie du RPC pendant le déploiement.
  const missionInitiale = proposition.missions ?? proposition;
  const [missionPlanifiee, setMissionPlanifiee] = useState<MissionProposee>(() => ({
    ...missionInitiale,
    erreur_planning: true,
  }));
  const mission = missionPlanifiee;
  const contratPropose = proposition.type_contrat_choisi ?? mission?.type_contrat_recherche;
  const expirationMs = new Date(proposition.cree_le).getTime() + EXPIRATION_MINUTES * 60 * 1000;

  useEffect(() => {
    const tick = () => {
      const now = new Date();
      const diffSec = differenceInSeconds(new Date(expirationMs), now);
      if (diffSec <= 0) {
        setExpiree(true);
        setRestant('Expirée');
        onTraitee(proposition.id);
        return;
      }
      const h = Math.floor(diffSec / 3600);
      const m = Math.floor((diffSec % 3600) / 60);
      setRestant(`${h}h ${m.toString().padStart(2, '0')}min`);
    };
    tick();
    const interval = setInterval(tick, 30000);
    return () => clearInterval(interval);
  }, [expirationMs, onTraitee, proposition.id]);

  useEffect(() => {
    let actif = true;
    const chargerPlanning = async () => {
      try {
        const [{ data: metadata, error }, creneaux] = await Promise.all([
          supabase.from('missions')
            .select('id, debut_le, fin_le, duree_heures, nb_creneaux, taux_horaire_base')
            .eq('id', proposition.mission_id)
            .single(),
          chargerCreneauxMissionsPagines([proposition.mission_id], {
            typeCreneau: 'PREVISIONNEL',
            exclurePauses: true,
          }),
        ]);
        if (error) throw error;
        if (!actif) return;
        const [completee] = associerCreneauxAuxMissions([
          { ...missionInitiale, ...metadata, id: proposition.mission_id },
        ], creneaux);
        setMissionPlanifiee(completee);
      } catch {
        if (!actif) return;
        setMissionPlanifiee({ ...missionInitiale, id: proposition.mission_id, erreur_planning: true });
      }
    };
    void chargerPlanning();
    return () => { actif = false; };
  }, [proposition.mission_id]);

  if (expiree || !mission.intitule || !mission.debut_le || !mission.fin_le) return null;

  const planning = construirePlanningCandidat(mission as any);
  const netEstime = mission.net_estime ?? (
    planning.exact && mission.taux_horaire_base
      ? mission.taux_horaire_base * planning.totalHeures * 0.78
      : null
  );

  const preparerAttestations = async (): Promise<'CONTINUER' | 'ATTESTER' | 'BLOQUER'> => {
    // Lot 21 D4 : l'attestation de temps de travail dépend du contrat de la
    // MISSION proposée, jamais du statut déclaré sur le profil.
    if (contratPropose === 'LIBERAL') return 'CONTINUER';
    if (!user || !planning.exact || planning.creneaux.some((creneau) => !creneau.fin)) {
      toast({
        title: 'Vérification impossible',
        description: 'Recharge le planning exact avant d’accepter cette proposition.',
        variant: 'destructive',
      });
      return 'BLOQUER';
    }

    try {
      const debutPeriode = debutSemaineParis(planning.creneaux[0].debut);
      const finPeriode = semaineSuivanteParis(planning.creneaux[planning.creneaux.length - 1].fin!);
      const { data: missionsData, error: missionsError } = await supabase.from('missions')
        .select('id, debut_le, fin_le, duree_heures, nb_creneaux, statut, type_contrat_applique, choix_contrat_soignant, type_contrat_recherche')
        .eq('soignant_assigne_id', user.id)
        .in('statut', ['ASSIGNEE', 'EN_COURS', 'TERMINEE'])
        .lt('debut_le', finPeriode.toISOString())
        .gt('fin_le', debutPeriode.toISOString())
        .neq('id', proposition.mission_id);
      if (missionsError) throw missionsError;

      const missionsExistantes = (missionsData ?? []) as MissionPourCalculHebdomadaire[];
      const creneauxExistants = await chargerCreneauxMissionsPagines(
        missionsExistantes.map((item) => item.id),
        { exclurePauses: true },
      );
      const missionCandidate: MissionPourCalculHebdomadaire = {
        id: proposition.mission_id,
        debut_le: mission.debut_le!,
        fin_le: mission.fin_le!,
        duree_heures: mission.duree_heures ?? null,
        nb_creneaux: mission.nb_creneaux ?? null,
        statut: 'OUVERTE',
        type_contrat_applique: contratPropose ?? 'SALARIE',
        choix_contrat_soignant: contratPropose ?? null,
        type_contrat_recherche: mission.type_contrat_recherche ?? null,
      };
      const tousLesCreneaux = [
        ...((mission.creneaux_planifies ?? []) as CreneauMissionPourCalculHebdomadaire[]),
        ...creneauxExistants,
      ];
      const ventilation = calculerSemainesAttestationProposition(
        missionCandidate,
        missionsExistantes,
        tousLesCreneaux,
      );
      if (!ventilation.ok) throw new Error(ventilation.erreur);

      const semainesISO = ventilation.semaines.map((semaine) => semaine.semaineISO);
      const { data: attestations, error: attestationsError } = await supabase
        .from('attestations_heures_externes')
        .select('id, semaine_du, heures_salarie')
        .eq('soignant_id', user.id)
        .in('semaine_du', semainesISO);
      if (attestationsError) throw attestationsError;

      const attestationParSemaine = new Map(
        (attestations ?? []).map((item: any) => [item.semaine_du, Number(item.heures_salarie) || 0]),
      );
      const depassementDejaDeclare = ventilation.semaines.find((semaine) => (
        attestationParSemaine.has(semaine.semaineISO)
        && semaine.heuresJoleneSemaine + (attestationParSemaine.get(semaine.semaineISO) ?? 0) > 48
      ));
      if (depassementDejaDeclare) {
        toast({
          title: 'Plafond hebdomadaire dépassé',
          description: `La semaine du ${depassementDejaDeclare.semaineISO} dépasserait 48 h avec cette proposition.`,
          variant: 'destructive',
        });
        return 'BLOQUER';
      }

      const aCompleter = ventilation.semaines.filter((semaine) => (
        !attestationParSemaine.has(semaine.semaineISO)
      ));
      if (aCompleter.length === 0) return 'CONTINUER';
      setAttestationsACompleter(aCompleter);
      setIndexAttestation(0);
      return 'ATTESTER';
    } catch {
      toast({
        title: 'Vérification impossible',
        description: 'Les heures exactes de chaque semaine ne peuvent pas être vérifiées. Réessaie avant d’accepter.',
        variant: 'destructive',
      });
      return 'BLOQUER';
    }
  };

  const handleAction = async (action: 'ACCEPTEE' | 'REFUSEE') => {
    if (action === 'ACCEPTEE') {
      setVerificationAttestation(true);
      const resultat = await preparerAttestations();
      setVerificationAttestation(false);
      if (resultat !== 'CONTINUER') return;
    }
    if (action === 'ACCEPTEE') setShowRecap(true);
    else await executeAction(action);
  };

  const executeAction = async (action: 'ACCEPTEE' | 'REFUSEE') => {
    setLoading(action === 'ACCEPTEE' ? 'accept' : 'refuse');
    try {
      const creneauxConfirmes = action === 'ACCEPTEE'
        ? creneauxConfirmesPourAction(mission as any)
        : null;
      if (action === 'ACCEPTEE' && !creneauxConfirmes) {
        throw new Error('Le planning exact doit être rechargé avant l’acceptation.');
      }
      const { data, error } = action === 'ACCEPTEE'
        ? await supabase.rpc('fn_confirmer_action_planning_v1' as any, {
            p_mission_id: proposition.mission_id,
            p_action: 'PROPOSITION',
            p_creneaux_confirmes: creneauxConfirmes as any,
            p_message: null,
            p_choix_contrat: null,
            p_candidature_id: proposition.id,
          })
        : await supabase.rpc('fn_repondre_proposition', {
            p_candidature_id: proposition.id,
            p_accepter: false,
          });
      if (error) throw error;
      const reponse = data as ReponseProposition | null;

      if (reponse?.error === 'E16_CANDIDATURE_ORPHELINE') {
        toast({
          title: 'Proposition obsolète',
          description: 'Cette proposition date d\'avant une mise à jour. Merci de postuler directement depuis la mission dans votre espace.',
        });
        onTraitee(proposition.id);
        return;
      }

      if (reponse?.error === 'Cette proposition a expiré') {
        toast({
          title: 'Proposition expirée',
          description: 'La fenêtre de réponse de 2 heures est terminée.',
        });
        onTraitee(proposition.id);
        return;
      }

      if (reponse?.error) throw new Error(reponse.error);

      if (action === 'ACCEPTEE') {
        setShowRecap(false);
        toast({ title: 'Mission acceptée ✅', description: 'Signez le contrat pour confirmer.' });
        onTraitee(proposition.id);
        navigate(`/soignant/missions/${proposition.mission_id}`);
      } else {
        toast({ title: 'Mission déclinée', description: 'La proposition a été refusée.' });
        onTraitee(proposition.id);
      }
    } catch {
      toast({ title: 'Erreur', description: 'Impossible de traiter la proposition. Veuillez réessayer.', variant: 'destructive' });
    } finally {
      setLoading(null);
    }
  };

  const attestationActive = attestationsACompleter[indexAttestation] ?? null;

  return (
    <>
      <div className="rounded-xl border-2 border-orange-400 bg-orange-50 dark:bg-orange-950/20 dark:border-orange-600 p-4 space-y-2">
        <div className="flex items-center justify-between">
          <div className="flex items-center gap-2">
            {mission.est_urgente && (
              <span className="inline-flex items-center rounded-full bg-destructive px-2 py-0.5 text-[10px] font-semibold text-destructive-foreground">🚨 URGENT</span>
            )}
            <h3 className="font-semibold text-sm text-foreground">{mission.intitule}</h3>
          </div>
          <span className="text-xs font-medium text-orange-600 dark:text-orange-400 whitespace-nowrap">⏳ {restant}</span>
        </div>

        <PlanningMissionCandidat mission={mission as any} compact limite={3} />

        <div className="flex items-center justify-between">
          <span className="text-sm font-bold text-primary">{mission.taux_horaire_base} €/h</span>
          {netEstime && (
            <span className="text-xs text-muted-foreground">
              Net estimé* : {new Intl.NumberFormat('fr-FR', { style: 'currency', currency: 'EUR' }).format(netEstime)}
            </span>
          )}
        </div>

        <div className="flex gap-2 pt-1">
          <BoutonY2K size="sm" className="flex-1" disabled={!!loading || verificationAttestation || !planning.exact} loading={loading === 'accept' || verificationAttestation} onClick={() => handleAction('ACCEPTEE')}>
            {loading === 'accept' || verificationAttestation ? '...' : '✅ Accepter'}
          </BoutonY2K>
          <BoutonY2K size="sm" variant="secondary" className="flex-1" disabled={!!loading} loading={loading === 'refuse'} onClick={() => handleAction('REFUSEE')}>
            {loading === 'refuse' ? '...' : '❌ Refuser'}
          </BoutonY2K>
        </div>
      </div>

      {attestationActive && (
        <ModalAttestationHebdo
          key={attestationActive.semaineISO}
          semaineISO={attestationActive.semaineISO}
          heuresJoleneSemaine={attestationActive.heuresJoleneSemaine}
          onValidated={(peutContinuer) => {
            if (!peutContinuer) {
              setAttestationsACompleter([]);
              setIndexAttestation(0);
              toast({
                title: 'Déclaration enregistrée',
                description: 'La mission n’a pas été acceptée car elle dépasserait le plafond salarié de 48 h.',
                variant: 'destructive',
              });
            } else if (indexAttestation + 1 < attestationsACompleter.length) {
              setIndexAttestation((index) => index + 1);
            } else {
              setAttestationsACompleter([]);
              setIndexAttestation(0);
              setShowRecap(true);
            }
          }}
          onCancel={() => {
            setAttestationsACompleter([]);
            setIndexAttestation(0);
          }}
        />
      )}

      <RecapitulatifCandidatureDialog
        mission={mission as any}
        ouvert={showRecap}
        onFermer={() => setShowRecap(false)}
        onConfirmer={() => void executeAction('ACCEPTEE')}
        chargement={loading === 'accept'}
        actionLabel="Accepter tous ces créneaux"
        retraitPossible={false}
      />
    </>
  );
}
