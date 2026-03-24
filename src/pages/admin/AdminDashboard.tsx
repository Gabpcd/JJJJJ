import React, { useState, useEffect, useMemo } from 'react';
import { useNavigate } from 'react-router-dom';
import { usePageTitle } from '@/hooks/usePageTitle';
import { Users, Building2, CheckCircle, Clock, Banknote, TrendingUp, Target, Star, AlertTriangle, FileText, UserPlus, CreditCard, ExternalLink } from 'lucide-react';
import { LayoutAdmin } from '@/components/LayoutAdmin';
import { CarteKPI } from '@/components/CarteKPI';
import { ChargementPage } from '@/components/ChargementPage';
import { supabase } from '@/integrations/supabase/client';
import { ChartContainer, ChartTooltip, ChartTooltipContent } from '@/components/ui/chart';
import { LineChart, Line, XAxis, YAxis, CartesianGrid, BarChart, Bar, AreaChart, Area, ReferenceLine } from 'recharts';
import { Card, CardContent, CardHeader, CardTitle } from '@/components/ui/card';
import { Badge } from '@/components/ui/badge';
import { Input } from '@/components/ui/input';
import { Progress } from '@/components/ui/progress';
import { Separator } from '@/components/ui/separator';

const formatEur = (v: number) => new Intl.NumberFormat('fr-FR', { style: 'currency', currency: 'EUR', maximumFractionDigits: 0 }).format(v);
const formatEurPrecis = (v: number) => new Intl.NumberFormat('fr-FR', { style: 'currency', currency: 'EUR', maximumFractionDigits: 2 }).format(v);
const formatDate = (d: string) => new Date(d).toLocaleDateString('fr-FR', { day: '2-digit', month: 'short' });

const CHARGES_FIXES = [
  { label: 'Supabase', montant: 25 },
  { label: 'Resend', montant: 20 },
  { label: 'Yousign', montant: 50 },
  { label: 'Lovable', montant: 20 },
  { label: 'Apple Developer', montant: 8 },
];
const TOTAL_CHARGES_FIXES_HORS_STRIPE = CHARGES_FIXES.reduce((s, c) => s + c.montant, 0);

function calculerIS(resultat: number): number {
  if (resultat <= 0) return 0;
  if (resultat <= 42500) return resultat * 0.15;
  return 42500 * 0.15 + (resultat - 42500) * 0.25;
}

function ResultatItem({ label, value, negatif }: { label: string; value: number; negatif?: boolean }) {
  const isNeg = value < 0;
  return (
    <div className="rounded-lg border p-3">
      <p className="text-xs text-muted-foreground">{label}</p>
      <p className={`text-lg font-bold ${isNeg || negatif ? 'text-destructive' : 'text-foreground'}`}>
        {formatEur(value)}
      </p>
    </div>
  );
}

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
  const [stripeMoisNb, setStripeMoisNb] = useState(0);
  const [stripeMoisCapture, setStripeMoisCapture] = useState(0);
  const [stripeMoisAttente, setStripeMoisAttente] = useState(0);
  const [connectStats, setConnectStats] = useState<any>(null);

  const [caCommissionsHT, setCaCommissionsHT] = useState(0);
  const [caEncaisse, setCaEncaisse] = useState(0);
  const [tvaCollectee, setTvaCollectee] = useState(0);
  const [nbTransactions, setNbTransactions] = useState(0);
  const [salaireNet, setSalaireNet] = useState(0);
  const [caMensuelData, setCaMensuelData] = useState<{ mois: string; ca_ht: number }[]>([]);

  useEffect(() => {
    async function charger() {
      const today = new Date().toISOString().split('T')[0];
      const [resKpi, resGraph, resSoignants, resEtabs, resLitiges, resFactures, resRentabilite, resEncaisse, resTransactions] = await Promise.all([
        supabase.rpc('fn_admin_kpi' as any),
        supabase.rpc('fn_admin_graphiques' as any),
        supabase.from('soignants').select('id, prenom, nom, profession, cree_le').order('cree_le', { ascending: false }).limit(5),
        supabase.from('etablissements').select('id, nom, type, cree_le').is('supprime_le', null).order('cree_le', { ascending: false }).limit(5),
        supabase.from('litiges').select('id, motif, statut, cree_le, soignant_id, etablissement_id').in('statut', ['OUVERT', 'EN_DISCUSSION']).order('cree_le', { ascending: false }).limit(10),
        supabase
          .from('factures')
          .select('id, numero_facture, montant_ttc, statut, date_echeance, etablissement_id, etablissements(nom)')
          .in('statut', ['EMISE', 'EN_RETARD'])
          .not('date_echeance', 'is', null)
          .lt('date_echeance', today)
          .order('date_echeance', { ascending: true })
          .limit(10),
        supabase
          .from('missions')
          .select('montant_commission_ht, montant_commission_tva, commission_facturee')
          .eq('statut', 'TERMINEE')
          .not('montant_commission_ht', 'is', null),
        supabase
          .from('missions')
          .select('montant_commission_ht')
          .eq('statut', 'TERMINEE')
          .eq('commission_facturee', true)
          .not('montant_commission_ht', 'is', null),
        supabase
          .from('missions')
          .select('id', { count: 'exact', head: true })
          .eq('statut', 'TERMINEE'),
      ]);

      if (resKpi.data) setKpi(resKpi.data);
      if (resGraph.data) {
        setGraphiques(resGraph.data);
        if (resGraph.data.ca_par_mois) setCaMensuelData(resGraph.data.ca_par_mois);
      }
      if (resSoignants.data) setDerniersSoignants(resSoignants.data);
      if (resEtabs.data) setDerniersEtabs(resEtabs.data);
      if (resLitiges.data) setLitiges(resLitiges.data);
      if (resFactures.data) setFacturesImpayees(resFactures.data);

      if (resRentabilite.data) {
        setCaCommissionsHT(resRentabilite.data.reduce((s: number, m: any) => s + (Number(m.montant_commission_ht) || 0), 0));
        setTvaCollectee(resRentabilite.data.reduce((s: number, m: any) => s + (Number(m.montant_commission_tva) || 0), 0));
      }
      if (resEncaisse.data) {
        setCaEncaisse(resEncaisse.data.reduce((s: number, m: any) => s + (Number(m.montant_commission_ht) || 0), 0));
      }
      if (resTransactions.count != null) setNbTransactions(resTransactions.count);

      // Stripe paiements ce mois
      const debutMois = new Date();
      debutMois.setDate(1);
      debutMois.setHours(0, 0, 0, 0);
      const { data: paiements } = await supabase
        .from('paiements_mission')
        .select('montant_ttc, statut')
        .gte('cree_le', debutMois.toISOString());
      if (paiements) {
        setStripeMoisNb(paiements.length);
        setStripeMoisCapture(paiements.filter((p: any) => p.statut === 'CAPTURE').reduce((s: number, p: any) => s + (Number(p.montant_ttc) || 0), 0));
        setStripeMoisAttente(paiements.filter((p: any) => p.statut === 'AUTORISE').reduce((s: number, p: any) => s + (Number(p.montant_ttc) || 0), 0));
      }

      setLoading(false);
    }
    charger();
  }, []);

  const rentabilite = useMemo(() => {
    const nbMois = Math.max(caMensuelData.length, 1);
    const caMensuelMoyen = caCommissionsHT / nbMois;
    const caAnnualise = caMensuelMoyen * 12;

    const stripeMensuel = (caMensuelMoyen * 0.014) + (nbTransactions / nbMois) * 0.25;
    const chargesMensuelles = TOTAL_CHARGES_FIXES_HORS_STRIPE + stripeMensuel;

    const coutSociete = salaireNet * 1.82;
    const chargesAnnuelles = chargesMensuelles * 12;
    const remunerationAnnuelle = coutSociete * 12;

    const resultatAvantIS = caAnnualise - chargesAnnuelles - remunerationAnnuelle;
    const is = calculerIS(resultatAvantIS);
    const resultatNetApresIS = resultatAvantIS - is;
    const dividendes = Math.max(0, resultatNetApresIS);
    const dividendesNets = dividendes * 0.70;
    const salaireNetAnnuel = salaireNet * 12;
    const revenuTotal = salaireNetAnnuel + dividendesNets;

    const seuilRentabilite = chargesAnnuelles + remunerationAnnuelle;
    const progressionSeuil = seuilRentabilite > 0 ? Math.min(100, (caAnnualise / seuilRentabilite) * 100) : 100;
    const seuilAtteint = caAnnualise >= seuilRentabilite;
    const resteAvantSeuil = Math.max(0, seuilRentabilite - caAnnualise);

    const graphResultat = caMensuelData.map((m, i) => {
      const caCumule = caMensuelData.slice(0, i + 1).reduce((s, x) => s + (Number(x.ca_ht) || 0), 0);
      const chargesCumulees = chargesMensuelles * (i + 1);
      const remCumulee = coutSociete * (i + 1);
      return { mois: m.mois, resultat_net: Math.round(caCumule - chargesCumulees - remCumulee) };
    });

    return { stripeMensuel, chargesMensuelles, coutSociete, caAnnualise, chargesAnnuelles, remunerationAnnuelle, resultatAvantIS, is, resultatNetApresIS, dividendes, dividendesNets, salaireNetAnnuel, revenuTotal, seuilRentabilite, progressionSeuil, seuilAtteint, resteAvantSeuil, graphResultat };
  }, [caCommissionsHT, salaireNet, caMensuelData, nbTransactions]);

  if (loading) return <LayoutAdmin><ChargementPage /></LayoutAdmin>;

  const missionChartConfig = { total: { label: 'Missions', color: 'hsl(var(--primary))' } };
  const caChartConfig = { ca_ht: { label: 'CA HT', color: 'hsl(var(--primary))' } };
  const resultatChartConfig = { resultat_net: { label: 'Résultat net cumulé', color: 'hsl(var(--primary))' } };

  return (
    <LayoutAdmin>
      <div className="space-y-6">
        <h1 className="text-2xl font-bold text-foreground">Dashboard Admin</h1>

        {/* KPI Grid */}
        <div className="grid grid-cols-2 lg:grid-cols-4 gap-4">
          <CarteKPI icone={Users} valeur={kpi?.soignants_total ?? '—'} label="Soignants inscrits" sousLabel={`+${kpi?.soignants_semaine ?? 0} cette semaine`} couleurIcone="text-primary" couleurFond="bg-primary/10" lien="/admin/utilisateurs" />
          <CarteKPI icone={Building2} valeur={kpi?.etablissements_total ?? '—'} label="Établissements" sousLabel={`+${kpi?.etablissements_semaine ?? 0} cette semaine`} couleurIcone="text-info" couleurFond="bg-info/10" lien="/admin/utilisateurs" />
          <CarteKPI icone={CheckCircle} valeur={kpi?.missions_terminees_total ?? '—'} label="Missions terminées" sousLabel={`${kpi?.missions_terminees_mois ?? 0} ce mois`} couleurIcone="text-success" couleurFond="bg-success/10" lien="/admin/missions?filtre=TERMINEE" />
          <CarteKPI icone={Clock} valeur={kpi?.missions_ouvertes ?? '—'} label="Missions ouvertes" couleurIcone="text-warning" couleurFond="bg-warning/10" lien="/admin/missions?filtre=OUVERTE" />
          <CarteKPI icone={Banknote} valeur={formatEur(kpi?.ca_commissions_ht_mois ?? 0)} label="CA commissions (contrats signés)" sousLabel={`Potentiel : ${formatEur(kpi?.ca_potentiel_mois ?? 0)} ce mois`} couleurIcone="text-success" couleurFond="bg-success/10" lien="/admin/facturation" />
          <CarteKPI icone={TrendingUp} valeur={formatEur(kpi?.ca_encaisse_total ?? 0)} label="CA encaissé (factures payées)" sousLabel={`Total potentiel : ${formatEur(kpi?.ca_potentiel_total ?? 0)}`} couleurIcone="text-primary" couleurFond="bg-primary/10" lien="/admin/facturation" />
          <CarteKPI icone={Target} valeur={`${kpi?.taux_acceptation_mois ?? 0}%`} label="Taux acceptation ce mois" couleurIcone="text-info" couleurFond="bg-info/10" />
          <CarteKPI icone={Star} valeur={kpi?.score_fiabilite_moyen ? `${kpi.score_fiabilite_moyen}/100` : 'Pas encore d\'évaluation'} label="Score fiabilité moyen" couleurIcone="text-warning" couleurFond="bg-warning/10" lien="/admin/conformite" />
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

        {/* ══════════════ 💰 RENTABILITÉ ══════════════ */}
        <Card className="border-primary/30">
          <CardHeader>
            <CardTitle className="text-lg font-bold flex items-center gap-2">💰 Rentabilité estimée</CardTitle>
          </CardHeader>
          <CardContent className="space-y-6">
            {/* CA */}
            <div className="grid grid-cols-1 md:grid-cols-3 gap-4">
              <div className="rounded-lg bg-muted/50 p-4">
                <p className="text-xs text-muted-foreground">CA commissions HT</p>
                <p className="text-2xl font-bold text-foreground">{formatEur(caCommissionsHT)}</p>
                <p className="text-xs text-muted-foreground mt-1">Encaissé : {formatEur(caEncaisse)}</p>
              </div>
              <div className="rounded-lg bg-muted/50 p-4">
                <p className="text-xs text-muted-foreground">TVA collectée</p>
                <p className="text-2xl font-bold text-foreground">{formatEur(tvaCollectee)}</p>
              </div>
              <div className="rounded-lg bg-muted/50 p-4">
                <p className="text-xs text-muted-foreground">CA annualisé</p>
                <p className="text-2xl font-bold text-primary">{formatEur(rentabilite.caAnnualise)}</p>
              </div>
            </div>

            <Separator />

            {/* Charges fixes */}
            <div>
              <h3 className="text-sm font-semibold text-foreground mb-3">Charges fixes estimées / mois</h3>
              <div className="grid grid-cols-2 sm:grid-cols-3 lg:grid-cols-6 gap-2">
                {CHARGES_FIXES.map((c) => (
                  <div key={c.label} className="rounded-lg border p-3 text-center">
                    <p className="text-xs text-muted-foreground">{c.label}</p>
                    <p className="text-sm font-semibold text-foreground">{c.montant} €</p>
                  </div>
                ))}
                <div className="rounded-lg border p-3 text-center border-warning/50">
                  <p className="text-xs text-muted-foreground">Stripe (1.4%+0.25€)</p>
                  <p className="text-sm font-semibold text-foreground">{formatEurPrecis(rentabilite.stripeMensuel)}</p>
                </div>
              </div>
              <p className="text-sm font-medium text-foreground mt-3">Total mensuel : <span className="font-bold">{formatEurPrecis(rentabilite.chargesMensuelles)}</span></p>
            </div>

            <Separator />

            {/* Rémunération */}
            <div>
              <h3 className="text-sm font-semibold text-foreground mb-3">Rémunération dirigeante</h3>
              <div className="flex flex-col sm:flex-row items-start sm:items-center gap-3">
                <div className="flex items-center gap-2">
                  <label className="text-sm text-muted-foreground whitespace-nowrap">Salaire net mensuel souhaité :</label>
                  <div className="relative">
                    <Input
                      type="number"
                      min={0}
                      step={100}
                      value={salaireNet || ''}
                      onChange={(e) => setSalaireNet(Number(e.target.value) || 0)}
                      className="w-32 pr-8"
                      placeholder="0"
                    />
                    <span className="absolute right-3 top-1/2 -translate-y-1/2 text-sm text-muted-foreground">€</span>
                  </div>
                </div>
                <p className="text-xs text-muted-foreground">Coût société : {formatEurPrecis(rentabilite.coutSociete)} / mois (×1.82)</p>
              </div>
            </div>

            <Separator />

            {/* Résultats */}
            <div className="grid grid-cols-1 sm:grid-cols-2 lg:grid-cols-3 gap-4">
              <ResultatItem label="Résultat avant IS" value={rentabilite.resultatAvantIS} />
              <ResultatItem label="IS estimé" value={-rentabilite.is} negatif />
              <ResultatItem label="Résultat net après IS" value={rentabilite.resultatNetApresIS} />
              <ResultatItem label="Dividendes distribuables" value={rentabilite.dividendes} />
              <ResultatItem label="Dividendes nets (flat tax 30%)" value={rentabilite.dividendesNets} />
              <ResultatItem label="Salaire net annuel" value={rentabilite.salaireNetAnnuel} />
            </div>

            {/* Récap */}
            <div className="rounded-lg bg-primary/5 border border-primary/20 p-4">
              <p className="text-sm font-bold text-foreground">
                Avec un CA de {formatEur(caCommissionsHT)} et un salaire de {formatEur(salaireNet)}/mois, votre revenu total estimé est de <span className="text-primary">{formatEur(rentabilite.revenuTotal)}/an</span>.
              </p>
            </div>

            {/* Seuil */}
            <div>
              <div className="flex items-center justify-between mb-2">
                <h3 className="text-sm font-semibold text-foreground">Seuil de rentabilité</h3>
                {rentabilite.seuilAtteint ? (
                  <Badge className="bg-success text-success-foreground">Seuil atteint ✅</Badge>
                ) : (
                  <span className="text-xs text-muted-foreground">Plus que {formatEur(rentabilite.resteAvantSeuil)} de CA</span>
                )}
              </div>
              <Progress value={rentabilite.progressionSeuil} className="h-3" />
              <p className="text-xs text-muted-foreground mt-1">{Math.round(rentabilite.progressionSeuil)}% — Seuil : {formatEur(rentabilite.seuilRentabilite)} / an</p>
            </div>

            {/* Graphique résultat net cumulé */}
            {rentabilite.graphResultat.length > 0 && (
              <div>
                <h3 className="text-sm font-semibold text-foreground mb-3">Résultat net cumulé par mois</h3>
                <ChartContainer config={resultatChartConfig} className="h-[220px] w-full">
                  <AreaChart data={rentabilite.graphResultat}>
                    <CartesianGrid strokeDasharray="3 3" />
                    <XAxis dataKey="mois" tickFormatter={(v) => new Date(v).toLocaleDateString('fr-FR', { month: 'short' })} fontSize={11} />
                    <YAxis fontSize={11} tickFormatter={(v) => `${v}€`} />
                    <ChartTooltip content={<ChartTooltipContent />} />
                    <ReferenceLine y={0} stroke="hsl(var(--destructive))" strokeDasharray="3 3" />
                    <defs>
                      <linearGradient id="gradientResultat" x1="0" y1="0" x2="0" y2="1">
                        <stop offset="5%" stopColor="hsl(var(--primary))" stopOpacity={0.3} />
                        <stop offset="95%" stopColor="hsl(var(--primary))" stopOpacity={0} />
                      </linearGradient>
                    </defs>
                    <Area type="monotone" dataKey="resultat_net" stroke="hsl(var(--primary))" fill="url(#gradientResultat)" strokeWidth={2} />
                  </AreaChart>
                </ChartContainer>
              </div>
            )}

            <p className="text-xs text-muted-foreground">
              *Estimation indicative SASU. Ne tient pas compte de la CFE, CVAE, ni des spécificités fiscales. Consultez votre expert-comptable.
            </p>
          </CardContent>
        </Card>

        {/* 💳 Stripe paiements */}
        <Card>
          <CardHeader>
            <CardTitle className="text-sm font-medium flex items-center gap-2">
              <CreditCard className="h-4 w-4 text-primary" /> 💳 Paiements Stripe
            </CardTitle>
          </CardHeader>
          <CardContent>
            {stripeMoisNb > 0 ? (
              <div className="space-y-3">
                <div className="grid grid-cols-3 gap-3">
                  <div className="rounded-lg bg-muted/50 p-3 text-center">
                    <p className="text-xs text-muted-foreground">Paiements ce mois</p>
                    <p className="text-xl font-bold text-foreground">{stripeMoisNb}</p>
                  </div>
                  <div className="rounded-lg bg-muted/50 p-3 text-center">
                    <p className="text-xs text-muted-foreground">Encaissé</p>
                    <p className="text-xl font-bold text-success">{formatEur(stripeMoisCapture)}</p>
                  </div>
                  <div className="rounded-lg bg-muted/50 p-3 text-center">
                    <p className="text-xs text-muted-foreground">En attente</p>
                    <p className="text-xl font-bold text-warning">{formatEur(stripeMoisAttente)}</p>
                  </div>
                </div>
                <a href="https://dashboard.stripe.com" target="_blank" rel="noopener noreferrer" className="flex items-center gap-1.5 text-sm text-primary font-medium hover:underline">
                  Ouvrir Stripe Dashboard → <ExternalLink className="h-3.5 w-3.5" />
                </a>
              </div>
            ) : (
              <div className="text-center py-4">
                <p className="text-sm text-muted-foreground">Aucun paiement pour le moment — les paiements apparaîtront quand des missions seront terminées.</p>
                <a href="https://dashboard.stripe.com" target="_blank" rel="noopener noreferrer" className="inline-flex items-center gap-1.5 text-sm text-primary font-medium hover:underline mt-2">
                  Ouvrir Stripe Dashboard → <ExternalLink className="h-3.5 w-3.5" />
                </a>
              </div>
            )}
          </CardContent>
        </Card>

        {/* Lists */}
        <div className="grid md:grid-cols-3 gap-6">
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

          <Card>
            <CardHeader><CardTitle className="text-sm font-medium flex items-center gap-2"><FileText className="h-4 w-4 text-destructive" /> Factures impayées</CardTitle></CardHeader>
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
