import React, { useState, useEffect, useMemo } from 'react';
import { useNavigate } from 'react-router-dom';
import { usePageTitle } from '@/hooks/usePageTitle';
import { Users, Building2, CheckCircle, Clock, Banknote, TrendingUp, Target, AlertTriangle, FileText, UserPlus, CreditCard, ExternalLink, ShieldCheck, FlaskConical, ChevronDown } from 'lucide-react';
import { LayoutAdmin } from '@/components/LayoutAdmin';
import { CarteKPIY2K } from '@/components/y2k/CarteKPIY2K';
import { ChargementAdmin } from '@/components/admin/ChargementAdmin';
import { supabase } from '@/integrations/supabase/client';
import { ChartContainer, ChartTooltip, ChartTooltipContent } from '@/components/ui/chart';
import { LineChart, Line, XAxis, YAxis, CartesianGrid, BarChart, Bar, AreaChart, Area, ReferenceLine } from 'recharts';
import {
  CardY2K,
  CardY2KHeader,
  CardY2KTitle,
  CardY2KContent,
} from '@/components/y2k/CardY2K';
import { BadgeY2K } from '@/components/y2k/BadgeY2K';
import { getLabelProfession, getLabelTypeEtablissement } from '@/lib/constantes';
import { Input } from '@/components/ui/input';
import { Progress } from '@/components/ui/progress';
import { Separator } from '@/components/ui/separator';
import { BandeauAlertesAntiTricheAdmin } from '@/components/admin/BandeauAlertesAntiTricheAdmin';
import { formatEuroAdmin } from '@/lib/adminPresentation';
import { jourCivilParis } from '@/lib/adminInvoiceAccounting';

const formatEur = (v: number) => formatEuroAdmin(v, { decimales: 0 });
const formatEurPrecis = (v: number) => formatEuroAdmin(v, { decimales: 2 });
const formatDate = (d: string) => new Date(d).toLocaleDateString('fr-FR', { day: '2-digit', month: 'short' }).replace(/ /g, '\u00a0');

// Libellés humains des statuts de litige affichés (alignés sur FilDiscussionLitige)
const STATUTS_LITIGE_LABELS: Record<string, string> = {
  OUVERT: 'Ouvert',
  EN_DISCUSSION: 'En discussion',
  EN_MEDIATION: 'Médiation Jolene',
  CONTESTEE: 'Contesté',
};

// Monthly fixed costs in EUR — update when subscription plans change
const CHARGES_FIXES = [
  { label: 'Supabase', montant: 25 },   // Pro plan (database + auth + storage)
  { label: 'Resend', montant: 20 },      // Transactional email service
  { label: 'Lovable', montant: 20 },     // AI dev tool subscription
  { label: 'Apple Developer', montant: 8 }, // ~99 USD/year ÷ 12 months
];
const TOTAL_CHARGES_FIXES_HORS_STRIPE = CHARGES_FIXES.reduce((s, c) => s + c.montant, 0);

// French corporate tax (IS) rates for SASU — 2024-2026 schedule
// - 15% reduced rate on first 42 500 EUR of profit (PME benefit)
// - 25% standard rate on profit above 42 500 EUR
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
  // Source UNIQUE de toutes les métriques d'argent (fn_admin_metriques_argent) —
  // KPI, carte rentabilité et alertes lisent cet objet, jamais un calcul local
  // divergent. Chaque montant a un split réel / test (est_compte_test) + HT/TTC.
  const [argent, setArgent] = useState<any>(null);
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

  const [salaireNet, setSalaireNet] = useState(0);
  const [caMensuelData, setCaMensuelData] = useState<{ mois: string; ca_ht: number }[]>([]);

  useEffect(() => {
    async function charger() {
      const maintenant = new Date();
      const aujourdhuiIso = jourCivilParis(maintenant)
        ?? maintenant.toISOString().slice(0, 10);
      const [resKpi, resArgent, resGraph, resSoignants, resEtabs, resLitiges, resFactures] = await Promise.all([
        supabase.rpc('fn_admin_kpi' as any),
        supabase.rpc('fn_admin_metriques_argent' as any),
        supabase.rpc('fn_admin_graphiques' as any),
        supabase.from('soignants').select('id, prenom, nom, profession, cree_le').order('cree_le', { ascending: false }).limit(5),
        supabase.from('etablissements').select('id, nom, type, cree_le').is('supprime_le', null).order('cree_le', { ascending: false }).limit(5),
        supabase.from('litiges').select('id, motif, statut, cree_le, soignant_id, etablissement_id').in('statut', ['OUVERT', 'EN_DISCUSSION', 'EN_MEDIATION', 'CONTESTEE']).order('cree_le', { ascending: false }).limit(10),
        supabase
          .from('factures')
          .select('id, numero_facture, montant_ttc, statut, date_echeance, etablissement_id, type_document, etablissements!inner(nom, est_compte_test)')
          .eq('type_document', 'FACTURE')
          .in('statut', ['EMISE', 'EN_RETARD'])
          .lt('date_echeance', aujourdhuiIso)
          .eq('etablissements.est_compte_test', false)
          .order('date_echeance', { ascending: true })
          .limit(10),
      ]);

      if (resKpi.data) setKpi(resKpi.data);
      if (resArgent.data && !(resArgent.data as any).error) setArgent(resArgent.data);
      if (resGraph.data) {
        setGraphiques(resGraph.data);
        if (resGraph.data.ca_par_mois) setCaMensuelData(resGraph.data.ca_par_mois);
      }
      if (resSoignants.data) setDerniersSoignants(resSoignants.data);
      if (resEtabs.data) setDerniersEtabs(resEtabs.data);
      if (resLitiges.data) setLitiges(resLitiges.data);
      if (resFactures.data) setFacturesImpayees(resFactures.data);

      // Stripe paiements ce mois (rail paiements_mission — vue opérationnelle brute TTC,
      // distincte de « Encaissé commission » qui vient de la source unique).
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

      // Stripe Connect stats
      const { data: csData } = await supabase.rpc('fn_admin_stripe_connect_stats' as any);
      if (csData) setConnectStats(csData);

      setLoading(false);
    }
    charger();
  }, []);

  // ── Dérivés de la SOURCE UNIQUE (jamais recalculés localement) ────────────────
  const caCommissionsHT = Number(argent?.commission?.total_reel ?? 0); // réel HT
  const caEncaisse = Number(argent?.encaisse?.ht_reel ?? 0);           // réel HT (cash)
  const caEncaisseTTC = Number(argent?.encaisse?.ttc_reel ?? 0);
  const tvaCollectee = Number(argent?.commission?.tva_reel ?? 0);
  const nbTransactions = Number(argent?.nb_missions_terminees_reel ?? 0);
  const nbEtabsAVerifier = Number(argent?.etab_a_valider ?? 0);
  const aDesDonneesTest = Boolean(argent?.a_des_donnees_test);
  const nbMissionsTest = Number(argent?.nb_missions_terminees_test ?? 0);
  const commissionTestTotal = Number(argent?.commission?.total_test ?? 0);
  const gmvTestTotal = Number(argent?.gmv?.total_test ?? 0);

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

  if (loading) return <LayoutAdmin><ChargementAdmin titre="Tableau de bord" /></LayoutAdmin>;

  const missionChartConfig = { total: { label: 'Missions', color: 'hsl(var(--primary))' } };
  const caChartConfig = { ca_ht: { label: 'CA HT', color: 'hsl(var(--primary))' } };
  const resultatChartConfig = { resultat_net: { label: 'Résultat net cumulé', color: 'hsl(var(--primary))' } };

  return (
    <LayoutAdmin>
      <div className="space-y-6">
        <header className="flex flex-col gap-3 border-b border-border pb-5 sm:flex-row sm:items-end sm:justify-between">
          <div>
            <p className="text-xs font-semibold uppercase tracking-wide text-primary">Pilotage quotidien</p>
            <h1 className="mt-1 text-2xl font-bold text-foreground">Tableau de bord</h1>
            <p className="mt-1 max-w-2xl text-sm text-muted-foreground">
              Suivez l’activité, traitez les urgences, puis ouvrez les analyses détaillées seulement quand vous en avez besoin.
            </p>
          </div>
          <div className="inline-flex w-fit items-center gap-2 rounded-lg border border-border bg-muted/30 px-3 py-2 text-sm text-muted-foreground">
            <UserPlus className="h-4 w-4 text-primary" aria-hidden="true" />
            <strong className="text-foreground">{(kpi?.soignants_semaine ?? 0) + (kpi?.etablissements_semaine ?? 0)}</strong>
            nouveaux comptes cette semaine
          </div>
        </header>

        <BandeauAlertesAntiTricheAdmin />

        <section aria-labelledby="dashboard-activity-title" className="space-y-3">
          <div>
            <h2 id="dashboard-activity-title" className="text-lg font-semibold text-foreground">Activité principale</h2>
            <p className="text-sm text-muted-foreground">Les quatre indicateurs utiles pour piloter l’offre et la demande.</p>
          </div>
          <div className="grid grid-cols-2 gap-4 lg:grid-cols-4">
            <CarteKPIY2K
              icone={<Clock className="h-4 w-4" />}
              valeur={kpi?.missions_ouvertes ?? '—'}
              label="Missions ouvertes"
              variant="holographic"
              onClick={() => navigate('/admin/missions?filtre=OUVERTE')}
            />
            <CarteKPIY2K
              icone={<CheckCircle className="h-4 w-4" />}
              valeur={kpi?.missions_terminees_total ?? '—'}
              label="Missions terminées"
              contexte={`${kpi?.missions_terminees_mois ?? 0} ce mois`}
              variant="default"
              onClick={() => navigate('/admin/missions?filtre=TERMINEE')}
            />
            <CarteKPIY2K
              icone={<Users className="h-4 w-4" />}
              valeur={kpi?.soignants_total ?? '—'}
              label="Soignants inscrits"
              contexte={`+${kpi?.soignants_semaine ?? 0} cette semaine`}
              variant="default"
              onClick={() => navigate('/admin/utilisateurs')}
            />
            <CarteKPIY2K
              icone={<Building2 className="h-4 w-4" />}
              valeur={kpi?.etablissements_total ?? '—'}
              label="Établissements"
              contexte={`+${kpi?.etablissements_semaine ?? 0} cette semaine`}
              variant="default"
              onClick={() => navigate('/admin/utilisateurs')}
            />
          </div>
        </section>

        {/* Alertes et actions urgentes */}
        <section aria-labelledby="dashboard-actions-title" className="space-y-3">
          <div>
            <h2 id="dashboard-actions-title" className="text-lg font-semibold text-foreground">À traiter maintenant</h2>
            <p className="text-sm text-muted-foreground">Les éléments qui nécessitent une décision ou une vérification.</p>
          </div>
          <div className="grid grid-cols-1 gap-3 md:grid-cols-2 xl:grid-cols-4">
          {nbEtabsAVerifier > 0 && (
            <button type="button" className="w-full rounded-xl border-2 border-primary/40 bg-primary/5 p-4 text-left cursor-pointer hover:border-primary/60 transition-colors" onClick={() => navigate('/admin/verification-etablissements')}>
              <div className="flex items-center gap-2 mb-2">
                <ShieldCheck className="h-5 w-5 text-primary" />
                <span className="font-bold text-foreground">{nbEtabsAVerifier} établissement{nbEtabsAVerifier > 1 ? 's' : ''} à valider</span>
              </div>
              <p className="text-xs text-muted-foreground">Vérification rattachement / cohérence →</p>
            </button>
          )}
          {litiges.length > 0 && (
            <button type="button" className="w-full rounded-xl border-2 border-warning/40 bg-warning/5 p-4 text-left cursor-pointer hover:border-warning/60 transition-colors" onClick={() => navigate('/admin/moderation')}>

              <div className="flex items-center gap-2 mb-2">
                <AlertTriangle className="h-5 w-5 text-warning" />
                <span className="font-bold text-foreground">{litiges.length} litige{litiges.length > 1 ? 's' : ''} ouvert{litiges.length > 1 ? 's' : ''}</span>
              </div>
              <p className="text-xs text-muted-foreground">Requiert votre attention →</p>
            </button>
          )}
          {facturesImpayees.length > 0 && (
            <button type="button" className="w-full rounded-xl border-2 border-destructive/40 bg-destructive/5 p-4 text-left cursor-pointer hover:border-destructive/60 transition-colors" onClick={() => navigate('/admin/impayees')}>
              <div className="flex items-center gap-2 mb-2">
                <CreditCard className="h-5 w-5 text-destructive" />
                <span className="font-bold text-foreground">{facturesImpayees.length} facture{facturesImpayees.length > 1 ? 's' : ''} impayée{facturesImpayees.length > 1 ? 's' : ''}</span>
              </div>
              <p className="text-xs text-muted-foreground">En retard de paiement →</p>
            </button>
          )}
          {nbEtabsAVerifier === 0 && litiges.length === 0 && facturesImpayees.length === 0 && (
            <div className="rounded-xl border border-success/30 bg-success/5 p-4">
              <div className="mb-2 flex items-center gap-2">
                <CheckCircle className="h-5 w-5 text-success" aria-hidden="true" />
                <span className="font-bold text-foreground">Aucune urgence détectée</span>
              </div>
              <p className="text-xs text-muted-foreground">Les files prioritaires sont à jour.</p>
            </div>
          )}
          <button type="button" className="w-full rounded-xl border border-border bg-card p-4 text-left cursor-pointer hover:border-primary/30 transition-colors" onClick={() => navigate('/admin/conformite')}>
            <div className="flex items-center gap-2 mb-2">
              <Target className="h-5 w-5 text-primary" />
              <span className="font-bold text-foreground">{kpi?.taux_acceptation_mois ?? 0}% d'acceptation</span>
            </div>
            <p className="text-xs text-muted-foreground">Taux ce mois · Conformité →</p>
          </button>
          </div>
        </section>

        {/* Les données de test restent visibles et identifiées, mais sont exclues
            des montants de production présentés ci-dessous. */}
        {aDesDonneesTest && (
          <div className="rounded-lg border border-warning/40 bg-warning/5 px-3 py-2 text-xs text-foreground flex items-start gap-2">
            <FlaskConical className="h-4 w-4 text-warning shrink-0 mt-0.5" />
            <span>
              <strong>Données de test présentes</strong> — les montants ci-dessous <strong>excluent</strong> les comptes de test.
              {nbMissionsTest > 0 && ` ${nbMissionsTest} mission${nbMissionsTest > 1 ? 's' : ''} test`}
              {commissionTestTotal > 0 && ` · commission test ${formatEur(commissionTestTotal)} HT`}
              {gmvTestTotal > 0 && ` · GMV test ${formatEur(gmvTestTotal)}`}
              {'. Elles restent identifiées et exclues des indicateurs de production.'}
            </span>
          </div>
        )}

        <section aria-labelledby="dashboard-details-title" className="space-y-3">
          <div>
            <h2 id="dashboard-details-title" className="text-lg font-semibold text-foreground">Analyses et détails</h2>
            <p className="text-sm text-muted-foreground">Ouvrez seulement le volet nécessaire à votre analyse.</p>
          </div>

          <details className="group rounded-xl border border-border bg-card">
            <summary className="flex cursor-pointer list-none items-center justify-between gap-4 p-4 focus-visible:outline-none focus-visible:ring-2 focus-visible:ring-primary [&::-webkit-details-marker]:hidden">
              <span className="flex min-w-0 items-center gap-3">
                <Banknote className="h-5 w-5 shrink-0 text-primary" aria-hidden="true" />
                <span>
                  <span className="block font-semibold text-foreground">Finances et volume d’activité</span>
                  <span className="block text-sm text-muted-foreground">Commission ce mois : {formatEur(argent?.commission?.mois_reel ?? 0)} HT</span>
                </span>
              </span>
              <ChevronDown className="h-5 w-5 shrink-0 text-muted-foreground transition-transform group-open:rotate-180" aria-hidden="true" />
            </summary>
            <div className="space-y-4 border-t border-border p-4">
              <p className="rounded-lg bg-muted/30 px-3 py-2 text-xs text-muted-foreground">
                <strong className="text-foreground">Commission Jolene</strong> = ce que vous gardez (commission facturée aux établissements, HT).
                <strong className="text-foreground"> GMV</strong> = volume brut des missions (argent qui passe par la plateforme mais va aux soignants — vous ne le touchez pas).
              </p>
              <div className="grid overflow-hidden rounded-lg border border-border sm:grid-cols-3">
                <button type="button" className="p-4 text-left transition-colors hover:bg-muted/40 sm:border-r sm:border-border" onClick={() => navigate('/admin/finances')}>
                  <span className="block text-xs text-muted-foreground">Commission Jolene ce mois (HT)</span>
                  <strong className="mt-1 block text-xl text-foreground">{formatEur(argent?.commission?.mois_reel ?? 0)}</strong>
                  <span className="mt-1 block text-xs text-muted-foreground">Facturable : {formatEur(argent?.facturable?.ht_reel ?? 0)} HT</span>
                </button>
                <button type="button" className="border-t border-border p-4 text-left transition-colors hover:bg-muted/40 sm:border-l-0 sm:border-t-0 sm:border-r" onClick={() => navigate('/admin/facturation')}>
                  <span className="block text-xs text-muted-foreground">Encaissé (commission, HT)</span>
                  <strong className="mt-1 block text-xl text-foreground">{formatEur(caEncaisse)}</strong>
                  <span className="mt-1 block text-xs text-muted-foreground">{formatEur(caEncaisseTTC)} TTC · sur compte</span>
                </button>
                <button type="button" className="border-t border-border p-4 text-left transition-colors hover:bg-muted/40 sm:border-t-0" onClick={() => navigate('/admin/missions')}>
                  <span className="block text-xs text-muted-foreground">GMV (volume brut transité)</span>
                  <strong className="mt-1 block text-xl text-foreground">{formatEur(argent?.gmv?.total_reel ?? 0)}</strong>
                  <span className="mt-1 block text-xs text-muted-foreground">Ce mois : {formatEur(argent?.gmv?.mois_reel ?? 0)}</span>
                </button>
              </div>
            </div>
          </details>

          <details className="group rounded-xl border border-border bg-card">
            <summary className="flex cursor-pointer list-none items-center justify-between gap-4 p-4 focus-visible:outline-none focus-visible:ring-2 focus-visible:ring-primary [&::-webkit-details-marker]:hidden">
              <span className="flex min-w-0 items-center gap-3">
                <TrendingUp className="h-5 w-5 shrink-0 text-primary" aria-hidden="true" />
                <span>
                  <span className="block font-semibold text-foreground">Tendances d’activité</span>
                  <span className="block text-sm text-muted-foreground">Missions terminées et chiffre d’affaires mensuel</span>
                </span>
              </span>
              <ChevronDown className="h-5 w-5 shrink-0 text-muted-foreground transition-transform group-open:rotate-180" aria-hidden="true" />
            </summary>
            <div className="grid gap-6 border-t border-border p-4 md:grid-cols-2">
              <div>
                <h3 className="mb-3 text-sm font-medium text-foreground">Missions terminées / semaine</h3>
                <ChartContainer config={missionChartConfig} className="h-[250px] w-full">
                  <LineChart data={graphiques?.missions_par_semaine ?? []}>
                    <CartesianGrid strokeDasharray="3 3" />
                    <XAxis dataKey="semaine" tickFormatter={(v) => formatDate(v)} fontSize={11} />
                    <YAxis fontSize={11} />
                    <ChartTooltip content={<ChartTooltipContent />} />
                    <Line type="monotone" dataKey="total" stroke="hsl(var(--primary))" strokeWidth={2} dot={{ r: 3 }} />
                  </LineChart>
                </ChartContainer>
              </div>
              <div>
                <h3 className="mb-3 text-sm font-medium text-foreground">CA mensuel HT</h3>
                <ChartContainer config={caChartConfig} className="h-[250px] w-full">
                  <BarChart data={graphiques?.ca_par_mois ?? []}>
                    <CartesianGrid strokeDasharray="3 3" />
                    <XAxis dataKey="mois" tickFormatter={(v) => new Date(v).toLocaleDateString('fr-FR', { month: 'short' })} fontSize={11} />
                    <YAxis fontSize={11} tickFormatter={(v) => `${v}€`} />
                    <ChartTooltip content={<ChartTooltipContent />} />
                    <Bar dataKey="ca_ht" fill="hsl(var(--primary))" radius={[4, 4, 0, 0]} />
                  </BarChart>
                </ChartContainer>
              </div>
            </div>
          </details>

          {/* Rentabilité */}
          <details className="group rounded-xl border border-primary/30 bg-card">
            <summary className="flex cursor-pointer list-none items-center justify-between gap-4 p-4 focus-visible:outline-none focus-visible:ring-2 focus-visible:ring-primary [&::-webkit-details-marker]:hidden">
              <span className="flex min-w-0 items-center gap-3">
                <TrendingUp className="h-5 w-5 shrink-0 text-primary" aria-hidden="true" />
                <span>
                  <span className="block font-semibold text-foreground">Rentabilité estimée</span>
                  <span className="block text-sm text-muted-foreground">CA annualisé : {formatEur(rentabilite.caAnnualise)} · seuil {Math.round(rentabilite.progressionSeuil)}%</span>
                </span>
              </span>
              <ChevronDown className="h-5 w-5 shrink-0 text-muted-foreground transition-transform group-open:rotate-180" aria-hidden="true" />
            </summary>
            <div className="space-y-6 border-t border-border p-4">
            {/* CA — mêmes chiffres que les KPI ci-dessus (source unique fn_admin_metriques_argent) */}
            <div className="grid grid-cols-1 md:grid-cols-3 gap-4">
              <div className="rounded-lg bg-muted/50 p-4">
                <p className="text-xs text-muted-foreground">CA commissions (HT)</p>
                <p className="text-2xl font-bold text-foreground">{formatEur(caCommissionsHT)}</p>
                <p className="text-xs text-muted-foreground mt-1">Encaissé : {formatEur(caEncaisse)} HT</p>
              </div>
              <div className="rounded-lg bg-muted/50 p-4">
                <p className="text-xs text-muted-foreground">TVA collectée</p>
                <p className="text-2xl font-bold text-foreground">{formatEur(tvaCollectee)}</p>
              </div>
              <div className="rounded-lg bg-muted/50 p-4">
                <p className="text-xs text-muted-foreground">CA annualisé (HT)</p>
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
                  <label htmlFor="admin-salaire-net" className="text-sm text-muted-foreground whitespace-nowrap">Salaire net mensuel souhaité :</label>
                  <div className="relative">
                    <Input
                      id="admin-salaire-net"
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
                <p className="text-xs text-muted-foreground" title="Estimation du salaire net majoré des cotisations employeur et salarié.">
                  Coût société estimé : {formatEurPrecis(rentabilite.coutSociete)} / mois (net × 1,82, charges incluses)
                </p>
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
                  <BadgeY2K variant="success" icone={<CheckCircle className="h-3 w-3" />}>Seuil atteint</BadgeY2K>
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
              Estimation indicative SASU, à confirmer avec votre expert-comptable.
            </p>
            </div>
          </details>

          {/* Stripe paiements — vue opérationnelle brute (TTC), distincte de « Encaissé commission ». */}
          <details className="group rounded-xl border border-border bg-card">
            <summary className="flex cursor-pointer list-none items-center justify-between gap-4 p-4 focus-visible:outline-none focus-visible:ring-2 focus-visible:ring-primary [&::-webkit-details-marker]:hidden">
              <span className="flex min-w-0 items-center gap-3">
                <CreditCard className="h-5 w-5 shrink-0 text-primary" aria-hidden="true" />
                <span>
                  <span className="block font-semibold text-foreground">Paiements Stripe et Connect</span>
                  <span className="block text-sm text-muted-foreground">{stripeMoisNb} paiement{stripeMoisNb > 1 ? 's' : ''} ce mois · {formatEur(stripeMoisCapture)} capturé TTC</span>
                </span>
              </span>
              <ChevronDown className="h-5 w-5 shrink-0 text-muted-foreground transition-transform group-open:rotate-180" aria-hidden="true" />
            </summary>
            <div className="space-y-6 border-t border-border p-4">
              <section aria-labelledby="dashboard-stripe-payments-title">
                <h3 id="dashboard-stripe-payments-title" className="mb-3 text-sm font-semibold text-foreground">Paiements Stripe bruts (TTC)</h3>
                {stripeMoisNb > 0 ? (
                  <div className="space-y-3">
                    <div className="grid overflow-hidden rounded-lg border border-border sm:grid-cols-3">
                      <div className="p-3 text-center sm:border-r sm:border-border">
                        <p className="text-xs text-muted-foreground">Paiements ce mois</p>
                        <p className="text-xl font-bold text-foreground">{stripeMoisNb}</p>
                      </div>
                      <div className="border-t border-border p-3 text-center sm:border-t-0 sm:border-r">
                        <p className="text-xs text-muted-foreground">Capturé (TTC brut)</p>
                        <p className="text-xl font-bold text-success">{formatEur(stripeMoisCapture)}</p>
                      </div>
                      <div className="border-t border-border p-3 text-center sm:border-t-0">
                        <p className="text-xs text-muted-foreground">En attente (TTC)</p>
                        <p className="text-xl font-bold text-warning">{formatEur(stripeMoisAttente)}</p>
                      </div>
                    </div>
                    <a href="https://dashboard.stripe.com" target="_blank" rel="noopener noreferrer" className="flex items-center gap-1.5 text-sm font-medium text-primary hover:underline">
                      Ouvrir Stripe Dashboard → <ExternalLink className="h-3.5 w-3.5" />
                    </a>
                  </div>
                ) : (
                  <div className="py-3">
                    <p className="text-sm text-muted-foreground">Aucun paiement pour le moment — les paiements apparaîtront quand des missions seront terminées.</p>
                    <a href="https://dashboard.stripe.com" target="_blank" rel="noopener noreferrer" className="mt-2 inline-flex items-center gap-1.5 text-sm font-medium text-primary hover:underline">
                      Ouvrir Stripe Dashboard → <ExternalLink className="h-3.5 w-3.5" />
                    </a>
                  </div>
                )}
              </section>

              {/* Stripe Connect — honoraires soignants + commission distincte facturée à l'établissement. */}
              {connectStats && (
                <section aria-labelledby="dashboard-stripe-connect-title" className="border-t border-border pt-5">
                  <h3 id="dashboard-stripe-connect-title" className="mb-3 text-sm font-semibold text-foreground">Stripe Connect</h3>
                  <div className="grid overflow-hidden rounded-lg border border-border sm:grid-cols-3">
                    <div className="p-3 text-center sm:border-r sm:border-border">
                      <p className="text-xs text-muted-foreground">Comptes Connect</p>
                      <p className="text-xl font-bold text-foreground">{connectStats.total_comptes}</p>
                      <p className="text-[10px] text-muted-foreground">{connectStats.complets} complets · {connectStats.en_cours} en cours</p>
                    </div>
                    <div className="border-t border-success/20 bg-success/5 p-3 text-center sm:border-t-0 sm:border-r" title="Honoraires effectivement versés aux soignants via Stripe Connect ; la commission Jolene est facturée séparément à l'établissement">
                      <p className="text-xs text-muted-foreground">Honoraires versés aux soignants</p>
                      <p className="text-xl font-bold text-success">{formatEur(connectStats.total_verse_soignants ?? 0)}</p>
                      {(connectStats.en_attente_soignants ?? 0) > 0 && (
                        <p className="text-[10px] text-warning">En attente : {formatEur(connectStats.en_attente_soignants)}</p>
                      )}
                    </div>
                    <div className="border-t border-primary/20 bg-primary/5 p-3 text-center sm:border-t-0" title="Commission Jolene facturée à l'établissement en plus des honoraires soignants">
                      <p className="text-xs text-muted-foreground">Commission facturée (Connect)</p>
                      <p className="text-xl font-bold text-primary">{formatEur(connectStats.total_commission_jolene ?? 0)}</p>
                      {(connectStats.en_attente_commission ?? 0) > 0 && (
                        <p className="text-[10px] text-warning">En attente : {formatEur(connectStats.en_attente_commission)}</p>
                      )}
                    </div>
                  </div>
                </section>
              )}
            </div>
          </details>
        </section>

        {/* Lists */}
        <div className="grid md:grid-cols-3 gap-6">
          <CardY2K noPadding>
            <CardY2KHeader><CardY2KTitle className="text-sm font-medium flex items-center gap-2"><UserPlus className="h-4 w-4" /> Dernières inscriptions</CardY2KTitle></CardY2KHeader>
            <CardY2KContent className="space-y-3">
              {derniersSoignants.map((s) => (
                <div key={s.id} className="flex justify-between items-center text-sm">
                  <div>
                    <span className="font-medium text-foreground">{s.prenom} {s.nom}</span>
                    <BadgeY2K variant="info" size="sm" className="ml-2">{getLabelProfession(s.profession)}</BadgeY2K>
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
                    <BadgeY2K variant="info" size="sm" className="ml-2">{getLabelTypeEtablissement(e.type)}</BadgeY2K>
                  </div>
                  <span className="text-muted-foreground text-xs">{formatDate(e.cree_le)}</span>
                </div>
              ))}
              {derniersEtabs.length === 0 && <p className="text-sm text-muted-foreground">Aucun</p>}
            </CardY2KContent>
          </CardY2K>

          <CardY2K noPadding>
            <CardY2KHeader><CardY2KTitle className="text-sm font-medium flex items-center gap-2"><AlertTriangle className="h-4 w-4 text-warning" /> Litiges ouverts</CardY2KTitle></CardY2KHeader>
            <CardY2KContent className="space-y-3">
              {litiges.map((l) => (
                <button type="button" key={l.id} className="block w-full text-left text-sm cursor-pointer hover:bg-muted/50 rounded p-1.5 -mx-1.5" onClick={() => navigate('/admin/moderation')}>
                  <p className="font-medium text-foreground line-clamp-1">{l.motif}</p>
                  <div className="flex gap-2 mt-1">
                    <BadgeY2K variant={l.statut === 'OUVERT' ? 'error' : 'info'} size="sm">{STATUTS_LITIGE_LABELS[l.statut] ?? l.statut}</BadgeY2K>
                    <span className="text-muted-foreground text-xs">{formatDate(l.cree_le)}</span>
                  </div>
                </button>
              ))}
              {litiges.length === 0 && <p className="text-sm text-muted-foreground">Aucun litige ouvert</p>}
            </CardY2KContent>
          </CardY2K>

          <CardY2K noPadding>
            <CardY2KHeader><CardY2KTitle className="text-sm font-medium flex items-center gap-2"><FileText className="h-4 w-4 text-destructive" /> Factures impayées</CardY2KTitle></CardY2KHeader>
            <CardY2KContent className="space-y-3">
              {facturesImpayees.map((f: any) => (
                <button type="button" key={f.id} className="block w-full text-left text-sm cursor-pointer hover:bg-muted/50 rounded p-1.5 -mx-1.5" onClick={() => navigate('/admin/impayees')}>
                  <div className="flex justify-between">
                    <span className="font-medium text-foreground">{f.numero_facture}</span>
                    <span className="font-semibold text-destructive">{formatEur(f.montant_ttc)} TTC</span>
                  </div>
                  <p className="text-xs text-muted-foreground mt-0.5">{(f.etablissements as any)?.nom ?? '—'} · Échue le {formatDate(f.date_echeance)}</p>
                </button>
              ))}
              {facturesImpayees.length === 0 && <p className="text-sm text-muted-foreground">Aucune</p>}
            </CardY2KContent>
          </CardY2K>
        </div>
      </div>
    </LayoutAdmin>
  );
}
