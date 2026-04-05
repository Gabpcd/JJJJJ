import React, { useState, useEffect, useMemo } from 'react';
import { LayoutAdmin } from '@/components/LayoutAdmin';
import { BreadcrumbAdmin } from '@/components/BreadcrumbAdmin';
import { usePageTitle } from '@/hooks/usePageTitle';
import { ChargementPage } from '@/components/ChargementPage';
import { supabase } from '@/integrations/supabase/client';
import { CarteKPI } from '@/components/CarteKPI';
import { Card, CardContent, CardHeader, CardTitle } from '@/components/ui/card';
import { Table, TableBody, TableCell, TableHead, TableHeader, TableRow } from '@/components/ui/table';
import { Button } from '@/components/ui/button';
import { Badge } from '@/components/ui/badge';
import { ChartContainer, ChartTooltip, ChartTooltipContent } from '@/components/ui/chart';
import { BarChart, Bar, XAxis, YAxis, CartesianGrid } from 'recharts';
import { TrendingUp, TrendingDown, Download, Coins, Receipt, AlertTriangle, BarChart3 } from 'lucide-react';
import { toast } from 'sonner';
import { useNavigate } from 'react-router-dom';

const formatEur = (v: number) => new Intl.NumberFormat('fr-FR', { style: 'currency', currency: 'EUR' }).format(v);
const formatDate = (d: string) => new Date(d).toLocaleDateString('fr-FR', { day: '2-digit', month: 'short', year: 'numeric' });

type SortKey = 'nom' | 'type' | 'nb_missions' | 'commissions_ht' | 'commissions_ttc' | 'impayes';
type SortDir = 'asc' | 'desc';

export default function AdminFinances() {
  usePageTitle('Finances Jolene');
  const navigate = useNavigate();
  const [loading, setLoading] = useState(true);
  const [factures, setFactures] = useState<any[]>([]);
  const [missions, setMissions] = useState<any[]>([]);
  const [sortKey, setSortKey] = useState<SortKey>('commissions_ht');
  const [sortDir, setSortDir] = useState<SortDir>('desc');

  useEffect(() => {
    Promise.all([
      supabase.from('factures')
        .select('id, montant_ht, montant_tva, montant_ttc, statut, date_emission, etablissement_id, etablissements(nom, type)')
        .order('date_emission', { ascending: false })
        .limit(1000),
      supabase.from('missions')
        .select('id, total_brut, montant_commission_ht, montant_commission_ttc, statut, debut_le, etablissement_id, etablissements(nom, type)')
        .in('statut', ['TERMINEE', 'EN_COURS', 'ASSIGNEE'])
        .limit(1000),
    ]).then(([fRes, mRes]) => {
      setFactures(fRes.data || []);
      setMissions(mRes.data || []);
      setLoading(false);
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
  const volumeBrut = missions.reduce((s, m) => s + (m.total_brut || 0), 0);
  const tauxCommMoyen = volumeBrut > 0 ? (totalHT / volumeBrut) * 100 : 0;

  // Chart data: 6 last months
  const chartData = useMemo(() => {
    const months: { label: string; ht: number }[] = [];
    for (let i = 5; i >= 0; i--) {
      const d = new Date(anneeCourante, moisCourant - i, 1);
      const m = d.getMonth();
      const y = d.getFullYear();
      const label = d.toLocaleDateString('fr-FR', { month: 'short', year: '2-digit' });
      const ht = factures
        .filter(f => { if (!f.date_emission) return false; const fd = new Date(f.date_emission); return fd.getMonth() === m && fd.getFullYear() === y; })
        .reduce((s, f) => s + (f.montant_ht || 0), 0);
      months.push({ label, ht });
    }
    return months;
  }, [factures, moisCourant, anneeCourante]);

  // Per-establishment table
  const etabData = useMemo(() => {
    const map = new Map<string, { nom: string; type: string; nb_missions: number; commissions_ht: number; commissions_ttc: number; impayes: number; derniere_mission: string }>();
    missions.forEach((m: any) => {
      const eid = m.etablissement_id;
      if (!eid) return;
      const existing = map.get(eid) || { nom: (m.etablissements as any)?.nom || '—', type: (m.etablissements as any)?.type || '—', nb_missions: 0, commissions_ht: 0, commissions_ttc: 0, impayes: 0, derniere_mission: '' };
      existing.nb_missions++;
      existing.commissions_ht += m.montant_commission_ht || 0;
      existing.commissions_ttc += m.montant_commission_ttc || 0;
      if (!existing.derniere_mission || (m.debut_le && m.debut_le > existing.derniere_mission)) existing.derniere_mission = m.debut_le;
      map.set(eid, existing);
    });
    // Add unpaid amounts
    factures.filter(f => f.statut === 'EMISE' || f.statut === 'EN_RETARD').forEach(f => {
      const eid = f.etablissement_id;
      if (!eid || !map.has(eid)) return;
      const e = map.get(eid)!;
      e.impayes += f.montant_ttc || 0;
    });
    return Array.from(map.entries()).map(([id, d]) => ({ id, ...d }));
  }, [missions, factures]);

  const sortedEtab = useMemo(() => {
    return [...etabData].sort((a, b) => {
      const va = a[sortKey];
      const vb = b[sortKey];
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
    const blob = new Blob([csv], { type: 'text/csv;charset=utf-8;' });
    const url = URL.createObjectURL(blob);
    const a = document.createElement('a'); a.href = url; a.download = `recap_comptable_${new Date().toISOString().slice(0, 7)}.csv`; a.click();
    URL.revokeObjectURL(url);
    toast.success('Export CSV téléchargé');
  };

  const chartConfig = { ht: { label: 'Commissions HT', color: 'hsl(var(--primary))' } };

  if (loading) return <LayoutAdmin><ChargementPage /></LayoutAdmin>;

  return (
    <LayoutAdmin>
      <BreadcrumbAdmin pageName="Finances" />
      <div className="space-y-6">
        <div className="flex flex-col sm:flex-row justify-between items-start sm:items-center gap-4">
          <h1 className="text-2xl font-bold text-foreground">💰 Finances Jolene</h1>
          <Button variant="outline" onClick={exporterCSV} className="gap-2">
            <Download className="h-4 w-4" /> Exporter le récap comptable
          </Button>
        </div>

        {/* KPIs */}
        <div className="grid grid-cols-1 sm:grid-cols-2 lg:grid-cols-4 gap-4">
          <Card>
            <CardContent className="pt-5 pb-4">
              <div className="flex items-center justify-between">
                <div>
                  <p className="text-xs text-muted-foreground">Commissions du mois (HT)</p>
                  <p className="text-2xl font-bold text-foreground">{formatEur(commHTMois)}</p>
                </div>
                <div className={`flex items-center gap-1 text-xs font-medium ${variationPositive ? 'text-green-600' : 'text-destructive'}`}>
                  {variationPositive ? <TrendingUp className="h-4 w-4" /> : <TrendingDown className="h-4 w-4" />}
                  {variationPct !== 0 ? `${variationPositive ? '+' : ''}${variationPct.toFixed(1)}%` : '—'}
                </div>
              </div>
            </CardContent>
          </Card>
          <Card>
            <CardContent className="pt-5 pb-4">
              <p className="text-xs text-muted-foreground">Commissions du mois (TTC)</p>
              <p className="text-2xl font-bold text-foreground">{formatEur(commTTCMois)}</p>
            </CardContent>
          </Card>
          <Card>
            <CardContent className="pt-5 pb-4">
              <p className="text-xs text-muted-foreground">📊 TVA collectée du mois</p>
              <p className="text-2xl font-bold text-foreground">{formatEur(tvaMois)}</p>
            </CardContent>
          </Card>
          <Card className={`${nbImpayees > 0 ? 'border-destructive/50' : ''}`} onClick={() => navigate('/admin/facturation?statut=EMISE')} onKeyDown={(e) => { if (e.key === 'Enter' || e.key === ' ') { e.preventDefault(); navigate('/admin/facturation?statut=EMISE'); } }} role="button" tabIndex={0}>
            <CardContent className="pt-5 pb-4 cursor-pointer">
              <p className="text-xs text-muted-foreground">⚠️ Factures impayées</p>
              <p className={`text-2xl font-bold ${nbImpayees > 0 ? 'text-destructive' : 'text-foreground'}`}>{nbImpayees}</p>
              {nbImpayees > 0 && <p className="text-xs text-destructive mt-0.5">{formatEur(montantImpayees)} en attente</p>}
            </CardContent>
          </Card>
        </div>

        {/* Recap comptable */}
        <Card>
          <CardHeader><CardTitle className="text-base">Récapitulatif comptable</CardTitle></CardHeader>
          <CardContent>
            <div className="grid grid-cols-2 sm:grid-cols-3 lg:grid-cols-5 gap-4">
              {[
                { label: 'Commissions HT (tout temps)', value: formatEur(totalHT) },
                { label: 'TVA collectée (tout temps)', value: formatEur(totalTVA) },
                { label: 'Commissions TTC (tout temps)', value: formatEur(totalTTC) },
                { label: 'Volume brut transité', value: formatEur(volumeBrut) },
                { label: 'Taux de commission moyen', value: `${tauxCommMoyen.toFixed(1)}%` },
              ].map(item => (
                <div key={item.label}>
                  <p className="text-xs text-muted-foreground">{item.label}</p>
                  <p className="text-lg font-semibold text-foreground">{item.value}</p>
                </div>
              ))}
            </div>
          </CardContent>
        </Card>

        {/* Chart */}
        <Card>
          <CardHeader><CardTitle className="text-base">Commissions HT — 6 derniers mois</CardTitle></CardHeader>
          <CardContent>
            <ChartContainer config={chartConfig} className="h-[280px] w-full">
              <BarChart data={chartData}>
                <CartesianGrid strokeDasharray="3 3" className="stroke-border" />
                <XAxis dataKey="label" tick={{ fontSize: 12 }} className="fill-muted-foreground" />
                <YAxis tickFormatter={(v) => `${(v / 1000).toFixed(0)}k`} tick={{ fontSize: 12 }} className="fill-muted-foreground" />
                <ChartTooltip content={<ChartTooltipContent formatter={(value) => formatEur(Number(value))} />} />
                <Bar dataKey="ht" fill="var(--color-ht)" radius={[4, 4, 0, 0]} />
              </BarChart>
            </ChartContainer>
          </CardContent>
        </Card>

        {/* Table par établissement */}
        <Card>
          <CardHeader>
            <CardTitle className="text-base">Par établissement</CardTitle>
          </CardHeader>
          <CardContent className="p-0">
            <div className="overflow-x-auto">
              <Table>
                <TableHeader>
                  <TableRow>
                    {([
                      ['nom', 'Établissement'],
                      ['type', 'Type'],
                      ['nb_missions', 'Nb missions'],
                      ['commissions_ht', 'Commissions HT'],
                      ['commissions_ttc', 'Commissions TTC'],
                      ['impayes', 'Impayés'],
                    ] as [SortKey, string][]).map(([key, label]) => (
                      <TableHead key={key} className="cursor-pointer select-none hover:bg-muted/50" onClick={() => toggleSort(key)}>
                        {label} {sortKey === key ? (sortDir === 'asc' ? '↑' : '↓') : ''}
                      </TableHead>
                    ))}
                    <TableHead>Dernière mission</TableHead>
                  </TableRow>
                </TableHeader>
                <TableBody>
                  {sortedEtab.length === 0 ? (
                    <TableRow><TableCell colSpan={7} className="text-center text-muted-foreground py-8">Aucune donnée</TableCell></TableRow>
                  ) : sortedEtab.map(e => (
                    <TableRow key={e.id} className={e.impayes > 0 ? 'bg-destructive/5' : ''}>
                      <TableCell className="font-medium">{e.nom}</TableCell>
                      <TableCell><Badge variant="secondary" className="text-[10px]">{e.type}</Badge></TableCell>
                      <TableCell>{e.nb_missions}</TableCell>
                      <TableCell>{formatEur(e.commissions_ht)}</TableCell>
                      <TableCell>{formatEur(e.commissions_ttc)}</TableCell>
                      <TableCell className={e.impayes > 0 ? 'text-destructive font-semibold' : ''}>{formatEur(e.impayes)}</TableCell>
                      <TableCell className="text-xs text-muted-foreground">{e.derniere_mission ? formatDate(e.derniere_mission) : '—'}</TableCell>
                    </TableRow>
                  ))}
                </TableBody>
              </Table>
            </div>
          </CardContent>
        </Card>
      </div>
    </LayoutAdmin>
  );
}
