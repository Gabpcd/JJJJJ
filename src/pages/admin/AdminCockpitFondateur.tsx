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
import { Users, Building2, TrendingUp, DollarSign, Target, Zap, Rocket, Calculator, RefreshCw, UserPlus, Percent, X, Loader2, ChevronRight } from 'lucide-react';
import { BarChart, Bar, LineChart, Line, AreaChart, Area, XAxis, YAxis, CartesianGrid, Tooltip, ResponsiveContainer, Legend } from 'recharts';
import { getLabelProfession, getLabelTypeEtablissement } from '@/lib/constantes';
import { formatEuroAdmin } from '@/lib/adminPresentation';

const fmt = (v: number) => formatEuroAdmin(v, { decimales: 0 });
const fmtK = (v: number) => v >= 1000 ? `${(v / 1000).toFixed(1)}k` : String(v);

/** Bornes [début, fin) d'un mois 'YYYY-MM' pour les requêtes de drill-down. */
function bornesMois(mois: string): { debut: string; fin: string } {
  const [a, m] = mois.split('-').map(Number);
  const pad = (n: number) => String(n).padStart(2, '0');
  const fin = m === 12 ? `${a + 1}-01` : `${a}-${pad(m + 1)}`;
  return { debut: `${mois}-01`, fin: `${fin}-01` };
}

const fmtMoisLong = (mois: string) => {
  const [a, m] = mois.split('-').map(Number);
  return new Intl.DateTimeFormat('fr-FR', { month: 'long', year: 'numeric' }).format(new Date(a, m - 1, 1));
};

type Drill =
  | { type: 'acquisition'; mois: string }
  | { type: 'revenue'; mois: string };

interface DrillAcquisition {
  soignants: { id: string; prenom: string | null; nom: string | null; profession: string | null }[];
  etablissements: { id: string; nom: string; type: string | null }[];
}
interface DrillRevenueLigne {
  etablissement_id: string;
  nom: string;
  nbMissions: number;
  totalHT: number;
}

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

  // Drill-down par graphique (Session D) : clic sur un mois → détail sous le graphe
  const [drill, setDrill] = useState<Drill | null>(null);
  const [drillLoading, setDrillLoading] = useState(false);
  const [drillAcq, setDrillAcq] = useState<DrillAcquisition | null>(null);
  const [drillRev, setDrillRev] = useState<DrillRevenueLigne[] | null>(null);

  const ouvrirDrill = async (d: Drill) => {
    if (drill && drill.type === d.type && drill.mois === d.mois) { setDrill(null); return; }
    setDrill(d);
    setDrillLoading(true);
    setDrillAcq(null);
    setDrillRev(null);
    const { debut, fin } = bornesMois(d.mois);

    if (d.type === 'acquisition') {
      const [resSg, resEt] = await Promise.all([
        supabase.from('soignants')
          .select('id, prenom, nom, profession')
          .gte('cree_le', debut).lt('cree_le', fin)
          .order('cree_le', { ascending: false })
          .limit(50),
        supabase.from('etablissements')
          .select('id, nom, type')
          .gte('cree_le', debut).lt('cree_le', fin)
          .is('supprime_le', null)
          .order('cree_le', { ascending: false })
          .limit(50),
      ]);
      setDrillAcq({
        soignants: (resSg.data as any[]) ?? [],
        etablissements: (resEt.data as any[]) ?? [],
      });
    } else {
      const { data: missions } = await supabase.from('missions')
        .select('etablissement_id, montant_commission_ht, etablissements(nom)')
        .eq('statut', 'TERMINEE')
        .not('montant_commission_ht', 'is', null)
        .gte('debut_le', debut).lt('debut_le', fin)
        .limit(1000);
      const parEtab = new Map<string, DrillRevenueLigne>();
      for (const m of (missions as any[]) ?? []) {
        const ligne = parEtab.get(m.etablissement_id) ?? {
          etablissement_id: m.etablissement_id,
          nom: m.etablissements?.nom ?? '—',
          nbMissions: 0,
          totalHT: 0,
        };
        ligne.nbMissions += 1;
        ligne.totalHT += Number(m.montant_commission_ht) || 0;
        parEtab.set(m.etablissement_id, ligne);
      }
      setDrillRev([...parEtab.values()].sort((a, b) => b.totalHT - a.totalHT));
    }
    setDrillLoading(false);
  };

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
              <p className="text-[11px] text-muted-foreground">Cliquez sur un mois pour voir qui s'est inscrit</p>
            </CardY2KHeader>
            <CardY2KContent>
              <ResponsiveContainer width="100%" height={220} className="cursor-pointer">
                <BarChart
                  data={acqData}
                  onClick={(state: any) => { if (state?.activeLabel) ouvrirDrill({ type: 'acquisition', mois: state.activeLabel }); }}
                >
                  <CartesianGrid strokeDasharray="3 3" className="stroke-border" />
                  <XAxis dataKey="mois" tick={{ fontSize: 11 }} />
                  <YAxis tick={{ fontSize: 11 }} />
                  <Tooltip />
                  <Legend />
                  <Bar dataKey="soignants" name="Soignants" fill="hsl(var(--primary))" radius={[4, 4, 0, 0]} />
                  <Bar dataKey="etablissements" name="Établissements" fill="hsl(var(--jolene-mauve-500, 270 60% 55%))" radius={[4, 4, 0, 0]} />
                </BarChart>
              </ResponsiveContainer>
              {drill?.type === 'acquisition' && (
                <div className="mt-3 rounded-lg border border-primary/20 bg-primary/5 p-3">
                  <div className="flex items-center justify-between mb-2">
                    <p className="text-xs font-semibold text-foreground">Inscriptions de {fmtMoisLong(drill.mois)}</p>
                    <button onClick={() => setDrill(null)} aria-label="Fermer le détail" className="p-1 text-muted-foreground hover:text-foreground">
                      <X className="h-4 w-4" />
                    </button>
                  </div>
                  {drillLoading ? (
                    <div className="flex justify-center py-4"><Loader2 className="h-4 w-4 animate-spin text-primary" /></div>
                  ) : drillAcq && (drillAcq.soignants.length > 0 || drillAcq.etablissements.length > 0) ? (
                    <div className="grid grid-cols-1 sm:grid-cols-2 gap-3 max-h-56 overflow-y-auto">
                      <div>
                        <p className="text-[11px] font-medium text-muted-foreground mb-1">Soignants ({drillAcq.soignants.length})</p>
                        <ul className="space-y-0.5">
                          {drillAcq.soignants.map(s => (
                            <li key={s.id}>
                              <button
                                onClick={() => navigate(`/admin/utilisateurs/${s.id}`)}
                                className="text-xs text-primary hover:underline inline-flex items-center gap-0.5 text-left"
                              >
                                {s.prenom} {s.nom}{s.profession ? ` — ${getLabelProfession(s.profession)}` : ''} <ChevronRight className="h-3 w-3 shrink-0" />
                              </button>
                            </li>
                          ))}
                        </ul>
                      </div>
                      <div>
                        <p className="text-[11px] font-medium text-muted-foreground mb-1">Établissements ({drillAcq.etablissements.length})</p>
                        <ul className="space-y-0.5">
                          {drillAcq.etablissements.map(e => (
                            <li key={e.id}>
                              <button
                                onClick={() => navigate(`/admin/utilisateurs/${e.id}`)}
                                className="text-xs text-primary hover:underline inline-flex items-center gap-0.5 text-left"
                              >
                                {e.nom}{e.type ? ` — ${getLabelTypeEtablissement(e.type)}` : ''} <ChevronRight className="h-3 w-3 shrink-0" />
                              </button>
                            </li>
                          ))}
                        </ul>
                      </div>
                    </div>
                  ) : (
                    <p className="text-xs text-muted-foreground py-2">Aucune inscription ce mois-ci.</p>
                  )}
                </div>
              )}
            </CardY2KContent>
          </CardY2K>

          {/* Revenue */}
          <CardY2K hoverLift={false}>
            <CardY2KHeader>
              <CardY2KTitle className="text-sm">Revenus mensuels (commissions HT)</CardY2KTitle>
              <p className="text-[11px] text-muted-foreground">Cliquez sur un mois pour voir le détail par établissement</p>
            </CardY2KHeader>
            <CardY2KContent>
              <ResponsiveContainer width="100%" height={220} className="cursor-pointer">
                <AreaChart
                  data={revData}
                  onClick={(state: any) => { if (state?.activeLabel) ouvrirDrill({ type: 'revenue', mois: state.activeLabel }); }}
                >
                  <CartesianGrid strokeDasharray="3 3" className="stroke-border" />
                  <XAxis dataKey="mois" tick={{ fontSize: 11 }} />
                  <YAxis tick={{ fontSize: 11 }} tickFormatter={(v) => fmtK(v)} />
                  <Tooltip formatter={(v: number) => fmt(v)} />
                  <Area dataKey="revenue_ht" name="Revenus HT" fill="hsl(var(--primary))" fillOpacity={0.3} stroke="hsl(var(--primary))" />
                </AreaChart>
              </ResponsiveContainer>
              {drill?.type === 'revenue' && (
                <div className="mt-3 rounded-lg border border-primary/20 bg-primary/5 p-3">
                  <div className="flex items-center justify-between mb-2">
                    <p className="text-xs font-semibold text-foreground">Commissions de {fmtMoisLong(drill.mois)} par établissement</p>
                    <button onClick={() => setDrill(null)} aria-label="Fermer le détail" className="p-1 text-muted-foreground hover:text-foreground">
                      <X className="h-4 w-4" />
                    </button>
                  </div>
                  {drillLoading ? (
                    <div className="flex justify-center py-4"><Loader2 className="h-4 w-4 animate-spin text-primary" /></div>
                  ) : drillRev && drillRev.length > 0 ? (
                    <ul className="space-y-1 max-h-56 overflow-y-auto">
                      {drillRev.map(l => (
                        <li key={l.etablissement_id} className="flex items-center justify-between gap-2">
                          <button
                            onClick={() => navigate(`/admin/utilisateurs/${l.etablissement_id}`)}
                            className="text-xs text-primary hover:underline inline-flex items-center gap-0.5 text-left min-w-0 truncate"
                          >
                            {l.nom} <ChevronRight className="h-3 w-3 shrink-0" />
                          </button>
                          <span className="text-xs text-foreground font-medium whitespace-nowrap">
                            {fmt(l.totalHT)} <span className="text-muted-foreground font-normal">· {l.nbMissions} mission{l.nbMissions > 1 ? 's' : ''}</span>
                          </span>
                        </li>
                      ))}
                    </ul>
                  ) : (
                    <p className="text-xs text-muted-foreground py-2">Aucune commission ce mois-ci.</p>
                  )}
                </div>
              )}
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
