import { useState, useEffect } from 'react';
import { Trophy } from 'lucide-react';
import { supabase } from '@/integrations/supabase/client';
import { JaugeProgression } from './JaugeProgression';

interface WidgetBFAProps {
  etablissementId: string;
  groupeId?: string | null;
}

function fmt(v: number): string {
  return new Intl.NumberFormat('fr-FR', { style: 'currency', currency: 'EUR' }).format(v);
}

export function WidgetBFA({ etablissementId, groupeId }: WidgetBFAProps) {
  const [bfa, setBfa] = useState<any>(null);
  const [loading, setLoading] = useState(true);

  useEffect(() => {
    const load = async () => {
      const params: any = {};
      if (groupeId) {
        params.p_groupe_id = groupeId;
      } else {
        params.p_etablissement_id = etablissementId;
      }

      const { data, error } = await supabase.rpc('fn_calculer_bfa_safe', params);
      if (!error && data) setBfa(data);
      setLoading(false);
    };
    load();
  }, [etablissementId, groupeId]);

  if (loading || !bfa) return null;

  const paliers = [
    { nom: 'Bronze', min: 100, max: 300, taux: 2 },
    { nom: 'Argent', min: 301, max: 600, taux: 3.5 },
    { nom: 'Or', min: 601, max: null, taux: 5 },
  ];

  const palierActuel = paliers.find(p => bfa.missions >= p.min && (p.max === null || bfa.missions <= p.max));
  const palierSuivant = paliers.find(p => bfa.missions < p.min);
  const missionsRestantes = palierSuivant ? palierSuivant.min - bfa.missions : 0;
  const economieSuivante = palierSuivant ? bfa.commissions_ht * ((palierSuivant.taux - (palierActuel?.taux || 0)) / 100) : 0;

  const annee = new Date().getFullYear();

  return (
    <div className="rounded-2xl bg-gradient-to-r from-amber-50 to-yellow-50 border border-amber-200 p-5 mb-6">
      <div className="flex items-center gap-2 mb-3">
        <Trophy className="h-5 w-5 text-amber-600" />
        <h3 className="text-base font-bold text-foreground">Bonus de Fin d'Année {annee}</h3>
      </div>

      <p className="text-sm text-muted-foreground mb-4">
        Missions cette année : <span className="font-semibold text-foreground">{bfa.missions}</span>
        {palierSuivant && <> / {palierSuivant.min} pour le palier {palierSuivant.nom}</>}
      </p>

      {/* Paliers */}
      <div className="flex items-center gap-1 mb-3 text-xs">
        {paliers.map((p, i) => (
          <div key={p.nom} className={`flex-1 text-center py-1.5 rounded-lg ${palierActuel?.nom === p.nom ? 'bg-amber-200 font-bold text-amber-800' : 'bg-amber-100/50 text-muted-foreground'}`}>
            <span>{p.nom}</span>
            <span className="block text-[10px]">({p.min}{p.max ? `-${p.max}` : '+'}) {p.taux}%</span>
          </div>
        ))}
      </div>

      {palierSuivant && (
        <JaugeProgression
          valeur={bfa.missions}
          max={palierSuivant.min}
          couleurBarre="bg-gradient-to-r from-amber-400 to-yellow-500"
          couleurFond="bg-amber-100"
        />
      )}

      <div className="mt-3 space-y-1">
        <p className="text-sm text-muted-foreground">
          Commissions HT cumulées : <span className="font-semibold text-foreground">{fmt(bfa.commissions_ht)}</span>
        </p>
        <p className="text-sm text-muted-foreground">
          BFA actuel ({bfa.palier} {bfa.taux_bfa}%) : <span className="font-bold text-amber-700">{fmt(bfa.montant_bfa)} de crédit</span>
        </p>
      </div>

      {palierSuivant && missionsRestantes > 0 && (
        <div className="mt-3 bg-amber-100/50 rounded-xl p-3">
          <p className="text-xs text-amber-800">
            💡 Encore <span className="font-bold">{missionsRestantes} mission{missionsRestantes > 1 ? 's' : ''}</span> pour le palier {palierSuivant.nom} ({palierSuivant.taux}%) !
            {economieSuivante > 0 && <> Économie supplémentaire : <span className="font-bold">+{fmt(economieSuivante)}</span></>}
          </p>
        </div>
      )}

      <p className="text-[10px] text-muted-foreground/60 italic mt-3">
        Simulation indicative. Le BFA est calculé en fin d'année civile.
      </p>
    </div>
  );
}
