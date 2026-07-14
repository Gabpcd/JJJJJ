import { useCallback, useState, useEffect } from 'react';
import { usePageTitle } from '@/hooks/usePageTitle';
import { LayoutAdmin } from '@/components/LayoutAdmin';
import { ChargementAdmin } from '@/components/admin/ChargementAdmin';
import { supabase } from '@/integrations/supabase/client';
import { useNotification } from '@/contexts/NotificationContext';
import { extraireMessageErreur } from '@/lib/erreurs';
import { TrendingUp, Users, Building2, DollarSign, RefreshCw, Percent, Clock, Zap } from 'lucide-react';
import { BoutonY2K } from '@/components/y2k/BoutonY2K';
import { CardY2K } from '@/components/y2k/CardY2K';
import { BarChart, Bar, LineChart, Line, AreaChart, Area, XAxis, YAxis, CartesianGrid, Tooltip, ResponsiveContainer, ReferenceLine } from 'recharts';

function fmt(v: number | null | undefined): string {
  if (v == null) return '—';
  return new Intl.NumberFormat('fr-FR', { style: 'currency', currency: 'EUR' }).format(v);
}

export default function AdminCohortEconomics() {
  usePageTitle('Cohortes & économie unitaire');
  const { afficherNotification } = useNotification();
  const [loading, setLoading] = useState(true);
  const [data, setData] = useState<any>(null);
  const [periode, setPeriode] = useState(12);

  const charger = useCallback(async () => {
    setLoading(true);
    const { data: result, error } = await supabase.rpc('fn_admin_cohort_economics' as any, { p_mois: periode });
    if (error) afficherNotification({ type: 'erreur', message: extraireMessageErreur(error) });
    else setData(result);
    setLoading(false);
  }, [afficherNotification, periode]);

  useEffect(() => { charger(); }, [charger]);

  if (loading) return <LayoutAdmin><ChargementAdmin titre="Cohortes & économie unitaire" /></LayoutAdmin>;

  const cohortes = data?.cohortes_mensuelles || [];
  const retention = data?.retention_mensuelle || [];
  const ue = data?.unit_economics || {};
  const totals = data?.totals || {};

  return (
    <LayoutAdmin>
      <div className="flex flex-col sm:flex-row sm:items-center sm:justify-between mb-6 gap-3">
        <div>
          <h1 className="text-xl font-bold text-foreground">Cohortes & économie unitaire</h1>
          <p className="text-sm text-muted-foreground">Métriques pour les investisseurs — {periode} derniers mois</p>
        </div>
        <div className="flex gap-2">
          {[6, 12, 24].map(m => (
            <BoutonY2K key={m} size="sm" variant={periode === m ? 'primary' : 'secondary'} onClick={() => setPeriode(m)}>
              {m}m
            </BoutonY2K>
          ))}
          <BoutonY2K variant="ghost" size="sm" onClick={charger} aria-label="Rafraîchir" iconeGauche={<RefreshCw className="h-4 w-4" />}>
          </BoutonY2K>
        </div>
      </div>

      {/* Totals headline */}
      <div className="grid grid-cols-2 sm:grid-cols-5 gap-3 mb-6">
        {[
          { label: 'Soignants', value: totals.total_soignants, icon: Users, color: 'text-primary' },
          { label: 'Établissements', value: totals.total_etabs, icon: Building2, color: 'text-info' },
          { label: 'Missions terminées', value: totals.total_missions_terminees, icon: Zap, color: 'text-success' },
          { label: 'GMV totale', value: fmt(totals.gmv_total), icon: TrendingUp, color: 'text-primary', raw: true },
          { label: 'Revenus (commissions)', value: fmt(totals.revenue_total), icon: DollarSign, color: 'text-success', raw: true },
        ].map((kpi, i) => (
          <CardY2K key={i} className="text-center p-4" hoverLift={false}>
            <kpi.icon className={`h-5 w-5 ${kpi.color} mx-auto mb-1`} />
            <p className="text-xl font-bold text-foreground">{kpi.raw ? kpi.value : kpi.value?.toLocaleString('fr-FR')}</p>
            <p className="text-[11px] text-muted-foreground">{kpi.label}</p>
          </CardY2K>
        ))}
      </div>

      {/* Économie unitaire */}
      <CardY2K className="mb-6" hoverLift={false}>
        <h2 className="text-base font-semibold text-foreground mb-4">Économie unitaire</h2>
        <div className="grid grid-cols-2 sm:grid-cols-4 gap-4">
          {[
            { label: 'ARPU / Établissement', value: fmt(ue.arpu_etab), sub: 'Commission moyenne par établissement' },
            { label: 'Revenu / soignant actif', value: fmt(ue.rev_per_soignant), sub: 'GMV par soignant' },
            { label: 'Commission / Mission', value: fmt(ue.commission_par_mission), sub: 'Commission moyenne par transaction' },
            { label: 'Commission / Heure', value: fmt(ue.commission_par_heure), sub: 'Marge horaire' },
            { label: 'GMV / Heure', value: fmt(ue.gmv_par_heure), sub: 'Volume horaire brut' },
            { label: 'Taux complétion', value: ue.taux_completion != null ? `${ue.taux_completion}%` : '—', sub: 'Missions terminées / total' },
            { label: 'Taux annulation', value: ue.taux_annulation != null ? `${ue.taux_annulation}%` : '—', sub: 'Missions annulées / total' },
          ].map((m, i) => (
            <div key={i} className="bg-muted/30 rounded-xl p-3">
              <p className="text-lg font-bold text-foreground">{m.value}</p>
              <p className="text-xs font-semibold text-muted-foreground">{m.label}</p>
              <p className="text-[10px] text-muted-foreground/60 mt-0.5">{m.sub}</p>
            </div>
          ))}
        </div>
      </CardY2K>

      {/* GMV + Commissions over time */}
      {cohortes.length > 0 && (
        <CardY2K className="mb-6" hoverLift={false}>
          <h2 className="text-base font-semibold text-foreground mb-4">GMV & Commissions mensuelles</h2>
          <ResponsiveContainer width="100%" height={280}>
            <AreaChart data={cohortes}>
              <CartesianGrid strokeDasharray="3 3" stroke="var(--border)" />
              <XAxis dataKey="mois" tick={{ fontSize: 11, fill: 'var(--muted-foreground)' }} />
              <YAxis tick={{ fontSize: 11, fill: 'var(--muted-foreground)' }} />
              <Tooltip contentStyle={{ background: 'var(--card)', border: '1px solid var(--border)', borderRadius: '0.75rem', fontSize: 12 }} />
              <Area type="monotone" dataKey="gmv" name="GMV (€)" fill="#E04590" fillOpacity={0.1} stroke="#E04590" strokeWidth={2} />
              <Area type="monotone" dataKey="commission_ttc" name="Commission TTC (€)" fill="#10B981" fillOpacity={0.15} stroke="#10B981" strokeWidth={2} />
            </AreaChart>
          </ResponsiveContainer>
        </CardY2K>
      )}

      <div className="grid grid-cols-1 lg:grid-cols-2 gap-6 mb-6">
        {/* Cohort: signups */}
        {cohortes.length > 0 && (
          <CardY2K hoverLift={false}>
            <h2 className="text-base font-semibold text-foreground mb-4">Inscriptions par cohorte</h2>
            <ResponsiveContainer width="100%" height={220}>
              <BarChart data={cohortes}>
                <CartesianGrid strokeDasharray="3 3" stroke="var(--border)" />
                <XAxis dataKey="mois" tick={{ fontSize: 11, fill: 'var(--muted-foreground)' }} />
                <YAxis tick={{ fontSize: 11, fill: 'var(--muted-foreground)' }} />
                <Tooltip contentStyle={{ background: 'var(--card)', border: '1px solid var(--border)', borderRadius: '0.75rem', fontSize: 12 }} />
                <Bar dataKey="nouveaux_soignants" name="Soignants" fill="#E04590" radius={[4, 4, 0, 0]} />
                <Bar dataKey="nouveaux_etabs" name="Établissements" fill="#E04590" radius={[4, 4, 0, 0]} />
              </BarChart>
            </ResponsiveContainer>
          </CardY2K>
        )}

        {/* Retention */}
        {retention.length > 0 && (
          <CardY2K hoverLift={false}>
            <h2 className="text-base font-semibold text-foreground mb-4">Rétention soignants (M → M+1)</h2>
            <ResponsiveContainer width="100%" height={220}>
              <LineChart data={retention}>
                <CartesianGrid strokeDasharray="3 3" stroke="var(--border)" />
                <XAxis dataKey="mois" tick={{ fontSize: 11, fill: 'var(--muted-foreground)' }} />
                <YAxis tick={{ fontSize: 11, fill: 'var(--muted-foreground)' }} domain={[0, 100]} />
                <Tooltip contentStyle={{ background: 'var(--card)', border: '1px solid var(--border)', borderRadius: '0.75rem', fontSize: 12 }} />
                <ReferenceLine y={50} stroke="var(--muted-foreground)" strokeDasharray="3 3" label={{ value: '50%', position: 'right', fontSize: 10 }} />
                <Line type="monotone" dataKey="taux_retention" name="Rétention (%)" stroke="#E04590" strokeWidth={2} dot={{ r: 4, fill: '#E04590' }} />
              </LineChart>
            </ResponsiveContainer>
          </CardY2K>
        )}
      </div>

      {/* Active users over time */}
      {cohortes.length > 0 && (
        <CardY2K hoverLift={false}>
          <h2 className="text-base font-semibold text-foreground mb-4">Utilisateurs actifs par mois</h2>
          <ResponsiveContainer width="100%" height={240}>
            <BarChart data={cohortes}>
              <CartesianGrid strokeDasharray="3 3" stroke="var(--border)" />
              <XAxis dataKey="mois" tick={{ fontSize: 11, fill: 'var(--muted-foreground)' }} />
              <YAxis tick={{ fontSize: 11, fill: 'var(--muted-foreground)' }} />
              <Tooltip contentStyle={{ background: 'var(--card)', border: '1px solid var(--border)', borderRadius: '0.75rem', fontSize: 12 }} />
              <Bar dataKey="soignants_actifs" name="Soignants actifs" fill="#E04590" radius={[4, 4, 0, 0]} />
              <Bar dataKey="etabs_actifs" name="Étab. actifs" fill="#E04590" radius={[4, 4, 0, 0]} />
            </BarChart>
          </ResponsiveContainer>
        </CardY2K>
      )}
    </LayoutAdmin>
  );
}
