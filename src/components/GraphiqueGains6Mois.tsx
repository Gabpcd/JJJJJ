import { useMemo } from 'react';
import { BarChart, Bar, XAxis, YAxis, Tooltip, ResponsiveContainer, Cell } from 'recharts';
import { cleMoisParis, formatParis } from '@/lib/date-heure-paris';

interface Props {
  missions: { debut_le: string; net_a_payer: number | null }[];
}

export function GraphiqueGains6Mois({ missions }: Props) {
  const data = useMemo(() => {
    const [anneeCourante, moisCourant] = cleMoisParis(new Date()).split('-').map(Number);
    const result: { cle: string; mois: string; gains: number }[] = [];
    for (let i = 5; i >= 0; i--) {
      const date = new Date(Date.UTC(anneeCourante, moisCourant - 1 - i, 1, 12));
      const cle = `${date.getUTCFullYear()}-${String(date.getUTCMonth() + 1).padStart(2, '0')}`;
      result.push({ cle, mois: formatParis(`${cle}-01T12:00:00`, 'MMM'), gains: 0 });
    }
    missions.forEach(m => {
      const index = result.findIndex((periode) => periode.cle === cleMoisParis(m.debut_le));
      if (index >= 0) result[index].gains += m.net_a_payer || 0;
    });
    return result;
  }, [missions]);

  const hasData = data.some(d => d.gains > 0);
  if (!hasData) return null;

  return (
    <div className="card-base mb-6">
      <h2 className="text-base font-semibold text-foreground mb-4">📊 Gains des 6 derniers mois</h2>
      <div className="h-48">
        <ResponsiveContainer width="100%" height="100%">
          <BarChart data={data} margin={{ top: 5, right: 5, bottom: 0, left: -15 }}>
            <XAxis dataKey="mois" tick={{ fontSize: 11, fill: 'hsl(var(--muted-foreground))' }} axisLine={false} tickLine={false} />
            <YAxis tick={{ fontSize: 10, fill: 'hsl(var(--muted-foreground))' }} axisLine={false} tickLine={false} tickFormatter={v => `${v}€`} />
            <Tooltip
              formatter={(v: number) => [`${v.toFixed(0)} €`, 'Net']}
              contentStyle={{ background: 'hsl(var(--card))', border: '1px solid hsl(var(--border))', borderRadius: 8, fontSize: 12 }}
              labelStyle={{ color: 'hsl(var(--foreground))' }}
              cursor={{ fill: 'hsl(var(--muted) / 0.3)' }}
            />
            <Bar dataKey="gains" radius={[6, 6, 0, 0]} maxBarSize={40}>
              {data.map((_, i) => (
                <Cell key={i} fill="hsl(var(--primary))" />
              ))}
            </Bar>
          </BarChart>
        </ResponsiveContainer>
      </div>
    </div>
  );
}
