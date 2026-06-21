import React, { useState, useEffect, useRef } from 'react';
import { capturerErreurSentry } from '@/lib/sentry';
import { ouvrirNavigation } from '@/lib/platform';
import { usePageTitle } from '@/hooks/usePageTitle';
import { handleErrorSilent } from '@/lib/handleError';
import { hapticNotification } from '@/lib/haptics';
import { useParams, useNavigate } from 'react-router-dom';
import { ArrowLeft, Phone, Mail, Building2, MessageCircle, MoreHorizontal } from 'lucide-react';
import { ChoixContratDialog } from '@/components/ChoixContratDialog';
import { BoutonNoterMission } from '@/components/BoutonNoterMission';
import { BadgeScoreEtabPublic } from '@/components/BadgeScoreEtabPublic';
import { LayoutApp } from '@/components/LayoutApp';
import { ChargementPage } from '@/components/ChargementPage';
import { BadgeStatut } from '@/components/BadgeStatut';
import { BadgeDistance } from '@/components/BadgeDistance';
import { DecompositionFinanciere } from '@/components/DecompositionFinanciere';
import { FactureHonorairesCard } from '@/components/FactureHonorairesCard';
import { NoteHonoraires } from '@/components/NoteHonoraires';
import { BlocagePostulation } from '@/components/BlocagePostulation';
import { ChatMission } from '@/components/ChatMission';
import { ChatConversation } from '@/components/ChatConversation';
import { BlocConformite } from '@/components/BlocConformite';
import { BoutonExclusion } from '@/components/BoutonExclusion';
import { SignalerUtilisateur } from '@/components/SignalerUtilisateur';
import { CompteurHebdomadaire } from '@/components/CompteurHebdomadaire';
import { ModalConfirmation } from '@/components/ModalConfirmation';
import { ModalCodeTravail } from '@/components/ModalCodeTravail';
import { ModalPerduDeVitesse } from '@/components/ModalPerduDeVitesse';
import { AnimationSuccesMission } from '@/components/AnimationSuccesMission';
import { GoalGradientMission } from '@/components/GoalGradient';
import { useAuth } from '@/contexts/AuthContext';
import { supabase } from '@/integrations/supabase/client';
import { calculerDistanceKm } from '@/lib/geo';
import { getLabelProfession, getLabelTypeEtablissement } from '@/lib/constantes';
import { extraireMessageErreur, estBlocageCodeTravail } from '@/lib/erreurs';
import { calculerCompletionProfil, getMotifProfilIncomplet } from '@/lib/profil-soignant';
import { BoutonY2K } from '@/components/y2k/BoutonY2K';
import { format } from 'date-fns';
import { fr } from 'date-fns/locale';
import { toast } from 'sonner';
import type { Database } from '@/integrations/supabase/types';
import { BlocContratTravailMission } from '@/components/BlocContratTravailMission';
import { BandeauActionPrioritaire, type ActionPrioritaire } from '@/components/BandeauActionPrioritaire';
import { ModaleAnnulationCandidature } from '@/components/soignant/ModaleAnnulationCandidature';
import { AnnulationCandidatureTimer } from '@/components/soignant/AnnulationCandidatureTimer';

type SoignantData = Database['public']['Tables']['soignants']['Row'];

export default function DetailMissionSoignant() {
  usePageTitle('Détail mission');
  const { id } = useParams<{ id: string }>();
  const navigate = useNavigate();
  const { user } = useAuth();
  const [mission, setMission] = useState<any>(null);
  const [etablissement, setEtablissement] = useState<any>(null);
  const [soignant, setSoignant] = useState<SoignantData | null>(null);
  const [countMissions, setCountMissions] = useState(0);
  const [loading, setLoading] = useState(true);
  const [acceptationEnCours, setAcceptationEnCours] = useState(false);

  // Modals
  const [modalConfirm, setModalConfirm] = useState(false);
  const [modalAnnuler, setModalAnnuler] = useState(false);
  const [modalCodeTravail, setModalCodeTravail] = useState<any>(null);
  const [modalPerdu, setModalPerdu] = useState(false);
  const [animationSucces, setAnimationSucces] = useState(false);
  const [conformiteOk, setConformiteOk] = useState(true);
  const [showEvaluation, setShowEvaluation] = useState(true);
  const [chevauchement, setChevauchement] = useState(false);
  const [noteMoyenne, setNoteMoyenne] = useState<{ moyenne: number; total: number } | null>(null);

  // Candidature mode
  const [messageCandidature, setMessageCandidature] = useState('');
  const [candidatureEnvoyee, setCandidatureEnvoyee] = useState(false);
  const [postulationEnCours, setPostulationEnCours] = useState(false);
  const [choixContratDialog, setChoixContratDialog] = useState<{ open: boolean; options: any[]; action: 'postuler' | 'accepter' }>({ open: false, options: [], action: 'postuler' });
  const postulationLockRef = useRef(false);
  const acceptationLockRef = useRef(false);

  // Sprint 5.5 PR 1 : annulation candidature avec fenêtre rétractation 30 min
  const [candidatureRec, setCandidatureRec] = useState<{ id: string; acceptee_a: string | null } | null>(null);
  const [modalAnnulationCandidature, setModalAnnulationCandidature] = useState(false);

  // Session E-6 : actions secondaires (exclure/signaler) repliées derrière un
  // menu « ⋯ » sur mission ouverte — elles ne concurrencent plus le CTA Postuler.
  const [actionsSecondairesOuvertes, setActionsSecondairesOuvertes] = useState(false);

  useEffect(() => {
    if (!user || !id) return;
    const load = async () => {
      const [{ data: m }, { data: s }] = await Promise.all([
        supabase.from('missions').select(`
          id, intitule, description, service, profession_requise,
          debut_le, fin_le, duree_heures, taux_horaire_base, taux_rist_plafonne, rist_plafond_applique,
          heures_nuit, heures_dimanche, heures_ferie,
          montant_majoration_nuit, montant_majoration_dimanche, montant_majoration_ferie,
          taux_ifm, taux_icp, montant_ifm, montant_icp,
          total_brut, net_a_payer, net_estime, est_urgente, niveau_urgence, statut,
          soignant_assigne_id, etablissement_id, cree_le, modifie_le,
          type_contrat_recherche, type_contrat_applique, type_paiement_soignant, mode_paiement_soignant, choix_contrat_soignant,
          numero_note_honoraires,
          mode_attribution, boostee_le, presence_confirmee_le, garantie_remplacement, est_arret_maladie, mode_remuneration, retrocession_pct, montant_honoraires_bruts, honoraires_confirmes_le
        `).eq('id', id).single(),
        supabase.rpc('fn_mon_profil_soignant_complet' as any),
      ]);
      if (m) {
        setMission(m);
        // Fetch etablissement via secure RPC (masque champs sensibles)
        const { data: etab } = await supabase.rpc('fn_etablissement_public' as any, { p_etablissement_id: (m as any).etablissement_id });
        if (etab) setEtablissement(Array.isArray(etab) ? etab[0] : etab);
        // Count missions from this establishment
        const { count } = await supabase.from('missions').select('id', { count: 'exact', head: true }).eq('etablissement_id', (m as any).etablissement_id);
        setCountMissions(count || 0);
      }
      if (s) setSoignant(s as any);

      // Check if already applied (candidature mode)
      if (m && (m as any).mode_attribution === 'CANDIDATURE' && (m as any).statut === 'OUVERTE') {
        const { data: cands } = await supabase.from('candidatures')
          .select('id').eq('mission_id', id).eq('soignant_id', user.id).limit(1);
        if (cands && cands.length > 0) setCandidatureEnvoyee(true);
      }

      // Sprint 5.5 PR 1 : récupère candidature acceptée (id + acceptee_a) pour annulation
      if (m && (m as any).soignant_assigne_id === user.id && ['ASSIGNEE', 'EN_COURS'].includes((m as any).statut)) {
        const { data: candRec } = await supabase.from('candidatures' as any)
          .select('id, acceptee_a, statut')
          .eq('mission_id', id)
          .eq('soignant_id', user.id)
          .eq('statut', 'ACCEPTEE')
          .order('acceptee_a', { ascending: false })
          .limit(1)
          .maybeSingle();
        if (candRec) {
          setCandidatureRec({ id: (candRec as any).id, acceptee_a: (candRec as any).acceptee_a });
        }
      }

      setLoading(false);
    };
    load();
  }, [user, id]);

  // Check for overlapping missions (must be before early return)
  useEffect(() => {
    if (!mission || mission.statut !== 'OUVERTE' || !user) return;
    supabase
      .from('missions')
      .select('id')
      .eq('soignant_assigne_id', user.id)
      .in('statut', ['ASSIGNEE', 'EN_COURS'])
      .lt('debut_le', mission.fin_le)
      .gt('fin_le', mission.debut_le)
      .then(({ data }) => {
        setChevauchement((data || []).length > 0);
      }).then(undefined, (err) => handleErrorSilent(err, 'DetailMissionSoignant.chevauchement'));
  }, [mission, user]);

  // Fetch average rating for the establishment
  useEffect(() => {
    if (!mission?.etablissement_id) return;
    supabase.rpc('fn_note_moyenne' as any, { p_user_id: mission.etablissement_id })
      .then(({ data }: any) => {
        if (data && typeof data === 'object') setNoteMoyenne(data);
        else if (Array.isArray(data) && data[0]) setNoteMoyenne(data[0]);
      }).then(undefined, (err) => handleErrorSilent(err, 'DetailMissionSoignant.noteMoyenne'));
  }, [mission?.etablissement_id]);

  if (loading) return <LayoutApp role="SOIGNANT"><ChargementPage /></LayoutApp>;
  if (!loading && !mission) return <LayoutApp role="SOIGNANT"><div className="text-center py-20"><p className="text-lg font-semibold text-foreground">Mission introuvable</p><p className="text-sm text-muted-foreground mt-2">Cette mission n'existe pas ou a été supprimée.</p><button onClick={() => navigate('/soignant/missions')} className="btn-primary mt-4">Retour aux missions</button></div></LayoutApp>;
  if (!mission || !soignant) return <LayoutApp role="SOIGNANT"><ChargementPage /></LayoutApp>;

  const distance = calculerDistanceKm(
    soignant.adresse_lat, soignant.adresse_lng,
    etablissement?.adresse_lat, etablissement?.adresse_lng
  );
  const resumeCompletion = calculerCompletionProfil(soignant as any);
  const completionProfil = resumeCompletion.pourcentage;
  const premiereMissionLe = (soignant as any).premiere_mission_le;
  // Soft-gating documents : la candidature est toujours possible — le contrôle
  // documents n'intervient qu'à l'acceptation (missions < 7 jours, côté backend).
  const peutPostuler = resumeCompletion.peut_candidater;
  const estAssigne = mission.soignant_assigne_id === user!.id;
  const estOuverte = mission.statut === 'OUVERTE';
  const estTerminee = mission.statut === 'TERMINEE';
  const estAssigneAutre = !estOuverte && !estAssigne && mission.soignant_assigne_id;
  const duree = mission.duree_heures ?? ((new Date(mission.fin_le).getTime() - new Date(mission.debut_le).getTime()) / 3600000);
  const estModeCandidature = mission.mode_attribution === 'CANDIDATURE';

  // Session E-6 : net estimé de la mission (même source que la liste,
  // cf. CarteMissionSoignant) pour la barre sticky mobile.
  const netEstimeMission: number | null = (mission.net_estime ?? mission.net_a_payer ?? null) as number | null;
  const fmtEuroEntier = (v: number) =>
    new Intl.NumberFormat('fr-FR', { style: 'currency', currency: 'EUR', maximumFractionDigits: 0 }).format(v);
  const champsManquants = resumeCompletion.items_obligatoires_manquants;

  /* Hiérarchisation : LA prochaine action attendue du soignant (la plus
     prioritaire seulement, et uniquement si l'état chargé la rend certaine —
     jamais de rappel pour une action peut-être déjà faite). */
  const actionPrioritaire: ActionPrioritaire | null = (() => {
    if (estAssigne && (mission as any).mode_remuneration === 'RETROCESSION'
      && (mission as any).montant_honoraires_bruts && !(mission as any).honoraires_confirmes_le) {
      return {
        titre: "Confirmez votre relevé d'honoraires",
        description: `Le cabinet déclare ${Number((mission as any).montant_honoraires_bruts).toLocaleString('fr-FR')} € — validez ou contestez sous 48h.`,
        cta: 'Voir le relevé',
        cibleId: 'bloc-retro-confirm',
        variante: 'warning',
      };
    }
    if (estAssigne && mission.statut === 'ASSIGNEE'
      && new Date(mission.debut_le).getTime() - Date.now() < 48 * 3600000
      && new Date(mission.debut_le).getTime() > Date.now()
      && !(mission as any).presence_confirmee_le) {
      return {
        titre: 'Confirmez votre présence',
        description: 'La mission démarre bientôt — 1 clic pour rassurer l\'établissement.',
        cta: 'Confirmer',
        cibleId: 'bloc-presence',
        variante: 'warning',
      };
    }
    // Session E-6 : profil incomplet = la complétion EST l'action n°1 de l'écran
    // (jamais de dead-end — standard onboarding Uber).
    if (estOuverte && !peutPostuler && !candidatureEnvoyee) {
      const n = champsManquants.length;
      return {
        titre: n > 0
          ? `Complétez votre profil pour postuler (${n} champ${n > 1 ? 's' : ''})`
          : 'Complétez votre profil pour postuler',
        description: getMotifProfilIncomplet(resumeCompletion) ?? undefined,
        cta: 'Compléter mon profil',
        onClick: () => navigate('/soignant/profil'),
        variante: 'warning',
      };
    }
    if (estOuverte && peutPostuler && !candidatureEnvoyee && !chevauchement) {
      return {
        titre: estModeCandidature ? 'Postulez à cette mission' : 'Acceptez cette mission',
        description: estModeCandidature
          ? 'L\'établissement examinera votre profil et vous répondra.'
          : 'Premier arrivé, premier servi — la mission part vite.',
        cta: estModeCandidature ? 'Postuler' : 'Accepter',
        cibleId: 'bloc-actions',
      };
    }
    return null;
  })();

  const postulerMission = async (choixContrat?: string) => {
    if (postulationLockRef.current) return;
    postulationLockRef.current = true;
    setPostulationEnCours(true);
    try {
      const params: any = { p_mission_id: id!, p_message: messageCandidature || null };
      if (choixContrat) params.p_choix_contrat = choixContrat;
      const { data, error } = await supabase.rpc('fn_postuler_mission_rate_limited' as any, params);
      if (error) { toast.error(extraireMessageErreur(error)); return; }
      if (data?.choix_requis) {
        setChoixContratDialog({ open: true, options: data.options || [], action: 'postuler' });
        return;
      }
      if (data?.error) { toast.error(data.error); return; }
      setCandidatureEnvoyee(true);
      if (data?.docs_a_completer) {
        toast.success('Candidature envoyée ! Validez vos documents pour pouvoir être accepté.', {
          action: { label: 'Mes documents', onClick: () => navigate('/soignant/mes-documents') },
          duration: 8000,
        });
      } else {
        toast.success('Candidature envoyée ! L\'établissement examinera votre profil.');
      }
    } catch (err: any) {
      capturerErreurSentry(err, 'DetailMissionSoignant', 'candidature');
      toast.error(extraireMessageErreur(err));
    } finally {
      postulationLockRef.current = false;
      setPostulationEnCours(false);
    }
  };

  const accepterMission = async (choixContrat?: string) => {
    if (acceptationLockRef.current) return;
    acceptationLockRef.current = true;
    setAcceptationEnCours(true);
    try {
      const params: any = { p_mission_id: id! };
      if (choixContrat) params.p_choix_contrat = choixContrat;
      const { data, error } = await supabase.rpc('fn_accepter_mission' as any, params);

      if (error) {
        if (estBlocageCodeTravail(error)) {
          setModalCodeTravail(error);
        } else if (error.message?.includes('0 rows') || error.message?.includes('déjà prise')) {
          setModalPerdu(true);
        } else {
          toast.error(extraireMessageErreur(error));
        }
        return;
      }
      if (data?.choix_requis) {
        setChoixContratDialog({ open: true, options: data.options || [], action: 'accepter' });
        return;
      }
      if (data?.error) {
        toast.error(data.error);
        return;
      }

      // Audit HDS
      const { error: auditError } = await supabase.rpc('fn_ecrire_audit_safe', {
        p_acteur_id: user!.id,
        p_type_acteur: 'SOIGNANT',
        p_action: 'MISSION_ASSIGNATION',
        p_type_ressource: 'mission',
        p_id_ressource: id!,
        p_cle_s3: null,
        p_details: {
          intitule: mission.intitule,
          etablissement: etablissement?.nom,
          debut: mission.debut_le,
          fin: mission.fin_le,
        },
        p_ip: null,
        p_navigateur: navigator.userAgent,
      });
      if (auditError) handleErrorSilent(auditError, 'Audit assignation mission');

      setMission({ ...mission, statut: 'ASSIGNEE', soignant_assigne_id: user!.id });
      setAnimationSucces(true);
      hapticNotification('success');

      // Redirect to contract signing after animation
      if (data?.contrat_id) {
        setTimeout(() => navigate(`/contrat/${data.contrat_id}`), 2000);
      }

      // Email au soignant
      supabase.functions.invoke('send-email', {
        body: {
          type: 'MISSION_ACCEPTEE_SOIGNANT',
          data: {
            prenom: soignant.prenom,
            mission: mission.intitule,
            etablissement: etablissement?.nom || '',
            date: format(new Date(mission.debut_le), 'EEEE d MMMM yyyy', { locale: fr }),
            heure_debut: format(new Date(mission.debut_le), "HH'h'mm", { locale: fr }),
            heure_fin: format(new Date(mission.fin_le), "HH'h'mm", { locale: fr }),
            taux_horaire: mission.taux_horaire_base,
            mission_id: id,
          },
          destinataire_id: user!.id,
        },
      }).then(undefined, (err) => handleErrorSilent(err, 'DetailMissionSoignant.email-soignant'));

      // Email à l'établissement (établissement role can send to other addresses)
      {
        supabase.functions.invoke('send-email', {
          body: {
            type: 'MISSION_ACCEPTEE_ETABLISSEMENT',
            data: {
              soignant_nom: `${soignant.prenom} ${soignant.nom}`,
              profession: soignant.profession,
              mission: mission.intitule,
              date: format(new Date(mission.debut_le), 'EEEE d MMMM yyyy', { locale: fr }),
              mission_id: id,
            },
            destinataire_id: mission.etablissement_id,
          },
        }).then(undefined, (err) => handleErrorSilent(err, 'DetailMissionSoignant.email-etablissement'));
      }
    } finally {
      acceptationLockRef.current = false;
      setAcceptationEnCours(false);
    }
  };

  const annulerParticipation = async () => {
    const { data, error } = await supabase.rpc('fn_annuler_mission_soignant' as any, { p_mission_id: id! });

    if (error) {
      toast.error(extraireMessageErreur(error));
      return;
    }
    if (data?.error) {
      toast.error(data.error);
      return;
    }

    const { error: auditError } = await supabase.rpc('fn_ecrire_audit_safe', {
      p_acteur_id: user!.id,
      p_type_acteur: 'SOIGNANT',
      p_action: 'MISSION_ANNULATION',
      p_type_ressource: 'mission',
      p_id_ressource: id!,
      p_cle_s3: null,
      p_details: { motif: 'Annulation volontaire par le soignant' },
      p_ip: null,
      p_navigateur: navigator.userAgent,
    });
    if (auditError) handleErrorSilent(auditError, 'Audit annulation participation');

    toast.warning('Participation annulée. Votre score sera mis à jour.');
    navigate('/soignant/missions');
  };

  return (
    <LayoutApp role="SOIGNANT">
      <button onClick={() => navigate(-1)} className="flex items-center gap-1 text-sm text-primary mb-4 hover:underline">
        <ArrowLeft className="h-4 w-4" /> Retour
      </button>

      {actionPrioritaire && <BandeauActionPrioritaire {...actionPrioritaire} />}

      <div className="grid grid-cols-1 lg:grid-cols-2 gap-4">
        {/* Col 1 — Infos */}
        <div className="space-y-4">
          {/* Goal gradient banner */}
          {estOuverte && (soignant as any).heures_cumulees != null && (
            <GoalGradientMission heures={(soignant as any).heures_cumulees || 0} dureeHeuresMission={duree} />
          )}
          {/* Mission info */}
          <div className="card-base">
            <div className="flex items-center gap-2 flex-wrap mb-2">
              <BadgeStatut statut={mission.statut} />
              {mission.est_urgente && <span className="badge-base bg-destructive text-destructive-foreground text-[10px]">🔥 URGENT</span>}
            </div>
            <h1 className="text-lg font-bold text-foreground mb-1">{mission.intitule}</h1>
            {mission.description && <p className="text-sm text-muted-foreground mb-2">{mission.description}</p>}
            <p className="text-xs text-muted-foreground">
              {getLabelProfession(mission.profession_requise)} {mission.service && `· ${mission.service}`}
            </p>
          </div>

          {/* Établissement */}
          <div className="card-base bg-muted/30">
            <div className="flex items-start gap-3">
              <Building2 className="h-5 w-5 text-primary shrink-0 mt-0.5" />
              <div>
                <div className="flex items-center gap-2 flex-wrap">
                  <h3 className="font-semibold text-sm text-foreground">{etablissement?.nom}</h3>
                  {estAssigne && mission.etablissement_id && (
                    <BadgeScoreEtabPublic etablissementId={mission.etablissement_id} />
                  )}
                  {estAssigne && (
                    <button
                      type="button"
                      onClick={async () => {
                        // Resolve etablissement_id to the actual user_id
                        const { data: userId, error: resolveError } = await supabase.rpc('fn_user_id_pour_etablissement' as any, { p_etablissement_id: mission.etablissement_id });
                        if (resolveError || !userId) {
                          toast.error("Impossible de trouver l'interlocuteur de l'établissement.");
                          return;
                        }
                        const { data, error } = await supabase.rpc('fn_obtenir_conversation', { p_autre_id: userId, p_mission_id: mission.id });
                        if (error) {
                          toast.error("Impossible d'ouvrir la conversation.");
                        } else if (data) {
                          navigate(`/soignant/messagerie?conv=${data}`);
                        } else {
                          toast.error("Impossible d'ouvrir la conversation.");
                        }
                      }}
                      className="h-8 w-8 rounded-full bg-primary text-primary-foreground flex items-center justify-center hover:bg-primary/90 transition-colors shrink-0"
                      title="Contacter l'établissement"
                    >
                      <MessageCircle className="h-4 w-4" />
                    </button>
                  )}
                </div>
                <p className="text-xs text-muted-foreground">{getLabelTypeEtablissement(etablissement?.type)}</p>
                <p className="text-xs text-muted-foreground mt-1">
                  {etablissement?.adresse_rue}, {etablissement?.adresse_code_postal} {etablissement?.adresse_ville}
                  {etablissement?.adresse_departement && ` (${etablissement.adresse_departement})`}
                </p>
                <div className="mt-1 flex items-center gap-2 flex-wrap">
                  <BadgeDistance distanceKm={distance} />
                  {/* Session E-6 : liens de navigation utiles à J-1 de la mission,
                      bruit au moment de candidater → visibles seulement si assigné. */}
                  {estAssigne && etablissement?.adresse_lat && etablissement?.adresse_lng && (
                    <>
                      <button
                        onClick={() => ouvrirNavigation(etablissement.adresse_lat, etablissement.adresse_lng, etablissement.nom).plans()}
                        className="inline-flex items-center gap-1 rounded-full bg-primary/10 text-primary text-xs font-medium px-2.5 py-1.5 hover:bg-primary/20 transition-colors"
                      >
                        📍 Plans
                      </button>
                      <button
                        onClick={() => ouvrirNavigation(etablissement.adresse_lat, etablissement.adresse_lng, etablissement.nom).googleMaps()}
                        className="inline-flex items-center gap-1 rounded-full bg-primary/10 text-primary text-xs font-medium px-2.5 py-1.5 hover:bg-primary/20 transition-colors"
                      >
                        🗺️ Maps
                      </button>
                      <button
                        onClick={() => ouvrirNavigation(etablissement.adresse_lat, etablissement.adresse_lng, etablissement.nom).waze()}
                        className="inline-flex items-center gap-1 rounded-full bg-primary/10 text-primary text-xs font-medium px-2.5 py-1.5 hover:bg-primary/20 transition-colors"
                      >
                        🚗 Waze
                      </button>
                    </>
                  )}
                </div>
                {/* L4: Contact info only visible after assignment */}
                {estAssigne && (
                  <div className="mt-2 space-y-1">
                    {etablissement?.telephone_contact && (
                      <a href={`tel:${etablissement.telephone_contact}`} className="flex items-center gap-1.5 text-xs text-primary hover:underline">
                        <Phone className="h-3.5 w-3.5" /> {etablissement.telephone_contact}
                      </a>
                    )}
                    {etablissement?.email_contact && (
                      <a href={`mailto:${etablissement.email_contact}`} className="flex items-center gap-1.5 text-xs text-primary hover:underline">
                        <Mail className="h-3.5 w-3.5" /> {etablissement.email_contact}
                      </a>
                    )}
                  </div>
                )}
                {noteMoyenne && noteMoyenne.total > 0 && (
                  <p className="text-xs text-foreground mt-2">
                    ⭐ {noteMoyenne.moyenne.toFixed(1)}/5 — {noteMoyenne.total} évaluation{noteMoyenne.total > 1 ? 's' : ''}
                  </p>
                )}
                <p className="text-[10px] text-muted-foreground/60 mt-1">
                  Cet établissement a publié {countMissions} mission{countMissions > 1 ? 's' : ''} sur Jolene
                </p>
                {/* E2: Blacklist côté soignant.
                    Session E-6 : sur mission ouverte (pas encore de relation),
                    exclure/signaler sont repliés derrière « ⋯ » (pattern Airbnb)
                    pour ne pas concurrencer le CTA Postuler. */}
                {mission.etablissement_id && (
                  estOuverte && !estAssigne ? (
                    <div className="mt-2 pt-2 border-t border-border">
                      <button
                        type="button"
                        onClick={() => setActionsSecondairesOuvertes(v => !v)}
                        aria-expanded={actionsSecondairesOuvertes}
                        className="flex items-center gap-1.5 text-xs text-muted-foreground hover:text-foreground transition-colors"
                      >
                        <MoreHorizontal className="h-4 w-4" /> Autres actions
                      </button>
                      {actionsSecondairesOuvertes && (
                        <div className="mt-2 flex items-center gap-3">
                          <BoutonExclusion excluId={mission.etablissement_id} typeExcluPar="SOIGNANT" />
                          <SignalerUtilisateur cibleId={mission.etablissement_id} cibleType="ETABLISSEMENT" missionId={mission.id} />
                        </div>
                      )}
                    </div>
                  ) : (
                    <div className="mt-2 pt-2 border-t border-border flex items-center gap-3">
                      <BoutonExclusion excluId={mission.etablissement_id} typeExcluPar="SOIGNANT" />
                      <SignalerUtilisateur cibleId={mission.etablissement_id} cibleType="ETABLISSEMENT" missionId={mission.id} />
                    </div>
                  )
                )}
              </div>
            </div>
          </div>

          {/* Horaires */}
          <div className="card-base">
            <h3 className="font-semibold text-sm text-foreground mb-2">🕐 Horaires</h3>
            <p className="text-sm text-foreground">📅 {format(new Date(mission.debut_le), 'EEEE d MMMM yyyy', { locale: fr })}</p>
            <p className="text-sm text-foreground">
              🕐 {format(new Date(mission.debut_le), "HH'h'mm", { locale: fr })} → {format(new Date(mission.fin_le), "HH'h'mm", { locale: fr })} ({Math.round(duree)}h)
            </p>
            <div className="flex flex-wrap gap-2 mt-2">
              {(mission.heures_nuit || 0) > 0 && <span className="badge-base bg-indigo-100 text-indigo-700">🌙 {mission.heures_nuit}h de nuit</span>}
              {(mission.heures_dimanche || 0) > 0 && <span className="badge-base bg-amber-100 text-amber-700">☀️ {mission.heures_dimanche}h de dimanche</span>}
              {(mission.heures_ferie || 0) > 0 && <span className="badge-base bg-red-100 text-red-700">🎌 {mission.heures_ferie}h de jour férié</span>}
            </div>
          </div>
        </div>

        {/* Col 2 — Finance + Actions */}
        <div className="space-y-4">
          {/* Compteur hebdomadaire compact */}
          {estOuverte && (
            <CompteurHebdomadaire compact missionCandidateHeures={mission.duree_heures || 0} />
          )}

          {/* Rémunération — Note d'honoraires pour libéraux, décomposition classique sinon */}
          {(soignant as any).type_contrat === 'LIBERAL' && estTerminee ? (
            <NoteHonoraires
              mission={mission}
              soignant={soignant}
              onAudit={() => {
                supabase.rpc('fn_ecrire_audit_safe', {
                  p_acteur_id: user!.id, p_type_acteur: 'SOIGNANT',
                  p_action: 'NOTE_HONORAIRES_GENEREE',
                  p_type_ressource: 'mission', p_id_ressource: id!,
                  p_cle_s3: null, p_details: { numero: mission.numero_note_honoraires },
                  p_ip: null, p_navigateur: navigator.userAgent,
                });
              }}
            />
          ) : (mission as any).mode_remuneration === 'RETROCESSION' && (mission as any).montant_honoraires_bruts && !(mission as any).honoraires_confirmes_le && mission.soignant_assigne_id === user?.id ? (
            <div id="bloc-retro-confirm" className="card-base border-warning/40 bg-warning/5 space-y-2">
              <p className="text-sm font-semibold text-foreground">💶 Relevé d'honoraires à confirmer</p>
              <p className="text-xs text-muted-foreground">
                Le cabinet déclare <strong>{Number((mission as any).montant_honoraires_bruts).toLocaleString('fr-FR')} €</strong> d'honoraires
                (justificatif joint à la mission) — votre rétrocession ({(mission as any).retrocession_pct}%) :
                <strong> {Number(mission.net_a_payer ?? 0).toLocaleString('fr-FR')} €</strong>.
                Sans action de votre part, validation automatique sous 48h.
              </p>
              <div className="flex gap-2">
                <button
                  onClick={async () => {
                    const { data, error } = await supabase.rpc('fn_confirmer_honoraires_retrocession' as any, { p_mission_id: mission.id });
                    if (error || (data as any)?.error) { toast.error((data as any)?.error || 'Confirmation impossible.'); return; }
                    toast.success('Relevé confirmé — votre note d\'honoraires est générée, le cabinet est notifié.');
                    setMission((prev: any) => ({ ...prev, honoraires_confirmes_le: new Date().toISOString() }));
                  }}
                  className="btn-primary flex-1 text-sm py-2.5"
                >
                  ✓ Je confirme le relevé
                </button>
                <button
                  onClick={() => navigate('/soignant/litiges')}
                  className="flex-1 text-sm py-2.5 rounded-xl border border-destructive/40 text-destructive hover:bg-destructive/5"
                >
                  Contester (litige)
                </button>
              </div>
            </div>
          ) : (mission as any).mode_remuneration === 'RETROCESSION' ? (
            <div className="card-base border-primary/20">
              <p className="text-sm font-semibold text-foreground mb-1">🤝 Remplacement de cabinet — rétrocession d'honoraires</p>
              <p className="text-3xl font-extrabold text-primary mb-2">{(mission as any).retrocession_pct ?? '—'}%</p>
              <p className="text-xs text-muted-foreground">
                Vous exercez sous les feuilles de soins du titulaire : il encaisse les honoraires
                puis vous rétrocède {(mission as any).retrocession_pct ?? '—'}% des actes réalisés
                (contrat de remplacement conforme au modèle de l'Ordre, généré à l'acceptation).
                RCP obligatoire.
              </p>
              {(mission as any).honoraires_confirmes_le && (
                <p className="text-xs text-success mt-2">✓ Relevé confirmé — rétrocession de {Number(mission.net_a_payer ?? 0).toLocaleString('fr-FR')} € validée</p>
              )}
            </div>
          ) : (
            <DecompositionFinanciere mission={mission} role="SOIGNANT" />
          )}
          {(mission as any).mode_remuneration !== 'RETROCESSION' && (
          <p className="text-xs text-muted-foreground/60 italic text-center">
            Simulation à titre indicatif. Seuls les montants calculés par le moteur de paie font foi.
          </p>
          )}

          {/* Facture honoraires — visible dès que mission TERMINEE (facture générée) */}
          {estTerminee && (
            <FactureHonorairesCard missionId={mission.id} viewerRole="SOIGNANT" />
          )}

          {estTerminee && estAssigne && (
            <div className="card-base">
              <div className="flex items-center justify-between gap-3">
                <div>
                  <h3 className="font-semibold text-foreground">Notez l'établissement</h3>
                  <p className="text-xs text-muted-foreground mt-0.5">
                    Votre notation aide la communauté + améliore votre score (composante "Notation par soignant").
                  </p>
                </div>
                <BoutonNoterMission missionId={mission.id} sens="SOIGNANT_VERS_ETAB" missionIntitule={mission.intitule} variant="primary" />
              </div>
            </div>
          )}

          {/* Bloc de conformité (missions ouvertes) */}
          {estOuverte && peutPostuler && (
            <BlocConformite missionId={id!} onResultat={setConformiteOk} />
          )}

          {/* Lien planning */}
          {estOuverte && (
            <button
              onClick={() => navigate(`/soignant/planning?highlight=${id}`)}
              className="text-xs text-primary font-medium hover:underline flex items-center gap-1"
            >
              📅 Voir dans mon planning
            </button>
          )}

          {/* Actions */}
          <div id="bloc-actions" className="card-base">
            {estOuverte && (
              <>
                <BlocagePostulation completionProfil={completionProfil} documentsValides={!!soignant.tous_documents_valides} premiereMissionLe={premiereMissionLe} missionDebutLe={mission.debut_le} />
                {chevauchement && (
                  <div className="bg-warning/10 border border-warning/30 rounded-xl p-3 mb-3 text-center">
                    <p className="text-sm font-semibold text-warning">⚠️ Vous avez déjà une mission sur ce créneau</p>
                    <p className="text-xs text-warning/80 mt-1">Vous ne pouvez pas accepter deux missions qui se chevauchent.</p>
                  </div>
                )}
                {/* Session E-6 : profil incomplet → la complétion devient l'action
                    primaire de l'écran (pas de dead-end), avec les champs nommés. */}
                {!peutPostuler && !candidatureEnvoyee && (
                  <div className="space-y-3">
                    {champsManquants.length > 0 && (
                      <div className="bg-muted/40 rounded-xl p-3">
                        <p className="text-xs font-semibold text-foreground mb-1.5">
                          Il manque {champsManquants.length} information{champsManquants.length > 1 ? 's' : ''} pour pouvoir postuler :
                        </p>
                        <ul className="space-y-1">
                          {champsManquants.map((item) => (
                            <li key={item.cle} className="text-xs text-muted-foreground flex items-center gap-1.5">
                              <span className="text-warning" aria-hidden="true">•</span> {item.label}
                            </li>
                          ))}
                        </ul>
                      </div>
                    )}
                    <BoutonY2K size="lg" className="w-full" onClick={() => navigate('/soignant/profil')}>
                      Compléter mon profil pour postuler
                    </BoutonY2K>
                  </div>
                )}
                {peutPostuler && !candidatureEnvoyee && (
                  <>
                    {estModeCandidature ? (
                      <>
                        <div className="mb-3">
                          <label className="text-xs font-medium text-foreground mb-1 block">Message à l'établissement (optionnel)</label>
                          <textarea
                            value={messageCandidature}
                            onChange={e => setMessageCandidature(e.target.value.slice(0, 300))}
                            placeholder="Présentez-vous brièvement…"
                            rows={3}
                            className="input-base resize-none text-sm"
                            maxLength={300}
                          />
                          <p className="text-[10px] text-muted-foreground text-right mt-0.5">{messageCandidature.length}/300</p>
                        </div>
                        <button
                          onClick={() => postulerMission()}
                          disabled={postulationEnCours || !conformiteOk || chevauchement}
                          className="btn-primary w-full text-base py-3.5 disabled:opacity-50 active:scale-[0.97] transition-transform"
                        >
                          {postulationEnCours ? 'Envoi en cours…' : '📨 Postuler à cette mission'}
                        </button>
                        <p className="text-[10px] text-muted-foreground text-center mt-2">
                          L'établissement examinera votre candidature. Vous serez notifié(e) de sa décision.
                        </p>
                      </>
                    ) : (
                      <>
                        <button
                          onClick={() => setModalConfirm(true)}
                          disabled={acceptationEnCours || !conformiteOk || chevauchement}
                          className="btn-primary w-full text-base py-3.5 disabled:opacity-50 active:scale-[0.97] transition-transform"
                          title={chevauchement ? 'Mission chevauchante détectée' : !conformiteOk ? 'Résolvez les conflits ci-dessus pour accepter' : undefined}
                        >
                          {acceptationEnCours ? 'Acceptation en cours…' : '★ Accepter cette mission'}
                        </button>
                        <p className="text-[10px] text-muted-foreground text-center mt-2">
                          En acceptant, vous vous engagez à être présent(e) aux dates et horaires indiqués.
                        </p>
                      </>
                    )}
                    {!conformiteOk && (
                      <p className="text-[10px] text-destructive text-center mt-2">
                        ⛔ Résolvez les conflits de conformité ci-dessus pour pouvoir accepter.
                      </p>
                    )}
                  </>
                )}
                {candidatureEnvoyee && estOuverte && (
                  <div className="bg-success/5 border border-success/20 rounded-xl p-3 text-center space-y-2">
                    <p className="text-sm font-semibold text-success">✅ Candidature envoyée — En attente de réponse</p>
                    {/* Session E-6 : prochaine étape persistante (pas seulement un
                        toast de 8 s) — documents requis pour pouvoir être accepté. */}
                    {!soignant.tous_documents_valides ? (
                      <>
                        <p className="text-xs text-muted-foreground">
                          Prochaine étape : validez vos documents pour que l'établissement puisse vous accepter.
                        </p>
                        <BoutonY2K className="w-full" onClick={() => navigate('/soignant/mes-documents')}>
                          📄 Valider mes documents (2 min)
                        </BoutonY2K>
                      </>
                    ) : (
                      <p className="text-xs text-muted-foreground">L'établissement examinera votre profil et reviendra vers vous.</p>
                    )}
                  </div>
                )}
              </>
            )}

            {estAssigne && (
              <>
                <div className="bg-success/5 border border-success/20 rounded-xl p-3 mb-4 text-center">
                  <p className="text-sm font-semibold text-success">✅ Vous êtes assigné(e) à cette mission</p>
                </div>

                {/* Confirmation de présence (J-2 → début) : rassure l'établissement,
                    alimente la garantie remplacement côté étab. */}
                {mission.statut === 'ASSIGNEE'
                  && new Date(mission.debut_le).getTime() - Date.now() < 48 * 3600000
                  && new Date(mission.debut_le).getTime() > Date.now()
                  && !(mission as any).presence_confirmee_le && (
                  <div id="bloc-presence" className="bg-warning/5 border border-warning/30 rounded-xl p-3 mb-4">
                    <p className="text-sm font-semibold text-foreground">Confirmez votre présence</p>
                    <p className="text-xs text-muted-foreground mt-1 mb-2">
                      La mission démarre bientôt — confirmez en 1 clic pour rassurer l'établissement.
                    </p>
                    <button
                      onClick={async () => {
                        const { data, error } = await supabase.rpc('fn_confirmer_presence_mission' as any, { p_mission_id: mission.id });
                        if (error || (data as any)?.error) { toast.error((data as any)?.error || 'Confirmation impossible.'); return; }
                        toast.success('Présence confirmée — l\'établissement est prévenu. ✓');
                        setMission((prev: any) => ({ ...prev, presence_confirmee_le: new Date().toISOString() }));
                      }}
                      className="btn-primary w-full text-sm py-2.5"
                    >
                      ✓ Je confirme ma présence
                    </button>
                  </div>
                )}
                {mission.statut === 'ASSIGNEE' && (mission as any).presence_confirmee_le && (
                  <div className="bg-success/5 border border-success/20 rounded-xl p-2.5 mb-4 text-center">
                    <p className="text-xs text-success">✓ Présence confirmée — l'établissement est prévenu</p>
                  </div>
                )}

                {/* Arrêt maladie : sans pénalité de score (justificatif sous 48h),
                    étab prévenu, remplacement automatique si mission garantie. */}
                {(mission.statut === 'ASSIGNEE' || mission.statut === 'EN_COURS') && !(mission as any).est_arret_maladie && (
                  <button
                    onClick={async () => {
                      if (!window.confirm('Déclarer un arrêt maladie sur cette mission ? L\'établissement sera prévenu immédiatement et vous devrez fournir un certificat médical sous 48h. Aucune pénalité de score avec justificatif.')) return;
                      const { data, error } = await supabase.rpc('fn_declarer_arret_maladie' as any, { p_mission_id: mission.id });
                      if (error || (data as any)?.error) { toast.error((data as any)?.error || 'Déclaration impossible.'); return; }
                      toast.success('Arrêt maladie déclaré — pensez au certificat médical sous 48h. Bon rétablissement.');
                      setMission((prev: any) => ({ ...prev, est_arret_maladie: true }));
                    }}
                    className="w-full text-xs text-muted-foreground hover:text-foreground underline mb-4"
                  >
                    🏥 Je dois me désister pour raison médicale (arrêt maladie)
                  </button>
                )}
                {(mission as any).est_arret_maladie && (
                  <div className="bg-warning/5 border border-warning/20 rounded-xl p-3 mb-4 space-y-2">
                    <p className="text-xs text-warning text-center">🏥 Arrêt maladie déclaré — certificat médical à fournir sous 48h</p>
                    <label className="btn-primary w-full text-sm py-2.5 text-center cursor-pointer block">
                      📎 Téléverser mon certificat (vérifié automatiquement)
                      <input
                        type="file"
                        accept="image/*,.pdf"
                        className="hidden"
                        onChange={async (e) => {
                          const fichier = e.target.files?.[0];
                          if (!fichier || !user) return;
                          const nomSanitise = fichier.name.normalize('NFD').replace(/[\u0300-\u036f]/g, '').replace(/[^\w.-]+/g, '-');
                          const chemin = `${user.id}/documents/ARRET_MALADIE/${Date.now()}-${nomSanitise}`;
                          const { error: upErr } = await supabase.storage.from('jolene-documents')
                            .upload(chemin, fichier, { contentType: fichier.type || undefined, upsert: false });
                          if (upErr) { toast.error('Téléversement impossible.'); return; }
                          const { data: doc, error: insErr } = await supabase.from('documents_soignants').insert({
                            soignant_id: user.id,
                            type_document: 'ARRET_MALADIE' as any,
                            libelle: `Arrêt maladie — mission ${mission.intitule}`.slice(0, 120),
                            s3_bucket: 'jolene-documents', s3_cle: chemin,
                            nom_fichier: fichier.name, type_mime: fichier.type, taille_octets: fichier.size,
                            statut_verification: 'EN_ATTENTE',
                          } as any).select().single();
                          if (insErr || !doc) {
                            await supabase.storage.from('jolene-documents').remove([chemin]);
                            toast.error('Enregistrement impossible.');
                            return;
                          }
                          toast.success('Certificat reçu — vérification automatique en cours.');
                          supabase.functions.invoke('verify-document', { body: { document_id: (doc as any).id } })
                            .then(({ data: v }) => {
                              if ((v as any)?.verdict === 'VERIFIE') toast.success('✅ Certificat vérifié — arrêt justifié, aucun impact score.');
                              else if ((v as any)?.verdict === 'REJETE') toast.error('❌ Certificat rejeté : ' + ((v as any)?.analysis?.motif_rejet || 'non conforme') + '. Re-téléversez un document lisible.');
                            });
                        }}
                      />
                    </label>
                  </div>
                )}

                {/* Sprint 5.5 PR 1 : statut rétractation Sprint 3.5 */}
                {candidatureRec?.acceptee_a && (
                  <div className="mb-4">
                    <AnnulationCandidatureTimer
                      accepteeA={candidatureRec.acceptee_a}
                      debutMission={mission.debut_le}
                      estAsap={Boolean((mission as any).est_urgente)}
                    />
                  </div>
                )}
                <div className="mb-4">
                  <BlocContratTravailMission
                    missionId={mission.id}
                    typeContratApplique={(mission as any).type_contrat_applique}
                    soignantAssigneId={mission.soignant_assigne_id}
                    etablissementId={mission.etablissement_id}
                    debutLe={mission.debut_le}
                    role="SOIGNANT"
                  />
                </div>
                <button
                  type="button"
                  onClick={async () => {
                    const { data: userId, error: resolveError } = await supabase.rpc('fn_user_id_pour_etablissement' as any, { p_etablissement_id: mission.etablissement_id });
                    if (resolveError || !userId) {
                      toast.error("Impossible de trouver l'interlocuteur de l'établissement.");
                      return;
                    }
                    const { data, error } = await supabase.rpc('fn_obtenir_conversation', { p_autre_id: userId, p_mission_id: mission.id });
                    if (error) {
                      toast.error("Impossible d'ouvrir la conversation.");
                    } else if (data) {
                      navigate(`/soignant/messagerie?conv=${data}`);
                    } else {
                      toast.error("Impossible d'ouvrir la conversation.");
                    }
                  }}
                  className="btn-secondary w-full text-sm py-2.5 mb-3"
                >
                  💬 Contacter l'établissement
                </button>
                <button
                  onClick={() => candidatureRec ? setModalAnnulationCandidature(true) : setModalAnnuler(true)}
                  className="w-full border-2 border-destructive text-destructive rounded-xl px-4 py-2.5 text-sm font-medium hover:bg-destructive/5 transition-colors"
                >
                  Annuler ma participation
                </button>
              </>
            )}

            {estTerminee && (
              <div className="bg-success/5 border border-success/20 rounded-xl p-3 text-center">
                <p className="text-sm font-semibold text-success">✅ Mission terminée</p>
              </div>
            )}

            {mission.statut === 'ABSENCE' && (
              <div className="bg-destructive/10 border border-destructive/30 rounded-xl p-3 text-center space-y-1">
                <p className="text-sm font-semibold text-destructive">❌ Mission marquée absence — score impacté (-20 pts)</p>
                <p className="text-xs text-destructive/80">Si c'est une erreur, contactez l'établissement pour correction.</p>
              </div>
            )}

            {estAssigneAutre && (
              <div className="text-center">
                <p className="text-sm text-muted-foreground mb-3">Cette mission a déjà été attribuée</p>
                <button onClick={() => navigate('/soignant/missions')} className="btn-secondary text-sm">
                  Voir d'autres missions →
                </button>
              </div>
            )}
          </div>

          {/* Chat — visible si ASSIGNEE, EN_COURS, TERMINEE, ABSENCE ou LITIGE */}
          {(mission.statut === 'ASSIGNEE' || mission.statut === 'EN_COURS' || mission.statut === 'TERMINEE' || mission.statut === 'ABSENCE' || mission.statut === 'LITIGE') && estAssigne && (
            <div id="chat-mission">
              <ChatConversation
                missionId={mission.id}
                autreUserId={mission.etablissement_id}
                isEtablissement
              />
            </div>
          )}
        </div>
      </div>

      {/* Session E-6 : barre sticky mobile « checkout » (pattern réservation
          Airbnb / RDV Doctolib) — net estimé + CTA toujours visibles, mêmes
          conditions et même action que le CTA du bloc-actions. Positionnée
          au-dessus de la bottom nav mobile (4rem + safe-area). */}
      {estOuverte && peutPostuler && !candidatureEnvoyee && (
        <>
          {/* Espace pour que la barre ne masque pas le bas de page */}
          <div className="h-16 md:hidden" aria-hidden="true" />
          <div
            className="md:hidden fixed left-0 right-0 z-40 border-t border-border bg-card/95 backdrop-blur-xl supports-[backdrop-filter]:bg-card/85 px-4 py-2.5 flex items-center justify-between gap-3 shadow-[0_-4px_16px_-4px_rgba(0,0,0,0.12)]"
            style={{ bottom: 'calc(4rem + env(safe-area-inset-bottom))' }}
          >
            <div className="min-w-0">
              {(mission as any).mode_remuneration === 'RETROCESSION' ? (
                <p className="text-base font-bold text-primary leading-tight">
                  🤝 Rétrocession {(mission as any).retrocession_pct ?? '—'}%
                </p>
              ) : netEstimeMission != null && netEstimeMission > 0 ? (
                <>
                  <p className="text-base font-bold text-foreground leading-tight">~{fmtEuroEntier(netEstimeMission)} net</p>
                  <p className="text-[10px] text-muted-foreground leading-tight">estimé, figé à l'acceptation</p>
                </>
              ) : (
                <p className="text-base font-bold text-foreground leading-tight">
                  {(mission.taux_rist_plafonne || mission.taux_horaire_base)?.toFixed(2)} €/h
                </p>
              )}
            </div>
            <BoutonY2K
              className="shrink-0"
              loading={postulationEnCours || acceptationEnCours}
              disabled={!conformiteOk || chevauchement}
              onClick={() => (estModeCandidature ? postulerMission() : setModalConfirm(true))}
            >
              {estModeCandidature ? '📨 Postuler' : '★ Accepter'}
            </BoutonY2K>
          </div>
        </>
      )}

      {/* Modals */}
      <ModalConfirmation
        ouvert={modalConfirm}
        onFermer={() => setModalConfirm(false)}
        onConfirmer={() => accepterMission()}
        titre="Accepter cette mission ?"
        message={`Vous vous engagez à être présent(e) le ${format(new Date(mission.debut_le), 'EEEE d MMMM', { locale: fr })} de ${format(new Date(mission.debut_le), "HH'h'mm", { locale: fr })} à ${format(new Date(mission.fin_le), "HH'h'mm", { locale: fr })}. Une annulation tardive impactera votre score de fiabilité.`}
        labelConfirmer="Oui, j'accepte"
        labelAnnuler="Annuler"
      />

      <ModalConfirmation
        ouvert={modalAnnuler}
        onFermer={() => setModalAnnuler(false)}
        onConfirmer={annulerParticipation}
        titre="⚠️ Annuler votre participation ?"
        message={(() => {
          const debut = new Date(mission.debut_le);
          const maintenant = new Date();
          const heuresAvant = (debut.getTime() - maintenant.getTime()) / 3600000;
          if (heuresAvant < 4) return 'Annulation à moins de 4h du début : pénalité de -25 points sur votre score de fiabilité. Cette action est irréversible.';
          if (heuresAvant < 24) return 'Annulation à moins de 24h du début : pénalité de -15 points sur votre score de fiabilité. Cette action est irréversible.';
          return 'Pénalité de -8 points sur votre score de fiabilité. Cette action est irréversible.';
        })()}
        labelConfirmer="Oui, annuler"
        labelAnnuler="Non, garder"
        variante="danger"
      />

      {modalCodeTravail && <ModalCodeTravail erreur={modalCodeTravail} onFermer={() => setModalCodeTravail(null)} />}

      {/* Sprint 5.5 PR 1 : modale annulation candidature avec grille Sprint 3.5 */}
      {candidatureRec && (
        <ModaleAnnulationCandidature
          ouvert={modalAnnulationCandidature}
          onFermer={() => setModalAnnulationCandidature(false)}
          onAnnulee={() => {
            setModalAnnulationCandidature(false);
            navigate('/soignant/missions');
          }}
          candidatureId={candidatureRec.id}
          accepteeA={candidatureRec.acceptee_a || new Date().toISOString()}
          debutMission={mission.debut_le}
          estAsap={Boolean((mission as any).est_urgente)}
          missionInfo={{
            intitule: mission.intitule,
            etablissementNom: etablissement?.nom || 'Établissement',
            debut_le: mission.debut_le,
            fin_le: mission.fin_le,
          }}
        />
      )}

      {modalPerdu && (
        <ModalPerduDeVitesse
          onFermer={() => setModalPerdu(false)}
          onVoirAutres={() => { setModalPerdu(false); navigate('/soignant/missions'); }}
        />
      )}

      {animationSucces && (
        <AnimationSuccesMission
          mission={mission}
          onTermine={() => { setAnimationSucces(false); navigate('/soignant/missions'); }}
        />
      )}

      <ChoixContratDialog
        open={choixContratDialog.open}
        options={choixContratDialog.options}
        onClose={() => { setChoixContratDialog(prev => ({ ...prev, open: false })); setPostulationEnCours(false); setAcceptationEnCours(false); }}
        onChoose={(val) => {
          setChoixContratDialog(prev => ({ ...prev, open: false }));
          if (choixContratDialog.action === 'postuler') postulerMission(val);
          else accepterMission(val);
        }}
        loading={postulationEnCours || acceptationEnCours}
        proposerMemorisation
      />

    </LayoutApp>
  );
}
