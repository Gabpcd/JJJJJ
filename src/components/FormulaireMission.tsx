import React, { useState, useEffect, useMemo } from 'react';
import { useNavigate, useSearchParams, Link } from 'react-router-dom';
import { Loader2, AlertTriangle } from 'lucide-react';
import { extraireContratPreference, injecterContratTag, type ContratPreference } from '@/lib/constantes';
import { SelectProfession } from '@/components/SelectProfession';
import { WarningRist } from '@/components/WarningRist';
import { useTypesExerciceAutorises } from '@/hooks/useTypesExerciceAutorises';
import { EncartCommissionDegressif } from '@/components/EncartCommissionDegressif';
import { ModalCodeTravail } from '@/components/ModalCodeTravail';
import { FormulaireRecurrence, type RecurrenceFlexConfig, type CreneauFlex, type ValidationFlexResult } from '@/components/FormulaireRecurrence';
import { BarreProgressionBulk } from '@/components/BarreProgressionBulk';
import { useAuth } from '@/contexts/AuthContext';
import { useRole } from '@/hooks/useRole';
import { useNotification } from '@/contexts/NotificationContext';
import { supabase } from '@/integrations/supabase/client';
import { logger } from '@/lib/logger';
import { extraireMessageErreur, estBlocageCodeTravail } from '@/lib/erreurs';
import { format } from 'date-fns';
import { fr } from 'date-fns/locale';

interface FormulaireMissionProps {
  missionSource?: any;
  modeEdition?: boolean;
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
  const [service, setService] = useState('');
  const [debutLe, setDebutLe] = useState('');
  const [finLe, setFinLe] = useState('');
  const [tauxHoraire, setTauxHoraire] = useState('');
  const [estUrgente, setEstUrgente] = useState(false);
  const [niveauUrgence, setNiveauUrgence] = useState(1);
  const [modeAttribution, setModeAttribution] = useState<'PREMIER_ARRIVE' | 'CANDIDATURE'>('PREMIER_ARRIVE');
  const [contratPreference, setContratPreference] = useState<'TOUS' | 'SALARIE' | 'LIBERAL'>('TOUS');
  const [loading, setLoading] = useState(false);
  const [erreurCodeTravail, setErreurCodeTravail] = useState<any>(null);
  const [dupliquerInfo, setDupliquerInfo] = useState<string | null>(null);
  const [ristPlafondActif, setRistPlafondActif] = useState(false);
  const [tauxCommission, setTauxCommission] = useState(15);
  const [palierNom, setPalierNom] = useState('Découverte');

  // Recurrence state
  const [modeRecurrent, setModeRecurrent] = useState(false);
  const [recurrenceConfig, setRecurrenceConfig] = useState<RecurrenceFlexConfig | null>(null);
  const [creneaux, setCreneaux] = useState<CreneauFlex[]>([]);
  const [recurrenceValidation, setRecurrenceValidation] = useState<ValidationFlexResult | null>(null);
  const [publicationEnCours, setPublicationEnCours] = useState(false);
  const [progression, setProgression] = useState(0);
  const [progressionActuel, setProgressionActuel] = useState(0);

  const [etablissementType, setEtablissementType] = useState<string | null>(null);
  const [erreurFactureImpayee, setErreurFactureImpayee] = useState(false);
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
        logger.error('[FormulaireMission] fn_mon_etablissement_complet error', error);
        return;
      }
      if (data) {
        setEstSecteurPublic(data.est_secteur_public === true);
        const typesPublics = ['HOPITAL_PUBLIC', 'CENTRE_SANTE'];
        const isPublic = data.est_secteur_public === true || typesPublics.includes(data.type);
        setRistPlafondActif(data.rist_plafond_actif === true && isPublic);
        setTauxCommission(data.taux_commission_negocie ?? 15);
        setEtablissementType(data.type);
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
      supabase.from('missions').select('intitule, description, profession_requise, service, taux_horaire_base, est_urgente, niveau_urgence, type_contrat_recherche').eq('id', dupId).single().then(({ data, error }) => {
        if (error) {
          logger.error('[FormulaireMission] mission duplication fetch error', error);
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
    }
  }, [missionSource]);

  const tauxBrut = parseFloat(tauxHoraire) || 0;
  const taux = Math.min(10000, Math.max(0, tauxBrut));

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

  const handleRecurrenceChange = (config: RecurrenceFlexConfig, creneauxGen: CreneauFlex[], validation: ValidationFlexResult) => {
    setRecurrenceConfig(config);
    setCreneaux(creneauxGen);
    setRecurrenceValidation(validation);
  };

  // Bulk publish via atomic RPC (C2)
  const publierSerieRecurrente = async () => {
    if (!user || !recurrenceConfig || creneaux.length === 0) return;
    if (creneaux.length > 30) {
      afficherNotification({ type: 'erreur', message: 'Maximum 30 créneaux par série récurrente.' });
      return;
    }
    setPublicationEnCours(true);
    setProgression(0);
    setProgressionActuel(0);

    const serieId = `SERIE_${Date.now()}_${Math.random().toString(36).slice(2, 8)}`;
    // C6: Sanitize description — strip any injected tags before sending to server
    const cleanDesc = (description || '').replace(/\[SERIE_ID:[^\]]*\]/g, '').replace(/\[CONTRAT:[^\]]*\]/g, '').trim();
    const descWithContrat = injecterContratTag(cleanDesc, contratPreference);
    const descriptionAvecTag = `[SERIE_ID:${serieId}] ${descWithContrat}`.trim();

    const missionsPayload = creneaux.map(c => ({
      debut: new Date(c.debut).toISOString(),
      fin: new Date(c.fin).toISOString(),
    }));

    const { data: rpcResult, error } = await supabase.rpc('fn_creer_serie' as any, {
      p_intitule: intitule,
      p_description: descriptionAvecTag,
      p_profession_requise: profession,
      p_service: service || null,
      p_taux_horaire_base: parseFloat(tauxHoraire),
      p_est_urgente: estUrgente,
      p_niveau_urgence: estUrgente ? niveauUrgence : 0,
      p_missions: JSON.stringify(missionsPayload),
    });

    setProgression(100);
    setProgressionActuel(creneaux.length);

    // C5: Audit — type_acteur resolved server-side by fn_creer_serie RPC, no client audit for serie needed
    // The RPC itself handles the audit internally

    setPublicationEnCours(false);

    if (error) {
      afficherNotification({ type: 'erreur', message: extraireMessageErreur(error) });
      return;
    }
    if (rpcResult && !(rpcResult as any).success) {
      const msg = (rpcResult as any).error || 'Erreur lors de la création de la série.';
      if (msg.includes('facture') || msg.includes('impayée')) setErreurFactureImpayee(true);
      afficherNotification({ type: 'erreur', message: msg });
      return;
    }

    const count = (rpcResult as any)?.count || creneaux.length;
    afficherNotification({ type: 'succes', message: `✅ ${count} missions créées avec succès !` });
    navigate('/etablissement/missions');
  };

  // Single mission submit
  const handleSubmit = async (e: React.FormEvent) => {
    e.preventDefault();
    if (!user) return;

    if (modeRecurrent) {
      if (recurrenceBlocante) return;
      if (creneaux.length === 0) return;
      await publierSerieRecurrente();
      return;
    }

    if (erreurDates || !intitule || !profession || !debutLe || !finLe || !tauxHoraire) return;

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

        // Set type_contrat_recherche column
        if (missionId && contratPreference !== 'TOUS') {
          await supabase.from('missions').update({ type_contrat_recherche: contratPreference } as any).eq('id', missionId);
        }
        await supabase.rpc('fn_ecrire_audit_safe', {
          p_acteur_id: user.id, p_type_acteur: role, p_action: 'MISSION_CREATION',
          p_type_ressource: 'mission', p_id_ressource: missionId || user.id, p_cle_s3: null,
          p_details: { intitule, profession, taux: tauxHoraire, debut: debutLe, fin: finLe },
          p_ip: null, p_navigateur: navigator.userAgent,
        });

        afficherNotification({ type: 'succes', message: 'Mission publiée avec succès !' });
        navigate('/etablissement/missions');
      }
    } finally {
      setLoading(false);
    }
  };

  const canSubmit = !siretInvalide && !erreurFactureImpayee && (modeRecurrent
    ? (!!intitule && !!profession && !!tauxHoraire && recurrenceValide && !publicationEnCours)
    : (!!intitule && !!profession && !!debutLe && !!finLe && !!tauxHoraire && !erreurDates && !loading));

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
          <span>Votre contrat de service n'est pas encore validé. <Link to="/etablissement/profil" className="text-primary hover:underline font-medium">Téléverser le contrat →</Link></span>
        </div>
      )}

      {dupliquerInfo && (
        <div className="bg-info/10 border border-info/20 rounded-xl p-3 mb-4 text-sm text-info">
          📋 Vous dupliquez la mission « {dupliquerInfo} ». Ajustez les dates ci-dessous.
        </div>
      )}

      {erreurFactureImpayee && (
        <div className="bg-destructive/10 border border-destructive/30 rounded-xl p-3 mb-4">
          <p className="text-sm font-semibold text-destructive">⚠️ Vous avez des factures impayées.</p>
          <p className="text-xs text-destructive/80 mt-1">Vous devez régulariser vos factures avant de publier de nouvelles missions.</p>
          <a href="/etablissement/facturation" className="text-sm font-medium text-destructive underline mt-2 inline-block">
            Régulariser mes factures →
          </a>
        </div>
      )}

      <form onSubmit={handleSubmit} className="space-y-5">
        {/* Intitulé */}
        <div>
          <label className="text-sm font-medium text-foreground mb-1 block">Intitulé *</label>
          <input value={intitule} onChange={(e) => setIntitule(e.target.value.slice(0, 120))}
            placeholder="Ex: IDE de nuit — Service Urgences" required className="input-base" />
          <p className="text-[10px] text-muted-foreground mt-1 text-right">{intitule.length}/120</p>
        </div>

        {/* Description */}
        <div>
          <label className="text-sm font-medium text-foreground mb-1 block">Description</label>
          <textarea value={description} onChange={(e) => setDescription(e.target.value)}
            placeholder="Informations complémentaires pour le soignant..." rows={3} className="input-base resize-none" />
        </div>

        {/* Profession */}
        <div>
          <label className="text-sm font-medium text-foreground mb-1 block">Profession requise *</label>
          <SelectProfession
            value={profession}
            onChange={setProfession}
            filtresProfessions={etablissementType === 'PHARMACIE_OFFICINE' ? ['PHARMACIEN', 'PREPARATEUR_PHARMA'] : undefined}
          />
          {etablissementType === 'PHARMACIE_OFFICINE' && (
            <p className="text-[10px] text-muted-foreground mt-1">🏥 Pharmacie : seuls les pharmaciens et préparateurs sont proposés.</p>
          )}
        </div>

        {/* Service */}
        <div>
          <label className="text-sm font-medium text-foreground mb-1 block">Service</label>
          <input value={service} onChange={(e) => setService(e.target.value)}
            placeholder="Ex: Urgences, Gériatrie, Réa, Bloc, EHPAD" className="input-base" />
        </div>

        {/* Type de profil recherché */}
        <div>
          <label className="text-sm font-medium text-foreground mb-2 block">Type de profil recherché</label>
          {uniqueExType === 'SALARIE' ? (
            <div className="p-3 bg-primary/5 border border-primary/20 rounded-xl">
              <p className="text-sm text-foreground">
                Pour cette profession, seuls les profils <strong>salariés</strong> sont autorisés.
              </p>
            </div>
          ) : (
          <div className="space-y-2">
            {([
              { value: 'TOUS' as const, label: 'Tous les profils', desc: 'Salariés et libéraux peuvent postuler' },
              { value: 'SALARIE' as const, label: 'Salarié uniquement', desc: 'Contrat CDDU — soumis au plafond 48h/semaine' },
              { value: 'LIBERAL' as const, label: 'Libéral uniquement', desc: 'Remplacement libéral — pas de plafond horaire' },
            ]).filter(opt => !typesExAutorise || opt.value === 'TOUS' || typesExAutorise.includes(opt.value)).map(opt => (
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
          </div>
          )}
        </div>

        {/* Mode ponctuel: horaires */}
        {!modeRecurrent && (
          <div className="border border-primary/20 rounded-xl p-4 bg-primary/5 space-y-3">
            <p className="text-sm font-semibold text-foreground">📅 Horaires de la mission</p>
            <div className="grid grid-cols-1 md:grid-cols-2 gap-3">
              <div>
                <label className="text-xs text-muted-foreground mb-1 block">Date et heure de début *</label>
                <input
                  type="datetime-local"
                  value={debutLe}
                  onChange={(e) => setDebutLe(e.target.value)}
                  min={!modeEdition ? new Date().toISOString().slice(0, 16) : undefined}
                  required
                  className="input-base"
                />
              </div>
              <div>
                <label className="text-xs text-muted-foreground mb-1 block">Date et heure de fin *</label>
                <input type="datetime-local" value={finLe} onChange={(e) => setFinLe(e.target.value)} required className="input-base" />
              </div>
            </div>
            {erreurDates && <p className="text-xs text-destructive font-medium">{erreurDates === 'La mission ne peut pas commencer dans le passé' ? '⛔ La mission doit commencer dans le futur.' : erreurDates}</p>}
            {warningDureeLongue && <p className="text-xs text-warning font-medium">⚠️ Mission longue — assurez-vous que les repos légaux sont respectés</p>}
            {warningDureeTresLongue && <p className="text-xs text-destructive font-medium">⚠️ Pour un remplacement de plusieurs jours, utilisez le mode récurrent ci-dessous</p>}
            {dureeEstimee > 0 && !erreurDates && (
              <div className="text-center">
                <span className="badge-base bg-primary/10 text-primary">
                  ⏱ Durée estimée : {Math.floor(dureeEstimee)}h{String(Math.round((dureeEstimee % 1) * 60)).padStart(2, '0')}
                </span>
                {heuresNuitEstimees > 0 && (
                  <p className="text-[10px] text-muted-foreground mt-1">dont ~{heuresNuitEstimees.toFixed(0)}h de nuit (21h-6h)</p>
                )}
              </div>
            )}
          </div>
        )}

        {/* Toggle Récurrence */}
        {!modeEdition && (
          <div className="flex items-center justify-between py-2">
            <label className="text-sm font-medium text-foreground">🔁 Mission récurrente (plusieurs jours)</label>
            <button
              type="button"
              onClick={() => setModeRecurrent(!modeRecurrent)}
              className={`relative w-12 h-6 rounded-full transition-colors ${modeRecurrent ? 'bg-primary' : 'bg-muted'}`}
            >
              <span className={`absolute top-0.5 w-5 h-5 rounded-full bg-card shadow transition-transform ${modeRecurrent ? 'translate-x-6' : 'translate-x-0.5'}`} />
            </button>
          </div>
        )}

        {/* Mode récurrent: formulaire */}
        {modeRecurrent && !modeEdition && (
          <FormulaireRecurrence onChange={handleRecurrenceChange} />
        )}

        {/* Taux horaire */}
        <div>
          <label className="text-sm font-medium text-foreground mb-1 block">Taux horaire brut * (€/h)</label>
          <div className="relative">
            <input type="number" step="0.01" min="11.65" value={tauxHoraire}
              onChange={(e) => setTauxHoraire(e.target.value)} placeholder="25.00" required
              readOnly={modeEdition && missionSource?.statut !== 'OUVERTE'}
              className={`input-base pr-12 ${modeEdition && missionSource?.statut !== 'OUVERTE' ? 'bg-muted cursor-not-allowed' : ''}`} />
            <span className="absolute right-3 top-1/2 -translate-y-1/2 text-sm text-muted-foreground">€/h</span>
          </div>
          {modeEdition && missionSource?.statut !== 'OUVERTE' && (
            <p className="text-[10px] text-muted-foreground mt-1">🔒 Ces champs ne sont plus modifiables après acceptation.</p>
          )}
        </div>

        {/* Warning Rist */}
        {profession && taux > 0 && <WarningRist profession={profession} tauxSaisi={taux} ristPlafondActif={ristPlafondActif} estSecteurPublic={estSecteurPublic} />}

        {/* Urgence */}
        <div className="flex items-center justify-between">
          <label className="text-sm font-medium text-foreground">Mission urgente ?</label>
          <button type="button" onClick={() => setEstUrgente(!estUrgente)}
            className={`relative w-12 h-6 rounded-full transition-colors ${estUrgente ? 'bg-primary' : 'bg-muted'}`}>
            <span className={`absolute top-0.5 w-5 h-5 rounded-full bg-card shadow transition-transform ${estUrgente ? 'translate-x-6' : 'translate-x-0.5'}`} />
          </button>
        </div>

        {estUrgente && (
          <select value={niveauUrgence} onChange={(e) => setNiveauUrgence(Number(e.target.value))} className="input-base">
            <option value={1}>⚡ Modéré — sous 48h</option>
            <option value={2}>🔥 Élevé — sous 24h</option>
            <option value={3}>🚨 Critique — sous 6h</option>
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
                <span className="text-sm text-foreground font-medium group-hover:text-primary transition-colors">⚡ Premier arrivé</span>
                <p className="text-xs text-muted-foreground">Le premier soignant qui accepte remporte la mission.</p>
              </div>
            </label>
            <label className="flex items-start gap-3 cursor-pointer group">
              <input type="radio" name="modeAttribution" checked={modeAttribution === 'CANDIDATURE'}
                onChange={() => setModeAttribution('CANDIDATURE')} className="mt-0.5 accent-primary" />
              <div>
                <span className="text-sm text-foreground font-medium group-hover:text-primary transition-colors">👤 Je choisis</span>
                <p className="text-xs text-muted-foreground">Les soignants postulent, vous consultez les profils et choisissez.</p>
              </div>
            </label>
          </div>
        </div>

        {/* Estimation (ponctuel only) */}
        {!modeRecurrent && dureeEstimee > 0 && taux > 0 && (
          <div className="bg-gradient-to-r from-primary/5 to-info/5 border border-primary/20 rounded-2xl p-5">
            <p className="font-bold text-foreground mb-3">💰 Estimation de rémunération</p>
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
              <p>ℹ️ Le montant final inclura automatiquement :</p>
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
              <p className="font-bold text-foreground mb-3">💰 Estimation de rémunération (série)</p>
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
            netEstime={taux * (modeRecurrent ? (recurrenceValidation?.totalHebdo ?? 0) : dureeEstimee) * 1.21}
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
          {modeEdition ? '💾 Enregistrer les modifications' :
            modeRecurrent ? `📤 Publier ${creneaux.length} mission${creneaux.length > 1 ? 's' : ''}` : '📤 Publier la mission'}
        </button>

        {modeRecurrent && recurrenceBlocante && (
          <p className="text-xs text-destructive text-center font-medium">
            ⛔ Corrigez les violations légales ci-dessus avant de publier.
          </p>
        )}
      </form>

      {erreurCodeTravail && (
        <ModalCodeTravail erreur={erreurCodeTravail} onFermer={() => setErreurCodeTravail(null)} />
      )}

      {publicationEnCours && (
        <BarreProgressionBulk progression={progression} total={creneaux.length} actuel={progressionActuel} />
      )}
    </>
  );
}
