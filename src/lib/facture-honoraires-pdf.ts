import { supabase } from '@/integrations/supabase/client';
import { format } from 'date-fns';
import { fr } from 'date-fns/locale';
import { toast } from 'sonner';
import { telechargerOuPartagerPdf } from './telechargement';
import { MANDAT_FACTURATION_VERSION } from '@/constantes/mandatFacturation';
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
 * Génère et télécharge le PDF d'une facture d'honoraires (soignant mandataire
 * Jolene). Design unifié selon la charte Jolene (rose / primary). Réutilisable
 * depuis n'importe quel composant (soignant / étab / admin).
 *
 * Contenu adapté au `type_contrat_applique` de la mission :
 *   - LIBERAL : brut honoraires, pas de cotisations
 *   - SALARIE : brut + IFM + ICP + cotisations estimées -> NET
 *
 * Inclut le détail des pointages (table `presences`) si disponibles.
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

    // Toujours régénérer depuis les données comptables courantes. Les anciens
    // PDF stockés pouvaient reprendre le total de la mission au lieu de la
    // seule période facturée.

    // PASSE 1 enrichissement : charger tous les champs nécessaires au rendu
    // détaillé (taux majorations figés, taux IFM/ICP, spécialités soignant,
    // créneaux prévisionnels fallback).
    const [{ data: sg }, { data: etab }, { data: mission }, { data: presences }, { data: creneaux }] = await Promise.all([
      supabase
        .from('soignants')
        .select('prenom, nom, profession, specialites, numero_rpps, numero_adeli, email, telephone, adresse_rue, adresse_code_postal, adresse_ville')
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
            .select(
              'intitule, service, profession_requise, debut_le, fin_le, duree_heures, ' +
              'taux_horaire_base, taux_horaire_base_fige, total_brut, net_a_payer, net_estime, ' +
              'montant_ifm, montant_icp, taux_ifm, taux_icp, ' +
              'montant_majoration_nuit, montant_majoration_dimanche, montant_majoration_ferie, ' +
              'heures_nuit, heures_dimanche, heures_ferie, ' +
              'taux_majoration_nuit_fige, taux_majoration_dimanche_fige, taux_majoration_ferie_fige, ' +
              'type_contrat_applique, taux_commission_fige',
            )
            .eq('id', (f as any).mission_id)
            .maybeSingle()
        : Promise.resolve({ data: null }),
      (f as any).mission_id
        ? supabase
            .from('presences')
            .select('pointage_arrivee_le, pointage_depart_le, pause_debut_le, pause_fin_le, duree_pause_min, heures_reelles')
            .eq('mission_id', (f as any).mission_id)
            .order('pointage_arrivee_le', { ascending: true })
        : Promise.resolve({ data: null as any }),
      (f as any).mission_id
        ? supabase
            .from('mission_creneaux')
            .select('debut_le, fin_le, type_creneau, duree_heures')
            .eq('mission_id', (f as any).mission_id)
            .eq('type_creneau', 'PREVISIONNEL')
            .order('debut_le', { ascending: true })
        : Promise.resolve({ data: null as any }),
    ]);

    const { default: jsPDF } = await import('jspdf');
    const autoTableMod = await import('jspdf-autotable');
    const autoTable = autoTableMod.default;
    const doc = new jsPDF();

    const statut = (f as any).statut;
    createHeader(doc, {
      title: "FACTURE D'HONORAIRES",
      subtitle: (f as any).numero_facture,
      statusLabel: statut === 'PAYEE' ? 'PAYÉE' : statut,
      statusColor: statut === 'PAYEE' ? 'success' : statut === 'EN_RETARD' ? 'warning' : 'muted',
    });

    // Mention mandataire
    doc.setTextColor(...JOLENE_COLORS.textMuted);
    doc.setFont('helvetica', 'italic');
    doc.setFontSize(7);
    doc.text(
      sanitizeForPdf(`Émise par ${ENTREPRISE.nom} en qualité de mandataire (art. 289 I-2 CGI) - Mandat v${(f as any).mandat_version || MANDAT_FACTURATION_VERSION}`),
      PAGE.margin,
      36,
    );

    // Blocs émetteur / destinataire (côte à côte)
    const blockY = 44;
    const yEmet = createInfoBlock(doc, {
      x: PAGE.margin,
      y: blockY,
      label: 'Émetteur (vendeur légal)',
      name: sg ? `${sg.prenom || ''} ${sg.nom || ''}`.trim() : '(soignant)',
      lines: [
        sg?.profession,
        sg?.numero_rpps ? `RPPS : ${sg.numero_rpps}` : null,
        sg?.numero_adeli ? `ADELI : ${sg.numero_adeli}` : null,
        sg?.adresse_rue,
        sg?.adresse_code_postal ? `${sg.adresse_code_postal} ${sg.adresse_ville || ''}` : null,
        sg?.email,
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

    // Métadonnées facture (2 colonnes)
    doc.setDrawColor(...JOLENE_COLORS.border);
    doc.setLineWidth(0.3);
    doc.line(PAGE.margin, y, PAGE.width - PAGE.margin, y);
    y += 6;

    addInfoRow(doc, PAGE.margin, y, "Émission :", format(new Date((f as any).date_emission), 'dd/MM/yyyy', { locale: fr }));
    if ((f as any).date_echeance) {
      addInfoRow(doc, 75, y, 'Échéance :', format(new Date((f as any).date_echeance), 'dd/MM/yyyy', { locale: fr }));
    }
    if ((f as any).date_paiement) {
      addInfoRow(doc, 140, y, 'Payée le :', format(new Date((f as any).date_paiement), 'dd/MM/yyyy', { locale: fr }));
    }
    y += 6;

    // ── PASSE 2 : Mission info enrichi (service, dates complètes, profession, spécialité) ──
    if (mission) {
      const sgSpec = ((sg as any)?.specialites || []).join(', ');
      addInfoRow(doc, PAGE.margin, y, 'Mission :', mission.intitule || '-');
      y += 5;
      if (mission.service) {
        addInfoRow(doc, PAGE.margin, y, 'Service :', mission.service);
        y += 5;
      }
      const profLabel = sgSpec ? `${mission.profession_requise || '-'} - ${sgSpec}` : (mission.profession_requise || '-');
      addInfoRow(doc, PAGE.margin, y, 'Profession :', profLabel);
      y += 5;
      addInfoRow(doc, PAGE.margin, y, 'Type contrat :', mission.type_contrat_applique === 'SALARIE' ? 'Salarié (CDD)' : 'Libéral');
      y += 5;
      const periodeDebut = (f as any).periode_debut || mission.debut_le;
      const periodeFin = (f as any).periode_fin || mission.fin_le;
      if (periodeDebut && periodeFin) {
        const debutStr = format(new Date(periodeDebut), "dd/MM/yyyy HH'h'mm", { locale: fr });
        const finStr = format(new Date(periodeFin), "dd/MM/yyyy HH'h'mm", { locale: fr });
        const dureeStr = (f as any).periode_debut && (f as any).periode_fin ? '' : (mission.duree_heures ? ` (${Number(mission.duree_heures).toFixed(1)} h)` : '');
        addInfoRow(doc, PAGE.margin, y, 'Période :', `${debutStr} -> ${finStr}${dureeStr}`, 22);
        y += 5;
      }
      y += 3;
    }

    // ── PASSE 3 : Section pointages avec fallback ──
    const debutFacture = (f as any).periode_debut ? new Date(`${String((f as any).periode_debut).slice(0, 10)}T00:00:00`) : null;
    const finFacture = (f as any).periode_fin ? new Date(`${String((f as any).periode_fin).slice(0, 10)}T23:59:59.999`) : null;
    const dansPeriodeFacturee = (date?: string | null) => {
      if (!date || !debutFacture || !finFacture) return true;
      const valeur = new Date(date).getTime();
      return valeur >= debutFacture.getTime() && valeur <= finFacture.getTime();
    };
    const presList = ((presences as any[] | null) || []).filter((p) => dansPeriodeFacturee(p.pointage_arrivee_le));
    const creneauxList = ((creneaux as any[] | null) || []).filter((c) => dansPeriodeFacturee(c.debut_le));
    const heuresFacturees = presList.length > 0
      ? presList.reduce((total, p) => total + Number(p.heures_reelles || 0), 0)
      : creneauxList.reduce((total, c) => total + Number(c.duree_heures || 0), 0);
    if (presList.length > 0) {
      y = createSectionTitle(doc, y, 'Détail des pointages');
      autoTable(doc, {
        startY: y,
        head: [['Date', 'Arrivée', 'Départ', 'Pause', 'Heures eff.']],
        body: presList.map((p) => {
          const arr = p.pointage_arrivee_le ? new Date(p.pointage_arrivee_le) : null;
          const dep = p.pointage_depart_le ? new Date(p.pointage_depart_le) : null;
          const pauseMin = Number(p.duree_pause_min ?? 0);
          const heures = Number(p.heures_reelles ?? 0);
          return [
            arr ? format(arr, 'dd/MM/yyyy', { locale: fr }) : '-',
            arr ? format(arr, "HH'h'mm", { locale: fr }) : '-',
            dep ? format(dep, "HH'h'mm", { locale: fr }) : '-',
            pauseMin > 0 ? `${pauseMin} min` : '-',
            heures > 0 ? `${heures.toFixed(2)} h` : '-',
          ];
        }),
        styles: { fontSize: 8, cellPadding: 2, textColor: JOLENE_COLORS.text as any },
        headStyles: { fillColor: JOLENE_COLORS.teal as any, textColor: [255, 255, 255] as any, fontStyle: 'bold' },
        alternateRowStyles: { fillColor: [245, 250, 249] as any },
        margin: { left: PAGE.margin, right: PAGE.margin },
      });
      y = (doc as any).lastAutoTable?.finalY ? (doc as any).lastAutoTable.finalY + 6 : y + 30;
    } else if (creneauxList.length > 0) {
      y = createSectionTitle(doc, y, 'Créneaux prévisionnels');
      doc.setTextColor(...JOLENE_COLORS.textMuted);
      doc.setFont('helvetica', 'italic');
      doc.setFontSize(7);
      doc.text(sanitizeForPdf('Aucun pointage enregistre - creneaux previsionnels :'), PAGE.margin, y);
      y += 3;
      autoTable(doc, {
        startY: y,
        head: [['Date', 'Début', 'Fin', 'Durée prév.']],
        body: creneauxList.map((c) => [
          c.debut_le ? format(new Date(c.debut_le), 'dd/MM/yyyy', { locale: fr }) : '-',
          c.debut_le ? format(new Date(c.debut_le), "HH'h'mm", { locale: fr }) : '-',
          c.fin_le ? format(new Date(c.fin_le), "HH'h'mm", { locale: fr }) : '-',
          c.duree_heures ? `${Number(c.duree_heures).toFixed(1)} h` : '-',
        ]),
        styles: { fontSize: 7.5, cellPadding: 1.5, textColor: JOLENE_COLORS.textMuted as any },
        headStyles: { fillColor: JOLENE_COLORS.border as any, textColor: JOLENE_COLORS.text as any, fontStyle: 'bold' },
        margin: { left: PAGE.margin, right: PAGE.margin },
      });
      y = (doc as any).lastAutoTable?.finalY ? (doc as any).lastAutoTable.finalY + 6 : y + 20;
    } else {
      doc.setTextColor(...JOLENE_COLORS.textMuted);
      doc.setFont('helvetica', 'italic');
      doc.setFontSize(7.5);
      doc.text(sanitizeForPdf('Aucun pointage enregistre (duree previsionnelle utilisee).'), PAGE.margin, y + 3);
      y += 10;
    }

    // Section décomposition financière adaptée au type de contrat
    if (mission?.type_contrat_applique === 'SALARIE') {
      y = createSectionTitle(doc, y, 'Décomposition CDD (Modèle A salarié)');
      const totalBrut = Number((f as any).montant_ht || 0);
      const ifm = Number(mission.montant_ifm || 0);
      const icp = Number(mission.montant_icp || 0);
      const superBrut = totalBrut + ifm + icp;
      const net = Number(mission.net_a_payer || mission.net_estime || superBrut * 0.78);
      const cotisations = superBrut - net;
      const majorations =
        Number(mission.montant_majoration_nuit || 0) +
        Number(mission.montant_majoration_dimanche || 0) +
        Number(mission.montant_majoration_ferie || 0);

      // ── PASSE 4 : majorations détaillées avec taux figés ──
      const tauxHoraire = Number(mission.taux_horaire_base_fige || mission.taux_horaire_base || 0);
      const rows: (string | number)[][] = [
        ['Brut de base', `${mission.duree_heures || 0} h x ${tauxHoraire.toFixed(2)} E/h`, fmtEur(totalBrut - majorations)],
      ];
      if (mission.heures_nuit && Number(mission.heures_nuit) > 0) {
        const tauxMajNuit = Number(mission.taux_majoration_nuit_fige || 25);
        rows.push(['Majoration nuit', `${Number(mission.heures_nuit).toFixed(1)} h x ${tauxHoraire.toFixed(2)} E x ${tauxMajNuit}%`, `+${fmtEur(mission.montant_majoration_nuit || 0)}`]);
      }
      if (mission.heures_dimanche && Number(mission.heures_dimanche) > 0) {
        const tauxMajDim = Number(mission.taux_majoration_dimanche_fige || 25);
        rows.push(['Majoration dimanche', `${Number(mission.heures_dimanche).toFixed(1)} h x ${tauxHoraire.toFixed(2)} E x ${tauxMajDim}%`, `+${fmtEur(mission.montant_majoration_dimanche || 0)}`]);
      }
      if (mission.heures_ferie && Number(mission.heures_ferie) > 0) {
        const tauxMajFerie = Number(mission.taux_majoration_ferie_fige || 50);
        rows.push(['Majoration férié', `${Number(mission.heures_ferie).toFixed(1)} h x ${tauxHoraire.toFixed(2)} E x ${tauxMajFerie}%`, `+${fmtEur(mission.montant_majoration_ferie || 0)}`]);
      }
      rows.push(['Brut total', '', fmtEur(totalBrut)]);
      const tauxIFM = Number(mission.taux_ifm || 10);
      const tauxICP = Number(mission.taux_icp || 10);
      rows.push([`IFM (${tauxIFM}%)`, '', `+${fmtEur(ifm)}`]);
      rows.push([`ICP (${tauxICP}%)`, '', `+${fmtEur(icp)}`]);
      rows.push(['Super brut (cout employeur)', '', fmtEur(superBrut)]);
      rows.push([`Cotisations salariales estimees (~22%)`, '', `-${fmtEur(cotisations)}`]);
      rows.push(['NET a verser au soignant', '', fmtEur(net)]);

      autoTable(doc, {
        startY: y,
        head: [['Ligne', 'Détail', 'Montant']],
        body: rows,
        styles: { fontSize: 8, cellPadding: 2.5, textColor: JOLENE_COLORS.text as any },
        headStyles: { fillColor: JOLENE_COLORS.primary as any, textColor: [255, 255, 255] as any, fontStyle: 'bold' },
        alternateRowStyles: { fillColor: JOLENE_COLORS.roseLight as any },
        columnStyles: { 2: { halign: 'right', fontStyle: 'bold' } },
        margin: { left: PAGE.margin, right: PAGE.margin },
        didParseCell: (data) => {
          if (data.section === 'body') {
            const label = String(data.row.cells[0]?.raw || '');
            if (label.includes('NET a verser')) {
              data.cell.styles.fillColor = JOLENE_COLORS.primary as any;
              data.cell.styles.textColor = [255, 255, 255] as any;
              data.cell.styles.fontStyle = 'bold';
              data.cell.styles.fontSize = 10;
            }
          }
        },
      });
      y = (doc as any).lastAutoTable?.finalY ? (doc as any).lastAutoTable.finalY + 6 : y + 40;

      y = createHighlightBox(doc, {
        x: PAGE.margin,
        y,
        width: PAGE.contentWidth,
        text: 'Employeur URSSAF : établissement - Jolene intervient comme prestataire bulletin de paie.',
        variant: 'info',
      });
    } else if (mission) {
      // LIBERAL (default)
      y = createSectionTitle(doc, y, 'Décomposition libérale');
      const totalBrutMission = Number(mission.total_brut || 0);
      const totalBrut = Number((f as any).montant_ht || 0);
      const majorations =
        Number(mission.montant_majoration_nuit || 0) +
        Number(mission.montant_majoration_dimanche || 0) +
        Number(mission.montant_majoration_ferie || 0);

      // ── PASSE 4 : majorations détaillées (branche LIBERAL) ──
      const tauxHoraireLib = Number(mission.taux_horaire_base_fige || mission.taux_horaire_base || 0);
      const facturePartielle = Math.abs(totalBrut - totalBrutMission) > 0.01;
      const detailHeures = heuresFacturees > 0
        ? `${heuresFacturees.toFixed(1)} h x ${tauxHoraireLib.toFixed(2)} E/h`
        : 'Période facturée';
      const rows: (string | number)[][] = facturePartielle
        ? [['Honoraires de la période', detailHeures, fmtEur(totalBrut)]]
        : [['Brut de base', `${mission.duree_heures || 0} h x ${tauxHoraireLib.toFixed(2)} E/h`, fmtEur(totalBrut - majorations)]];
      if (!facturePartielle && mission.heures_nuit && Number(mission.heures_nuit) > 0) {
        const tauxMajNuit = Number(mission.taux_majoration_nuit_fige || 25);
        rows.push(['Majoration nuit', `${Number(mission.heures_nuit).toFixed(1)} h x ${tauxHoraireLib.toFixed(2)} E x ${tauxMajNuit}%`, `+${fmtEur(mission.montant_majoration_nuit || 0)}`]);
      }
      if (!facturePartielle && mission.heures_dimanche && Number(mission.heures_dimanche) > 0) {
        const tauxMajDim = Number(mission.taux_majoration_dimanche_fige || 25);
        rows.push(['Majoration dimanche', `${Number(mission.heures_dimanche).toFixed(1)} h x ${tauxHoraireLib.toFixed(2)} E x ${tauxMajDim}%`, `+${fmtEur(mission.montant_majoration_dimanche || 0)}`]);
      }
      if (!facturePartielle && mission.heures_ferie && Number(mission.heures_ferie) > 0) {
        const tauxMajFerie = Number(mission.taux_majoration_ferie_fige || 50);
        rows.push(['Majoration férié', `${Number(mission.heures_ferie).toFixed(1)} h x ${tauxHoraireLib.toFixed(2)} E x ${tauxMajFerie}%`, `+${fmtEur(mission.montant_majoration_ferie || 0)}`]);
      }
      rows.push(['Brut honoraires soignant', '', fmtEur(totalBrut)]);

      autoTable(doc, {
        startY: y,
        head: [['Ligne', 'Détail', 'Montant']],
        body: rows,
        styles: { fontSize: 8, cellPadding: 2.5, textColor: JOLENE_COLORS.text as any },
        headStyles: { fillColor: JOLENE_COLORS.primary as any, textColor: [255, 255, 255] as any, fontStyle: 'bold' },
        alternateRowStyles: { fillColor: JOLENE_COLORS.roseLight as any },
        columnStyles: { 2: { halign: 'right', fontStyle: 'bold' } },
        margin: { left: PAGE.margin, right: PAGE.margin },
        didParseCell: (data) => {
          if (data.section === 'body') {
            const label = String(data.row.cells[0]?.raw || '');
            if (label.includes('Brut honoraires soignant')) {
              data.cell.styles.fillColor = JOLENE_COLORS.primary as any;
              data.cell.styles.textColor = [255, 255, 255] as any;
              data.cell.styles.fontStyle = 'bold';
              data.cell.styles.fontSize = 10;
            }
          }
        },
      });
      y = (doc as any).lastAutoTable?.finalY ? (doc as any).lastAutoTable.finalY + 6 : y + 30;

      y = createHighlightBox(doc, {
        x: PAGE.margin,
        y,
        width: PAGE.contentWidth,
        text: 'Le soignant cotise directement auprès URSSAF libérale et de sa caisse de retraite (CARPIMKO/CIPAV).',
        variant: 'info',
      });
    }

    y += 2;
    y = createTotalsBlock(doc, {
      y,
      ht: Number((f as any).montant_ht),
      tva: Number((f as any).montant_tva),
      ttc: Number((f as any).montant_ttc),
      tauxTva: (f as any).taux_tva,
      exonerationTva: (f as any).exoneration_tva,
    });

    if (statut === 'PAYEE') {
      y += 2;
      createHighlightBox(doc, {
        x: PAGE.margin,
        y,
        width: PAGE.contentWidth,
        text: (f as any).date_paiement
          ? `FACTURE PAYÉE le ${format(new Date((f as any).date_paiement), 'dd/MM/yyyy', { locale: fr })}`
          : 'FACTURE PAYÉE',
        variant: 'success',
      });
    }

    createFooter(doc, {
      companyLine: `${ENTREPRISE.nom} - ${ENTREPRISE.forme_juridique} - Capital ${ENTREPRISE.capital_social} - SIRET ${ENTREPRISE.siret_formate} - ${ENTREPRISE.rcs}`,
      contactLine: `TVA intra : ${ENTREPRISE.tva_intra} - Siège : ${ENTREPRISE.adresse} - ${ENTREPRISE.email}`,
      extraLine: `Facture émise par ${ENTREPRISE.nom} en qualité de mandataire (art. 289 I-2 CGI). Le professionnel ci-dessus demeure le vendeur légal.`,
    });

    await telechargerOuPartagerPdf(doc, `${(f as any).numero_facture}.pdf`);
    toast.success('Facture prête');
  } catch (err: any) {
    console.error('Erreur génération PDF facture honoraires:', err);
    toast.error(err?.message || 'Erreur génération PDF');
  }
}
