import { useState, useEffect } from 'react';
import { Trophy, Check } from 'lucide-react';
import { supabase } from '@/integrations/supabase/client';

interface PalierBFA {
  nom: string;
  missions_min: number;
  missions_max: number | null;
  taux: number;
  atteint: boolean;
  est_actuel: boolean;
}

interface BFAInfo {
  palier_actuel: string;
  taux_bfa: number;
  montant_estime: number;
  missions_annee: number;
  commissions_ht: number;
  prochain_palier_nom: string | null;
  prochain_palier_missions_min: number | null;
  missions_restantes: number | null;
  paliers: PalierBFA[];
  explication: string;
}

function fmt(v: number): string {
  return new Intl.NumberFormat('fr-FR', { style: 'currency', currency: 'EUR' }).format(v);
}

export function CarteBFAInfo({ etablissementId }: { etablissementId: string }) {
  const [info, setInfo] = useState<BFAInfo | null>(null);
  const [loading, setLoading] = useState(true);

  useEffect(() => {
    const load = async () => {
      const { data, error } = await supabase.rpc('fn_bfa_info' as any);
      if (!error && data) {
        const d = data as any;
        // Hide BFA if not yet eligible (0 missions and no active tier)
        if (d.missions_annee > 0 || (d.palier_actuel && d.palier_actuel !== 'Pas encore éligible')) {
          setInfo(d);
        }
      }
      setLoading(false);
    };
    load();
  }, [etablissementId]);

  if (loading || !info) return null;

  // Guard against NaN values
  const montant = isNaN(info.montant_estime) ? 0 : info.montant_estime;
  const commissions = isNaN(info.commissions_ht) ? 0 : info.commissions_ht;
  const progressMax = info.prochain_palier_missions_min ?? info.missions_annee;
  const progressPct = progressMax > 0 ? Math.min(Math.round((info.missions_annee / progressMax) * 100), 100) : 100;

  const palierColors: Record<string, string> = {
    Bronze: 'bg-amber-600',
    Argent: 'bg-slate-400',
    Or: 'bg-yellow-500',
  };

  return (
    <div className="rounded-2xl border border-border bg-card p-5 mb-6">
      <div className="flex items-center gap-2 mb-4">
        <div className="rounded-xl p-2 bg-amber-500/10">
          <Trophy className="h-5 w-5 text-amber-600" />
        </div>
        <h3 className="font-bold text-foreground">Bonus Fidélité Annuel</h3>
      </div>

      {/* Palier actuel + montant */}
      <div className="flex items-baseline gap-3 mb-1">
        <span className={`inline-flex items-center gap-1.5 px-3 py-1 rounded-full text-sm font-bold text-white ${palierColors[info.palier_actuel] || 'bg-muted-foreground'}`}>
          <Trophy className="h-3.5 w-3.5" />
          {info.palier_actuel}
        </span>
        <span className="text-2xl font-extrabold text-foreground">{fmt(montant)}</span>
      </div>

      <p className="text-sm text-muted-foreground mb-4">
        {info.missions_annee} mission{info.missions_annee > 1 ? 's' : ''} cette année · {fmt(commissions)} de commissions HT
      </p>

      {/* Barre de progression */}
      {info.prochain_palier_nom && info.missions_restantes != null && info.missions_restantes > 0 && (
        <div className="mb-4">
          <div className="flex justify-between text-xs text-muted-foreground mb-1.5">
            <span>{info.missions_annee} / {info.prochain_palier_missions_min}</span>
            <span className="font-medium">Palier {info.prochain_palier_nom}</span>
          </div>
          <div className="relative h-2.5 rounded-full bg-muted overflow-hidden">
            <div
              className="absolute inset-y-0 left-0 rounded-full bg-amber-500 transition-all duration-700 ease-out"
              style={{ width: `${progressPct}%` }}
            />
          </div>
          <p className="text-xs text-muted-foreground mt-1.5">
            Encore <span className="font-bold text-amber-600">{info.missions_restantes}</span> mission{info.missions_restantes > 1 ? 's' : ''} manquante{info.missions_restantes > 1 ? 's' : ''}
          </p>
        </div>
      )}

      {/* Liste des paliers */}
      {info.paliers && info.paliers.length > 0 && (
        <div className="space-y-1.5 mb-4">
          {info.paliers.map((p) => (
            <div
              key={p.nom}
              className={`flex items-center gap-3 px-3 py-2 rounded-lg text-sm transition-all ${
                p.est_actuel
                  ? 'bg-primary/10 border border-primary/20 font-semibold text-foreground'
                  : p.atteint
                  ? 'bg-muted/50 text-foreground'
                  : 'text-muted-foreground'
              }`}
            >
              <div className={`h-5 w-5 rounded-full flex items-center justify-center shrink-0 ${
                p.atteint || p.est_actuel ? 'bg-primary text-primary-foreground' : 'border-2 border-border'
              }`}>
                {(p.atteint || p.est_actuel) && <Check className="h-3 w-3" />}
              </div>
              <span className="flex-1">{p.nom}</span>
              <span className="text-xs opacity-70">
                {p.missions_max ? `${p.missions_min}-${p.missions_max}` : `${p.missions_min}+`} missions
              </span>
              <span className="font-medium">{p.taux}%</span>
            </div>
          ))}
        </div>
      )}

      {!info.prochain_palier_nom && (
        <p className="text-xs text-success font-medium mb-3">🎉 Palier maximum atteint !</p>
      )}

      {/* Explication dynamique */}
      <p className="text-[10px] text-muted-foreground italic">
        {info.explication || 'Calculé en fin d\'année civile sur la base de vos commissions cumulées.'}
      </p>
    </div>
  );
}
