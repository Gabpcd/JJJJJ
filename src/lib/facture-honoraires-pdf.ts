import { supabase } from '@/integrations/supabase/client';
import { format } from 'date-fns';
import { fr } from 'date-fns/locale';
import { toast } from 'sonner';
import { MANDAT_FACTURATION_VERSION } from '@/constantes/mandatFacturation';
import { ENTREPRISE } from '@/constantes/entreprise';

const fmt = (v: number) => new Intl.NumberFormat('fr-FR', { style: 'currency', currency: 'EUR' }).format(Number(v) || 0);

/**
 * Télécharge le PDF d'une facture d'honoraires en la générant côté client via jsPDF.
 * Réutilisable depuis n'importe quel composant (soignant, étab, admin).
 *
 * Utilise pdf_s3_key si présent (Storage Supabase) — fallback génération client
 * sinon. Actuellement tout va par le fallback car generate-invoice ne stocke
 * pas encore les PDF en Storage (cf. logique-paiements-v1 §2.3).
 */
export async function telechargerFactureHonorairesPDF(factureId: string) {
  try {
    const { data: f } = await supabase
      .from('factures_honoraires')
      .select('*')
      .eq('id', factureId)
      .maybeSingle();
    if (!f) {
      toast.error('Facture introuvable');
      return;
    }

    // Si un PDF est déjà stocké dans Storage, on l'utilise directement
    if ((f as any).pdf_s3_key) {
      const { data: urlData } = await supabase.storage
        .from('factures-honoraires')
        .createSignedUrl((f as any).pdf_s3_key, 300);
      if (urlData?.signedUrl) {
        window.open(urlData.signedUrl, '_blank');
        toast.success('Facture ouverte');
        return;
      }
    }

    // Fallback : génération client via jsPDF
    const [{ data: sg }, { data: etab }, { data: mission }] = await Promise.all([
      supabase
        .from('soignants')
        .select('prenom, nom, profession, numero_rpps, numero_adeli, email, telephone, adresse_rue, adresse_code_postal, adresse_ville')
        .eq('id', (f as any).soignant_id)
        .maybeSingle(),
      supabase
        .from('etablissements')
        .select('nom, type, adresse_rue, adresse_code_postal, adresse_ville, siret, email_contact')
        .eq('id', (f as any).etablissement_id)
        .maybeSingle(),
      (f as any).mission_id
        ? supabase
            .from('missions')
            .select('intitule, profession_requise, debut_le, fin_le, duree_heures, taux_horaire_base')
            .eq('id', (f as any).mission_id)
            .maybeSingle()
        : Promise.resolve({ data: null }),
    ]);

    const { default: jsPDF } = await import('jspdf');
    const doc = new jsPDF();
    const TEAL = { r: 23, g: 162, b: 184 };

    doc.setFillColor(TEAL.r, TEAL.g, TEAL.b);
    doc.rect(0, 0, 210, 28, 'F');
    doc.setTextColor(255, 255, 255);
    doc.setFontSize(18);
    doc.setFont('helvetica', 'bold');
    doc.text("FACTURE D'HONORAIRES", 14, 17);
    doc.setFontSize(10);
    doc.setFont('helvetica', 'normal');
    doc.text((f as any).numero_facture, 14, 24);

    doc.setTextColor(80, 80, 80);
    doc.setFontSize(7);
    doc.text('Émise par Jolene en qualité de mandataire (Article 289 I-2 CGI)', 110, 17);
    doc.text(`Mandat version ${(f as any).mandat_version || MANDAT_FACTURATION_VERSION}`, 110, 22);

    let y = 40;
    doc.setTextColor(0, 0, 0);
    doc.setFontSize(9);
    doc.setFont('helvetica', 'bold');
    doc.text('ÉMETTEUR (vendeur légal)', 14, y);
    doc.setFont('helvetica', 'normal');
    y += 5;
    if (sg) {
      doc.text(`${sg.prenom || ''} ${sg.nom || ''}`.trim(), 14, y); y += 4;
      doc.text(sg.profession || '', 14, y); y += 4;
      if (sg.numero_rpps) { doc.text(`RPPS : ${sg.numero_rpps}`, 14, y); y += 4; }
      if (sg.numero_adeli) { doc.text(`ADELI : ${sg.numero_adeli}`, 14, y); y += 4; }
      if (sg.adresse_rue) { doc.text(sg.adresse_rue, 14, y); y += 4; }
      if (sg.adresse_code_postal) { doc.text(`${sg.adresse_code_postal} ${sg.adresse_ville || ''}`, 14, y); y += 4; }
      if (sg.email) { doc.text(sg.email, 14, y); y += 4; }
    }

    let yClient = 45;
    doc.setFont('helvetica', 'bold');
    doc.text('FACTURÉ À', 120, yClient);
    doc.setFont('helvetica', 'normal');
    yClient += 5;
    if (etab) {
      doc.text(etab.nom || '', 120, yClient); yClient += 4;
      if (etab.adresse_rue) { doc.text(etab.adresse_rue, 120, yClient); yClient += 4; }
      if (etab.adresse_code_postal) { doc.text(`${etab.adresse_code_postal} ${etab.adresse_ville || ''}`, 120, yClient); yClient += 4; }
      if (etab.siret) { doc.text(`SIRET : ${etab.siret}`, 120, yClient); yClient += 4; }
    }

    y = Math.max(y, yClient) + 8;
    doc.setDrawColor(200, 200, 200);
    doc.line(14, y, 196, y);
    y += 6;

    doc.setFontSize(9);
    const addInfo = (label: string, value: string) => {
      doc.setFont('helvetica', 'bold');
      doc.text(label, 14, y);
      doc.setFont('helvetica', 'normal');
      doc.text(value, 60, y);
      y += 5;
    };
    addInfo("Date d'émission :", format(new Date((f as any).date_emission), 'dd/MM/yyyy', { locale: fr }));
    if ((f as any).date_echeance) addInfo("Date d'échéance :", format(new Date((f as any).date_echeance), 'dd/MM/yyyy', { locale: fr }));
    if ((f as any).date_paiement) addInfo('Date de paiement :', format(new Date((f as any).date_paiement), 'dd/MM/yyyy', { locale: fr }));

    if (mission) {
      addInfo('Mission :', mission.intitule || '—');
      addInfo('Profession :', mission.profession_requise || '—');
      if (mission.debut_le && mission.fin_le) {
        addInfo('Période :', `${format(new Date(mission.debut_le), 'dd/MM/yyyy HH:mm', { locale: fr })} → ${format(new Date(mission.fin_le), 'dd/MM/yyyy HH:mm', { locale: fr })}`);
      }
      if (mission.duree_heures) addInfo('Heures :', `${mission.duree_heures} h`);
      if (mission.taux_horaire_base) addInfo('Taux horaire :', `${Number(mission.taux_horaire_base).toFixed(2)} €`);
    }

    y += 5;
    doc.setDrawColor(200, 200, 200);
    doc.line(14, y, 196, y);
    y += 8;

    doc.setFontSize(10);
    doc.setFont('helvetica', 'bold');
    doc.text('Montant HT', 14, y);
    doc.text(fmt(Number((f as any).montant_ht)), 196, y, { align: 'right' });
    y += 6;

    if ((f as any).exoneration_tva) {
      doc.setFont('helvetica', 'normal');
      doc.setFontSize(8);
      doc.text('TVA non applicable — Article 261-4 du CGI (actes médicaux et paramédicaux)', 14, y);
      y += 6;
    } else {
      doc.setFont('helvetica', 'normal');
      doc.text(`TVA (${(f as any).taux_tva}%)`, 14, y);
      doc.text(fmt(Number((f as any).montant_tva)), 196, y, { align: 'right' });
      y += 6;
    }

    doc.setFontSize(13);
    doc.setFont('helvetica', 'bold');
    doc.text('TOTAL TTC', 14, y);
    doc.text(fmt(Number((f as any).montant_ttc)), 196, y, { align: 'right' });
    y += 12;

    if ((f as any).statut === 'PAYEE') {
      doc.setFontSize(12);
      doc.setTextColor(40, 167, 69);
      doc.setFont('helvetica', 'bold');
      doc.text('✓ FACTURE PAYÉE', 14, y);
      y += 8;
      doc.setTextColor(0, 0, 0);
    }

    doc.setFontSize(8);
    doc.setFont('helvetica', 'normal');
    doc.text('Conditions de paiement : 30 jours date de facture.', 14, y); y += 4;
    doc.text("Pénalités de retard : 3× le taux d'intérêt légal. Indemnité forfaitaire : 40 €.", 14, y); y += 4;

    y = 272;
    doc.setFontSize(7);
    doc.setTextColor(120, 120, 120);
    doc.text('Facture émise par ' + ENTREPRISE.nom + ' en qualité de mandataire (Article 289 I-2 du CGI).', 14, y);
    y += 3;
    doc.text('Le professionnel ci-dessus demeure le vendeur légal de la prestation.', 14, y);
    y += 4;
    doc.text(
      `${ENTREPRISE.nom} · ${ENTREPRISE.forme_juridique} · Capital ${ENTREPRISE.capital_social} · SIRET ${ENTREPRISE.siret_formate} · ${ENTREPRISE.rcs}`,
      14,
      y,
    );
    y += 3;
    doc.text(`TVA intra : ${ENTREPRISE.tva_intra} · Siège : ${ENTREPRISE.adresse} · ${ENTREPRISE.email}`, 14, y);

    doc.save(`${(f as any).numero_facture}.pdf`);
    toast.success('Facture téléchargée');
  } catch (err: any) {
    toast.error(err?.message || 'Erreur génération PDF');
  }
}
