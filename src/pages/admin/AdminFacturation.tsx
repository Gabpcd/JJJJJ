import React, { useState, useEffect, useMemo } from 'react';
import { telechargerOuPartagerPdf, telechargerOuPartager } from '@/lib/telechargement';
import { LayoutAdmin } from '@/components/LayoutAdmin';
import { BreadcrumbAdmin } from '@/components/BreadcrumbAdmin';
import { usePageTitle } from '@/hooks/usePageTitle';
import { ChargementAdmin } from '@/components/admin/ChargementAdmin';
import { AdminPageHeader } from '@/components/admin/AdminPageHeader';
import { AdminSummaryStrip } from '@/components/admin/AdminSummaryStrip';
import { supabase } from '@/integrations/supabase/client';
import { BoutonY2K } from '@/components/y2k/BoutonY2K';
import { BadgeY2K } from '@/components/y2k/BadgeY2K';
import { Input } from '@/components/ui/input';
import { Select, SelectContent, SelectItem, SelectTrigger, SelectValue } from '@/components/ui/select';
import { Table, TableBody, TableCell, TableHead, TableHeader, TableRow } from '@/components/ui/table';
import { toast } from 'sonner';
import { Loader2, Search, Zap, Download, FileText, ChevronDown, ChevronRight, ExternalLink, CheckCircle, CheckCircle2, XCircle, CreditCard, History } from 'lucide-react';
import { useNavigate, useSearchParams } from 'react-router-dom';
import jsPDF from 'jspdf';
import { BoutonsBulkFactures } from '@/components/admin/BoutonsBulkFactures';
import { Checkbox } from '@/components/ui/checkbox';
import { EmptyState } from '@/components/ui/EmptyState';
import { estDocumentComptabilise, montantDocumentComptable } from '@/lib/adminInvoiceAccounting';
import { estFactureProduction, perimetreFacture, type FactureAvecPerimetre } from '@/lib/adminInvoiceScope';

const formatEur = (v: number) => new Intl.NumberFormat('fr-FR', { style: 'currency', currency: 'EUR' }).format(v);
const formatDate = (d: string) => new Date(d).toLocaleDateString('fr-FR', { day: '2-digit', month: 'short', year: 'numeric' }).replace(/ /g, '\u00a0');
const formatDateTime = (d: string) => new Date(d).toLocaleDateString('fr-FR', { day: '2-digit', month: 'short', hour: '2-digit', minute: '2-digit' }).replace(/ /g, '\u00a0');

// Statuts demandant une action admin → section « À traiter » en tête de page.
// Le reste est relégué dans l'historique replié (pattern « file de travail », Session D).
const STATUTS_A_TRAITER = ['VIREMENT_DECLARE', 'EN_RETARD'];
// Statuts proposés dans le filtre de l'historique (les statuts actionnables sont toujours visibles au-dessus).
const STATUTS_HISTORIQUE = ['TOUS', 'BROUILLON', 'EMISE', 'PAYEE', 'ANNULEE'];
const statutColor: Record<string, 'success' | 'warning' | 'error' | 'info' | 'premium'> = {
  BROUILLON: 'info',
  EMISE: 'info',
  VIREMENT_DECLARE: 'warning',
  PAYEE: 'success',
  EN_RETARD: 'error',
  ANNULEE: 'info',
};
const statutLabel: Record<string, string> = {
  BROUILLON: 'Brouillon',
  EMISE: 'Émise',
  VIREMENT_DECLARE: 'Virement déclaré',
  PAYEE: 'Payée',
  EN_RETARD: 'En retard',
  ANNULEE: 'Annulée',
};

function BadgePerimetreFacture({ facture }: { facture: FactureAvecPerimetre }) {
  const perimetre = perimetreFacture(facture);
  if (perimetre === 'PRODUCTION') return null;
  return (
    <BadgeY2K variant={perimetre === 'TEST' ? 'warning' : 'error'} size="sm">
      {perimetre === 'TEST' ? 'TEST' : 'PÉRIMÈTRE À VÉRIFIER'}
    </BadgeY2K>
  );
}

/**
 * Bloc détail factures rattachées — utilisé en desktop (TableRow colSpan)
 * et mobile (div standalone à l'intérieur d'une card).
 */
function FactureDetailContenu({ missions, loading, error, mode }: { missions: any[]; loading: boolean; error: string | null; mode: 'desktop' | 'mobile' }) {
  const navigate = useNavigate();

  if (loading) return (
    <div className="py-4">
      <Loader2 className="h-4 w-4 animate-spin mx-auto text-muted-foreground" />
    </div>
  );

  if (error) return (
    <p className="py-4 text-center text-xs font-medium text-destructive" role="alert">
      Missions indisponibles : {error}
    </p>
  );

  if (missions.length === 0) return (
    <p className="py-4 text-center text-xs text-muted-foreground">Aucune mission rattachée à cette facture</p>
  );

  if (mode === 'mobile') {
    return (
      <div className="space-y-2">
        <p className="text-xs font-semibold text-muted-foreground">Missions rattachées ({missions.length})</p>
        {missions.map((m: any) => {
          const sg = m.soignants as any;
          return (
            <div key={m.id} className="rounded-lg border border-border/60 bg-background p-2.5 space-y-1.5">
              <button
                type="button"
                onClick={(e) => { e.stopPropagation(); navigate(`/admin/missions/${m.id}`); }}
                className="font-semibold text-primary hover:underline text-left inline-flex items-center gap-1 text-xs"
              >
                {m.intitule}
                <ExternalLink className="h-3 w-3 shrink-0" />
              </button>
              {sg && (
                <button
                  type="button"
                  onClick={(e) => { e.stopPropagation(); navigate(`/admin/utilisateurs/${m.soignant_assigne_id}`); }}
                  className="text-primary hover:underline inline-flex items-center gap-1 text-xs"
                >
                  {sg.prenom} {sg.nom}
                  <ExternalLink className="h-3 w-3 shrink-0" />
                </button>
              )}
              <p className="text-[10px] text-muted-foreground">
                {m.profession_requise} · {formatDateTime(m.debut_le)} → {formatDateTime(m.fin_le)}
              </p>
              <div className="grid grid-cols-2 gap-1 text-[11px] pt-1 border-t border-border/40">
                <span className="text-muted-foreground">Heures : <span className="text-foreground font-medium">{m.duree_heures}h</span></span>
                <span className="text-muted-foreground">Taux : <span className="text-foreground font-medium">{formatEur(m.taux_horaire_base)}</span></span>
                <span className="text-muted-foreground">Brut : <span className="text-foreground font-medium">{formatEur(m.total_brut || 0)}</span></span>
                <span className="text-muted-foreground">Com. HT : <span className="text-primary font-semibold">{formatEur(m.montant_commission_ht || 0)}</span></span>
              </div>
            </div>
          );
        })}
      </div>
    );
  }

  return (
    <div className="px-6 py-3">
      <p className="text-xs font-semibold text-muted-foreground mb-2">Missions rattachées ({missions.length})</p>
      <table className="w-full text-xs">
        <thead>
          <tr className="border-b border-border">
            <th className="text-left py-1.5 pr-2 font-medium text-muted-foreground">Intitulé</th>
            <th className="text-left py-1.5 pr-2 font-medium text-muted-foreground">Soignant</th>
            <th className="text-left py-1.5 pr-2 font-medium text-muted-foreground">Profession</th>
            <th className="text-left py-1.5 pr-2 font-medium text-muted-foreground">Dates</th>
            <th className="text-right py-1.5 pr-2 font-medium text-muted-foreground">Heures</th>
            <th className="text-right py-1.5 pr-2 font-medium text-muted-foreground">Taux/h</th>
            <th className="text-right py-1.5 pr-2 font-medium text-muted-foreground">Brut soignant</th>
            <th className="text-right py-1.5 font-medium text-muted-foreground">Commission HT</th>
          </tr>
        </thead>
        <tbody>
          {missions.map((m: any) => {
            const sg = m.soignants as any;
            return (
              <tr key={m.id} className="border-b border-border/40 hover:bg-muted/50">
                <td className="py-1.5 pr-2">
                  <button
                    onClick={(e) => { e.stopPropagation(); navigate(`/admin/missions/${m.id}`); }}
                    className="font-medium text-primary hover:underline text-left inline-flex items-center gap-1"
                  >
                    {m.intitule}
                    <ExternalLink className="h-3 w-3 shrink-0" />
                  </button>
                </td>
                <td className="py-1.5 pr-2">
                  {sg ? (
                    <button
                      onClick={(e) => { e.stopPropagation(); navigate(`/admin/utilisateurs/${m.soignant_assigne_id}`); }}
                      className="text-primary hover:underline inline-flex items-center gap-1"
                    >
                      {sg.prenom} {sg.nom}
                      <ExternalLink className="h-3 w-3 shrink-0" />
                    </button>
                  ) : '—'}
                </td>
                <td className="py-1.5 pr-2 text-muted-foreground">{m.profession_requise}</td>
                <td className="py-1.5 pr-2 text-muted-foreground">{formatDateTime(m.debut_le)} → {formatDateTime(m.fin_le)}</td>
                <td className="py-1.5 pr-2 text-right">{m.duree_heures}h</td>
                <td className="py-1.5 pr-2 text-right">{formatEur(m.taux_horaire_base)}</td>
                <td className="py-1.5 pr-2 text-right">{formatEur(m.total_brut || 0)}</td>
                <td className="py-1.5 text-right font-semibold text-primary">{formatEur(m.montant_commission_ht || 0)}</td>
              </tr>
            );
          })}
        </tbody>
      </table>
    </div>
  );
}

/**
 * Hook : charge la liste des missions rattachées à une facture.
 * Permet de partager la logique entre FactureDetailRow (desktop)
 * et le rendu mobile inline.
 */
function useMissionsFacture(factureId: string) {
  const [missions, setMissions] = useState<any[]>([]);
  const [loading, setLoading] = useState(true);
  const [error, setError] = useState<string | null>(null);

  useEffect(() => {
    let actif = true;
    void (async () => {
      setLoading(true);
      setError(null);
      try {
        const { data, error: missionsError } = await (supabase
          .from('missions')
          .select('id, intitule, profession_requise, debut_le, fin_le, duree_heures, taux_horaire_base, total_brut, montant_commission_ht, montant_commission_ttc, soignant_assigne_id')
          .eq('facture_id', factureId)
          .order('debut_le', { ascending: true }) as any);
        if (missionsError) throw missionsError;
        const mList = (data as any[]) || [];
        const sgIds = [...new Set(mList.map((m: any) => m.soignant_assigne_id).filter(Boolean))];
        const sgMap: Record<string, any> = {};
        if (sgIds.length > 0) {
          const { data: sgData, error: soignantsError } = await supabase.from('soignants').select('id, prenom, nom').in('id', sgIds);
          if (soignantsError) throw soignantsError;
          if (sgData) for (const s of sgData) sgMap[s.id] = s;
        }
        if (actif) setMissions(mList.map((m: any) => ({ ...m, soignants: m.soignant_assigne_id ? sgMap[m.soignant_assigne_id] || null : null })));
      } catch (fetchError: any) {
        console.error('useMissionsFacture fetch error', fetchError);
        if (actif) {
          setMissions([]);
          setError(fetchError?.message || 'chargement impossible');
        }
      } finally {
        if (actif) setLoading(false);
      }
    })();
    return () => { actif = false; };
  }, [factureId]);

  return { missions, loading, error };
}

function FactureDetailRow({ factureId }: { factureId: string }) {
  const { missions, loading, error } = useMissionsFacture(factureId);
  return (
    <TableRow>
      <TableCell colSpan={10} className="bg-muted/30 p-0">
        <FactureDetailContenu missions={missions} loading={loading} error={error} mode="desktop" />
      </TableCell>
    </TableRow>
  );
}

function FactureDetailMobile({ factureId }: { factureId: string }) {
  const { missions, loading, error } = useMissionsFacture(factureId);
  return (
    <div className="bg-muted/30 rounded-lg p-3 -mx-1">
      <FactureDetailContenu missions={missions} loading={loading} error={error} mode="mobile" />
    </div>
  );
}

/**
 * Détail responsive pour les cartes « À traiter » (affichées à toutes les largeurs) :
 * un seul fetch, rendu desktop sur md+ et rendu mobile en dessous.
 */
function FactureDetailATraiter({ factureId }: { factureId: string }) {
  const { missions, loading, error } = useMissionsFacture(factureId);
  return (
    <div className="bg-muted/30 rounded-lg">
      <div className="hidden md:block">
        <FactureDetailContenu missions={missions} loading={loading} error={error} mode="desktop" />
      </div>
      <div className="md:hidden p-3">
        <FactureDetailContenu missions={missions} loading={loading} error={error} mode="mobile" />
      </div>
    </div>
  );
}

// Jolene brand teal — used in the accounting report where CSS vars are unavailable.
const PDF_BRAND_COLOR = { r: 23, g: 162, b: 184 } as const;

export function libellePerimetreRapport(filtreStatut: string, recherche: string): string {
  const segments = ['production uniquement', filtreStatut === 'TOUS' ? 'tous statuts' : `statut ${statutLabel[filtreStatut] ?? filtreStatut}`];
  const terme = recherche.trim();
  if (terme) segments.push(`recherche « ${terme} »`);
  return segments.join(' · ');
}
export default function AdminFacturation() {
  usePageTitle('Facturation');
  const [factures, setFactures] = useState<any[]>([]);
  const [loading, setLoading] = useState(true);
  const [loadError, setLoadError] = useState<string | null>(null);
  const [generating, setGenerating] = useState(false);
  const [actionId, setActionId] = useState<string | null>(null);
  const [filtreStatut, setFiltreStatut] = useState('TOUS');
  // ?q= : pré-remplissage depuis la recherche globale ⌘K (Session D-2)
  const [searchParams] = useSearchParams();
  const [recherche, setRecherche] = useState(searchParams.get('q') ?? '');
  const [expandedId, setExpandedId] = useState<string | null>(null);
  const [selectedIds, setSelectedIds] = useState<Set<string>>(new Set());
  // Historique replié par défaut (pattern « file de travail »), mais ouvert d'emblée
  // si on arrive depuis la recherche globale ⌘K (?q=) pour que le résultat cherché
  // soit immédiatement visible. État au niveau page : il survit aux refetchs
  // (état de chargement de la page) contrairement à l'état interne de <FileDeTravail />.
  const [historiqueOuvert, setHistoriqueOuvert] = useState(() => Boolean(searchParams.get('q')));

  const navigate = useNavigate();

  const charger = async () => {
    setLoading(true);
    setLoadError(null);
    try {
      const toutes: any[] = [];
      const taillePage = 1000;
      for (let offset = 0; ; offset += taillePage) {
        const { data, error } = await supabase.from('factures')
          .select('id, numero_facture, montant_ht, montant_tva, montant_ttc, montant_signe, type_document, statut, date_emission, date_echeance, nombre_missions, etablissement_id, virement_reference, etablissements(nom, est_compte_test)')
          .order('date_emission', { ascending: false })
          .order('id', { ascending: false })
          .range(offset, offset + taillePage - 1);
        if (error) throw error;
        if (!data) throw new Error('Réponse factures absente');
        const page = data;
        toutes.push(...page);
        if (page.length < taillePage) break;
      }
      setFactures(toutes);
    } catch (error: any) {
      console.error('charger factures error', error);
      setFactures([]);
      setLoadError(error?.message || 'Impossible de charger la facturation.');
    } finally {
      setLoading(false);
    }
  };

  useEffect(() => { charger(); }, []);

  // Section « À traiter » : toujours visible, indépendante des filtres de l'historique.
  // Virements déclarés d'abord (plus anciens en premier), puis factures en retard.
  const aTraiter = useMemo(() => {
    const ts = (f: any) => (f.date_emission ? new Date(f.date_emission).getTime() : 0);
    return factures
      .filter((f: any) => estFactureProduction(f) && STATUTS_A_TRAITER.includes(f.statut))
      .sort((a: any, b: any) => {
        if (a.statut !== b.statut) return a.statut === 'VIREMENT_DECLARE' ? -1 : 1;
        return ts(a) - ts(b);
      });
  }, [factures]);

  // Filtres statut + recherche sur l'ensemble (sert aux totaux et au rapport PDF,
  // comportement inchangé), puis l'historique en exclut les statuts « à traiter ».
  const filtered = useMemo(() => {
    let f = factures;
    if (filtreStatut !== 'TOUS') f = f.filter(x => x.statut === filtreStatut);
    if (recherche) {
      const q = recherche.toLowerCase();
      f = f.filter(x => `${x.numero_facture} ${(x.etablissements as any)?.nom ?? ''}`.toLowerCase().includes(q));
    }
    return f;
  }, [factures, filtreStatut, recherche]);

  const historique = useMemo(
    () => filtered.filter((f: any) => !estFactureProduction(f) || !STATUTS_A_TRAITER.includes(f.statut)),
    [filtered]
  );

  const historiqueProduction = useMemo(
    () => historique.filter(estFactureProduction),
    [historique],
  );

  const donneesTestVisibles = useMemo(
    () => historique.filter((f: any) => perimetreFacture(f) === 'TEST').length,
    [historique],
  );

  const perimetresAVerifier = useMemo(
    () => historique.filter((f: any) => perimetreFacture(f) === 'A_VERIFIER').length,
    [historique],
  );

  const documentsComptabilises = useMemo(
    () => filtered.filter(estFactureProduction).filter(estDocumentComptabilise),
    [filtered],
  );

  const totaux = useMemo(() => ({
    ht: documentsComptabilises.reduce((s, f) => s + montantDocumentComptable(f, 'ht'), 0),
    tva: documentsComptabilises.reduce((s, f) => s + montantDocumentComptable(f, 'tva'), 0),
    ttc: documentsComptabilises.reduce((s, f) => s + montantDocumentComptable(f, 'ttc'), 0),
  }), [documentsComptabilises]);

  // Sélection bulk : factures cochées parmi celles actuellement visibles
  // (cartes « À traiter » + liste historique filtrée).
  const selectionBulk = useMemo(() =>
    [...aTraiter, ...historique]
      .filter((f: any) => selectedIds.has(f.id))
      .map((f: any) => ({
        id: f.id,
        numero: f.numero_facture,
        montant_ttc: montantDocumentComptable(f, 'ttc'),
        statut: f.statut,
        date_emission: f.date_emission,
        etablissement_nom: (f.etablissements as any)?.nom ?? null,
        perimetre: perimetreFacture(f),
      })),
  [aTraiter, historique, selectedIds]);

  const toggleSelection = (factureId: string, checked: boolean | 'indeterminate') => {
    const next = new Set(selectedIds);
    if (checked) next.add(factureId);
    else next.delete(factureId);
    setSelectedIds(next);
  };

  const confirmerVirement = async (f: any) => {
    setActionId(f.id);
    const { data, error } = await supabase.rpc('fn_confirmer_virement_admin' as any, { p_facture_id: f.id });
    if (error || (data as any)?.error) {
      toast.error('Erreur lors de la confirmation du virement.');
    } else {
      toast.success('Virement confirmé');
      charger();
    }
    setActionId(null);
  };

  const rejeterVirement = async (f: any) => {
    setActionId(f.id);
    const { data, error } = await supabase.rpc('fn_rejeter_virement_admin' as any, { p_facture_id: f.id });
    if (error || (data as any)?.error) {
      toast.error('Erreur lors du rejet du virement.');
    } else {
      toast.success('Virement rejeté — facture remise en Émise');
      charger();
    }
    setActionId(null);
  };

  const genererFactures = async () => {
    setGenerating(true);
    try {
      const { data, error } = await supabase.rpc('fn_auto_facturation_mensuelle' as any);
      if (error) { toast.error('Erreur lors de la génération des factures. Veuillez réessayer.'); return; }
      const result = data as any;
      if (result?.success) {
        if ((result.factures_generees ?? 0) === 0) {
          toast.info('Aucune nouvelle facture à générer — toutes les missions terminées sont déjà facturées.');
        } else {
          toast.success(`${result.factures_generees} facture(s) générée(s) avec succès !`);
          charger();
        }
      } else {
        toast.error(result?.error || 'Erreur inconnue lors de la génération');
      }
    } catch (err: any) {
      toast.error('Une erreur inattendue est survenue. Veuillez réessayer.');
    } finally {
      setGenerating(false);
    }
  };

  const exporterJournalVentes = async () => {
    const annee = new Date().getFullYear();
    const result = await (supabase.rpc('fn_export_fec' as any, { p_annee: annee }) as any).catch((err: any) => { console.warn('exporterJournalVentes error:', err); return { data: null, error: err }; });
    const { data, error } = result;
    if (error) { toast.error('Une erreur est survenue. Veuillez réessayer.'); return; }
    const lignes = Array.isArray(data) ? data : [];
    if (lignes.length === 0) { toast.info('Aucune vente de production pour ' + annee); return; }
    const cols = Object.keys(lignes[0]);
    const csv = [cols.join('\t'), ...lignes.map((l: any) => cols.map(c => l[c] ?? '').join('\t'))].join('\n');
    await telechargerOuPartager('﻿' + csv, `JOURNAL_VENTES_${annee}.tsv`, 'text/tab-separated-values');
    toast.success(`Journal des ventes ${annee} exporté`);
  };

  const genererRapportPDF = async () => {
    const doc = new jsPDF();
    doc.setFillColor(PDF_BRAND_COLOR.r, PDF_BRAND_COLOR.g, PDF_BRAND_COLOR.b);
    doc.rect(0, 0, 210, 30, 'F');
    doc.setTextColor(255, 255, 255);
    doc.setFontSize(18);
    doc.text('Jolene — Rapport de facturation', 14, 20);
    doc.setTextColor(0, 0, 0);
    doc.setFontSize(11);
    const libellePerimetre = libellePerimetreRapport(filtreStatut, recherche);
    doc.text(`Périmètre : ${libellePerimetre}`, 14, 42);
    doc.text(`Documents comptabilisés : ${documentsComptabilises.length}`, 14, 50);
    doc.text(`Total HT : ${formatEur(totaux.ht)}`, 14, 58);
    doc.text(`TVA : ${formatEur(totaux.tva)} · Total TTC : ${formatEur(totaux.ttc)}`, 14, 66);
    let y = 80;
    doc.setFontSize(9);
    doc.setFont('helvetica', 'bold');
    const dessinerEntete = () => {
      doc.setFont('helvetica', 'bold');
      doc.text('N° document', 14, y); doc.text('Type', 50, y); doc.text('Établissement', 70, y); doc.text('HT', 138, y); doc.text('TTC', 163, y); doc.text('Statut', 187, y);
      y += 6;
      doc.setFont('helvetica', 'normal');
    };
    dessinerEntete();
    documentsComptabilises.forEach((f: any) => {
      if (y > 275) {
        doc.addPage();
        y = 20;
        dessinerEntete();
      }
      doc.text(f.numero_facture || '—', 14, y);
      doc.text(f.type_document === 'AVOIR' ? 'Avoir' : 'Facture', 50, y);
      doc.text(((f.etablissements as any)?.nom ?? '—').substring(0, 27), 70, y);
      doc.text(formatEur(montantDocumentComptable(f, 'ht')), 138, y);
      doc.text(formatEur(montantDocumentComptable(f, 'ttc')), 163, y);
      doc.text(f.statut || '—', 187, y);
      y += 5;
    });
    await telechargerOuPartagerPdf(doc, `rapport_facturation_${new Date().toISOString().slice(0, 10)}.pdf`);
    toast.success('Rapport PDF généré');
  };

  if (loading) return <LayoutAdmin><ChargementAdmin titre="Facturation" /></LayoutAdmin>;

  if (loadError) {
    return (
      <LayoutAdmin>
        <BreadcrumbAdmin pageName="Facturation" />
        <div className="mx-auto max-w-2xl rounded-xl border border-destructive/40 bg-destructive/5 p-6 text-center">
          <XCircle className="mx-auto h-8 w-8 text-destructive" />
          <h1 className="mt-3 text-lg font-bold text-foreground">Facturation indisponible</h1>
          <p className="mt-1 text-sm text-muted-foreground">{loadError}</p>
          <BoutonY2K className="mt-4" onClick={charger}>Réessayer</BoutonY2K>
        </div>
      </LayoutAdmin>
    );
  }

  return (
    <LayoutAdmin>
      <BreadcrumbAdmin pageName="Facturation" />
      <div className="space-y-6">
        <AdminPageHeader
          eyebrow="Encaissement"
          title="Facturation"
          description="Traitez les virements et retards en priorité, puis consultez ou exportez l’historique."
          icon={<FileText className="h-6 w-6" />}
          actions={(
            <BoutonY2K onClick={genererFactures} disabled={generating} loading={generating} className="gap-2" iconeGauche={generating ? undefined : <Zap className="h-4 w-4" />}>
              Générer les factures du mois
            </BoutonY2K>
          )}
        />

        <details className="group rounded-xl border border-border bg-card">
          <summary className="flex cursor-pointer list-none items-center justify-between gap-4 p-4 focus-visible:outline-none focus-visible:ring-2 focus-visible:ring-primary [&::-webkit-details-marker]:hidden">
            <span>
              <span className="block font-semibold text-foreground">Exports et prélèvements</span>
              <span className="block text-sm text-muted-foreground">Journal des ventes, rapport PDF et prélèvement SEPA</span>
            </span>
            <ChevronDown className="h-5 w-5 text-muted-foreground transition-transform group-open:rotate-180" aria-hidden="true" />
          </summary>
          <div className="flex flex-wrap gap-2 border-t border-border p-4">
            <BoutonY2K variant="secondary" onClick={exporterJournalVentes} className="gap-2" iconeGauche={<Download className="h-4 w-4" />}>
              Journal des ventes {new Date().getFullYear()} (18 colonnes)
            </BoutonY2K>
            <BoutonY2K variant="secondary" onClick={genererRapportPDF} className="gap-2" iconeGauche={<FileText className="h-4 w-4" />}>
              Rapport PDF
            </BoutonY2K>
            <BoutonY2K
              variant="secondary"
              onClick={async () => {
                const { data, error } = await supabase.functions.invoke('sepa-auto-charge');
                if (error || data?.success !== true) { toast.error(data?.error || 'Erreur prélèvement SEPA'); return; }
                const charged = Number(data.charged ?? 0);
                const failed = Number(data.failed ?? 0);
                const skippedTest = Number(data.skipped_test ?? 0);
                if (charged > 0 && failed === 0) {
                  toast.success(`${charged} facture(s) prélevée(s) par SEPA${skippedTest > 0 ? ` · ${skippedTest} donnée(s) de test neutralisée(s)` : ''}`);
                } else if (charged > 0 || failed > 0) {
                  toast.warning(`${charged} prélèvement(s) confirmé(s), ${failed} échec(s), ${skippedTest} donnée(s) de test neutralisée(s).`);
                } else if (skippedTest > 0) {
                  toast.info(`${skippedTest} facture(s) de test neutralisée(s) — aucun prélèvement réel.`);
                } else {
                  toast.info('Aucune facture SEPA à prélever');
                }
                charger();
              }}
              className="gap-2"
              iconeGauche={<CreditCard className="h-4 w-4" />}
            >
              Prélever SEPA
            </BoutonY2K>
          </div>
        </details>

        <AdminSummaryStrip
          ariaLabel="Résumé de la facturation"
          items={[
            {
              id: 'total-ht',
              label: 'Total HT',
              value: formatEur(totaux.ht),
              detail: `${documentsComptabilises.length} document${documentsComptabilises.length > 1 ? 's' : ''} comptabilisé${documentsComptabilises.length > 1 ? 's' : ''}`,
              icon: <FileText className="h-4 w-4" />,
              tone: 'primary',
            },
            {
              id: 'total-ttc',
              label: 'Total TTC',
              value: formatEur(totaux.ttc),
              detail: `dont ${formatEur(totaux.tva)} de TVA`,
              icon: <CreditCard className="h-4 w-4" />,
            },
            {
              id: 'a-traiter',
              label: 'À traiter',
              value: aTraiter.length,
              detail: 'Virements déclarés et retards',
              icon: aTraiter.length > 0 ? <History className="h-4 w-4" /> : <CheckCircle2 className="h-4 w-4" />,
              tone: aTraiter.length > 0 ? 'danger' : 'success',
            },
            {
              id: 'historique',
              label: 'Dans l’historique',
              value: historiqueProduction.length,
              detail: [
                filtreStatut === 'TOUS' ? 'Production, tous statuts' : `Production, ${statutLabel[filtreStatut] ?? filtreStatut}`,
                donneesTestVisibles > 0 ? `${donneesTestVisibles} test visible${donneesTestVisibles > 1 ? 's' : ''}` : null,
                perimetresAVerifier > 0 ? `${perimetresAVerifier} périmètre${perimetresAVerifier > 1 ? 's' : ''} à vérifier` : null,
              ].filter(Boolean).join(' · '),
              icon: <History className="h-4 w-4" />,
            },
          ]}
        />

        {/* ── Section « À traiter » : virements déclarés puis factures en retard ── */}
        <section aria-label="À traiter">
          <h2 className="flex items-center gap-2 text-sm font-bold text-foreground mb-1">
            {aTraiter.length > 0 ? (
              <span className="inline-flex items-center justify-center min-w-5 h-5 px-1.5 rounded-full bg-destructive text-destructive-foreground text-[11px] font-bold">
                {aTraiter.length}
              </span>
            ) : (
              <CheckCircle2 className="h-4 w-4 text-emerald-500" />
            )}
            À traiter
          </h2>
          <p className="text-xs text-muted-foreground mb-3">
            Virements déclarés à vérifier en premier, puis factures en retard.
          </p>
          {aTraiter.length === 0 ? (
            <EmptyState
              icone={<CheckCircle2 />}
              titre="Tout est traité"
              description="Aucun virement à vérifier et aucune facture en retard."
              variant="success"
            />
          ) : (
            <div className="space-y-3">
              {aTraiter.map((f: any) => {
                const isExpanded = expandedId === f.id;
                const isSelected = selectedIds.has(f.id);
                const enRetard = f.statut === 'EN_RETARD';
                return (
                  <div
                    key={f.id}
                    className={`rounded-xl border bg-card p-3 space-y-2 ${isSelected ? 'border-primary/50 bg-primary/5' : enRetard ? 'border-destructive/40' : 'border-warning/40'}`}
                  >
                    <div className="flex items-start gap-2">
                      <Checkbox
                        aria-label={`Sélectionner facture ${f.numero_facture ?? f.id}`}
                        checked={isSelected}
                        onCheckedChange={(checked) => toggleSelection(f.id, checked)}
                        className="mt-0.5"
                      />
                      <div className="flex-1 min-w-0">
                        <div className="flex flex-wrap items-center gap-2">
                          <p className="font-mono text-xs font-semibold">{f.numero_facture}</p>
                          <BadgeY2K variant={statutColor[f.statut] || 'info'} size="sm">
                            {statutLabel[f.statut] ?? f.statut}
                          </BadgeY2K>
                        </div>
                        <button
                          type="button"
                          onClick={() => navigate(`/admin/utilisateurs/${f.etablissement_id}`)}
                          className="text-primary hover:underline inline-flex items-center gap-1 text-sm font-medium mt-0.5"
                        >
                          {(f.etablissements as any)?.nom ?? '—'}
                          <ExternalLink className="h-3 w-3 shrink-0" />
                        </button>
                      </div>
                      <div className="text-right shrink-0">
                        <p className="font-semibold text-sm">{formatEur(montantDocumentComptable(f, 'ttc'))}</p>
                        <p className="text-[10px] text-muted-foreground">TTC</p>
                      </div>
                    </div>

                    <div className="flex flex-wrap gap-x-4 gap-y-1 text-xs text-muted-foreground pl-7">
                      <span>HT : <span className="text-foreground font-medium">{formatEur(montantDocumentComptable(f, 'ht'))}</span></span>
                      <span>Missions : <span className="text-foreground font-medium">{f.nombre_missions}</span></span>
                      <span>Émise le : <span className="text-foreground font-medium">{f.date_emission ? formatDate(f.date_emission) : '—'}</span></span>
                      <span>Échéance : <span className={enRetard ? 'text-destructive font-semibold' : 'text-foreground font-medium'}>{f.date_echeance ? formatDate(f.date_echeance) : '—'}</span></span>
                      {f.statut === 'VIREMENT_DECLARE' && f.virement_reference && (
                        <span>Réf. virement : <span className="text-foreground font-medium">{f.virement_reference}</span></span>
                      )}
                    </div>

                    <div className="flex flex-wrap items-center gap-2 pl-7">
                      {f.statut === 'VIREMENT_DECLARE' && (
                        <>
                          <BoutonY2K
                            variant="primary"
                            size="sm"
                            className="min-h-[36px] text-xs gap-1"
                            disabled={actionId === f.id}
                            iconeGauche={<CheckCircle className="h-3.5 w-3.5" />}
                            onClick={() => confirmerVirement(f)}
                          >
                            Confirmer
                          </BoutonY2K>
                          <BoutonY2K
                            variant="destructive"
                            size="sm"
                            className="min-h-[36px] text-xs gap-1"
                            disabled={actionId === f.id}
                            iconeGauche={<XCircle className="h-3.5 w-3.5" />}
                            onClick={() => rejeterVirement(f)}
                          >
                            Rejeter
                          </BoutonY2K>
                        </>
                      )}
                      <BoutonY2K
                        variant="secondary"
                        size="sm"
                        className="min-h-[36px] text-xs gap-1"
                        onClick={() => setExpandedId(isExpanded ? null : f.id)}
                        iconeGauche={isExpanded ? <ChevronDown className="h-3.5 w-3.5" /> : <ChevronRight className="h-3.5 w-3.5" />}
                      >
                        {isExpanded ? 'Masquer missions' : 'Voir missions'}
                      </BoutonY2K>
                    </div>

                    {isExpanded && (
                      <div className="pl-7 pt-1">
                        <FactureDetailATraiter factureId={f.id} />
                      </div>
                    )}
                  </div>
                );
              })}
            </div>
          )}
        </section>

        {/* Toolbar bulk : toujours visible (sert aux cases « À traiter » comme à l'historique) */}
        <BoutonsBulkFactures
          selection={selectionBulk}
          onActionTerminee={() => {
            setSelectedIds(new Set());
            charger();
          }}
        />

        {/* ── Section « Historique » : repliée par défaut, filtres + recherche + bulk + expand intacts ── */}
        <section aria-label="Historique des factures">
          <button
            type="button"
            onClick={() => setHistoriqueOuvert(o => !o)}
            aria-expanded={historiqueOuvert}
            className="flex items-center gap-2 text-sm font-semibold text-muted-foreground hover:text-foreground transition-colors mb-3"
          >
            <History className="h-4 w-4" />
            Historique des factures
            <span className="inline-flex items-center justify-center min-w-5 h-5 px-1.5 rounded-full bg-muted text-muted-foreground text-[11px] font-semibold">
              {historique.length}
            </span>
            <ChevronDown className={`h-4 w-4 transition-transform ${historiqueOuvert ? 'rotate-180' : ''}`} />
          </button>

          {historiqueOuvert && (
            <div className="space-y-4">
              <div className="flex flex-col sm:flex-row gap-3">
                <div className="relative max-w-xs flex-1">
                  <Search className="absolute left-3 top-1/2 -translate-y-1/2 h-4 w-4 text-muted-foreground" />
                  <Input aria-label="Rechercher dans l’historique des factures" placeholder="Rechercher…" value={recherche} onChange={(e) => setRecherche(e.target.value)} className="pl-10" />
                </div>
                <Select value={filtreStatut} onValueChange={setFiltreStatut}>
                  <SelectTrigger aria-label="Filtrer l’historique des factures par statut" className="w-full sm:w-[160px]"><SelectValue /></SelectTrigger>
                  <SelectContent>
                    {STATUTS_HISTORIQUE.map(s => <SelectItem key={s} value={s}>{s === 'TOUS' ? 'Tous statuts' : statutLabel[s] ?? s}</SelectItem>)}
                  </SelectContent>
                </Select>
              </div>

              {/* Desktop : table 10 colonnes */}
              <div className="hidden md:block rounded-lg border overflow-x-auto">
                <Table>
                  <TableHeader>
                    <TableRow>
                      <TableHead className="w-8">
                        <Checkbox
                          aria-label="Tout sélectionner"
                          checked={historique.length > 0 && historique.every((f: any) => selectedIds.has(f.id))}
                          onCheckedChange={(checked) => {
                            if (checked) setSelectedIds(new Set(historique.map((f: any) => f.id)));
                            else setSelectedIds(new Set());
                          }}
                        />
                      </TableHead>
                      <TableHead className="w-8"></TableHead>
                      <TableHead>N° Facture</TableHead>
                      <TableHead>Établissement</TableHead>
                      <TableHead>HT</TableHead>
                      <TableHead>TTC</TableHead>
                      <TableHead>Missions</TableHead>
                      <TableHead>Émise le</TableHead>
                      <TableHead>Statut</TableHead>
                      <TableHead className="w-10"></TableHead>
                    </TableRow>
                  </TableHeader>
                  <TableBody>
                    {historique.map((f: any) => {
                      const isExpanded = expandedId === f.id;
                      return (
                        <React.Fragment key={f.id}>
                          <TableRow
                            className="cursor-pointer hover:bg-muted/50 transition-colors"
                            onClick={() => setExpandedId(isExpanded ? null : f.id)}
                          >
                            <TableCell className="w-8 pr-0" onClick={(e) => e.stopPropagation()}>
                              <Checkbox
                                aria-label={`Sélectionner facture ${f.numero_facture ?? f.id}`}
                                checked={selectedIds.has(f.id)}
                                onCheckedChange={(checked) => toggleSelection(f.id, checked)}
                              />
                            </TableCell>
                            <TableCell className="w-8 pr-0">
                              {isExpanded ? <ChevronDown className="h-4 w-4 text-muted-foreground" /> : <ChevronRight className="h-4 w-4 text-muted-foreground" />}
                            </TableCell>
                            <TableCell className="font-mono text-xs font-medium">
                              <div className="flex flex-wrap items-center gap-1.5">
                                <span>{f.numero_facture}</span>
                                <BadgePerimetreFacture facture={f} />
                              </div>
                            </TableCell>
                            <TableCell>
                              <button
                                onClick={(e) => { e.stopPropagation(); navigate(`/admin/utilisateurs/${f.etablissement_id}`); }}
                                className="text-primary hover:underline inline-flex items-center gap-1"
                              >
                                {(f.etablissements as any)?.nom ?? '—'}
                                <ExternalLink className="h-3 w-3 shrink-0" />
                              </button>
                            </TableCell>
                            <TableCell>{formatEur(montantDocumentComptable(f, 'ht'))}</TableCell>
                            <TableCell className="font-medium">{formatEur(montantDocumentComptable(f, 'ttc'))}</TableCell>
                            <TableCell>{f.nombre_missions}</TableCell>
                            <TableCell className="text-xs text-muted-foreground">{f.date_emission ? formatDate(f.date_emission) : '—'}</TableCell>
                            <TableCell>
                              <BadgeY2K variant={statutColor[f.statut] || 'info'} size="sm">
                                {statutLabel[f.statut] ?? f.statut}
                              </BadgeY2K>
                            </TableCell>
                            <TableCell className="w-auto pr-2" />
                          </TableRow>
                          {isExpanded && <FactureDetailRow factureId={f.id} />}
                        </React.Fragment>
                      );
                    })}
                    {historique.length === 0 && (
                      <TableRow>
                        <TableCell colSpan={10} className="p-0">
                          <EmptyState
                            icone={<FileText />}
                            mascotte="empty"
                            titre="Aucune facture"
                            description="Aucune facture ne correspond aux filtres sélectionnés."
                            compact
                          />
                        </TableCell>
                      </TableRow>
                    )}
                  </TableBody>
                </Table>
              </div>

              {/* Mobile : cards */}
              <div className="md:hidden space-y-3">
                {historique.length === 0 ? (
                  <EmptyState
                    icone={<FileText />}
                    mascotte="empty"
                    titre="Aucune facture"
                    description="Aucune facture ne correspond aux filtres sélectionnés."
                    compact
                  />
                ) : (
                  <>
                    {/* Sélection globale mobile */}
                    <div className="rounded-lg border border-border bg-card p-2 flex items-center justify-between text-xs">
                      <label className="flex items-center gap-2 cursor-pointer">
                        <Checkbox
                          aria-label="Tout sélectionner"
                          checked={historique.length > 0 && historique.every((f: any) => selectedIds.has(f.id))}
                          onCheckedChange={(checked) => {
                            if (checked) setSelectedIds(new Set(historique.map((f: any) => f.id)));
                            else setSelectedIds(new Set());
                          }}
                        />
                        <span className="font-medium">Tout sélectionner</span>
                      </label>
                      {selectedIds.size > 0 && (
                        <span className="text-primary font-semibold">{selectedIds.size} sélectionné{selectedIds.size > 1 ? 's' : ''}</span>
                      )}
                    </div>

                    {historique.map((f: any) => {
                      const isExpanded = expandedId === f.id;
                      const isSelected = selectedIds.has(f.id);
                      return (
                        <div
                          key={f.id}
                          className={`rounded-xl border bg-card p-3 space-y-2 ${isSelected ? 'border-primary/50 bg-primary/5' : 'border-border'}`}
                        >
                          <div className="flex items-start gap-2">
                            <Checkbox
                              aria-label={`Sélectionner facture ${f.numero_facture ?? f.id}`}
                              checked={isSelected}
                              onCheckedChange={(checked) => toggleSelection(f.id, checked)}
                              className="mt-0.5"
                            />
                            <div className="flex-1 min-w-0">
                              <div className="flex items-start justify-between gap-2">
                                <div className="flex min-w-0 flex-wrap items-center gap-1.5">
                                  <p className="font-mono text-xs font-semibold truncate">{f.numero_facture}</p>
                                  <BadgePerimetreFacture facture={f} />
                                </div>
                                <BadgeY2K variant={statutColor[f.statut] || 'info'} size="sm" className="shrink-0">
                                  {statutLabel[f.statut] ?? f.statut}
                                </BadgeY2K>
                              </div>
                              <button
                                type="button"
                                onClick={() => navigate(`/admin/utilisateurs/${f.etablissement_id}`)}
                                className="text-primary hover:underline inline-flex items-center gap-1 text-sm font-medium mt-0.5"
                              >
                                {(f.etablissements as any)?.nom ?? '—'}
                                <ExternalLink className="h-3 w-3 shrink-0" />
                              </button>
                            </div>
                          </div>

                          <div className="grid grid-cols-2 gap-2 text-xs pl-7">
                            <div>
                              <p className="text-muted-foreground">HT</p>
                              <p className="font-medium">{formatEur(montantDocumentComptable(f, 'ht'))}</p>
                            </div>
                            <div>
                              <p className="text-muted-foreground">TTC</p>
                              <p className="font-semibold">{formatEur(montantDocumentComptable(f, 'ttc'))}</p>
                            </div>
                            <div>
                              <p className="text-muted-foreground">Missions</p>
                              <p className="font-medium">{f.nombre_missions}</p>
                            </div>
                            <div>
                              <p className="text-muted-foreground">Émise le</p>
                              <p className="font-medium">{f.date_emission ? formatDate(f.date_emission) : '—'}</p>
                            </div>
                          </div>

                          <div className="flex items-center gap-2 pl-7">
                            <BoutonY2K
                              variant="secondary"
                              size="sm"
                              className="flex-1 min-h-[36px] text-xs gap-1"
                              onClick={() => setExpandedId(isExpanded ? null : f.id)}
                              iconeGauche={isExpanded ? <ChevronDown className="h-3.5 w-3.5" /> : <ChevronRight className="h-3.5 w-3.5" />}
                            >
                              {isExpanded ? 'Masquer missions' : 'Voir missions'}
                            </BoutonY2K>
                          </div>

                          {isExpanded && (
                            <div className="pl-7 pt-1">
                              <FactureDetailMobile factureId={f.id} />
                            </div>
                          )}
                        </div>
                      );
                    })}
                  </>
                )}
              </div>
            </div>
          )}
        </section>
      </div>
    </LayoutAdmin>
  );
}
