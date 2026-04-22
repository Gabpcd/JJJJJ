import { supabase } from '@/integrations/supabase/client';
import { format } from 'date-fns';
import { fr } from 'date-fns/locale';
import { toast } from 'sonner';
import { ENTREPRISE } from '@/constantes/entreprise';
import {
  JOLENE_COLORS,
  PAGE,
  sanitizeForPdf,
  fmtEur,
  createHeader,
  createInfoBlock,
  addInfoRow,
  createTotalsBlock,
  createFooter,
  createHighlightBox,
  createSectionTitle,
} from './pdf-design-system';

/**
 * Génère et télécharge le PDF d'une facture commission Jolene (étab ou admin).
 * Contenu RICHE cohérent avec la vue web détail facture :
 *   - Header rose Jolene avec statut
 *   - Blocs émetteur Jolene / destinataire étab
 *   - Mode de paiement (Stripe à la source / Virement / Chorus Pro)
 *   - Section "MISSIONS FACTURÉES" : pour chaque mission, décomposition
 *     financière (brut, majorations, IFM/ICP SALARIE) + commission HT/TVA/TTC +
 *     pointages réels si présents
 *   - Totaux HT / TVA / TTC globaux
 *   - Footer mentions légales Jolene
 */
export async function telechargerFactureCommissionPDF(factureId: string) {
  try {
    const { data: f } = await supabase
      .from('factures')
      .select('*')
      .eq('id', factureId)
      .maybeSingle();
    if (!f) {
      toast.error('Facture introuvable');
      return;
    }

    const [{ data: etab }] = await Promise.all([
      supabase
        .from('etablissements')
        .select('nom, adresse_rue, adresse_code_postal, adresse_ville, siret, email_contact')
        .eq('id', (f as any).etablissement_id)
        .maybeSingle(),
    ]);

    // Missions rattachées : soit la seule mission_id (facture par-mission), soit
    // celles reliées via facture_id pour les factures mensuelles groupées.
    let missions: any[] = [];
    if ((f as any).mission_id) {
      const { data: m } = await supabase
        .from('missions')
        .select(
          'id, intitule, service, profession_requise, debut_le, fin_le, duree_heures, taux_horaire_base, total_brut, net_a_payer, montant_ifm, montant_icp, montant_majoration_nuit, montant_majoration_dimanche, montant_majoration_ferie, heures_nuit, heures_dimanche, heures_ferie, type_contrat_applique, taux_commission_fige, montant_commission_ht, montant_commission_tva, montant_commission_ttc, soignant_assigne_id',
        )
        .eq('id', (f as any).mission_id);
      missions = m || [];
    } else {
      const { data: m } = await supabase
        .from('missions')
        .select(
          'id, intitule, service, profession_requise, debut_le, fin_le, duree_heures, taux_horaire_base, total_brut, net_a_payer, montant_ifm, montant_icp, montant_majoration_nuit, montant_majoration_dimanche, montant_majoration_ferie, heures_nuit, heures_dimanche, heures_ferie, type_contrat_applique, taux_commission_fige, montant_commission_ht, montant_commission_tva, montant_commission_ttc, soignant_assigne_id',
        )
        .eq('facture_id', (f as any).id);
      missions = m || [];
    }

    // Enrichir avec nom du soignant + pointages
    const soignantIds = [...new Set(missions.map((m) => m.soignant_assigne_id).filter(Boolean))];
    const missionIds = missions.map((m) => m.id);
    const [{ data: soignants }, { data: allPresences }] = await Promise.all([
      soignantIds.length > 0
        ? supabase.from('soignants').select('id, prenom, nom').in('id', soignantIds)
        : Promise.resolve({ data: [] as any[] }),
      missionIds.length > 0
        ? supabase
            .from('presences')
            .select('mission_id, pointage_arrivee_le, pointage_depart_le, duree_pause_min, heures_reelles')
            .in('mission_id', missionIds)
            .order('pointage_arrivee_le', { ascending: true })
        : Promise.resolve({ data: [] as any[] }),
    ]);
    const soignantMap = new Map((soignants || []).map((s: any) => [s.id, `${s.prenom || ''} ${s.nom || ''}`.trim()]));
    const presencesByMission = new Map<string, any[]>();
    for (const p of (allPresences as any[] | null) || []) {
      const list = presencesByMission.get(p.mission_id) || [];
      list.push(p);
      presencesByMission.set(p.mission_id, list);
    }

    const { default: jsPDF } = await import('jspdf');
    const autoTableMod = await import('jspdf-autotable');
    const autoTable = autoTableMod.default;
    const doc = new jsPDF();

    const statut = (f as any).statut;
    createHeader(doc, {
      title: 'FACTURE COMMISSION',
      subtitle: (f as any).numero_facture,
      statusLabel: statut === 'PAYEE' ? 'PAYÉE' : statut === 'EMISE' ? 'ÉMISE' : statut,
      statusColor: statut === 'PAYEE' ? 'success' : statut === 'EN_RETARD' ? 'warning' : 'muted',
    });

    // Mention facturation unifiée
    doc.setTextColor(...JOLENE_COLORS.textMuted);
    doc.setFont('helvetica', 'italic');
    doc.setFontSize(7);
    doc.text(
      sanitizeForPdf(`Facture commission Jolene - mise en relation soignants & établissements de santé`),
      PAGE.margin,
      36,
    );

    // Blocs émetteur (Jolene) / destinataire (étab)
    const blockY = 44;
    const yEmet = createInfoBlock(doc, {
      x: PAGE.margin,
      y: blockY,
      label: 'Émetteur',
      name: ENTREPRISE.nom,
      lines: [
        ENTREPRISE.forme_juridique,
        ENTREPRISE.adresse_ligne1,
        `${ENTREPRISE.adresse_code_postal} ${ENTREPRISE.adresse_ville}`,
        `SIRET : ${ENTREPRISE.siret_formate}`,
        `TVA intra : ${ENTREPRISE.tva_intra}`,
        ENTREPRISE.email,
      ],
    });
    const yDest = createInfoBlock(doc, {
      x: 115,
      y: blockY,
      label: 'Facturé à',
      name: etab?.nom || '(établissement)',
      lines: [
        etab?.adresse_rue,
        etab?.adresse_code_postal ? `${etab.adresse_code_postal} ${etab.adresse_ville || ''}` : null,
        etab?.siret ? `SIRET : ${etab.siret}` : null,
        etab?.email_contact,
      ],
    });
    let y = Math.max(yEmet, yDest) + 6;

    doc.setDrawColor(...JOLENE_COLORS.border);
    doc.setLineWidth(0.3);
    doc.line(PAGE.margin, y, PAGE.width - PAGE.margin, y);
    y += 6;

    addInfoRow(doc, PAGE.margin, y, 'Émission :', (f as any).date_emission ? format(new Date((f as any).date_emission), 'dd/MM/yyyy', { locale: fr }) : '-');
    if ((f as any).date_echeance) {
      addInfoRow(doc, 75, y, 'Échéance :', format(new Date((f as any).date_echeance), 'dd/MM/yyyy', { locale: fr }));
    }
    if ((f as any).date_paiement) {
      addInfoRow(doc, 140, y, 'Payée le :', format(new Date((f as any).date_paiement), 'dd/MM/yyyy', { locale: fr }));
    }
    y += 6;

    // Mode de paiement
    const mode = (f as any).mode_paiement;
    const modeLabel =
      mode === 'STRIPE' && (f as any).stripe_payment_intent_id
        ? 'Stripe Connect (capturée à la source)'
        : mode === 'STRIPE'
        ? 'Stripe'
        : mode === 'VIREMENT'
        ? `Virement${(f as any).virement_reference ? ' - réf. ' + (f as any).virement_reference : ''}`
        : mode === 'CHORUS_PRO'
        ? 'Chorus Pro'
        : mode || '-';
    addInfoRow(doc, PAGE.margin, y, 'Mode paiement :', modeLabel, 30);
    y += 8;

    // Section MISSIONS FACTURÉES — rendu riche
    if (missions.length > 0) {
      y = createSectionTitle(doc, y, 'Missions facturées');

      for (const m of missions) {
        // Bandeau mission : intitulé + soignant + dates
        if (y > 240) { doc.addPage(); y = 20; }
        doc.setFillColor(...JOLENE_COLORS.roseLight);
        doc.rect(PAGE.margin, y, PAGE.contentWidth, 8, 'F');
        doc.setTextColor(...JOLENE_COLORS.primaryDark);
        doc.setFont('helvetica', 'bold');
        doc.setFontSize(9);
        doc.text(sanitizeForPdf(m.intitule || '(mission)'), PAGE.margin + 2, y + 5.5);
        doc.setFont('helvetica', 'normal');
        doc.setTextColor(...JOLENE_COLORS.textMuted);
        doc.setFontSize(8);
        const soignantNom = soignantMap.get(m.soignant_assigne_id) || 'Soignant';
        const dateStr = m.debut_le ? format(new Date(m.debut_le), 'dd/MM/yyyy', { locale: fr }) : '-';
        doc.text(`${soignantNom} - ${dateStr} - ${m.profession_requise || '-'}`, PAGE.width - PAGE.margin - 2, y + 5.5, { align: 'right' });
        y += 10;

        // Décomposition financière mission (table compacte)
        const totalBrut = Number(m.total_brut || 0);
        const majorations =
          Number(m.montant_majoration_nuit || 0) +
          Number(m.montant_majoration_dimanche || 0) +
          Number(m.montant_majoration_ferie || 0);
        const tauxCommission = Number(m.taux_commission_fige || 15);
        const decompoRows: (string | number)[][] = [
          ['Brut de base', `${m.duree_heures || 0} h × ${Number(m.taux_horaire_base || 0).toFixed(2)} €`, fmtEur(totalBrut - majorations)],
        ];
        if (m.heures_nuit && Number(m.heures_nuit) > 0) {
          decompoRows.push(['Maj. nuit', `${m.heures_nuit} h`, `+${fmtEur(m.montant_majoration_nuit || 0)}`]);
        }
        if (m.heures_dimanche && Number(m.heures_dimanche) > 0) {
          decompoRows.push(['Maj. dimanche', `${m.heures_dimanche} h`, `+${fmtEur(m.montant_majoration_dimanche || 0)}`]);
        }
        if (m.heures_ferie && Number(m.heures_ferie) > 0) {
          decompoRows.push(['Maj. férié', `${m.heures_ferie} h`, `+${fmtEur(m.montant_majoration_ferie || 0)}`]);
        }
        decompoRows.push(['Brut soignant', '', fmtEur(totalBrut)]);

        if (m.type_contrat_applique === 'SALARIE') {
          const ifm = Number(m.montant_ifm || 0);
          const icp = Number(m.montant_icp || 0);
          const superBrut = totalBrut + ifm + icp;
          decompoRows.push(['IFM (10%)', '', `+${fmtEur(ifm)}`]);
          decompoRows.push(['ICP (10%)', '', `+${fmtEur(icp)}`]);
          decompoRows.push(['Super brut (assiette commission)', '', fmtEur(superBrut)]);
        }

        decompoRows.push([`Commission Jolene (${tauxCommission}%)`, '', fmtEur(m.montant_commission_ht || 0)]);
        decompoRows.push(['TVA 20%', '', fmtEur(m.montant_commission_tva || 0)]);
        decompoRows.push(['Commission TTC mission', '', fmtEur(m.montant_commission_ttc || 0)]);

        autoTable(doc, {
          startY: y,
          body: decompoRows,
          styles: { fontSize: 7.5, cellPadding: 1.8, textColor: JOLENE_COLORS.text as any },
          columnStyles: {
            0: { cellWidth: 60 },
            1: { cellWidth: 60 },
            2: { halign: 'right', cellWidth: 'auto', fontStyle: 'bold' },
          },
          margin: { left: PAGE.margin, right: PAGE.margin },
          didParseCell: (data) => {
            if (data.section === 'body') {
              const label = String(data.row.cells[0]?.raw || '');
              if (label.includes('Commission TTC mission')) {
                data.cell.styles.fillColor = JOLENE_COLORS.primary as any;
                data.cell.styles.textColor = [255, 255, 255] as any;
                data.cell.styles.fontStyle = 'bold';
              } else if (label.includes('Commission Jolene') || label.includes('Super brut') || label.includes('Brut soignant')) {
                data.cell.styles.fillColor = JOLENE_COLORS.roseLight as any;
                data.cell.styles.fontStyle = 'bold';
              }
            }
          },
        });
        y = (doc as any).lastAutoTable?.finalY ? (doc as any).lastAutoTable.finalY + 3 : y + 30;

        // Pointages détaillés (si présents)
        const pres = presencesByMission.get(m.id) || [];
        if (pres.length > 0) {
          if (y > 250) { doc.addPage(); y = 20; }
          doc.setTextColor(...JOLENE_COLORS.textMuted);
          doc.setFont('helvetica', 'bold');
          doc.setFontSize(7.5);
          doc.text(sanitizeForPdf(`Pointages (${pres.length})`), PAGE.margin + 2, y + 3);
          y += 4;
          autoTable(doc, {
            startY: y,
            head: [['Date', 'Arrivée', 'Départ', 'Pause', 'Heures']],
            body: pres.map((p) => {
              const arr = p.pointage_arrivee_le ? new Date(p.pointage_arrivee_le) : null;
              const dep = p.pointage_depart_le ? new Date(p.pointage_depart_le) : null;
              return [
                arr ? format(arr, 'dd/MM', { locale: fr }) : '-',
                arr ? format(arr, "HH'h'mm", { locale: fr }) : '-',
                dep ? format(dep, "HH'h'mm", { locale: fr }) : '-',
                Number(p.duree_pause_min ?? 0) > 0 ? `${p.duree_pause_min} min` : '-',
                Number(p.heures_reelles ?? 0) > 0 ? `${Number(p.heures_reelles).toFixed(2)} h` : '-',
              ];
            }),
            styles: { fontSize: 7, cellPadding: 1.5, textColor: JOLENE_COLORS.text as any },
            headStyles: { fillColor: JOLENE_COLORS.teal as any, textColor: [255, 255, 255] as any, fontStyle: 'bold' },
            alternateRowStyles: { fillColor: [245, 250, 249] as any },
            margin: { left: PAGE.margin + 6, right: PAGE.margin },
            tableWidth: PAGE.contentWidth - 6,
          });
          y = (doc as any).lastAutoTable?.finalY ? (doc as any).lastAutoTable.finalY + 4 : y + 20;
        } else {
          y += 3;
        }
      }
    }

    // Totaux globaux
    if (y > 240) { doc.addPage(); y = 20; }
    y += 2;
    y = createTotalsBlock(doc, {
      y,
      ht: Number((f as any).montant_ht),
      tva: Number((f as any).montant_tva),
      ttc: Number((f as any).montant_ttc),
      tauxTva: (f as any).taux_tva,
    });

    if (statut === 'PAYEE') {
      createHighlightBox(doc, {
        x: PAGE.margin,
        y,
        width: PAGE.contentWidth,
        text: (f as any).date_paiement
          ? `FACTURE PAYÉE le ${format(new Date((f as any).date_paiement), 'dd/MM/yyyy', { locale: fr })} - ${modeLabel}`
          : `FACTURE PAYÉE - ${modeLabel}`,
        variant: 'success',
      });
    }

    createFooter(doc, {
      companyLine: `${ENTREPRISE.nom} - ${ENTREPRISE.forme_juridique} - Capital ${ENTREPRISE.capital_social} - SIRET ${ENTREPRISE.siret_formate} - ${ENTREPRISE.rcs}`,
      contactLine: `TVA intra : ${ENTREPRISE.tva_intra} - Siège : ${ENTREPRISE.adresse} - ${ENTREPRISE.email}`,
      extraLine: `Facture générée le ${format(new Date(), 'dd/MM/yyyy à HH:mm', { locale: fr })}`,
    });

    doc.save(`${(f as any).numero_facture}.pdf`);
    toast.success('Facture téléchargée');
  } catch (err: any) {
    console.error('Erreur génération PDF facture commission:', err);
    toast.error(err?.message || 'Erreur génération PDF');
  }
}
