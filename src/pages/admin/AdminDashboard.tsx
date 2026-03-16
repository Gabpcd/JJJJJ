import React, { useState, useEffect } from 'react';
import { useNavigate } from 'react-router-dom';
import { usePageTitle } from '@/hooks/usePageTitle';
import { Users, Building2, CheckCircle, Clock, Banknote, TrendingUp, Target, Star, AlertTriangle, FileText, UserPlus } from 'lucide-react';
import { LayoutAdmin } from '@/components/LayoutAdmin';
import { CarteKPI } from '@/components/CarteKPI';
import { ChargementPage } from '@/components/ChargementPage';
import { supabase } from '@/integrations/supabase/client';
import { ChartContainer, ChartTooltip, ChartTooltipContent } from '@/components/ui/chart';
import { LineChart, Line, XAxis, YAxis, CartesianGrid, BarChart, Bar, ResponsiveContainer } from 'recharts';
import { Card, CardContent, CardHeader, CardTitle } from '@/components/ui/card';
import { Badge } from '@/components/ui/badge';

const formatEur = (v: number) => new Intl.NumberFormat('fr-FR', { style: 'currency', currency: 'EUR', maximumFractionDigits: 0 }).format(v);
const formatDate = (d: string) => new Date(d).toLocaleDateString('fr-FR', { day: '2-digit', month: 'short' });

export default function AdminDashboard() {
  usePageTitle('Admin');
  const navigate = useNavigate();
  const [kpi, setKpi] = useState<any>(null);
  const [graphiques, setGraphiques] = useState<any>(null);
  const [derniersSoignants, setDerniersSoignants] = useState<any[]>([]);
  const [derniersEtabs, setDerniersEtabs] = useState<any[]>([]);
  const [litiges, setLitiges] = useState<any[]>([]);
  const [facturesImpayees, setFacturesImpayees] = useState<any[]>([]);
  const [loading, setLoading] = useState(true);

  useEffect(() => {
    async function charger() {
      const [resKpi, resGraph, resSoignants, resEtabs, resLitiges, resFactures] = await Promise.all([
        supabase.rpc('fn_admin_kpi' as any),
        supabase.rpc('fn_admin_graphiques' as any),
        supabase.from('soignants').select('id, prenom, nom, profession, cree_le').order('cree_le', { ascending: false }).limit(5),
        supabase.from('etablissements').select('id, nom, type, cree_le').is('supprime_le', null).order('cree_le', { ascending: false }).limit(5),
        supabase.from('litiges').select('id, motif, statut, cree_le, soignant_id, etablissement_id').in('statut', ['OUVERT', 'EN_DISCUSSION']).order('cree_le', { ascending: false }).limit(10),
        supabase.from('factures').select('id, numero_facture, montant_ttc, statut, date_echeance, etablissement_id, etablissements(nom)').eq('statut', 'EMISE').lt('date_echeance', new Date(Date.now() - 30 * 86400000).toISOString().split('T')[0]).order('date_echeance', { ascending: true }).limit(10),
      ]);

      if (resKpi.data) setKpi(resKpi.data);
      if (resGraph.data) setGraphiques(resGraph.data);
      if (resSoignants.data) setDerniersSoignants(resSoignants.data);
      if (resEtabs.data) setDerniersEtabs(resEtabs.data);
      if (resLitiges.data) setLitiges(resLitiges.data);
      if (resFactures.data) setFacturesImpayees(resFactures.data);
      setLoading(false);
    }
    charger();
  }, []);

  if (loading) return <LayoutAdmin><ChargementPage /></LayoutAdmin>;

  const missionChartConfig = { total: { label: 'Missions', color: 'hsl(var(--primary))' } };
  const caChartConfig = { ca_ht: { label: 'CA HT', color: 'hsl(var(--primary))' } };

  return (
    <LayoutAdmin>
      <div className="space-y-6">
        <h1 className="text-2xl font-bold text-foreground">Dashboard Admin</h1>

        {/* KPI Grid 4x2 */}
        <div className="grid grid-cols-2 lg:grid-cols-4 gap-4">
          <CarteKPI icone={Users} valeur={kpi?.soignants_total ?? '—'} label="Soignants inscrits" sousLabel={`+${kpi?.soignants_semaine ?? 0} cette semaine`} couleurIcone="text-primary" couleurFond="bg-primary/10" lien="/admin/utilisateurs" />
          <CarteKPI icone={Building2} valeur={kpi?.etablissements_total ?? '—'} label="Établissements" sousLabel={`+${kpi?.etablissements_semaine ?? 0} cette semaine`} couleurIcone="text-info" couleurFond="bg-info/10" lien="/admin/utilisateurs" />
          <CarteKPI icone={CheckCircle} valeur={kpi?.missions_terminees_total ?? '—'} label="Missions terminées" sousLabel={`${kpi?.missions_terminees_mois ?? 0} ce mois`} couleurIcone="text-success" couleurFond="bg-success/10" lien="/admin/moderation" />
          <CarteKPI icone={Clock} valeur={kpi?.missions_ouvertes ?? '—'} label="Missions ouvertes" couleurIcone="text-warning" couleurFond="bg-warning/10" lien="/admin/moderation" />
          <CarteKPI icone={Banknote} valeur={formatEur(kpi?.ca_commissions_ht_mois ?? 0)} label="CA commissions (contrats signés)" sousLabel={`Potentiel : ${formatEur(kpi?.ca_potentiel_mois ?? 0)} ce mois`} couleurIcone="text-success" couleurFond="bg-success/10" lien="/admin/facturation" />
          <CarteKPI icone={TrendingUp} valeur={formatEur(kpi?.ca_encaisse_total ?? 0)} label="CA encaissé (factures payées)" sousLabel={`Total potentiel : ${formatEur(kpi?.ca_potentiel_total ?? 0)}`} couleurIcone="text-primary" couleurFond="bg-primary/10" lien="/admin/facturation" />
          <CarteKPI icone={Target} valeur={`${kpi?.taux_acceptation_mois ?? 0}%`} label="Taux acceptation ce mois" couleurIcone="text-info" couleurFond="bg-info/10" />
          <CarteKPI icone={Star} valeur={`${kpi?.score_fiabilite_moyen ?? 0}/100`} label="Score fiabilité moyen" couleurIcone="text-warning" couleurFond="bg-warning/10" lien="/admin/conformite" />
        </div>

        {/* Charts */}
        <div className="grid md:grid-cols-2 gap-6">
          <Card>
            <CardHeader><CardTitle className="text-sm font-medium">Missions terminées / semaine</CardTitle></CardHeader>
            <CardContent>
              <ChartContainer config={missionChartConfig} className="h-[250px] w-full">
                <LineChart data={graphiques?.missions_par_semaine ?? []}>
                  <CartesianGrid strokeDasharray="3 3" />
                  <XAxis dataKey="semaine" tickFormatter={(v) => formatDate(v)} fontSize={11} />
                  <YAxis fontSize={11} />
                  <ChartTooltip content={<ChartTooltipContent />} />
                  <Line type="monotone" dataKey="total" stroke="hsl(var(--primary))" strokeWidth={2} dot={{ r: 3 }} />
                </LineChart>
              </ChartContainer>
            </CardContent>
          </Card>
          <Card>
            <CardHeader><CardTitle className="text-sm font-medium">CA mensuel HT</CardTitle></CardHeader>
            <CardContent>
              <ChartContainer config={caChartConfig} className="h-[250px] w-full">
                <BarChart data={graphiques?.ca_par_mois ?? []}>
                  <CartesianGrid strokeDasharray="3 3" />
                  <XAxis dataKey="mois" tickFormatter={(v) => new Date(v).toLocaleDateString('fr-FR', { month: 'short' })} fontSize={11} />
                  <YAxis fontSize={11} tickFormatter={(v) => `${v}€`} />
                  <ChartTooltip content={<ChartTooltipContent />} />
                  <Bar dataKey="ca_ht" fill="hsl(var(--primary))" radius={[4, 4, 0, 0]} />
                </BarChart>
              </ChartContainer>
            </CardContent>
          </Card>
        </div>

        {/* Lists */}
        <div className="grid md:grid-cols-3 gap-6">
          {/* Dernières inscriptions */}
          <Card>
            <CardHeader><CardTitle className="text-sm font-medium flex items-center gap-2"><UserPlus className="h-4 w-4" /> Dernières inscriptions</CardTitle></CardHeader>
            <CardContent className="space-y-3">
              {derniersSoignants.map((s) => (
                <div key={s.id} className="flex justify-between items-center text-sm">
                  <div>
                    <span className="font-medium text-foreground">{s.prenom} {s.nom}</span>
                    <Badge variant="outline" className="ml-2 text-[10px]">{s.profession}</Badge>
                  </div>
                  <span className="text-muted-foreground text-xs">{formatDate(s.cree_le)}</span>
                </div>
              ))}
              {derniersSoignants.length === 0 && <p className="text-sm text-muted-foreground">Aucun</p>}
              <div className="border-t pt-2 mt-2" />
              {derniersEtabs.map((e) => (
                <div key={e.id} className="flex justify-between items-center text-sm">
                  <div>
                    <span className="font-medium text-foreground">{e.nom}</span>
                    <Badge variant="outline" className="ml-2 text-[10px]">{e.type}</Badge>
                  </div>
                  <span className="text-muted-foreground text-xs">{formatDate(e.cree_le)}</span>
                </div>
              ))}
              {derniersEtabs.length === 0 && <p className="text-sm text-muted-foreground">Aucun</p>}
            </CardContent>
          </Card>

          {/* Litiges ouverts */}
          <Card>
            <CardHeader><CardTitle className="text-sm font-medium flex items-center gap-2"><AlertTriangle className="h-4 w-4 text-warning" /> Litiges ouverts</CardTitle></CardHeader>
            <CardContent className="space-y-3">
              {litiges.map((l) => (
                <div key={l.id} className="text-sm cursor-pointer hover:bg-muted/50 rounded p-1.5 -mx-1.5" onClick={() => navigate('/admin/moderation')}>
                  <p className="font-medium text-foreground line-clamp-1">{l.motif}</p>
                  <div className="flex gap-2 mt-1">
                    <Badge variant={l.statut === 'OUVERT' ? 'destructive' : 'secondary'} className="text-[10px]">{l.statut}</Badge>
                    <span className="text-muted-foreground text-xs">{formatDate(l.cree_le)}</span>
                  </div>
                </div>
              ))}
              {litiges.length === 0 && <p className="text-sm text-muted-foreground">Aucun litige ouvert</p>}
            </CardContent>
          </Card>

          {/* Factures impayées > 30j */}
          <Card>
            <CardHeader><CardTitle className="text-sm font-medium flex items-center gap-2"><FileText className="h-4 w-4 text-destructive" /> Factures impayées &gt; 30j</CardTitle></CardHeader>
            <CardContent className="space-y-3">
              {facturesImpayees.map((f: any) => (
                <div key={f.id} className="text-sm cursor-pointer hover:bg-muted/50 rounded p-1.5 -mx-1.5" onClick={() => navigate('/admin/facturation')}>
                  <div className="flex justify-between">
                    <span className="font-medium text-foreground">{f.numero_facture}</span>
                    <span className="font-semibold text-destructive">{formatEur(f.montant_ttc)}</span>
                  </div>
                  <p className="text-xs text-muted-foreground mt-0.5">{(f.etablissements as any)?.nom ?? '—'} · Échue le {formatDate(f.date_echeance)}</p>
                </div>
              ))}
              {facturesImpayees.length === 0 && <p className="text-sm text-muted-foreground">Aucune</p>}
            </CardContent>
          </Card>
        </div>
      </div>
    </LayoutAdmin>
  );
}
