// Simulation de paie SALARIE — document non officiel tant que les données de
// prélèvement à la source ne sont pas disponibles.
//
// Le calcul brut→net est fait en base via fn_calculer_cotisations() qui
// peuple la table cotisations_sociales. Ce helper ne fait QUE le rendu :
// il consomme les valeurs DB (donc pas de risque d'écart entre la valeur
// affichée et la valeur enregistrée).
//
// Les pourcentages affichés à côté des montants viennent de
// `cotisations-2026.ts` qui doit rester aligné avec les taux DB.

import jsPDF from 'jspdf';
import { JOLENE_COLORS, PAGE, sanitizeForPdf, createHeader, createFooter, fmtEur } from './pdf-design-system';
import { supabase } from '@/integrations/supabase/client';
import { telechargerOuPartagerPdf } from './telechargement';
import {
  TAUX_CSG_BASE, TAUX_CSG_DEDUCTIBLE, TAUX_CSG_NON_DEDUCTIBLE, TAUX_CRDS,
  TAUX_SS_VIEILLESSE_PLAFONNEE, TAUX_SS_VIEILLESSE_DEPLAFONNEE,
  TAUX_RETRAITE_T1, TAUX_RETRAITE_T2, TAUX_CEG,
  TAUX_PATRONAL_SECURITE_SOCIALE, TAUX_PATRONAL_ALLOCATIONS_FAMILIALES,
  TAUX_PATRONAL_ACCIDENT_TRAVAIL, TAUX_PATRONAL_RETRAITE,
  TAUX_PATRONAL_CHOMAGE, TAUX_PATRONAL_FNAL, TAUX_PATRONAL_FORMATION,
  TAUX_PATRONAL_TRANSPORT, TAUX_IFM, TAUX_ICP, formatTaux, PMSS_2026,
} from './cotisations-2026';
import { MENTION_SIMULATION_PAIE } from './bulletinPaieUi';

interface BulletinSnapshot {
  id: string;
  numero_bulletin: string;
  soignant_id: string;
  mission_id: string;
  etablissement_id: string;
  periode_debut: string;
  periode_fin: string;
  salaire_brut: number;
  total_cotisations_salariales: number;
  total_cotisations_patronales: number;
  net_avant_impot: number;
  ifm: number;
  icp: number;
  statut: string;
  date_emission: string;
}

interface CotisationsSnapshot {
  csg_deductible: number;
  csg_non_deductible: number;
  crds: number;
  securite_sociale_maladie: number;
  securite_sociale_vieillesse_plafonnee: number;
  securite_sociale_vieillesse_deplafonnee: number;
  retraite_complementaire_t1: number;
  retraite_complementaire_t2: number;
  contribution_equilibre_general: number;
  patronal_securite_sociale: number;
  patronal_allocations_familiales: number;
  patronal_accident_travail: number;
  patronal_retraite_complementaire: number;
  patronal_chomage: number;
  patronal_fnal: number;
  patronal_formation: number;
  patronal_transport: number;
}

interface SoignantSnapshot {
  prenom: string | null;
  nom: string | null;
  email: string | null;
  date_naissance: string | null;
  profession: string | null;
  adresse_rue: string | null;
  adresse_code_postal: string | null;
  adresse_ville: string | null;
  numero_securite_sociale: string | null;
}

interface EtablissementSnapshot {
  nom: string | null;
  siret: string | null;
  adresse_rue: string | null;
  adresse_code_postal: string | null;
  adresse_ville: string | null;
  convention_collective?: string | null;
}

interface MissionSnapshot {
  intitule: string | null;
  service: string | null;
  duree_heures: number | null;
  taux_horaire_base: number | null;
  debut_le: string;
  fin_le: string;
}

// ─────────────────────────────────────────────────────────────────────────

export async function telechargerBulletinPaiePdf(bulletinId: string): Promise<void> {
  const { data: bulletin, error: bErr } = await supabase
    .from('bulletins_paie' as any)
    .select('*')
    .eq('id', bulletinId)
    .single();
  if (bErr || !bulletin) throw new Error(bErr?.message || 'Bulletin introuvable');
  const b = bulletin as unknown as BulletinSnapshot;

  const [cotisationsResult, soignantResult, etablissementResult, missionResult, cumulResult] = await Promise.all([
    supabase.from('cotisations_sociales').select('*').eq('mission_id', b.mission_id).maybeSingle(),
    supabase.from('soignants')
      .select('prenom, nom, email, date_naissance, profession, adresse_rue, adresse_code_postal, adresse_ville, numero_securite_sociale')
      .eq('id', b.soignant_id).single(),
    supabase.from('etablissements' as any)
      .select('nom, siret, adresse_rue, adresse_code_postal, adresse_ville, convention_collective')
      .eq('id', b.etablissement_id).single(),
    supabase.from('missions')
      .select('intitule, service, duree_heures, taux_horaire_base, debut_le, fin_le')
      .eq('id', b.mission_id).single(),
    supabase.rpc('fn_cumul_annuel_paie' as any, {
      p_soignant_id: b.soignant_id,
      p_jusqu_au: b.periode_fin,
    }),
  ]);

  if (cotisationsResult.error) throw new Error(cotisationsResult.error.message || 'Cotisations indisponibles');
  if (soignantResult.error) throw new Error(soignantResult.error.message || 'Soignant indisponible');
  if (etablissementResult.error) throw new Error(etablissementResult.error.message || 'Établissement indisponible');
  if (missionResult.error) throw new Error(missionResult.error.message || 'Mission indisponible');
  if (cumulResult.error) throw new Error(cumulResult.error.message || 'Cumul annuel indisponible');

  const cotisations = cotisationsResult.data;
  const soignant = soignantResult.data;
  const etablissement = etablissementResult.data;
  const mission = missionResult.data;
  const cumul = cumulResult.data;

  if (!cotisations) throw new Error('Détail des cotisations indisponible : la simulation PDF ne peut pas être générée de façon fiable.');
  if (!soignant) throw new Error('Soignant introuvable');
  if (!etablissement) throw new Error('Établissement introuvable');
  if (!mission) throw new Error('Mission introuvable');

  const doc = genererBulletinPaiePdf(
    b,
    cotisations as unknown as CotisationsSnapshot,
    soignant as unknown as SoignantSnapshot,
    etablissement as unknown as EtablissementSnapshot,
    mission as unknown as MissionSnapshot,
    (cumul as any) || null,
  );
  await telechargerOuPartagerPdf(doc, `simulation-paie-${b.numero_bulletin}.pdf`);
}

interface CumulAnnuel {
  annee: number;
  jusqu_au: string;
  nombre_bulletins: number;
  cumul_brut: number;
  cumul_cotisations_salariales: number;
  cumul_cotisations_patronales: number;
  cumul_net_avant_impot: number;
  cumul_ifm: number;
  cumul_icp: number;
}

// ─────────────────────────────────────────────────────────────────────────

export function genererBulletinPaiePdf(
  b: BulletinSnapshot,
  cot: CotisationsSnapshot,
  soignant: SoignantSnapshot,
  etab: EtablissementSnapshot,
  mission: MissionSnapshot,
  cumul?: CumulAnnuel | null,
): jsPDF {
  const doc = new jsPDF({ unit: 'mm', format: 'a4' });
  const margin = PAGE.margin;
  const contentWidth = PAGE.contentWidth;

  createHeader(doc, {
    title: 'Simulation de paie — document non officiel',
    subtitle: `${b.numero_bulletin}  -  Période : ${formatPeriode(b.periode_debut, b.periode_fin)}`,
  });

  let y = 34;
  doc.setFillColor(...JOLENE_COLORS.roseLight);
  doc.roundedRect(margin, y, contentWidth, 10, 1.5, 1.5, 'F');
  doc.setFont('helvetica', 'bold');
  doc.setFontSize(7.5);
  doc.setTextColor(...JOLENE_COLORS.primaryDark);
  doc.text(doc.splitTextToSize(sanitizeForPdf(MENTION_SIMULATION_PAIE), contentWidth - 6), margin + 3, y + 4);
  y += 14;

  // ─── Bandeau employeur / salarié ──────────────────────────────────────
  doc.setFillColor(...JOLENE_COLORS.background);
  doc.roundedRect(margin, y, contentWidth, 36, 2, 2, 'F');

  // Colonne employeur (gauche)
  const colW = (contentWidth - 4) / 2;
  doc.setFont('helvetica', 'bold');
  doc.setFontSize(8);
  doc.setTextColor(...JOLENE_COLORS.textMuted);
  doc.text('EMPLOYEUR', margin + 3, y + 5);

  doc.setFont('helvetica', 'bold');
  doc.setFontSize(10);
  doc.setTextColor(...JOLENE_COLORS.text);
  doc.text(sanitizeForPdf(etab.nom || '-'), margin + 3, y + 10);

  doc.setFont('helvetica', 'normal');
  doc.setFontSize(8);
  doc.text(sanitizeForPdf(etab.adresse_rue || ''), margin + 3, y + 15);
  doc.text(sanitizeForPdf(`${etab.adresse_code_postal || ''} ${etab.adresse_ville || ''}`.trim() || '-'), margin + 3, y + 19);
  doc.text(sanitizeForPdf(`SIRET : ${etab.siret || '-'}`), margin + 3, y + 23);
  doc.text(sanitizeForPdf(`Convention collective : ${etab.convention_collective || 'CCN établissements de santé applicable'}`), margin + 3, y + 27);
  doc.setFont('helvetica', 'italic');
  doc.setTextColor(...JOLENE_COLORS.textMuted);
  doc.text(sanitizeForPdf('Simulation préparée par Jolene SAS'), margin + 3, y + 32);

  // Colonne salarié (droite)
  const colX2 = margin + colW + 4;
  doc.setFont('helvetica', 'bold');
  doc.setFontSize(8);
  doc.setTextColor(...JOLENE_COLORS.textMuted);
  doc.text('SALARIÉ', colX2, y + 5);

  doc.setFont('helvetica', 'bold');
  doc.setFontSize(10);
  doc.setTextColor(...JOLENE_COLORS.text);
  doc.text(sanitizeForPdf(`${soignant.prenom || ''} ${soignant.nom || ''}`.trim() || '-'), colX2, y + 10);

  doc.setFont('helvetica', 'normal');
  doc.setFontSize(8);
  doc.text(sanitizeForPdf(soignant.adresse_rue || ''), colX2, y + 15);
  doc.text(sanitizeForPdf(`${soignant.adresse_code_postal || ''} ${soignant.adresse_ville || ''}`.trim() || '-'), colX2, y + 19);
  doc.text(sanitizeForPdf(`Emploi : ${soignant.profession || '-'}`), colX2, y + 23);
  doc.text(sanitizeForPdf(`N° Sécurité sociale : ${soignant.numero_securite_sociale || 'à renseigner sur votre profil'}`), colX2, y + 27);
  doc.text(sanitizeForPdf(`Contrat : Contrat à Durée Déterminée (CDD)`), colX2, y + 31);

  y += 40;

  // ─── Détail prestation ──────────────────────────────────────────────
  doc.setFont('helvetica', 'bold');
  doc.setFontSize(10);
  doc.setTextColor(...JOLENE_COLORS.primaryDark);
  doc.text('PRESTATION', margin, y);
  y += 5;

  doc.setFont('helvetica', 'normal');
  doc.setFontSize(8.5);
  doc.setTextColor(...JOLENE_COLORS.text);
  const tauxH = mission.taux_horaire_base ?? 0;
  const heures = mission.duree_heures ?? 0;
  doc.text(sanitizeForPdf(`${mission.intitule || 'Mission'} - ${mission.service || ''}`), margin, y);
  doc.text(sanitizeForPdf(`Du ${formatDateTime(mission.debut_le)} au ${formatDateTime(mission.fin_le)}`), margin, y + 4);
  doc.text(sanitizeForPdf(`${heures.toFixed(2)} h x ${fmtEur(tauxH)}/h`), margin, y + 8);
  y += 12;

  // ─── Tableau cotisations ────────────────────────────────────────────
  y = renderTableauCotisations(doc, y, b, cot);

  // ─── Bloc totaux net ────────────────────────────────────────────────
  if (y > PAGE.height - 60) { doc.addPage(); y = margin; }
  y += 4;
  doc.setDrawColor(...JOLENE_COLORS.primary);
  doc.setLineWidth(0.5);
  doc.line(margin, y, margin + contentWidth, y);
  y += 5;

  drawTotalRow(doc, y, 'Salaire brut total (avec IFM + ICP)', b.salaire_brut, 'normal');
  y += 5;
  drawTotalRow(doc, y, 'Total cotisations salariales', -b.total_cotisations_salariales, 'normal');
  y += 5;
  doc.setDrawColor(...JOLENE_COLORS.border);
  doc.line(margin + 100, y - 1, margin + contentWidth, y - 1);

  drawTotalRow(doc, y, 'Net imposable (avant CSG non déd. + CRDS)', netImposable(b, cot), 'normal');
  y += 5;
  drawTotalRow(doc, y, 'Net avant impôt sur le revenu', b.net_avant_impot, 'bold');
  y += 6;
  doc.setFillColor(...JOLENE_COLORS.roseLight);
  doc.roundedRect(margin, y, contentWidth, 8, 1.5, 1.5, 'F');
  doc.setFont('helvetica', 'bold');
  doc.setFontSize(11);
  doc.setTextColor(...JOLENE_COLORS.primaryDark);
  doc.text('NET AVANT IMPÔT — PAS NON INTÉGRÉ', margin + 3, y + 5.5);
  doc.text(sanitizeForPdf(fmtEur(b.net_avant_impot)), margin + contentWidth - 3, y + 5.5, { align: 'right' });
  y += 14;

  // ─── Cumul annuel indicatif ──────────────────────────────────────────
  if (cumul && Number(cumul.nombre_bulletins) > 0) {
    if (y > PAGE.height - 60) { doc.addPage(); y = margin; }
    doc.setFont('helvetica', 'bold');
    doc.setFontSize(8.5);
    doc.setTextColor(...JOLENE_COLORS.primaryDark);
    doc.text(sanitizeForPdf(`CUMUL ANNUEL ${cumul.annee} (au ${formatDate(cumul.jusqu_au)})`), margin, y);
    y += 4;

    doc.setFont('helvetica', 'normal');
    doc.setFontSize(8);
    doc.setTextColor(...JOLENE_COLORS.text);
    const colWidth = contentWidth / 2;
    const rows: Array<[string, string]> = [
      [`Simulations générées (${cumul.annee})`, String(cumul.nombre_bulletins)],
      ['Cumul brut', fmtEur(Number(cumul.cumul_brut))],
      ['Cumul cotisations salariales', fmtEur(-Number(cumul.cumul_cotisations_salariales))],
      ['Cumul cotisations patronales', fmtEur(Number(cumul.cumul_cotisations_patronales))],
      ['Cumul IFM', fmtEur(Number(cumul.cumul_ifm))],
      ['Cumul ICP', fmtEur(Number(cumul.cumul_icp))],
      ['Cumul NET avant impôt', fmtEur(Number(cumul.cumul_net_avant_impot))],
    ];
    const startY = y;
    rows.forEach((r, i) => {
      const col = i % 2;
      const row = Math.floor(i / 2);
      const xLabel = margin + col * colWidth;
      doc.setFont('helvetica', 'normal');
      doc.text(sanitizeForPdf(r[0]), xLabel, startY + row * 4);
      doc.setFont('helvetica', 'bold');
      doc.text(sanitizeForPdf(r[1]), xLabel + colWidth - 2, startY + row * 4, { align: 'right' });
    });
    y = startY + Math.ceil(rows.length / 2) * 4 + 4;
  }

  // ─── Mentions légales ──────────────────────────────────────────────
  if (y > PAGE.height - 50) { doc.addPage(); y = margin; }
  doc.setFont('helvetica', 'bold');
  doc.setFontSize(8.5);
  doc.setTextColor(...JOLENE_COLORS.primaryDark);
  doc.text('INFORMATIONS DE SIMULATION — NON EXHAUSTIVES', margin, y);
  y += 4;

  doc.setFont('helvetica', 'normal');
  doc.setFontSize(7);
  doc.setTextColor(...JOLENE_COLORS.text);
  const mentions = [
    `Simulation generee le ${formatDate(b.date_emission)} pour la periode du ${formatDate(b.periode_debut)} au ${formatDate(b.periode_fin)}.`,
    `Ce document ne remplace pas le bulletin de paie officiel remis par l'employeur.`,
    `Le taux, la base et le montant du prelevement a la source ne sont pas integres. Le net affiche est donc un net avant impot.`,
    `Plafond mensuel SS 2026 (PMSS) : ${fmtEur(PMSS_2026)}.`,
    `Indemnites CDD : IFM ${formatTaux(TAUX_IFM)} (precarite, art. L1243-8) + ICP ${formatTaux(TAUX_ICP)} (conges payes, art. L3141-22).`,
    `Cotisations salariales = part deduite du brut. Cotisations patronales = a la charge de l'employeur, mentionnees a titre informatif.`,
    `Les taux et montants restent indicatifs jusqu'a validation par l'employeur et son gestionnaire de paie.`,
  ];
  for (const m of mentions) {
    const wrapped = doc.splitTextToSize(sanitizeForPdf(m), contentWidth);
    doc.text(wrapped, margin, y);
    y += (Array.isArray(wrapped) ? wrapped.length : 1) * 3.2 + 1;
  }

  // Footer toutes pages
  const total = doc.getNumberOfPages();
  for (let i = 1; i <= total; i++) {
    doc.setPage(i);
    createFooter(doc, {
      companyLine: `Simulation de paie — document non officiel — page ${i}/${total}`,
      contactLine: 'jolene.app | support@jolene.app',
    });
  }

  return doc;
}

// ─────────────────────────────────────────────────────────────────────────
// Helpers internes

function renderTableauCotisations(
  doc: jsPDF,
  startY: number,
  b: BulletinSnapshot,
  cot: CotisationsSnapshot,
): number {
  const margin = PAGE.margin;
  const w = PAGE.contentWidth;
  let y = startY;

  // Header
  doc.setFillColor(...JOLENE_COLORS.primary);
  doc.rect(margin, y, w, 6, 'F');
  doc.setFont('helvetica', 'bold');
  doc.setFontSize(8);
  doc.setTextColor(255, 255, 255);
  doc.text('Cotisation', margin + 2, y + 4);
  doc.text('Base', margin + 65, y + 4, { align: 'right' });
  doc.text('Taux sal.', margin + 90, y + 4, { align: 'right' });
  doc.text('Mt salarial', margin + 120, y + 4, { align: 'right' });
  doc.text('Taux pat.', margin + 145, y + 4, { align: 'right' });
  doc.text('Mt patronal', margin + w - 2, y + 4, { align: 'right' });
  y += 6;

  doc.setTextColor(...JOLENE_COLORS.text);
  doc.setFont('helvetica', 'normal');
  doc.setFontSize(7.5);

  const csgBase = b.salaire_brut * TAUX_CSG_BASE;
  const rows: Array<[string, number | null, number | null, number | null, number | null, number | null]> = [
    // [libellé, base, tauxSal, mtSal, tauxPat, mtPat]
    ['CSG deductible', csgBase, TAUX_CSG_DEDUCTIBLE, cot.csg_deductible, null, null],
    ['CSG / CRDS non deductibles', csgBase, TAUX_CSG_NON_DEDUCTIBLE + TAUX_CRDS, cot.csg_non_deductible + cot.crds, null, null],
    ['SS - Maladie', b.salaire_brut, 0, cot.securite_sociale_maladie, 0.1305, cot.patronal_securite_sociale],
    ['SS - Vieillesse plafonnee', Math.min(b.salaire_brut, PMSS_2026), TAUX_SS_VIEILLESSE_PLAFONNEE, cot.securite_sociale_vieillesse_plafonnee, null, null],
    ['SS - Vieillesse deplafonnee', b.salaire_brut, TAUX_SS_VIEILLESSE_DEPLAFONNEE, cot.securite_sociale_vieillesse_deplafonnee, null, null],
    ['Retraite compl. T1', Math.min(b.salaire_brut, PMSS_2026), TAUX_RETRAITE_T1, cot.retraite_complementaire_t1, TAUX_PATRONAL_RETRAITE, cot.patronal_retraite_complementaire],
    ['Retraite compl. T2', Math.max(0, b.salaire_brut - PMSS_2026), TAUX_RETRAITE_T2, cot.retraite_complementaire_t2, null, null],
    ['CEG (Equilibre general)', Math.min(b.salaire_brut, PMSS_2026), TAUX_CEG, cot.contribution_equilibre_general, null, null],
    ['Allocations familiales', b.salaire_brut, null, null, TAUX_PATRONAL_ALLOCATIONS_FAMILIALES, cot.patronal_allocations_familiales],
    ['Accidents du travail', b.salaire_brut, null, null, TAUX_PATRONAL_ACCIDENT_TRAVAIL, cot.patronal_accident_travail],
    ['Assurance chomage', b.salaire_brut, null, null, TAUX_PATRONAL_CHOMAGE, cot.patronal_chomage],
    ['FNAL', b.salaire_brut, null, null, TAUX_PATRONAL_FNAL, cot.patronal_fnal],
    ['Formation professionnelle', b.salaire_brut, null, null, TAUX_PATRONAL_FORMATION, cot.patronal_formation],
    ['Transport', b.salaire_brut, null, null, TAUX_PATRONAL_TRANSPORT, cot.patronal_transport],
  ];

  let alt = false;
  for (const r of rows) {
    if (y > PAGE.height - 60) {
      doc.addPage();
      y = PAGE.margin;
    }
    if (alt) {
      doc.setFillColor(...JOLENE_COLORS.background);
      doc.rect(margin, y, w, 4, 'F');
    }
    alt = !alt;
    doc.setTextColor(...JOLENE_COLORS.text);
    doc.text(sanitizeForPdf(r[0]), margin + 2, y + 3);
    doc.text(r[1] != null ? sanitizeForPdf(fmtEur(r[1])) : '-', margin + 65, y + 3, { align: 'right' });
    doc.text(r[2] != null ? formatTaux(r[2]) : '-', margin + 90, y + 3, { align: 'right' });
    doc.text(r[3] != null ? sanitizeForPdf(fmtEur(r[3])) : '-', margin + 120, y + 3, { align: 'right' });
    doc.text(r[4] != null ? formatTaux(r[4]) : '-', margin + 145, y + 3, { align: 'right' });
    doc.text(r[5] != null ? sanitizeForPdf(fmtEur(r[5])) : '-', margin + w - 2, y + 3, { align: 'right' });
    y += 4;
  }

  return y + 2;
}

function drawTotalRow(doc: jsPDF, y: number, label: string, montant: number, weight: 'normal' | 'bold' = 'normal') {
  const margin = PAGE.margin;
  const w = PAGE.contentWidth;
  doc.setFont('helvetica', weight);
  doc.setFontSize(weight === 'bold' ? 10 : 9);
  doc.setTextColor(...JOLENE_COLORS.text);
  doc.text(sanitizeForPdf(label), margin, y);
  doc.text(sanitizeForPdf(fmtEur(montant)), margin + w, y, { align: 'right' });
}

function netImposable(b: BulletinSnapshot, cot: CotisationsSnapshot): number {
  // Net imposable ≈ brut - cot. salariales déductibles (toutes sauf CSG non déd. + CRDS)
  const cotDeductibles = b.total_cotisations_salariales - cot.csg_non_deductible - cot.crds;
  return Math.max(0, b.salaire_brut - cotDeductibles);
}

function formatPeriode(d1: string, d2: string): string {
  return `${formatDate(d1)} au ${formatDate(d2)}`;
}

function formatDate(d: string): string {
  try {
    return new Date(d).toLocaleDateString('fr-FR', { day: '2-digit', month: '2-digit', year: 'numeric' });
  } catch { return d; }
}

function formatDateTime(d: string): string {
  try {
    return new Date(d).toLocaleString('fr-FR', {
      day: '2-digit', month: '2-digit', year: 'numeric', hour: '2-digit', minute: '2-digit', timeZone: 'Europe/Paris',
    });
  } catch { return d; }
}
