/**
 * Fixtures démo du domaine « bulletins » du lot 4 (docs/mobile-swift/LOT4_PLAN.md §2.7), remplies par T10.
 *
 * Module du domaine : chaque tranche du lot 4 n'écrit que le module de son domaine, jamais
 * export-demo-fixtures.mjs ni les modules des autres (§4). Même contrat que buildFixtures() : nom de fichier
 * (`demo-<nom>.json`) → valeur JSON, ou `{ brut }` pour un texte tel quel. Horloge fixée : contexte.now.
 *
 * `demo-copie.pdf` : PDF d'une page marqué « DÉMONSTRATION », écrit ici octet par octet (ASCII seulement : le texte
 * brut de l'exporteur, écrit en UTF-8, est alors identique aux octets hachés ; « É » est l'échappement octal `\311` de
 * WinAnsiEncoding). Aucune donnée réelle, aucun nom, aucun montant.
 *
 * `demo-copies-bulletins.json` : quatre copies du compte démo au format exact de `fn_lister_copies_bulletins`
 * (supabase/schema/public.sql, tri `periode_fin` puis `publie_le` décroissants), lues par `DemoBulletinsGateway` à
 * travers le décodage strict de l'app (`CopieBulletinValidation`, port de `validerListeCopiesBulletins`,
 * src/lib/copiesBulletins.ts) : identifiants au format uuid, comme le serveur. Deux employeurs fictifs (le filtre
 * « Employeur » du web n'apparaît qu'à partir de deux) :
 *   - version 2 publiée, qui remplace la version 1 (motif `CONTENU`) : la bonne copie, SHA-256 et taille du PDF ;
 *   - version 1 remplacée, toujours consultable (`copieBulletinTelechargeable`) ;
 *   - une copie publiée dont le SHA-256 annoncé est faux (taille exacte) : refus d'intégrité à l'ouverture ;
 *   - une copie retirée, déjà signalée : aucun bouton d'ouverture.
 * `pdf` : fichier, SHA-256 et taille calculés ici, relus par les tests Swift.
 *
 * @param {{ now: Date }} contexte
 * @returns {Record<string, unknown>}
 */
import { createHash } from 'node:crypto';

export const FICHIER_PDF = 'demo-copie.pdf';
export const FICHIER_COPIES = 'demo-copies-bulletins.json';

/** Identifiants fictifs au format uuid v4 (le décodage strict de l'app refuse tout autre format). */
const id = (prefixe, rang) => `${prefixe}-0000-4000-8000-${String(rang).padStart(12, '0')}`;
export const COPIES = {
  valide: id('c0b1e000', 1),
  remplacee: id('c0b1e000', 2),
  falsifiee: id('c0b1e000', 3),
  retiree: id('c0b1e000', 4),
};
const EMPLOYEURS = {
  lilas: { id: id('e7ab0000', 2), nom: 'Établissement fictif des Lilas' },
  parc: { id: id('e7ab0000', 3), nom: 'Cabinet fictif du Parc' },
};
const SOIGNANT = { id: id('50190000', 1), nom: 'Démonstration', prenom: 'Soignant' };
const mission = (rang) => id('a1551000', rang);

/** PDF 1.4 minimal et valide (une page A4, police standard Helvetica), en ASCII pur. */
export function pdfDemonstration() {
  const lignes = [
    ['28', '72 760', 'D\\311MONSTRATION'],
    ['14', '72 720', 'Copie fictive de document de paie'],
    ['11', '72 696', 'Aucune donn\\351e r\\351elle. Document sans valeur, g\\351n\\351r\\351 pour le mode d\\351monstration.'],
  ];
  const contenu = lignes.map(([taille, position, texte]) => `BT /F1 ${taille} Tf ${position} Td (${texte}) Tj ET`).join('\n');
  const objets = [
    '<< /Type /Catalog /Pages 2 0 R >>',
    '<< /Type /Pages /Kids [3 0 R] /Count 1 >>',
    '<< /Type /Page /Parent 2 0 R /MediaBox [0 0 595 842] /Resources << /Font << /F1 4 0 R >> >> /Contents 5 0 R >>',
    '<< /Type /Font /Subtype /Type1 /BaseFont /Helvetica /Encoding /WinAnsiEncoding >>',
    `<< /Length ${contenu.length} >>\nstream\n${contenu}\nendstream`,
  ];
  let pdf = '%PDF-1.4\n';
  const offsets = [];
  objets.forEach((objet, index) => {
    offsets.push(pdf.length);
    pdf += `${index + 1} 0 obj\n${objet}\nendobj\n`;
  });
  const xref = pdf.length;
  pdf += `xref\n0 ${objets.length + 1}\n0000000000 65535 f \n`;
  pdf += offsets.map((offset) => `${String(offset).padStart(10, '0')} 00000 n \n`).join('');
  pdf += `trailer\n<< /Size ${objets.length + 1} /Root 1 0 R >>\nstartxref\n${xref}\n%%EOF\n`;
  if (!/^[\x00-\x7f]*$/.test(pdf)) throw new Error('fixtures démo (bulletins) : le PDF de démonstration doit rester en ASCII');
  return pdf;
}

const sha256 = (texte) => createHash('sha256').update(texte, 'utf8').digest('hex');

export function fixtures(contexte) {
  const heure = 3_600_000;
  const iso = (decalageHeures) => new Date(contexte.now.getTime() + decalageHeures * heure).toISOString();
  const pdf = pdfDemonstration();
  const empreinte = sha256(pdf);
  const taille = Buffer.byteLength(pdf, 'utf8');
  // Empreinte d'un autre contenu : 64 caractères hexadécimaux valides, différents de ceux du PDF servi.
  const empreinteFausse = sha256('copie falsifiée (fixture démo)');
  if (empreinteFausse === empreinte) throw new Error('fixtures démo (bulletins) : la copie falsifiée doit avoir une autre empreinte');
  const copie = (champs) => ({
    id: champs.id,
    etablissement_id: champs.employeur.id,
    etablissement_nom: champs.employeur.nom,
    soignant_id: SOIGNANT.id,
    soignant_nom: SOIGNANT.nom,
    soignant_prenom: SOIGNANT.prenom,
    periode_debut: champs.debut,
    periode_fin: champs.fin,
    statut: champs.statut,
    version: champs.version,
    publie_le: champs.publieLe,
    remplace_id: champs.remplaceId ?? null,
    motif_remplacement: champs.motifRemplacement ?? null,
    mission_ids: champs.missions,
    taille_octets: taille,
    sha256: champs.sha256 ?? empreinte,
    signalee: champs.signalee ?? false,
  });
  return {
    [FICHIER_PDF]: { brut: pdf },
    [FICHIER_COPIES]: {
      fixed_now: contexte.now.toISOString(),
      pdf: { fichier: FICHIER_PDF, sha256: empreinte, taille_octets: taille },
      copies: [
        copie({
          id: COPIES.valide, employeur: EMPLOYEURS.lilas, debut: '2026-10-01', fin: '2026-10-31', statut: 'PUBLIEE',
          version: 2, publieLe: iso(-38.5), remplaceId: COPIES.remplacee, motifRemplacement: 'CONTENU',
          missions: [mission(1), mission(2)],
        }),
        copie({
          id: COPIES.remplacee, employeur: EMPLOYEURS.lilas, debut: '2026-10-01', fin: '2026-10-31', statut: 'REMPLACEE',
          version: 1, publieLe: iso(-62), missions: [mission(1), mission(2)],
        }),
        copie({
          id: COPIES.falsifiee, employeur: EMPLOYEURS.parc, debut: '2026-09-01', fin: '2026-09-30', statut: 'PUBLIEE',
          version: 1, publieLe: iso(-24 * 27), missions: [mission(3)], sha256: empreinteFausse,
        }),
        copie({
          id: COPIES.retiree, employeur: EMPLOYEURS.parc, debut: '2026-08-01', fin: '2026-08-31', statut: 'RETIREE',
          version: 1, publieLe: iso(-24 * 58), missions: [mission(4)], signalee: true,
        }),
      ],
    },
  };
}
