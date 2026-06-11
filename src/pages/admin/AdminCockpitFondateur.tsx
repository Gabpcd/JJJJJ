import { useState, useEffect, useMemo } from 'react';
import { useNavigate } from 'react-router-dom';
import { usePageTitle } from '@/hooks/usePageTitle';
import { LayoutAdmin } from '@/components/LayoutAdmin';
import { ChargementPage } from '@/components/ChargementPage';
import { supabase } from '@/integrations/supabase/client';
import { CarteKPIY2K } from '@/components/y2k/CarteKPIY2K';
import { CardY2K, CardY2KHeader, CardY2KTitle, CardY2KContent } from '@/components/y2k/CardY2K';
import { BoutonY2K } from '@/components/y2k/BoutonY2K';
import { BadgeY2K } from '@/components/y2k/BadgeY2K';
import { Users, Building2, TrendingUp, DollarSign, Target, Zap, Rocket, Calculator, RefreshCw, UserPlus, Percent } from 'lucide-react';
import { BarChart, Bar, LineChart, Line, AreaChart, Area, XAxis, YAxis, CartesianGrid, Tooltip, ResponsiveContainer, Legend } from 'recharts';

const fmt = (v: number) => new Intl.NumberFormat('fr-FR', { style: 'currency', currency: 'EUR', maximumFractionDigits: 0 }).format(v);
const fmtK = (v: number) => v >= 1000 ? `${(v / 1000).toFixed(1)}k` : String(v);

// Estimations maintenues manuellement — affichées comme « estimation » à l'écran, pas comme coûts réels.
const CHARGES_FIXES_MENSUELLES = [
  { label: 'Supabase', montant: 25 },
  { label: 'Resend', montant: 20 },
  { label: 'Lovable', montant: 20 },
  { label: 'Apple Developer', montant: 8 },
];
const TOTAL_FIXES = CHARGES_FIXES_MENSUELLES.reduce((s, c) => s + c.montant, 0);

export default function AdminCockpitFondateur() {
  usePageTitle('Cockpit Fondateur');
  const navigate = useNavigate();
  const [loading, setLoading] = useState(true);
  const [data, setData] = useState<any>(null);
  const [equipe, setEquipe] = useState<any[]>([]);
  const [pipeline, setPipeline] = useState<any[]>([]);

  const charger = async () => {
    setLoading(true);
    const [resMetriques, resEquipe, resPipeline] = await Promise.all([
      supabase.rpc('fn_admin_cockpit_fondateur' as any),
      supabase.from('equipe_admin' as any).select('*').eq('actif', true).order('date_embauche', { ascending: true }),
      supabase.from('investisseurs_pipeline' as any).select('*').order('cree_le', { ascending: false }),
    ]);
    if (resMetriques.data) setData(resMetriques.data);
    if (resEquipe.data) setEquipe(resEquipe.data);
    if (resPipeline.data) setPipeline(resPipeline.data);
    setLoading(false);
  };

  useEffect(() => { charger(); }, []);

  const runway = useMemo(() => {
    if (!data) return null;
    const revenuMensuel = (data.revenue_total || 0) / Math.max(data.revenue_mensuel?.length || 1, 1);
    const chargesEquipe = data.charges_equipe_mensuel || 0;
    const stripeFees = revenuMensuel * 0.014 + (data.missions_terminees || 0) / 12 * 0.25;
    const totalCharges = TOTAL_FIXES + chargesEquipe + stripeFees;
    const burnMensuel = totalCharges - revenuMensuel;
    const mrrAnnualise = revenuMensuel * 12;
    const arr = mrrAnnualise;
    const ltv = revenuMensuel > 0 && data.total_etabs > 0 ? (revenuMensuel / data.total_etabs) * 24 : 0;

    return {
      mrr: revenuMensuel,
      arr,
      burnMensuel: Math.max(burnMensuel, 0),
      totalCharges,
      stripeFees,
      ltv,
    };
  }, [data]);

  if (loading) return <LayoutAdmin><ChargementPage /></LayoutAdmin>;
  if (!data) return <LayoutAdmin><p className="text-muted-foreground">Erreur de chargement.</p></LayoutAdmin>;

  const acqData = data.acquisition_mensuelle || [];
  const revData = data.revenue_mensuel || [];

  const pipelineStats = {
    actifs: pipeline.filter((i: any) => !['DECLINE', 'SIGNE'].includes(i.statut)).length,
    montantVise: pipeline.reduce((s: number, i: any) => s + (Number(i.montant_vise) || 0), 0),
  };

  return (
    <LayoutAdmin>
      <div className="space-y-6">
        <div className="flex flex-col sm:flex-row sm:items-center sm:justify-between gap-3">
          <div>
            <h1 className="text-xl font-bold text-foreground">Cockpit Fondateur</h1>
            <p className="text-sm text-muted-foreground">Vue stratégique — métriques Série A</p>
          </div>
          <BoutonY2K variant="ghost" size="sm" onClick={charger} iconeGauche={<RefreshCw className="h-4 w-4" />}>
            Rafraîchir
          </BoutonY2K>
        </div>

        {/* KPIs headline — chaque carte est cliquable vers la page de détail */}
        <div className="grid grid-cols-2 lg:grid-cols-4 gap-4">
          <CarteKPIY2K
            icone={<Users className="h-4 w-4" />}
            valeur={data.total_soignants?.toLocaleString('fr-FR') ?? '—'}
            label="Soignants"
            contexte={`+${data.soignants_7j ?? 0} /7j · +${data.soignants_30j ?? 0} /30j`}
            variant="holographic"
            onClick={() => navigate('/admin/utilisateurs')}
          />
          <CarteKPIY2K
            icone={<Building2 className="h-4 w-4" />}
            valeur={data.total_etabs?.toLocaleString('fr-FR') ?? '—'}
            label="Établissements"
            contexte={`+${data.etabs_7j ?? 0} /7j · +${data.etabs_30j ?? 0} /30j`}
            variant="default"
            onClick={() => navigate('/admin/utilisateurs')}
          />
          <CarteKPIY2K
            icone={<DollarSign className="h-4 w-4" />}
            valeur={runway ? fmt(runway.mrr) : '—'}
            label="MRR"
            contexte={runway ? `ARR ${fmt(runway.arr)}` : ''}
            variant="holographic"
            onClick={() => navigate('/admin/finances')}
          />
          <CarteKPIY2K
            icone={<Zap className="h-4 w-4" />}
            valeur={data.missions_terminees?.toLocaleString('fr-FR') ?? '—'}
            label="Missions terminées"
            contexte={`${data.missions_mois ?? 0} ce mois`}
            variant="default"
            onClick={() => navigate('/admin/missions?statut=TERMINEE')}
          />
        </div>

        {/* Row 2 : activation + economics */}
        <div className="grid grid-cols-2 lg:grid-cols-4 gap-4">
          <CarteKPIY2K
            icone={<Percent className="h-4 w-4" />}
            valeur={`${data.taux_activation_soignant ?? 0}%`}
            label="Activation soignants"
            contexte="≥1 candidature"
            variant="default"
            onClick={() => navigate('/admin/utilisateurs')}
          />
          <CarteKPIY2K
            icone={<Percent className="h-4 w-4" />}
            valeur={`${data.taux_activation_etab ?? 0}%`}
            label="Activation étab."
            contexte="≥1 mission publiée"
            variant="default"
            onClick={() => navigate('/admin/missions')}
          />
          <CarteKPIY2K
            icone={<TrendingUp className="h-4 w-4" />}
            valeur={fmt(data.gmv_total ?? 0)}
            label="GMV totale"
            variant="default"
            onClick={() => navigate('/admin/finances')}
          />
          <CarteKPIY2K
            icone={<Target className="h-4 w-4" />}
            valeur={fmt(data.revenue_total ?? 0)}
            label="Revenus totaux (commissions)"
            variant="default"
            onClick={() => navigate('/admin/facturation')}
          />
        </div>

        {/* Charts row */}
        <div className="grid grid-cols-1 lg:grid-cols-2 gap-4">
          {/* Acquisition */}
          <CardY2K hoverLift={false}>
            <CardY2KHeader>
              <CardY2KTitle className="text-sm">Acquisition mensuelle</CardY2KTitle>
            </CardY2KHeader>
            <CardY2KContent>
              <ResponsiveContainer width="100%" height={220}>
                <BarChart data={acqData}>
                  <CartesianGrid strokeDasharray="3 3" className="stroke-border" />
                  <XAxis dataKey="mois" tick={{ fontSize: 11 }} />
                  <YAxis tick={{ fontSize: 11 }} />
                  <Tooltip />
                  <Legend />
                  <Bar dataKey="soignants" name="Soignants" fill="hsl(var(--primary))" radius={[4, 4, 0, 0]} />
                  <Bar dataKey="etablissements" name="Établissements" fill="hsl(var(--jolene-mauve-500, 270 60% 55%))" radius={[4, 4, 0, 0]} />
                </BarChart>
              </ResponsiveContainer>
            </CardY2KContent>
          </CardY2K>

          {/* Revenue */}
          <CardY2K hoverLift={false}>
            <CardY2KHeader>
              <CardY2KTitle className="text-sm">Revenus mensuels (commissions HT)</CardY2KTitle>
            </CardY2KHeader>
            <CardY2KContent>
              <ResponsiveContainer width="100%" height={220}>
                <AreaChart data={revData}>
                  <CartesianGrid strokeDasharray="3 3" className="stroke-border" />
                  <XAxis dataKey="mois" tick={{ fontSize: 11 }} />
                  <YAxis tick={{ fontSize: 11 }} tickFormatter={(v) => fmtK(v)} />
                  <Tooltip formatter={(v: number) => fmt(v)} />
                  <Area dataKey="revenue_ht" name="Revenus HT" fill="hsl(var(--primary))" fillOpacity={0.3} stroke="hsl(var(--primary))" />
                </AreaChart>
              </ResponsiveContainer>
            </CardY2KContent>
          </CardY2K>
        </div>

        {/* Runway / Unit Economics */}
        {runway && (
          <CardY2K hoverLift={false}>
            <CardY2KHeader>
              <CardY2KTitle className="text-sm flex items-center gap-2">
                <Calculator className="h-4 w-4" /> Unit Economics & Runway
              </CardY2KTitle>
            </CardY2KHeader>
            <CardY2KContent>
              <div className="grid grid-cols-2 sm:grid-cols-4 gap-4">
                <div className="rounded-lg border p-3">
                  <p className="text-xs text-muted-foreground">Burn mensuel</p>
                  <p className="text-lg font-bold text-foreground">{fmt(runway.burnMensuel)}</p>
                </div>
                <div className="rounded-lg border p-3">
                  <p className="text-xs text-muted-foreground">Charges totales /mois (estimation)</p>
                  <p className="text-lg font-bold text-foreground">{fmt(runway.totalCharges)}</p>
                  <p className="text-[10px] text-muted-foreground">fixes estimées {fmt(TOTAL_FIXES)} + Stripe estimé {fmt(runway.stripeFees)} + équipe {fmt(data.charges_equipe_mensuel || 0)}</p>
                </div>
                <div className="rounded-lg border p-3">
                  <p className="text-xs text-muted-foreground">LTV (étab, 24 mois)</p>
                  <p className="text-lg font-bold text-foreground">{runway.ltv > 0 ? fmt(runway.ltv) : '—'}</p>
                </div>
                <div className="rounded-lg border p-3">
                  <p className="text-xs text-muted-foreground">CAC</p>
                  <p className="text-lg font-bold text-foreground">—</p>
                  <p className="text-[10px] text-muted-foreground">Non mesuré — acquisition organique</p>
                </div>
              </div>
            </CardY2KContent>
          </CardY2K>
        )}

        {/* Quick links */}
        <div className="grid grid-cols-1 sm:grid-cols-3 gap-4">
          <CardY2K className="cursor-pointer" onClick={() => navigate('/admin/fondateur/equipe')}>
            <div className="flex items-center gap-3 p-4">
              <UserPlus className="h-6 w-6 text-primary" />
              <div>
                <p className="font-semibold text-foreground">Équipe</p>
                <p className="text-xs text-muted-foreground">{equipe.length} membre{equipe.length > 1 ? 's' : ''} actif{equipe.length > 1 ? 's' : ''}</p>
              </div>
            </div>
          </CardY2K>
          <CardY2K className="cursor-pointer" onClick={() => navigate('/admin/fondateur/levee')}>
            <div className="flex items-center gap-3 p-4">
              <Rocket className="h-6 w-6 text-primary" />
              <div>
                <p className="font-semibold text-foreground">Levée de fonds</p>
                <p className="text-xs text-muted-foreground">
                  {pipelineStats.actifs} investisseur{pipelineStats.actifs > 1 ? 's' : ''} actif{pipelineStats.actifs > 1 ? 's' : ''}
                  {pipelineStats.montantVise > 0 ? ` · ${fmt(pipelineStats.montantVise)} visés` : ''}
                </p>
              </div>
            </div>
          </CardY2K>
          <CardY2K className="cursor-pointer" onClick={() => navigate('/admin/cohort')}>
            <div className="flex items-center gap-3 p-4">
              <TrendingUp className="h-6 w-6 text-primary" />
              <div>
                <p className="font-semibold text-foreground">Cohort & Economics</p>
                <p className="text-xs text-muted-foreground">Rétention, cohortes mensuelles</p>
              </div>
            </div>
          </CardY2K>
        </div>
      </div>
    </LayoutAdmin>
  );
}
