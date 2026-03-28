import React, { useState, useEffect } from 'react';
import { usePageTitle } from '@/hooks/usePageTitle';
import { useNavigate, useParams } from 'react-router-dom';
import { ArrowLeft, Printer, CreditCard, Loader2, CheckCircle, Clock, Download } from 'lucide-react';
import { LayoutApp } from '@/components/LayoutApp';
import { ChargementPage } from '@/components/ChargementPage';
import { useEtablissementScope } from '@/hooks/useEtablissementScope';
import { useNotification } from '@/contexts/NotificationContext';
import { supabase } from '@/integrations/supabase/client';
import { StripeEmbeddedCheckout } from '@/components/StripeEmbeddedCheckout';
import { PaiementVirement } from '@/components/PaiementVirement';
import { format, differenceInHours, differenceInMinutes } from 'date-fns';
import { fr } from 'date-fns/locale';
import { ENTREPRISE } from '@/constantes/entreprise';
import { capturerErreurSentry } from '@/lib/sentry';
import { toast } from 'sonner';
import jsPDF from 'jspdf';
import autoTable from 'jspdf-autotable';
import { Table, TableHeader, TableBody, TableHead, TableRow, TableCell } from '@/components/ui/table';

const STATUT_COLORS: Record<string, string> = {
  BROUILLON: 'bg-muted text-muted-foreground',
  EMISE: 'bg-primary/10 text-primary',
  VIREMENT_DECLARE: 'bg-amber-100 text-amber-700 dark:bg-amber-900/30 dark:text-amber-400',
  PAYEE: 'bg-green-100 text-green-700 dark:bg-green-900/30 dark:text-green-400',
  EN_RETARD: 'bg-destructive/10 text-destructive',
  ANNULEE: 'bg-muted text-muted-foreground line-through',
};

const STATUT_LABELS: Record<string, string> = {
  BROUILLON: 'Brouillon',
  EMISE: 'Émise',
  VIREMENT_DECLARE: 'Virement déclaré 🔍',
  PAYEE: 'Payée',
  EN_RETARD: 'En retard',
  ANNULEE: 'Annulée',
};

const MODE_LABELS: Record<string, string> = {
  STRIPE: 'Carte bancaire',
  VIREMENT: 'Virement bancaire',
  SEPA: 'Prélèvement SEPA',
};

const formatEur = (v: number) => new Intl.NumberFormat('fr-FR', { style: 'currency', currency: 'EUR' }).format(v);

function calcHeures(debut: string, fin: string): string {
  const mins = differenceInMinutes(new Date(fin), new Date(debut));
  const h = Math.floor(Math.abs(mins) / 60);
  const m = Math.abs(mins) % 60;
  return m > 0 ? `${h}h${String(m).padStart(2, '0')}` : `${h}h`;
}

function calcHeuresNum(debut: string, fin: string): number {
  return Math.abs(differenceInMinutes(new Date(fin), new Date(debut))) / 60;
}

export default function DetailFacture() {
  usePageTitle('Détail facture');
  const { id } = useParams<{ id: string }>();
  const navigate = useNavigate();
  const { user, etablissementId } = useEtablissementScope();
  const { afficherNotification } = useNotification();
  const [loading, setLoading] = useState(true);
  const [facture, setFacture] = useState<any>(null);
  const [missions, setMissions] = useState<any[]>([]);
  const [etab, setEtab] = useState<any>(null);
  const [showCheckout, setShowCheckout] = useState(false);
  const [generatingPdf, setGeneratingPdf] = useState(false);

  const charger = async () => {
    if (!user || !id || !etablissementId) return;
    setLoading(true);

    const [resDetail, resE] = await Promise.all([
      supabase.rpc('fn_detail_facture' as any, { p_facture_id: id }),
      supabase.from('etablissements').select('nom, siret, adresse_rue, adresse_ville, adresse_code_postal, taux_commission_negocie').eq('id', etablissementId).single(),
    ]);

    if (resDetail.error) {
      toast.error('Erreur chargement facture');
      setLoading(false);
      return;
    }
    if ((resDetail.data as any)?.error) {
      toast.error((resDetail.data as any).error);
      setLoading(false);
      return;
    }

    let detail = resDetail.data as any;
    // Handle case where RPC returns stringified JSON
    if (typeof detail === 'string') {
      try { detail = JSON.parse(detail); } catch { /* keep as-is */ }
    }
    // Handle case where data is wrapped in an array
    if (Array.isArray(detail) && detail.length === 1) {
      detail = detail[0];
    }
    console.log('[DetailFacture] RPC response:', JSON.stringify(detail)?.substring(0, 500));
    if (detail?.facture) setFacture(detail.facture);
    if (Array.isArray(detail?.missions)) {
      setMissions(detail.missions);
    } else {
      console.warn('[DetailFacture] missions not found in response, keys:', detail ? Object.keys(detail) : 'null');
    }
    if (resE.data) setEtab(resE.data);
    setLoading(false);
  };

  useEffect(() => { charger(); }, [user, id, etablissementId]);

  const genererPDF = () => {
    if (!facture || !etab) return;
    setGeneratingPdf(true);
    try {
      const doc = new jsPDF();
      const pw = doc.internal.pageSize.getWidth();

      doc.setFillColor(23, 162, 184);
      doc.rect(0, 0, pw, 32, 'F');
      doc.setTextColor(255, 255, 255);
      doc.setFontSize(18);
      doc.text('FACTURE', 14, 16);
      doc.setFontSize(11);
      doc.text(facture.numero_facture || '', 14, 26);
      doc.setFontSize(9);
      doc.text(`Statut : ${STATUT_LABELS[facture.statut] ?? facture.statut}`, pw - 14, 16, { align: 'right' });

      doc.setTextColor(0, 0, 0);
      let y = 42;
      doc.setFontSize(10);
      doc.setFont('helvetica', 'bold');
      doc.text(ENTREPRISE.nom, 14, y);
      doc.setFont('helvetica', 'normal');
      doc.setFontSize(8);
      doc.text('Plateforme de mise en relation soignants', 14, y + 5);

      doc.setFontSize(9);
      doc.text('Facturé à :', pw - 80, y);
      doc.setFont('helvetica', 'bold');
      doc.text(etab.nom, pw - 80, y + 5);
      doc.setFont('helvetica', 'normal');
      doc.setFontSize(8);
      doc.text(etab.adresse_rue, pw - 80, y + 10);
      doc.text(`${etab.adresse_code_postal} ${etab.adresse_ville}`, pw - 80, y + 15);
      doc.text(`SIRET : ${etab.siret}`, pw - 80, y + 20);

      y += 32;
      doc.setFontSize(8);
      if (facture.date_emission) {
        doc.text(`Date d'émission : ${format(new Date(facture.date_emission), 'dd/MM/yyyy')}`, 14, y);
        y += 5;
      }
      if (facture.date_echeance) {
        doc.text(`Échéance : ${format(new Date(facture.date_echeance), 'dd/MM/yyyy')}`, 14, y);
        y += 5;
      }
      y += 5;

      const tableData = missions.map(m => [
        m.debut_le ? format(new Date(m.debut_le), 'dd/MM') : '—',
        m.intitule?.substring(0, 25) || '—',
        m.soignant_nom || '—',
        m.debut_le && m.fin_le ? calcHeures(m.debut_le, m.fin_le) : '—',
        formatEur(m.taux_horaire_base ?? 0),
        formatEur(m.total_brut ?? 0),
        `${m.taux_commission ?? 0}%`,
        formatEur(m.montant_commission_ht ?? 0),
      ]);

      autoTable(doc, {
        startY: y,
        head: [['Date', 'Mission', 'Soignant', 'Heures', 'Taux/h', 'Brut', 'Tx Com.', 'Com. HT']],
        body: tableData,
        styles: { fontSize: 7, cellPadding: 2 },
        headStyles: { fillColor: [23, 162, 184], textColor: 255, fontStyle: 'bold' },
        margin: { left: 14, right: 14 },
      });

      y = (doc as any).lastAutoTable?.finalY ?? y + 30;
      y += 10;

      if (y > 240) { doc.addPage(); y = 20; }
      doc.setDrawColor(200, 200, 200);
      doc.line(pw - 100, y, pw - 14, y);
      y += 8;
      doc.setFontSize(9);
      doc.text('Total HT', pw - 100, y);
      doc.text(formatEur(facture.montant_ht), pw - 14, y, { align: 'right' });
      y += 6;
      doc.text(`TVA (${facture.taux_tva ?? 20}%)`, pw - 100, y);
      doc.text(formatEur(facture.montant_tva), pw - 14, y, { align: 'right' });
      y += 7;
      doc.setFont('helvetica', 'bold');
      doc.setFontSize(12);
      doc.text('Total TTC', pw - 100, y);
      doc.text(formatEur(facture.montant_ttc), pw - 14, y, { align: 'right' });

      const ph = doc.internal.pageSize.getHeight();
      doc.setFontSize(6.5);
      doc.setFont('helvetica', 'normal');
      doc.setTextColor(140, 140, 140);
      doc.text(`${ENTREPRISE.nom} — Facture générée le ${format(new Date(), 'dd/MM/yyyy à HH:mm')}`, pw / 2, ph - 8, { align: 'center' });

      doc.save(`facture_${facture.numero_facture}.pdf`);
      afficherNotification({ type: 'succes', message: 'PDF téléchargé' });
    } catch (err) {
      capturerErreurSentry(err, 'DetailFacture', 'generer_pdf');
      afficherNotification({ type: 'erreur', message: 'Erreur lors de la génération du PDF' });
    } finally {
      setGeneratingPdf(false);
    }
  };

  if (loading) return <LayoutApp role="ADMIN_ETABLISSEMENT"><ChargementPage /></LayoutApp>;
  if (!facture) return (
    <LayoutApp role="ADMIN_ETABLISSEMENT">
      <p className="text-center text-muted-foreground py-12">Facture introuvable.</p>
    </LayoutApp>
  );

  const canPay = facture.statut === 'EMISE' || facture.statut === 'EN_RETARD';

  return (
    <LayoutApp role="ADMIN_ETABLISSEMENT">
      {/* Header */}
      <div className="flex items-center justify-between mb-6 no-print">
        <button onClick={() => navigate('/etablissement/facturation')} className="flex items-center gap-2 text-sm text-muted-foreground hover:text-foreground transition-colors">
          <ArrowLeft className="h-4 w-4" /> Retour
        </button>
        <div className="flex flex-wrap gap-2">
          <button onClick={genererPDF} disabled={generatingPdf} className="btn-secondary text-sm flex items-center gap-1.5 disabled:opacity-50">
            {generatingPdf ? <Loader2 className="h-4 w-4 animate-spin" /> : <Download className="h-4 w-4" />}
            PDF
          </button>
          <button onClick={() => window.print()} className="btn-secondary text-sm flex items-center gap-1.5">
            <Printer className="h-4 w-4" /> Imprimer
          </button>
          {canPay && !facture.est_secteur_public && (
            <button onClick={() => setShowCheckout(true)} className="btn-primary text-sm flex items-center gap-1.5">
              <CreditCard className="h-4 w-4" /> Payer
            </button>
          )}
        </div>
      </div>

      {/* Invoice card */}
      <div className="card-base print-invoice print-full">
        {/* Header facture */}
        <div className="flex flex-col sm:flex-row justify-between gap-4 mb-6 pb-4 border-b border-border">
          <div>
            <h1 className="text-2xl font-black text-foreground">FACTURE</h1>
            <p className="text-lg font-bold text-primary mt-1">{facture.numero_facture}</p>
            <p className="text-sm text-muted-foreground mt-2">
              Émise le {facture.date_emission ? format(new Date(facture.date_emission), 'dd MMMM yyyy', { locale: fr }) : '—'}
            </p>
            {facture.date_echeance && (
              <p className="text-sm text-muted-foreground">
                Échéance : {format(new Date(facture.date_echeance), 'dd MMMM yyyy', { locale: fr })}
              </p>
            )}
            {facture.mode_paiement && (
              <p className="text-xs text-muted-foreground mt-1">
                Mode : {MODE_LABELS[facture.mode_paiement] ?? facture.mode_paiement}
              </p>
            )}
          </div>
          <div className="text-right">
            <p className="text-sm font-bold text-foreground">{ENTREPRISE.nom}</p>
            <p className="text-xs text-muted-foreground">Plateforme de mise en relation</p>
            <p className="text-xs text-muted-foreground mt-2">Facturé à :</p>
            <p className="text-sm font-semibold text-foreground">{etab?.nom}</p>
            <p className="text-xs text-muted-foreground">{etab?.adresse_rue}</p>
            <p className="text-xs text-muted-foreground">{etab?.adresse_code_postal} {etab?.adresse_ville}</p>
            <p className="text-xs text-muted-foreground">SIRET : {etab?.siret}</p>
          </div>
        </div>

        {/* Status */}
        <div className="mb-6 flex items-center gap-2">
          <span className="text-sm text-muted-foreground">Statut :</span>
          <span className={`px-3 py-1 rounded-full text-xs font-bold ${STATUT_COLORS[facture.statut] ?? STATUT_COLORS.BROUILLON}`}>
            {STATUT_LABELS[facture.statut] ?? facture.statut}
          </span>
        </div>

        {facture.statut === 'VIREMENT_DECLARE' && (
          <div className="mb-6 flex items-center gap-2 bg-amber-50 dark:bg-amber-900/20 border border-amber-200 dark:border-amber-700/30 rounded-xl p-3">
            <Clock className="h-4 w-4 text-amber-600 dark:text-amber-400 shrink-0" />
            <div>
              <p className="text-sm font-medium text-amber-700 dark:text-amber-300">Virement déclaré — en attente de vérification</p>
              {facture.virement_reference && (
                <p className="text-xs text-amber-600/80 dark:text-amber-400/80">Référence : {facture.virement_reference}</p>
              )}
            </div>
          </div>
        )}

        {/* Missions table */}
        <h2 className="text-sm font-bold text-foreground mb-3 uppercase tracking-wider">
          📋 Missions facturées ({missions.length})
        </h2>

        {missions.length === 0 ? (
          <p className="text-sm text-muted-foreground italic py-4">Aucune mission liée à cette facture.</p>
        ) : (
          <div className="overflow-x-auto mb-6">
            <Table>
              <TableHeader>
                <TableRow>
                  <TableHead>Date</TableHead>
                  <TableHead>Mission</TableHead>
                  <TableHead>Soignant</TableHead>
                  <TableHead className="text-right">Heures</TableHead>
                  <TableHead className="text-right">Taux/h</TableHead>
                  <TableHead className="text-right">Brut</TableHead>
                  <TableHead className="text-right">Tx Com.</TableHead>
                  <TableHead className="text-right">Com. HT</TableHead>
                </TableRow>
              </TableHeader>
              <TableBody>
                {missions.map((m: any, i: number) => {
                  const heures = m.debut_le && m.fin_le ? calcHeures(m.debut_le, m.fin_le) : '—';
                  return (
                    <TableRow key={m.id ?? i}>
                      <TableCell className="text-xs whitespace-nowrap">
                        {m.debut_le ? format(new Date(m.debut_le), 'dd/MM/yy', { locale: fr }) : '—'}
                      </TableCell>
                      <TableCell className="text-xs font-medium">{m.intitule || '—'}</TableCell>
                      <TableCell className="text-xs">
                        <div>{m.soignant_nom || '—'}</div>
                        {m.profession && <div className="text-muted-foreground text-[10px]">{m.profession}</div>}
                      </TableCell>
                      <TableCell className="text-xs text-right">{heures}</TableCell>
                      <TableCell className="text-xs text-right">{formatEur(m.taux_horaire_base ?? 0)}</TableCell>
                      <TableCell className="text-xs text-right">{formatEur(m.total_brut ?? 0)}</TableCell>
                      <TableCell className="text-xs text-right">{m.taux_commission ?? 0}%</TableCell>
                      <TableCell className="text-xs text-right font-semibold text-primary">{formatEur(m.montant_commission_ht ?? 0)}</TableCell>
                    </TableRow>
                  );
                })}
              </TableBody>
            </Table>
          </div>
        )}

        {/* Totals */}
        <div className="border-t-2 border-border pt-4 space-y-2 max-w-xs ml-auto">
          <div className="flex justify-between text-sm">
            <span className="text-muted-foreground">Total commissions HT</span>
            <span className="font-medium text-foreground">{formatEur(facture.montant_ht ?? 0)}</span>
          </div>
          <div className="flex justify-between text-sm">
            <span className="text-muted-foreground">TVA ({facture.taux_tva ?? 20}%)</span>
            <span className="font-medium text-foreground">{formatEur(facture.montant_tva ?? 0)}</span>
          </div>
          <div className="flex justify-between text-lg font-bold border-t border-border pt-2">
            <span className="text-foreground">Total TTC</span>
            <span className="text-primary">{formatEur(facture.montant_ttc ?? 0)}</span>
          </div>
          {facture.mode_paiement && (
            <div className="flex justify-between text-xs pt-1">
              <span className="text-muted-foreground">Mode de paiement</span>
              <span className="text-foreground">{MODE_LABELS[facture.mode_paiement] ?? facture.mode_paiement}</span>
            </div>
          )}
        </div>

        {/* Payment info */}
        {facture.statut === 'PAYEE' && facture.date_paiement && (
          <div className="mt-6 flex items-center gap-2 bg-success/10 border border-success/20 rounded-xl p-3">
            <CheckCircle className="h-4 w-4 text-success shrink-0" />
            <p className="text-sm text-success">
              Payée le {format(new Date(facture.date_paiement), 'dd MMMM yyyy', { locale: fr })}
            </p>
          </div>
        )}

        {canPay && !facture.est_secteur_public && (
          <div className="mt-6 no-print">
            <PaiementVirement facture={facture} onUpdate={charger} />
          </div>
        )}

        <div className="mt-8 pt-4 border-t border-border text-[10px] text-muted-foreground text-center">
          <p>{ENTREPRISE.nom} — Plateforme de mise en relation soignants-établissements</p>
          <p>Facture détaillée — Commission sur missions terminées</p>
        </div>
      </div>

      {showCheckout && facture && (
        <StripeEmbeddedCheckout
          factureId={facture.id}
          open={showCheckout}
          onClose={() => setShowCheckout(false)}
          onComplete={() => { setShowCheckout(false); charger(); }}
        />
      )}
    </LayoutApp>
  );
}
