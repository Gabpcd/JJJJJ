import React, { useState, useEffect } from 'react';
import { emailMissionAccepteeSoignant, emailMissionAccepteeEtablissement } from '@/lib/emailTemplates';
import { useParams, useNavigate } from 'react-router-dom';
import { ArrowLeft, Phone, Mail, Building2 } from 'lucide-react';
import { LayoutApp } from '@/components/LayoutApp';
import { ChargementPage } from '@/components/ChargementPage';
import { BadgeStatut } from '@/components/BadgeStatut';
import { BadgeDistance } from '@/components/BadgeDistance';
import { DecompositionFinanciere } from '@/components/DecompositionFinanciere';
import { NoteHonoraires } from '@/components/NoteHonoraires';
import { BlocagePostulation } from '@/components/BlocagePostulation';
import { BlocConformite } from '@/components/BlocConformite';
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
  const checks: boolean[] = [
    !!s.prenom, !!s.nom, !!s.telephone, !!s.date_naissance,
    !!s.profession, !!s.type_contrat,
    !!(s.numero_rpps || s.numero_adeli),
    !!(s.adresse_lat && s.adresse_lng),
    !!s.tous_documents_valides, !!s.identite_verifiee,
  ];
  return Math.round((checks.filter(Boolean).length / checks.length) * 100);
}

export default function DetailMissionSoignant() {
  const { id } = useParams<{ id: string }>();
  const navigate = useNavigate();
  const { user } = useAuth();
  const [mission, setMission] = useState<any>(null);
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

  useEffect(() => {
    if (!user || !id) return;
    const load = async () => {
      const [{ data: m }, { data: s }] = await Promise.all([
        supabase.from('missions').select(`
          *, etablissements(nom, adresse_rue, adresse_ville, adresse_code_postal,
            adresse_departement, adresse_lat, adresse_lng, type,
            telephone_contact, email_contact,
            taux_majoration_nuit_pourcent, taux_majoration_dimanche_pourcent,
            taux_majoration_ferie_pourcent)
        `).eq('id', id).single(),
        supabase.from('soignants').select('prenom, nom, telephone, date_naissance, profession, type_contrat, numero_rpps, numero_adeli, adresse_lat, adresse_lng, tous_documents_valides, identite_verifiee, heures_cumulees').eq('id', user.id).single(),
      ]);
      if (m) {
        setMission(m);
        // Count missions from this establishment
        const { count } = await supabase.from('missions').select('id', { count: 'exact', head: true }).eq('etablissement_id', (m as any).etablissement_id);
        setCountMissions(count || 0);
      }
      if (s) setSoignant(s as any);
      setLoading(false);
    };
    load();
  }, [user, id]);

  if (loading || !mission || !soignant) return <LayoutApp role="SOIGNANT"><ChargementPage /></LayoutApp>;

  const distance = calculerDistanceKm(
    soignant.adresse_lat, soignant.adresse_lng,
    mission.etablissements?.adresse_lat, mission.etablissements?.adresse_lng
  );
  const completionProfil = calculerCompletionProfil(soignant);
  const peutPostuler = completionProfil >= 100 && soignant.tous_documents_valides;
  const estAssigne = mission.soignant_assigne_id === user!.id;
  const estOuverte = mission.statut === 'OUVERTE';
  const estTerminee = mission.statut === 'TERMINEE';
  const estAssigneAutre = !estOuverte && !estAssigne && mission.soignant_assigne_id;
  const duree = mission.duree_heures ?? ((new Date(mission.fin_le).getTime() - new Date(mission.debut_le).getTime()) / 3600000);

  const accepterMission = async () => {
    setAcceptationEnCours(true);
    try {
      const { data, error } = await supabase
        .from('missions')
        .update({
          soignant_assigne_id: user!.id,
          statut: 'ASSIGNEE' as any,
          modifie_le: new Date().toISOString(),
        })
        .eq('id', id!)
        .eq('statut', 'OUVERTE')
        .select()
        .single();

      if (!data && !error) {
        setModalPerdu(true);
        return;
      }
      if (error) {
        if (estBlocageCodeTravail(error)) {
          setModalCodeTravail(error);
        } else if (error.message?.includes('0 rows')) {
          setModalPerdu(true);
        } else {
          toast.error(extraireMessageErreur(error));
        }
        return;
      }

      // Audit HDS
      const { error: auditError } = await supabase.rpc('fn_ecrire_audit', {
        p_acteur_id: user!.id,
        p_type_acteur: 'SOIGNANT',
        p_action: 'MISSION_ASSIGNATION',
        p_type_ressource: 'mission',
        p_id_ressource: id!,
        p_cle_s3: null,
        p_details: {
          intitule: mission.intitule,
          etablissement: mission.etablissements?.nom,
          debut: mission.debut_le,
          fin: mission.fin_le,
        },
        p_ip: null,
        p_navigateur: navigator.userAgent,
      });
      if (auditError) console.error('Audit failed:', auditError);

      setMission({ ...mission, ...data });
      setAnimationSucces(true);

      // Email au soignant
      const dateFormatee = format(new Date(mission.debut_le), 'EEEE d MMMM yyyy à HH:mm', { locale: fr });
      supabase.functions.invoke('send-email', {
        body: {
          to: user!.email,
          subject: `Mission confirmée : ${mission.intitule}`,
          html: emailMissionAccepteeSoignant(soignant.prenom, mission.intitule, dateFormatee, mission.etablissements?.nom || '', id!),
          type: 'MISSION_ACCEPTEE_SOIGNANT',
          destinataire_id: user!.id,
        },
      }).catch(() => {});

      // Email à l'établissement
      if (mission.etablissements?.email_contact) {
        supabase.functions.invoke('send-email', {
          body: {
            to: mission.etablissements.email_contact,
            subject: `Mission acceptée par ${soignant.prenom} ${soignant.nom}`,
            html: emailMissionAccepteeEtablissement(mission.etablissements.nom, `${soignant.prenom} ${soignant.nom}`, mission.intitule, dateFormatee, id!),
            type: 'MISSION_ACCEPTEE_ETABLISSEMENT',
            destinataire_id: mission.etablissement_id,
          },
        }).catch(() => {});
      }
    } finally {
      setAcceptationEnCours(false);
    }
  };

  const annulerParticipation = async () => {
    const { error } = await supabase
      .from('missions')
      .update({
        soignant_assigne_id: null,
        statut: 'ANNULEE_PAR_SOIGNANT' as any,
        modifie_le: new Date().toISOString(),
      })
      .eq('id', id!);

    if (error) {
      toast.error(extraireMessageErreur(error));
      return;
    }

    const { error: auditError } = await supabase.rpc('fn_ecrire_audit', {
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
    if (auditError) console.error('Audit failed:', auditError);

    toast.warning('Participation annulée. Votre score sera mis à jour.');
    navigate('/soignant/missions');
  };

  return (
    <LayoutApp role="SOIGNANT">
      <button onClick={() => navigate(-1)} className="flex items-center gap-1 text-sm text-primary mb-4 hover:underline">
        <ArrowLeft className="h-4 w-4" /> Retour
      </button>

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
                <h3 className="font-semibold text-sm text-foreground">{mission.etablissements?.nom}</h3>
                <p className="text-xs text-muted-foreground">{getLabelTypeEtablissement(mission.etablissements?.type)}</p>
                <p className="text-xs text-muted-foreground mt-1">
                  {mission.etablissements?.adresse_rue}, {mission.etablissements?.adresse_code_postal} {mission.etablissements?.adresse_ville}
                  {mission.etablissements?.adresse_departement && ` (${mission.etablissements.adresse_departement})`}
                </p>
                <div className="mt-1">
                  <BadgeDistance distanceKm={distance} />
                </div>
                {estAssigne && (
                  <div className="mt-2 space-y-1">
                    {mission.etablissements?.telephone_contact && (
                      <a href={`tel:${mission.etablissements.telephone_contact}`} className="flex items-center gap-1.5 text-xs text-primary hover:underline">
                        <Phone className="h-3.5 w-3.5" /> {mission.etablissements.telephone_contact}
                      </a>
                    )}
                    {mission.etablissements?.email_contact && (
                      <a href={`mailto:${mission.etablissements.email_contact}`} className="flex items-center gap-1.5 text-xs text-primary hover:underline">
                        <Mail className="h-3.5 w-3.5" /> {mission.etablissements.email_contact}
                      </a>
                    )}
                  </div>
                )}
                <p className="text-[10px] text-muted-foreground/60 mt-2">
                  Cet établissement a publié {countMissions} mission{countMissions > 1 ? 's' : ''} sur Soin Direct
                </p>
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
                supabase.rpc('fn_ecrire_audit', {
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
                <BlocagePostulation completionProfil={completionProfil} documentsValides={!!soignant.tous_documents_valides} />
                {peutPostuler && (
                  <>
                    <button
                      onClick={() => setModalConfirm(true)}
                      disabled={acceptationEnCours || !conformiteOk}
                      className="btn-primary w-full text-base py-3.5 disabled:opacity-50 active:scale-[0.97] transition-transform"
                      title={!conformiteOk ? 'Résolvez les conflits ci-dessus pour accepter' : undefined}
                    >
                      {acceptationEnCours ? 'Acceptation en cours…' : '★ Accepter cette mission'}
                    </button>
                    {!conformiteOk && (
                      <p className="text-[10px] text-destructive text-center mt-2">
                        ⛔ Résolvez les conflits de conformité ci-dessus pour pouvoir accepter.
                      </p>
                    )}
                    <p className="text-[10px] text-muted-foreground text-center mt-2">
                      En acceptant, vous vous engagez à être présent(e) aux dates et horaires indiqués.
                    </p>
                  </>
                )}
              </>
            )}

            {estAssigne && (
              <>
                <div className="bg-success/5 border border-success/20 rounded-xl p-3 mb-4 text-center">
                  <p className="text-sm font-semibold text-success">✅ Vous êtes assigné(e) à cette mission</p>
                </div>
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

            {estAssigneAutre && (
              <div className="text-center">
                <p className="text-sm text-muted-foreground mb-3">Cette mission a déjà été attribuée</p>
                <button onClick={() => navigate('/soignant/missions')} className="btn-secondary text-sm">
                  Voir d'autres missions →
                </button>
              </div>
            )}
          </div>
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
        message="Cette action est irréversible. Votre score de fiabilité sera impacté de -8 points."
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
