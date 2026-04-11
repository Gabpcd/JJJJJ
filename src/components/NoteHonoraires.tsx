import { Printer, Send, FileDown } from 'lucide-react';
import { format } from 'date-fns';
import { fr } from 'date-fns/locale';
import type jsPDF from 'jspdf';

interface NoteHonorairesProps {
  mission: any;
  soignant: any;
  etablissement?: any;
  onAudit?: () => void;
}

function fmt(v: number | null | undefined): string {
  if (v == null) return '—';
  return new Intl.NumberFormat('fr-FR', { style: 'currency', currency: 'EUR' }).format(v);
}

function genererNumeroNote(missionId: string): string {
  // Génère un numéro lisible à partir de l'ID mission si aucun numéro officiel n'existe
  const hash = missionId.replace(/-/g, '').substring(0, 8).toUpperCase();
  const date = new Date();
  return `NH-${date.getFullYear()}-${String(date.getMonth() + 1).padStart(2, '0')}-${hash}`;
}

async function genererPDFNote(m: any, soignant: any, etab: any) {
  const { default: jsPDF } = await import('jspdf');
  const doc = new jsPDF();
  const duree = m.duree_heures ?? 0;
  const tauxEffectif = m.taux_rist_plafonne || m.taux_horaire_base;
  const sousTotal = duree * tauxEffectif;
  const totalHT = m.total_brut || sousTotal;
  const assujettiTVA = soignant?.assujetti_tva === true;
  const tva = assujettiTVA ? totalHT * 0.2 : 0;
  const totalTTC = totalHT + tva;
  const numNote = m.numero_note_honoraires || genererNumeroNote(m.id);

  // Header
  doc.setFontSize(10);
  doc.setTextColor(100);
  doc.text('NOTE D\'HONORAIRES', 105, 20, { align: 'center' });
  doc.setFontSize(12);
  doc.setTextColor(224, 69, 144);
  doc.text(`N° ${numNote}`, 105, 28, { align: 'center' });
  doc.setDrawColor(200);
  doc.line(14, 32, 196, 32);

  // Soignant info
  doc.setFontSize(9);
  doc.setTextColor(0);
  let y = 40;
  doc.setFont('helvetica', 'bold');
  doc.text('DE :', 14, y);
  doc.setFont('helvetica', 'normal');
  y += 5;
  doc.text(`${soignant?.prenom || ''} ${soignant?.nom || ''}`, 14, y);
  if (soignant?.numero_rpps) { y += 4; doc.text(`RPPS : ${soignant.numero_rpps}`, 14, y); }
  if (soignant?.siret_liberal) { y += 4; doc.text(`SIRET : ${soignant.siret_liberal}`, 14, y); }
  if (soignant?.adresse_rue) { y += 4; doc.text(`${soignant.adresse_rue}, ${soignant.adresse_code_postal} ${soignant.adresse_ville}`, 14, y); }
  if (soignant?.iban) { y += 4; doc.text(`RIB : ${soignant.iban}`, 14, y); }

  // Etablissement info
  let yE = 40;
  doc.setFont('helvetica', 'bold');
  doc.text('À :', 110, yE);
  doc.setFont('helvetica', 'normal');
  yE += 5;
  doc.text(etab?.nom || '', 110, yE);
  if (etab?.siret) { yE += 4; doc.text(`SIRET : ${etab.siret}`, 110, yE); }
  if (etab?.finess) { yE += 4; doc.text(`FINESS : ${etab.finess}`, 110, yE); }
  if (etab?.adresse_rue) { yE += 4; doc.text(`${etab.adresse_rue}`, 110, yE); yE += 4; doc.text(`${etab.adresse_code_postal} ${etab.adresse_ville}`, 110, yE); }

  // Date de la note
  const startY = Math.max(y, yE) + 12;
  doc.text(`Date : ${format(new Date(), 'd MMMM yyyy', { locale: fr })}`, 14, startY);

  // Prestation
  let pY = startY + 10;
  doc.setDrawColor(200);
  doc.line(14, pY - 2, 196, pY - 2);
  doc.setFont('helvetica', 'bold');
  doc.text('PRESTATION', 14, pY + 4);
  doc.setFont('helvetica', 'normal');
  pY += 10;
  doc.text(`Mission : ${m.intitule}${m.service ? ` — ${m.service}` : ''}`, 14, pY);
  pY += 5;
  doc.text(`Date : ${format(new Date(m.debut_le), 'd MMMM yyyy', { locale: fr })} — ${format(new Date(m.debut_le), "HH'h'mm", { locale: fr })} → ${format(new Date(m.fin_le), "HH'h'mm", { locale: fr })}`, 14, pY);
  pY += 5;
  doc.text(`Durée : ${duree}h`, 14, pY);

  // Financial breakdown
  pY += 10;
  doc.line(14, pY - 2, 196, pY - 2);
  doc.setFont('helvetica', 'bold');
  doc.text('DÉCOMPTE', 14, pY + 4);
  doc.setFont('helvetica', 'normal');
  pY += 10;

  const addLine = (label: string, amount: string) => {
    doc.text(label, 14, pY);
    doc.text(amount, 180, pY, { align: 'right' });
    pY += 5;
  };

  addLine(`${duree}h × ${tauxEffectif?.toFixed(2)} €/h`, `${sousTotal.toFixed(2)} €`);
  if ((m.montant_majoration_nuit || 0) > 0) addLine('Majoration nuit', `+${(m.montant_majoration_nuit).toFixed(2)} €`);
  if ((m.montant_majoration_dimanche || 0) > 0) addLine('Majoration dimanche', `+${(m.montant_majoration_dimanche).toFixed(2)} €`);
  if ((m.montant_majoration_ferie || 0) > 0) addLine('Majoration jour férié', `+${(m.montant_majoration_ferie).toFixed(2)} €`);

  pY += 3;
  doc.line(14, pY, 196, pY);
  pY += 6;
  doc.setFont('helvetica', 'bold');
  addLine('TOTAL HT', `${totalHT.toFixed(2)} €`);

  if (assujettiTVA) {
    doc.setFont('helvetica', 'normal');
    addLine('TVA 20%', `${tva.toFixed(2)} €`);
    pY += 2;
    doc.setFont('helvetica', 'bold');
    doc.setFontSize(11);
    addLine('TOTAL TTC', `${totalTTC.toFixed(2)} €`);
    doc.setFontSize(9);
  }

  // Legal mentions
  pY += 8;
  doc.setFont('helvetica', 'normal');
  doc.setFontSize(7);
  doc.setTextColor(120);
  if (!assujettiTVA) {
    doc.text('TVA non applicable, art. 293 B du CGI', 14, pY);
    pY += 4;
  }
  doc.text('Dispensé d\'immatriculation au RCS et au RM', 14, pY);
  pY += 4;
  doc.text('En cas de retard de paiement, indemnité forfaitaire de recouvrement : 40 €', 14, pY);

  // Footer
  const pageH = doc.internal.pageSize.height;
  doc.setFontSize(7);
  doc.setTextColor(150);
  doc.text('Document généré via Jolene · SASU · SIRET 103 305 744 00015 · 103 rue de Vaugirard, 75006 Paris', 105, pageH - 10, { align: 'center' });

  doc.save(`note_honoraires_${m.numero_note_honoraires || m.id}.pdf`);
}

export function NoteHonoraires({ mission, soignant, etablissement, onAudit }: NoteHonorairesProps) {
  const m = mission;
  const etab = etablissement || m.etablissements;
  const duree = m.duree_heures ?? 0;
  const tauxEffectif = m.taux_rist_plafonne || m.taux_horaire_base;
  const sousTotal = duree * tauxEffectif;
  const assujettiTVA = soignant?.assujetti_tva === true;
  const tva = assujettiTVA ? (m.total_brut || sousTotal) * 0.2 : 0;
  const totalTTC = (m.total_brut || sousTotal) + tva;

  const handlePrint = () => {
    onAudit?.();
    window.print();
  };

  const handlePDF = async () => {
    onAudit?.();
    await genererPDFNote(m, soignant, etab);
  };

  return (
    <div className="bg-card border border-border rounded-2xl p-6 shadow-sm print:shadow-none print:border-0 print:p-0">
      {/* Header */}
      <div className="text-center mb-6 print:mb-4">
        <h2 className="text-lg font-bold text-foreground">NOTE D'HONORAIRES</h2>
        <p className="text-sm text-primary font-semibold mt-1">N° {m.numero_note_honoraires || genererNumeroNote(m.id)}</p>
      </div>

      {/* De / À */}
      <div className="grid grid-cols-1 md:grid-cols-2 gap-4 mb-6 text-sm">
        <div className="bg-muted/30 rounded-xl p-4">
          <p className="text-xs font-semibold text-muted-foreground uppercase tracking-wide mb-2">De :</p>
          <p className="font-semibold text-foreground">{soignant?.prenom} {soignant?.nom}</p>
          {soignant?.numero_rpps && <p className="text-xs text-muted-foreground">RPPS : {soignant.numero_rpps}</p>}
          {soignant?.siret_liberal && <p className="text-xs text-muted-foreground">SIRET : {soignant.siret_liberal}</p>}
          {soignant?.adresse_rue && <p className="text-xs text-muted-foreground mt-1">{soignant.adresse_rue}, {soignant.adresse_code_postal} {soignant.adresse_ville}</p>}
          {soignant?.iban && <p className="text-xs text-muted-foreground">RIB : {soignant.iban}</p>}
        </div>
        <div className="bg-muted/30 rounded-xl p-4">
          <p className="text-xs font-semibold text-muted-foreground uppercase tracking-wide mb-2">À :</p>
          <p className="font-semibold text-foreground">{etab?.nom}</p>
          {etab?.siret && <p className="text-xs text-muted-foreground">SIRET : {etab.siret}</p>}
          {etab?.finess && <p className="text-xs text-muted-foreground">FINESS : {etab.finess}</p>}
          {etab?.adresse_rue && <p className="text-xs text-muted-foreground mt-1">{etab.adresse_rue}, {etab.adresse_code_postal} {etab.adresse_ville}</p>}
        </div>
      </div>

      {/* Prestation */}
      <div className="border-t border-border pt-4 mb-4">
        <p className="text-xs font-semibold text-muted-foreground uppercase tracking-wide mb-2">Prestation</p>
        <p className="text-sm text-foreground">
          Date : {format(new Date(m.debut_le), 'd MMMM yyyy', { locale: fr })} — {format(new Date(m.debut_le), "HH'h'mm", { locale: fr })} → {format(new Date(m.fin_le), "HH'h'mm", { locale: fr })}
        </p>
        <p className="text-sm text-foreground">Nature : {m.intitule}{m.service ? ` — ${m.service}` : ''}</p>
        <p className="text-sm text-foreground">Durée : {duree}h</p>
      </div>

      {/* Décomposition */}
      <div className="border-t border-border pt-4 space-y-2 text-sm">
        <div className="flex justify-between">
          <span className="text-muted-foreground">Taux horaire</span>
          <span className="font-medium">{tauxEffectif?.toFixed(2)} €/h</span>
        </div>
        <div className="flex justify-between">
          <span className="text-muted-foreground">Sous-total ({duree}h × {tauxEffectif?.toFixed(2)} €)</span>
          <span className="font-medium">{fmt(sousTotal)}</span>
        </div>

        {(m.montant_majoration_nuit || 0) > 0 && (
          <div className="flex justify-between">
            <span className="text-muted-foreground">🌙 Majoration nuit</span>
            <span className="font-medium text-primary">+{fmt(m.montant_majoration_nuit)}</span>
          </div>
        )}
        {(m.montant_majoration_dimanche || 0) > 0 && (
          <div className="flex justify-between">
            <span className="text-muted-foreground">☀️ Majoration dimanche</span>
            <span className="font-medium text-primary">+{fmt(m.montant_majoration_dimanche)}</span>
          </div>
        )}
        {(m.montant_majoration_ferie || 0) > 0 && (
          <div className="flex justify-between">
            <span className="text-muted-foreground">🎌 Majoration jour férié</span>
            <span className="font-medium text-primary">+{fmt(m.montant_majoration_ferie)}</span>
          </div>
        )}

        <div className="border-t-2 border-primary/30 pt-3 mt-3">
          <div className="flex justify-between">
            <span className="font-bold text-foreground">TOTAL HT</span>
            <span className="text-xl font-bold text-primary">{fmt(m.total_brut)}</span>
          </div>
        </div>

        {assujettiTVA ? (
          <>
            <div className="flex justify-between">
              <span className="text-muted-foreground">TVA 20%</span>
              <span className="font-medium">{fmt(tva)}</span>
            </div>
            <div className="border-t-2 border-foreground/20 pt-3">
              <div className="flex justify-between">
                <span className="font-bold text-foreground text-lg">TOTAL TTC</span>
                <span className="text-2xl font-bold text-primary">{fmt(totalTTC)}</span>
              </div>
            </div>
          </>
        ) : (
          <>
            <div className="bg-muted/30 rounded-xl p-3 mt-3">
              <p className="text-xs text-muted-foreground italic">
                TVA non applicable, art. 293 B du CGI
              </p>
            </div>
            <div className="border-t-2 border-foreground/20 pt-3">
              <div className="flex justify-between">
                <span className="font-bold text-foreground text-lg">TOTAL À PAYER</span>
                <span className="text-2xl font-bold text-primary">{fmt(m.total_brut)}</span>
              </div>
            </div>
          </>
        )}

        <p className="text-[10px] text-muted-foreground italic mt-2">
          Dispensé d'immatriculation au RCS et au RM
        </p>
      </div>

      {/* Actions */}
      <div className="flex gap-3 mt-6 print:hidden">
        <button onClick={handlePDF} className="btn-primary flex-1 flex items-center justify-center gap-2">
          <FileDown className="h-4 w-4" /> Télécharger PDF
        </button>
        <button onClick={handlePrint} className="btn-secondary flex-1 flex items-center justify-center gap-2">
          <Printer className="h-4 w-4" /> Imprimer
        </button>
      </div>

      <p className="text-[10px] text-muted-foreground/60 italic text-center mt-3 print:hidden">
        Simulation à titre indicatif. Seuls les montants calculés par le moteur de paie font foi.
      </p>
    </div>
  );
}
