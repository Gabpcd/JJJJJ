import { useState, useEffect } from 'react';
import { Tag, Sparkles } from 'lucide-react';
import { supabase } from '@/integrations/supabase/client';

interface Palier {
  nom: string;
  taux_commission: number;
  missions_min: number;
  missions_max: number | null;
  est_actuel: boolean;
}

interface CommissionInfo {
  taux_actuel: number;
  palier_nom: string;
  missions_ce_mois: number;
  prochain_palier_nom: string | null;
  prochain_palier_taux: number | null;
  prochain_palier_missions_min: number | null;
  missions_restantes: number | null;
  paliers: Palier[];
}

export function CarteCommissionJolene({ etablissementId }: { etablissementId: string }) {
  const [info, setInfo] = useState<CommissionInfo | null>(null);
  const [loading, setLoading] = useState(true);

  useEffect(() => {
    const load = async () => {
      const { data, error } = await supabase.rpc('fn_commission_info_etablissement' as any);
      if (!error && data) setInfo(data as any);
      setLoading(false);
    };
    load();
  }, [etablissementId]);

  if (loading || !info) return null;

  const progressMax = info.prochain_palier_missions_min ?? info.missions_ce_mois;
  const progressPct = progressMax > 0 ? Math.min(Math.round((info.missions_ce_mois / progressMax) * 100), 100) : 100;

  return (
    <div className="rounded-2xl border border-border bg-card p-5 mb-6">
      <div className="flex items-center gap-2 mb-4">
        <div className="rounded-xl p-2 bg-primary/10">
          <Tag className="h-5 w-5 text-primary" />
        </div>
        <h3 className="font-bold text-foreground">Ta commission Jolene</h3>
      </div>

      {/* Taux actuel en gros */}
      <div className="flex items-baseline gap-3 mb-1">
        <span className="text-4xl font-extrabold text-primary">{info.taux_actuel}%</span>
        <span className="text-sm font-semibold text-muted-foreground">Palier {info.palier_nom}</span>
      </div>

      <p className="text-sm text-muted-foreground mb-4">
        {info.missions_ce_mois} mission{info.missions_ce_mois > 1 ? 's' : ''} terminée{info.missions_ce_mois > 1 ? 's' : ''} ce mois
      </p>

      {/* Barre de progression vers prochain palier */}
      {info.prochain_palier_nom && info.missions_restantes != null && info.missions_restantes > 0 && (
        <div className="mb-4">
          <div className="flex justify-between text-xs text-muted-foreground mb-1.5">
            <span>{info.missions_ce_mois} / {info.prochain_palier_missions_min}</span>
            <span className="font-medium">Palier {info.prochain_palier_nom} ({info.prochain_palier_taux}%)</span>
          </div>
          <div className="relative h-2.5 rounded-full bg-muted overflow-hidden">
            <div
              className="absolute inset-y-0 left-0 rounded-full bg-primary transition-all duration-700 ease-out"
              style={{ width: `${progressPct}%` }}
            />
          </div>
          <div className="flex items-center gap-1.5 mt-2">
            <Sparkles className="h-3.5 w-3.5 text-primary" />
            <p className="text-xs text-muted-foreground">
              Encore <span className="font-bold text-primary">{info.missions_restantes}</span> mission{info.missions_restantes > 1 ? 's' : ''} pour le palier suivant
            </p>
          </div>
        </div>
      )}

      {/* Liste des paliers */}
      {info.paliers && info.paliers.length > 0 && (
        <div className="flex gap-1 mb-4">
          {info.paliers.map((p) => (
            <div
              key={p.nom}
              className={`flex-1 text-center py-2 rounded-lg text-xs transition-all ${
                p.est_actuel
                  ? 'bg-primary text-primary-foreground font-bold shadow-sm'
                  : 'bg-muted text-muted-foreground'
              }`}
            >
              <span className="block font-medium">{p.nom}</span>
              <span className="block text-[10px] opacity-80">{p.taux_commission}%</span>
              <span className="block text-[9px] opacity-60">
                {p.missions_max ? `${p.missions_min}-${p.missions_max}` : `${p.missions_min}+`}
              </span>
            </div>
          ))}
        </div>
      )}

      {!info.prochain_palier_nom && (
        <p className="text-xs text-success font-medium mb-3">🎉 Tu bénéficies du meilleur taux !</p>
      )}

      <p className="text-[10px] text-muted-foreground italic">
        Recalculée chaque 1er du mois selon ton volume.
      </p>
    </div>
  );
}
