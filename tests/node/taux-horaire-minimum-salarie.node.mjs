// Garde de parité du taux horaire minimal d'une mission salariée (migration 20261125120000).
//
// Trois copies de la même valeur ne peuvent plus diverger en silence : la valeur posée par la migration dans
// parametres_systeme (et sa borne basse), le repli du site (src/lib/tauxHoraireMinimumSalarie.ts) et la constante de
// l'app iOS (LibellesWeb.Publication.tauxMinimumHorsLiberal). Le texte du refus est le même au serveur, sur le site et
// dans l'app. Aucun plancher en dur ne subsiste dans le formulaire web, et l'ancienne valeur 11,65 n'apparaît plus.
// Lecture de fichiers du dépôt seulement : aucun réseau, aucun secret.
import test from 'node:test';
import assert from 'node:assert/strict';
import { readFileSync, readdirSync, statSync } from 'node:fs';
import { dirname, join, resolve } from 'node:path';
import { fileURLToPath } from 'node:url';

const RACINE = resolve(dirname(fileURLToPath(import.meta.url)), '..', '..');
const lire = chemin => readFileSync(join(RACINE, chemin), 'utf8');

export const FICHIERS = {
  migrations: 'supabase/migrations',
  web: 'src/lib/tauxHoraireMinimumSalarie.ts',
  formulaire: 'src/components/FormulaireMission.tsx',
  ios: 'ios-native/Packages/JoleneCore/Sources/JoleneCore/Libelles/LibellesWeb.swift',
  iosMessage: 'ios-native/Packages/JoleneCore/Sources/JoleneCore/Etablissement/Publication/PublicationPresentation.swift',
  iosTest: 'ios-native/Packages/JoleneCore/Tests/JoleneCoreTests/PublicationPayloadTests.swift',
};

const CLE = 'taux_horaire_minimum_salarie';

function unique(texte, motif, quoi) {
  const trouves = [...texte.matchAll(motif)];
  assert.equal(trouves.length, 1, `${quoi} : ${trouves.length} occurrence(s) au lieu d'une`);
  return trouves[0];
}

/**
 * Dernière valeur posée par une migration (ordre des horodatages) : INSERT … VALUES('taux_horaire_minimum_salarie',X
 * ou UPDATE … SET valeur = X … WHERE cle = 'taux_horaire_minimum_salarie'. Une revalorisation du SMIC arrive par une
 * NOUVELLE migration : la garde suit la dernière, jamais la première.
 */
export function derniereValeurMigration() {
  const fichiers = readdirSync(join(RACINE, FICHIERS.migrations)).filter(f => f.endsWith('.sql')).sort();
  return derniereValeurDans(fichiers.map(fichier => ({ fichier, sql: lire(`${FICHIERS.migrations}/${fichier}`) })));
}

/** Même lecture sur une liste `{ fichier, sql }` déjà triée (testable sans toucher au dépôt). */
export function derniereValeurDans(migrations) {
  let trouve = null;
  for (const { fichier, sql: brut } of migrations) {
    const sql = brut.replace(/^\s*--.*$/gm, '');
    if (!sql.includes(CLE)) continue;
    const valeurs = [
      ...[...sql.matchAll(/VALUES\s*\(\s*'taux_horaire_minimum_salarie'\s*,\s*(\d+\.\d{2})\s*,/g)].map(m => [m.index, m[1]]),
      ...[...sql.matchAll(/SET\s+valeur\s*=\s*(\d+\.\d{2})[^;]*cle\s*=\s*'taux_horaire_minimum_salarie'/g)].map(m => [m.index, m[1]]),
    ].sort((a, b) => a[0] - b[0]);
    if (valeurs.length) trouve = { fichier, valeur: valeurs.at(-1)[1] };
  }
  assert.ok(trouve, `aucune migration ne pose ${CLE}`);
  return trouve;
}

/** Dernière migration qui définit le verrou : c'est elle qui porte le texte du refus serveur. */
function derniereDefinitionVerrou() {
  const fichiers = readdirSync(join(RACINE, FICHIERS.migrations)).filter(f => f.endsWith('.sql')).sort();
  const dernier = fichiers.filter(f => /FUNCTION\s+private\.fn_trg_verifier_taux_minimum_salarie\s*\(/.test(lire(`${FICHIERS.migrations}/${f}`))).at(-1);
  assert.ok(dernier, 'aucune migration ne définit private.fn_trg_verifier_taux_minimum_salarie');
  return lire(`${FICHIERS.migrations}/${dernier}`);
}

export function valeurs() {
  const migration = derniereValeurMigration();
  const web = unique(lire(FICHIERS.web), /^export const TAUX_HORAIRE_MINIMUM_SALARIE_REPLI = Number\('(\d+\.\d{2})'\);$/gm,
    'repli du site');
  const ios = unique(lire(FICHIERS.ios), /public static let tauxMinimumHorsLiberal = "(\d+\.\d{2})"/g, 'constante iOS');
  return { migration, web: web[1], ios: ios[1] };
}

test('même plancher dans la dernière migration, le repli du site et l\'app iOS', () => {
  const v = valeurs();
  const attendu = v.migration.valeur;
  const message = `dernière valeur posée par ${v.migration.fichier} : ${attendu} ; repli du site (${FICHIERS.web}) : ${v.web} ; `
    + `app (${FICHIERS.ios}, tauxMinimumHorsLiberal) : ${v.ios}. À une revalorisation, mettre à jour le repli du site, `
    + `la constante iOS et le texte attendu de ${FICHIERS.iosTest} dans la même PR que la migration.`;
  assert.equal(v.web, attendu, message);
  assert.equal(v.ios, attendu, message);
});

test('la garde suit la dernière migration qui pose la valeur (revalorisation par une nouvelle migration)', () => {
  const posee = "INSERT INTO public.parametres_systeme(cle,valeur) VALUES('taux_horaire_minimum_salarie',12.31,'x') ON CONFLICT(cle) DO NOTHING;";
  const relevee = "UPDATE public.parametres_systeme SET valeur = 12.50, val_min = 12.50 WHERE cle = 'taux_horaire_minimum_salarie';";
  assert.deepEqual(derniereValeurDans([{ fichier: 'a.sql', sql: posee }, { fichier: 'b.sql', sql: 'SELECT 1;' }]),
    { fichier: 'a.sql', valeur: '12.31' });
  assert.deepEqual(derniereValeurDans([{ fichier: 'a.sql', sql: posee }, { fichier: 'c.sql', sql: relevee }]),
    { fichier: 'c.sql', valeur: '12.50' });
  assert.deepEqual(derniereValeurDans([{ fichier: 'a.sql', sql: posee }, { fichier: 'd.sql', sql: `-- ${relevee}` }]),
    { fichier: 'a.sql', valeur: '12.31' }, 'une ligne commentée ne compte pas');
});

test('même texte de refus au serveur, sur le site et dans l\'app', () => {
  const montant = derniereValeurMigration().valeur.replace('.', ',');
  unique(derniereDefinitionVerrou(), /RAISE EXCEPTION 'Le taux horaire doit être d''au moins % €\/h\.'/g, 'message du serveur');
  unique(lire(FICHIERS.web), /return `Le taux horaire doit être d'au moins \$\{montantFrancais\(minimum\)\} €\/h\.`;/g,
    'message du site');
  unique(lire(FICHIERS.iosMessage),
    /"Le taux horaire doit être d'au moins \\\(montantFrancais\(minimum\)\) €\/h\."/g, 'message iOS');
  unique(lire(FICHIERS.iosTest), new RegExp(`"Le taux horaire doit être d'au moins ${montant} €/h\\."`, 'g'),
    `message attendu par le test Swift (${montant} €/h)`);
});

test('le formulaire web lit le plancher (paramètre serveur ou repli), sans valeur en dur', () => {
  const formulaire = lire(FICHIERS.formulaire);
  unique(formulaire, /min=\{minimumSalarieApplicable\(contratPreference\) \? String\(tauxMinimumSalarie\) : '0\.01'\}/g,
    'attribut min du champ taux');
  unique(formulaire, /const tauxMinimumSalarie = useTauxHoraireMinimumSalarie\(\);/g, 'lecture du paramètre');
  unique(formulaire, /\{messageTauxSousMinimum\(tauxMinimumSalarie\)\}/g, 'message sous le champ');
  assert.doesNotMatch(formulaire, /min=\{[^}]*'1\d[.,]\d\d'/, 'aucun plancher numérique en dur dans le formulaire');
});

function* parcourir(dossier) {
  for (const nom of readdirSync(join(RACINE, dossier))) {
    if (['node_modules', '.build', 'DerivedData'].includes(nom)) continue;
    const chemin = `${dossier}/${nom}`;
    if (statSync(join(RACINE, chemin)).isDirectory()) yield* parcourir(chemin);
    else if (/\.(tsx?|swift)$/.test(nom)) yield chemin;
  }
}

test('l\'ancien plancher 11,65 €/h a disparu du site et de l\'app', () => {
  const restes = [];
  for (const dossier of ['src', 'ios-native']) {
    for (const chemin of parcourir(dossier)) {
      if (/(?<![\d.,])11[.,]65(?![\d])/.test(lire(chemin))) restes.push(chemin);
    }
  }
  assert.deepEqual(restes, []);
});
