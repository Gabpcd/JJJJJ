import React, { useState, useEffect, useMemo, Suspense } from 'react';
import { lazyRetry as lazy } from '@/lib/lazyRetry';
import { useNavigate, useSearchParams, Link } from 'react-router-dom';
import { Loader2, AlertTriangle, CalendarDays, Timer, Ban, Banknote, Lightbulb, Lock, User, Calculator, Info, Save, Send, ClipboardList } from 'lucide-react';
import { extraireContratPreference, injecterContratTag, getLabelProfession, type ContratPreference } from '@/lib/constantes';
import { SelectProfession } from '@/components/SelectProfession';
import { SelectSpecialiteMedicale } from '@/components/SelectSpecialiteMedicale';
import { WarningRist } from '@/components/WarningRist';
import { useModeExerciceMission } from '@/hooks/useModeExerciceMission';
import { liberalEstProposable, liensSourcesModeExercice } from '@/lib/modeExerciceMission';
import { professionMissionExigeSpecialisationExacte } from '@/lib/profession-hierarchy';
import { EncartCommissionDegressif } from '@/components/EncartCommissionDegressif';
import { ModalCodeTravail } from '@/components/ModalCodeTravail';
import {
  FormulaireRecurrence,
  type RecurrenceFlexConfig,
  type CreneauFlex,
  type PlanningInitialCreneau,
  type ValidationFlexResult,
} from '@/components/FormulaireRecurrence';
import type { RecapMissionData } from '@/components/mission/ModalRecapMission';
// Sprint 8 ter-G PR 3 — lazy load modal récap (code splitting, ~8KB)
const ModalRecapMission = lazy(() =>
  import('@/components/mission/ModalRecapMission').then((m) => ({
    default: m.ModalRecapMission,
  })),
);
import { useAuth } from '@/contexts/AuthContext';
import { useNotification } from '@/contexts/NotificationContext';
import { supabase } from '@/integrations/supabase/client';
import { extraireMessageErreur, estBlocageCodeTravail } from '@/lib/erreurs';
import { contratServiceEstSigne } from '@/lib/contratEtablissement';
import { cleJourParis, formatParis, instantJolene } from '@/lib/date-heure-paris';
import { calculerHeuresNuitParis } from '@/lib/planning-derive';
import { construirePlanningCandidat } from '@/components/planning/planning-candidat';

interface FormulaireMissionProps {
  missionSource?: any;
  modeEdition?: boolean;
}

// Session F (F5) — Grille indicative de taux horaire brut conseillé par profession,
// fourchettes représentatives du marché du remplacement en France (€/h brut).
// Purement informatif : n'impose jamais la valeur, sert de repère à l'établissement.
const TAUX_CONSEILLE: Record<string, [number, number]> = {
  IDE: [25, 38],
  AS: [18, 26],
  AES: [18, 26],
  AUXILIAIRE_PUERICULTURE: [19, 27],
  IBODE: [30, 45],
  IADE: [35, 55],
  SAGE_FEMME: [28, 40],
  KINE: [30, 45],
  MEDECIN: [60, 110],
  DENTISTE: [60, 110],
  PHARMACIEN: [30, 45],
  MANIPULATEUR_RADIO: [24, 36],
  PREPARATEUR_PHARMA: [18, 26],
  DIETETICIEN: [22, 34],
  ERGOTHERAPEUTE: [24, 38],
  PSYCHOMOTRICIEN: [24, 38],
  ORTHOPHONISTE: [28, 42],
};

/** Fourchette de taux conseillé pour une profession (fallback générique 20–40 €/h). */
function getTauxConseille(profession: string): [number, number] {
  return TAUX_CONSEILLE[profession] ?? [20, 40];
}

/**
 * Convertit une date stockée en ISO (UTC) vers la valeur locale attendue par
 * `<input type="datetime-local">`. Tronquer directement l'ISO conserverait
 * l'heure UTC et décalerait silencieusement le créneau en Europe/Paris.
 */
function versDateHeureLocale(value?: string | null): string {
  if (!value) return '';
  try {
    const date = instantJolene(value);
    return `${cleJourParis(date)}T${formatParis(date, 'HH:mm')}`;
  } catch {
    return '';
  }
}

export function FormulaireMission({ missionSource, modeEdition }: FormulaireMissionProps) {
  const navigate = useNavigate();
  const [searchParams] = useSearchParams();
  const { user } = useAuth();
  const { afficherNotification } = useNotification();

  const [intitule, setIntitule] = useState('');
  const [description, setDescription] = useState('');
  const [profession, setProfession] = useState('');
  const [specialiteMedicaleRequise, setSpecialiteMedicaleRequise] = useState('');
  const [service, setService] = useState('');
  const [debutLe, setDebutLe] = useState('');
  const [finLe, setFinLe] = useState('');
  const [tauxHoraire, setTauxHoraire] = useState('');
  const [estUrgente, setEstUrgente] = useState(false);
  const [niveauUrgence, setNiveauUrgence] = useState(1);
  const [modeAttribution, setModeAttribution] = useState<'PREMIER_ARRIVE' | 'CANDIDATURE'>('PREMIER_ARRIVE');
  const [contratPreference, setContratPreference] = useState<'TOUS' | 'SALARIE' | 'LIBERAL'>('TOUS');
  // Remplacement libéral en cabinet (dentistes/médecins) : le titulaire encaisse
  // les honoraires puis rétrocède — la mission porte un % au lieu d'un taux horaire.
  const [modeRemuneration, setModeRemuneration] = useState<'TAUX_HORAIRE' | 'RETROCESSION'>('TAUX_HORAIRE');
  const [retrocessionPct, setRetrocessionPct] = useState('50');
  const [loading, setLoading] = useState(false);
  const [erreurCodeTravail, setErreurCodeTravail] = useState<any>(null);
  const [dupliquerInfo, setDupliquerInfo] = useState<string | null>(null);
  const [ristPlafondActif, setRistPlafondActif] = useState(false);
  const [tauxCommission, setTauxCommission] = useState(15);
  const [palierNom, setPalierNom] = useState('Découverte');

  const [creneaux, setCreneaux] = useState<CreneauFlex[]>([]);
  const [recurrenceValidation, setRecurrenceValidation] = useState<ValidationFlexResult | null>(null);
  const [creneauxRepublication, setCreneauxRepublication] = useState<PlanningInitialCreneau[]>([]);
  const [sourceRepublication, setSourceRepublication] = useState<any>(null);
  const [planningRepublicationCharge, setPlanningRepublicationCharge] = useState(false);
  const [erreurPlanningRepublication, setErreurPlanningRepublication] = useState<string | null>(null);
  const [publicationEnCours, setPublicationEnCours] = useState(false);

  const [etablissementType, setEtablissementType] = useState<string | null>(null);
  const [erreurFactureImpayee, setErreurFactureImpayee] = useState(false);
  const [toleranceGpsMetres, setToleranceGpsMetres] = useState<number | null>(null);
  // Sprint 7 PR 1 — Modal récap mission (P1-4)
  const [modalRecapOuvert, setModalRecapOuvert] = useState(false);
  const [explicationModeOuverte, setExplicationModeOuverte] = useState(false);
  const [siretInvalide, setSiretInvalide] = useState(false);
  // `null` pendant le chargement : aucun faux avertissement visuel, mais le
  // bouton reste bloqué jusqu'à confirmation explicite de la signature.
  const [contratNonValide, setContratNonValide] = useState<boolean | null>(null);

  // Load rist_plafond_actif + commission info + type + siret validation
  const [estSecteurPublic, setEstSecteurPublic] = useState(false);
  const {
    mode: modeExerciceMission,
    loading: modeExerciceLoading,
    error: modeExerciceError,
  } = useModeExerciceMission(profession, etablissementType, estSecteurPublic);
  const liberalAutoriseMission = liberalEstProposable(modeExerciceMission);
  const sourcesModeExerciceMission = modeExerciceMission
    ? liensSourcesModeExercice(modeExerciceMission)
    : [];

  useEffect(() => {
    if (!profession || !etablissementType || modeExerciceLoading) return;
    if (modeExerciceError || (modeExerciceMission && !liberalAutoriseMission)) {
      setContratPreference('SALARIE');
    }
  }, [
    profession,
    etablissementType,
    liberalAutoriseMission,
    modeExerciceError,
    modeExerciceLoading,
    modeExerciceMission,
  ]);
  useEffect(() => {
    if (!user) return;
    supabase.rpc('fn_mon_etablissement_complet' as any).then(({ data, error }: any) => {
      if (error) {
        console.warn('FormulaireMission: fn_mon_etablissement_complet error', error);
        setContratNonValide(true);
        return;
      }
      if (data) {
        setEstSecteurPublic(data.est_secteur_public === true);
        const typesPublics = ['HOPITAL_PUBLIC', 'CENTRE_SANTE'];
        const isPublic = data.est_secteur_public === true || typesPublics.includes(data.type);
        setRistPlafondActif(data.rist_plafond_actif === true && isPublic);
        setTauxCommission(data.taux_commission_negocie ?? 15);
        setEtablissementType(data.type);
        if ((data as any).tolerance_gps_metres != null) setToleranceGpsMetres((data as any).tolerance_gps_metres);
        if ((data as any).paliers_commission?.nom) setPalierNom((data as any).paliers_commission.nom);
        // SIRET check: must exist and not be empty
        const s = (data.siret || '').trim();
        setSiretInvalide(!s || s.length === 0);
        // Même source que fn_blocage_publication_etab : une signature active.
        // `contrat_valide` est l'ancien statut d'un PDF et ne débloque rien.
        setContratNonValide(!contratServiceEstSigne(data));
      }
    });
  }, [user]);

  // Load from query params (soignant_id from pool, or duplication)
  useEffect(() => {
    const soignantIdParam = searchParams.get('soignant_id');
    const professionParam = searchParams.get('profession');
    if (soignantIdParam && !missionSource) {
      // Pre-fill from pool
      if (professionParam) setProfession(professionParam);
    }

    const dupId = searchParams.get('dupliquer');
    if (dupId && !missionSource) {
      // Session F (F3) — « Republier » : si des nouvelles dates sont passées en query
      // params (?debut=<iso>&fin=<iso>), on préremplit les horaires dans le fuseau
      // local attendu par <input datetime-local>.
      const debutParam = searchParams.get('debut');
      const finParam = searchParams.get('fin');
      if (debutParam) setDebutLe(versDateHeureLocale(debutParam));
      if (finParam) setFinLe(versDateHeureLocale(finParam));

      supabase.from('missions').select('id, intitule, description, profession_requise, service, taux_horaire_base, est_urgente, niveau_urgence, type_contrat_recherche, specialite_medicale_requise, debut_le, fin_le, nb_creneaux').eq('id', dupId).single().then(({ data, error }) => {
        if (error) {
          console.warn('FormulaireMission: mission duplication fetch error', error);
          setErreurPlanningRepublication('La mission source ne peut pas être vérifiée.');
          return;
        }
        if (data) {
          setSourceRepublication(data);
          setIntitule(data.intitule);
          setDescription(data.description || '');
          setContratPreference(((data as any).type_contrat_recherche as any) || extraireContratPreference(data.description));
          setProfession(data.profession_requise);
          setService(data.service || '');
          setTauxHoraire(String(data.taux_horaire_base));
          setEstUrgente(data.est_urgente || false);
          setNiveauUrgence(data.niveau_urgence || 1);
          setSpecialiteMedicaleRequise(((data as any).specialite_medicale_requise as string) || '');
          setDupliquerInfo(data.intitule);
        }
      });
      // Toujours charger le planning source. Les query params debut/fin ne
      // peuvent remplacer qu'un planning reellement mono-creneau : une mission
      // multi-creneaux ne doit jamais etre reduite a son enveloppe globale.
      supabase
        .from('mission_creneaux')
        .select('debut, fin, ordre')
        .eq('mission_id', dupId)
        .eq('est_pause', false)
        .eq('type_creneau', 'PREVISIONNEL')
        .order('ordre', { ascending: true })
        .then(({ data, error }) => {
          setPlanningRepublicationCharge(true);
          if (error) {
            console.warn('FormulaireMission: créneaux de republication introuvables', error);
            setErreurPlanningRepublication('Le planning exact de la mission source ne peut pas être chargé.');
            return;
          }
          setCreneauxRepublication((data ?? []).map((item: any) => ({
            debut: item.debut,
            fin: item.fin,
          })));
        });
    }
  }, [searchParams, missionSource]);

  // Load edition source
  useEffect(() => {
    if (missionSource) {
      setIntitule(missionSource.intitule);
      setDescription(missionSource.description || '');
      setProfession(missionSource.profession_requise);
      setService(missionSource.service || '');
      setDebutLe(versDateHeureLocale(missionSource.debut_le));
      setFinLe(versDateHeureLocale(missionSource.fin_le));
      setTauxHoraire(String(missionSource.taux_horaire_base));
      setEstUrgente(missionSource.est_urgente || false);
      setNiveauUrgence(missionSource.niveau_urgence || 1);
      setModeAttribution(missionSource.mode_attribution || 'PREMIER_ARRIVE');
      setContratPreference(
        (missionSource.type_contrat_recherche as 'TOUS' | 'SALARIE' | 'LIBERAL')
          || extraireContratPreference(missionSource.description),
      );
      setSpecialiteMedicaleRequise(missionSource.specialite_medicale_requise || '');
    }
  }, [missionSource]);

  const planningSourceRepublication = useMemo(() => {
    if (!sourceRepublication || !planningRepublicationCharge) return null;
    return construirePlanningCandidat(sourceRepublication, creneauxRepublication.map((creneau) => ({
      ...creneau,
      mission_id: sourceRepublication.id,
      est_pause: false,
      type_creneau: 'PREVISIONNEL',
    })));
  }, [creneauxRepublication, planningRepublicationCharge, sourceRepublication]);
  const republicationDemandee = Boolean(searchParams.get('dupliquer')) && !missionSource;
  const republicationBloquee = republicationDemandee && (
    Boolean(erreurPlanningRepublication)
    || !planningRepublicationCharge
    || !sourceRepublication
    || !planningSourceRepublication?.exact
  );

  const planningInitial = useMemo<PlanningInitialCreneau[]>(() => {
    const source = Array.isArray(missionSource?.creneaux)
      ? missionSource.creneaux
          .filter((item: any) => item && item.debut && item.fin && item.est_pause !== true && item.type_creneau !== 'PAUSE')
          .map((item: any) => ({ id: item.id, debut: item.debut, fin: item.fin }))
      : [];
    if (source.length > 0) return source;

    const debutParam = searchParams.get('debut');
    const finParam = searchParams.get('fin');
    if (republicationDemandee) {
      if (!planningSourceRepublication?.exact) return [];
      const sourceExacte = planningSourceRepublication.creneaux.map((creneau) => ({
        id: creneau.id,
        debut: creneau.debut,
        fin: creneau.fin!,
      }));
      if (sourceExacte.length > 1) return sourceExacte;
      if (debutParam && finParam) return [{ debut: debutParam, fin: finParam }];
      return sourceExacte;
    }
    if (missionSource?.debut_le && missionSource?.fin_le) {
      return [{ debut: missionSource.debut_le, fin: missionSource.fin_le }];
    }
    return [];
  }, [missionSource, planningSourceRepublication, republicationDemandee, searchParams]);

  const taux = parseFloat(tauxHoraire) || 0;
  const estRetrocession = contratPreference === 'LIBERAL'
    && modeRemuneration === 'RETROCESSION'
    && !modeEdition;
  // Le schema financier exige un taux de reference positif lors de la
  // creation, avant que la RPC de retrocession ne bascule la mission sur le
  // pourcentage d'honoraires. Il n'est jamais presente comme la remuneration
  // contractuelle du remplacant.
  const tauxCreation = estRetrocession
    ? (taux > 0 ? taux : getTauxConseille(profession)[0])
    : taux;
  const retrocessionNombre = Number(retrocessionPct);
  const retrocessionValide = !estRetrocession
    || (Number.isFinite(retrocessionNombre) && retrocessionNombre > 0 && retrocessionNombre <= 100);

  const { dureeEstimee, heuresNuitEstimees } = useMemo(() => {
    const duree = creneaux.reduce((somme, creneau) => somme + creneau.dureeHeures, 0);
    const nuit = calculerHeuresNuitParis(creneaux);
    return { dureeEstimee: duree, heuresNuitEstimees: Math.min(nuit, duree) };
  }, [creneaux]);

  // Recurrence validation
  const recurrenceBlocante = recurrenceValidation && !recurrenceValidation.valide;
  const contientCreneauPasse = !modeEdition && creneaux.some((creneau) => new Date(creneau.debut) < new Date());
  const recurrenceValide = creneaux.length > 0
    && recurrenceValidation
    && recurrenceValidation.valide
    && !contientCreneauPasse;

  const handleRecurrenceChange = (_config: RecurrenceFlexConfig, creneauxGen: CreneauFlex[], validation: ValidationFlexResult) => {
    setCreneaux(creneauxGen);
    setRecurrenceValidation(validation);
    setDebutLe(creneauxGen[0]?.debut ?? '');
    setFinLe(creneauxGen.reduce((maximum, creneau) => (
      !maximum || new Date(creneau.fin) > new Date(maximum) ? creneau.fin : maximum
    ), ''));
  };

  // Publication d'UNE mission multi-jours (1 mission + N créneaux PREVISIONNEL).
  // Le pointage QR, la paie et la facturation gèrent déjà le multi-créneaux.
  const publierMissionMultiJours = async () => {
    if (!user || creneaux.length === 0) return;
    setPublicationEnCours(true);
    try {
      // Sanitize description — strip injected tags, puis ré-inject le tag contrat.
      const cleanDesc = (description || '').replace(/\[SERIE_ID:[^\]]*\]/g, '').replace(/\[CONTRAT:[^\]]*\]/g, '').trim();
      const descriptionFinale = injecterContratTag(cleanDesc, contratPreference);

      const creneauxPayload = creneaux.map(c => ({
        debut: c.debut,
        fin: c.fin,
      }));

      const { data: rpcResult, error } = await supabase.rpc('fn_creer_mission_multi_jours_v2' as any, {
        p_intitule: intitule,
        p_description: descriptionFinale || null,
        p_profession_requise: profession,
        p_service: service || null,
        p_taux_horaire_base: tauxCreation,
        p_est_urgente: estUrgente,
        p_niveau_urgence: estUrgente ? niveauUrgence : 0,
        p_mode_attribution: modeAttribution,
        p_specialite_medicale_requise: profession === 'MEDECIN' ? (specialiteMedicaleRequise || null) : null,
        p_accepte_non_specialises: !professionMissionExigeSpecialisationExacte(profession),
        p_creneaux: creneauxPayload as any,
        p_type_contrat_recherche: contratPreference,
        p_mode_remuneration: estRetrocession ? 'RETROCESSION' : 'TAUX_HORAIRE',
        p_retrocession_pct: estRetrocession ? retrocessionNombre : null,
      });

      if (error) {
        if (estBlocageCodeTravail(error)) { setErreurCodeTravail(error); }
        else afficherNotification({ type: 'erreur', message: extraireMessageErreur(error) });
        return;
      }
      if (rpcResult && !(rpcResult as any).success) {
        const msg = (rpcResult as any).error || 'Erreur lors de la création de la mission.';
        if (msg.includes('facture') || msg.includes('impayée')) setErreurFactureImpayee(true);
        afficherNotification({ type: 'erreur', message: msg });
        return;
      }

      const missionId = (rpcResult as any)?.mission_id;

      // Le planning, le type de contrat et l'éventuelle rétrocession sont déjà
      // posés atomiquement par fn_creer_mission_multi_jours_v2.
      // Lot 17 (F2) : une mission issue d'un « Republier »/« Dupliquer » est
      // tracée mission_source=REPUBLICATION (best-effort, ne bloque jamais).
      if (missionId && searchParams.get('dupliquer')) {
        await supabase.rpc('fn_marquer_source_mission' as any, {
          p_mission_id: missionId, p_source: 'REPUBLICATION',
        }).then(() => {}, () => {});
      }
      afficherNotification({ type: 'succes', message: 'Mission publiée ! Les soignants à proximité sont prévenus 🔔' });
      navigate('/etablissement/missions');
    } finally {
      setPublicationEnCours(false);
    }
  };

  // Création et édition passent toutes les deux par le même récapitulatif exact.
  const handleSubmit = (e: React.FormEvent) => {
    e.preventDefault();
    if (!user) return;
    if (recurrenceBlocante || creneaux.length === 0 || !recurrenceValide) return;
    setModalRecapOuvert(true);
  };

  const enregistrerMission = async () => {
    if (!user) return;
    if (!modeEdition || !missionSource) {
      await publierMissionMultiJours();
      return;
    }

    setLoading(true);
    try {
      const cleanDescription = (description || '').replace(/\[SERIE_ID:[^\]]*\]/g, '').replace(/\[CONTRAT:[^\]]*\]/g, '').trim();
      const descriptionFinale = injecterContratTag(cleanDescription, contratPreference);
      const { data: rpcResult, error } = await supabase.rpc('fn_modifier_mission_etablissement_v3' as any, {
        p_mission_id: missionSource.id,
        p_intitule: intitule,
        p_description: descriptionFinale || null,
        p_service: service || null,
        p_profession_requise: profession,
        p_taux_horaire_base: parseFloat(tauxHoraire),
        p_est_urgente: estUrgente,
        p_niveau_urgence: estUrgente ? niveauUrgence : 0,
        p_mode_attribution: modeAttribution,
        p_type_contrat_recherche: contratPreference,
        p_specialite_medicale_requise: profession === 'MEDECIN' ? (specialiteMedicaleRequise || null) : null,
        p_accepte_non_specialises: !professionMissionExigeSpecialisationExacte(profession),
        p_creneaux: creneaux.map((creneau) => ({
          debut: creneau.debut,
          fin: creneau.fin,
        })) as any,
      });

      if (error) {
        if (estBlocageCodeTravail(error)) setErreurCodeTravail(error);
        else afficherNotification({ type: 'erreur', message: extraireMessageErreur(error) });
        return;
      }
      if ((rpcResult as any)?.success === false) {
        afficherNotification({ type: 'erreur', message: (rpcResult as any).error || 'La mission n’a pas pu être mise à jour.' });
        return;
      }

      afficherNotification({ type: 'succes', message: 'Mission et planning mis à jour !' });
      setModalRecapOuvert(false);
      navigate(`/etablissement/missions/${missionSource.id}`);
    } finally {
      setLoading(false);
    }
  };

  const officineNonProposee = etablissementType === 'PHARMACIE_OFFICINE';
  const canSubmit = !officineNonProposee
    && !siretInvalide
    && contratNonValide === false
    && !erreurFactureImpayee
    && !!intitule
    && !!profession
    && tauxCreation > 0
    && retrocessionValide
    && !republicationBloquee
    && !!recurrenceValide
    && !publicationEnCours
    && !loading;

  // Sprint 7 PR 1 — Données récap pour le modal (P1-4)
  const liberalRestreint = !!modeExerciceMission && !liberalAutoriseMission;
  const recapData: RecapMissionData = {
    intitule,
    description,
    profession,
    service,
    debutLe,
    finLe,
    creneaux,
    dureeHeures: dureeEstimee,
    heuresNuit: heuresNuitEstimees,
    tauxHoraire: taux,
    modeRemuneration: estRetrocession ? 'RETROCESSION' : 'TAUX_HORAIRE',
    retrocessionPct: estRetrocession ? retrocessionNombre : null,
    contratPreference,
    modeAttribution,
    estUrgente,
    niveauUrgence,
    tauxCommission,
    toleranceGpsMetres,
    qrAutoGenere: true, // Sprint 4.5 PR 4 : trigger auto à la signature du contrat
    etablissementType,
    liberalRestreint,
    modeExerciceMission,
  };

  return (
    <>
      {siretInvalide && (
        <div className="bg-warning/10 border border-warning/30 rounded-xl p-3 mb-4 flex items-center gap-2 text-sm">
          <AlertTriangle className="h-4 w-4 text-warning shrink-0" />
          <span>Veuillez compléter votre SIRET dans votre profil avant de publier une mission. <Link to="/etablissement/profil" className="text-primary hover:underline font-medium">Aller au profil →</Link></span>
        </div>
      )}

      {contratNonValide === true && (
        <div className="bg-warning/10 border border-warning/30 rounded-xl p-3 mb-4 flex items-center gap-2 text-sm">
          <AlertTriangle className="h-4 w-4 text-warning shrink-0" />
          <span>Votre contrat de service n'est pas encore signé. <Link to="/etablissement/activer" className="text-primary hover:underline font-medium">Signer le contrat →</Link></span>
        </div>
      )}

      {dupliquerInfo && (
        <div className="bg-info/10 border border-info/20 rounded-xl p-3 mb-4 text-sm text-info">
          <ClipboardList aria-hidden="true" className="inline-block h-4 w-4 mr-1 -mt-0.5" />Vous dupliquez la mission « {dupliquerInfo} ». Ajustez les dates ci-dessous.
        </div>
      )}

      {republicationDemandee && erreurPlanningRepublication && (
        <div className="mb-4 rounded-xl border border-destructive/30 bg-destructive/5 p-3 text-sm text-destructive" role="alert">
          {erreurPlanningRepublication} La republication est bloquée pour éviter de reprendre un planning partiel.
        </div>
      )}
      {republicationDemandee && planningRepublicationCharge && sourceRepublication && !planningSourceRepublication?.exact && !erreurPlanningRepublication && (
        <div className="mb-4 rounded-xl border border-destructive/30 bg-destructive/5 p-3 text-sm text-destructive" role="alert">
          Le nombre de créneaux détaillés ne correspond pas au planning contractuel. La republication est bloquée.
        </div>
      )}

      {erreurFactureImpayee && (
        <div className="bg-destructive/10 border border-destructive/30 rounded-xl p-3 mb-4">
          <p className="text-sm font-semibold text-destructive flex items-center gap-1.5"><AlertTriangle aria-hidden="true" className="h-4 w-4 shrink-0" />Vous avez des factures impayées.</p>
          <p className="text-xs text-destructive/80 mt-1">Vous devez régulariser vos factures avant de publier de nouvelles missions.</p>
          <a href="/etablissement/facturation" className="text-sm font-medium text-destructive underline mt-2 inline-block">
            Régulariser mes factures →
          </a>
        </div>
      )}

      {officineNonProposee && (
        <div className="bg-warning/10 border border-warning/30 rounded-xl p-3 mb-4">
          <p className="text-sm font-semibold text-warning flex items-center gap-1.5">
            <Ban aria-hidden="true" className="h-4 w-4 shrink-0" />
            Les remplacements de titulaire d’officine ne sont pas proposés sur Jolene.
          </p>
          <p className="text-xs text-muted-foreground mt-1">
            Les missions de pharmacien disponibles sur la plateforme sont des postes salariés d’établissement, notamment en pharmacie à usage intérieur (PUI).
          </p>
        </div>
      )}

      <form onSubmit={handleSubmit} className="space-y-5">
        {/* Intitulé */}
        <div>
          <label htmlFor="mission-intitule" className="text-sm font-medium text-foreground mb-1 block">Intitulé *</label>
          <input id="mission-intitule" value={intitule} onChange={(e) => setIntitule(e.target.value.slice(0, 120))}
            placeholder="Ex: IDE de nuit — Service Urgences" required className="input-base" />
          <p className="text-[10px] text-muted-foreground mt-1 text-right">{intitule.length}/120</p>
        </div>

        {/* Description */}
        <div>
          <label htmlFor="mission-description" className="text-sm font-medium text-foreground mb-1 block">Description</label>
          <textarea id="mission-description" value={description} onChange={(e) => setDescription(e.target.value)}
            placeholder="Informations complémentaires pour le soignant..." rows={3} className="input-base resize-none" />
        </div>

        {/* Profession */}
        <div>
          <label className="text-sm font-medium text-foreground mb-1 block">Profession requise *</label>
          <SelectProfession
            value={profession}
            onChange={setProfession}
            triggerId="mission-profession"
            placeholder="Sélectionnez la profession recherchée"
            disabled={officineNonProposee}
          />
          {etablissementType === 'PHARMACIE_OFFICINE' && (
            <p className="text-[10px] text-muted-foreground mt-1">Publication désactivée pour les officines.</p>
          )}
        </div>

        {/* Spécialité médecin (optionnelle) */}
        {profession === 'MEDECIN' && (
          <div>
            <label className="text-sm font-medium text-foreground mb-1 block">
              Spécialité requise (optionnel)
            </label>
            <SelectSpecialiteMedicale
              value={specialiteMedicaleRequise}
              onChange={setSpecialiteMedicaleRequise}
              professionParent="MEDECIN"
              placeholder="Toutes spécialités acceptées"
            />
            <p className="text-[10px] text-muted-foreground mt-1">
              Laissez vide pour accepter tous les médecins, ou choisissez une spécialité spécifique.
            </p>
          </div>
        )}

        {/* Service — Lot 12 : liste normalisée (datalist) + saisie libre en repli.
            La fragmentation « Urgences/urgences/URG » dégrade la recherche et le
            matching : on suggère les libellés canoniques sans bloquer la saisie. */}
        <div>
          <label htmlFor="mission-service" className="text-sm font-medium text-foreground mb-1 block">Service</label>
          <input id="mission-service" value={service} onChange={(e) => setService(e.target.value)}
            list="services-canoniques"
            placeholder="Choisissez ou saisissez le service" className="input-base" />
          <datalist id="services-canoniques">
            {['Urgences', 'Réanimation', 'Soins intensifs', 'Soins continus', 'Médecine polyvalente',
              'Chirurgie', 'Bloc opératoire', 'Gériatrie', 'Pédiatrie', 'Cardiologie', 'Maternité',
              'Rééducation', 'EHPAD', 'Psychiatrie', 'Oncologie'].map((s) => (
              <option key={s} value={s} />
            ))}
          </datalist>
        </div>

        {/* Type de contrat proposé (Lot 11 : c'est le choix du type_contrat de la
            mission, pas un « profil » — chaque option affiche ses conséquences) */}
        <div>
          <label className="text-sm font-medium text-foreground mb-2 block">Type de contrat proposé</label>
          <div className="space-y-2">
            {modeExerciceLoading && profession && etablissementType ? (
              <div className="flex items-center gap-2 rounded-xl border border-border bg-muted/30 p-3 text-sm text-muted-foreground" role="status">
                <Loader2 className="h-4 w-4 animate-spin" aria-hidden="true" />
                Vérification du mode d'exercice…
              </div>
            ) : (
              <>
              {([
                { value: 'TOUS' as const, label: 'Tous profils', desc: 'Selon le soignant retenu : salarié (vous êtes l’employeur) ou libéral (honoraires via la plateforme)' },
                { value: 'SALARIE' as const, label: 'Salarié', desc: 'Vous êtes l’employeur : CDD, bulletin de paie, plafond légal 48 h/semaine' },
                { value: 'LIBERAL' as const, label: 'Libéral', desc: 'Honoraires facturés via la plateforme — pas de plafond horaire' },
              ]).filter(opt => {
                return liberalAutoriseMission || opt.value === 'SALARIE';
              }).map(opt => (
              <label key={opt.value} className="flex items-start gap-3 cursor-pointer group">
                <input
                  type="radio" name="contratPreference"
                  checked={contratPreference === opt.value}
                  onChange={() => setContratPreference(opt.value)}
                  className="mt-0.5 accent-primary"
                />
                <div>
                  <span className="text-sm text-foreground font-medium group-hover:text-primary transition-colors">{opt.label}</span>
                  <p className="text-xs text-muted-foreground">{opt.desc}</p>
                </div>
              </label>
              ))}
              </>
            )}
            {profession && etablissementType && modeExerciceMission && !liberalAutoriseMission && (
              <div className="text-xs text-amber-700 dark:text-amber-400 bg-amber-50 dark:bg-amber-950/30 border border-amber-200 dark:border-amber-900 rounded-lg p-3 mt-2">
                <strong>
                  <Info aria-hidden="true" className="inline-block h-3.5 w-3.5 mr-1 -mt-0.5" />
                  {modeExerciceMission.niveau === 'BLOQUE'
                    ? 'Mode libéral non disponible'
                    : 'Mission proposée en salarié'}
                </strong>
                <p className="mt-1">{modeExerciceMission.source_libelle}</p>
                {sourcesModeExerciceMission.length > 0 && (
                  <div className="mt-1.5 flex flex-col items-start gap-1">
                    {sourcesModeExerciceMission.map((source) => (
                      <a
                        key={source.href}
                        href={source.href}
                        target="_blank"
                        rel="noopener noreferrer"
                        className="underline hover:no-underline"
                      >
                        {source.libelle}
                      </a>
                    ))}
                  </div>
                )}
                <button
                  type="button"
                  onClick={() => setExplicationModeOuverte((value) => !value)}
                  className="mt-1.5 block underline hover:no-underline"
                  aria-expanded={explicationModeOuverte}
                >
                  Comprendre pourquoi
                </button>
                {explicationModeOuverte && (
                  <p className="mt-2 border-t border-amber-200 pt-2 dark:border-amber-900">
                    {modeExerciceMission.niveau === 'BLOQUE'
                      ? "Le mode libéral est exclu ici par la règle professionnelle ou le type de structure indiqué dans la source ci-dessus."
                      : "Ce n’est pas une interdiction générale faite aux cliniques. Jolene recommande le salariat lorsque les conditions concrètes de la mission (organisation, horaires imposés et lien de subordination) pourraient conduire à une requalification. La règle dépend de la profession demandée et du cadre réel de la mission, pas du seul nom de la structure."}
                  </p>
                )}
              </div>
            )}
            {profession && etablissementType && modeExerciceError && (
              <p className="rounded-lg border border-destructive/30 bg-destructive/5 p-3 text-xs text-destructive" role="alert">
                Impossible de vérifier le mode libéral pour le moment. La mission reste proposée en salarié par sécurité.
              </p>
            )}
          </div>
        </div>

        {/* Source unique création + édition : créneaux datés réels. */}
        <div>
          <p className="text-sm font-semibold text-foreground mb-1 flex items-center gap-1.5"><CalendarDays aria-hidden="true" className="h-4 w-4" />Planning exact de la mission</p>
          <p className="text-xs text-muted-foreground mb-3">
            Vérifiez chaque date travaillée et chaque horaire. Les jours de repos et les gardes de nuit sont enregistrés tels qu’affichés.
          </p>
          <FormulaireRecurrence
            key={planningInitial.map((item) => `${item.id ?? 'new'}:${item.debut}:${item.fin}`).join('|') || 'planning-vide'}
            onChange={handleRecurrenceChange}
            initialCreneaux={planningInitial}
          />
          {contientCreneauPasse && (
            <p className="mt-2 flex items-center gap-1 text-xs font-medium text-destructive" role="alert">
              <Ban aria-hidden="true" className="h-3.5 w-3.5 shrink-0" />
              Une mission à publier ne peut pas contenir un créneau déjà commencé.
            </p>
          )}
        </div>

        {/* Mode de rémunération — rétrocession réservée au libéral pur (remplacement
            de cabinet : dentistes, médecins), création de mission ponctuelle uniquement */}
        {contratPreference === 'LIBERAL' && !modeEdition && (
          <div className="border border-primary/20 rounded-xl p-4 bg-primary/5 space-y-2">
            <p className="text-sm font-semibold text-foreground flex items-center gap-1.5"><Banknote aria-hidden="true" className="h-4 w-4" />Mode de rémunération</p>
            <label className="flex items-start gap-3 cursor-pointer">
              <input type="radio" name="modeRemuneration" checked={modeRemuneration === 'TAUX_HORAIRE'}
                onChange={() => setModeRemuneration('TAUX_HORAIRE')} className="mt-0.5 accent-primary" />
              <div>
                <span className="text-sm font-medium text-foreground">Taux horaire</span>
                <p className="text-xs text-muted-foreground">Le soignant facture ses heures en honoraires.</p>
              </div>
            </label>
            <label className="flex items-start gap-3 cursor-pointer">
              <input type="radio" name="modeRemuneration" checked={modeRemuneration === 'RETROCESSION'}
                onChange={() => {
                  setModeRemuneration('RETROCESSION');
                  setTauxHoraire((valeur) => (
                    Number.isFinite(Number(valeur)) && Number(valeur) > 0
                      ? valeur
                      : String(getTauxConseille(profession)[0])
                  ));
                }} className="mt-0.5 accent-primary" />
              <div>
                <span className="text-sm font-medium text-foreground">Rétrocession d'honoraires — remplacement de cabinet</span>
                <p className="text-xs text-muted-foreground">
                  Le remplaçant exerce sous vos feuilles de soins : vous encaissez les honoraires
                  puis rétrocédez le pourcentage convenu (contrat type conforme à l'Ordre, usage 40-60 %).
                </p>
              </div>
            </label>
            {modeRemuneration === 'RETROCESSION' && (
              <div className="pt-1">
                <label htmlFor="mission-retrocession" className="text-sm font-medium text-foreground mb-1 block">Rétrocession au remplaçant * (%)</label>
                <div className="relative max-w-[160px]">
                  <input id="mission-retrocession" type="number" step="1" min="1" max="100" value={retrocessionPct}
                    onChange={(e) => setRetrocessionPct(e.target.value)} placeholder="50" className="input-base pr-9" />
                  <span aria-hidden="true" className="absolute right-3 top-1/2 -translate-y-1/2 text-sm text-muted-foreground">%</span>
                </div>
                {!retrocessionValide && (
                  <p className="mt-1 text-xs font-medium text-destructive" role="alert">
                    Le pourcentage de rétrocession doit être compris entre 1 et 100 %.
                  </p>
                )}
              </div>
            )}
          </div>
        )}

        {/* Taux horaire */}
        {!(contratPreference === 'LIBERAL' && modeRemuneration === 'RETROCESSION' && !modeEdition) && (
        <div>
          <label htmlFor="mission-taux-horaire" className="text-sm font-medium text-foreground mb-1 block">Taux horaire brut * (€/h)</label>
          <div className="relative">
            <input id="mission-taux-horaire" type="number" step="0.01" min="11.65" value={tauxHoraire}
              onChange={(e) => setTauxHoraire(e.target.value)} placeholder="25.00" required
              readOnly={modeEdition && missionSource?.statut !== 'OUVERTE'}
              className={`input-base pr-12 ${modeEdition && missionSource?.statut !== 'OUVERTE' ? 'bg-muted cursor-not-allowed' : ''}`} />
            <span aria-hidden="true" className="absolute right-3 top-1/2 -translate-y-1/2 text-sm text-muted-foreground">€/h</span>
          </div>
          {/* Session F (F5) — Taux conseillé indicatif par profession (n'impose rien) */}
          {profession && (
            <p className="text-xs text-muted-foreground mt-1">
              <Lightbulb aria-hidden="true" className="inline-block h-3.5 w-3.5 mr-1 -mt-0.5" />Taux conseillé pour {getLabelProfession(profession)} : {getTauxConseille(profession)[0]}–{getTauxConseille(profession)[1]} €/h brut
            </p>
          )}
          {modeEdition && missionSource?.statut !== 'OUVERTE' && (
            <p className="text-[10px] text-muted-foreground mt-1 flex items-center gap-1"><Lock aria-hidden="true" className="h-3 w-3 shrink-0" />Verrouillé : ces champs ne sont plus modifiables après acceptation.</p>
          )}
        </div>
        )}

        {/* Warning Rist */}
        {profession && taux > 0 && <WarningRist profession={profession} tauxSaisi={taux} ristPlafondActif={ristPlafondActif} estSecteurPublic={estSecteurPublic} />}

        {/* Urgence */}
        <div className="flex items-center justify-between gap-3">
          <div>
            <label className="text-sm font-medium text-foreground">Mission urgente ?</label>
            <p className="text-xs text-muted-foreground">Mise en avant dans les recherches + notification immédiate aux soignants disponibles à proximité.</p>
          </div>
          <button type="button" aria-label="Mission urgente" onClick={() => setEstUrgente(!estUrgente)}
            className={`relative w-12 h-6 rounded-full transition-colors shrink-0 ${estUrgente ? 'bg-primary' : 'bg-muted'}`}>
            <span className={`absolute top-0.5 w-5 h-5 rounded-full bg-card shadow transition-transform ${estUrgente ? 'translate-x-6' : 'translate-x-0.5'}`} />
          </button>
        </div>

        {estUrgente && (
          <select value={niveauUrgence} onChange={(e) => setNiveauUrgence(Number(e.target.value))} className="input-base" aria-label="Niveau d'urgence">
            <option value={1}>Modéré — besoin sous 48h</option>
            <option value={2}>Élevé — besoin sous 24h</option>
            <option value={3}>Critique — besoin sous 6h</option>
        </select>
        )}

        {/* Mode de sélection */}
        <div className="card-base border-border">
          <p className="text-sm font-medium text-foreground mb-3">Mode de sélection</p>
          <div className="space-y-2">
            <label className="flex items-start gap-3 cursor-pointer group">
              <input type="radio" name="modeAttribution" checked={modeAttribution === 'PREMIER_ARRIVE'}
                onChange={() => setModeAttribution('PREMIER_ARRIVE')} className="mt-0.5 accent-primary" />
              <div>
                <span className="text-sm text-foreground font-medium group-hover:text-primary transition-colors inline-flex items-center gap-1.5"><Timer aria-hidden="true" className="h-4 w-4" />Premier arrivé</span>
                <p className="text-xs text-muted-foreground">Le premier soignant qui accepte remporte la mission.</p>
              </div>
            </label>
            <label className="flex items-start gap-3 cursor-pointer group">
              <input type="radio" name="modeAttribution" checked={modeAttribution === 'CANDIDATURE'}
                onChange={() => setModeAttribution('CANDIDATURE')} className="mt-0.5 accent-primary" />
              <div>
                <span className="text-sm text-foreground font-medium group-hover:text-primary transition-colors inline-flex items-center gap-1.5"><User aria-hidden="true" className="h-4 w-4" />Je choisis</span>
                <p className="text-xs text-muted-foreground">Les soignants postulent, vous consultez les profils et choisissez.</p>
              </div>
            </label>
          </div>
        </div>

        {/* Estimation de l'ensemble des créneaux exacts. */}
        {taux > 0 && recurrenceValidation && recurrenceValidation.totalHebdo > 0 && (() => {
          const totalH = creneaux.length > 0
            ? creneaux.reduce((s, c) => s + c.dureeHeures, 0)
            : recurrenceValidation.totalHebdo;
          const label = creneaux.length > 0
            ? `${creneaux.length} créneau${creneaux.length > 1 ? 'x' : ''} — ${totalH.toFixed(0)}h total`
            : `${recurrenceValidation.totalHebdo}h / semaine (renseignez les dates pour le total)`;
          return (
            <div className="bg-gradient-to-r from-primary/5 to-info/5 border border-primary/20 rounded-2xl p-5">
              <p className="font-bold text-foreground mb-3 flex items-center gap-1.5"><Calculator aria-hidden="true" className="h-4 w-4" />Estimation de rémunération du planning</p>
              <div className="space-y-2 text-sm">
                <div className="flex justify-between">
                  <span className="text-muted-foreground">Taux de base</span>
                  <span className="font-medium">{taux.toFixed(2)} €/h</span>
                </div>
                <div className="flex justify-between">
                  <span className="text-muted-foreground">{label}</span>
                  <span className="font-medium">~{totalH.toFixed(0)}h</span>
                </div>
                <div className="border-t border-border pt-2 flex justify-between">
                  <span className="text-muted-foreground">Base brute estimée</span>
                  <span className="font-bold text-primary">~{(taux * totalH).toFixed(2)} €</span>
                </div>
              </div>
            </div>
          );
        })()}

        {/* Encart commission dégressive */}
        {taux > 0 && dureeEstimee > 0 && (
          <EncartCommissionDegressif
            netEstime={taux * dureeEstimee * 1.21}
            tauxActuel={tauxCommission}
            palierNom={palierNom}
          />
        )}

        <p className="text-[10px] text-muted-foreground italic text-center">
          Simulation à titre indicatif. Seuls les montants calculés par le moteur de paie font foi.
        </p>

        {/* Submit */}
        <button type="submit" disabled={!canSubmit}
          className="btn-primary w-full flex items-center justify-center gap-2 disabled:opacity-50">
          {loading && <Loader2 className="h-4 w-4 animate-spin" />}
          {modeEdition ? <><Save aria-hidden="true" className="h-4 w-4" />Enregistrer les modifications</> :
            <><Send aria-hidden="true" className="h-4 w-4" />Publier la mission{creneaux.length > 1 ? ` (${creneaux.length} créneaux)` : ''}</>}
        </button>
        {/* Lot 11 : plus de doublon d'erreur ici — la zone unique d'erreurs 48h
            vit dans le bloc récurrence (scroll auto), le bouton est désactivé. */}
      </form>

      {erreurCodeTravail && (
        <ModalCodeTravail erreur={erreurCodeTravail} onFermer={() => setErreurCodeTravail(null)} />
      )}

      {publicationEnCours && (
        <div className="fixed inset-0 z-50 flex items-center justify-center bg-background/70 backdrop-blur-sm">
          <div className="flex items-center gap-3 rounded-xl bg-card px-5 py-4 shadow-lg border border-border">
            <Loader2 className="h-5 w-5 animate-spin text-primary" />
            <span className="text-sm font-medium text-foreground">Publication de la mission…</span>
          </div>
        </div>
      )}

      {/* Sprint 7 PR 1 — Modal récap avant publication finale (P1-4)
          Sprint 8 ter-G : lazy mount (code splitting) */}
      {modalRecapOuvert && (
        <Suspense fallback={null}>
          <ModalRecapMission
            ouvert={true}
            data={recapData}
            onModifier={() => setModalRecapOuvert(false)}
            onConfirmer={enregistrerMission}
            loading={loading || publicationEnCours}
            labelConfirmer={modeEdition ? 'Enregistrer' : 'Publier'}
          />
        </Suspense>
      )}
    </>
  );
}
