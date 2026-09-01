import React, { useState, useEffect, useMemo } from 'react';
import { telechargerOuPartager } from '@/lib/telechargement';
import { LayoutAdmin } from '@/components/LayoutAdmin';
import { BreadcrumbAdmin } from '@/components/BreadcrumbAdmin';
import { usePageTitle } from '@/hooks/usePageTitle';
import { ChargementAdmin } from '@/components/admin/ChargementAdmin';
import { AdminPageHeader } from '@/components/admin/AdminPageHeader';
import { AdminSummaryStrip } from '@/components/admin/AdminSummaryStrip';
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
import { TrendingUp, TrendingDown, Download, AlertTriangle, ExternalLink, Building2, CheckCircle2, Stethoscope, ChevronDown } from 'lucide-react';
import { toast } from 'sonner';
import { useNavigate } from 'react-router-dom';
import { getLabelTypeEtablissement } from '@/lib/constantes';
import { FinancialOperationsMonitor } from '@/components/admin/FinancialOperationsMonitor';
import {
  estDocumentComptabilise,
  estFactureRelancable,
  montantDocumentComptable,
} from '@/lib/adminInvoiceAccounting';

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

type Periode = 'mois' | 'mois_precedent' | 'trimestre' | 'annee' | 'tout' | 'perso';

const LIBELLES_PERIODE: Record<Periode, string> = {
  mois: 'Ce mois',
  mois_precedent: 'Mois dernier',
  trimestre: '3 derniers mois',
  annee: 'Cette année',
  tout: 'Tout',
  perso: 'Période personnalisée',
};

const TAILLE_PAGE_SUPABASE = 1000;

async function chargerToutesFactures() {
  const lignes: any[] = [];
  for (let offset = 0; ; offset += TAILLE_PAGE_SUPABASE) {
    const { data, error } = await supabase.from('factures')
      .select('id, numero_facture, montant_ht, montant_tva, montant_ttc, montant_signe, type_document, statut, date_emission, date_echeance, etablissement_id, etablissements(nom, type, est_compte_test)')
      .order('date_emission', { ascending: false })
      .range(offset, offset + TAILLE_PAGE_SUPABASE - 1);
    if (error) throw error;
    const page = data || [];
    lignes.push(...page);
    if (page.length < TAILLE_PAGE_SUPABASE) return lignes;
  }
}

async function chargerToutesMissionsFinancieres() {
  const lignes: any[] = [];
  for (let offset = 0; ; offset += TAILLE_PAGE_SUPABASE) {
    const { data, error } = await supabase.from('missions')
      .select('id, total_brut, montant_commission_ht, montant_commission_ttc, statut, debut_le, etablissement_id, soignant_assigne_id, etablissements(nom, type, taux_commission_negocie, est_compte_test), soignants(est_compte_test)')
      .in('statut', ['TERMINEE', 'EN_COURS', 'ASSIGNEE'])
      .order('debut_le', { ascending: false })
      .range(offset, offset + TAILLE_PAGE_SUPABASE - 1);
    if (error) throw error;
    const page = data || [];
    lignes.push(...page);
    if (page.length < TAILLE_PAGE_SUPABASE) return lignes;
  }
}

export default function AdminFinances() {
  usePageTitle('Finances Jolene');
  const navigate = useNavigate();
  const [loading, setLoading] = useState(true);
  const [factures, setFactures] = useState<any[]>([]);
  const [missions, setMissions] = useState<any[]>([]);
  const [loadError, setLoadError] = useState<string | null>(null);
  const [sortKey, setSortKey] = useState<SortKey>('commissions_ht');
  const [sortDir, setSortDir] = useState<SortDir>('desc');
  const [afficherTests, setAfficherTests] = useState(false);

  // Filtre temporel du récap « sur la période » + détail par établissement.
  const [periode, setPeriode] = useState<Periode>('tout');
  const [dateDebut, setDateDebut] = useState<string>('');
  const [dateFin, setDateFin] = useState<string>('');

  // Task 12
  const [diagResult, setDiagResult] = useState<DiagResult | null>(null);
  const [diagLoading, setDiagLoading] = useState(false);

  const charger = async () => {
    setLoading(true);
    setLoadError(null);
    try {
      const [fRes, mRes] = await Promise.all([chargerToutesFactures(), chargerToutesMissionsFinancieres()]);
      setFactures(fRes);
      setMissions(mRes);
    } catch (error: any) {
      console.error('charger finances admin error', error);
      setFactures([]);
      setMissions([]);
      setLoadError(error?.message || 'Impossible de charger les données financières.');
    } finally {
      setLoading(false);
    }
  };

  useEffect(() => {
    void charger();
  }, []);

  const now = new Date();
  const moisCourant = now.getMonth();
  const anneeCourante = now.getFullYear();
  const moisPrecedent = moisCourant === 0 ? 11 : moisCourant - 1;
  const anneePrecedente = moisCourant === 0 ? anneeCourante - 1 : anneeCourante;

  const facturesProduction = useMemo(
    () => afficherTests ? factures : factures.filter(f => (f.etablissements as any)?.est_compte_test === false),
    [afficherTests, factures],
  );
  const missionsProduction = useMemo(
    () => afficherTests ? missions : missions.filter(m => (
      (m.etablissements as any)?.est_compte_test === false
      && (m.soignants as any)?.est_compte_test === false
    )),
    [afficherTests, missions],
  );
  const facturesComptabilisees = useMemo(
    () => facturesProduction.filter(estDocumentComptabilise),
    [facturesProduction],
  );
  const nbDonneesTestExclues = (factures.length - facturesProduction.length)
    + (missions.length - missionsProduction.length);

  const facturesMoisCourant = useMemo(() => facturesComptabilisees.filter(f => {
    if (!f.date_emission) return false;
    const d = new Date(f.date_emission);
    return d.getMonth() === moisCourant && d.getFullYear() === anneeCourante;
  }), [facturesComptabilisees, moisCourant, anneeCourante]);

  const facturesMoisPrecedent = useMemo(() => facturesComptabilisees.filter(f => {
    if (!f.date_emission) return false;
    const d = new Date(f.date_emission);
    return d.getMonth() === moisPrecedent && d.getFullYear() === anneePrecedente;
  }), [facturesComptabilisees, moisPrecedent, anneePrecedente]);

  // Prédicat de période réutilisable (factures via date_emission, missions via debut_le).
  const dansLaPeriode = useMemo(() => {
    const debutMois = new Date(anneeCourante, moisCourant, 1);
    const debutMoisPrec = new Date(anneePrecedente, moisPrecedent, 1);
    const finMoisPrec = new Date(anneeCourante, moisCourant, 1); // exclusif
    const debutTrimestre = new Date(anneeCourante, moisCourant - 2, 1); // 3 mois glissants
    const debutAnnee = new Date(anneeCourante, 0, 1);
    // Bornes perso (inclusives, bornes vides ignorées).
    const bornePersoDebut = dateDebut ? new Date(dateDebut + 'T00:00:00') : null;
    const bornePersoFin = dateFin ? new Date(dateFin + 'T23:59:59.999') : null;

    return (dateStr: string | null | undefined): boolean => {
      if (periode === 'tout') return true;
      if (!dateStr) return false;
      const d = new Date(dateStr);
      if (Number.isNaN(d.getTime())) return false;
      switch (periode) {
        case 'mois':
          return d >= debutMois;
        case 'mois_precedent':
          return d >= debutMoisPrec && d < finMoisPrec;
        case 'trimestre':
          return d >= debutTrimestre;
        case 'annee':
          return d >= debutAnnee;
        case 'perso':
          if (bornePersoDebut && d < bornePersoDebut) return false;
          if (bornePersoFin && d > bornePersoFin) return false;
          return true;
        default:
          return true;
      }
    };
  }, [periode, dateDebut, dateFin, moisCourant, anneeCourante, moisPrecedent, anneePrecedente]);

  const facturesFiltrees = useMemo(
    () => facturesComptabilisees.filter(f => dansLaPeriode(f.date_emission)),
    [facturesComptabilisees, dansLaPeriode],
  );
  const missionsFiltrees = useMemo(
    () => missionsProduction.filter(m => dansLaPeriode(m.debut_le)),
    [missionsProduction, dansLaPeriode],
  );

  const commHTMois = facturesMoisCourant.reduce((s, f) => s + montantDocumentComptable(f, 'ht'), 0);
  const commTTCMois = facturesMoisCourant.reduce((s, f) => s + montantDocumentComptable(f, 'ttc'), 0);
  const tvaMois = facturesMoisCourant.reduce((s, f) => s + montantDocumentComptable(f, 'tva'), 0);
  const commHTMoisPrec = facturesMoisPrecedent.reduce((s, f) => s + montantDocumentComptable(f, 'ht'), 0);

  const variationPct = commHTMoisPrec > 0 ? ((commHTMois - commHTMoisPrec) / commHTMoisPrec) * 100 : 0;
  const variationPositive = variationPct >= 0;

  const impayees = facturesFiltrees.filter(facture => estFactureRelancable(facture));
  const nbImpayees = impayees.length;
  const montantImpayees = impayees.reduce((s, f) => s + montantDocumentComptable(f, 'ttc'), 0);

  // Recap « sur la période » (rewiré sur les données filtrées par période)
  const totalHT = facturesFiltrees.reduce((s, f) => s + montantDocumentComptable(f, 'ht'), 0);
  const totalTVA = facturesFiltrees.reduce((s, f) => s + montantDocumentComptable(f, 'tva'), 0);
  const totalTTC = facturesFiltrees.reduce((s, f) => s + montantDocumentComptable(f, 'ttc'), 0);
  const payesTTC = facturesFiltrees
    .filter(f => f.statut === 'PAYEE')
    .reduce((s, f) => s + montantDocumentComptable(f, 'ttc'), 0);
  const volumeBrut = missionsFiltrees.reduce((s, m) => s + (m.total_brut || 0), 0);

  // Taux commission moyen = moyenne des taux de chaque établissement (pas HT/volume)
  // Global (sur tous les établissements actifs) — indicateur structurel, non scopé période.
  const tauxParEtab = useMemo(() => {
    const map = new Map<string, number>();
    missionsProduction.forEach((m: any) => {
      const taux = (m.etablissements as any)?.taux_commission_negocie;
      if (taux != null && m.etablissement_id) map.set(m.etablissement_id, Number(taux));
    });
    const vals = [...map.values()];
    return vals.length > 0 ? vals.reduce((a, b) => a + b, 0) / vals.length : null;
  }, [missionsProduction]);

  // Chart data
  const chartData = useMemo(() => {
    const months: { label: string; ht: number; ttc: number }[] = [];
    for (let i = 5; i >= 0; i--) {
      const d = new Date(anneeCourante, moisCourant - i, 1);
      const m = d.getMonth();
      const y = d.getFullYear();
      const label = d.toLocaleDateString('fr-FR', { month: 'short', year: '2-digit' });
      const moisFactures = facturesComptabilisees.filter(f => {
        if (!f.date_emission) return false;
        const fd = new Date(f.date_emission);
        return fd.getMonth() === m && fd.getFullYear() === y;
      });
      months.push({
        label,
        ht: moisFactures.reduce((s, f) => s + montantDocumentComptable(f, 'ht'), 0),
        ttc: moisFactures.reduce((s, f) => s + montantDocumentComptable(f, 'ttc'), 0),
      });
    }
    return months;
  }, [facturesComptabilisees, moisCourant, anneeCourante]);

  // Par établissement : volumes issus des missions, CA signé issu des documents comptables.
  const etabData = useMemo(() => {
    const map = new Map<string, {
      id: string; nom: string; type: string; nb_missions: number; soignants: Set<string>;
      commissions_ht: number; commissions_ttc: number; impayes: number; taux_com: number | null; derniere_mission: string;
    }>();
    missionsFiltrees.forEach((m: any) => {
      const eid = m.etablissement_id;
      if (!eid) return;
      const tauxCommission = (m.etablissements as any)?.taux_commission_negocie;
      const existing = map.get(eid) || {
        id: eid,
        nom: (m.etablissements as any)?.nom || '—',
        type: (m.etablissements as any)?.type || '—',
        taux_com: tauxCommission != null && Number.isFinite(Number(tauxCommission)) ? Number(tauxCommission) : null,
        nb_missions: 0, soignants: new Set<string>(),
        commissions_ht: 0, commissions_ttc: 0, impayes: 0, derniere_mission: '',
      };
      existing.nb_missions++;
      if (m.soignant_assigne_id) existing.soignants.add(m.soignant_assigne_id);
      if (!existing.derniere_mission || (m.debut_le && m.debut_le > existing.derniere_mission)) existing.derniere_mission = m.debut_le;
      map.set(eid, existing);
    });
    facturesFiltrees.forEach(f => {
      const eid = f.etablissement_id;
      if (!eid) return;
      if (!map.has(eid)) {
        map.set(eid, {
          id: eid,
          nom: (f.etablissements as any)?.nom || '—',
          type: (f.etablissements as any)?.type || '—',
          taux_com: null,
          nb_missions: 0,
          soignants: new Set<string>(),
          commissions_ht: 0,
          commissions_ttc: 0,
          impayes: 0,
          derniere_mission: '',
        });
      }
      const etablissement = map.get(eid)!;
      etablissement.commissions_ht += montantDocumentComptable(f, 'ht');
      etablissement.commissions_ttc += montantDocumentComptable(f, 'ttc');
      if (estFactureRelancable(f)) {
        etablissement.impayes += montantDocumentComptable(f, 'ttc');
      }
    });
    return Array.from(map.values()).map(e => ({ ...e, nb_soignants: e.soignants.size }));
  }, [missionsFiltrees, facturesFiltrees]);

  // Pattern « file de travail » (Session D, version légère) : établissements avec impayés,
  // montant décroissant — la vraie file de traitement vit dans /admin/impayees.
  const etabsImpayes = useMemo(
    () => etabData.filter(e => e.impayes > 0).sort((a, b) => b.impayes - a.impayes),
    [etabData],
  );

  const sortedEtab = useMemo(() => {
    return [...etabData].sort((a, b) => {
      const va = (a as any)[sortKey];
      const vb = (b as any)[sortKey];
      if (typeof va === 'number' && typeof vb === 'number') return sortDir === 'asc' ? va - vb : vb - va;
      return sortDir === 'asc' ? String(va).localeCompare(String(vb)) : String(vb).localeCompare(String(va));
    });
  }, [etabData, sortKey, sortDir]);

  const exporterCSV = () => {
    const headers = ['Date émission', 'N° Document', 'Établissement', 'Type établissement', 'Type document', 'Montant HT signé', 'TVA signée', 'Montant TTC signé', 'Statut'];
    const escapeCSV = (v: string) => `"${v.replace(/"/g, '""')}"`;
    const rows = facturesFiltrees.map(f => [
      escapeCSV(f.date_emission ? formatDate(f.date_emission) : ''),
      escapeCSV(f.numero_facture || ''),
      escapeCSV((f.etablissements as any)?.nom || ''),
      escapeCSV((f.etablissements as any)?.type || ''),
      escapeCSV(f.type_document || 'FACTURE'),
      montantDocumentComptable(f, 'ht').toFixed(2),
      montantDocumentComptable(f, 'tva').toFixed(2),
      montantDocumentComptable(f, 'ttc').toFixed(2),
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

  if (loading) return <LayoutAdmin><ChargementAdmin titre="Piloter les finances Jolene" /></LayoutAdmin>;

  if (loadError) {
    return (
      <LayoutAdmin>
        <BreadcrumbAdmin pageName="Finances" />
        <div className="mx-auto max-w-2xl rounded-xl border border-destructive/40 bg-destructive/5 p-6 text-center">
          <AlertTriangle className="mx-auto h-8 w-8 text-destructive" />
          <h1 className="mt-3 text-lg font-bold text-foreground">Données financières indisponibles</h1>
          <p className="mt-1 text-sm text-muted-foreground">{loadError}</p>
          <BoutonY2K className="mt-4" onClick={charger}>Réessayer</BoutonY2K>
        </div>
      </LayoutAdmin>
    );
  }

  // Scopé période (cohérent avec « Volume brut soignants » du même bloc récap).
  const nbSoignantsTotal = new Set(missionsFiltrees.map((m: any) => m.soignant_assigne_id).filter(Boolean)).size;
  const libellePeriode = LIBELLES_PERIODE[periode];

  return (
    <LayoutAdmin>
      <BreadcrumbAdmin pageName="Finances" />
      <div className="space-y-6">
        <AdminPageHeader
          eyebrow="Pilotage financier"
          title="Finances Jolene"
          description="Suivez l’encaissement, les commissions et les établissements sur une période cohérente."
          icon={<TrendingUp className="h-6 w-6" />}
          actions={(
            <>
            <BoutonY2K variant="secondary" onClick={exporterCSV} className="gap-2" iconeGauche={<Download className="h-4 w-4" />}>
              Export CSV
            </BoutonY2K>
            <BoutonY2K onClick={() => navigate('/admin/facturation')} className="gap-2">
              Ouvrir la facturation
            </BoutonY2K>
            </>
          )}
        />

        {/* Sélecteur de période — pilote le récap « sur la période » + le détail par établissement */}
        <div className="space-y-2">
          <div className="-mx-1 overflow-x-auto pb-1" aria-label="Période financière">
            <div className="flex w-max min-w-full items-center gap-2 px-1">
              {(['mois', 'mois_precedent', 'trimestre', 'annee', 'tout', 'perso'] as Periode[]).map(p => (
                <BoutonY2K
                  key={p}
                  size="sm"
                  variant={periode === p ? 'primary' : 'secondary'}
                  onClick={() => setPeriode(p)}
                  aria-pressed={periode === p}
                  className="shrink-0"
                >
                  {p === 'mois' ? 'Ce mois'
                    : p === 'mois_precedent' ? 'Mois dernier'
                    : p === 'trimestre' ? '3 mois'
                    : p === 'annee' ? 'Cette année'
                    : p === 'tout' ? 'Tout'
                    : 'Période…'}
                </BoutonY2K>
              ))}
            </div>
          </div>
          <label className="flex min-h-11 w-fit items-center gap-2 rounded-lg border border-border bg-card px-3 py-2 text-xs text-foreground">
            <input
              type="checkbox"
              checked={afficherTests}
              onChange={(event) => setAfficherTests(event.target.checked)}
              className="h-5 w-5 shrink-0"
            />
            Afficher les données de test (hors comptabilité de production)
          </label>
          {afficherTests && (
            <p className="rounded-lg border border-amber-200 bg-amber-50 px-3 py-2 text-xs text-amber-900" role="status">
              Mode contrôle TEST actif : ces montants servent au diagnostic et restent exclus des statistiques de production.
            </p>
          )}
          {periode === 'perso' && (
            <div className="flex flex-wrap items-end gap-3 rounded-xl border border-border bg-card p-3">
              <label className="flex flex-col gap-1 text-xs text-muted-foreground">
                Du
                <input
                  type="date"
                  value={dateDebut}
                  max={dateFin || undefined}
                  onChange={(e) => setDateDebut(e.target.value)}
                  className="rounded-lg border border-border bg-background px-2 py-1.5 text-base md:text-sm text-foreground"
                />
              </label>
              <label className="flex flex-col gap-1 text-xs text-muted-foreground">
                Au
                <input
                  type="date"
                  value={dateFin}
                  min={dateDebut || undefined}
                  onChange={(e) => setDateFin(e.target.value)}
                  className="rounded-lg border border-border bg-background px-2 py-1.5 text-base md:text-sm text-foreground"
                />
              </label>
            </div>
          )}
          <p className="text-xs text-muted-foreground">
            {facturesFiltrees.length} document{facturesFiltrees.length > 1 ? 's' : ''} comptabilisé{facturesFiltrees.length > 1 ? 's' : ''} sur la période
            {nbDonneesTestExclues > 0 && ` · ${nbDonneesTestExclues} donnée${nbDonneesTestExclues > 1 ? 's' : ''} de test exclue${nbDonneesTestExclues > 1 ? 's' : ''}`}
          </p>
        </div>

        <AdminSummaryStrip
          ariaLabel={`Résumé financier — ${libellePeriode}`}
          items={[
            {
              id: 'ca-ht',
              label: `CA HT · ${libellePeriode}`,
              value: formatEur(totalHT),
              detail: `${facturesFiltrees.length} document${facturesFiltrees.length > 1 ? 's' : ''} comptabilisé${facturesFiltrees.length > 1 ? 's' : ''}`,
              icon: <TrendingUp className="h-4 w-4" />,
              tone: 'primary',
            },
            {
              id: 'ca-ttc',
              label: 'CA TTC',
              value: formatEur(totalTTC),
              detail: `dont ${formatEur(totalTVA)} de TVA`,
            },
            {
              id: 'encaisse',
              label: 'Encaissé TTC',
              value: formatEur(payesTTC),
              icon: <CheckCircle2 className="h-4 w-4" />,
              tone: 'success',
            },
            {
              id: 'volume',
              label: 'Volume brut soignants',
              value: formatEur(volumeBrut),
              detail: `${nbSoignantsTotal} soignant${nbSoignantsTotal > 1 ? 's' : ''} mobilisé${nbSoignantsTotal > 1 ? 's' : ''}`,
              icon: <Building2 className="h-4 w-4" />,
            },
            {
              id: 'impayes',
              label: 'Factures impayées',
              value: nbImpayees,
              detail: nbImpayees > 0 ? `${formatEur(montantImpayees)} en attente` : 'Aucun impayé',
              icon: <AlertTriangle className="h-4 w-4" />,
              tone: nbImpayees > 0 ? 'danger' : 'success',
            },
          ]}
        />

        <FinancialOperationsMonitor />

        <details className="group rounded-xl border border-border bg-card">
          <summary className="flex cursor-pointer list-none items-center justify-between gap-4 p-4 focus-visible:outline-none focus-visible:ring-2 focus-visible:ring-primary [&::-webkit-details-marker]:hidden">
            <span>
              <span className="block font-semibold text-foreground">Repères du mois courant</span>
              <span className="block text-sm text-muted-foreground">Commissions, TVA et taux moyen</span>
            </span>
            <ChevronDown className="h-5 w-5 text-muted-foreground transition-transform group-open:rotate-180" aria-hidden="true" />
          </summary>
          <dl className="grid gap-px border-t border-border bg-border sm:grid-cols-4">
            <div className="bg-card p-4">
              <dt className="text-xs text-muted-foreground">Commissions HT du mois</dt>
              <dd className="mt-1 text-xl font-bold text-foreground">{formatEur(commHTMois)}</dd>
              <dd className={`mt-1 flex items-center gap-1 text-xs font-medium ${variationPositive ? 'text-success' : 'text-destructive'}`}>
                {variationPct !== 0 && (variationPositive ? <TrendingUp className="h-3.5 w-3.5" /> : <TrendingDown className="h-3.5 w-3.5" />)}
                {variationPct !== 0 ? `${variationPositive ? '+' : ''}${variationPct.toFixed(0)}% vs mois précédent` : 'Pas de comparaison disponible'}
              </dd>
            </div>
            <div className="bg-card p-4">
              <dt className="text-xs text-muted-foreground">TTC du mois</dt>
              <dd className="mt-1 text-xl font-bold text-foreground">{formatEur(commTTCMois)}</dd>
            </div>
            <div className="bg-card p-4">
              <dt className="text-xs text-muted-foreground">TVA collectée du mois</dt>
              <dd className="mt-1 text-xl font-bold text-foreground">{formatEur(tvaMois)}</dd>
            </div>
            <div className="bg-card p-4">
              <dt className="text-xs text-muted-foreground">Taux de commission moyen</dt>
              <dd className="mt-1 text-xl font-bold text-foreground">{tauxParEtab != null ? `${tauxParEtab.toFixed(1)}%` : '—'}</dd>
            </div>
          </dl>
        </details>

        {/* Chart */}
        <details className="group rounded-xl border border-border bg-card">
          <summary className="flex cursor-pointer list-none items-center justify-between gap-4 p-4 focus-visible:outline-none focus-visible:ring-2 focus-visible:ring-primary [&::-webkit-details-marker]:hidden">
            <span>
              <span className="block font-semibold text-foreground">Évolution des commissions</span>
              <span className="block text-sm text-muted-foreground">Comparaison HT et TTC sur les 6 derniers mois</span>
            </span>
            <ChevronDown className="h-5 w-5 text-muted-foreground transition-transform group-open:rotate-180" aria-hidden="true" />
          </summary>
          <div className="border-t border-border p-4">
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
          </div>
        </details>

        {/* Task 12 — Diagnostic de cohérence financière */}
        <details className="group rounded-xl border border-border bg-card">
          <summary className="flex cursor-pointer list-none items-center justify-between gap-4 p-4 focus-visible:outline-none focus-visible:ring-2 focus-visible:ring-primary [&::-webkit-details-marker]:hidden">
            <span className="flex items-center gap-3">
              <Stethoscope className="h-5 w-5 text-primary" aria-hidden="true" />
              <span>
                <span className="block font-semibold text-foreground">Diagnostic de cohérence financière</span>
                <span className="block text-sm text-muted-foreground">Missions, factures et transferts Stripe</span>
              </span>
            </span>
            <ChevronDown className="h-5 w-5 text-muted-foreground transition-transform group-open:rotate-180" aria-hidden="true" />
          </summary>
          <div className="space-y-4 border-t border-border p-4">
            <div className="flex justify-end">
              <BoutonY2K size="sm" variant="secondary" onClick={lancerDiagnostic} disabled={diagLoading} loading={diagLoading}>
                {diagLoading ? 'Analyse en cours…' : 'Lancer le diagnostic'}
              </BoutonY2K>
            </div>
            {!diagResult && !diagLoading && (
              <p className="text-sm text-muted-foreground">Lancez l'analyse de cohérence entre missions, factures et transferts Stripe.</p>
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
          </div>
        </details>

        {/* Table par établissement */}
        <CardY2K noPadding>
          <CardY2KHeader>
            <CardY2KTitle className="text-base">Détail par établissement — {libellePeriode}</CardY2KTitle>
            {/* Mobile : tri visible via select */}
            <div className="md:hidden flex items-center gap-2 mt-2">
              <label htmlFor="admin-finances-tri-mobile" className="text-xs text-muted-foreground">Trier par</label>
              <select
                id="admin-finances-tri-mobile"
                value={sortKey}
                onChange={(e) => { setSortKey(e.target.value as SortKey); setSortDir('desc'); }}
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
            {/* Bandeau compact « À traiter » : établissements avec impayés (max 5, montant décroissant) */}
            {etabsImpayes.length > 0 && (
              <div className="mx-4 my-3 rounded-xl border border-destructive/30 bg-destructive/5 p-3 space-y-2">
                <div className="flex items-center justify-between flex-wrap gap-2">
                  <p className="flex items-center gap-2 text-sm font-bold text-foreground">
                    <span className="inline-flex items-center justify-center min-w-5 h-5 px-1.5 rounded-full bg-destructive text-destructive-foreground text-[11px] font-bold">
                      {etabsImpayes.length}
                    </span>
                    À traiter — {etabsImpayes.length > 1 ? 'établissements' : 'établissement'} avec impayés
                  </p>
                  <button
                    type="button"
                    onClick={() => navigate('/admin/impayees')}
                    className="text-xs font-medium text-destructive hover:underline inline-flex items-center gap-1"
                  >
                    Traiter les factures impayées
                    <ExternalLink className="h-3 w-3 shrink-0" />
                  </button>
                </div>
                <div className="flex flex-wrap gap-2">
                  {etabsImpayes.slice(0, 5).map(e => (
                    <button
                      key={e.id}
                      type="button"
                      onClick={() => navigate('/admin/impayees')}
                      className="inline-flex items-center gap-1.5 rounded-lg border border-destructive/30 bg-card px-2.5 py-1.5 text-xs hover:bg-destructive/10 transition-colors min-h-[32px]"
                    >
                      <AlertTriangle className="h-3 w-3 text-destructive shrink-0" />
                      <span className="font-medium text-foreground truncate max-w-[160px]">{e.nom}</span>
                      <span className="font-bold text-destructive">{formatEur(e.impayes)}</span>
                    </button>
                  ))}
                  {etabsImpayes.length > 5 && (
                    <button
                      type="button"
                      onClick={() => navigate('/admin/impayees')}
                      className="inline-flex items-center rounded-lg px-2.5 py-1.5 text-xs text-muted-foreground hover:text-foreground transition-colors min-h-[32px]"
                    >
                      +{etabsImpayes.length - 5} {etabsImpayes.length - 5 > 1 ? 'autres' : 'autre'}
                    </button>
                  )}
                </div>
              </div>
            )}
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
                  case 'type': return <BadgeY2K variant="info" size="sm">{getLabelTypeEtablissement(e.type)}</BadgeY2K>;
                  case 'nb_missions': return <span className="font-medium">{e.nb_missions}</span>;
                  case 'taux_com': return <span className="font-medium text-primary">{e.taux_com != null ? `${e.taux_com}%` : '—'}</span>;
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
                    <BadgeY2K variant="info" size="sm" className="shrink-0">{getLabelTypeEtablissement(e.type)}</BadgeY2K>
                  </div>
                  <div className="grid grid-cols-2 gap-2 text-xs">
                    <div>
                      <p className="text-muted-foreground">Missions</p>
                      <p className="font-semibold">{e.nb_missions} · {e.nb_soignants} soignant(s)</p>
                    </div>
                    <div>
                      <p className="text-muted-foreground">Taux com.</p>
                      <p className="font-semibold text-primary">{e.taux_com != null ? `${e.taux_com}%` : '—'}</p>
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
