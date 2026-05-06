import React, { useEffect, useState } from 'react';
import { BarChart, Bar, XAxis, YAxis, Tooltip, Legend, ResponsiveContainer, CartesianGrid } from 'recharts';
import { TrendingUp } from 'lucide-react';
import { supabase } from '@/integrations/supabase/client';
import { format } from 'date-fns';
import { fr } from 'date-fns/locale';

interface PointMois {
  mois: string;
  publiees: number;
  assignees: number;
  terminees: number;
}

export function GraphiqueEvolutionMissions() {
  const [data, setData] = useState<PointMois[]>([]);
  const [loading, setLoading] = useState(true);

  useEffect(() => {
    let alive = true;
    (async () => {
      const { data: payload } = await supabase.rpc('fn_evolution_missions_etab' as any);
      if (!alive) return;
      if (Array.isArray(payload)) {
        setData(payload as PointMois[]);
      }
      setLoading(false);
    })();
    return () => { alive = false; };
  }, []);

  const chart = data.map((p) => ({
    ...p,
    label: (() => {
      const [y, m] = p.mois.split('-');
      return format(new Date(parseInt(y, 10), parseInt(m, 10) - 1, 1), 'MMM', { locale: fr });
    })(),
  }));

  const aData = chart.some((p) => p.publiees > 0 || p.assignees > 0 || p.terminees > 0);

  return (
    <div className="card-base mb-6">
      <h2 className="text-base font-bold text-foreground inline-flex items-center gap-2 mb-3">
        <TrendingUp className="h-4 w-4 text-primary" /> Évolution missions (6 mois)
      </h2>

      {loading ? (
        <div className="h-56 animate-pulse bg-muted rounded-lg" />
      ) : !aData ? (
        <div className="text-center py-10">
          <p className="text-sm text-muted-foreground">Pas encore assez de données pour afficher l'évolution.</p>
        </div>
      ) : (
        <div className="h-56">
          <ResponsiveContainer width="100%" height="100%">
            <BarChart data={chart} margin={{ top: 8, right: 8, left: 0, bottom: 8 }}>
              <CartesianGrid strokeDasharray="3 3" stroke="hsl(var(--border))" />
              <XAxis dataKey="label" tick={{ fontSize: 11 }} />
              <YAxis allowDecimals={false} tick={{ fontSize: 11 }} width={28} />
              <Tooltip wrapperStyle={{ fontSize: '12px' }} />
              <Legend wrapperStyle={{ fontSize: '12px' }} />
              <Bar dataKey="publiees" name="Publiées" fill="#94a3b8" radius={[4, 4, 0, 0]} />
              <Bar dataKey="assignees" name="Assignées" fill="#6366f1" radius={[4, 4, 0, 0]} />
              <Bar dataKey="terminees" name="Terminées" fill="#10b981" radius={[4, 4, 0, 0]} />
            </BarChart>
          </ResponsiveContainer>
        </div>
      )}
    </div>
  );
}
