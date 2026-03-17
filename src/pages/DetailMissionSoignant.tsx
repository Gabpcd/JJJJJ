import React, { useState, useEffect } from 'react';
import { usePageTitle } from '@/hooks/usePageTitle';
import { handleErrorSilent } from '@/lib/handleError';
import { useParams, useNavigate } from 'react-router-dom';
import { ArrowLeft, Phone, Mail, Building2, MessageCircle } from 'lucide-react';
import { LayoutApp } from '@/components/LayoutApp';
import { ChargementPage } from '@/components/ChargementPage';
import { BadgeStatut } from '@/components/BadgeStatut';
import { BadgeDistance } from '@/components/BadgeDistance';
import { DecompositionFinanciere } from '@/components/DecompositionFinanciere';
import { NoteHonoraires } from '@/components/NoteHonoraires';
import { BlocagePostulation } from '@/components/BlocagePostulation';
import { ChatMission } from '@/components/ChatMission';
import { BlocConformite } from '@/components/BlocConformite';
import { BandeauGraceDocuments } from '@/components/BandeauGraceDocuments';
import { BoutonExclusion } from '@/components/BoutonExclusion';
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
import { format } from 'date-fns';
import { fr } from 'date-fns/locale';
import { toast } from 'sonner';

interface SoignantData {
  prenom: string; nom: string; telephone: string | null;
  date_naissance: string | null; profession: string; type_contrat: string | null;
  numero_rpps: string | null; numero_adeli: string | null;
  adresse_lat: number | null; adresse_lng: number | null;
  tous_documents_valides: boolean | null; identite_verifiee: boolean | null;
}

function calculerCompletionProfil(s: SoignantData) {
  // Only count fields the user can actually fill in — not verification statuses
  const checks: boolean[] = [
    !!s.prenom, !!s.nom, !!s.telephone, !!s.date_naissance,
    !!s.profession, !!s.type_contrat,
    !!(s.numero_rpps || s.numero_adeli),
    !!(s.adresse_lat && s.adresse_lng),
  ];
  return Math.round((checks.filter(Boolean).length / checks.length) * 100);
}

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
          type_paiement_soignant, numero_note_honoraires,
          yousign_statut, mode_attribution
        `).eq('id', id).single(),
        supabase.from('soignants').select('prenom, nom, telephone, date_naissance, profession, type_contrat, numero_rpps, numero_adeli, adresse_lat, adresse_lng, tous_documents_valides, identite_verifiee, heures_cumulees, premiere_mission_le').eq('id', user.id).single(),
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
      });
  }, [mission, user]);

  // Fetch average rating for the establishment
  useEffect(() => {
    if (!mission?.etablissement_id) return;
    supabase.rpc('fn_note_moyenne' as any, { p_user_id: mission.etablissement_id })
      .then(({ data }: any) => {
        if (data && typeof data === 'object') setNoteMoyenne(data);
        else if (Array.isArray(data) && data[0]) setNoteMoyenne(data[0]);
      });
  }, [mission?.etablissement_id]);

  if (loading || !mission || !soignant) return <LayoutApp role="SOIGNANT"><ChargementPage /></LayoutApp>;

  const distance = calculerDistanceKm(
    soignant.adresse_lat, soignant.adresse_lng,
    etablissement?.adresse_lat, etablissement?.adresse_lng
  );
  const completionProfil = calculerCompletionProfil(soignant);
  const premiereMissionLe = (soignant as any).premiere_mission_le;
  const SEPT_JOURS_MS = 7 * 24 * 60 * 60 * 1000;
  const enPeriodeGrace = !premiereMissionLe || 
    (new Date(premiereMissionLe).getTime() + SEPT_JOURS_MS > Date.now());
  const missionLaisseLeTemps = mission.debut_le &&
    (new Date(mission.debut_le).getTime() - Date.now() > SEPT_JOURS_MS);
  const docsOk = soignant.tous_documents_valides || enPeriodeGrace || missionLaisseLeTemps;
  const peutPostuler = completionProfil >= 100 && docsOk;
  const estAssigne = mission.soignant_assigne_id === user!.id;
  const estOuverte = mission.statut === 'OUVERTE';
  const estTerminee = mission.statut === 'TERMINEE';
  const estAssigneAutre = !estOuverte && !estAssigne && mission.soignant_assigne_id;
  const duree = mission.duree_heures ?? ((new Date(mission.fin_le).getTime() - new Date(mission.debut_le).getTime()) / 3600000);
  const estModeCandidature = mission.mode_attribution === 'CANDIDATURE';

  const postulerMission = async () => {
    setPostulationEnCours(true);
    try {
      const { data, error } = await supabase.rpc('fn_postuler_mission' as any, {
        p_mission_id: id!,
        p_message: messageCandidature || null,
      });
      if (error) { toast.error(extraireMessageErreur(error)); return; }
      if (data?.error) { toast.error(data.error); return; }
      setCandidatureEnvoyee(true);
      toast.success('Candidature envoyée ! L\'établissement examinera votre profil.');
    } catch (err: any) {
      toast.error(extraireMessageErreur(err));
    }
    setPostulationEnCours(false);
  };

  const accepterMission = async () => {
    setAcceptationEnCours(true);
    try {
      const { data, error } = await supabase.rpc('fn_accepter_mission' as any, { p_mission_id: id! });

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
      }).catch(() => {});

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
        }).catch(() => {});
      }
    } finally {
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

      {/* Bandeau grâce documents */}
      {enPeriodeGrace && (
        <BandeauGraceDocuments
          premiereMissionLe={premiereMissionLe}
          tousDocumentsValides={soignant.tous_documents_valides}
        />
      )}

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
                <div className="flex items-center gap-2">
                  <h3 className="font-semibold text-sm text-foreground">{etablissement?.nom}</h3>
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
                          toast.error(`Impossible d'ouvrir la conversation : ${error.message}`);
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
                <div className="mt-1">
                  <BadgeDistance distanceKm={distance} />
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
                {/* E2: Blacklist côté soignant */}
                {mission.etablissement_id && (
                  <div className="mt-2 pt-2 border-t border-border">
                    <BoutonExclusion excluId={mission.etablissement_id} typeExcluPar="SOIGNANT" />
                  </div>
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
          ) : (
            <DecompositionFinanciere mission={mission} />
          )}
          <p className="text-xs text-muted-foreground/60 italic text-center">
            Simulation à titre indicatif. Seuls les montants calculés par le moteur de paie font foi.
          </p>

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
          <div className="card-base">
            {estOuverte && (
              <>
                <BlocagePostulation completionProfil={completionProfil} documentsValides={!!soignant.tous_documents_valides} premiereMissionLe={premiereMissionLe} />
                {chevauchement && (
                  <div className="bg-warning/10 border border-warning/30 rounded-xl p-3 mb-3 text-center">
                    <p className="text-sm font-semibold text-warning">⚠️ Vous avez déjà une mission sur ce créneau</p>
                    <p className="text-xs text-warning/80 mt-1">Vous ne pouvez pas accepter deux missions qui se chevauchent.</p>
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
                          onClick={postulerMission}
                          disabled={postulationEnCours || !conformiteOk || chevauchement}
                          className="btn-primary w-full text-base py-3.5 disabled:opacity-50 active:scale-[0.97] transition-transform"
                        >
                          {postulationEnCours ? 'Envoi en cours…' : '📨 Postuler à cette mission'}
                        </button>
                        <p className="text-[10px] text-muted-foreground text-center mt-2">
                          L'établissement examinera votre candidature et vous sera notifié de sa décision.
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
                  <div className="bg-success/5 border border-success/20 rounded-xl p-3 text-center">
                    <p className="text-sm font-semibold text-success">✅ Candidature envoyée — En attente de réponse</p>
                    <p className="text-xs text-muted-foreground mt-1">L'établissement examinera votre profil et reviendra vers vous.</p>
                  </div>
                )}
              </>
            )}

            {estAssigne && (
              <>
                <div className="bg-success/5 border border-success/20 rounded-xl p-3 mb-4 text-center">
                  <p className="text-sm font-semibold text-success">✅ Vous êtes assigné(e) à cette mission</p>
                </div>
                <button
                  type="button"
                  onClick={async () => {
                    const { data } = await supabase.rpc('fn_obtenir_conversation', { p_autre_id: mission.etablissement_id, p_mission_id: mission.id });
                    if (data) navigate(`/soignant/messagerie?conv=${data}`);
                  }}
                  className="btn-secondary w-full text-sm py-2.5 mb-3"
                >
                  💬 Contacter l'établissement
                </button>
                <button onClick={() => setModalAnnuler(true)} className="w-full border-2 border-destructive text-destructive rounded-xl px-4 py-2.5 text-sm font-medium hover:bg-destructive/5 transition-colors">
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
              <ChatMission
                missionId={mission.id}
                role="SOIGNANT"
                prenomUtilisateur={soignant.prenom}
              />
            </div>
          )}
        </div>
      </div>

      {/* Modals */}
      <ModalConfirmation
        ouvert={modalConfirm}
        onFermer={() => setModalConfirm(false)}
        onConfirmer={accepterMission}
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

    </LayoutApp>
  );
}
