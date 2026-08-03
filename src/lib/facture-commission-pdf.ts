import { supabase } from '@/integrations/supabase/client';
import { telechargerOuPartagerPdf } from './telechargement';
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
    // Enrichissement PASSE 1 : récupérer tous les champs nécessaires au rendu
    // détaillé (service, net_estime, taux IFM/ICP, taux majorations figés).
    const missionSelect =
      'id, intitule, service, profession_requise, debut_le, fin_le, duree_heures, ' +
      'taux_horaire_base, taux_horaire_base_fige, total_brut, net_a_payer, net_estime, ' +
      'montant_ifm, montant_icp, taux_ifm, taux_icp, ' +
      'montant_majoration_nuit, montant_majoration_dimanche, montant_majoration_ferie, ' +
      'heures_nuit, heures_dimanche, heures_ferie, ' +
      'taux_majoration_nuit_fige, taux_majoration_dimanche_fige, taux_majoration_ferie_fige, ' +
      'type_contrat_applique, taux_commission_fige, ' +
      'montant_commission_ht, montant_commission_tva, montant_commission_ttc, soignant_assigne_id';
    let missions: any[] = [];
    if ((f as any).mission_id) {
      const { data: m } = await supabase
        .from('missions')
        .select(missionSelect)
        .eq('id', (f as any).mission_id);
      missions = m || [];
    } else {
      const { data: m } = await supabase
        .from('missions')
        .select(missionSelect)
        .eq('facture_id', (f as any).id);
      missions = m || [];
    }

    // Enrichir avec soignant (nom + profession + spécialités) + pointages +
    // créneaux prévisionnels (fallback quand pas de pointages réels).
    const soignantIds = [...new Set(missions.map((m) => m.soignant_assigne_id).filter(Boolean))];
    const missionIds = missions.map((m) => m.id);
    const [{ data: soignants }, { data: allPresences }, { data: allCreneaux }] = await Promise.all([
      soignantIds.length > 0
        ? supabase.from('soignants').select('id, prenom, nom, profession, specialites').in('id', soignantIds)
        : Promise.resolve({ data: [] as any[] }),
      missionIds.length > 0
        ? supabase
            .from('presences')
            .select('mission_id, pointage_arrivee_le, pointage_depart_le, pause_debut_le, pause_fin_le, duree_pause_min, heures_reelles')
            .in('mission_id', missionIds)
            .order('pointage_arrivee_le', { ascending: true })
        : Promise.resolve({ data: [] as any[] }),
      missionIds.length > 0
        ? supabase
            .from('mission_creneaux')
            .select('mission_id, debut_le, fin_le, type_creneau, duree_heures')
            .in('mission_id', missionIds)
            .eq('type_creneau', 'PREVISIONNEL')
            .order('debut_le', { ascending: true })
        : Promise.resolve({ data: [] as any[] }),
    ]);
    const soignantMap = new Map(
      (soignants || []).map((s: any) => [
        s.id,
        {
          nom: `${s.prenom || ''} ${s.nom || ''}`.trim(),
          profession: s.profession || null,
          specialites: (s.specialites || []) as string[],
        },
      ]),
    );
    const presencesByMission = new Map<string, any[]>();
    for (const p of (allPresences as any[] | null) || []) {
      const list = presencesByMission.get(p.mission_id) || [];
      list.push(p);
      presencesByMission.set(p.mission_id, list);
    }
    const creneauxByMission = new Map<string, any[]>();
    for (const c of (allCreneaux as any[] | null) || []) {
      const list = creneauxByMission.get(c.mission_id) || [];
      list.push(c);
      creneauxByMission.set(c.mission_id, list);
    }
    const debutFacture = (f as any).periode_debut ? new Date(`${String((f as any).periode_debut).slice(0, 10)}T00:00:00`) : null;
    const finFacture = (f as any).periode_fin ? new Date(`${String((f as any).periode_fin).slice(0, 10)}T23:59:59.999`) : null;
    const dansPeriodeFacturee = (date?: string | null) => {
      if (!date || !debutFacture || !finFacture) return true;
      const valeur = new Date(date).getTime();
      return valeur >= debutFacture.getTime() && valeur <= finFacture.getTime();
    };
    const factureMonoMission = missions.length === 1 && Boolean((f as any).mission_id);

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
        // ── PASSE 2 : Header mission enrichi ──
        if (y > 230) { doc.addPage(); y = 20; }
        const soignantInfo = soignantMap.get(m.soignant_assigne_id);
        const soignantNom = soignantInfo?.nom || 'Soignant';
        const soignantProf = soignantInfo?.profession || m.profession_requise || '';
        const soignantSpec = (soignantInfo?.specialites || []).join(', ');

        // Bandeau rose-light
        doc.setFillColor(...JOLENE_COLORS.roseLight);
        doc.rect(PAGE.margin, y, PAGE.contentWidth, 16, 'F');
        doc.setDrawColor(...JOLENE_COLORS.primary);
        doc.setLineWidth(0.4);
        doc.line(PAGE.margin, y, PAGE.margin, y + 16);

        doc.setTextColor(...JOLENE_COLORS.primaryDark);
        doc.setFont('helvetica', 'bold');
        doc.setFontSize(9);
        doc.text(sanitizeForPdf(m.intitule || '(mission)'), PAGE.margin + 3, y + 5);

        doc.setFont('helvetica', 'normal');
        doc.setTextColor(...JOLENE_COLORS.text);
        doc.setFontSize(7.5);
        const profLine = soignantSpec ? `${soignantNom} - ${soignantProf} - ${soignantSpec}` : `${soignantNom} - ${soignantProf}`;
        doc.text(sanitizeForPdf(profLine), PAGE.margin + 3, y + 10);

        const serviceLine = m.service ? `Service : ${m.service}` : '';
        const debutAffiche = factureMonoMission && (f as any).periode_debut ? (f as any).periode_debut : m.debut_le;
        const finAffiche = factureMonoMission && (f as any).periode_fin ? (f as any).periode_fin : m.fin_le;
        const debutStr = debutAffiche ? format(new Date(debutAffiche), "dd/MM/yyyy HH'h'mm", { locale: fr }) : '-';
        const finStr = finAffiche ? format(new Date(finAffiche), "dd/MM/yyyy HH'h'mm", { locale: fr }) : '-';
        const dureeStr = factureMonoMission && (f as any).periode_debut && (f as any).periode_fin
          ? ''
          : (m.duree_heures ? `${Number(m.duree_heures).toFixed(1)} h` : '');
        const periodeLine = `${debutStr} -> ${finStr} (${dureeStr})`;
        doc.setFontSize(7);
        doc.setTextColor(...JOLENE_COLORS.textMuted);
        doc.text(sanitizeForPdf(serviceLine ? `${serviceLine}  |  ${periodeLine}` : periodeLine), PAGE.margin + 3, y + 14.5);
        y += 19;

        // ── PASSE 3 : Section pointages ──
        const pres = (presencesByMission.get(m.id) || []).filter((p) => !factureMonoMission || dansPeriodeFacturee(p.pointage_arrivee_le));
        const cren = (creneauxByMission.get(m.id) || []).filter((c) => !factureMonoMission || dansPeriodeFacturee(c.debut_le));
        if (pres.length > 0) {
          doc.setTextColor(...JOLENE_COLORS.text);
          doc.setFont('helvetica', 'bold');
          doc.setFontSize(8);
          doc.text('Pointages', PAGE.margin, y + 3);
          y += 4;
          autoTable(doc, {
            startY: y,
            head: [['Date', 'Arrivée', 'Départ', 'Pause', 'Heures eff.']],
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
            margin: { left: PAGE.margin + 4, right: PAGE.margin },
            tableWidth: PAGE.contentWidth - 4,
          });
          y = (doc as any).lastAutoTable?.finalY ? (doc as any).lastAutoTable.finalY + 3 : y + 15;
        } else if (cren.length > 0) {
          doc.setTextColor(...JOLENE_COLORS.textMuted);
          doc.setFont('helvetica', 'italic');
          doc.setFontSize(7);
          doc.text(sanitizeForPdf('Aucun pointage enregistre - creneaux previsionnels utilises :'), PAGE.margin, y + 3);
          y += 5;
          autoTable(doc, {
            startY: y,
            head: [['Date', 'Début', 'Fin', 'Durée prév.']],
            body: cren.map((c) => [
              c.debut_le ? format(new Date(c.debut_le), 'dd/MM', { locale: fr }) : '-',
              c.debut_le ? format(new Date(c.debut_le), "HH'h'mm", { locale: fr }) : '-',
              c.fin_le ? format(new Date(c.fin_le), "HH'h'mm", { locale: fr }) : '-',
              c.duree_heures ? `${Number(c.duree_heures).toFixed(1)} h` : '-',
            ]),
            styles: { fontSize: 7, cellPadding: 1.5, textColor: JOLENE_COLORS.textMuted as any },
            headStyles: { fillColor: JOLENE_COLORS.border as any, textColor: JOLENE_COLORS.text as any, fontStyle: 'bold' },
            margin: { left: PAGE.margin + 4, right: PAGE.margin },
            tableWidth: PAGE.contentWidth - 4,
          });
          y = (doc as any).lastAutoTable?.finalY ? (doc as any).lastAutoTable.finalY + 3 : y + 15;
        } else {
          doc.setTextColor(...JOLENE_COLORS.textMuted);
          doc.setFont('helvetica', 'italic');
          doc.setFontSize(7);
          doc.text(sanitizeForPdf('Aucun pointage enregistre (duree previsionnelle utilisee).'), PAGE.margin, y + 3);
          y += 7;
        }

        // ── PASSE 4 : Décomposition financière mission (majorations détaillées) ──
        const totalBrutMission = Number(m.total_brut || 0);
        const tauxHoraire = Number(m.taux_horaire_base_fige || m.taux_horaire_base || 0);
        const majorations =
          Number(m.montant_majoration_nuit || 0) +
          Number(m.montant_majoration_dimanche || 0) +
          Number(m.montant_majoration_ferie || 0);
        const tauxCommission = Number(m.taux_commission_fige || 15);
        const ifmMission = Number(m.montant_ifm || 0);
        const icpMission = Number(m.montant_icp || 0);
        const assietteMission = m.type_contrat_applique === 'SALARIE'
          ? totalBrutMission + ifmMission + icpMission
          : totalBrutMission;
        const commissionHtFacturee = factureMonoMission ? Number((f as any).montant_ht || 0) : Number(m.montant_commission_ht || 0);
        const commissionTvaFacturee = factureMonoMission ? Number((f as any).montant_tva || 0) : Number(m.montant_commission_tva || 0);
        const commissionTtcFacturee = factureMonoMission ? Number((f as any).montant_ttc || 0) : Number(m.montant_commission_ttc || 0);
        const assietteFacturee = tauxCommission > 0 ? commissionHtFacturee * 100 / tauxCommission : assietteMission;
        const facturePartielle = factureMonoMission && Math.abs(assietteFacturee - assietteMission) > 0.01;
        const totalBrut = facturePartielle ? assietteFacturee : totalBrutMission;
        const decompoRows: (string | number)[][] = facturePartielle ? [
          ['Assiette facturée pour la période', 'Base de calcul de cette facture uniquement', fmtEur(assietteFacturee)],
        ] : [
          ['Brut de base', `${m.duree_heures || 0} h x ${tauxHoraire.toFixed(2)} E/h`, fmtEur(totalBrut - majorations)],
        ];
        if (!facturePartielle && m.heures_nuit && Number(m.heures_nuit) > 0) {
          const tauxMajNuit = Number(m.taux_majoration_nuit_fige || 25);
          decompoRows.push([
            'Maj. nuit',
            `${Number(m.heures_nuit).toFixed(1)} h x ${tauxHoraire.toFixed(2)} E x ${tauxMajNuit}%`,
            `+${fmtEur(m.montant_majoration_nuit || 0)}`,
          ]);
        }
        if (!facturePartielle && m.heures_dimanche && Number(m.heures_dimanche) > 0) {
          const tauxMajDim = Number(m.taux_majoration_dimanche_fige || 25);
          decompoRows.push([
            'Maj. dimanche',
            `${Number(m.heures_dimanche).toFixed(1)} h x ${tauxHoraire.toFixed(2)} E x ${tauxMajDim}%`,
            `+${fmtEur(m.montant_majoration_dimanche || 0)}`,
          ]);
        }
        if (!facturePartielle && m.heures_ferie && Number(m.heures_ferie) > 0) {
          const tauxMajFerie = Number(m.taux_majoration_ferie_fige || 50);
          decompoRows.push([
            'Maj. férié',
            `${Number(m.heures_ferie).toFixed(1)} h x ${tauxHoraire.toFixed(2)} E x ${tauxMajFerie}%`,
            `+${fmtEur(m.montant_majoration_ferie || 0)}`,
          ]);
        }
        // ── PASSE 5 : décompo SALARIE complète + assiette commission explicite ──
        if (!facturePartielle) decompoRows.push(['Brut soignant', '', fmtEur(totalBrut)]);

        let assiette: number;
        let assietteLabel: string;
        if (m.type_contrat_applique === 'SALARIE' && !facturePartielle) {
          const ifm = ifmMission;
          const icp = icpMission;
          const superBrut = totalBrut + ifm + icp;
          const tauxIFM = Number(m.taux_ifm || 10);
          const tauxICP = Number(m.taux_icp || 10);
          decompoRows.push([`IFM (${tauxIFM}%)`, '', `+${fmtEur(ifm)}`]);
          decompoRows.push([`ICP (${tauxICP}%)`, '', `+${fmtEur(icp)}`]);
          decompoRows.push(['Super brut', '', fmtEur(superBrut)]);
          decompoRows.push(['Net salarié et cotisations', 'Déterminés par le bulletin de paie de l\'employeur', '—']);
          decompoRows.push(['', '', '']);
          assiette = superBrut;
          assietteLabel = `${tauxCommission}% x ${fmtEur(assiette)} super brut (base + IFM + ICP)`;
        } else {
          decompoRows.push(['', '', '']);
          assiette = facturePartielle ? assietteFacturee : totalBrut;
          assietteLabel = `${tauxCommission}% x ${fmtEur(assiette)} ${facturePartielle ? 'assiette facturée pour la période' : 'honoraires bruts'}`;
        }

        decompoRows.push([`Commission Jolene`, assietteLabel, fmtEur(commissionHtFacturee)]);
        decompoRows.push(['TVA 20%', '', fmtEur(commissionTvaFacturee)]);
        decompoRows.push(['Commission TTC facturée', '', fmtEur(commissionTtcFacturee)]);

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
              if (label.includes('Commission TTC')) {
                data.cell.styles.fillColor = JOLENE_COLORS.primary as any;
                data.cell.styles.textColor = [255, 255, 255] as any;
                data.cell.styles.fontStyle = 'bold';
              } else if (label.includes('NET a verser')) {
                data.cell.styles.fillColor = JOLENE_COLORS.teal as any;
                data.cell.styles.textColor = [255, 255, 255] as any;
                data.cell.styles.fontStyle = 'bold';
              } else if (label.includes('Commission Jolene') || label.includes('Super brut') || label.includes('Brut soignant')) {
                data.cell.styles.fillColor = JOLENE_COLORS.roseLight as any;
                data.cell.styles.fontStyle = 'bold';
              }
            }
          },
        });
        y = (doc as any).lastAutoTable?.finalY ? (doc as any).lastAutoTable.finalY + 5 : y + 30;
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

    await telechargerOuPartagerPdf(doc, `${(f as any).numero_facture}.pdf`);
    toast.success('Facture téléchargée');
  } catch (err: any) {
    console.error('Erreur génération PDF facture commission:', err);
    toast.error(err?.message || 'Erreur génération PDF');
  }
}
