// Zéro visible et liste d'appels (20261124123500, B9) — contrôle hors réseau.
// Ne remplace pas la suite SQL (tests/security/agents-croissance-brouillons.test.sql,
// section 11, exécutée sur le staging sous ROLLBACK) ; verrouille ce qu'elle ne
// peut pas voir :
//   * les empreintes du préflight sont celles des corps du dépôt (md5 du texte
//     entre les deux délimiteurs $body$, comme pg_proc.prosrc), relues en prod
//     le 24/11/2026 ;
//   * chaque fonction redéfinie reprend son corps d'origine : les lignes
//     retirées sont listées, et celles de l'agent email se retrouvent dans
//     l'univers ciblé unique ;
//   * une seule lecture des cibles, une seule règle téléphone, un seul script ;
//   * le script ne reprend que des phrases publiées sur le site, comparées à
//     leur source ;
//   * aucun envoi, aucun appel, aucune écriture dans growth_config, un seul
//     SECURITY DEFINER (le décideur, inventaire mis à jour), câblage CI présent.
import assert from 'node:assert/strict';
import { createHash } from 'node:crypto';
import { readdirSync, readFileSync } from 'node:fs';
import { test } from 'node:test';

const read = path => readFileSync(new URL(`../../${path}`, import.meta.url), 'utf8');
const md5 = body => createHash('md5').update(body, 'utf8').digest('hex');

const MIGRATION = '20261124123500_prospection_zero_visible_liste_appels.sql';
const BASE = '20261109140000_agents_croissance_brouillons.sql';
const MSSANTE = '20261116143942_prospection_sans_mssante.sql';
const SUITE = 'tests/security/agents-croissance-brouillons.test.sql';
const migration = read(`supabase/migrations/${MIGRATION}`);
const base = read(`supabase/migrations/${BASE}`);
const mssante = read(`supabase/migrations/${MSSANTE}`);
const suite = read(SUITE);
const workflow = read('.github/workflows/validate-pr.yml');

// Dernière version du registre de production relue le 24/11/2026.
const DERNIERE_VERSION_DISTANTE = '20261120150000';

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

const sansCommentaires = sql => sql.replace(/--[^\n]*/g, '');
const code = sansCommentaires(migration);

// Fonctions redéfinies : [nom, signature du préflight, source du corps d'origine, SECURITY DEFINER, volatilité].
const REDEFINIES = [
  ['private.fn_growth_agent_prospection', 'private.fn_growth_agent_prospection()', mssante, false, 'v'],
  ['private.fn_growth_entonnoir', 'private.fn_growth_entonnoir(timestamp with time zone,timestamp with time zone)', base, false, 's'],
  ['private.fn_growth_agents_executer', 'private.fn_growth_agents_executer(text)', base, false, 'v'],
  ['public.fn_admin_growth_brouillon_decider', 'public.fn_admin_growth_brouillon_decider(uuid,text,text,text,text)', base, true, 'v'],
];
const NEUVES = [
  ['private.fn_growth_telephone_national', 'private.fn_growth_telephone_national(text)'],
  ['private.fn_growth_prospects_cibles', 'private.fn_growth_prospects_cibles()'],
  ['private.fn_growth_cibles_prospection', 'private.fn_growth_cibles_prospection()'],
  ['private.fn_growth_appel_bloque', 'private.fn_growth_appel_bloque(text,text,text)'],
  ['private.fn_growth_script_appel', 'private.fn_growth_script_appel(text)'],
  ['private.fn_growth_agent_appels', 'private.fn_growth_agent_appels()'],
];

test('une seule migration, horodatée après le registre distant, sans transaction interne ni $$', () => {
  const noms = readdirSync(new URL('../../supabase/migrations/', import.meta.url)).filter(n => n.endsWith('.sql')).sort();
  assert.equal(noms.filter(n => n.endsWith('_prospection_zero_visible_liste_appels.sql')).length, 1);
  assert.match(MIGRATION, /^\d{14}_/);
  assert.ok(MIGRATION.slice(0, 14) > DERNIERE_VERSION_DISTANTE);
  assert.doesNotMatch(migration, /^\s*(BEGIN|COMMIT|ROLLBACK);\s*$/m);
  assert.doesNotMatch(migration, /\$\$/);
  assert.doesNotMatch(migration, /\r/);
});

test('préflight : empreintes = corps du dépôt, avant toute écriture, helpers neufs et contraintes connues', () => {
  const finPreflight = code.indexOf('$prospection_liste_appels_avant$;');
  assert.ok(finPreflight > 0);
  assert.ok(finPreflight < code.search(/\b(CREATE|ALTER|REVOKE|GRANT|UPDATE|INSERT|DELETE)\b/), 'une écriture précède le préflight');
  const preflight = code.slice(0, finPreflight);
  for (const [nom, signature, source, secdef, volatilite] of REDEFINIES) {
    const empreinte = md5(definition(source, nom).corps);
    assert.ok(preflight.includes(`('${signature}', '${empreinte}', ${secdef}, '${volatilite}')`), `${signature} : empreinte ${empreinte}`);
  }
  // Le prédicat unique n'est pas redéfini, mais la règle téléphone repose sur lui.
  const predicat = md5(definition(mssante, 'private.fn_growth_destinataire_bloque').corps);
  assert.ok(preflight.includes(`('private.fn_growth_destinataire_bloque(text,text,text,text,text)', '${predicat}', false, 's')`));
  assert.match(preflight, /IF p\.prosrc IS NULL\s+OR pg_catalog\.md5\(p\.prosrc\) <> p\.empreinte\s+OR p\.prosecdef IS DISTINCT FROM p\.secdef\s+OR p\.provolatile::text <> p\.volatilite\s+OR p\.proconfig IS DISTINCT FROM ARRAY\['search_path=""'\]::text\[\]/);
  assert.match(preflight, /RAISE EXCEPTION 'PROSPECTION_LISTE_APPELS_SOURCE_AVANT_DIVERGENTE(?:[^']|'')*CLAUDE\.md, garde-fous 9\.0 n°2/);
  for (const [, signature] of NEUVES) {
    assert.ok(preflight.includes(`to_regprocedure('${signature}') IS NOT NULL`), signature);
  }
  for (const crm of ['public.fn_admin_sourcing_ajouter_crm(text,text,smallint)',
    'public.fn_admin_crm_effectuer_action(uuid,text,text,timestamp with time zone)',
    'public.fn_sales_outreach_est_interdit(uuid,text,text,text,text)']) {
    assert.ok(preflight.includes(`to_regprocedure('${crm}') IS NULL`), crm);
  }
  assert.ok(preflight.includes("ARRAY['MISSION_A_POURVOIR', 'POST_SOCIAL', 'PROSPECTION_ETABLISSEMENT', 'REACTIVATION']::text[]"));
  assert.ok(preflight.includes("ARRAY['EMAIL', 'FACEBOOK_GROUPE', 'LINKEDIN']::text[]"));
});

test('fonctions définies : quatre redéfinitions à en-tête identique, six fonctions neuves', () => {
  const definies = [...code.matchAll(/CREATE OR REPLACE FUNCTION ([a-z_.]+)\(/g)].map(m => m[1]);
  assert.deepEqual([...definies].sort(), [...REDEFINIES.map(r => r[0]), ...NEUVES.map(n => n[0])].sort());
  for (const [nom, , source] of REDEFINIES) {
    assert.equal(definition(migration, nom).entete, definition(source, nom).entete, `${nom} : en-tête modifié`);
  }
  for (const [nom] of NEUVES) {
    assert.match(definition(migration, nom).entete, /SET search_path TO ''\s*$/, `${nom} : search_path vide attendu`);
    assert.doesNotMatch(definition(migration, nom).entete, /SECURITY\s+DEFINER/i, `${nom} doit rester SECURITY INVOKER`);
  }
});

test('contraintes : élargissement seul, une fiche d\'appel exige un prospect et un numéro', () => {
  const alter = /ALTER TABLE public\.growth_brouillons([\s\S]*?);/.exec(code)[1];
  assert.match(alter, /DROP CONSTRAINT growth_brouillons_agent_check,\s+ADD CONSTRAINT growth_brouillons_agent_check CHECK \(agent IN \(\s+'PROSPECTION_ETABLISSEMENT', 'APPEL_ETABLISSEMENT', 'POST_SOCIAL', 'MISSION_A_POURVOIR', 'REACTIVATION'\s+\)\)/);
  assert.match(alter, /DROP CONSTRAINT growth_brouillons_canal_check,\s+ADD CONSTRAINT growth_brouillons_canal_check CHECK \(canal IN \('EMAIL', 'TELEPHONE', 'LINKEDIN', 'FACEBOOK_GROUPE'\)\)/);
  assert.match(alter, /ADD CONSTRAINT growth_brouillons_telephone_destinataire CHECK \(\s+canal <> 'TELEPHONE'\s+OR \(cible_type = 'PROSPECT_ETABLISSEMENT'\s+AND cible_id IS NOT NULL\s+AND regexp_replace\(COALESCE\(contexte->>'telephone', ''\), '\\D', '', 'g'\) ~ '\^\(0\|330\?\|00330\?\)\[1-9\]\[0-9\]\{8\}\$'\)/);
  assert.equal(code.match(/\bALTER TABLE\b/g).length, 1);
  assert.doesNotMatch(code, /\b(DROP TABLE|DROP COLUMN|TRUNCATE|DROP FUNCTION|DROP POLICY|CREATE POLICY)\b/i);
});

test('agent email : corps d\'origine, sélection déplacée dans l\'univers unique, décompte ajouté', () => {
  const avant = definition(mssante, 'private.fn_growth_agent_prospection').corps;
  const apres = definition(migration, 'private.fn_growth_agent_prospection').corps;
  const univers = definition(migration, 'private.fn_growth_prospects_cibles').corps;
  const { retirees, ajoutees } = difference(avant, apres);
  assert.deepEqual(ajoutees, [
    '             p.pts_type,',
    '             p.pts_signal, p.pts_tension, p.bmo',
    '      -- Univers ciblé unique (départements, types, adresse ouverte, cible libre).',
    '      FROM private.fn_growth_prospects_cibles() p',
    '      WHERE p.email_utilisable AND p.disponible',
    '    -- Places restées vides alors que toutes les cibles disponibles ont été examinées.',
    "    'places_non_pourvues', greatest(0, v_place - v_crees),",
    "    'departements', to_jsonb(v_depts),",
    "    -- Décompte après ce passage : un zéro n'est plus muet (écran d'administration).",
    "    'cibles', private.fn_growth_cibles_prospection());",
  ]);
  // Chaque ligne retirée se retrouve telle quelle dans l'univers unique, sauf
  // celles dont la forme change (lecture des réglages, enchaînement des AND).
  const lignesUnivers = new Set(univers.split('\n').map(l => l.trim()));
  assert.deepEqual(retirees.filter(l => !lignesUnivers.has(l.trim())), [
    '  v_types text[] := private.fn_growth_config_liste(',
    "    'agents_types_cibles', 'EHPAD,HANDICAP,DOMICILE,CENTRE_SANTE,HOPITAL,DIALYSE,ECOLE_SANTE');",
    '      WHERE p.departement = ANY (v_depts)',
    '        AND p.type_jolene = ANY (v_types)',
    "        AND NULLIF(btrim(p.email), '') IS NOT NULL",
    '        -- MSSanté : espace de confiance fermé, un envoi depuis Gmail est rejeté.',
    '        AND NOT private.fn_growth_email_mssante(p.email)',
    '        AND p.email_envoye_le IS NULL',
    '        )',
    '    LIMIT v_place * 3',
    "    'departements', to_jsonb(v_depts));",
  ]);
  assert.equal(retirees.length, 48);
  // Plus de borne avant les contrôles cible par cible (revue B8, M2) ; les relances gardent la leur.
  assert.doesNotMatch(apres, /LIMIT v_place/);
  assert.match(apres, /ORDER BY sc\.prochaine_action_le\s+LIMIT 50/);
  // … et leur équivalent y figure.
  assert.ok(univers.includes("WHERE p.departement = ANY (private.fn_growth_config_liste('agents_departements_cibles', '75,92,56'))"));
  assert.ok(univers.includes("'agents_types_cibles', 'EHPAD,HANDICAP,DOMICILE,CENTRE_SANTE,HOPITAL,DIALYSE,ECOLE_SANTE'));"));
  const utilisable = /\(NULLIF\(btrim\(p\.email\), ''\) IS NOT NULL\s+AND btrim\(p\.email\) ~\* '[^']+'\s+(?:--[^\n]*\s+)?AND NOT private\.fn_growth_email_mssante\(p\.email\)\) AS email_utilisable,/;
  assert.match(univers, utilisable);
  assert.match(univers, /\(p\.email_envoye_le IS NULL\s+AND p\.ajoute_crm_le IS NULL\s+AND p\.statut_sourcing NOT IN \('IGNORE', 'OPPOSITION'\)\s+(?:--[^\n]*\s+)*AND NOT EXISTS \(SELECT 1 FROM public\.sales_contacts sc WHERE sc\.finess = p\.finess\)\s+AND NOT EXISTS \(SELECT 1 FROM public\.etablissements e WHERE e\.finess = p\.finess\)\s+AND NOT EXISTS \(\s+SELECT 1 FROM public\.growth_brouillons b/);
  assert.match(univers, /\(private\.fn_growth_telephone_national\(p\.telephone\) IS NOT NULL\) AS telephone_utilisable,/);
  // Les contrôles cible par cible restent dans la boucle : STOP, puis une séquence par adresse.
  assert.ok(apres.includes("IF private.fn_growth_destinataire_bloque('PROSPECT_ETABLISSEMENT', r.finess, r.email, r.telephone, NULL) IS NOT NULL THEN"));
  assert.ok(apres.includes('WHERE lower(b.destinataire_email) = lower(r.email)'));
});

test('univers ciblé, règle téléphone et décompte : écrits une fois, lus partout', () => {
  // Les réglages de ciblage des types ne sont lus qu'à un endroit.
  assert.equal(code.match(/'agents_types_cibles'/g).length, 1);
  assert.equal(code.match(/FROM private\.fn_growth_prospects_cibles\(\)/g).length, 3, 'agent email, agent d\'appels, décompte');
  for (const nom of ['private.fn_growth_agent_prospection', 'private.fn_growth_agent_appels', 'private.fn_growth_cibles_prospection']) {
    assert.match(definition(migration, nom).corps, /FROM private\.fn_growth_prospects_cibles\(\) [cp]\b/, nom);
    assert.doesNotMatch(sansCommentaires(definition(migration, nom).corps), /FROM public\.prospects_etablissements/, `${nom} relit la table`);
  }
  // Décompte : dans le résultat de l'agent email et dans l'entonnoir figé.
  assert.equal(code.match(/private\.fn_growth_cibles_prospection\(\)/g).filter(Boolean).length >= 3, true);
  assert.match(definition(migration, 'private.fn_growth_entonnoir').corps, /'cibles_agent', private\.fn_growth_cibles_prospection\(\)/);
  // Règle téléphone : le prédicat unique, moins le motif propre à l'email.
  // Le STOP est comparé sous les cinq écritures du numéro ; MSSANTE ne vient que de l'adresse.
  assert.equal(sansCommentaires(definition(migration, 'private.fn_growth_appel_bloque').corps).replace(/\s+/g, ' ').trim(),
    "SELECT CASE WHEN 'STOP' IN (COALESCE(v.national, ''), COALESCE(v.i33, ''), COALESCE(v.i330, ''), COALESCE(v.i0033, ''), COALESCE(v.i00330, '')) THEN 'STOP' ELSE NULLIF(v.national, 'MSSANTE') END FROM ( SELECT private.fn_growth_destinataire_bloque('PROSPECT_ETABLISSEMENT', p_finess, p_email, COALESCE(n.numero, p_telephone), NULL) AS national, private.fn_growth_destinataire_bloque('PROSPECT_ETABLISSEMENT', p_finess, NULL, '33' || substr(n.numero, 2), NULL) AS i33, private.fn_growth_destinataire_bloque('PROSPECT_ETABLISSEMENT', p_finess, NULL, '33' || n.numero, NULL) AS i330, private.fn_growth_destinataire_bloque('PROSPECT_ETABLISSEMENT', p_finess, NULL, '0033' || substr(n.numero, 2), NULL) AS i0033, private.fn_growth_destinataire_bloque('PROSPECT_ETABLISSEMENT', p_finess, NULL, '0033' || n.numero, NULL) AS i00330 FROM (SELECT private.fn_growth_telephone_national(p_telephone) AS numero) n ) v;");
  assert.equal(sansCommentaires(definition(migration, 'private.fn_growth_telephone_national').corps).replace(/\s+/g, ' ').trim(),
    "SELECT CASE WHEN n.chiffres ~ '^0[1-9][0-9]{8}$' THEN n.chiffres WHEN n.chiffres ~ '^33[1-9][0-9]{8}$' THEN '0' || substr(n.chiffres, 3) WHEN n.chiffres ~ '^330[1-9][0-9]{8}$' THEN substr(n.chiffres, 3) WHEN n.chiffres ~ '^0033[1-9][0-9]{8}$' THEN '0' || substr(n.chiffres, 5) WHEN n.chiffres ~ '^00330[1-9][0-9]{8}$' THEN substr(n.chiffres, 5) END FROM (SELECT regexp_replace(COALESCE(p_telephone, ''), '\\D', '', 'g') AS chiffres) n;");
  assert.ok(definition(migration, 'private.fn_growth_agent_appels').corps.includes(
    'IF private.fn_growth_appel_bloque(r.finess, btrim(r.email), r.telephone) IS NOT NULL THEN'));
  assert.ok(definition(migration, 'public.fn_admin_growth_brouillon_decider').corps.includes(
    "v_motif := private.fn_growth_appel_bloque(v_b.cible_id, v_prospect.email, v_b.contexte->>'telephone');"));
  for (const [, signature] of NEUVES) {
    const sig = signature.replace('private.', '').replace(/,/g, ', ');
    assert.ok(migration.includes(`REVOKE ALL ON FUNCTION private.${sig} FROM PUBLIC, anon, authenticated;`), sig);
  }
});

test('agent d\'appels : quota à la semaine, alternance des départements, un numéro une fois, fiches seulement', () => {
  const { corps } = definition(migration, 'private.fn_growth_agent_appels');
  assert.match(corps, /fn_growth_config_int\('agents_appels_quota_semaine', 30, 0, 200\)/);
  assert.match(corps, /fn_growth_config_int\('agents_appels_file_max', 60, 0, 500\)/);
  assert.match(corps, /date_trunc\('week', now\(\) AT TIME ZONE 'Europe\/Paris'\) AT TIME ZONE 'Europe\/Paris'/);
  assert.match(corps, /WHERE c\.telephone_utilisable AND c\.disponible/);
  assert.match(corps, /PARTITION BY c\.departement\s+ORDER BY c\.pts_type \+ c\.pts_signal \+ c\.pts_tension DESC, c\.nom, c\.finess/);
  assert.match(corps, /ORDER BY q\.rang_departement, q\.score_total DESC, q\.nom, q\.finess/);
  // Même règle que la cible : seule une fiche jamais validée puis expirée libère le numéro.
  assert.match(corps, /AND private\.fn_growth_telephone_national\(b\.contexte->>'telephone'\) = v_numero\s+AND NOT \(b\.statut = 'EXPIRE' AND b\.valide_le IS NULL\)/);
  // Pas de borne avant les contrôles cible par cible, et les places non pourvues sont dites.
  assert.doesNotMatch(corps, /\bLIMIT\b/);
  assert.match(corps, /EXIT WHEN v_crees >= v_place;/);
  assert.match(corps, /'places_non_pourvues', greatest\(0, v_place - v_crees\),/);
  assert.match(corps, /'APPEL_ETABLISSEMENT', 'TELEPHONE', 'PROSPECT_ETABLISSEMENT', r\.finess,/);
  assert.match(corps, /private\.fn_growth_script_appel\(r\.type_jolene\)/);
  assert.doesNotMatch(corps, /pts_email|destinataire_email/, 'la part email du score n\'a pas sa place dans une fiche d\'appel');
});

test('orchestrateur et entonnoir : corps d\'origine, lignes modifiées listées', () => {
  const orchestrateur = difference(definition(base, 'private.fn_growth_agents_executer').corps,
    definition(migration, 'private.fn_growth_agents_executer').corps);
  assert.deepEqual(orchestrateur.retirees, [
    "  FOREACH v_agent IN ARRAY ARRAY['PROSPECTION_ETABLISSEMENT', 'POST_SOCIAL', 'MISSION_A_POURVOIR', 'REACTIVATION'] LOOP",
  ]);
  assert.deepEqual(orchestrateur.ajoutees, [
    "  FOREACH v_agent IN ARRAY ARRAY['PROSPECTION_ETABLISSEMENT', 'APPEL_ETABLISSEMENT', 'POST_SOCIAL', 'MISSION_A_POURVOIR', 'REACTIVATION'] LOOP",
    "        WHEN 'APPEL_ETABLISSEMENT' THEN private.fn_growth_agent_appels()",
  ]);
  const entonnoir = difference(definition(base, 'private.fn_growth_entonnoir').corps,
    definition(migration, 'private.fn_growth_entonnoir').corps);
  assert.deepEqual(entonnoir.retirees, [
    "    'crm_stop', (SELECT count(*) FROM public.sales_contacts sc WHERE sc.ne_plus_contacter IS TRUE)",
  ]);
  assert.deepEqual(entonnoir.ajoutees, [
    "    'crm_stop', (SELECT count(*) FROM public.sales_contacts sc WHERE sc.ne_plus_contacter IS TRUE),",
    "    'fiches_appel_notees_periode', (SELECT count(*) FROM public.growth_brouillons b",
    "                                    WHERE b.canal = 'TELEPHONE' AND b.statut = 'ENVOYE'",
    '                                      AND b.envoye_le >= p_debut AND b.envoye_le < p_fin),',
    "    -- État des cibles des agents au moment du calcul (pas une mesure de période).",
    "    'cibles_agent', private.fn_growth_cibles_prospection()",
  ]);
});

test('décideur : garde admin et parcours email intacts, canal téléphone ajouté', () => {
  const avant = definition(base, 'public.fn_admin_growth_brouillon_decider').corps;
  const apres = definition(migration, 'public.fn_admin_growth_brouillon_decider').corps;
  const { retirees, ajoutees } = difference(avant, apres);
  assert.deepEqual(retirees, [
    "  IF v_action IN ('VALIDER', 'MARQUER_ENVOYE') AND v_b.canal = 'EMAIL' THEN",
    '    v_motif := private.fn_growth_destinataire_bloque(',
    '      v_b.cible_type, v_b.cible_id, v_b.destinataire_email,',
    "      v_b.contexte->>'telephone', v_b.contexte->>'finess');",
    "               ELSE 'Destinataire invalide' END",
    "          WHEN 'STOP' THEN 'Contact en opposition (STOP) ou perdu : aucun envoi possible'",
    "          WHEN 'EMAILS_DESACTIVES' THEN 'Le destinataire a désactivé ces emails : aucun envoi possible'",
    "          ELSE 'Destinataire invalide : aucun envoi possible' END);",
    "           statut = 'VALIDE', valide_par = auth.uid(), valide_le = now(), maj_le = now()",
    "       SET statut = 'ENVOYE', envoye_par = auth.uid(), envoye_le = now(), maj_le = now()",
    "    'contact_crm_id', v_contact_id);",
  ]);
  assert.equal(ajoutees.length, 99);
  // Email : la date de validation reste posée à chaque validation, comme avant ; seule la fiche d'appel garde la première.
  assert.match(apres, /statut = 'VALIDE', valide_par = auth\.uid\(\), maj_le = now\(\),\s+(?:--[^\n]*\s+)*valide_le = CASE WHEN v_b\.canal = 'TELEPHONE' AND v_b\.valide_le IS NOT NULL THEN v_b\.valide_le ELSE now\(\) END/);
  // La réponse porte le numéro revérifié (l'écran ne compose jamais un numéro périmé).
  assert.match(apres, /'contact_crm_id', v_contact_id,\s+--[^\n]*\s+'telephone', v_b\.contexte->>'telephone'\);/);
  assert.ok(apres.includes("               ELSE 'Destinataire invalide' END,"), 'le texte de refus par défaut reste le même');
  // Email : même appel du prédicat unique (indenté sous ELSE), mêmes textes de refus.
  assert.match(apres, /ELSE\s+v_consigne := 'aucun envoi possible';\s+v_motif := private\.fn_growth_destinataire_bloque\(\s+v_b\.cible_type, v_b\.cible_id, v_b\.destinataire_email,\s+v_b\.contexte->>'telephone', v_b\.contexte->>'finess'\);/);
  for (const debut of ['Contact en opposition (STOP) ou perdu : ', 'Le destinataire a désactivé ces emails : ', 'Destinataire invalide : ']) {
    assert.ok(apres.includes(`'${debut}' || v_consigne`), debut);
  }
  // Garde d'accès : toujours la première instruction, inchangée.
  assert.match(apres, /\nBEGIN\n  IF auth\.uid\(\) IS NULL OR public\.est_admin\(\) IS NOT TRUE THEN\n    RAISE EXCEPTION 'Accès admin requis' USING ERRCODE = '42501';\n  END IF;/);
  assert.ok(apres.includes('SELECT * INTO v_b FROM public.growth_brouillons WHERE id = p_id FOR UPDATE;'));
  // Téléphone : revérification avant l'appel et au constat, résultat exigé, CRM existant.
  assert.ok(apres.includes("IF v_action IN ('VALIDER', 'MARQUER_ENVOYE') AND v_b.canal IN ('EMAIL', 'TELEPHONE') THEN"));
  assert.match(apres, /IF v_action = 'MARQUER_ENVOYE' AND v_b\.canal = 'TELEPHONE'\s+AND v_resultat NOT IN \('APPEL_REPONDU', 'SANS_REPONSE', 'INTERESSE', 'A_RAPPELER', 'PAS_INTERESSE', 'STOP'\) THEN\s+RAISE EXCEPTION/);
  assert.match(apres, /ELSIF v_b\.canal = 'TELEPHONE' AND v_b\.cible_type = 'PROSPECT_ETABLISSEMENT' THEN[\s\S]*?v_crm := public\.fn_admin_sourcing_ajouter_crm\('ETABLISSEMENT', v_b\.cible_id, v_b\.score\);[\s\S]*?'PREMIER_CONTACT', 'TELEPHONE', 'NORMALE',[\s\S]*?PERFORM public\.fn_admin_crm_effectuer_action\(\s+v_tache_id, v_resultat,/);
  // Revue B8, M1 : VALIDER rejouable revérifie avant chaque appel (STOP, cible passée au CRM,
  // inscrite ou écartée, numéro modifié) ; au constat, un refus entendu est toujours enregistré
  // et tout autre résultat refusé au CRM reste lisible sur la fiche.
  assert.ok(apres.includes("IF v_action IN ('MODIFIER', 'VALIDER', 'REJETER') AND v_b.statut NOT IN ('BROUILLON', 'VALIDE') THEN"));
  // « Déjà suivi » est relu avant l'appel ET au constat (seconde revue, m2) ; le suivi du numéro, avant l'appel seulement.
  assert.match(apres, /IF v_motif IS NULL AND \(\s+v_prospect\.statut_sourcing = 'IGNORE'\s+OR EXISTS \(SELECT 1 FROM public\.sales_contacts sc WHERE sc\.finess = v_b\.cible_id\)\s+OR EXISTS \(SELECT 1 FROM public\.etablissements e WHERE e\.finess = v_b\.cible_id\)\) THEN\s+v_motif := 'DEJA_SUIVI';\s+END IF;\s+IF v_motif IS NULL AND v_action = 'VALIDER' THEN/);
  assert.match(apres, /ELSIF v_motif IN \('STOP', 'DEJA_SUIVI'\) AND v_b\.canal = 'TELEPHONE' AND v_action = 'MARQUER_ENVOYE'\s+AND v_resultat IN \('PAS_INTERESSE', 'STOP'\) THEN[\s\S]*?v_motif := NULL;\s+ELSIF v_motif IS NOT NULL THEN/);
  // Un refus entendu est aussi porté par le prospect (seconde revue, m3).
  assert.match(apres, /IF v_resultat IN \('PAS_INTERESSE', 'STOP'\) THEN\s+UPDATE public\.prospects_etablissements SET statut_sourcing = 'OPPOSITION' WHERE finess = v_b\.cible_id;\s+END IF;/);
  assert.match(apres, /contexte = CASE WHEN v_b\.canal = 'TELEPHONE' AND v_action = 'MARQUER_ENVOYE'\s+THEN contexte \|\| jsonb_build_object\('resultat_appel', v_resultat\)\s+ELSE contexte END\s+WHERE id = p_id;\s+RETURN jsonb_build_object\('success', false/);
  assert.ok(apres.includes("v_consigne := CASE WHEN v_action = 'VALIDER' THEN 'ne pas appeler' ELSE 'appel non enregistré au CRM' END;"));
  // Aucune nouvelle suppression, aucun envoi.
  assert.equal(apres.match(/\bDELETE\b/g).length, avant.match(/\bDELETE\b/g).length);
});

// Littéraux SQL d'un corps de fonction, apostrophes dédoublées rétablies.
const litteraux = corps => [...corps.matchAll(/'((?:[^']|'')*)'/g)].map(m => m[1].replace(/''/g, "'"));
// Réponse d'une FAQ du site (chaîne TypeScript simple ou double, échappements rétablis).
function reponseFaq(fichier, question) {
  const source = read(fichier);
  const debut = source.indexOf(question);
  assert.ok(debut >= 0, `${fichier} : question « ${question} » absente`);
  const m = /r: (['"])((?:\\.|(?!\1).)*)\1/.exec(source.slice(debut));
  assert.ok(m, `${fichier} : réponse introuvable`);
  return m[2].replace(/\\(.)/g, '$1');
}

test('script d\'appel : uniquement des phrases publiées sur le site, comparées à leur source', () => {
  const { corps, entete } = definition(migration, 'private.fn_growth_script_appel');
  assert.match(entete, /RETURNS text\s+LANGUAGE sql\s+IMMUTABLE\s+SET search_path TO ''/);
  const textes = litteraux(corps).filter(t => t.length > 20);
  assert.equal(textes.length, 10, 'quatre paragraphes pour une école, six pour un établissement');
  const ecole = textes.slice(0, 4);
  const etablissement = textes.slice(4);

  // Commission : la phrase de la FAQ de l'accueil, mot pour mot (une seule description de la base).
  const faqAccueil = reponseFaq('src/lib/seo-contenu/accueil.ts', 'Comment fonctionne la commission ?');
  const phraseCommission = faqAccueil.slice(0, faqAccueil.indexOf('. ') + 1);
  assert.equal(phraseCommission, 'Jolene facture à l\'établissement une commission de 15 % HT sur la base financière validée : honoraires HT pour une mission libérale ou rémunération brute contractuelle pour une mission salariée, majorations et indemnités incluses lorsqu’elles entrent dans cette base.');
  const faqGuide = reponseFaq('src/lib/seo-contenu/guides.ts', 'Combien coûte la publication d’une mission ?');
  const phraseAbonnement = faqGuide.slice(0, faqGuide.indexOf('. ') + 1);
  assert.equal(phraseAbonnement, 'Il n’y a ni abonnement ni frais d’entrée : vous ne payez que lorsque vous recrutez.');
  assert.equal(etablissement[3], `${phraseCommission} ${phraseAbonnement}`);
  assert.equal(etablissement.filter(t => /commission|15 %/.test(t)).length, 1, 'la commission n\'est décrite qu\'une fois');

  // Autres affirmations : formulations des pages publiques.
  const recruter = reponseFaq('src/lib/seo-contenu/recruter-soignants.ts', "Jolene Santé est-elle une agence d'intérim ?");
  assert.ok(recruter.includes('plateforme de mise en relation directe'));
  assert.ok(recruter.includes('vous publiez votre besoin, des soignants vérifiés candidatent'));
  assert.ok(etablissement[1].includes('plateforme de mise en relation directe'));
  assert.ok(etablissement[2].startsWith('Vous publiez votre besoin, des soignants vérifiés candidatent'));
  assert.ok(read('src/lib/seo-contenu/accueil.ts').includes('Contrat signé en ligne'));
  assert.ok(etablissement[2].includes('le contrat est signé en ligne'));
  const accueil = read('src/lib/seo-routes.ts');
  assert.ok(accueil.includes('pour des missions et remplacements ponctuels'));
  assert.ok(accueil.includes('Inscription gratuite'));
  assert.ok(etablissement[1].includes('pour des missions et remplacements ponctuels'));
  assert.ok(ecole[1].includes('pour des missions et remplacements ponctuels'));
  assert.ok(ecole[1].includes('inscription est gratuite pour les soignants'));

  // Ni chiffre sans source, ni promesse de délai, ni autre type de prestataire, ni règle de droit.
  assert.deepEqual(etablissement.join(' ').match(/\d+/g), ['15']);
  assert.equal(ecole.join(' ').match(/\d+/g), null);
  for (const texte of [...ecole, ...etablissement]) {
    assert.doesNotMatch(texte, /intérim|agence|freelance|concurren|moins cher|garanti|en quelques minutes|sous \d|loi|décret|article|code du travail|RGPD|CNIL/i, texte);
  }
  // Chaque script se termine par l'origine du numéro puis la possibilité de ne plus être rappelé
  // (information, opposition simple et gratuite : CNIL, prospection téléphonique entre professionnels).
  const information = 'Je vous appelle au numéro de votre établissement, publié dans les annuaires publics des établissements de santé (répertoire FINESS et Annuaire Santé).';
  const opposition = 'Si vous préférez ne pas être rappelé, dites-le-moi : je le note et Jolene ne vous rappellera plus.';
  assert.equal(ecole.at(-1), `${information} ${opposition}`);
  assert.equal(etablissement.at(-1), `${information} ${opposition}`);
  // Même désignation des sources que la mention d'opposition des emails (20261109140000) et que la fiche d'appel.
  assert.ok(base.includes('(répertoire FINESS et Annuaire Santé)'));
  assert.ok(definition(migration, 'private.fn_growth_agent_appels').corps.includes("'Annuaires publics des établissements de santé (répertoire FINESS et Annuaire Santé)'"));
});

test('aucun envoi, aucun appel automatique, aucun réglage écrit, aucun cron touché', () => {
  assert.doesNotMatch(code, /net\.http|pg_net|resend|send-email|twilio|\bsms\b|cron\.(schedule|alter_job|unschedule)/i);
  assert.doesNotMatch(code, /(INSERT INTO|UPDATE|DELETE FROM) public\.growth_config/i, 'les volumes sont des défauts du code');
  // Écritures sur les prospects : le constat d'envoi d'email (corps d'origine du décideur) et
  // l'opposition posée après un refus entendu au téléphone. Aucune adresse, aucun numéro modifié.
  const ecrituresProspects = sql => sansCommentaires(sql).match(/(INSERT INTO|UPDATE|DELETE FROM) public\.prospects_etablissements/gi) ?? [];
  assert.deepEqual(ecrituresProspects(migration), ['UPDATE public.prospects_etablissements', 'UPDATE public.prospects_etablissements']);
  assert.equal(sansCommentaires(migration).match(/UPDATE public\.prospects_etablissements\s+SET (\w+)/g).join('|'),
    'UPDATE public.prospects_etablissements\n         SET email_envoye_le|UPDATE public.prospects_etablissements SET statut_sourcing');
  assert.deepEqual(ecrituresProspects(definition(base, 'public.fn_admin_growth_brouillon_decider').corps), ['UPDATE public.prospects_etablissements']);
});

test('un seul SECURITY DEFINER : le décideur, droits rejoués et inventaire mis à jour', () => {
  // Attribut de fonction (ligne seule), hors messages d'erreur qui citent l'inventaire.
  assert.equal(code.match(/^SECURITY\s+DEFINER\s*$/gim).length, 1);
  assert.match(definition(migration, 'public.fn_admin_growth_brouillon_decider').entete, /SECURITY DEFINER\s+SET search_path TO ''/);
  assert.ok(migration.includes('REVOKE ALL ON FUNCTION public.fn_admin_growth_brouillon_decider(uuid, text, text, text, text) FROM PUBLIC, anon;'));
  assert.ok(migration.includes('GRANT EXECUTE ON FUNCTION public.fn_admin_growth_brouillon_decider(uuid, text, text, text, text) TO authenticated, service_role;'));
  assert.equal(code.match(/\bGRANT\b/g).length, 1, 'aucun autre GRANT');
  assert.match(code, /INSERT INTO private\.security_definer_inventory \(signature, categorie, definition_md5, justification, recense_le\)\s+SELECT 'fn_admin_growth_brouillon_decider\(uuid,text,text,text,text\)', 'ADMIN_EST_ADMIN_VALIDE', pg_catalog\.md5\(p\.prosrc\),/);
  assert.match(code, /ON CONFLICT \(signature\) DO UPDATE\s+SET categorie = EXCLUDED\.categorie,\s+definition_md5 = EXCLUDED\.definition_md5,/);
  const post = code.slice(code.indexOf('$prospection_liste_appels_apres$'));
  assert.match(post, /i\.definition_md5 = pg_catalog\.md5\(f\.prosrc\)/);
  // Revue B8, m1 : aucune donnée réelle (un contact STOP à ce numéro) ne peut faire échouer le déploiement.
  assert.match(post, /fn_growth_appel_bloque\('POSTCONDITION', '[^']+@interop-mssante\.apicrypt\.org', NULL\) IS NOT NULL/);
  assert.doesNotMatch(post, /fn_growth_(appel|destinataire)_bloque\([^)]*'0\d{9}'/);
});

test('la suite SQL couvre le décompte, la liste d\'appels et le constat, sans recopier la règle', () => {
  for (const attendu of ["'Appels : décompte des cibles inexact — %'", "'telephones_utilisables', 12, 'telephones_restants', 9",
    "'Zéro visible : aucun premier contact, toutes les places non pourvues et décompte dans le résultat attendus — %'",
    "'Appels : 3 fiches, 4 STOP, 1 numéro déjà en file sur 8 cibles examinées attendus — %'",
    "'Appels : une place, trois cibles écartées en tête, la fiche attendue pour 012 — %'",
    "'Appels : quota de la semaine atteint, aucune fiche attendue — %'",
    "'Appels : un appel a pu être noté sans résultat'",
    "'Appels : la revérification d''une fiche validée doit réussir — %'",
    "'Appels : une opposition arrivée après la validation doit être vue à la demande d''appel — %'",
    "'Appels : un refus entendu au téléphone doit toujours être enregistré — %'",
    "'Appels : le numéro d''une fiche rejetée ne doit pas être reproposé par un autre établissement — %'",
    "'Contact en opposition (STOP) ou perdu : ne pas appeler'",
    "'Contact en opposition (STOP) ou perdu : appel non enregistré au CRM'",
    "'Établissement déjà suivi au CRM, déjà inscrit ou écarté : ne pas appeler'",
    "'Destinataire invalide : aucun envoi possible'",
    "'Orchestrateur : 5 agents attendus — %'",
    "v_appels_avant + 7"]) {
    assert.ok(suite.includes(attendu), attendu);
  }
  // Revue B8, m3 et m4 : la section 11 ne dépend pas de l'état du staging et ne passe pas à vide.
  const section11 = suite.slice(suite.indexOf("  -- 11. Zéro visible et liste d'appels"));
  assert.doesNotMatch(section11, /places_de_la_semaine'\)::integer (<>|IS DISTINCT FROM) (30|27)\b/, 'valeur absolue dépendante du staging');
  assert.doesNotMatch(section11, /\)::integer <> /, 'comparaison muette sur une valeur absente : écrire IS DISTINCT FROM');
  assert.match(section11, /canal = 'TELEPHONE' AND cible_id LIKE 'ZYTEL%'\s+AND cible_id NOT IN \('ZYTEL001', 'ZYTEL002', 'ZYTEL009'\)/);
  assert.doesNotMatch(sansCommentaires(suite), /NULLIF\(\s*private\.fn_growth_destinataire_bloque/, 'la suite SQL recopie la règle téléphone');
});

test('câblage CI : garde Node et suite SQL sous ROLLBACK', () => {
  assert.match(workflow, /run: node --test tests\/node\/prospection-liste-appels\.node\.mjs/);
  assert.match(workflow, new RegExp(`^\\s+${SUITE.replace(/[.]/g, '\\.')}$`, 'm'));
});
