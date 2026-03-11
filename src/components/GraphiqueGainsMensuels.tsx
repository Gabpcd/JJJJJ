import { useState } from 'react';
import { BarChart, Bar, LineChart, Line, XAxis, YAxis, Tooltip, ResponsiveContainer, CartesianGrid } from 'recharts';

interface GraphiqueGainsMensuelsProps {
  missions: any[];
}

const MOIS_FR: Record<string, string> = {
  '01': 'Janvier', '02': 'Février', '03': 'Mars', '04': 'Avril',
  '05': 'Mai', '06': 'Juin', '07': 'Juillet', '08': 'Août',
  '09': 'Septembre', '10': 'Octobre', '11': 'Novembre', '12': 'Décembre',
};

function formatMoisFR(moisCle: string): string {
  const [annee, mois] = moisCle.split('-');
  return `${MOIS_FR[mois] || mois} ${annee}`;
}

export function GraphiqueGainsMensuels({ missions }: GraphiqueGainsMensuelsProps) {
  const [mode, setMode] = useState<'barres' | 'courbe'>('barres');

  const gainsMensuels = missions.reduce((acc, m) => {
    const moisCle = new Date(m.debut_le).toISOString().substring(0, 7);
    if (!acc[moisCle]) acc[moisCle] = { mois: moisCle, net: 0, heures: 0, missions: 0 };
    acc[moisCle].net += m.net_a_payer || 0;
    acc[moisCle].heures += m.duree_heures || 0;
    acc[moisCle].missions += 1;
    return acc;
  }, {} as Record<string, any>);

  const data = Object.values(gainsMensuels)
    .sort((a: any, b: any) => a.mois.localeCompare(b.mois))
    .map((g: any) => ({ ...g, label: formatMoisFR(g.mois), net: Math.round(g.net * 100) / 100 }));

  if (data.length === 0) return null;

  return (
    <div className="card-base">
      <div className="flex items-center justify-between mb-4">
        <h3 className="text-base font-bold text-foreground">📈 Évolution de vos revenus</h3>
        <div className="flex gap-1">
          <button onClick={() => setMode('barres')} className={`px-2 py-1 rounded text-xs ${mode === 'barres' ? 'bg-primary text-primary-foreground' : 'bg-muted text-muted-foreground'}`}>Barres</button>
          <button onClick={() => setMode('courbe')} className={`px-2 py-1 rounded text-xs ${mode === 'courbe' ? 'bg-primary text-primary-foreground' : 'bg-muted text-muted-foreground'}`}>Courbe</button>
        </div>
      </div>
      <ResponsiveContainer width="100%" height={250}>
        {mode === 'barres' ? (
          <BarChart data={data}>
            <CartesianGrid strokeDasharray="3 3" stroke="hsl(var(--border))" />
            <XAxis dataKey="label" tick={{ fontSize: 11 }} />
            <YAxis tickFormatter={(v) => `${v}€`} tick={{ fontSize: 11 }} />
            <Tooltip formatter={(value: number) => [`${value.toFixed(2)} €`, 'Net à payer']} labelStyle={{ fontWeight: 'bold' }} />
            <Bar dataKey="net" fill="hsl(var(--primary))" radius={[6, 6, 0, 0]} name="Net à payer" />
          </BarChart>
        ) : (
          <LineChart data={data}>
            <CartesianGrid strokeDasharray="3 3" stroke="hsl(var(--border))" />
            <XAxis dataKey="label" tick={{ fontSize: 11 }} />
            <YAxis tickFormatter={(v) => `${v}€`} tick={{ fontSize: 11 }} />
            <Tooltip formatter={(value: number) => [`${value.toFixed(2)} €`, 'Net à payer']} labelStyle={{ fontWeight: 'bold' }} />
            <Line type="monotone" dataKey="net" stroke="hsl(var(--primary))" strokeWidth={2} dot={{ r: 4, fill: 'hsl(var(--primary))' }} name="Net à payer" />
          </LineChart>
        )}
      </ResponsiveContainer>
    </div>
  );
}
