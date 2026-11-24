// Adresses publiques de l'annuaire des établissements pour personnes âgées
// (20261124170000, HARD STOP n°4 pour la mention) — contrôle hors réseau.
// Ne remplace pas la suite SQL (tests/security/agents-croissance-brouillons.test.sql,
// section 12, exécutée sur le staging sous ROLLBACK) ; verrouille ce qu'elle ne
// peut pas voir :
//   * le tri des adresses : aucune adresse qui peut nommer une personne n'est retenue
//     (script reproductible scripts/acquisition/extraire-annuaire-personnes-agees.mjs) ;
//   * le bloc de données de la migration : empreinte, format, aucune messagerie de santé
//     fermée, aucune initiale isolée, un FINESS par ligne ;
//   * les empreintes du préflight sont celles des corps de 20261124123500, et chaque
//     fonction redéfinie reprend son corps d'origine (lignes retirées et ajoutées listées) ;
//   * la mention de l'annuaire reprend mot pour mot la phrase d'opposition existante ;
//     une origine inconnue n'a pas de mention ;
//   * aucun envoi, aucune écriture dans growth_config, aucun SECURITY DEFINER, câblage CI.
import assert from 'node:assert/strict';
import { createHash } from 'node:crypto';
import { readFileSync } from 'node:fs';
import { test } from 'node:test';
import { FONCTIONS, PRENOMS, SOURCE, blocSql, classerAdresse, domaineDouteux, extraire } from '../../scripts/acquisition/extraire-annuaire-personnes-agees.mjs';

const read = path => readFileSync(new URL(`../../${path}`, import.meta.url), 'utf8');
const md5 = body => createHash('md5').update(body, 'utf8').digest('hex');

const MIGRATION = '20261124170000_prospection_adresses_annuaire_personnes_agees.sql';
const ETAPE_1 = '20261124123500_prospection_zero_visible_liste_appels.sql';
const BASE = '20261109140000_agents_croissance_brouillons.sql';
const APICRYPT = '20261117060000_prospection_sans_apicrypt.sql';
const migration = read(`supabase/migrations/${MIGRATION}`);
const etape1 = read(`supabase/migrations/${ETAPE_1}`);
const base = read(`supabase/migrations/${BASE}`);
const apicrypt = read(`supabase/migrations/${APICRYPT}`);
const suite = read('tests/security/agents-croissance-brouillons.test.sql');
const workflow = read('.github/workflows/validate-pr.yml');

function definition(sql, nom) {
  const marqueur = `CREATE OR REPLACE FUNCTION ${nom}(`;
  const debut = sql.indexOf(marqueur);
  assert.ok(debut >= 0, `${nom} : définition absente`);
  assert.equal(sql.indexOf(marqueur, debut + 1), -1, `${nom} : définie deux fois`);
  const reste = sql.slice(debut);
  const ouverture = /\bAS\s+(\$[a-zA-Z_0-9]*\$)/.exec(reste);
  assert.ok(ouverture, `${nom} : corps dollar-quoted absent`);
  const corpsDebut = ouverture.index + ouverture[0].length;
  const corpsFin = reste.indexOf(ouverture[1], corpsDebut);
  assert.ok(corpsFin > corpsDebut, `${nom} : fin du corps absente`);
  return { entete: reste.slice(0, ouverture.index), corps: reste.slice(corpsDebut, corpsFin) };
}

// Différence par multiensemble de lignes : ce que le nouveau corps n'a plus, ce qu'il a en plus.
function difference(avant, apres) {
  const compter = texte => texte.split('\n').reduce((m, l) => m.set(l, (m.get(l) ?? 0) + 1), new Map());
  const restantApres = compter(apres);
  const retirees = [];
  for (const ligne of avant.split('\n')) {
    if ((restantApres.get(ligne) ?? 0) > 0) restantApres.set(ligne, restantApres.get(ligne) - 1);
    else retirees.push(ligne);
  }
  const restantAvant = compter(avant);
  const ajoutees = [];
  for (const ligne of apres.split('\n')) {
    if ((restantAvant.get(ligne) ?? 0) > 0) restantAvant.set(ligne, restantAvant.get(ligne) - 1);
    else ajoutees.push(ligne);
  }
  return { retirees, ajoutees };
}

function blocDeDonnees() {
  const ouverture = '$adresses_publiques_donnees$\n';
  const debut = migration.indexOf(ouverture);
  const fin = migration.indexOf('\n$adresses_publiques_donnees$;', debut + 1);
  assert.ok(debut >= 0 && fin > debut, 'bloc de données introuvable');
  return migration.slice(debut + ouverture.length, fin);
}

// ---------------------------------------------------------------------------
// Tri des adresses (exemples fictifs)
// ---------------------------------------------------------------------------
const etab = { nom: 'EHPAD Résidence Les Mimosas', ville: 'VILLENEUVE SUR LOT', gestionnaire: 'Association Les Mimosas' };

test('une adresse de fonction ou au nom de la structure est retenue', () => {
  for (const [adresse, contexte, classe] of [
    ['contact@mimosas.example', etab, 'FONCTION'],
    ['direction@ch-exemple.example', etab, 'FONCTION'],
    ['Accueil.Mimosas@orange.example', etab, 'FONCTION'],
    ['secretariat-direction@exemple.example', etab, 'FONCTION'],
    ['ehpad.villeneuve@exemple.example', etab, 'FONCTION'],
    ['residencelesmimosas@exemple.example', etab, 'FONCTION'],
    ['mdrvilleneuve@exemple.example', etab, 'FONCTION'],
    ['rh@exemple.example', etab, 'FONCTION'],
    ['mapad2@exemple.example', etab, 'FONCTION'],
    ['lesmimosas@exemple.example', etab, 'STRUCTURE'],
    ['mimosas47@exemple.example', etab, 'STRUCTURE'],
    ['villeneuve@groupe.example', etab, 'STRUCTURE'],
    ['larbois@exemple.example', { nom: "EHPAD Résidence L'Arbois", ville: 'VELAUX' }, 'STRUCTURE'],
    ['saintjoseph@exemple.example', { nom: 'EHPAD Saint-Joseph', ville: 'PAU' }, 'STRUCTURE'],
    ['st.joseph@exemple.example', { nom: 'EHPAD Saint-Joseph', ville: 'PAU' }, 'STRUCTURE'],
    ['accueil.joseph@exemple.example', { nom: 'EHPAD Saint-Joseph', ville: 'PAU' }, 'FONCTION'],
    // Un prénom du nom de l'établissement passe avec un mot de fonction.
    ['ehpad.huguette-henry@exemple.example', { nom: 'EHPAD Huguette Henry', ville: 'WOIPPY' }, 'FONCTION'],
    // Un sigle de deux lettres passe seul, ou à côté du nom de la commune.
    ['mr.villeneuve@exemple.example', etab, 'FONCTION'],
    ['mrvilleneuve@exemple.example', etab, 'FONCTION'],
    ['ch@exemple.example', etab, 'FONCTION'],
    // Deux liaisons qui se lisent (« de la »), entre des mots reconnus.
    ['residencedelaforet@exemple.example', { nom: 'Résidence de la Forêt', ville: 'PAU' }, 'FONCTION'],
    // Une adresse au seul nom de l'établissement est retenue, même si ce nom est un patronyme (limite écrite).
    ['dupont@exemple.example', { nom: 'Résidence Dupont', ville: 'PAU' }, 'STRUCTURE'],
  ]) {
    assert.equal(classerAdresse(adresse, contexte), classe, adresse);
  }
});

test('une adresse qui peut nommer une personne est écartée', () => {
  for (const [adresse, contexte] of [
    ['marie.dupont@exemple.example', etab],
    ['m.dupont@exemple.example', etab],
    ['mdupont@exemple.example', etab],
    ['dupont@exemple.example', etab],
    // Un mot de fonction ne sauve pas un nom : « V. Leleu, direction ».
    ['v.leleu.direction@exemple.example', etab],
    ['dupont.direction@exemple.example', etab],
    ['marie.dupont.ehpadmimosas@exemple.example', etab],
    // Une initiale isolée suffit, même devant un mot de fonction ou de la structure.
    ['j.bureau@exemple.example', etab],
    ['s.direction@exemple.example', etab],
    ['m.mimosas@exemple.example', etab],
    // Initiale collée à un mot de la structure : « P. Mimosas », « D. Martin ».
    ['pmimosas@exemple.example', etab],
    ['dmartin@exemple.example', { nom: 'Résidence Martin Luther King', ville: 'LYON' }],
    // Prénom de saint seul : « martin@ » peut être une personne.
    ['martin@exemple.example', { nom: 'EHPAD Saint-Martin', ville: 'TOURS' }],
    ['pmartin@exemple.example', { nom: 'EHPAD Saint-Martin', ville: 'TOURS' }],
    ['joseph@exemple.example', { nom: 'EHPAD Saint-Joseph', ville: 'PAU' }],
    // Mots de liaison seuls, sigle inconnu, identifiant sans rapport.
    ['les@exemple.example', etab],
    ['cgomas@exemple.example', etab],
    ['hpv70@exemple.example', etab],
    // Revue de #1180. Le gestionnaire peut être une personne physique : il n'explique rien.
    ['marie.dupont@exemple.example', { nom: 'EHPAD Les Tilleuls', ville: 'LORIENT', gestionnaire: 'Madame Marie Dupont' }],
    ['dupont.marie@exemple.example', { nom: 'PUV La Touche', ville: 'GENAC', gestionnaire: 'Dupont Marie' }],
    ['mimosas@exemple.example', { nom: 'EHPAD Les Tilleuls', ville: 'LORIENT', gestionnaire: 'Association Les Mimosas' }],
    // Un prénom du nom de l'établissement, sans mot de fonction.
    ['huguette-henry@exemple.example', { nom: 'EHPAD Huguette Henry', ville: 'WOIPPY' }],
    ['jean.moulin@exemple.example', { nom: 'Résidence Jean Moulin', ville: 'LORIENT' }],
    ['charlotte@exemple.example', { nom: 'EHPAD Le Domaine de la Charlotte', ville: 'LORIENT' }],
    // Prénom de saint venu de la commune, ou à côté d'un autre mot du nom.
    ['martin@exemple.example', { nom: 'EHPAD Les Oliviers', ville: 'SAINT-MARTIN-DE-CRAU' }],
    ['martin.lac@exemple.example', { nom: 'Résidence Saint-Martin du Lac', ville: 'LORIENT' }],
    // Sigle de deux lettres à côté d'un mot du nom : « Mr Dupont », « Ch. Dupont ».
    ['mr.dupont@exemple.example', { nom: 'Résidence Dupont', ville: 'LORIENT' }],
    ['ch.dupont@exemple.example', { nom: 'Résidence Dupont', ville: 'LORIENT' }],
    ['mr.martin@exemple.example', { nom: 'EHPAD Les Oliviers', ville: 'SAINT-MARTIN-DE-CRAU' }],
    // Un nom fait de liaisons collées, avec ou sans mot de fonction.
    ['direction.lesaux@exemple.example', etab],
    ['dela@exemple.example', { nom: 'EHPAD de la Forêt', ville: 'LORIENT' }],
    // Un intitulé qui présente une personne n'explique rien.
    ['dupont@exemple.example', { nom: 'Accueil de jour Madame Dupont', ville: 'LORIENT' }],
  ]) {
    assert.equal(classerAdresse(adresse, contexte), 'A_VERIFIER', adresse);
  }
});

test('adresse absente, mal formée ou en messagerie de santé fermée', () => {
  assert.equal(classerAdresse('', etab), 'ABSENTE');
  assert.equal(classerAdresse(null, etab), 'ABSENTE');
  assert.equal(classerAdresse('contact@mimosas', etab), 'MAL_FORMEE');
  assert.equal(classerAdresse('contact mimosas@exemple.example', etab), 'MAL_FORMEE');
  assert.equal(classerAdresse('château@exemple.example', etab), 'MAL_FORMEE');
  assert.equal(classerAdresse("contact'@exemple.example", etab), 'MAL_FORMEE');
  assert.equal(classerAdresse('contact;x@exemple.example', etab), 'MAL_FORMEE');
  assert.equal(classerAdresse('contact@ehpad.mssante.fr', etab), 'MESSAGERIE_FERMEE');
  assert.equal(classerAdresse('contact@interop-mssante.apicrypt.org', etab), 'MESSAGERIE_FERMEE');
  // Même règle que la base (20261117060000).
  assert.match(definition(apicrypt, 'private.fn_growth_email_mssante').corps, /\[@\.\]\(mssante\\\.fr\|apicrypt\\\.org\)\$/);
});

test('domaine à une faute de frappe d’un domaine courant', () => {
  for (const d of ['orane.fr', 'ornge.fr', 'wandoo.fr', 'xanadoo.fr', 'gmail.com.fr', 'hotmai.fr']) assert.equal(domaineDouteux(d), true, d);
  for (const d of ['orange.fr', 'wanadoo.fr', 'gmail.com', 'ymail.com', 'ehpad-mimosas.example', 'ch-exemple.example']) assert.equal(domaineDouteux(d), false, d);
  // Un domaine très présent dans le fichier sert aussi de repère.
  assert.equal(domaineDouteux('goupe-exemple.example', ['groupe-exemple.example']), true);
  assert.equal(domaineDouteux('groupe-exemple.example', ['groupe-exemple.example']), false);
});

test('aucun mot de fonction n’est un prénom ni un nom courant, et tous sont écrits sans accent', () => {
  for (const mot of FONCTIONS) assert.match(mot, /^[a-z]+$/, mot);
  for (const mot of FONCTIONS) assert.ok(!PRENOMS.has(mot), `« ${mot} » est aussi un prénom`);
  for (const prenom of PRENOMS) assert.match(prenom, /^[a-z]{3,}$/, prenom);
  for (const interdit of ['bureau', 'maison', 'cadre', 'martin', 'marie', 'centre', 'village']) {
    assert.ok(!FONCTIONS.includes(interdit), `« ${interdit} » est aussi un nom de famille ou un prénom`);
  }
});

test('extraction : une adresse par FINESS, décompte de ce qui est écarté, bloc au format de la migration', () => {
  const entetes = 'title,updatedAt,noFinesset,coordinates.deptcode,coordinates.city,coordinates.emailContact,coordinates.gestionnaire';
  const csv = [entetes,
    '"EHPAD Les Mimosas",2020-10-04T18:33:19.000Z,010000001,01,BOURG,contact@mimosas.example,Association',
    '"EHPAD Les Mimosas, annexe",2020-10-05T08:00:00.000Z,010000001,01,BOURG,accueil@mimosas.example,Association',
    '"EHPAD Les Lilas",2020-09-01T08:00:00.000Z,920000002,92,CLAMART,Les.Lilas@exemple.example,SARL',
    '"EHPAD Les Roses",2020-09-01T08:00:00.000Z,750000003,75,PARIS,marie.dupont@exemple.example,SARL',
    '"EHPAD Les Iris",2020-09-01T08:00:00.000Z,560000004,56,VANNES,,SARL',
    '"EHPAD Sans Finess",2020-09-01T08:00:00.000Z,12,56,VANNES,contact@exemple.example,SARL',
  ].join('\n');
  const { comptes, adresses } = extraire(csv);
  assert.deepEqual(adresses, [
    { finess: '010000001', email: 'contact@mimosas.example', classe: 'FONCTION', maj: '2020-10-04', departement: '01' },
    { finess: '920000002', email: 'les.lilas@exemple.example', classe: 'STRUCTURE', maj: '2020-09-01', departement: '92' },
  ]);
  assert.deepEqual({ lignes: comptes.lignes, invalides: comptes.finess_invalide, absentes: comptes.ABSENTE, aVerifier: comptes.A_VERIFIER, doublons: comptes.doublon_finess, retenues: comptes.retenues },
    { lignes: 6, invalides: 1, absentes: 1, aVerifier: 1, doublons: 1, retenues: 2 });
  assert.equal(blocSql(adresses), '010000001;contact@mimosas.example;F;2020-10-04\n920000002;les.lilas@exemple.example;S;2020-09-01');
});

// ---------------------------------------------------------------------------
// Bloc de données de la migration
// ---------------------------------------------------------------------------
test('bloc de données : empreinte, format, aucune messagerie fermée, aucune initiale isolée', () => {
  const bloc = blocDeDonnees();
  const lignes = bloc.split('\n');
  const attendu = /-- (\d+) lignes, md5 ([0-9a-f]{32}) \(contrôlé/.exec(migration);
  assert.ok(attendu, 'nombre de lignes et empreinte annoncés en tête du bloc');
  assert.equal(lignes.length, Number(attendu[1]));
  assert.equal(md5(bloc), attendu[2]);
  assert.ok(migration.includes(`IF pg_catalog.md5(v_bloc) <> '${attendu[2]}' THEN`), 'empreinte contrôlée par la migration');
  assert.equal(migration.split(`<> ${attendu[1]}`).length - 1, 2, 'nombre de lignes contrôlé par la migration (format et FINESS distincts)');

  const finess = new Set();
  const classes = { F: 0, S: 0 };
  let precedent = '';
  for (const ligne of lignes) {
    const m = /^([0-9]{9});([a-z0-9._%+-]+)@([a-z0-9-]+(?:\.[a-z0-9-]+)*\.[a-z]{2,});([FS]);(20[0-9]{2}-[0-9]{2}-[0-9]{2})$/.exec(ligne);
    assert.ok(m, `ligne mal formée : ${ligne.slice(0, 12)}…`);
    const [, f, identifiant, domaine, classe] = m;
    assert.ok(f > precedent, `FINESS en double ou hors ordre : ${f}`);
    precedent = f;
    finess.add(f);
    classes[classe] += 1;
    assert.doesNotMatch(domaine, /(^|\.)(mssante\.fr|apicrypt\.org)$/, `messagerie fermée : ${f}`);
    assert.ok(!identifiant.split(/[^a-z0-9]+/).some(x => x.replace(/[0-9]/g, '').length === 1), `initiale isolée : ${f}`);
    assert.equal(domaineDouteux(domaine), false, `domaine à une faute de frappe d'un domaine courant : ${f}`);
    // Aucun identifiant fait seulement de prénoms courants (« jean.moulin », « charlotte »).
    const morceaux = identifiant.split(/[^a-z]+/).filter(Boolean);
    assert.ok(!morceaux.every(x => PRENOMS.has(x)), `identifiant fait de prénoms : ${f}`);
  }
  assert.equal(finess.size, lignes.length);
  // Les nombres écrits dans l'en-tête sont ceux du bloc.
  assert.ok(migration.includes(`en retient ${lignes.length} :`), 'total annoncé');
  assert.ok(migration.includes(`${classes.F} portent un mot de fonction\n-- (classe F), ${classes.S} le seul nom de la structure (classe S)`), 'répartition annoncée');
  assert.ok(migration.includes("le champ « gestionnaire » n'est pas lu"), 'le gestionnaire n’explique aucune adresse');
  // Source : même jeu, même fichier, mêmes dates dans le script et dans la migration.
  assert.ok(migration.includes(`sha256 ${SOURCE.sha256}`));
  assert.ok(migration.includes(`'source_code', '${SOURCE.code}'`));
  assert.ok(migration.includes(`'source_url', '${SOURCE.url}'`));
  assert.ok(migration.includes(`'source_publie_le', '${SOURCE.publie_le}'`));
  assert.ok(migration.includes(`'releve_le', '${SOURCE.releve_le}'`));
});

test('import : jamais sur une adresse ouverte ni sur une opposition, ancienne adresse conservée', () => {
  const debut = migration.indexOf('DO $adresses_publiques_import$');
  const fin = migration.indexOf('$adresses_publiques_import$;', debut);
  const importation = migration.slice(migration.indexOf('\n$adresses_publiques_donnees$;', debut), fin);
  assert.match(importation, /AND e\.statut_sourcing <> 'OPPOSITION'\s+AND NOT e\.adresse_ouverte/);
  assert.match(importation, /'remplace', NULLIF\(btrim\(p\.email\), ''\)/);
  assert.equal(importation.split('UPDATE ').length - 1, 1, 'une seule écriture');
  assert.doesNotMatch(importation, /\b(INSERT|DELETE)\b/);
  // Invariants exécutés par la migration elle-même (au déploiement et sous ROLLBACK en CI).
  for (const code of ['ADRESSES_PUBLIQUES_IMPORT_INCOHERENT', 'ADRESSES_PUBLIQUES_IMPORT_ADRESSE_OUVERTE_MODIFIEE', 'ADRESSES_PUBLIQUES_IMPORT_OPPOSITION_TOUCHEE']) {
    assert.match(importation, new RegExp(`RAISE EXCEPTION '${code} :`), code);
  }
  assert.ok(importation.indexOf('INTO v_ouvertes_avant') < importation.indexOf('UPDATE public.prospects_etablissements'), 'photographie prise avant l’écriture');
  assert.match(importation, /AND p\.email_provenance IS NULL[\s\S]+IS DISTINCT FROM v_ouvertes_avant THEN/);
});

// ---------------------------------------------------------------------------
// Fonctions
// ---------------------------------------------------------------------------
test('préflight : empreintes des corps de l’étape 1, colonne et fonctions neuves absentes', () => {
  for (const [nom, sql] of [
    ['private.fn_growth_agent_prospection', etape1],
    ['private.fn_growth_agent_appels', etape1],
    ['private.fn_growth_cibles_prospection', etape1],
    ['private.fn_growth_prospects_cibles', etape1],
    ['private.fn_growth_email_mssante', apicrypt],
  ]) {
    const empreinte = md5(definition(sql, nom).corps);
    assert.ok(new RegExp(`\\('${nom.replace('.', '\\.')}\\([a-z]*\\)', '${empreinte}', '[vsi]'\\)`).test(migration), `${nom} : empreinte ${empreinte} absente du préflight`);
  }
  assert.match(migration, /to_regprocedure\('private\.fn_growth_email_source\(text,text\)'\) IS NOT NULL\s+OR pg_catalog\.to_regprocedure\('private\.fn_growth_mention_opposition\(text,text\)'\) IS NOT NULL/);
  assert.match(migration, /a\.attname = 'email_provenance' AND NOT a\.attisdropped\) THEN\s+RAISE EXCEPTION/);
  assert.ok(MIGRATION > ETAPE_1, 'la migration suit celle de l’étape 1');
  assert.doesNotMatch(migration, /^\s*(BEGIN|COMMIT);/m);
});

test('décompte : corps de l’étape 1, plus une clé', () => {
  const { retirees, ajoutees } = difference(
    definition(etape1, 'private.fn_growth_cibles_prospection').corps,
    definition(migration, 'private.fn_growth_cibles_prospection').corps);
  assert.deepEqual(retirees, []);
  assert.deepEqual(ajoutees, [
    "    -- Dont celles qui viennent d'un annuaire public ouvert (provenance valide).",
    "    'adresses_annuaire_public', count(*) FILTER (",
    '      WHERE c.email_utilisable',
    "        AND COALESCE(private.fn_growth_email_source(c.finess, c.email)->>'source_code', 'SAISIE_MANUELLE') <> 'SAISIE_MANUELLE'),",
  ]);
});

test('agent email : corps de l’étape 1, mention et source selon l’origine de l’adresse', () => {
  const corps = definition(migration, 'private.fn_growth_agent_prospection').corps;
  const { retirees, ajoutees } = difference(definition(etape1, 'private.fn_growth_agent_prospection').corps, corps);
  assert.deepEqual(retirees, [
    '        v_mention);', '        v_mention);',
    "        'source', 'FINESS (établissement) + Annuaire Santé (email)',",
    '        v_mention);', '        v_mention);',
    "        'telephone', NULLIF(btrim(c.telephone), ''), 'relance_crm', true),",
  ]);
  assert.equal(ajoutees.filter(l => l === '        v_mention_cible);').length, 4, 'les quatre corps portent la mention de leur adresse');
  // Plus aucun corps ne reçoit la mention historique sans passer par la source unique.
  assert.equal(corps.split('v_mention').length - 1 - (corps.split('v_mention_cible').length - 1), 2, 'v_mention : déclaration et verrou de tête seulement');
  assert.equal(corps.split('private.fn_growth_mention_opposition(').length - 1, 2, 'premier contact et relance');
  assert.match(corps, /v_mention_cible := private\.fn_growth_mention_opposition\(r\.finess, r\.email\);\s+IF v_mention_cible IS NULL THEN\s+v_sans_mention := v_sans_mention \+ 1;\s+CONTINUE;/);
  assert.match(corps, /v_mention_cible := private\.fn_growth_mention_opposition\(c\.finess, c\.email\);\s+IF v_mention_cible IS NULL THEN\s+v_sans_mention := v_sans_mention \+ 1;\s+CONTINUE;/);
  assert.match(corps, /'email_source', v_source - 'remplace',/);
  // La relance dit aussi d'où vient son adresse, sans l'ancienne adresse fermée.
  assert.match(corps, /'relance_crm', true,\s+--[^\n]+\s+'email_source', private\.fn_growth_email_source\(c\.finess, c\.email\) - 'remplace'\),/);
  assert.match(corps, /'exclus_sans_mention', v_sans_mention,/);
  // Le verrou « mention historique absente » reste en tête.
  assert.match(corps, /IF v_mention IS NULL THEN\s+RAISE EXCEPTION 'growth_config\.prospection_mention_opposition absente/);
});

test('agent d’appels : corps de l’étape 1, d’abord les cibles qu’aucun email ne peut joindre', () => {
  const { retirees, ajoutees } = difference(
    definition(etape1, 'private.fn_growth_agent_appels').corps,
    definition(migration, 'private.fn_growth_agent_appels').corps);
  assert.deepEqual(retirees, ['               ORDER BY c.pts_type + c.pts_signal + c.pts_tension DESC, c.nom, c.finess']);
  assert.deepEqual(ajoutees, [
    "               -- Un établissement joignable par email attend l'agent email : les fiches",
    "               -- d'appel vont d'abord à ceux qu'aucun email ne peut joindre.",
    '               ORDER BY c.email_utilisable, c.pts_type + c.pts_signal + c.pts_tension DESC, c.nom, c.finess',
  ]);
});

test('mention : même phrase d’opposition que l’existante, origine exacte, rien pour une origine inconnue', () => {
  const semee = /\('prospection_mention_opposition',\s+'((?:[^']|'')+)'/.exec(base);
  assert.ok(semee, 'mention historique introuvable dans 20261109140000');
  const historique = semee[1].replace(/''/g, "'");
  const corps = definition(migration, 'private.fn_growth_mention_opposition').corps;
  const defaut = /'prospection_mention_opposition_annuaire_pa',\s+'((?:[^']|'')+)'\)/.exec(corps);
  assert.ok(defaut, 'mention de l’annuaire introuvable');
  const annuaire = defaut[1].replace(/''/g, "'");
  const couper = texte => { const i = texte.indexOf('). '); assert.ok(i > 0); return [texte.slice(0, i + 2), texte.slice(i + 3)]; };
  const [origineHistorique, oppositionHistorique] = couper(historique);
  const [origineAnnuaire, oppositionAnnuaire] = couper(annuaire);
  assert.equal(oppositionAnnuaire, oppositionHistorique, 'phrase d’opposition reprise mot pour mot');
  assert.match(oppositionAnnuaire, /^Si vous ne souhaitez plus être contacté par Jolene, répondez simplement « STOP » à cet email/);
  assert.equal(origineAnnuaire, "Votre adresse de contact provient de l'annuaire public des établissements pour personnes âgées (pour-les-personnes-agees.gouv.fr, données ouvertes publiées sur data.gouv.fr).");
  assert.notEqual(origineAnnuaire, origineHistorique);
  assert.doesNotMatch(annuaire, /FINESS|Annuaire Santé/);
  // Une origine que le code ne connaît pas n'a pas de mention : pas de branche par défaut.
  assert.doesNotMatch(corps, /\bELSE\b/);
  assert.equal(corps.split('WHEN ').length - 1, 2);
  // La mention historique reste celle des établissements sans aucune provenance. Dès que le
  // prospect en porte une, une adresse qu'elle ne décrit pas n'a pas de mention (adresse changée
  // depuis l'import, fiche CRM corrigée à la main).
  assert.match(corps, /WHEN s\.origine IS NULL AND NOT EXISTS \(\s+SELECT 1 FROM public\.prospects_etablissements p\s+WHERE p\.finess = p_finess AND p\.email_provenance IS NOT NULL\s+\) THEN private\.fn_growth_config\('prospection_mention_opposition', NULL\)/);
  assert.doesNotMatch(corps, /SAISIE_MANUELLE/, 'aucune mention pour une saisie manuelle');
  assert.match(corps, new RegExp(`WHEN s\\.origine->>'source_code' = '${SOURCE.code}' THEN`));
  // La provenance ne vaut que pour l'adresse qu'elle décrit.
  assert.match(definition(migration, 'private.fn_growth_email_source').corps, /AND p\.email_provenance->>'email' = lower\(btrim\(p_email\)\);/);
});

test('aucun envoi, aucune écriture de configuration, aucun droit ouvert', () => {
  assert.doesNotMatch(migration, /net\.http_|pg_net|cron\.schedule|SECURITY DEFINER|\bGRANT\b/);
  assert.doesNotMatch(migration, /(INSERT INTO|UPDATE|DELETE FROM)\s+public\.growth_config/);
  // Brouillons : les deux insertions de l'agent email (premier contact, relance) et celle de
  // l'agent d'appels, rien d'autre.
  assert.equal(migration.split('INSERT INTO public.growth_brouillons').length - 1, 3);
  assert.doesNotMatch(migration, /(UPDATE|DELETE FROM)\s+public\.(growth_brouillons|sales_contacts|sales_taches)\b/);
  for (const signature of ['fn_growth_email_source(text, text)', 'fn_growth_mention_opposition(text, text)', 'fn_growth_cibles_prospection()', 'fn_growth_agent_prospection()', 'fn_growth_agent_appels()']) {
    assert.ok(migration.includes(`REVOKE ALL ON FUNCTION private.${signature} FROM PUBLIC, anon, authenticated;`), signature);
  }
  for (const nom of ['private.fn_growth_email_source', 'private.fn_growth_mention_opposition', 'private.fn_growth_cibles_prospection', 'private.fn_growth_agent_prospection', 'private.fn_growth_agent_appels']) {
    assert.match(definition(migration, nom).entete, /SET search_path TO ''/, nom);
  }
  // Dollar-quoting : étiquettes distinctes, jamais « $$ » (CLAUDE.md, migrations n°8).
  assert.doesNotMatch(migration, /\$\$/);
});

test('adresse saisie à la main et envoi groupé : origine posée, lot fermé aux adresses à provenance', () => {
  const sales = read('src/pages/admin/AdminSales.tsx');
  assert.match(sales, /const saisie = saisieAdresseManuelle\(emailEdit\.valeur\);/);
  assert.match(sales, /\.update\(\{ email: saisie\.email, email_provenance: saisie\.provenance \} as any\)\.eq\('finess', emailEdit\.finess\)/);
  assert.equal(sales.split("from('prospects_etablissements' as any)").length - 1, 2, 'deux écritures seulement : favori et adresse');
  const lib = read('src/lib/agentsCroissance.ts');
  assert.match(lib, /source_code: 'SAISIE_MANUELLE', releve_le: releve/);
  // La contrainte de forme accepte une saisie manuelle sans page source, et elle seule.
  assert.match(migration, /AND \(email_provenance->>'source_code' = 'SAISIE_MANUELLE'\s+OR COALESCE\(email_provenance->>'source_url', ''\) ~ '\^https:\/\/'\)/);
  // L'envoi groupé (éteint avant le lancement) n'emporte aucune adresse dont l'origine est enregistrée.
  const lot = read('supabase/functions/sales-outreach-batch/index.ts');
  assert.match(lot, /if \(cible === "ETABLISSEMENT"\) q = q\.is\("email_provenance", null\);/);
  assert.ok(lot.indexOf('q.is("email_provenance", null)') < lot.indexOf('await q;'), 'filtre posé avant la lecture des destinataires');
});

test('suite SQL, écran et CI : la section 12 existe, l’écran nomme la source, la garde est câblée', () => {
  for (const repere of ['-- 12. Adresses publiques', '-- 12.b Forme de la provenance', '-- 12.c bis Liste d\'appels', '-- 12.e Agent', '-- 12.f Relance',
    "'adresses_annuaire_public', 0,"]) {
    assert.ok(suite.includes(repere), `suite SQL : ${repere}`);
  }
  assert.ok(read('src/lib/agentsCroissance.ts').includes(`${SOURCE.code}:`), 'libellé de la source dans l’écran');
  assert.ok(workflow.includes('node --test tests/node/prospection-adresses-publiques.node.mjs'), 'garde câblée dans validate-pr');
});
