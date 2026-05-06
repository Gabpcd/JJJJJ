import React, { useEffect, useState } from 'react';
import { LineChart, Line, XAxis, YAxis, Tooltip, ResponsiveContainer, CartesianGrid, ReferenceLine } from 'recharts';
import { TrendingUp, Loader2 } from 'lucide-react';
import { supabase } from '@/integrations/supabase/client';
import { format } from 'date-fns';
import { fr } from 'date-fns/locale';

interface Point {
  mois: string;
  score: number;
  niveau: string;
  cree_le: string;
}

interface Props {
  /** RPC à appeler — si différent par défaut */
  rpc?: 'fn_evolution_score_soignant';
}

export function GraphiqueEvolutionScore({ rpc = 'fn_evolution_score_soignant' }: Props) {
  const [data, setData] = useState<Point[]>([]);
  const [loading, setLoading] = useState(true);

  useEffect(() => {
    let alive = true;
    (async () => {
      const { data: payload } = await supabase.rpc(rpc as any, { p_limit: 6 });
      if (!alive) return;
      if (Array.isArray(payload)) setData(payload as Point[]);
      setLoading(false);
    })();
    return () => { alive = false; };
  }, [rpc]);

  const chart = data.map((p) => ({
    ...p,
    label: (() => {
      const [y, m] = p.mois.split('-');
      return format(new Date(parseInt(y, 10), parseInt(m, 10) - 1, 1), 'MMM', { locale: fr });
    })(),
    score: Number(p.score),
  }));

  const insuffisant = chart.length < 2;

  if (loading) {
    return (
      <div className="card-base text-center py-10">
        <Loader2 className="h-5 w-5 animate-spin text-muted-foreground mx-auto" />
      </div>
    );
  }

  if (chart.length === 0) {
    return (
      <div className="card-base text-center py-8">
        <TrendingUp className="h-6 w-6 text-muted-foreground/30 mx-auto mb-2" />
        <p className="text-sm text-muted-foreground">Pas encore d'historique.</p>
        <p className="text-xs text-muted-foreground mt-0.5">L'évolution apparaîtra après vos premiers recalculs de score.</p>
      </div>
    );
  }

  return (
    <div className="card-base">
      <h3 className="text-base font-bold text-foreground inline-flex items-center gap-2 mb-3">
        <TrendingUp className="h-4 w-4 text-primary" /> Évolution sur 6 mois
      </h3>

      {insuffisant && (
        <p className="text-xs text-muted-foreground mb-3">
          Données limitées : {chart.length} snapshot{chart.length > 1 ? 's' : ''}. Le graphique s'enrichira avec le temps.
        </p>
      )}

      <div className="h-56">
        <ResponsiveContainer width="100%" height="100%">
          <LineChart data={chart} margin={{ top: 8, right: 8, left: 0, bottom: 8 }}>
            <CartesianGrid strokeDasharray="3 3" stroke="hsl(var(--border))" />
            <XAxis dataKey="label" tick={{ fontSize: 11 }} />
            <YAxis domain={[0, 100]} tick={{ fontSize: 11 }} width={28} />
            <Tooltip wrapperStyle={{ fontSize: '12px' }} />
            <ReferenceLine y={50} stroke="#94a3b8" strokeDasharray="2 4" label={{ value: 'Argent', fontSize: 10, fill: '#64748b' }} />
            <ReferenceLine y={70} stroke="#fbbf24" strokeDasharray="2 4" label={{ value: 'Or', fontSize: 10, fill: '#a16207' }} />
            <ReferenceLine y={90} stroke="#10b981" strokeDasharray="2 4" label={{ value: 'Platine', fontSize: 10, fill: '#047857' }} />
            <Line type="monotone" dataKey="score" stroke="#6366f1" strokeWidth={2.5} dot={{ r: 4, fill: '#6366f1' }} activeDot={{ r: 6 }} name="Score" />
          </LineChart>
        </ResponsiveContainer>
      </div>
    </div>
  );
}
