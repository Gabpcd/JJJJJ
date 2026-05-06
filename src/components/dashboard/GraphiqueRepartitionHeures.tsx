import React, { useEffect, useState } from 'react';
import { PieChart, Pie, Cell, ResponsiveContainer, Tooltip, Legend } from 'recharts';
import { PieChart as PieIcon } from 'lucide-react';
import { supabase } from '@/integrations/supabase/client';

interface Repartition {
  total_heures: number;
  periode_jours: number;
  jour: number;
  nuit: number;
  dimanche: number;
  ferie: number;
}

const COLORS = {
  jour: '#fbbf24',
  nuit: '#6366f1',
  dimanche: '#ec4899',
  ferie: '#10b981',
};

const PERIODES = [
  { value: 30, label: '30 derniers jours' },
  { value: -1, label: 'Mois en cours' },
  { value: 180, label: '6 derniers mois' },
];

function debutMoisJours(): number {
  const d = new Date();
  return Math.max(d.getDate(), 1);
}

export function GraphiqueRepartitionHeures() {
  const [periode, setPeriode] = useState<number>(30);
  const [data, setData] = useState<Repartition | null>(null);
  const [loading, setLoading] = useState(true);

  useEffect(() => {
    let alive = true;
    (async () => {
      setLoading(true);
      const jours = periode === -1 ? debutMoisJours() : periode;
      const { data: payload } = await supabase.rpc('fn_repartition_heures_soignant' as any, { p_periode_jours: jours });
      if (!alive) return;
      setData(payload as Repartition | null);
      setLoading(false);
    })();
    return () => { alive = false; };
  }, [periode]);

  const chart = data ? [
    { name: 'Jour', value: Number(data.jour), color: COLORS.jour },
    { name: 'Nuit', value: Number(data.nuit), color: COLORS.nuit },
    { name: 'Dimanche', value: Number(data.dimanche), color: COLORS.dimanche },
    { name: 'Férié', value: Number(data.ferie), color: COLORS.ferie },
  ].filter(d => d.value > 0) : [];

  const total = data ? Number(data.total_heures) : 0;
  const hasData = chart.length > 0 && total > 0;

  return (
    <div className="card-base mb-6">
      <div className="flex items-center justify-between mb-3 flex-wrap gap-2">
        <h2 className="text-base font-bold text-foreground inline-flex items-center gap-2">
          <PieIcon className="h-4 w-4 text-primary" /> Répartition de mes heures
        </h2>
        <select
          value={periode}
          onChange={(e) => setPeriode(parseInt(e.target.value, 10))}
          className="text-xs px-2 py-1.5 rounded-lg border border-border bg-background"
        >
          {PERIODES.map((p) => (
            <option key={p.value} value={p.value}>{p.label}</option>
          ))}
        </select>
      </div>

      {loading ? (
        <div className="h-48 animate-pulse bg-muted rounded-lg" />
      ) : !hasData ? (
        <div className="text-center py-10">
          <p className="text-sm text-muted-foreground">Pas encore de missions terminées sur cette période.</p>
        </div>
      ) : (
        <>
          <p className="text-xs text-muted-foreground mb-3">
            Total : <strong className="text-foreground">{total.toFixed(1)}h</strong> sur {data?.periode_jours ?? 30} jour{(data?.periode_jours ?? 30) > 1 ? 's' : ''}
          </p>
          <div className="h-56">
            <ResponsiveContainer width="100%" height="100%">
              <PieChart>
                <Pie
                  data={chart}
                  cx="50%"
                  cy="50%"
                  outerRadius={70}
                  dataKey="value"
                  label={(entry: any) => `${entry.name}: ${entry.value}h`}
                  labelLine={false}
                >
                  {chart.map((d, i) => <Cell key={i} fill={d.color} />)}
                </Pie>
                <Tooltip formatter={(v: number) => `${v}h`} />
                <Legend wrapperStyle={{ fontSize: '12px' }} />
              </PieChart>
            </ResponsiveContainer>
          </div>
        </>
      )}
    </div>
  );
}
