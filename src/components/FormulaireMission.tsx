import React, { useState, useEffect, useMemo } from 'react';
import { useNavigate, useSearchParams } from 'react-router-dom';
import { Loader2 } from 'lucide-react';
import { SelectProfession } from '@/components/SelectProfession';
import { WarningRist } from '@/components/WarningRist';
import { ModalCodeTravail } from '@/components/ModalCodeTravail';
import { useAuth } from '@/contexts/AuthContext';
import { useNotification } from '@/contexts/NotificationContext';
import { supabase } from '@/integrations/supabase/client';
import { extraireMessageErreur, estBlocageCodeTravail } from '@/lib/erreurs';

interface FormulaireMissionProps {
  missionSource?: any;
  modeEdition?: boolean;
}

export function FormulaireMission({ missionSource, modeEdition }: FormulaireMissionProps) {
  const navigate = useNavigate();
  const [searchParams] = useSearchParams();
  const { user } = useAuth();
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
  const [loading, setLoading] = useState(false);
  const [erreurCodeTravail, setErreurCodeTravail] = useState<any>(null);
  const [dupliquerInfo, setDupliquerInfo] = useState<string | null>(null);

  // Load duplication source
  useEffect(() => {
    const dupId = searchParams.get('dupliquer');
    if (dupId && !missionSource) {
      supabase.from('missions').select('*').eq('id', dupId).single().then(({ data }) => {
        if (data) {
          setIntitule(data.intitule);
          setDescription(data.description || '');
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
    }
  }, [missionSource]);

  const taux = parseFloat(tauxHoraire) || 0;

  const { dureeEstimee, heuresNuitEstimees } = useMemo(() => {
    if (!debutLe || !finLe) return { dureeEstimee: 0, heuresNuitEstimees: 0 };
    const d = new Date(debutLe);
    const f = new Date(finLe);
    const dur = Math.max(0, (f.getTime() - d.getTime()) / 3600000);
    // Rough night hours estimate
    let nuit = 0;
    const cursor = new Date(d);
    while (cursor < f) {
      const h = cursor.getHours();
      if (h >= 21 || h < 6) nuit += Math.min(1, (f.getTime() - cursor.getTime()) / 3600000);
      cursor.setTime(cursor.getTime() + 3600000);
    }
    return { dureeEstimee: dur, heuresNuitEstimees: Math.min(nuit, dur) };
  }, [debutLe, finLe]);

  const erreurDates = useMemo(() => {
    if (!debutLe || !finLe) return null;
    const d = new Date(debutLe);
    const f = new Date(finLe);
    if (f <= d) return 'La fin doit être après le début';
    if (!modeEdition && d < new Date()) return 'La mission ne peut pas commencer dans le passé';
    return null;
  }, [debutLe, finLe, modeEdition]);

  const warningDuree = dureeEstimee > 24;

  const handleSubmit = async (e: React.FormEvent) => {
    e.preventDefault();
    if (!user || erreurDates || !intitule || !profession || !debutLe || !finLe || !tauxHoraire) return;

    setLoading(true);
    try {
      const payload = {
        intitule,
        description: description || null,
        profession_requise: profession,
        service: service || null,
        debut_le: new Date(debutLe).toISOString(),
        fin_le: new Date(finLe).toISOString(),
        taux_horaire_base: parseFloat(tauxHoraire),
        est_urgente: estUrgente,
        niveau_urgence: estUrgente ? niveauUrgence : 0,
      };

      if (modeEdition && missionSource) {
        const { error } = await supabase
          .from('missions')
          .update({ ...payload, modifie_le: new Date().toISOString() } as any)
          .eq('id', missionSource.id)
          .eq('statut', 'OUVERTE');

        if (error) {
          if (estBlocageCodeTravail(error)) { setErreurCodeTravail(error); }
          else afficherNotification({ type: 'erreur', message: extraireMessageErreur(error) });
          return;
        }

        await supabase.rpc('fn_ecrire_audit', {
          p_acteur_id: user.id, p_type_acteur: 'ADMIN_ETABLISSEMENT', p_action: 'MISSION_MODIFICATION',
          p_type_ressource: 'mission', p_id_ressource: missionSource.id, p_cle_s3: null,
          p_details: { intitule, profession, taux: tauxHoraire, debut: debutLe, fin: finLe } as any,
          p_ip: null, p_navigateur: navigator.userAgent,
        });

        afficherNotification({ type: 'succes', message: 'Mission mise à jour !' });
        navigate(`/etablissement/missions/${missionSource.id}`);
      } else {
        const { data, error } = await supabase
          .from('missions')
          .insert({ ...payload, etablissement_id: user.id } as any)
          .select()
          .single();

        if (error) {
          if (estBlocageCodeTravail(error)) { setErreurCodeTravail(error); }
          else afficherNotification({ type: 'erreur', message: extraireMessageErreur(error) });
          return;
        }

        await supabase.rpc('fn_ecrire_audit', {
          p_acteur_id: user.id, p_type_acteur: 'ADMIN_ETABLISSEMENT', p_action: 'MISSION_CREATION',
          p_type_ressource: 'mission', p_id_ressource: data.id, p_cle_s3: null,
          p_details: { intitule, profession, taux: tauxHoraire, debut: debutLe, fin: finLe } as any,
          p_ip: null, p_navigateur: navigator.userAgent,
        });

        afficherNotification({ type: 'succes', message: 'Mission publiée avec succès !' });
        navigate('/etablissement/missions');
      }
    } finally {
      setLoading(false);
    }
  };

  return (
    <>
      {dupliquerInfo && (
        <div className="bg-info/10 border border-info/20 rounded-xl p-3 mb-4 text-sm text-info">
          📋 Vous dupliquez la mission « {dupliquerInfo} ». Ajustez les dates ci-dessous.
        </div>
      )}

      <form onSubmit={handleSubmit} className="space-y-5">
        {/* Intitulé */}
        <div>
          <label className="text-sm font-medium text-foreground mb-1 block">Intitulé *</label>
          <input
            value={intitule} onChange={(e) => setIntitule(e.target.value.slice(0, 120))}
            placeholder="Ex: IDE de nuit — Service Urgences"
            required className="input-base"
          />
          <p className="text-[10px] text-muted-foreground mt-1 text-right">{intitule.length}/120</p>
        </div>

        {/* Description */}
        <div>
          <label className="text-sm font-medium text-foreground mb-1 block">Description</label>
          <textarea
            value={description} onChange={(e) => setDescription(e.target.value)}
            placeholder="Informations complémentaires pour le soignant..."
            rows={3} className="input-base resize-none"
          />
        </div>

        {/* Profession */}
        <div>
          <label className="text-sm font-medium text-foreground mb-1 block">Profession requise *</label>
          <SelectProfession value={profession} onChange={setProfession} />
        </div>

        {/* Service */}
        <div>
          <label className="text-sm font-medium text-foreground mb-1 block">Service</label>
          <input
            value={service} onChange={(e) => setService(e.target.value)}
            placeholder="Ex: Urgences, Gériatrie, Réa, Bloc, EHPAD"
            className="input-base"
          />
        </div>

        {/* Bloc horaire */}
        <div className="border border-primary/20 rounded-xl p-4 bg-primary/5 space-y-3">
          <p className="text-sm font-semibold text-foreground">📅 Horaires de la mission</p>
          <div className="grid grid-cols-1 md:grid-cols-2 gap-3">
            <div>
              <label className="text-xs text-muted-foreground mb-1 block">Date et heure de début *</label>
              <input type="datetime-local" value={debutLe} onChange={(e) => setDebutLe(e.target.value)} required className="input-base" />
            </div>
            <div>
              <label className="text-xs text-muted-foreground mb-1 block">Date et heure de fin *</label>
              <input type="datetime-local" value={finLe} onChange={(e) => setFinLe(e.target.value)} required className="input-base" />
            </div>
          </div>
          {erreurDates && <p className="text-xs text-destructive font-medium">{erreurDates}</p>}
          {warningDuree && <p className="text-xs text-warning font-medium">⚠️ Attention : mission de plus de 24h</p>}
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

        {/* Taux horaire */}
        <div>
          <label className="text-sm font-medium text-foreground mb-1 block">Taux horaire brut * (€/h)</label>
          <div className="relative">
            <input
              type="number" step="0.01" min="11.65" value={tauxHoraire}
              onChange={(e) => setTauxHoraire(e.target.value)}
              placeholder="25.00" required className="input-base pr-12"
            />
            <span className="absolute right-3 top-1/2 -translate-y-1/2 text-sm text-muted-foreground">€/h</span>
          </div>
        </div>

        {/* Warning Rist */}
        {profession && taux > 0 && <WarningRist profession={profession} tauxSaisi={taux} />}

        {/* Urgence */}
        <div className="flex items-center justify-between">
          <label className="text-sm font-medium text-foreground">Mission urgente ?</label>
          <button
            type="button"
            onClick={() => setEstUrgente(!estUrgente)}
            className={`relative w-12 h-6 rounded-full transition-colors ${estUrgente ? 'bg-primary' : 'bg-muted'}`}
          >
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

        {/* Estimation */}
        {dureeEstimee > 0 && taux > 0 && (
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

        <p className="text-[10px] text-muted-foreground italic text-center">
          Simulation à titre indicatif. Seuls les montants calculés par le moteur de paie font foi.
          Les majorations (nuit, dimanche, jours fériés), l'IFM et l'ICP sont calculés automatiquement
          par le système après la création de la mission.
        </p>

        {/* Submit */}
        <button
          type="submit"
          disabled={loading || !!erreurDates || !intitule || !profession || !debutLe || !finLe || !tauxHoraire}
          className="btn-primary w-full flex items-center justify-center gap-2 disabled:opacity-50"
        >
          {loading && <Loader2 className="h-4 w-4 animate-spin" />}
          {modeEdition ? '💾 Enregistrer les modifications' : '📤 Publier la mission'}
        </button>
      </form>

      {erreurCodeTravail && (
        <ModalCodeTravail erreur={erreurCodeTravail} onFermer={() => setErreurCodeTravail(null)} />
      )}
    </>
  );
}
