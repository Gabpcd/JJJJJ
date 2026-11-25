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
  migration: 'supabase/migrations/20261125120000_taux_horaire_minimum_salarie.sql',
  web: 'src/lib/tauxHoraireMinimumSalarie.ts',
  formulaire: 'src/components/FormulaireMission.tsx',
  ios: 'ios-native/Packages/JoleneCore/Sources/JoleneCore/Libelles/LibellesWeb.swift',
  iosMessage: 'ios-native/Packages/JoleneCore/Sources/JoleneCore/Etablissement/Publication/PublicationPresentation.swift',
  iosTest: 'ios-native/Packages/JoleneCore/Tests/JoleneCoreTests/PublicationPayloadTests.swift',
};

function unique(texte, motif, quoi) {
  const trouves = [...texte.matchAll(motif)];
  assert.equal(trouves.length, 1, `${quoi} : ${trouves.length} occurrence(s) au lieu d'une`);
  return trouves[0];
}

export function valeurs() {
  const migration = lire(FICHIERS.migration);
  const insertion = unique(migration,
    /VALUES\('taux_horaire_minimum_salarie',(\d+\.\d{2}),[\s\S]*?'€\/h brut',(\d+\.\d{2}),(\d+),'FINANCE'/g,
    'paramètre taux_horaire_minimum_salarie de la migration');
  const web = unique(lire(FICHIERS.web), /^export const TAUX_HORAIRE_MINIMUM_SALARIE_REPLI = Number\('(\d+\.\d{2})'\);$/gm,
    'repli du site');
  const ios = unique(lire(FICHIERS.ios), /public static let tauxMinimumHorsLiberal = "(\d+\.\d{2})"/g, 'constante iOS');
  return { migration: insertion[1], borneBasse: insertion[2], web: web[1], ios: ios[1] };
}

test('même plancher dans la migration, le repli du site et l\'app iOS', () => {
  const v = valeurs();
  assert.deepEqual(v, { migration: '12.31', borneBasse: '12.31', web: '12.31', ios: '12.31' },
    'SMIC horaire brut au 1er juin 2026 (arrêté du 22 mai 2026) : changer les trois valeurs ensemble');
});

test('même texte de refus au serveur, sur le site et dans l\'app', () => {
  unique(lire(FICHIERS.migration), /RAISE EXCEPTION 'Le taux horaire doit être d''au moins % €\/h\.'/g, 'message du serveur');
  unique(lire(FICHIERS.web), /return `Le taux horaire doit être d'au moins \$\{montantFrancais\(minimum\)\} €\/h\.`;/g,
    'message du site');
  unique(lire(FICHIERS.iosMessage),
    /"Le taux horaire doit être d'au moins \\\(montantFrancais\(PublicationRules\.tauxMinimum\)\) €\/h\."/g, 'message iOS');
  unique(lire(FICHIERS.iosTest), /"Le taux horaire doit être d'au moins 12,31 €\/h\."/g, 'message attendu par le test Swift');
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
