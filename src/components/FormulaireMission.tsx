import React, { useState, useEffect, useMemo, Suspense } from 'react';
import { lazyRetry as lazy } from '@/lib/lazyRetry';
import { useNavigate, useSearchParams, Link } from 'react-router-dom';
import { Loader2, AlertTriangle, CalendarDays, Timer, Ban, Banknote, Lightbulb, Lock, User, Calculator, Info, Save, Send, ClipboardList } from 'lucide-react';
import { extraireContratPreference, injecterContratTag, peutExercerLiberal, getLabelProfession, getLabelTypeEtablissement, type ContratPreference } from '@/lib/constantes';
import { SelectProfession } from '@/components/SelectProfession';
import { SelectSpecialiteMedicale } from '@/components/SelectSpecialiteMedicale';
import { WarningRist } from '@/components/WarningRist';
import { useTypesExerciceAutorises } from '@/hooks/useTypesExerciceAutorises';
import { EncartCommissionDegressif } from '@/components/EncartCommissionDegressif';
import { ModalCodeTravail } from '@/components/ModalCodeTravail';
import { FormulaireRecurrence, type RecurrenceFlexConfig, type CreneauFlex, type ValidationFlexResult } from '@/components/FormulaireRecurrence';
import type { RecapMissionData } from '@/components/mission/ModalRecapMission';
// Sprint 8 ter-G PR 3 — lazy load modal récap (code splitting, ~8KB)
const ModalRecapMission = lazy(() =>
  import('@/components/mission/ModalRecapMission').then((m) => ({
    default: m.ModalRecapMission,
  })),
);
import { useAuth } from '@/contexts/AuthContext';
import { useRole } from '@/hooks/useRole';
import { useNotification } from '@/contexts/NotificationContext';
import { supabase } from '@/integrations/supabase/client';
import { extraireMessageErreur, estBlocageCodeTravail } from '@/lib/erreurs';
import { format } from 'date-fns';
import { fr } from 'date-fns/locale';

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

export function FormulaireMission({ missionSource, modeEdition }: FormulaireMissionProps) {
  const navigate = useNavigate();
  const [searchParams] = useSearchParams();
  const { user } = useAuth();
  const { role } = useRole();
  const { afficherNotification } = useNotification();

  const [intitule, setIntitule] = useState('');
  const [description, setDescription] = useState('');
  const [profession, setProfession] = useState('');
  const [specialiteMedicaleRequise, setSpecialiteMedicaleRequise] = useState('');
  const [accepteNonSpecialises, setAccepteNonSpecialises] = useState(true);
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

  // Sélecteur jours/dates : toujours actif pour une NOUVELLE mission (multi-jours
  // = 1 mission). En édition, on garde l'ancien créneau unique début/fin.
  const [modeRecurrent] = useState(!modeEdition);
  const [creneaux, setCreneaux] = useState<CreneauFlex[]>([]);
  const [recurrenceValidation, setRecurrenceValidation] = useState<ValidationFlexResult | null>(null);
  const [publicationEnCours, setPublicationEnCours] = useState(false);

  const [etablissementType, setEtablissementType] = useState<string | null>(null);
  const [erreurFactureImpayee, setErreurFactureImpayee] = useState(false);
  const [toleranceGpsMetres, setToleranceGpsMetres] = useState<number | null>(null);
  // Sprint 7 PR 1 — Modal récap mission (P1-4)
  const [modalRecapOuvert, setModalRecapOuvert] = useState(false);
  const { typesAutorises: typesExAutorise, uniqueType: uniqueExType } = useTypesExerciceAutorises(profession);

  // Auto-set contratPreference when profession only allows SALARIE
  useEffect(() => {
    if (uniqueExType === 'SALARIE') {
      setContratPreference('SALARIE');
    }
  }, [uniqueExType]);
  const [siretInvalide, setSiretInvalide] = useState(false);
  const [contratNonValide, setContratNonValide] = useState(false);

  // Load rist_plafond_actif + commission info + type + siret validation
  const [estSecteurPublic, setEstSecteurPublic] = useState(false);
  useEffect(() => {
    if (!user) return;
    supabase.rpc('fn_mon_etablissement_complet' as any).then(({ data, error }: any) => {
      if (error) {
        console.warn('FormulaireMission: fn_mon_etablissement_complet error', error);
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
        // Check contrat validation — explicit reset
        setContratNonValide(data.contrat_valide !== true);
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
      // params (?debut=<iso>&fin=<iso>), on préremplit les horaires. Format attendu
      // pour <input datetime-local> : "YYYY-MM-DDTHH:mm" (slice ISO à 16 caractères).
      const debutParam = searchParams.get('debut');
      const finParam = searchParams.get('fin');
      if (debutParam) setDebutLe(debutParam.slice(0, 16));
      if (finParam) setFinLe(finParam.slice(0, 16));

      supabase.from('missions').select('intitule, description, profession_requise, service, taux_horaire_base, est_urgente, niveau_urgence, type_contrat_recherche, specialite_medicale_requise, accepte_non_specialises').eq('id', dupId).single().then(({ data, error }) => {
        if (error) {
          console.warn('FormulaireMission: mission duplication fetch error', error);
          return;
        }
        if (data) {
          setIntitule(data.intitule);
          setDescription(data.description || '');
          setContratPreference(((data as any).type_contrat_recherche as any) || extraireContratPreference(data.description));
          setProfession(data.profession_requise);
          setService(data.service || '');
          setTauxHoraire(String(data.taux_horaire_base));
          setEstUrgente(data.est_urgente || false);
          setNiveauUrgence(data.niveau_urgence || 1);
          setSpecialiteMedicaleRequise(((data as any).specialite_medicale_requise as string) || '');
          setAccepteNonSpecialises((data as any).accepte_non_specialises !== false);
          setDupliquerInfo(data.intitule);
        }
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
      setDebutLe(missionSource.debut_le?.slice(0, 16) || '');
      setFinLe(missionSource.fin_le?.slice(0, 16) || '');
      setTauxHoraire(String(missionSource.taux_horaire_base));
      setEstUrgente(missionSource.est_urgente || false);
      setNiveauUrgence(missionSource.niveau_urgence || 1);
      setModeAttribution(missionSource.mode_attribution || 'PREMIER_ARRIVE');
      setSpecialiteMedicaleRequise(missionSource.specialite_medicale_requise || '');
      setAccepteNonSpecialises(missionSource.accepte_non_specialises !== false);
    }
  }, [missionSource]);

  const taux = parseFloat(tauxHoraire) || 0;

  const { dureeEstimee, heuresNuitEstimees } = useMemo(() => {
    if (modeRecurrent || !debutLe || !finLe) return { dureeEstimee: 0, heuresNuitEstimees: 0 };
    const d = new Date(debutLe);
    const f = new Date(finLe);
    const dur = Math.max(0, (f.getTime() - d.getTime()) / 3600000);
    let nuit = 0;
    const cursor = new Date(d);
    while (cursor < f) {
      const h = cursor.getHours();
      if (h >= 21 || h < 6) nuit += Math.min(1, (f.getTime() - cursor.getTime()) / 3600000);
      cursor.setTime(cursor.getTime() + 3600000);
    }
    return { dureeEstimee: dur, heuresNuitEstimees: Math.min(nuit, dur) };
  }, [debutLe, finLe, modeRecurrent]);

  const erreurDates = useMemo(() => {
    if (modeRecurrent) return null;
    if (!debutLe || !finLe) return null;
    const d = new Date(debutLe);
    const f = new Date(finLe);
    if (f <= d) return 'La fin doit être après le début';
    if (!modeEdition && d < new Date()) return 'La mission ne peut pas commencer dans le passé';
    return null;
  }, [debutLe, finLe, modeEdition, modeRecurrent]);

  const warningDureeLongue = !modeRecurrent && dureeEstimee > 12 && dureeEstimee <= 24;
  const warningDureeTresLongue = !modeRecurrent && dureeEstimee > 24;

  // Recurrence validation
  const recurrenceBlocante = modeRecurrent && recurrenceValidation && !recurrenceValidation.valide;
  const recurrenceValide = modeRecurrent && creneaux.length > 0 && recurrenceValidation && recurrenceValidation.valide;

  const handleRecurrenceChange = (_config: RecurrenceFlexConfig, creneauxGen: CreneauFlex[], validation: ValidationFlexResult) => {
    setCreneaux(creneauxGen);
    setRecurrenceValidation(validation);
  };

  // Publication d'UNE mission multi-jours (1 mission + N créneaux PREVISIONNEL).
  // Le pointage QR, la paie et la facturation gèrent déjà le multi-créneaux.
  const publierMissionMultiJours = async () => {
    if (!user || creneaux.length === 0) return;
    if (creneaux.length > 366) {
      afficherNotification({ type: 'erreur', message: 'Maximum 366 jours par mission.' });
      return;
    }
    setPublicationEnCours(true);
    try {
      // Sanitize description — strip injected tags, puis ré-inject le tag contrat.
      const cleanDesc = (description || '').replace(/\[SERIE_ID:[^\]]*\]/g, '').replace(/\[CONTRAT:[^\]]*\]/g, '').trim();
      const descriptionFinale = injecterContratTag(cleanDesc, contratPreference);

      const creneauxPayload = creneaux.map(c => ({
        debut: new Date(c.debut).toISOString(),
        fin: new Date(c.fin).toISOString(),
      }));

      const { data: rpcResult, error } = await supabase.rpc('fn_creer_mission_multi_jours' as any, {
        p_intitule: intitule,
        p_description: descriptionFinale || null,
        p_profession_requise: profession,
        p_service: service || null,
        p_taux_horaire_base: parseFloat(tauxHoraire) || 0,
        p_est_urgente: estUrgente,
        p_niveau_urgence: estUrgente ? niveauUrgence : 0,
        p_mode_attribution: modeAttribution,
        p_specialite_medicale_requise: profession === 'MEDECIN' ? (specialiteMedicaleRequise || null) : null,
        p_accepte_non_specialises: (profession === 'IBODE' || profession === 'IADE') ? accepteNonSpecialises : true,
        p_creneaux: creneauxPayload as any,
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

      // Parité libéral : type de contrat + rétrocession posés par mission_id.
      if (missionId && contratPreference === 'LIBERAL' && modeRemuneration === 'RETROCESSION') {
        await supabase.rpc('fn_definir_retrocession_mission' as any, {
          p_mission_id: missionId,
          p_pct: Math.min(100, Math.max(1, parseFloat(retrocessionPct) || 50)),
        });
      }
      if (missionId && contratPreference !== 'TOUS') {
        await supabase.rpc('fn_modifier_type_contrat_mission' as any, {
          p_mission_id: missionId,
          p_type_contrat: contratPreference,
        });
      }
      await supabase.rpc('fn_ecrire_audit_safe', {
        p_acteur_id: user.id, p_type_acteur: role, p_action: 'MISSION_CREATION',
        p_type_ressource: 'mission', p_id_ressource: missionId || user.id, p_cle_s3: null,
        p_details: { intitule, profession, taux: tauxHoraire, nb_jours: creneaux.length },
        p_ip: null, p_navigateur: navigator.userAgent,
      });

      afficherNotification({ type: 'succes', message: 'Mission publiée ! Les soignants à proximité sont prévenus 🔔' });
      navigate('/etablissement/missions');
    } finally {
      setPublicationEnCours(false);
    }
  };

  // Sprint 7 PR 1 — Submit intercepté pour afficher le modal récap avant publication.
  // En mode édition ou récurrent, on garde le flow direct (pas de modal).
  const handleSubmit = async (e: React.FormEvent) => {
    e.preventDefault();
    if (!user) return;

    if (modeRecurrent) {
      if (recurrenceBlocante) return;
      if (creneaux.length === 0) return;
      await publierMissionMultiJours();
      return;
    }

    if (erreurDates || !intitule || !profession || !debutLe || !finLe || !tauxHoraire) return;

    // Mode édition : pas de modal récap, on enregistre directement
    if (modeEdition && missionSource) {
      await publierMissionPonctuelle();
      return;
    }

    // Mode création ponctuelle : on ouvre le modal récap
    setModalRecapOuvert(true);
  };

  // Publication ponctuelle (création ou édition) — appelée par le modal en mode création,
  // ou directement par handleSubmit en mode édition.
  const publierMissionPonctuelle = async () => {
    if (!user) return;
    setLoading(true);
    try {
      // C6: Sanitize description — strip injected tags
      const cleanDescription = (description || '').replace(/\[SERIE_ID:[^\]]*\]/g, '').replace(/\[CONTRAT:[^\]]*\]/g, '').trim();
      const descriptionFinale = injecterContratTag(cleanDescription, contratPreference);
      const payload = {
        intitule,
        description: descriptionFinale || null,
        profession_requise: profession,
        service: service || null,
        debut_le: new Date(debutLe).toISOString(),
        fin_le: new Date(finLe).toISOString(),
        taux_horaire_base: parseFloat(tauxHoraire),
        est_urgente: estUrgente,
        niveau_urgence: estUrgente ? niveauUrgence : 0,
        specialite_medicale_requise: profession === 'MEDECIN' ? (specialiteMedicaleRequise || null) : null,
        accepte_non_specialises: (profession === 'IBODE' || profession === 'IADE') ? accepteNonSpecialises : true,
      };

      if (modeEdition && missionSource) {
        const { data: rpcResult, error } = await supabase.rpc('fn_modifier_mission_etablissement' as any, {
          p_mission_id: missionSource.id,
          p_intitule: intitule,
          p_description: descriptionFinale || null,
          p_service: service || null,
        });

        if (error) {
          if (estBlocageCodeTravail(error)) { setErreurCodeTravail(error); }
          else afficherNotification({ type: 'erreur', message: extraireMessageErreur(error) });
          return;
        }
        if ((rpcResult as any)?.success === false) {
          afficherNotification({ type: 'erreur', message: (rpcResult as any).error });
          return;
        }

        afficherNotification({ type: 'succes', message: 'Mission mise à jour !' });
        navigate(`/etablissement/missions/${missionSource.id}`);
      } else {
        // C1: Use secure RPC instead of direct INSERT
        const { data: rpcResult, error } = await supabase.rpc('fn_creer_mission' as any, {
          p_intitule: payload.intitule,
          p_description: payload.description,
          p_profession_requise: payload.profession_requise,
          p_service: payload.service,
          p_debut_le: payload.debut_le,
          p_fin_le: payload.fin_le,
          p_taux_horaire_base: payload.taux_horaire_base,
          p_est_urgente: payload.est_urgente,
          p_niveau_urgence: payload.niveau_urgence,
          p_mode_attribution: modeAttribution,
          p_specialite_medicale_requise: payload.specialite_medicale_requise,
          p_accepte_non_specialises: payload.accepte_non_specialises,
        });

        if (error) {
          if (estBlocageCodeTravail(error)) { setErreurCodeTravail(error); }
          else {
            afficherNotification({ type: 'erreur', message: extraireMessageErreur(error) });
          }
          return;
        }

        if (rpcResult && !(rpcResult as any).success) {
          const msg = (rpcResult as any).error || 'Erreur lors de la création.';
          if (msg.includes('facture') || msg.includes('impayée')) setErreurFactureImpayee(true);
          afficherNotification({ type: 'erreur', message: msg });
          return;
        }

        const missionId = (rpcResult as any)?.mission_id;

        // type_contrat_recherche : passe par RPC dédiée (audit log)
        if (missionId && contratPreference === 'LIBERAL' && modeRemuneration === 'RETROCESSION') {
          await supabase.rpc('fn_definir_retrocession_mission' as any, {
            p_mission_id: missionId,
            p_pct: Math.min(100, Math.max(1, parseFloat(retrocessionPct) || 50)),
          });
        }
        if (missionId && contratPreference !== 'TOUS') {
          await supabase.rpc('fn_modifier_type_contrat_mission' as any, {
            p_mission_id: missionId,
            p_type_contrat: contratPreference,
          });
        }
        await supabase.rpc('fn_ecrire_audit_safe', {
          p_acteur_id: user.id, p_type_acteur: role, p_action: 'MISSION_CREATION',
          p_type_ressource: 'mission', p_id_ressource: missionId || user.id, p_cle_s3: null,
          p_details: { intitule, profession, taux: tauxHoraire, debut: debutLe, fin: finLe },
          p_ip: null, p_navigateur: navigator.userAgent,
        });

        afficherNotification({ type: 'succes', message: 'Mission publiée ! Les soignants à proximité sont prévenus 🔔' });
        setModalRecapOuvert(false);
        navigate('/etablissement/missions');
      }
    } finally {
      setLoading(false);
    }
  };

  const canSubmit = !siretInvalide && !contratNonValide && !erreurFactureImpayee && (modeRecurrent
    ? (!!intitule && !!profession && !!tauxHoraire && recurrenceValide && !publicationEnCours)
    : (!!intitule && !!profession && !!debutLe && !!finLe && !!tauxHoraire && !erreurDates && !loading));

  // Sprint 7 PR 1 — Données récap pour le modal (P1-4)
  const liberalRestreint = !!profession && !!etablissementType && !peutExercerLiberal(profession, etablissementType);
  const recapData: RecapMissionData = {
    intitule,
    description,
    profession,
    service,
    debutLe,
    finLe,
    dureeHeures: dureeEstimee,
    heuresNuit: heuresNuitEstimees,
    tauxHoraire: taux,
    contratPreference,
    modeAttribution,
    estUrgente,
    niveauUrgence,
    tauxCommission,
    toleranceGpsMetres,
    qrAutoGenere: true, // Sprint 4.5 PR 4 : trigger auto à la signature du contrat
    etablissementType,
    liberalRestreint,
  };

  return (
    <>
      {siretInvalide && (
        <div className="bg-warning/10 border border-warning/30 rounded-xl p-3 mb-4 flex items-center gap-2 text-sm">
          <AlertTriangle className="h-4 w-4 text-warning shrink-0" />
          <span>Veuillez compléter votre SIRET dans votre profil avant de publier une mission. <Link to="/etablissement/profil" className="text-primary hover:underline font-medium">Aller au profil →</Link></span>
        </div>
      )}

      {contratNonValide && (
        <div className="bg-warning/10 border border-warning/30 rounded-xl p-3 mb-4 flex items-center gap-2 text-sm">
          <AlertTriangle className="h-4 w-4 text-warning shrink-0" />
          <span>Votre contrat de service n'est pas encore validé. <Link to="/etablissement/parametres?tab=contrats" className="text-primary hover:underline font-medium">Téléverser le contrat →</Link></span>
        </div>
      )}

      {dupliquerInfo && (
        <div className="bg-info/10 border border-info/20 rounded-xl p-3 mb-4 text-sm text-info">
          <ClipboardList aria-hidden="true" className="inline-block h-4 w-4 mr-1 -mt-0.5" />Vous dupliquez la mission « {dupliquerInfo} ». Ajustez les dates ci-dessous.
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
            placeholder="Sélectionnez la profession recherchée"
            filtresProfessions={etablissementType === 'PHARMACIE_OFFICINE' ? ['PHARMACIEN', 'PREPARATEUR_PHARMA'] : undefined}
          />
          {etablissementType === 'PHARMACIE_OFFICINE' && (
            <p className="text-[10px] text-muted-foreground mt-1">Pharmacie : seuls les pharmaciens et préparateurs sont proposés.</p>
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

        {/* Tolérance IDE non spécialisés pour IBODE/IADE */}
        {(profession === 'IBODE' || profession === 'IADE') && (
          <div className="rounded-xl border border-primary/20 bg-primary/5 p-3">
            <label className="flex items-start gap-3 cursor-pointer">
              <input
                type="checkbox"
                checked={accepteNonSpecialises}
                onChange={(e) => setAccepteNonSpecialises(e.target.checked)}
                className="mt-0.5 h-4 w-4 rounded border-border accent-primary"
              />
              <div className="flex-1">
                <span className="text-sm font-medium text-foreground">
                  Accepter aussi les IDE non spécialisés
                </span>
                <p className="text-xs text-muted-foreground mt-0.5">
                  Élargit le vivier aux IDE motivés qui peuvent assister un {profession === 'IBODE' ? 'IBODE' : 'IADE'}.
                </p>
              </div>
            </label>
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
              'Rééducation', 'EHPAD', 'Psychiatrie', 'Oncologie', 'Officine'].map((s) => (
              <option key={s} value={s} />
            ))}
          </datalist>
        </div>

        {/* Type de contrat proposé (Lot 11 : c'est le choix du type_contrat de la
            mission, pas un « profil » — chaque option affiche ses conséquences) */}
        <div>
          <label className="text-sm font-medium text-foreground mb-2 block">Type de contrat proposé</label>
          {uniqueExType === 'SALARIE' ? (
            <div className="p-3 bg-primary/5 border border-primary/20 rounded-xl">
              <p className="text-sm text-foreground">
                Pour cette profession, seuls les profils <strong>salariés</strong> sont autorisés.
              </p>
            </div>
          ) : (
          <div className="space-y-2">
            {(() => {
              // PR 2 Sprint 1 — matrice de compatibilité prof × type_etab.
              // Si la combinaison ne permet pas le libéral, on retire l'option.
              const liberalAutorise = profession && etablissementType
                ? peutExercerLiberal(profession, etablissementType)
                : true;
              return ([
                { value: 'TOUS' as const, label: 'Tous profils', desc: 'Selon le soignant retenu : salarié (vous êtes l’employeur) ou libéral (honoraires via la plateforme)' },
                { value: 'SALARIE' as const, label: 'Salarié', desc: 'Vous êtes l’employeur : CDD, bulletin de paie, plafond légal 48 h/semaine' },
                { value: 'LIBERAL' as const, label: 'Libéral', desc: 'Honoraires facturés via la plateforme — pas de plafond horaire' },
              ]).filter(opt => {
                if (typesExAutorise && opt.value !== 'TOUS' && !typesExAutorise.includes(opt.value)) return false;
                // Bloquer LIBERAL si incompatible avec le type d'établissement courant
                if (opt.value === 'LIBERAL' && !liberalAutorise) return false;
                // Bloquer TOUS si LIBERAL n'est pas autorisé (force SALARIE only)
                if (opt.value === 'TOUS' && !liberalAutorise) return false;
                return true;
              });
            })().map(opt => (
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
            {profession && etablissementType && !peutExercerLiberal(profession, etablissementType) && (
              <div className="text-xs text-amber-700 dark:text-amber-400 bg-amber-50 dark:bg-amber-950/30 border border-amber-200 dark:border-amber-900 rounded-lg p-3 mt-2">
                <strong><Info aria-hidden="true" className="inline-block h-3.5 w-3.5 mr-1 -mt-0.5" />Mode libéral non disponible :</strong> pour <strong>{getLabelProfession(profession)}</strong> en <strong>{getLabelTypeEtablissement(etablissementType).toLowerCase()}</strong>, le mode libéral n'est pas autorisé par la réglementation (cas de salariat déguisé, cf Conseil d'État 11/02/2025 arrêt Mediflash). Vous pouvez proposer la mission en CDD ou Vacation.
              </div>
            )}
          </div>
          )}
        </div>

        {/* Mode ponctuel: horaires */}
        {!modeRecurrent && (
          <div className="border border-primary/20 rounded-xl p-4 bg-primary/5 space-y-3">
            <p className="text-sm font-semibold text-foreground flex items-center gap-1.5"><CalendarDays aria-hidden="true" className="h-4 w-4" />Horaires de la mission</p>
            <div className="grid grid-cols-1 md:grid-cols-2 gap-3">
              <div>
                <label htmlFor="mission-debut-le" className="text-xs text-muted-foreground mb-1 block">Date et heure de début *</label>
                <input
                  id="mission-debut-le"
                  type="datetime-local"
                  value={debutLe}
                  onChange={(e) => setDebutLe(e.target.value)}
                  min={!modeEdition ? new Date().toISOString().slice(0, 16) : undefined}
                  required
                  className="input-base"
                />
              </div>
              <div>
                <label htmlFor="mission-fin-le" className="text-xs text-muted-foreground mb-1 block">Date et heure de fin *</label>
                <input id="mission-fin-le" type="datetime-local" value={finLe} onChange={(e) => setFinLe(e.target.value)} required className="input-base" />
              </div>
            </div>
            {erreurDates && <p className="text-xs text-destructive font-medium flex items-center gap-1"><Ban aria-hidden="true" className="h-3.5 w-3.5 shrink-0" />{erreurDates === 'La mission ne peut pas commencer dans le passé' ? 'La mission doit commencer dans le futur.' : erreurDates}</p>}
            {warningDureeLongue && <p className="text-xs text-warning font-medium flex items-center gap-1"><AlertTriangle aria-hidden="true" className="h-3.5 w-3.5 shrink-0" />Mission longue — assurez-vous que les repos légaux sont respectés</p>}
            {warningDureeTresLongue && <p className="text-xs text-destructive font-medium flex items-center gap-1"><AlertTriangle aria-hidden="true" className="h-3.5 w-3.5 shrink-0" />Pour un remplacement de plusieurs jours, utilisez le mode récurrent ci-dessous</p>}
            {dureeEstimee > 0 && !erreurDates && (
              <div className="text-center">
                <span className="badge-base bg-primary/10 text-primary inline-flex items-center gap-1">
                  <Timer aria-hidden="true" className="h-3.5 w-3.5" />Durée estimée : {Math.floor(dureeEstimee)}h{String(Math.round((dureeEstimee % 1) * 60)).padStart(2, '0')}
                </span>
                {heuresNuitEstimees > 0 && (
                  <p className="text-[10px] text-muted-foreground mt-1">dont ~{heuresNuitEstimees.toFixed(0)}h de nuit (21h-6h)</p>
                )}
              </div>
            )}
          </div>
        )}

        {/* Planification jours/dates — toujours affichée pour une nouvelle mission.
            Une mission de plusieurs jours = UNE seule mission (plusieurs créneaux). */}
        {!modeEdition && (
          <div>
            <p className="text-sm font-semibold text-foreground mb-1 flex items-center gap-1.5"><CalendarDays aria-hidden="true" className="h-4 w-4" />Jours et horaires de la mission</p>
            <p className="text-xs text-muted-foreground mb-3">
              Choisissez la période, puis ajustez les jours travaillés. Tout est publié en <strong>une seule mission</strong>.
            </p>
            <FormulaireRecurrence onChange={handleRecurrenceChange} />
          </div>
        )}

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
                onChange={() => { setModeRemuneration('RETROCESSION'); setTauxHoraire('0'); }} className="mt-0.5 accent-primary" />
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

        {/* Estimation (ponctuel only) */}
        {!modeRecurrent && dureeEstimee > 0 && taux > 0 && (
          <div className="bg-gradient-to-r from-primary/5 to-info/5 border border-primary/20 rounded-2xl p-5">
            <p className="font-bold text-foreground mb-3 flex items-center gap-1.5"><Calculator aria-hidden="true" className="h-4 w-4" />Estimation de rémunération</p>
            <div className="space-y-2 text-sm">
              <div className="flex justify-between">
                <span className="text-muted-foreground">Taux de base</span>
                <span className="font-medium">{taux.toFixed(2)} €/h</span>
              </div>
              <div className="flex justify-between">
                <span className="text-muted-foreground">Durée estimée</span>
                <span className="font-medium">~{dureeEstimee.toFixed(1)}h</span>
              </div>
              <div className="border-t border-border pt-2 flex justify-between">
                <span className="text-muted-foreground">Base brute estimée</span>
                <span className="font-bold text-primary">~{(taux * dureeEstimee).toFixed(2)} €</span>
              </div>
            </div>
            <div className="mt-3 text-xs text-muted-foreground space-y-1">
              <p className="flex items-center gap-1"><Info aria-hidden="true" className="h-3.5 w-3.5 shrink-0" />Le montant final inclura automatiquement :</p>
              <p>• Majorations nuit (21h-6h), dimanche et jours fériés</p>
              <p>• IFM 10% (Indemnité de Fin de Mission)</p>
              <p>• ICP 10% (Indemnité de Congés Payés)</p>
              <p className="mt-1">→ Le net à payer sera calculé après la création.</p>
            </div>
          </div>
        )}

        {/* Estimation (récurrent) */}
        {modeRecurrent && taux > 0 && recurrenceValidation && recurrenceValidation.totalHebdo > 0 && (() => {
          const totalH = creneaux.length > 0
            ? creneaux.reduce((s, c) => s + c.dureeHeures, 0)
            : recurrenceValidation.totalHebdo;
          const label = creneaux.length > 0
            ? `${creneaux.length} créneau${creneaux.length > 1 ? 'x' : ''} — ${totalH.toFixed(0)}h total`
            : `${recurrenceValidation.totalHebdo}h / semaine (renseignez les dates pour le total)`;
          return (
            <div className="bg-gradient-to-r from-primary/5 to-info/5 border border-primary/20 rounded-2xl p-5">
              <p className="font-bold text-foreground mb-3 flex items-center gap-1.5"><Calculator aria-hidden="true" className="h-4 w-4" />Estimation de rémunération (série)</p>
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
        {taux > 0 && ((dureeEstimee > 0 && !modeRecurrent) || (modeRecurrent && recurrenceValidation && recurrenceValidation.totalHebdo > 0)) && (
          <EncartCommissionDegressif
            netEstime={taux * (modeRecurrent ? creneaux.reduce((s, c) => s + c.dureeHeures, 0) : dureeEstimee) * 1.21}
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
            <><Send aria-hidden="true" className="h-4 w-4" />Publier la mission{modeRecurrent && creneaux.length > 1 ? ` (${creneaux.length} jours)` : ''}</>}
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
            onConfirmer={publierMissionPonctuelle}
            loading={loading}
          />
        </Suspense>
      )}
    </>
  );
}
