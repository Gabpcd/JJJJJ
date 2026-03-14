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
import { Loader2, Search, Zap, Download, FileText } from 'lucide-react';
import jsPDF from 'jspdf';

const formatEur = (v: number) => new Intl.NumberFormat('fr-FR', { style: 'currency', currency: 'EUR' }).format(v);
const formatDate = (d: string) => new Date(d).toLocaleDateString('fr-FR', { day: '2-digit', month: 'short', year: 'numeric' });

const STATUTS = ['TOUS', 'BROUILLON', 'EMISE', 'PAYEE', 'EN_RETARD', 'ANNULEE'];
const statutColor: Record<string, string> = {
  BROUILLON: 'secondary',
  EMISE: 'outline',
  PAYEE: 'default',
  EN_RETARD: 'destructive',
  ANNULEE: 'secondary',
};

export default function AdminFacturation() {
  usePageTitle('Facturation');
  const [factures, setFactures] = useState<any[]>([]);
  const [loading, setLoading] = useState(true);
  const [generating, setGenerating] = useState(false);
  const [filtreStatut, setFiltreStatut] = useState('TOUS');
  const [recherche, setRecherche] = useState('');

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
    const { data, error } = await supabase.rpc('fn_auto_facturation_mensuelle' as any);
    setGenerating(false);
    if (error) { toast.error(error.message); return; }
    const result = data as any;
    if (result?.success) {
      toast.success(`${result.factures_generees} facture(s) générée(s)`);
      charger();
    } else {
      toast.error(result?.error || 'Erreur inconnue');
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
    doc.text('N° Facture', 14, y);
    doc.text('Établissement', 55, y);
    doc.text('HT', 130, y);
    doc.text('TTC', 155, y);
    doc.text('Statut', 180, y);
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
    toast({ title: 'Rapport PDF généré' });
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

        {/* Totaux */}
        <div className="grid grid-cols-2 gap-4 max-w-md">
          <Card><CardContent className="pt-4"><p className="text-xs text-muted-foreground">Total HT</p><p className="text-xl font-bold text-foreground">{formatEur(totaux.ht)}</p></CardContent></Card>
          <Card><CardContent className="pt-4"><p className="text-xs text-muted-foreground">Total TTC</p><p className="text-xl font-bold text-foreground">{formatEur(totaux.ttc)}</p></CardContent></Card>
        </div>

        {/* Filtres */}
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

        {/* Table */}
        <div className="rounded-lg border overflow-x-auto">
          <Table>
            <TableHeader>
              <TableRow>
                <TableHead>N° Facture</TableHead>
                <TableHead>Établissement</TableHead>
                <TableHead>HT</TableHead>
                <TableHead>TTC</TableHead>
                <TableHead>Missions</TableHead>
                <TableHead>Émise le</TableHead>
                <TableHead>Échéance</TableHead>
                <TableHead>Statut</TableHead>
              </TableRow>
            </TableHeader>
            <TableBody>
              {filtered.map((f: any) => (
                <TableRow key={f.id}>
                  <TableCell className="font-mono text-xs font-medium">{f.numero_facture}</TableCell>
                  <TableCell>{(f.etablissements as any)?.nom ?? '—'}</TableCell>
                  <TableCell>{formatEur(f.montant_ht)}</TableCell>
                  <TableCell className="font-medium">{formatEur(f.montant_ttc)}</TableCell>
                  <TableCell>{f.nombre_missions}</TableCell>
                  <TableCell className="text-xs text-muted-foreground">{f.date_emission ? formatDate(f.date_emission) : '—'}</TableCell>
                  <TableCell className="text-xs text-muted-foreground">{f.date_echeance ? formatDate(f.date_echeance) : '—'}</TableCell>
                  <TableCell><Badge variant={(statutColor[f.statut] || 'secondary') as any} className="text-[10px]">{f.statut}</Badge></TableCell>
                </TableRow>
              ))}
              {filtered.length === 0 && <TableRow><TableCell colSpan={8} className="text-center text-muted-foreground py-8">Aucune facture</TableCell></TableRow>}
            </TableBody>
          </Table>
        </div>
      </div>
    </LayoutAdmin>
  );
}
