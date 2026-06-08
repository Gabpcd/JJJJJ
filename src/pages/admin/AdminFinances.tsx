import React, { useState, useEffect, useMemo } from 'react';
import { telechargerOuPartager } from '@/lib/telechargement';
import { LayoutAdmin } from '@/components/LayoutAdmin';
import { BreadcrumbAdmin } from '@/components/BreadcrumbAdmin';
import { usePageTitle } from '@/hooks/usePageTitle';
import { ChargementPage } from '@/components/ChargementPage';
import { supabase } from '@/integrations/supabase/client';
import {
  CardY2K,
  CardY2KHeader,
  CardY2KTitle,
  CardY2KContent,
} from '@/components/y2k/CardY2K';
import { TableOuCartes, type ColonneTableau } from '@/components/ui/TableOuCartes';
import { BoutonY2K } from '@/components/y2k/BoutonY2K';
import { BadgeY2K } from '@/components/y2k/BadgeY2K';
import { ChartContainer, ChartTooltip, ChartTooltipContent } from '@/components/ui/chart';
import { BarChart, Bar, XAxis, YAxis, CartesianGrid } from 'recharts';
import { TrendingUp, TrendingDown, Download, AlertTriangle, ExternalLink, Building2, CheckCircle2, Stethoscope } from 'lucide-react';
import { toast } from 'sonner';
import { useNavigate } from 'react-router-dom';

// Task 12 — diagnostic result type
interface DiagResult {
  success: boolean;
  genere_le: string;
  missions_incoherentes: { count: number; echantillon: Array<{ id: string; intitule: string; total_brut: number; attendu: number; ecart: number }> };
  factures_ecart_mission: { count: number; echantillon: Array<{ facture_id: string; numero_facture: string; mission_id: string; montant_ht: number; mission_net: number; ecart: number }> };
  stripe_transfers_orphelins: { count: number; echantillon: Array<{ transfer_id: string; mission_id: string; montant_total: number }> };
}

const formatEur = (v: number) => new Intl.NumberFormat('fr-FR', { style: 'currency', currency: 'EUR' }).format(v);
const formatDate = (d: string) => new Date(d).toLocaleDateString('fr-FR', { day: '2-digit', month: 'short', year: 'numeric' });

type SortKey = 'nom' | 'type' | 'nb_missions' | 'commissions_ht' | 'commissions_ttc' | 'impayes' | 'taux_com';
type SortDir = 'asc' | 'desc';

export default function AdminFinances() {
  usePageTitle('Finances Jolene');
  const navigate = useNavigate();
  const [loading, setLoading] = useState(true);
  const [factures, setFactures] = useState<any[]>([]);
  const [missions, setMissions] = useState<any[]>([]);
  const [sortKey, setSortKey] = useState<SortKey>('commissions_ht');
  const [sortDir, setSortDir] = useState<SortDir>('desc');

  // Task 12
  const [diagResult, setDiagResult] = useState<DiagResult | null>(null);
  const [diagLoading, setDiagLoading] = useState(false);

  useEffect(() => {
    Promise.all([
      supabase.from('factures')
        .select('id, montant_ht, montant_tva, montant_ttc, statut, date_emission, etablissement_id, etablissements(nom, type)')
        .order('date_emission', { ascending: false })
        .limit(200),
      supabase.from('missions')
        .select('id, total_brut, montant_commission_ht, montant_commission_ttc, statut, debut_le, etablissement_id, soignant_assigne_id, etablissements(nom, type, taux_commission_negocie)')
        .in('statut', ['TERMINEE', 'EN_COURS', 'ASSIGNEE'])
        .limit(200),
    ]).then(([fRes, mRes]) => {
      setFactures(fRes.data || []);
      setMissions(mRes.data || []);
      setLoading(false);
    })
      .catch((err) => {
        setLoading(false);
        toast.error(err?.message || 'Erreur chargement finances');
      });
  }, []);

  const now = new Date();
  const moisCourant = now.getMonth();
  const anneeCourante = now.getFullYear();
  const moisPrecedent = moisCourant === 0 ? 11 : moisCourant - 1;
  const anneePrecedente = moisCourant === 0 ? anneeCourante - 1 : anneeCourante;

  const facturesMoisCourant = useMemo(() => factures.filter(f => {
    if (!f.date_emission) return false;
    const d = new Date(f.date_emission);
    return d.getMonth() === moisCourant && d.getFullYear() === anneeCourante;
  }), [factures, moisCourant, anneeCourante]);

  const facturesMoisPrecedent = useMemo(() => factures.filter(f => {
    if (!f.date_emission) return false;
    const d = new Date(f.date_emission);
    return d.getMonth() === moisPrecedent && d.getFullYear() === anneePrecedente;
  }), [factures, moisPrecedent, anneePrecedente]);

  const commHTMois = facturesMoisCourant.reduce((s, f) => s + (f.montant_ht || 0), 0);
  const commTTCMois = facturesMoisCourant.reduce((s, f) => s + (f.montant_ttc || 0), 0);
  const tvaMois = facturesMoisCourant.reduce((s, f) => s + (f.montant_tva || 0), 0);
  const commHTMoisPrec = facturesMoisPrecedent.reduce((s, f) => s + (f.montant_ht || 0), 0);

  const variationPct = commHTMoisPrec > 0 ? ((commHTMois - commHTMoisPrec) / commHTMoisPrec) * 100 : 0;
  const variationPositive = variationPct >= 0;

  const impayees = factures.filter(f => f.statut === 'EMISE' || f.statut === 'EN_RETARD');
  const nbImpayees = impayees.length;
  const montantImpayees = impayees.reduce((s, f) => s + (f.montant_ttc || 0), 0);

  // Recap all-time
  const totalHT = factures.reduce((s, f) => s + (f.montant_ht || 0), 0);
  const totalTVA = factures.reduce((s, f) => s + (f.montant_tva || 0), 0);
  const totalTTC = factures.reduce((s, f) => s + (f.montant_ttc || 0), 0);
  const payesTTC = factures.filter(f => f.statut === 'PAYEE').reduce((s, f) => s + (f.montant_ttc || 0), 0);
  const volumeBrut = missions.reduce((s, m) => s + (m.total_brut || 0), 0);

  // Taux commission moyen = moyenne des taux de chaque établissement (pas HT/volume)
  const tauxParEtab = useMemo(() => {
    const map = new Map<string, number>();
    missions.forEach((m: any) => {
      const taux = (m.etablissements as any)?.taux_commission_negocie;
      if (taux != null && m.etablissement_id) map.set(m.etablissement_id, Number(taux));
    });
    const vals = [...map.values()];
    return vals.length > 0 ? vals.reduce((a, b) => a + b, 0) / vals.length : 15;
  }, [missions]);

  // Chart data
  const chartData = useMemo(() => {
    const months: { label: string; ht: number; ttc: number }[] = [];
    for (let i = 5; i >= 0; i--) {
      const d = new Date(anneeCourante, moisCourant - i, 1);
      const m = d.getMonth();
      const y = d.getFullYear();
      const label = d.toLocaleDateString('fr-FR', { month: 'short', year: '2-digit' });
      const moisFactures = factures.filter(f => {
        if (!f.date_emission) return false;
        const fd = new Date(f.date_emission);
        return fd.getMonth() === m && fd.getFullYear() === y;
      });
      months.push({
        label,
        ht: moisFactures.reduce((s, f) => s + (f.montant_ht || 0), 0),
        ttc: moisFactures.reduce((s, f) => s + (f.montant_ttc || 0), 0),
      });
    }
    return months;
  }, [factures, moisCourant, anneeCourante]);

  // Per-establishment table
  const etabData = useMemo(() => {
    const map = new Map<string, {
      id: string; nom: string; type: string; nb_missions: number; soignants: Set<string>;
      commissions_ht: number; commissions_ttc: number; impayes: number; taux_com: number; derniere_mission: string;
    }>();
    missions.forEach((m: any) => {
      const eid = m.etablissement_id;
      if (!eid) return;
      const existing = map.get(eid) || {
        id: eid,
        nom: (m.etablissements as any)?.nom || '—',
        type: (m.etablissements as any)?.type || '—',
        taux_com: Number((m.etablissements as any)?.taux_commission_negocie) || 15,
        nb_missions: 0, soignants: new Set<string>(),
        commissions_ht: 0, commissions_ttc: 0, impayes: 0, derniere_mission: '',
      };
      existing.nb_missions++;
      existing.commissions_ht += m.montant_commission_ht || 0;
      existing.commissions_ttc += m.montant_commission_ttc || 0;
      if (m.soignant_assigne_id) existing.soignants.add(m.soignant_assigne_id);
      if (!existing.derniere_mission || (m.debut_le && m.debut_le > existing.derniere_mission)) existing.derniere_mission = m.debut_le;
      map.set(eid, existing);
    });
    factures.filter(f => f.statut === 'EMISE' || f.statut === 'EN_RETARD').forEach(f => {
      const eid = f.etablissement_id;
      if (!eid || !map.has(eid)) return;
      map.get(eid)!.impayes += f.montant_ttc || 0;
    });
    return Array.from(map.values()).map(e => ({ ...e, nb_soignants: e.soignants.size }));
  }, [missions, factures]);

  const sortedEtab = useMemo(() => {
    return [...etabData].sort((a, b) => {
      const va = (a as any)[sortKey];
      const vb = (b as any)[sortKey];
      if (typeof va === 'number' && typeof vb === 'number') return sortDir === 'asc' ? va - vb : vb - va;
      return sortDir === 'asc' ? String(va).localeCompare(String(vb)) : String(vb).localeCompare(String(va));
    });
  }, [etabData, sortKey, sortDir]);

  const toggleSort = (key: SortKey) => {
    if (sortKey === key) setSortDir(d => d === 'asc' ? 'desc' : 'asc');
    else { setSortKey(key); setSortDir('desc'); }
  };

  const exporterCSV = () => {
    const headers = ['Date émission', 'N° Facture', 'Établissement', 'Type', 'Montant HT', 'TVA', 'Montant TTC', 'Statut'];
    const escapeCSV = (v: string) => `"${v.replace(/"/g, '""')}"`;
    const rows = factures.map(f => [
      escapeCSV(f.date_emission ? formatDate(f.date_emission) : ''),
      escapeCSV(f.numero_facture || ''),
      escapeCSV((f.etablissements as any)?.nom || ''),
      escapeCSV((f.etablissements as any)?.type || ''),
      (f.montant_ht || 0).toFixed(2),
      (f.montant_tva || 0).toFixed(2),
      (f.montant_ttc || 0).toFixed(2),
      escapeCSV(f.statut || ''),
    ]);
    const csv = '\uFEFF' + [headers.map(escapeCSV).join(';'), ...rows.map(r => r.join(';'))].join('\n');
    void telechargerOuPartager(csv, `recap_comptable_${new Date().toISOString().slice(0, 7)}.csv`, 'text/csv');
    toast.success('Export CSV téléchargé');
  };

  const chartConfig = {
    ht: { label: 'HT', color: 'hsl(var(--primary))' },
    ttc: { label: 'TTC', color: 'hsl(195 70% 65%)' },
  };

  const lancerDiagnostic = async () => {
    setDiagLoading(true);
    try {
      const { data, error } = await supabase.rpc('fn_diagnostic_coherence_financiere' as any);
      if (error) throw error;
      if (!(data as any)?.success) throw new Error((data as any)?.error || 'Diagnostic échoué.');
      setDiagResult(data as DiagResult);
      toast.success('Diagnostic terminé');
    } catch (err: any) {
      toast.error(err?.message || 'Erreur lors du diagnostic.');
    }
    setDiagLoading(false);
  };

  if (loading) return <LayoutAdmin><ChargementPage /></LayoutAdmin>;

  const nbSoignantsTotal = new Set(missions.map((m: any) => m.soignant_assigne_id).filter(Boolean)).size;

  return (
    <LayoutAdmin>
      <BreadcrumbAdmin pageName="Finances" />
      <div className="space-y-6">
        <div className="flex flex-col sm:flex-row justify-between items-start sm:items-center gap-4">
          <h1 className="text-2xl font-bold text-foreground">Finances Jolene</h1>
          <div className="flex gap-2">
            <BoutonY2K variant="secondary" onClick={exporterCSV} className="gap-2" iconeGauche={<Download className="h-4 w-4" />}>
              Export CSV
            </BoutonY2K>
            <BoutonY2K variant="secondary" onClick={() => navigate('/admin/facturation')} className="gap-2">
              Facturation
            </BoutonY2K>
          </div>
        </div>

        {/* KPIs du mois */}
        <div className="grid grid-cols-2 lg:grid-cols-5 gap-3">
          <CardY2K noPadding className="cursor-pointer hover:border-primary/30 transition-colors" onClick={() => navigate('/admin/facturation')}>
            <CardY2KContent className="pt-4 pb-3">
              <div className="flex items-center justify-between">
                <div>
                  <p className="text-[10px] text-muted-foreground uppercase">Commissions HT du mois</p>
                  <p className="text-xl font-bold text-foreground">{formatEur(commHTMois)}</p>
                </div>
                <div className={`flex items-center gap-1 text-xs font-medium ${variationPositive ? 'text-success' : 'text-destructive'}`}>
                  {variationPositive ? <TrendingUp className="h-3.5 w-3.5" /> : <TrendingDown className="h-3.5 w-3.5" />}
                  {variationPct !== 0 ? `${variationPositive ? '+' : ''}${variationPct.toFixed(0)}%` : '—'}
                </div>
              </div>
            </CardY2KContent>
          </CardY2K>
          <CardY2K noPadding className="cursor-pointer hover:border-primary/30 transition-colors" onClick={() => navigate('/admin/facturation')}>
            <CardY2KContent className="pt-4 pb-3">
              <p className="text-[10px] text-muted-foreground uppercase">TTC du mois</p>
              <p className="text-xl font-bold text-foreground">{formatEur(commTTCMois)}</p>
            </CardY2KContent>
          </CardY2K>
          <CardY2K noPadding className="cursor-pointer hover:border-primary/30 transition-colors" onClick={() => navigate('/admin/facturation')}>
            <CardY2KContent className="pt-4 pb-3">
              <p className="text-[10px] text-muted-foreground uppercase">TVA collectée du mois</p>
              <p className="text-xl font-bold text-foreground">{formatEur(tvaMois)}</p>
            </CardY2KContent>
          </CardY2K>
          <CardY2K
            noPadding
            className={`cursor-pointer hover:border-destructive/50 transition-colors ${nbImpayees > 0 ? 'border-destructive/30 bg-destructive/5' : ''}`}
            onClick={() => navigate('/admin/impayees')}
          >
            <CardY2KContent className="pt-4 pb-3">
              <p className="text-[10px] text-muted-foreground uppercase">Factures impayées</p>
              <p className={`text-xl font-bold ${nbImpayees > 0 ? 'text-destructive' : 'text-foreground'}`}>{nbImpayees}</p>
              {nbImpayees > 0 && <p className="text-[10px] text-destructive">{formatEur(montantImpayees)} en attente</p>}
            </CardY2KContent>
          </CardY2K>
          <CardY2K noPadding>
            <CardY2KContent className="pt-4 pb-3">
              <p className="text-[10px] text-muted-foreground uppercase">Taux com. moyen</p>
              <p className="text-xl font-bold text-foreground">{tauxParEtab.toFixed(1)}%</p>
            </CardY2KContent>
          </CardY2K>
        </div>

        {/* Récap tout temps */}
        <div className="grid grid-cols-2 md:grid-cols-3 lg:grid-cols-6 gap-3">
          {[
            { label: 'CA HT total', value: formatEur(totalHT), click: () => navigate('/admin/facturation') },
            { label: 'TVA total', value: formatEur(totalTVA) },
            { label: 'CA TTC total', value: formatEur(totalTTC) },
            { label: 'Encaissé TTC', value: formatEur(payesTTC), color: 'text-success' },
            { label: 'Volume brut soignants', value: formatEur(volumeBrut) },
            { label: 'Soignants mobilisés', value: String(nbSoignantsTotal) },
          ].map(item => (
            <div
              key={item.label}
              className={`p-3 rounded-xl border border-border bg-card ${item.click ? 'cursor-pointer hover:border-primary/30' : ''}`}
              onClick={item.click}
            >
              <p className="text-[10px] text-muted-foreground">{item.label}</p>
              <p className={`text-lg font-bold ${item.color || 'text-foreground'}`}>{item.value}</p>
            </div>
          ))}
        </div>

        {/* Chart */}
        <CardY2K noPadding>
          <CardY2KHeader><CardY2KTitle className="text-base">Commissions — 6 derniers mois</CardY2KTitle></CardY2KHeader>
          <CardY2KContent>
            <ChartContainer config={chartConfig} className="h-[280px] w-full">
              <BarChart data={chartData}>
                <CartesianGrid strokeDasharray="3 3" className="stroke-border" />
                <XAxis dataKey="label" tick={{ fontSize: 12 }} className="fill-muted-foreground" />
                <YAxis tickFormatter={(v) => `${(v / 1000).toFixed(0)}k`} tick={{ fontSize: 12 }} className="fill-muted-foreground" />
                <ChartTooltip content={<ChartTooltipContent formatter={(value) => formatEur(Number(value))} />} />
                <Bar dataKey="ht" fill="var(--color-ht)" radius={[4, 4, 0, 0]} />
                <Bar dataKey="ttc" fill="var(--color-ttc)" radius={[4, 4, 0, 0]} />
              </BarChart>
            </ChartContainer>
          </CardY2KContent>
        </CardY2K>

        {/* Task 12 — Diagnostic de cohérence financière */}
        <CardY2K noPadding>
          <CardY2KHeader>
            <div className="flex items-center justify-between flex-wrap gap-2">
              <CardY2KTitle className="text-base inline-flex items-center gap-2">
                <Stethoscope className="h-5 w-5 text-primary" />
                Diagnostic de cohérence financière
              </CardY2KTitle>
              <BoutonY2K size="sm" variant="secondary" onClick={lancerDiagnostic} disabled={diagLoading} loading={diagLoading}>
                {diagLoading ? 'Analyse en cours…' : 'Lancer le diagnostic'}
              </BoutonY2K>
            </div>
          </CardY2KHeader>
          <CardY2KContent>
            {!diagResult && !diagLoading && (
              <p className="text-sm text-muted-foreground">Lance l'analyse de cohérence entre missions, factures et transferts Stripe.</p>
            )}
            {diagResult && (
              <div className="space-y-4">
                <p className="text-xs text-muted-foreground">Généré le {new Date(diagResult.genere_le).toLocaleString('fr-FR')}</p>
                {/* 3 counts */}
                <div className="grid grid-cols-1 sm:grid-cols-3 gap-3">
                  {[
                    { label: 'Missions incohérentes', count: diagResult.missions_incoherentes.count },
                    { label: 'Factures avec écart mission', count: diagResult.factures_ecart_mission.count },
                    { label: 'Transferts Stripe orphelins', count: diagResult.stripe_transfers_orphelins.count },
                  ].map((item) => (
                    <div key={item.label} className={`rounded-xl border p-3 flex items-center gap-3 ${item.count > 0 ? 'border-destructive/40 bg-destructive/5' : 'border-success/30 bg-success/5'}`}>
                      {item.count > 0
                        ? <AlertTriangle className="h-5 w-5 text-destructive shrink-0" />
                        : <CheckCircle2 className="h-5 w-5 text-success shrink-0" />}
                      <div>
                        <p className={`text-xl font-bold ${item.count > 0 ? 'text-destructive' : 'text-success'}`}>{item.count}</p>
                        <p className="text-xs text-muted-foreground">{item.label}</p>
                      </div>
                    </div>
                  ))}
                </div>
                {/* Echantillons */}
                {diagResult.missions_incoherentes.count > 0 && diagResult.missions_incoherentes.echantillon.length > 0 && (
                  <div className="space-y-1">
                    <p className="text-xs font-semibold text-foreground">Missions incohérentes (échantillon)</p>
                    {diagResult.missions_incoherentes.echantillon.map((m) => (
                      <div key={m.id} className="text-xs flex flex-wrap items-center gap-2 p-2 rounded-lg bg-muted/40">
                        <span className="font-medium text-foreground truncate max-w-[200px]">{m.intitule}</span>
                        <span className="text-muted-foreground">Brut {formatEur(m.total_brut)}</span>
                        <span className="text-muted-foreground">Attendu {formatEur(m.attendu)}</span>
                        <span className="text-destructive font-bold">Écart {formatEur(m.ecart)}</span>
                      </div>
                    ))}
                  </div>
                )}
                {diagResult.factures_ecart_mission.count > 0 && diagResult.factures_ecart_mission.echantillon.length > 0 && (
                  <div className="space-y-1">
                    <p className="text-xs font-semibold text-foreground">Factures avec écart (échantillon)</p>
                    {diagResult.factures_ecart_mission.echantillon.map((f) => (
                      <div key={f.facture_id} className="text-xs flex flex-wrap items-center gap-2 p-2 rounded-lg bg-muted/40">
                        <span className="font-mono text-foreground">{f.numero_facture}</span>
                        <span className="text-muted-foreground">HT {formatEur(f.montant_ht)}</span>
                        <span className="text-muted-foreground">Mission net {formatEur(f.mission_net)}</span>
                        <span className="text-destructive font-bold">Écart {formatEur(f.ecart)}</span>
                      </div>
                    ))}
                  </div>
                )}
                {diagResult.stripe_transfers_orphelins.count > 0 && diagResult.stripe_transfers_orphelins.echantillon.length > 0 && (
                  <div className="space-y-1">
                    <p className="text-xs font-semibold text-foreground">Transferts Stripe orphelins (échantillon)</p>
                    {diagResult.stripe_transfers_orphelins.echantillon.map((t) => (
                      <div key={t.transfer_id} className="text-xs flex flex-wrap items-center gap-2 p-2 rounded-lg bg-muted/40">
                        <span className="font-mono text-foreground">{t.transfer_id}</span>
                        <span className="text-muted-foreground">Mission {t.mission_id?.slice(0, 8)}…</span>
                        <span className="text-destructive font-bold">{formatEur(t.montant_total)}</span>
                      </div>
                    ))}
                  </div>
                )}
                {diagResult.missions_incoherentes.count === 0 && diagResult.factures_ecart_mission.count === 0 && diagResult.stripe_transfers_orphelins.count === 0 && (
                  <p className="text-sm text-success inline-flex items-center gap-2">
                    <CheckCircle2 className="h-4 w-4" /> Tout cohérent — aucune anomalie détectée.
                  </p>
                )}
              </div>
            )}
          </CardY2KContent>
        </CardY2K>

        {/* Table par établissement */}
        <CardY2K noPadding>
          <CardY2KHeader>
            <CardY2KTitle className="text-base">Détail par établissement</CardY2KTitle>
            {/* Mobile : tri visible via select */}
            <div className="md:hidden flex items-center gap-2 mt-2">
              <label className="text-xs text-muted-foreground">Trier par</label>
              <select
                value={sortKey}
                onChange={(e) => setSortKey(e.target.value as SortKey)}
                className="rounded-lg border border-border bg-background px-2 py-1 text-xs"
              >
                <option value="commissions_ht">Com. HT</option>
                <option value="commissions_ttc">Com. TTC</option>
                <option value="impayes">Impayés</option>
                <option value="nb_missions">Missions</option>
                <option value="taux_com">Taux</option>
                <option value="nom">Nom</option>
              </select>
              <button
                type="button"
                onClick={() => setSortDir(d => d === 'asc' ? 'desc' : 'asc')}
                className="rounded-lg border border-border px-2 py-1 text-xs"
                aria-label={`Tri ${sortDir === 'asc' ? 'ascendant' : 'descendant'}`}
              >
                {sortDir === 'asc' ? '↑' : '↓'}
              </button>
            </div>
          </CardY2KHeader>
          <CardY2KContent className="p-0">
            <TableOuCartes
              colonnes={[
                { cle: 'nom', titre: 'Établissement' },
                { cle: 'type', titre: 'Type' },
                { cle: 'nb_missions', titre: 'Missions' },
                { cle: 'taux_com', titre: 'Taux' },
                { cle: 'commissions_ht', titre: 'Com. HT' },
                { cle: 'commissions_ttc', titre: 'Com. TTC' },
                { cle: 'impayes', titre: 'Impayés' },
                { cle: 'nb_soignants', titre: 'Soignants' },
                { cle: 'derniere_mission', titre: 'Dernière mission' },
              ] as ColonneTableau<typeof sortedEtab[number]>[]}
              donnees={sortedEtab}
              getId={(e) => e.id}
              etatVide={<p className="text-center text-muted-foreground py-8 text-sm">Aucune donnée</p>}
              renduCellule={(e, col) => {
                switch (col.cle) {
                  case 'nom':
                    return (
                      <button onClick={(ev) => { ev.stopPropagation(); navigate(`/admin/utilisateurs/${e.id}`); }} className="text-primary hover:underline font-medium inline-flex items-center gap-1 text-sm">
                        {e.nom}
                        <ExternalLink className="h-3 w-3 shrink-0" />
                      </button>
                    );
                  case 'type': return <BadgeY2K variant="info" size="sm">{e.type}</BadgeY2K>;
                  case 'nb_missions': return <span className="font-medium">{e.nb_missions}</span>;
                  case 'taux_com': return <span className="font-medium text-primary">{e.taux_com}%</span>;
                  case 'commissions_ht': return <span className="font-medium">{formatEur(e.commissions_ht)}</span>;
                  case 'commissions_ttc': return formatEur(e.commissions_ttc);
                  case 'impayes': return e.impayes > 0 ? (
                    <button onClick={(ev) => { ev.stopPropagation(); navigate('/admin/impayees'); }} className="text-destructive font-bold hover:underline inline-flex items-center gap-1">
                      <AlertTriangle className="h-3 w-3" />
                      {formatEur(e.impayes)}
                    </button>
                  ) : <span className="text-muted-foreground">—</span>;
                  case 'nb_soignants': return <span className="text-xs">{e.nb_soignants}</span>;
                  case 'derniere_mission': return <span className="text-xs text-muted-foreground">{e.derniere_mission ? formatDate(e.derniere_mission) : '—'}</span>;
                  default: return null;
                }
              }}
              renduCarte={(e) => (
                <div className={`rounded-xl border p-3 space-y-2 ${e.impayes > 0 ? 'border-destructive/40 bg-destructive/5' : 'border-border bg-card'}`}>
                  <div className="flex items-start justify-between gap-2">
                    <button
                      type="button"
                      onClick={(ev) => { ev.stopPropagation(); navigate(`/admin/utilisateurs/${e.id}`); }}
                      className="text-primary hover:underline font-semibold text-sm inline-flex items-center gap-1 text-left"
                    >
                      <Building2 className="h-3.5 w-3.5 shrink-0" />
                      {e.nom}
                      <ExternalLink className="h-3 w-3 shrink-0" />
                    </button>
                    <BadgeY2K variant="info" size="sm" className="shrink-0">{e.type}</BadgeY2K>
                  </div>
                  <div className="grid grid-cols-2 gap-2 text-xs">
                    <div>
                      <p className="text-muted-foreground">Missions</p>
                      <p className="font-semibold">{e.nb_missions} · {e.nb_soignants} soignant(s)</p>
                    </div>
                    <div>
                      <p className="text-muted-foreground">Taux com.</p>
                      <p className="font-semibold text-primary">{e.taux_com}%</p>
                    </div>
                    <div>
                      <p className="text-muted-foreground">Com. HT</p>
                      <p className="font-semibold">{formatEur(e.commissions_ht)}</p>
                    </div>
                    <div>
                      <p className="text-muted-foreground">Com. TTC</p>
                      <p className="font-semibold">{formatEur(e.commissions_ttc)}</p>
                    </div>
                  </div>
                  {e.impayes > 0 && (
                    <button
                      type="button"
                      onClick={(ev) => { ev.stopPropagation(); navigate('/admin/impayees'); }}
                      className="w-full inline-flex items-center justify-center gap-1.5 text-destructive font-bold text-sm py-1.5 rounded-lg bg-destructive/10 hover:bg-destructive/15 min-h-[36px]"
                    >
                      <AlertTriangle className="h-3.5 w-3.5" />
                      Impayés : {formatEur(e.impayes)}
                    </button>
                  )}
                  {e.derniere_mission && (
                    <p className="text-[10px] text-muted-foreground">Dernière mission : {formatDate(e.derniere_mission)}</p>
                  )}
                </div>
              )}
            />
          </CardY2KContent>
        </CardY2K>
      </div>
    </LayoutAdmin>
  );
}
