import React, { useState, useEffect, useMemo } from 'react';
import { LayoutAdmin } from '@/components/LayoutAdmin';
import { BreadcrumbAdmin } from '@/components/BreadcrumbAdmin';
import { usePageTitle } from '@/hooks/usePageTitle';
import { ChargementPage } from '@/components/ChargementPage';
import { supabase } from '@/integrations/supabase/client';
import { Button } from '@/components/ui/button';
import { Badge } from '@/components/ui/badge';
import { Input } from '@/components/ui/input';
import { Select, SelectContent, SelectItem, SelectTrigger, SelectValue } from '@/components/ui/select';
import { Table, TableBody, TableCell, TableHead, TableHeader, TableRow } from '@/components/ui/table';
import { Card, CardContent } from '@/components/ui/card';
import { toast } from 'sonner';
import { Loader2, Search, Zap, Download, FileText, ChevronDown, ChevronRight } from 'lucide-react';
import jsPDF from 'jspdf';

const formatEur = (v: number) => new Intl.NumberFormat('fr-FR', { style: 'currency', currency: 'EUR' }).format(v);
const formatDate = (d: string) => new Date(d).toLocaleDateString('fr-FR', { day: '2-digit', month: 'short', year: 'numeric' });
const formatDateTime = (d: string) => new Date(d).toLocaleDateString('fr-FR', { day: '2-digit', month: 'short', hour: '2-digit', minute: '2-digit' });

const STATUTS = ['TOUS', 'BROUILLON', 'EMISE', 'PAYEE', 'EN_RETARD', 'ANNULEE'];
const statutColor: Record<string, string> = {
  BROUILLON: 'secondary',
  EMISE: 'outline',
  PAYEE: 'default',
  EN_RETARD: 'destructive',
  ANNULEE: 'secondary',
};

function FactureDetailRow({ factureId }: { factureId: string }) {
  const [missions, setMissions] = useState<any[]>([]);
  const [loading, setLoading] = useState(true);

  useEffect(() => {
    supabase
      .from('missions')
      .select('id, intitule, profession_requise, debut_le, fin_le, duree_heures, taux_horaire_base, total_brut, montant_commission_ht, montant_commission_ttc, soignant_assigne_id, soignants(nom, prenom)')
      .eq('facture_id', factureId)
      .order('debut_le', { ascending: true })
      .then(({ data }) => {
        setMissions((data as any[]) || []);
        setLoading(false);
      });
  }, [factureId]);

  if (loading) return (
    <TableRow>
      <TableCell colSpan={8} className="bg-muted/30 py-4">
        <Loader2 className="h-4 w-4 animate-spin mx-auto text-muted-foreground" />
      </TableCell>
    </TableRow>
  );

  if (missions.length === 0) return (
    <TableRow>
      <TableCell colSpan={8} className="bg-muted/30 py-4 text-center text-xs text-muted-foreground">
        Aucune mission rattachée à cette facture
      </TableCell>
    </TableRow>
  );

  return (
    <TableRow>
      <TableCell colSpan={8} className="bg-muted/30 p-0">
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
                    <td className="py-1.5 pr-2 font-medium text-foreground">{m.intitule}</td>
                    <td className="py-1.5 pr-2 text-foreground">{sg ? `${sg.prenom} ${sg.nom}` : '—'}</td>
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
      </TableCell>
    </TableRow>
  );
}

export default function AdminFacturation() {
  usePageTitle('Facturation');
  const [factures, setFactures] = useState<any[]>([]);
  const [loading, setLoading] = useState(true);
  const [generating, setGenerating] = useState(false);
  const [filtreStatut, setFiltreStatut] = useState('TOUS');
  const [recherche, setRecherche] = useState('');
  const [expandedId, setExpandedId] = useState<string | null>(null);

  const charger = async () => {
    setLoading(true);
    const { data } = await supabase.from('factures')
      .select('id, numero_facture, montant_ht, montant_tva, montant_ttc, statut, date_emission, date_echeance, nombre_missions, etablissement_id, etablissements(nom)')
      .order('date_emission', { ascending: false })
      .limit(500);
    if (data) setFactures(data);
    setLoading(false);
  };

  useEffect(() => { charger(); }, []);

  const filtered = useMemo(() => {
    let f = factures;
    if (filtreStatut !== 'TOUS') f = f.filter(x => x.statut === filtreStatut);
    if (recherche) {
      const q = recherche.toLowerCase();
      f = f.filter(x => `${x.numero_facture} ${(x.etablissements as any)?.nom ?? ''}`.toLowerCase().includes(q));
    }
    return f;
  }, [factures, filtreStatut, recherche]);

  const totaux = useMemo(() => ({
    ht: filtered.reduce((s, f) => s + (f.montant_ht || 0), 0),
    ttc: filtered.reduce((s, f) => s + (f.montant_ttc || 0), 0),
  }), [filtered]);

  const genererFactures = async () => {
    setGenerating(true);
    try {
      const { data, error } = await supabase.rpc('fn_auto_facturation_mensuelle' as any);
      if (error) { toast.error(`Erreur : ${error.message}`); return; }
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
      toast.error(`Erreur inattendue : ${err.message}`);
    } finally {
      setGenerating(false);
    }
  };

  const exporterFEC = async () => {
    const annee = new Date().getFullYear();
    const { data, error } = await supabase.rpc('fn_export_fec' as any, { p_annee: annee });
    if (error) { toast.error(error.message); return; }
    const lignes = Array.isArray(data) ? data : [];
    if (lignes.length === 0) { toast.info('Aucune donnée FEC pour ' + annee); return; }
    const cols = Object.keys(lignes[0]);
    const csv = [cols.join('\t'), ...lignes.map((l: any) => cols.map(c => l[c] ?? '').join('\t'))].join('\n');
    const blob = new Blob(['\uFEFF' + csv], { type: 'text/csv;charset=utf-8;' });
    const url = URL.createObjectURL(blob);
    const a = document.createElement('a'); a.href = url; a.download = `FEC_${annee}.csv`; a.click();
    URL.revokeObjectURL(url);
    toast.success(`FEC ${annee} exporté`);
  };

  const genererRapportPDF = async () => {
    const doc = new jsPDF();
    doc.setFillColor(23, 162, 184);
    doc.rect(0, 0, 210, 30, 'F');
    doc.setTextColor(255, 255, 255);
    doc.setFontSize(18);
    doc.text('Soin Direct — Rapport mensuel', 14, 20);
    doc.setTextColor(0, 0, 0);
    doc.setFontSize(11);
    const mois = new Date().toLocaleDateString('fr-FR', { month: 'long', year: 'numeric' });
    doc.text(`Période : ${mois}`, 14, 42);
    doc.text(`Factures : ${filtered.length}`, 14, 50);
    doc.text(`Total HT : ${formatEur(totaux.ht)}`, 14, 58);
    doc.text(`Total TTC : ${formatEur(totaux.ttc)}`, 14, 66);
    let y = 80;
    doc.setFontSize(9);
    doc.setFont('helvetica', 'bold');
    doc.text('N° Facture', 14, y); doc.text('Établissement', 55, y); doc.text('HT', 130, y); doc.text('TTC', 155, y); doc.text('Statut', 180, y);
    y += 6;
    doc.setFont('helvetica', 'normal');
    filtered.slice(0, 50).forEach((f: any) => {
      if (y > 275) { doc.addPage(); y = 20; }
      doc.text(f.numero_facture || '—', 14, y);
      doc.text(((f.etablissements as any)?.nom ?? '—').substring(0, 30), 55, y);
      doc.text(formatEur(f.montant_ht), 130, y);
      doc.text(formatEur(f.montant_ttc), 155, y);
      doc.text(f.statut || '—', 180, y);
      y += 5;
    });
    doc.save(`rapport_mensuel_${new Date().toISOString().slice(0, 7)}.pdf`);
    toast.success('Rapport PDF généré');
  };

  if (loading) return <LayoutAdmin><ChargementPage /></LayoutAdmin>;

  return (
    <LayoutAdmin>
      <BreadcrumbAdmin pageName="Facturation" />
      <div className="space-y-6">
        <div className="flex flex-col sm:flex-row justify-between items-start sm:items-center gap-4">
          <h1 className="text-2xl font-bold text-foreground">Facturation</h1>
          <div className="flex flex-wrap gap-2">
            <Button variant="outline" onClick={exporterFEC} className="gap-2">
              <Download className="h-4 w-4" /> Exporter FEC {new Date().getFullYear()}
            </Button>
            <Button variant="outline" onClick={genererRapportPDF} className="gap-2">
              <FileText className="h-4 w-4" /> Rapport PDF
            </Button>
            <Button onClick={genererFactures} disabled={generating} className="gap-2">
              {generating ? <Loader2 className="h-4 w-4 animate-spin" /> : <Zap className="h-4 w-4" />}
              Générer les factures du mois
            </Button>
          </div>
        </div>

        <div className="grid grid-cols-2 gap-4 max-w-md">
          <Card><CardContent className="pt-4"><p className="text-xs text-muted-foreground">Total HT</p><p className="text-xl font-bold text-foreground">{formatEur(totaux.ht)}</p></CardContent></Card>
          <Card><CardContent className="pt-4"><p className="text-xs text-muted-foreground">Total TTC</p><p className="text-xl font-bold text-foreground">{formatEur(totaux.ttc)}</p></CardContent></Card>
        </div>

        <div className="flex flex-col sm:flex-row gap-3">
          <div className="relative max-w-xs flex-1">
            <Search className="absolute left-3 top-1/2 -translate-y-1/2 h-4 w-4 text-muted-foreground" />
            <Input placeholder="Rechercher…" value={recherche} onChange={(e) => setRecherche(e.target.value)} className="pl-10" />
          </div>
          <Select value={filtreStatut} onValueChange={setFiltreStatut}>
            <SelectTrigger className="w-[160px]"><SelectValue /></SelectTrigger>
            <SelectContent>
              {STATUTS.map(s => <SelectItem key={s} value={s}>{s === 'TOUS' ? 'Tous statuts' : s}</SelectItem>)}
            </SelectContent>
          </Select>
        </div>

        <div className="rounded-lg border overflow-x-auto">
          <Table>
            <TableHeader>
              <TableRow>
                <TableHead className="w-8"></TableHead>
                <TableHead>N° Facture</TableHead>
                <TableHead>Établissement</TableHead>
                <TableHead>HT</TableHead>
                <TableHead>TTC</TableHead>
                <TableHead>Missions</TableHead>
                <TableHead>Émise le</TableHead>
                <TableHead>Statut</TableHead>
              </TableRow>
            </TableHeader>
            <TableBody>
              {filtered.map((f: any) => {
                const isExpanded = expandedId === f.id;
                return (
                  <React.Fragment key={f.id}>
                    <TableRow
                      className="cursor-pointer hover:bg-muted/50 transition-colors"
                      onClick={() => setExpandedId(isExpanded ? null : f.id)}
                    >
                      <TableCell className="w-8 pr-0">
                        {isExpanded ? <ChevronDown className="h-4 w-4 text-muted-foreground" /> : <ChevronRight className="h-4 w-4 text-muted-foreground" />}
                      </TableCell>
                      <TableCell className="font-mono text-xs font-medium">{f.numero_facture}</TableCell>
                      <TableCell>{(f.etablissements as any)?.nom ?? '—'}</TableCell>
                      <TableCell>{formatEur(f.montant_ht)}</TableCell>
                      <TableCell className="font-medium">{formatEur(f.montant_ttc)}</TableCell>
                      <TableCell>{f.nombre_missions}</TableCell>
                      <TableCell className="text-xs text-muted-foreground">{f.date_emission ? formatDate(f.date_emission) : '—'}</TableCell>
                      <TableCell><Badge variant={(statutColor[f.statut] || 'secondary') as any} className="text-[10px]">{f.statut}</Badge></TableCell>
                    </TableRow>
                    {isExpanded && <FactureDetailRow factureId={f.id} />}
                  </React.Fragment>
                );
              })}
              {filtered.length === 0 && <TableRow><TableCell colSpan={9} className="text-center text-muted-foreground py-8">Aucune facture</TableCell></TableRow>}
            </TableBody>
          </Table>
        </div>
      </div>
    </LayoutAdmin>
  );
}
