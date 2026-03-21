import React, { useState } from 'react';
import { Switch } from '@/components/ui/switch';
import { Slider } from '@/components/ui/slider';
import { Flame, Shield, Star, Eye } from 'lucide-react';
import { supabase } from '@/integrations/supabase/client';
import { extraireMessageErreur } from '@/lib/erreurs';

interface PoolUrgenceToggleProps {
  actif: boolean;
  rayonKm: number;
  villeUrgence?: string;
  onUpdate: (actif: boolean, rayonKm: number, villeUrgence?: string) => void;
  onError: (msg: string) => void;
  onSuccess: (msg: string) => void;
}

export function PoolUrgenceToggle({ actif, rayonKm, villeUrgence, onUpdate, onError, onSuccess }: PoolUrgenceToggleProps) {
  const [loading, setLoading] = useState(false);
  const [localActif, setLocalActif] = useState(actif);
  const [localRayon, setLocalRayon] = useState(rayonKm);
  const [modeZone, setModeZone] = useState<'position' | 'ville'>(villeUrgence ? 'ville' : 'position');
  const [localVille, setLocalVille] = useState(villeUrgence || '');

  const save = async (newActif: boolean, newRayon: number) => {
    setLoading(true);
    const { data, error } = await supabase.rpc('fn_toggle_pool_urgence' as any, {
      p_actif: newActif,
      p_rayon_km: newRayon,
      p_creneaux: [],
    });
    if (error) {
      onError(extraireMessageErreur(error));
    } else if (data?.error) {
      onError(data.error);
    } else {
      onUpdate(newActif, newRayon, modeZone === 'ville' ? localVille : undefined);
      onSuccess(newActif ? 'Pool urgence activé !' : 'Pool urgence désactivé.');
    }
    setLoading(false);
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
            Vous serez alerté en priorité quand un soignant annule une mission dans votre rayon.
          </p>
        </div>
        <Switch
          checked={localActif}
          disabled={loading}
          onCheckedChange={(checked) => {
            setLocalActif(checked);
            save(checked, localRayon);
          }}
        />
      </div>

      {localActif && (
        <>
          <div className="mb-4">
            <label className="text-sm font-medium text-foreground mb-2 block">
              Rayon maximum : <span className="text-primary font-bold">{localRayon} km</span>
            </label>
            <Slider
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

          <div className="bg-primary/5 border border-primary/20 rounded-xl p-3 mb-3">
            <div className="flex items-center gap-2 mb-2">
              <span className="badge-base bg-destructive/10 text-destructive text-[10px] font-bold">
                Soignant Urgence 🔥
              </span>
              <span className="text-xs text-muted-foreground">Badge visible sur votre profil</span>
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
              En activant le pool d'urgence, vous acceptez d'être contacté pour des remplacements de dernière minute dans votre rayon.
              Vous restez libre de refuser. Chaque mission urgence terminée vous rapporte <strong className="text-foreground">+10 points de fiabilité</strong>.
            </p>
          </div>
        </>
      )}
    </div>
  );
}
