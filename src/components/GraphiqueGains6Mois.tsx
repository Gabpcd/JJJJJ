import { useMemo } from 'react';
import { BarChart, Bar, XAxis, YAxis, Tooltip, ResponsiveContainer, Cell } from 'recharts';

const MOIS = ['Jan', 'Fév', 'Mar', 'Avr', 'Mai', 'Juin', 'Juil', 'Août', 'Sep', 'Oct', 'Nov', 'Déc'];

interface Props {
  missions: { debut_le: string; net_a_payer: number | null }[];
}

export function GraphiqueGains6Mois({ missions }: Props) {
  const data = useMemo(() => {
    const now = new Date();
    const result: { mois: string; gains: number }[] = [];
    for (let i = 5; i >= 0; i--) {
      const d = new Date(now.getFullYear(), now.getMonth() - i, 1);
      result.push({ mois: MOIS[d.getMonth()], gains: 0 });
    }
    missions.forEach(m => {
      const d = new Date(m.debut_le);
      const now2 = new Date();
      for (let i = 5; i >= 0; i--) {
        const ref = new Date(now2.getFullYear(), now2.getMonth() - i, 1);
        if (d.getFullYear() === ref.getFullYear() && d.getMonth() === ref.getMonth()) {
          result[5 - i].gains += m.net_a_payer || 0;
        }
      }
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
