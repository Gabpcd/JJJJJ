import React, { useState, useEffect } from 'react';
import { Switch } from '@/components/ui/switch';
import { Slider } from '@/components/ui/slider';
import { Flame, Shield, Star, Eye, MessageSquare } from 'lucide-react';
import { supabase } from '@/integrations/supabase/client';
import { useAuth } from '@/contexts/AuthContext';
import { extraireMessageErreur } from '@/lib/erreurs';
import { toast } from 'sonner';
import type { RpcSuccessOrError } from '@/lib/supabase-rpc-types';

interface PoolUrgenceToggleProps {
  actif?: boolean;
  rayonKm?: number;
  villeUrgence?: string;
  smsOptIn?: boolean;
  onUpdate?: (actif: boolean, rayonKm: number, villeUrgence?: string) => void;
  onError?: (msg: string) => void;
  onSuccess?: (msg: string) => void;
}

export function PoolUrgenceToggle({ actif, rayonKm, villeUrgence, smsOptIn, onUpdate, onError, onSuccess }: PoolUrgenceToggleProps) {
  const { user } = useAuth();
  const [loading, setLoading] = useState(false);
  const [localActif, setLocalActif] = useState(actif ?? false);
  const [localRayon, setLocalRayon] = useState(rayonKm ?? 15);
  const [localSms, setLocalSms] = useState(smsOptIn ?? false);
  const [smsLoading, setSmsLoading] = useState(false);
  const [modeZone, setModeZone] = useState<'position' | 'ville'>(villeUrgence ? 'ville' : 'position');
  const [localVille, setLocalVille] = useState(villeUrgence || '');

  // Ces props arrivent souvent après le premier rendu (notamment depuis la RPC
  // du pool). Elles restent la projection contrôlée de la ligne soignants : le
  // composant doit donc abandonner ses valeurs initiales dès que le serveur
  // fournit l'état canonique.
  useEffect(() => {
    if (actif !== undefined) setLocalActif(actif);
    if (rayonKm !== undefined) setLocalRayon(rayonKm);
    if (smsOptIn !== undefined) setLocalSms(smsOptIn);
  }, [actif, rayonKm, smsOptIn]);

  useEffect(() => {
    if (villeUrgence === undefined) return;
    setLocalVille(villeUrgence);
    setModeZone(villeUrgence ? 'ville' : 'position');
  }, [villeUrgence]);

  useEffect(() => {
    if (actif !== undefined) return;
    if (!user) return;
    supabase.from('soignants').select('disponible_urgence, urgence_rayon_km, pool_urgence_sms_opt_in').eq('id', user.id).maybeSingle()
      .then(({ data }: any) => {
        if (data) {
          setLocalActif(data.disponible_urgence ?? false);
          setLocalRayon(data.urgence_rayon_km ?? 15);
          setLocalSms(data.pool_urgence_sms_opt_in ?? false);
        }
      });
  }, [user, actif]);

  // revertActif : valeur à rétablir sur le switch si le save échoue (sinon le
  // toggle resterait visuellement activé alors que l'activation a été refusée,
  // ex. garde documents/RCP côté serveur).
  const save = async (newActif: boolean, newRayon: number, revertActif?: boolean) => {
    setLoading(true);
    const { data, error } = await supabase.rpc('fn_toggle_pool_urgence' as any, {
      p_actif: newActif,
      p_rayon_km: newRayon,
      p_creneaux: [],
    });
    const result = data as unknown as RpcSuccessOrError | null;
    if (error) {
      if (revertActif !== undefined) setLocalActif(revertActif);
      (onError ?? ((m: string) => toast.error(m)))(extraireMessageErreur(error));
    } else if (result?.error) {
      if (revertActif !== undefined) setLocalActif(revertActif);
      (onError ?? ((m: string) => toast.error(m)))(result.error);
    } else {
      onUpdate?.(newActif, newRayon, modeZone === 'ville' ? localVille : undefined);
      (onSuccess ?? ((m: string) => toast.success(m)))(newActif ? 'Pool urgence activé !' : 'Pool urgence désactivé.');
    }
    setLoading(false);
  };

  const saveSms = async (newSms: boolean) => {
    setSmsLoading(true);
    const { data, error } = await supabase.rpc('fn_toggle_pool_urgence_sms' as any, { p_actif: newSms });
    const result = data as unknown as RpcSuccessOrError | null;
    if (error) {
      toast.error(extraireMessageErreur(error));
      setLocalSms(!newSms);
    } else if (result?.error) {
      toast.error(result.error);
      setLocalSms(!newSms);
    } else {
      toast.success(newSms ? 'SMS d\'urgence activés' : 'SMS d\'urgence désactivés');
    }
    setSmsLoading(false);
  };

  return (
    <div className="card-base">
      <h2 className="text-base font-semibold text-foreground mb-4 flex items-center gap-2">
        <Flame className="h-5 w-5 text-destructive" />
        Disponibilité urgence
      </h2>

      <div className="flex items-center justify-between mb-4">
        <div className="flex-1">
          <p className="text-sm text-foreground font-medium">🚨 Disponible pour les remplacements d'urgence</p>
          <p className="text-xs text-muted-foreground mt-1">
            Tu seras alerté(e) en priorité quand un soignant annule une mission dans ton rayon.
          </p>
        </div>
        <Switch
          aria-label="Disponible pour les remplacements d’urgence"
          checked={localActif}
          disabled={loading}
          onCheckedChange={(checked) => {
            setLocalActif(checked);
            save(checked, localRayon, !checked);
          }}
        />
      </div>

      {localActif && (
        <>
          {/* Zone choice */}
          <div className="mb-4">
            <p className="text-xs font-medium text-foreground mb-2">Zone d'alerte :</p>
            <div className="flex gap-2">
              <button
                type="button"
                onClick={() => setModeZone('position')}
                className={`px-3 py-1.5 rounded-lg text-xs font-medium border transition-colors ${modeZone === 'position' ? 'border-primary bg-primary/10 text-primary' : 'border-border text-muted-foreground'}`}
              >
                📍 Autour de ma position
              </button>
              <button
                type="button"
                onClick={() => setModeZone('ville')}
                className={`px-3 py-1.5 rounded-lg text-xs font-medium border transition-colors ${modeZone === 'ville' ? 'border-primary bg-primary/10 text-primary' : 'border-border text-muted-foreground'}`}
              >
                🏙️ Ville spécifique
              </button>
            </div>
            {modeZone === 'ville' && (
              <input
                aria-label="Ville des alertes d’urgence"
                value={localVille}
                onChange={(e) => setLocalVille(e.target.value)}
                placeholder="Ex : Lyon, Marseille..."
                className="input-base mt-2"
              />
            )}
          </div>

          <div className="mb-4">
            <label className="text-sm font-medium text-foreground mb-2 block">
              Rayon maximum : <span className="text-primary font-bold">{localRayon} km</span>
            </label>
            <Slider
              aria-label="Rayon maximum des alertes d’urgence"
              value={[localRayon]}
              min={5}
              max={50}
              step={1}
              onValueCommit={(val) => {
                const v = val[0];
                setLocalRayon(v);
                save(true, v);
              }}
              onValueChange={(val) => setLocalRayon(val[0])}
            />
            <div className="flex justify-between text-[10px] text-muted-foreground mt-1">
              <span>5 km</span><span>50 km</span>
            </div>
          </div>

          {/* Toggle SMS opt-in */}
          <div className="border border-border rounded-xl p-3 mb-3 bg-orange-50/50 dark:bg-orange-950/10">
            <div className="flex items-center justify-between gap-3">
              <div className="flex-1">
                <p className="text-sm font-medium text-foreground inline-flex items-center gap-1.5">
                  <MessageSquare className="h-4 w-4 text-orange-600" /> Recevoir les alertes par SMS
                </p>
                <p className="text-xs text-muted-foreground mt-1">
                  Notification immédiate par SMS, en plus des push et e-mails, pour ne manquer aucune mission de dernière minute.
                </p>
              </div>
              <Switch
                aria-label="Recevoir les alertes d’urgence par SMS"
                checked={localSms}
                disabled={smsLoading}
                onCheckedChange={(checked) => {
                  setLocalSms(checked);
                  saveSms(checked);
                }}
              />
            </div>
          </div>

          <div className="bg-primary/5 border border-primary/20 rounded-xl p-3 mb-3">
            <div className="flex items-center gap-2 mb-2">
              <span className="badge-base bg-destructive/10 text-destructive text-[10px] font-bold">
                Soignant Urgence 🔥
              </span>
              <span className="text-xs text-muted-foreground">Badge visible sur ton profil</span>
            </div>
          </div>

          <div className="space-y-2">
            <p className="text-xs font-semibold text-foreground">Avantages :</p>
            <div className="flex items-center gap-2 text-xs text-muted-foreground">
              <Star className="h-3.5 w-3.5 text-warning shrink-0" />
              +10 points fiabilité par mission urgence terminée
            </div>
            <div className="flex items-center gap-2 text-xs text-muted-foreground">
              <Shield className="h-3.5 w-3.5 text-primary shrink-0" />
              Accès prioritaire aux missions urgentes
            </div>
            <div className="flex items-center gap-2 text-xs text-muted-foreground">
              <Eye className="h-3.5 w-3.5 text-success shrink-0" />
              Badge Urgence visible par les établissements
            </div>
          </div>

          <div className="mt-4 bg-muted/50 border border-border rounded-xl p-3">
            <p className="text-xs text-muted-foreground">
              En activant le pool d'urgence, tu acceptes d'être contacté(e) pour des remplacements de dernière minute dans ton rayon.
              Tu restes libre de refuser. Chaque mission urgence terminée te rapporte <strong className="text-foreground">+10 points de fiabilité</strong>.
            </p>
          </div>
        </>
      )}
    </div>
  );
}
