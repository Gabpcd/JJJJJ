import { useState, useEffect, lazy, Suspense } from 'react';
import { usePageTitle } from '@/hooks/usePageTitle';
import { LayoutApp } from '@/components/LayoutApp';
import { ChargementPage } from '@/components/ChargementPage';
import { useAuth } from '@/contexts/AuthContext';
import { useNotification } from '@/contexts/NotificationContext';
import { extraireMessageErreur } from '@/lib/erreurs';
import { supabase } from '@/integrations/supabase/client';
import { BarChart3, TrendingUp, Users, Clock, DollarSign, RefreshCw } from 'lucide-react';
import { BarChart, Bar, LineChart, Line, XAxis, YAxis, CartesianGrid, Tooltip, ResponsiveContainer, PieChart, Pie, Cell } from 'recharts';

const COULEURS = ['#E04590', '#E04590', '#F59E0B', '#10B981', '#8B5CF6', '#F97316'];

function fmt(v: number | null | undefined): string {
  if (v == null) return '—';
  return new Intl.NumberFormat('fr-FR', { style: 'currency', currency: 'EUR' }).format(v);
}

export default function AnalyticsEtablissement() {
  usePageTitle('Analytics');
  const { user } = useAuth();
  const { afficherNotification } = useNotification();
  const [loading, setLoading] = useState(true);
  const [data, setData] = useState<any>(null);
  const [periode, setPeriode] = useState(6);

  const charger = async () => {
    setLoading(true);
    const { data: result, error } = await supabase.rpc('fn_analytics_etablissement' as any, {
      p_etablissement_id: user!.id,
      p_mois: periode,
    });
    if (error) {
      afficherNotification({ type: 'erreur', message: extraireMessageErreur(error) });
    } else {
      setData(result);
    }
    setLoading(false);
  };

  useEffect(() => {
    if (user) charger();
  }, [user, periode]);

  if (loading) return <LayoutApp role="ADMIN_ETABLISSEMENT"><ChargementPage /></LayoutApp>;

  const mpm = data?.missions_par_mois || [];
  const professions = data?.top_professions || [];
  const recurrents = data?.soignants_recurrents || [];

  return (
    <LayoutApp role="ADMIN_ETABLISSEMENT">
      <div className="flex flex-col sm:flex-row sm:items-center sm:justify-between mb-6 gap-3">
        <div>
          <h1 className="text-xl font-bold text-foreground">Analytics</h1>
          <p className="text-sm text-muted-foreground">Indicateurs de performance sur {periode} mois</p>
        </div>
        <div className="flex gap-2">
          {[3, 6, 12].map(m => (
            <button key={m} onClick={() => setPeriode(m)} className={`px-3 py-1.5 rounded-lg text-sm font-medium transition ${periode === m ? 'bg-primary text-primary-foreground' : 'bg-muted text-muted-foreground hover:bg-muted/80'}`}>
              {m} mois
            </button>
          ))}
          <button onClick={charger} className="p-1.5 rounded-lg bg-muted hover:bg-muted/80 transition">
            <RefreshCw className="h-4 w-4 text-muted-foreground" />
          </button>
        </div>
      </div>

      {/* KPI Cards */}
      <div className="grid grid-cols-1 sm:grid-cols-3 gap-4 mb-6">
        <div className="card-base flex items-center gap-4">
          <div className="p-3 rounded-xl bg-primary/10">
            <TrendingUp className="h-6 w-6 text-primary" />
          </div>
          <div>
            <p className="text-2xl font-bold text-foreground">{data?.taux_remplissage ?? 0}%</p>
            <p className="text-sm text-muted-foreground">Taux de remplissage</p>
          </div>
        </div>
        <div className="card-base flex items-center gap-4">
          <div className="p-3 rounded-xl bg-info/10">
            <DollarSign className="h-6 w-6 text-info" />
          </div>
          <div>
            <p className="text-2xl font-bold text-foreground">{fmt(data?.cout_heure_moyen)}/h</p>
            <p className="text-sm text-muted-foreground">Coût horaire moyen</p>
          </div>
        </div>
        <div className="card-base flex items-center gap-4">
          <div className="p-3 rounded-xl bg-warning/10">
            <Users className="h-6 w-6 text-warning" />
          </div>
          <div>
            <p className="text-2xl font-bold text-foreground">{data?.turnover_pourcent ?? 0}%</p>
            <p className="text-sm text-muted-foreground">Turnover soignants</p>
          </div>
        </div>
      </div>

      {/* Missions par mois */}
      {mpm.length > 0 && (
        <div className="card-base mb-6">
          <h2 className="text-base font-semibold text-foreground mb-4">Missions par mois</h2>
          <ResponsiveContainer width="100%" height={280}>
            <BarChart data={mpm}>
              <CartesianGrid strokeDasharray="3 3" stroke="var(--border)" />
              <XAxis dataKey="mois" tick={{ fontSize: 12, fill: 'var(--muted-foreground)' }} />
              <YAxis tick={{ fontSize: 12, fill: 'var(--muted-foreground)' }} />
              <Tooltip
                contentStyle={{ background: 'var(--card)', border: '1px solid var(--border)', borderRadius: '0.75rem', fontSize: 12 }}
              />
              <Bar dataKey="terminees" name="Terminées" fill="#10B981" radius={[4, 4, 0, 0]} />
              <Bar dataKey="annulees" name="Annulées" fill="#EF4444" radius={[4, 4, 0, 0]} />
              <Bar dataKey="total" name="Total" fill="#E04590" radius={[4, 4, 0, 0]} opacity={0.3} />
            </BarChart>
          </ResponsiveContainer>
        </div>
      )}

      <div className="grid grid-cols-1 lg:grid-cols-2 gap-6 mb-6">
        {/* Coût par mois */}
        {mpm.length > 0 && (
          <div className="card-base">
            <h2 className="text-base font-semibold text-foreground mb-4">Coût total par mois</h2>
            <ResponsiveContainer width="100%" height={220}>
              <LineChart data={mpm}>
                <CartesianGrid strokeDasharray="3 3" stroke="var(--border)" />
                <XAxis dataKey="mois" tick={{ fontSize: 11, fill: 'var(--muted-foreground)' }} />
                <YAxis tick={{ fontSize: 11, fill: 'var(--muted-foreground)' }} />
                <Tooltip contentStyle={{ background: 'var(--card)', border: '1px solid var(--border)', borderRadius: '0.75rem', fontSize: 12 }} />
                <Line type="monotone" dataKey="cout_total" name="Coût (€)" stroke="#E04590" strokeWidth={2} dot={{ r: 4, fill: '#E04590' }} />
              </LineChart>
            </ResponsiveContainer>
          </div>
        )}

        {/* Top professions */}
        {professions.length > 0 && (
          <div className="card-base">
            <h2 className="text-base font-semibold text-foreground mb-4">Professions les plus demandées</h2>
            <ResponsiveContainer width="100%" height={220}>
              <PieChart>
                <Pie data={professions} dataKey="nb_missions" nameKey="profession" cx="50%" cy="50%" outerRadius={80} label={({ profession, nb_missions }) => `${profession} (${nb_missions})`}>
                  {professions.map((_: any, i: number) => (
                    <Cell key={i} fill={COULEURS[i % COULEURS.length]} />
                  ))}
                </Pie>
                <Tooltip contentStyle={{ background: 'var(--card)', border: '1px solid var(--border)', borderRadius: '0.75rem', fontSize: 12 }} />
              </PieChart>
            </ResponsiveContainer>
          </div>
        )}
      </div>

      {/* Soignants récurrents */}
      {recurrents.length > 0 && (
        <div className="card-base">
          <h2 className="text-base font-semibold text-foreground mb-4">Soignants les plus sollicités</h2>
          <div className="overflow-x-auto">
            <table className="w-full text-sm">
              <thead>
                <tr className="border-b border-border text-muted-foreground">
                  <th className="text-left py-2 px-3 font-medium">Soignant</th>
                  <th className="text-left py-2 px-3 font-medium">Profession</th>
                  <th className="text-center py-2 px-3 font-medium">Missions</th>
                  <th className="text-center py-2 px-3 font-medium">Note</th>
                </tr>
              </thead>
              <tbody>
                {recurrents.map((s: any) => (
                  <tr key={s.id} className="border-b border-border/50 hover:bg-muted/30 transition">
                    <td className="py-2.5 px-3 font-medium text-foreground">{s.prenom} {s.nom}</td>
                    <td className="py-2.5 px-3 text-muted-foreground">{s.profession}</td>
                    <td className="py-2.5 px-3 text-center">
                      <span className="inline-flex items-center justify-center rounded-full bg-primary/10 text-primary px-2.5 py-0.5 text-xs font-semibold">{s.nb_missions}</span>
                    </td>
                    <td className="py-2.5 px-3 text-center">{s.note_moyenne > 0 ? `${s.note_moyenne}/5` : '—'}</td>
                  </tr>
                ))}
              </tbody>
            </table>
          </div>
        </div>
      )}

      {!mpm.length && !professions.length && (
        <div className="card-base text-center py-12">
          <BarChart3 className="h-12 w-12 text-muted-foreground/40 mx-auto mb-3" />
          <p className="text-muted-foreground">Pas encore de données sur cette période.</p>
          <p className="text-sm text-muted-foreground/60 mt-1">Les analytics apparaîtront après vos premières missions.</p>
        </div>
      )}
    </LayoutApp>
  );
}
