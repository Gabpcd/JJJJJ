import assert from 'node:assert/strict';
import { readFileSync } from 'node:fs';
import test from 'node:test';
import { parse, type DefaultTreeAdapterMap } from 'parse5';
import { rendreCddEmployeur, validerDonneesCdd, type DonneesCdd } from '../../../../supabase/functions/_shared/cdd-employeur';
import { rendreContratLiberal } from '../../../../supabase/functions/_shared/contrat-liberal';
import { CONTRACT_WRAPPER_CSS, parseNativeContract, type NativeContractDocument } from './readerModel';

// Read the actual versioned templates, not a parallel legal model. These pure
// rendering functions do not import a network client or generate a backend file.
const generator = readFileSync(new URL('../../../../supabase/functions/generate-contrat-mission-pdf/index.ts', import.meta.url), 'utf8');
const css = generator.match(/<style>([\s\S]*?)<\/style>/)?.[1];
assert.ok(css, 'The actual HTML wrapper stylesheet must be found');
const liberalMaster = readFileSync(new URL('../../../../tests/admin/security/fixtures/contrat-liberal-master-v3.html', import.meta.url), 'utf8');
const wrap = (body: string, style = css) => `<!doctype html><html lang="fr"><head><meta charset="utf-8" /><title>Contrat fictif TEST</title><style>${style}</style></head><body>${body}</body></html>`;
const visible = (document: Extract<NativeContractDocument, { supported: true }>) => document.blocks.map(block => block.runs.map(run => run.text).join('')).join('\n');
const required = (html: string) => { const result = parseNativeContract(html); if (!result.supported) throw new Error(result.reason); assert.equal(result.supported, true); return result; };
const compact = (text: string) => text.replace(/[\t\n\f\r ]+/g, ' ').trim();

// Independent completeness oracle for templates composed of text-bearing blocks:
// every original body text node must survive, in order. Separate tests cover
// whitespace/line breaks/emphasis and block boundaries, rather than only words.
function bodyText(html: string) {
  const document = parse(html);
  const root = document.childNodes.find(node => 'tagName' in node && node.tagName === 'html') as DefaultTreeAdapterMap['element'];
  const body = root.childNodes.find(node => 'tagName' in node && node.tagName === 'body') as DefaultTreeAdapterMap['element'];
  const text = (node: DefaultTreeAdapterMap['childNode']): string => {
    if (node.nodeName === '#text') return (node as DefaultTreeAdapterMap['textNode']).value;
    if (!('tagName' in node)) return '';
    if (node.tagName === 'br') return '\n';
    const content = node.childNodes.map(text).join('');
    return ['h1', 'h2', 'p', 'section', 'article'].includes(node.tagName) ? `\n${content}\n` : content;
  };
  return body.childNodes.map(text).join('');
}
const common = {
  numero_contrat: 'TEST-FICTIF', etablissement_nom: 'Établissement fictif &amp; associé', etablissement_siret: '00000000000000',
  etablissement_adresse: 'Adresse fictive', soignant_prenom: 'Camille', soignant_nom: 'Exemple', soignant_adresse: 'Adresse fictive',
  soignant_date_naissance: '01/01/1990', soignant_rpps: '00000000000', profession: 'Médecin',
  debut_le: '27/10/2026 à 08:00', fin_le: '27/10/2026 à 16:00', duree_heures: '8', taux_horaire: '50.00',
  intitule_mission: 'Mission fictive de lecture', date_signature: '27/10/2026',
};
const employerText = "CLAUSE FICTIVE : A & B < C\n  Indentation  conservée\n\nDernière ligne : l’employeur dit 'oui'.";
const supplied: DonneesCdd = { cadre: 'TEXTE_EMPLOYEUR', confirme: true, representant_nom: 'Représentant fictif',
  representant_qualite: 'Direction', cadre_declare: 'Cadre fictif de test', texte_employeur: employerText };

test('reader stylesheet is the actual generator wrapper, not a permissive CSS parser', () => {
  assert.equal(compact(CONTRACT_WRAPPER_CSS), compact(css));
  assert.equal(parseNativeContract(wrap('<p>Clause visible</p>', `${css} p { display:none; }`)).supported, false);
});

test('actual employer CDD template preserves every clause and all pre-wrap characters', () => {
  const validation = validerDonneesCdd(supplied); assert.ok(validation.donnees);
  const html = wrap(rendreCddEmployeur(common, validation.donnees, 'acteur-fictif', '2026-10-27T10:00:00.000Z'));
  const model = required(html);
  assert.equal(model.blocks.find(block => block.kind === 'pre')?.runs.map(run => run.text).join(''), employerText);
  assert.equal(compact(visible(model)), compact(bodyText(html)));
  assert.equal(model.blocks[0].kind, 'h1');
});

test('actual private CDD renders every section including optional replacement and benefits', () => {
  const data: DonneesCdd = { cadre: 'PRIVE_TERME_PRECIS', confirme: true, representant_nom: 'Direction fictive', representant_qualite: 'Direction',
    motif_type: 'REMPLACEMENT', motif_precis: 'Absence fictive', poste: 'Poste fictif', qualification: 'Qualification fictive',
    lieu_travail: 'Lieu fictif', risques: 'OUI', risques_precisions: 'Précision fictive', convention_collective: 'Convention déclarée fictive',
    renouvellement: 'Aucun renouvellement fictif', essai: 'CONVENU', essai_duree: 'Durée déclarée fictive', essai_conditions: 'Conditions fictives',
    remuneration_accessoires: 'Accessoires déclarés fictifs', temps_partiel: 'OUI', temps_partiel_conditions: 'Conditions déclarées fictives',
    retraite_nom: 'Organisme fictif', retraite_adresse: 'Adresse fictive', prevoyance: 'OUI', prevoyance_nom: 'Prévoyance fictive',
    prevoyance_adresse: 'Adresse fictive', remplace_nom: 'Personne fictive', remplace_qualification: 'Qualification fictive' };
  const validation = validerDonneesCdd(data); assert.ok(validation.donnees);
  const html = wrap(rendreCddEmployeur(common, validation.donnees, 'acteur-fictif', '2026-10-27T10:00:00.000Z'));
  const model = required(html);
  assert.equal(compact(visible(model)), compact(bodyText(html)));
  assert.deepEqual(model.blocks.filter(block => block.kind === 'h2').map(block => block.runs.map(run => run.text).join('')),
    ['Parties', 'Motif et poste', 'Terme et temps de travail', 'Convention collective', 'Période d’essai', 'Rémunération', 'Retraite et prévoyance']);
});

for (const mode of ['TAUX_HORAIRE', 'RETROCESSION']) test(`actual liberal master preserves all six articles in ${mode}`, () => {
  const rendered = rendreContratLiberal(liberalMaster, common, { debut_le: '2026-10-27T07:00:00Z', fin_le: '2026-10-27T15:00:00Z',
    duree_heures: 8, mode_remuneration: mode, taux_horaire_base: 50, retrocession_pct: 70 }, { adresse_ville: 'Ville fictive' });
  assert.ok(rendered.html); const html = wrap(rendered.html); const model = required(html);
  assert.equal(compact(visible(model)), compact(bodyText(html)));
  assert.equal(model.blocks.filter(block => block.kind === 'h2').length, 7);
  assert.ok(model.blocks.some(block => block.runs.some(run => run.italic)));
  assert.match(visible(model), /Article 6 — Communication à l'Ordre/);
  assert.match(visible(model), /Fait à Ville fictive/);
});

test('inline spaces, entities, strong/em overlap and explicit line breaks retain meaning', () => {
  const document = required(wrap('<p>Montant <strong>1&nbsp;234,50</strong> € <em>brut <strong>annuel</strong></em>.<br/>A &amp; B &#58; l&#39;accord.</p>'));
  assert.equal(visible(document), "Montant 1\u00a0234,50 € brut annuel.\nA & B : l'accord.");
  assert.deepEqual(document.blocks[0].runs.find(run => run.text === 'annuel'), { text: 'annuel', bold: true, italic: true });
});

test('adjacent inline nodes collapse ordinary spaces without merging words or NBSP', () => {
  assert.equal(visible(required(wrap('<p>Texte  <strong> important </strong> ici&nbsp;!</p>'))), 'Texte important ici\u00a0!');
});

const unsupportedMarkup = [
  '<pre>Poste       Montant\nA           123</pre>',
  '<table><thead><tr><th>Poste</th><th>Montant</th></tr></thead><tbody><tr><td>A</td><td>123</td></tr></tbody></table>',
  '<ol start="3" reversed><li value="7">Clause</li></ol>', '<ul><li>Clause</li></ul>',
  '<p><a href="https://example.com/annexe">Annexe obligatoire</a></p>',
  '<p style="display:none">Clause cachée</p>', '<p hidden>Clause cachée</p>', '<p dir="rtl">Clause orientée</p>',
  '<article style="white-space:pre-wrap;overflow-wrap:anywhere;color:transparent">Clause cachée</article>',
  '<script>void 0</script>', '<img src="https://example.com/signature.png" alt="Signature"/>', '<!-- clause non affichée -->',
];
for (const body of unsupportedMarkup) test(`unsupported semantics reject the entire original: ${body.slice(0, 45)}`, () => {
  const result = parseNativeContract(wrap(`<p>Avant</p>${body}<p>Après</p>`));
  assert.equal(result.supported, false);
  assert.equal('blocks' in result, false, 'No partial original may be displayed as complete');
});

test('invalid/oversized documents and non-template head semantics fail closed', () => {
  assert.equal(parseNativeContract('<p>Missing document structure</p>').supported, false);
  assert.equal(parseNativeContract(wrap('<p>Texte</p>').replace('<head>', '<head><base href="https://example.com/"/>')).supported, false);
  assert.equal(parseNativeContract(wrap(`<p>${'x'.repeat(1_000_001)}</p>`)).supported, false);
  assert.equal(parseNativeContract(wrap('<p>Texte\u0000tronqué</p>')).supported, false);
});
