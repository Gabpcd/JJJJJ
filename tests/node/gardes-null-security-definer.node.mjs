// Garde statique B9 « gardes NULL » : aucune fonction SECURITY DEFINER ne doit
// refuser l'accès avec une comparaison nue à mon_etablissement_id() (NULL pour
// un appelant sans établissement) ou à auth.uid() (colonne nullable), ni nier
// est_admin_etablissement() (NULL sans rôle) : `IF x != NULL AND NOT est_admin()
// THEN refus` vaut NULL et laisse passer. Seule une liste revue, motivée et
// référencée est tolérée ; une entrée devenue sans objet échoue aussi (le gap
// connu reste verrouillé), et une entrée qui renvoie au correctif d'une autre PR
// B9 exige sa preuve dans le dépôt (ordre de merge verrouillé).
// Contexte : docs/GARDES_NULL_SECURITY_DEFINER.md.
import assert from 'node:assert/strict';
import { createHash } from 'node:crypto';
import { readdirSync, readFileSync } from 'node:fs';
import { test } from 'node:test';

const read = path => readFileSync(new URL(`../../${path}`, import.meta.url), 'utf8');
const md5 = value => createHash('md5').update(value, 'utf8').digest('hex');

const MIGRATION = '20261109010957_gardes_null_security_definer.sql';
const DOC = 'docs/GARDES_NULL_SECURITY_DEFINER.md';
const SQL_SUITE = 'tests/security/gardes-null-security-definer.test.sql';
// pg_get_functiondef LIVE exact des 20 fonctions, avant correctif (relu le 09/11).
const LIVE = 'tests/security/fixtures/gardes-null-security-definer-live.sql';
// Dernière version du registre de production relue le 09/11, et migration de la
// PR voisine #1124 (fix/dpae-serveur-cddu-vacation), mergée avant ce lot.
const DERNIERE_VERSION_DISTANTE = '20261102210943';
const MIGRATION_1124 = '20261108223500';
// Fichiers de ce lot : aucune chaîne hexadécimale ≥ 32 (GitGuardian, empreintes calculées).
const FICHIERS_DU_LOT = [
  `supabase/migrations/${MIGRATION}`, LIVE, SQL_SUITE, DOC,
  'tests/node/gardes-null-security-definer.node.mjs',
  'e2e/recette-complete-gardes-null.spec.ts', 'e2e/helpers/recette-complete-gardes-null.ts',
];
// Littéral SQL tel que la migration et la recette l'écrivent.
const litteralSql = v => /[\n\\]/.test(v)
  ? `E'${v.replace(/\\/g, '\\\\').replace(/'/g, "''").replace(/\n/g, '\\n')}'`
  : `'${v.replace(/'/g, "''")}'`;

// ── Analyse ────────────────────────────────────────────────────────────────

export function functions(sql) {
  const out = [];
  const re = /CREATE OR REPLACE FUNCTION\s+("?)(\w+)\1\.("?)(\w+)\3\(/g;
  let m;
  while ((m = re.exec(sql))) {
    const tail = sql.slice(m.index);
    const opening = /\bAS\s+(\$[A-Za-z_0-9]*\$)/.exec(tail);
    if (!opening) continue;
    const bodyStart = opening.index + opening[0].length;
    const bodyEnd = tail.indexOf(opening[1], bodyStart);
    assert.ok(bodyEnd > bodyStart, `${m[4]} : fin de corps introuvable`);
    out.push({
      schema: m[2],
      name: m[4],
      header: tail.slice(0, opening.index),
      body: tail.slice(bodyStart, bodyEnd),
      securityDefiner: /\bSECURITY\s+DEFINER\b/i.test(tail.slice(0, opening.index)),
    });
    re.lastIndex = m.index + bodyEnd;
  }
  return out;
}

// Commentaires retirés, littéraux vidés (longueurs conservées).
function code(body) {
  let out = '';
  for (let i = 0; i < body.length;) {
    if (body[i] === "'") {
      let j = i + 1;
      while (j < body.length && !(body[j] === "'" && body[j + 1] !== "'")) j += body[j] === "'" ? 2 : 1;
      out += "'" + ' '.repeat(Math.max(0, j - i - 1)) + "'";
      i = j + 1;
    } else if (body[i] === '-' && body[i + 1] === '-') {
      while (i < body.length && body[i] !== '\n') { out += ' '; i++; }
    } else {
      out += body[i++];
    }
  }
  return out;
}

function until(text, from, stop) {
  let depth = 0;
  for (let j = from; j < text.length; j++) {
    if (text[j] === '(') depth++;
    else if (text[j] === ')') depth--;
    else if (depth === 0 && stop(text, j)) return j;
  }
  return text.length;
}

const isThen = (t, j) => /^THEN\b/i.test(t.slice(j, j + 5)) && !/\w/.test(t[j - 1] ?? ' ');

export function segments(body) {
  const text = code(body);
  const segs = [];
  for (const m of text.matchAll(/\b(ELSIF|IF)\b/gi)) {
    if (/\bEND\s+$/i.test(text.slice(Math.max(0, m.index - 8), m.index))) continue;
    const start = m.index + m[0].length;
    segs.push({ kind: 'IF', text: text.slice(start, until(text, start, isThen)) });
  }
  for (const m of text.matchAll(/([A-Za-z_][\w.]*)\s*:=/g)) {
    const start = m.index + m[0].length;
    segs.push({ kind: 'ASSIGN', target: m[1], text: text.slice(start, until(text, start, (t, j) => t[j] === ';')) });
  }
  return { text, segs };
}

function groups(text, pos) {
  const stack = [];
  for (let i = 0; i < pos; i++) {
    if (text[i] === '(') stack.push(i);
    else if (text[i] === ')') stack.pop();
  }
  return stack;
}

const MON = String.raw`(?:public\.)?mon_etablissement_id\(\)`;
const UID = String.raw`auth\.uid\(\)`;
const squash = s => s.replace(/\s+/g, ' ').trim();
const isNull = operande => new RegExp(String.raw`${operande}\s+IS\s+(?:NOT\s+)?NULL\b`, 'i');
const echapper = s => s.replace(/[.*+?^${}()|[\]\\]/g, '\\$&');
const OPERANDE = String.raw`[A-Za-z_][\w.]*(?:\(\s*\))?`;

// Deux règles, un même défaut : la comparaison vaut NULL et une garde de refus
// `IF x != y THEN refus` / `IF NOT (… x = y …) THEN refus` / `IF NOT x = y THEN refus`
// (NOT lie moins fort que =) ne refuse pas.
//   * mon_etablissement_id : NULL pour un appelant sans établissement actif. Une
//     variable qui le reçoit exactement est suivie, sauf si elle est testée
//     IS [NOT] NULL quelque part dans le corps.
//   * auth.uid : la colonne comparée est nullable (mission non assignée,
//     soignant_assigne_id NULL) ; seul un test IS [NOT] NULL de l'autre opérande
//     dans la même condition exempte. Un test de auth.uid() lui-même n'exempte
//     pas : il ne rend pas la colonne non nulle.
// Choix conservateur, documenté (DOC §3) : le scanner ne suit pas le flot de
// données. Une affectation `ok := … = mon_etablissement_id()` est signalée même
// si chaque lecture de `ok` est ensuite sous COALESCE (forme sûre « COALESCE à
// l'usage », B5b et fix/scanner-code-sans-code-suivant) ; ces cas passent par
// REVUES avec une preuve exigée dans le corps.
const REGLES = [
  { regle: 'mon_etablissement_id', base: MON, suivreVariables: true, exempteSiCibleTestee: true },
  { regle: 'auth.uid', base: UID, suivreVariables: true, exempteSiCibleTestee: false },
];

function cibles(text, segs, r) {
  const vars = new Set();
  for (const m of text.matchAll(new RegExp(String.raw`\b([A-Za-z_]\w*)\s+uuid\s*:=\s*${r.base}\s*;`, 'gi'))) vars.add(m[1]);
  for (const s of segs) if (s.kind === 'ASSIGN' && new RegExp(String.raw`^\s*${r.base}\s*$`, 'i').test(s.text)) vars.add(s.target);
  return [r.base, ...[...vars]
    .filter(v => !r.exempteSiCibleTestee || !isNull(String.raw`\b${v}`).test(text))
    .map(v => String.raw`\b${v}\b(?!\s*\()`)];
}

export function scan(fn) {
  const { text, segs } = segments(fn.body);
  const hits = [];
  for (const r of REGLES) {
    const targets = cibles(text, segs, r);
    for (const s of segs) {
      for (const t of targets) {
        const re = new RegExp(String.raw`(!=|<>|(?<![:<>!=])=(?![>=]))\s*${t}|${t}\s*(!=|<>|=(?![>=]))`, 'gi');
        for (const m of s.text.matchAll(re)) {
          const op = m[1] || m[2];
          const g = groups(s.text, m.index);
          if (g.some(i => /^\(\s*SELECT\b/i.test(s.text.slice(i)))) continue; // WHERE : NULL exclut la ligne
          if (g.some(i => /\bCOALESCE\s*$/i.test(s.text.slice(0, i)))) continue;
          if (r.exempteSiCibleTestee && isNull(t).test(s.text)) continue;
          // Autre opérande de la comparaison : à gauche de l'opérateur, ou à droite de la cible.
          const debutGroupe = g.length ? g[g.length - 1] + 1 : 0;
          const avant = s.text.slice(debutGroupe, m.index);
          const autre = m[1]
            ? new RegExp(String.raw`(${OPERANDE})\s*$`).exec(avant)?.[1]
            : new RegExp(String.raw`^\s*(${OPERANDE})`).exec(s.text.slice(m.index + m[0].length))?.[1];
          if (!r.exempteSiCibleTestee && autre && isNull(echapper(autre)).test(s.text)) continue;
          const underNot = g.some(i => /\bNOT\s*$/i.test(s.text.slice(0, i)))
            // NOT sans parenthèses : `NOT x = cible` ou `NOT cible = x`.
            || (m[1] ? new RegExp(String.raw`\bNOT\s+${OPERANDE}\s*$`, 'i').test(avant) : /\bNOT\s*$/i.test(avant));
          if (s.kind === 'ASSIGN' || op === '!=' || op === '<>' || underNot) {
            hits.push({ fonction: fn.name, kind: s.kind, target: s.target ?? null, regle: r.regle, condition: squash(s.text) });
          }
        }
      }
    }
  }
  for (const s of segs) {
    if (s.kind !== 'IF') continue;
    for (const m of s.text.matchAll(/(?:public\.)?est_admin_etablissement\(\)/gi)) {
      const g = groups(s.text, m.index);
      if (g.some(i => /\bCOALESCE\s*$/i.test(s.text.slice(0, i)))) continue;
      const directNot = /\bNOT\s+$/i.test(s.text.slice(0, m.index));
      if (directNot || g.some(i => /\bNOT\s*$/i.test(s.text.slice(0, i)))) {
        hits.push({ fonction: fn.name, kind: s.kind, target: null, regle: 'NOT est_admin_etablissement', condition: squash(s.text) });
      }
    }
  }
  return hits;
}

const scanSql = sql => functions(sql).filter(f => f.securityDefiner).flatMap(scan);

// ── Liste revue (chaque entrée motivée ; voir DOC) ─────────────────────────
//
// Une entrée `preuve` n'est acceptée que si la preuve figure dans la définition
// versionnée la plus récente de la fonction : la migration `dependance` (et toute
// migration ultérieure qui la redéfinit) si elle est dans le dépôt, sinon le dump.
// Tant que la PR qui porte le correctif n'est pas mergée et cette branche rebasée,
// la garde échoue : l'ordre de merge est verrouillé (DOC §7), et main ne peut pas
// afficher une raison « corrigée » fausse.

const SCANNER_B9 = {
  dependance: '20261102205212_scanner_code_sans_code_suivant.sql',
  branche: 'fix/scanner-code-sans-code-suivant',
};
const B5B = {
  dependance: '20261102210943_visibilite_etablissement_par_permission.sql',
  branche: 'fix/visibilite-etablissement-par-permission',
};

const REVUES = [
  { fonction: 'fn_declarer_fin_retroactive', kind: 'ASSIGN', motif: 'v_caller_is_etab_admin', ...SCANNER_B9,
    preuve: 'OR COALESCE(v_caller_is_etab_admin, false)',
    raison: 'Corrigée par la PR B9 fix/scanner-code-sans-code-suivant (20261102205212) : variable lue sous COALESCE à l’usage ; non redéfinie ici pour ne pas réintroduire le code suivant.' },
  { fonction: 'fn_declarer_fin_retroactive', kind: 'ASSIGN', motif: 'v_caller_is_soignant', ...SCANNER_B9,
    preuve: 'NOT (COALESCE(v_caller_is_soignant, false)',
    raison: 'Même correctif (20261102205212) : v_caller_is_soignant lu sous COALESCE dans la garde ; le contexte système (auth.uid() NULL) y garde son comportement LIVE.' },
  { fonction: 'fn_etat_pointage_mission', kind: 'ASSIGN', motif: 'v_is_etab', ...B5B,
    preuve: 'IF NOT COALESCE(v_is_etab, false) AND NOT COALESCE(v_is_soignant, false) THEN',
    raison: 'Corrigée par la PR B9 fix/visibilite-etablissement-par-permission (B5b, 20261102210943) : COALESCE à l’usage, code réservé à la permission pointage ; retirée de ce lot pour ne pas entrer en collision.' },
  { fonction: 'fn_etat_pointage_mission', kind: 'ASSIGN', motif: 'v_is_soignant', ...B5B,
    preuve: 'IF NOT COALESCE(v_is_etab, false) AND NOT COALESCE(v_is_soignant, false) THEN',
    raison: 'Même correctif B5b : v_is_soignant (NULL sur une mission non assignée) n’est lu que sous COALESCE dans la garde ; est_etab reste null pour le soignant.' },
  { fonction: 'fn_creer_reclamation_score', kind: 'IF', motif: 'v_proprio_id != v_uid',
    raison: 'Branche SOIGNANT : v_uid testé IS NULL en tête, v_proprio_id lu dans evenements_score_soignant.soignant_id (NOT NULL) après le test v_event.id IS NULL : la comparaison ne vaut jamais NULL.' },
  { fonction: 'dec_valider_paiement_facture', kind: 'IF', motif: 'NEW.etablissement_id != mon_etablissement_id()', raison: 'Trigger factures : RLS UPDATE réservée à est_admin() ; le NULL est porteur pour le contexte système (webhook, cron sans auth.uid()) qui passe la facture PAYEE.' },
  { fonction: 'fn_ouvrir_litige_rate_limited', kind: 'IF', motif: 'v_mission.soignant_assigne_id = v_uid', raison: 'NULL seulement si la mission n’a pas de soignant assigné ; la lecture factures_honoraires (soignant_id = NULL) ne trouve alors rien et refuse.' },
  { fonction: 'fn_ouvrir_litige_rate_limited', kind: 'ASSIGN', motif: 'v_initie_par', raison: 'CASE calculé après la garde : sur une mission sans soignant assigné, seule la branche établissement a pu passer, et le ELSE « ETABLISSEMENT » est exact.' },
  { fonction: 'fn_suivi_remboursements_connect_facture', kind: 'ASSIGN', motif: 'v_finance', raison: 'Conjonction avec fn_a_permission_etablissement(...) IS TRUE : sans établissement, ce terme vaut false et NULL AND false = false.' },
  ...['dec_proteger_mission_soignant', 'dec_proteger_presence_soignant', 'fn_protect_contrat_integrity', 'fn_protect_mission_financials', 'fn_protect_presence_integrity']
    .map(fonction => ({ fonction, kind: 'IF', motif: 'est_admin_etablissement()', raison: 'Volet 2 (helper) instruit dans la DOC : corriger réactiverait le revert pour tous les soignants et le contexte système (désistement, finances) ; écriture directe soignant fermée par la RLS.' })),
];

const revue = hit => REVUES.find(r => r.fonction === hit.fonction && r.kind === hit.kind
  && (hit.target === r.motif || hit.condition.includes(r.motif)));

const MIGRATIONS_DIR = new URL('../../supabase/migrations/', import.meta.url);
const migrationsDuDepot = () => readdirSync(MIGRATIONS_DIR).filter(name => /^\d{14}_.*\.sql$/.test(name)).sort();

// Définition versionnée la plus récente : migration `dependance` ou ultérieure qui
// redéfinit la fonction, sinon le dump.
export function corpsEffectif(r, { migrations = migrationsDuDepot(), lire = name => read(`supabase/migrations/${name}`), dump = read('supabase/schema/public.sql') } = {}) {
  const dependanceMergee = migrations.includes(r.dependance);
  if (dependanceMergee) {
    const definitions = migrations.filter(name => name >= r.dependance)
      .flatMap(name => functions(lire(name)).filter(f => f.schema === 'public' && f.name === r.fonction).map(f => ({ name, body: f.body })));
    if (definitions.length) return { source: definitions.at(-1).name, body: definitions.at(-1).body, dependanceMergee };
  }
  const enDump = functions(dump).filter(f => f.schema === 'public' && f.name === r.fonction);
  return { source: 'supabase/schema/public.sql', body: enDump.at(-1)?.body ?? '', dependanceMergee };
}

const preuveTenue = (r, options) => squash(code(corpsEffectif(r, options).body)).includes(squash(r.preuve));

// ── Manifeste de la migration (LIVE relu le 2026-11-03, puis le 2026-11-09) ──
//
// Aucune empreinte écrite en dur : la référence LIVE est la fixture
// pg_get_functiondef versionnée, comparée texte à texte.

const CORRECTIFS = [
  ['fn_valider_alerte_presence(uuid)',
    '    IF v_presence.etablissement_id != v_etab_id AND NOT est_admin() THEN',
    '    IF NOT COALESCE(v_presence.etablissement_id = v_etab_id, false) AND NOT est_admin() THEN'],
  ['fn_codes_pointage_mission(uuid)',
    '  IF NOT est_admin() AND v_mission.etablissement_id != mon_etablissement_id() THEN',
    '  IF NOT est_admin() AND NOT COALESCE(v_mission.etablissement_id = mon_etablissement_id(), false) THEN'],
  ['fn_generer_code_secours_mission(uuid,text)',
    '  IF NOT (est_admin() OR v_mission.etablissement_id = mon_etablissement_id()) THEN',
    '  IF NOT (est_admin() OR COALESCE(v_mission.etablissement_id = mon_etablissement_id(), false)) THEN'],
  ['fn_generer_qr_mission(uuid,text)',
    '  IF NOT (est_admin() OR v_mission.etablissement_id = mon_etablissement_id()) THEN',
    '  IF NOT (est_admin() OR COALESCE(v_mission.etablissement_id = mon_etablissement_id(), false)) THEN'],
  ['fn_soignants_urgence(uuid)',
    '  IF NOT (public.est_admin() OR v_mission.etablissement_id = public.mon_etablissement_id()) THEN',
    '  IF NOT (public.est_admin() OR COALESCE(v_mission.etablissement_id = public.mon_etablissement_id(), false)) THEN'],
  ['fn_generer_donnees_dpae(uuid)',
    '  IF NOT (est_admin() OR v_etab_id = mon_etablissement_id()) THEN',
    '  IF NOT (est_admin() OR COALESCE(v_etab_id = mon_etablissement_id(), false)) THEN'],
  ['fn_enregistrer_numero_dpae(uuid,text)',
    '  IF NOT (est_admin() OR v_etab_id = mon_etablissement_id()) THEN',
    '  IF NOT (est_admin() OR COALESCE(v_etab_id = mon_etablissement_id(), false)) THEN'],
  ['fn_rebooker_soignant(uuid,uuid,timestamp with time zone,timestamp with time zone)',
    '  IF v_m.etablissement_id <> public.mon_etablissement_id() AND NOT public.est_admin() THEN',
    '  IF NOT COALESCE(v_m.etablissement_id = public.mon_etablissement_id(), false) AND NOT public.est_admin() THEN'],
  ['fn_booster_mission(uuid)',
    '  IF v_m.etablissement_id <> public.mon_etablissement_id() AND NOT public.est_admin() THEN',
    '  IF NOT COALESCE(v_m.etablissement_id = public.mon_etablissement_id(), false) AND NOT public.est_admin() THEN'],
  ['fn_presences_detail_mission(uuid)',
    '    IF v_mission.etablissement_id != mon_etablissement_id() AND NOT est_admin() \n       AND v_mission.soignant_assigne_id != auth.uid() THEN',
    '    IF NOT COALESCE(v_mission.etablissement_id = mon_etablissement_id(), false) AND NOT est_admin()\n       AND NOT COALESCE(v_mission.soignant_assigne_id = auth.uid(), false) THEN'],
  ['fn_activer_garantie_mission(uuid,boolean)',
    '  IF v_m.etablissement_id != mon_etablissement_id() AND NOT est_admin() THEN',
    '  IF NOT COALESCE(v_m.etablissement_id = mon_etablissement_id(), false) AND NOT est_admin() THEN'],
  ['fn_deposer_chorus(uuid,text)',
    '    IF v_facture.etablissement_id != mon_etablissement_id() AND NOT est_admin() THEN',
    '    IF NOT COALESCE(v_facture.etablissement_id = mon_etablissement_id(), false) AND NOT est_admin() THEN'],
  ['fn_generer_facture(uuid)',
    '    IF NOT est_admin() AND v_mission.etablissement_id != mon_etablissement_id() THEN',
    '    IF NOT est_admin() AND NOT COALESCE(v_mission.etablissement_id = mon_etablissement_id(), false) THEN'],
  ['fn_diffuser_pool_urgence(uuid)',
    '    OR v_etablissement_id = public.mon_etablissement_id()\n  ) THEN',
    '    OR COALESCE(v_etablissement_id = public.mon_etablissement_id(), false)\n  ) THEN'],
  ['fn_etablissement_pour_mission(uuid)',
    '    ) AND mon_etablissement_id() != p_etablissement_id AND NOT est_admin() THEN',
    '    ) AND NOT COALESCE(mon_etablissement_id() = p_etablissement_id, false) AND NOT est_admin() THEN'],
  ['fn_annuler_serie(uuid)',
    '    IF NOT est_admin_etablissement() AND NOT est_admin() THEN',
    '    IF NOT COALESCE(est_admin_etablissement(), false) AND NOT est_admin() THEN'],
  ['fn_assigner_mission_admin(uuid,uuid,text)',
    '  IF NOT (public.est_admin() OR public.est_admin_etablissement()) THEN',
    '  IF NOT (public.est_admin() OR COALESCE(public.est_admin_etablissement(), false)) THEN'],
  ['fn_creer_reclamation_score(uuid,text,text,text,text)',
    "  IF p_evenement_type = 'ETAB' AND v_proprio_id != mon_etablissement_id() THEN",
    "  IF p_evenement_type = 'ETAB' AND NOT COALESCE(v_proprio_id = mon_etablissement_id(), false) THEN"],
  ['fn_declarer_honoraires_retrocession(uuid,numeric,text)',
    '  IF v_m.etablissement_id != mon_etablissement_id() AND NOT est_admin() THEN',
    '  IF NOT COALESCE(v_m.etablissement_id = mon_etablissement_id(), false) AND NOT est_admin() THEN'],
  ['fn_definir_retrocession_mission(uuid,numeric)',
    '  IF v_m.etablissement_id != mon_etablissement_id() AND NOT est_admin() THEN',
    '  IF NOT COALESCE(v_m.etablissement_id = mon_etablissement_id(), false) AND NOT est_admin() THEN'],
].map(([signature, garde, correctif]) => ({ signature, name: signature.split('(')[0], garde, correctif }));

// Règle auth.uid : appliquée à toutes les migrations à partir de celle-ci mais,
// dans le dump, seulement aux fonctions de ce lot et de REVUES (verrou de
// régression). Le reste du dump (34 occurrences dans 31 fonctions SECURITY
// DEFINER au 03/11, colonnes NOT NULL ou contexte système pour la plupart) est
// hors périmètre : DOC §3.
const PERIMETRE_UID = new Set([...CORRECTIFS.map(c => c.name), ...REVUES.map(r => r.fonction)]);
const dansPerimetre = hit => hit.regle !== 'auth.uid' || PERIMETRE_UID.has(hit.fonction);

// Branches B9 du 02/11 dont la migration précède celle-ci (DOC §7).
const FRERES = [
  ['fix/score-matching-inconnu-null', '20261102204820'],
  [SCANNER_B9.branche, SCANNER_B9.dependance.slice(0, 14)],
  ['fix/contestation-paiement-soignant', '20261102205808'],
  [B5B.branche, B5B.dependance.slice(0, 14)],
];

// ── Tests ──────────────────────────────────────────────────────────────────

test('le scanner reconnaît les formes NULL connues et leurs corrections', () => {
  const fn = body => ({ name: 'f', body, securityDefiner: true });
  const bad = [
    'BEGIN IF x.etablissement_id != mon_etablissement_id() AND NOT est_admin() THEN RETURN 1; END IF; END;',
    'BEGIN IF NOT (est_admin() OR x.etablissement_id = public.mon_etablissement_id()) THEN RETURN 1; END IF; END;',
    'DECLARE v uuid := mon_etablissement_id(); BEGIN IF x <> v AND NOT est_admin() THEN RETURN 1; END IF; END;',
    'BEGIN ok := est_admin() OR x = mon_etablissement_id(); IF NOT ok THEN RETURN 1; END IF; END;',
    'BEGIN IF NOT est_admin_etablissement() AND NOT est_admin() THEN RETURN 1; END IF; END;',
    'BEGIN IF NOT (est_admin() OR public.est_admin_etablissement()) THEN RETURN 1; END IF; END;',
    // NOT lie moins fort que = : `NOT x = y` vaut `NOT (x = y)`, donc NULL.
    'BEGIN IF NOT x.etablissement_id = mon_etablissement_id() THEN RETURN 1; END IF; END;',
    'BEGIN IF NOT mon_etablissement_id() = x.etablissement_id AND NOT est_admin() THEN RETURN 1; END IF; END;',
    // Colonne nullable comparée à auth.uid() (mission non assignée).
    'BEGIN IF NOT COALESCE(v_mission.etablissement_id = mon_etablissement_id(), false) AND NOT est_admin() AND v_mission.soignant_assigne_id != auth.uid() THEN RETURN 1; END IF; END;',
    'BEGIN IF NOT COALESCE(v_mission.etablissement_id = mon_etablissement_id(), false) AND v_mission.soignant_assigne_id <> auth.uid() THEN RETURN 1; END IF; END;',
    'BEGIN IF NOT (v_mission.soignant_assigne_id = auth.uid() OR est_admin()) THEN RETURN 1; END IF; END;',
    'BEGIN IF NOT v_mission.soignant_assigne_id = auth.uid() THEN RETURN 1; END IF; END;',
    'DECLARE v_uid uuid := auth.uid(); BEGIN IF v_uid IS NULL THEN RETURN 0; END IF; IF v_mission.soignant_assigne_id != v_uid THEN RETURN 1; END IF; END;',
    'BEGIN v_is_soignant := v_mission.soignant_assigne_id = auth.uid(); IF NOT v_is_soignant THEN RETURN 1; END IF; END;',
  ];
  const good = [
    'BEGIN IF NOT COALESCE(x.etablissement_id = mon_etablissement_id(), false) AND NOT est_admin() THEN RETURN 1; END IF; END;',
    'BEGIN IF x.etablissement_id IS DISTINCT FROM mon_etablissement_id() AND NOT est_admin() THEN RETURN 1; END IF; END;',
    'BEGIN IF mon_etablissement_id() IS NULL OR mon_etablissement_id() <> p THEN RETURN 1; END IF; END;',
    'BEGIN IF NOT EXISTS (SELECT 1 FROM m WHERE m.etablissement_id = mon_etablissement_id()) THEN RETURN 1; END IF; END;',
    'BEGIN IF x = mon_etablissement_id() THEN RETURN 1; END IF; END;',
    "BEGIN IF NOT COALESCE(est_admin_etablissement(), false) THEN RETURN 1; END IF; -- x != mon_etablissement_id()\n RAISE 'a != mon_etablissement_id()'; END;",
    'DECLARE v uuid := mon_etablissement_id(); BEGIN IF v IS NULL THEN RETURN 1; END IF; IF x <> v THEN RETURN 2; END IF; END;',
    // Formes corrigées de ce lot (fn_presences_detail_mission).
    'BEGIN IF NOT COALESCE(v_mission.etablissement_id = mon_etablissement_id(), false) AND NOT est_admin() AND NOT COALESCE(v_mission.soignant_assigne_id = auth.uid(), false) THEN RETURN 1; END IF; END;',
    'BEGIN IF v_mission.soignant_assigne_id IS DISTINCT FROM auth.uid() THEN RETURN 1; END IF; END;',
    'BEGIN IF v_mission.soignant_assigne_id IS NULL OR v_mission.soignant_assigne_id != auth.uid() THEN RETURN 1; END IF; END;',
    'BEGIN IF v_mission.soignant_assigne_id = auth.uid() THEN RETURN 1; END IF; END;',
    'BEGIN IF NOT EXISTS (SELECT 1 FROM p WHERE p.soignant_id = auth.uid()) THEN RETURN 1; END IF; END;',
  ];
  for (const body of bad) assert.ok(scan(fn(body)).length > 0, body);
  for (const body of good) assert.deepEqual(scan(fn(body)), [], body);
  // Choix conservateur (DOC §3) : la forme sûre « COALESCE à l'usage » reste
  // signalée, faute de suivi du flot de données ; elle passe par REVUES + preuve.
  const coalesceALUsage = 'BEGIN ok := x.etablissement_id = mon_etablissement_id(); IF NOT COALESCE(ok, false) THEN RETURN 1; END IF; END;';
  assert.deepEqual(scan(fn(coalesceALUsage)).map(h => [h.kind, h.target, h.regle]), [['ASSIGN', 'ok', 'mon_etablissement_id']]);
});

test('REVUES conditionnées : la preuve suit la redéfinition la plus récente (verrou d’ordre de merge)', () => {
  const r = { fonction: 'f', dependance: '20261102210943_b.sql', preuve: 'NOT COALESCE(ok, false)' };
  const def = corps => `CREATE OR REPLACE FUNCTION public.f() RETURNS void LANGUAGE plpgsql SECURITY DEFINER AS $x$ ${corps} $x$;`;
  const vuln = def('BEGIN ok := x = mon_etablissement_id(); IF NOT ok THEN RETURN; END IF; END;');
  const corrige = def('BEGIN ok := x = mon_etablissement_id(); IF NOT COALESCE(ok, false) THEN RETURN; END IF; END;');
  const commentaire = def('BEGIN -- NOT COALESCE(ok, false)\n ok := x = mon_etablissement_id(); IF NOT ok THEN RETURN; END IF; END;');
  const cas = (migrations, fichiers, dump) => preuveTenue(r, { migrations, lire: name => fichiers[name], dump });
  // PR B9 dépendante non mergée, dump LIVE vulnérable : refus.
  assert.equal(cas(['20261109010957_ce_lot.sql'], { '20261109010957_ce_lot.sql': '' }, vuln), false);
  // Preuve en commentaire seulement : refus.
  assert.equal(cas([], {}, commentaire), false);
  // PR B9 mergée (migration présente), dump pas encore re-baseliné : accepté.
  assert.equal(cas(['20261102210943_b.sql', '20261109010957_ce_lot.sql'], { '20261102210943_b.sql': corrige, '20261109010957_ce_lot.sql': '' }, vuln), true);
  // Une migration ultérieure redéfinit sans le correctif : refus.
  assert.equal(cas(['20261102210943_b.sql', '20261104000000_regression.sql'], { '20261102210943_b.sql': corrige, '20261104000000_regression.sql': vuln }, corrige), false);
  // Dump re-baseliné après déploiement : accepté.
  assert.equal(cas([], {}, corrige), true);
});

test('dump : aucune garde SECURITY DEFINER NULL hors liste revue, aucune entrée sans objet', () => {
  const hits = scanSql(read('supabase/schema/public.sql')).filter(dansPerimetre);
  const nonRevues = hits.filter(hit => !revue(hit));
  assert.deepEqual(nonRevues, [], `Gardes de refus NULL sur mon_etablissement_id()/auth.uid()/est_admin_etablissement() : ${JSON.stringify(nonRevues, null, 1)}`);
  for (const r of REVUES) {
    assert.ok(hits.some(hit => revue(hit) === r), `Entrée revue sans objet (gap fermé ?) : ${r.fonction} ${r.motif} — retirer de REVUES et mettre ${DOC} à jour`);
    assert.ok(r.raison.length > 40, r.fonction);
  }
  assert.deepEqual([...new Set(hits.map(h => h.fonction))].sort(), [...new Set(REVUES.map(r => r.fonction))].sort());
});

test('ordre de merge : les correctifs B9 dont dépendent les entrées revues sont mergés', () => {
  for (const r of REVUES.filter(entree => entree.preuve)) {
    const { source, dependanceMergee } = corpsEffectif(r);
    assert.ok(preuveTenue(r), `${r.fonction} (${r.motif}) : preuve « ${r.preuve} » absente de ${source}. `
      + (dependanceMergee
        ? 'La redéfinition la plus récente a perdu le correctif.'
        : `Merger d’abord ${r.branche} (${r.dependance}), puis rebaser cette branche : DOC §7.`));
  }
});

test('migrations à partir de celle-ci : aucune nouvelle garde NULL', () => {
  const recentes = migrationsDuDepot().filter(name => name >= MIGRATION);
  assert.ok(recentes.includes(MIGRATION));
  for (const name of recentes) {
    const nonRevues = scanSql(read(`supabase/migrations/${name}`)).filter(hit => !revue(hit));
    assert.deepEqual(nonRevues, [], `${name} : ${JSON.stringify(nonRevues, null, 1)}`);
  }
});

test('migration : une seule migration, postérieure au registre distant et à #1124, aucune empreinte en dur', () => {
  const fichiers = migrationsDuDepot().filter(name => name.endsWith('_gardes_null_security_definer.sql'));
  assert.deepEqual(fichiers, [MIGRATION]);
  const version = MIGRATION.slice(0, 14);
  assert.ok(version > DERNIERE_VERSION_DISTANTE, `${version} doit suivre la dernière version distante ${DERNIERE_VERSION_DISTANTE}`);
  assert.ok(version > MIGRATION_1124, `${version} doit suivre la migration de #1124 (${MIGRATION_1124})`);
  for (const chemin of FICHIERS_DU_LOT) {
    assert.doesNotMatch(read(chemin), /[0-9a-fA-F]{32,}/, `${chemin} : chaîne hexadécimale ≥ 32 (empreinte en dur)`);
  }
  assert.doesNotMatch(read(LIVE), /^\s*(?:BEGIN|COMMIT|ROLLBACK);\s*$/m);
});

test('migration : une seule différence (la garde) depuis chaque corps LIVE, dump aligné', () => {
  const migration = read(`supabase/migrations/${MIGRATION}`);
  const dump = functions(read('supabase/schema/public.sql'));
  const live = functions(read(LIVE));
  const bodies = functions(migration);
  assert.equal(CORRECTIFS.length, 20);
  assert.deepEqual(bodies.map(f => f.name), CORRECTIFS.map(c => c.name));
  assert.deepEqual(live.map(f => f.name), CORRECTIFS.map(c => c.name));
  CORRECTIFS.forEach((c, i) => {
    const propose = bodies[i];
    const avant = live[i];
    assert.ok(propose.securityDefiner && avant.securityDefiner, `${c.name} : SECURITY DEFINER`);
    // En-tête pg_get_functiondef identique (signature, résultat, langage, sécurité, search_path).
    assert.equal(propose.header, avant.header, `${c.name} : en-tête modifié`);
    assert.equal(avant.body.split(c.garde).length, 2, `${c.name} : garde LIVE unique`);
    assert.equal(avant.body.split(c.correctif).length, 1, `${c.name} : correctif déjà présent dans le LIVE`);
    assert.equal(propose.body.split(c.correctif).length, 2, `${c.name} : garde corrigée unique`);
    assert.equal(propose.body.split(c.garde).length, 1, `${c.name} : garde LIVE encore présente`);
    // Seule la garde diffère du LIVE (comparaison texte à texte, empreintes calculées).
    assert.equal(md5(propose.body.replace(c.correctif, c.garde)), md5(avant.body), `${c.name} : autre différence que la garde`);
    assert.equal(propose.body.replace(c.correctif, c.garde), avant.body);
    const enDump = dump.filter(f => f.schema === 'public' && f.name === c.name);
    assert.equal(enDump.length, 1, `${c.name} : surcharge inattendue dans le dump`);
    assert.equal(enDump[0].body, propose.body, `${c.name} : dump non aligné`);
    // Manifeste du préflight : ordre, signature, garde LIVE et correctif en littéraux SQL.
    assert.ok(migration.includes(`      (${i + 1}, '${c.signature}',\n`), `${c.name} : ligne ${i + 1} du manifeste`);
    assert.ok(migration.includes(`       ${litteralSql(c.garde)},\n       ${litteralSql(c.correctif)})`), `${c.name} : garde et correctif du manifeste`);
  });
  const squelette = migration.replace(/--[^\n]*/g, '').replace(/\$fonction\$[\s\S]*?\$fonction\$/g, () => '$fonction$ $fonction$');
  // Seule table créée : la table temporaire du préflight (ON COMMIT DROP).
  assert.doesNotMatch(squelette.replace(/\) ON COMMIT DROP;/, ');'), /\b(?:GRANT|REVOKE|DROP|ALTER\s+FUNCTION|ALTER\s+TABLE|TRUNCATE|DELETE\s+FROM)\b/i);
  assert.deepEqual([...squelette.matchAll(/INSERT\s+INTO\s+([\w.]+)/gi)].map(m => m[1]), ['_gardes_null_avant']);
  assert.match(squelette, /CREATE TEMP TABLE _gardes_null_avant \([\s\S]*?\) ON COMMIT DROP;/);
  assert.doesNotMatch(migration, /^[ \t]*(?:BEGIN|COMMIT|ROLLBACK);[ \t]*$/m);
  assert.deepEqual([...squelette.matchAll(/UPDATE\s+([\w.]+)/gi)].map(m => m[1]), ['private.security_definer_inventory']);
  assert.ok(squelette.indexOf('$gardes_null_avant$;') < squelette.indexOf('CREATE OR REPLACE FUNCTION'));
  assert.ok(squelette.lastIndexOf('CREATE OR REPLACE FUNCTION') < squelette.indexOf('DO $gardes_null_apres$'));
  assert.equal([...squelette.matchAll(/CREATE OR REPLACE FUNCTION/g)].length, 20);
  // Préflight : garde LIVE exactement une fois, correctif absent, inventaire = md5 calculé du LIVE.
  assert.match(squelette, /pg_catalog\.replace\(p\.prosrc, r\.ancienne_garde, ''\)\)\)\s*\/ pg_catalog\.length\(r\.ancienne_garde\) <> 1/);
  assert.match(squelette, /pg_catalog\.strpos\(p\.prosrc, r\.nouvelle_garde\) > 0/);
  assert.match(squelette, /i\.definition_md5 = pg_catalog\.md5\(p\.prosrc\)\)/);
  assert.match(squelette, /SELECT pg_catalog\.count\(\*\) FROM _gardes_null_avant\) <> 20 THEN/);
  // Postflight : seule la garde diffère, inventaire suivi, rejeu impossible.
  assert.match(squelette, /pg_catalog\.md5\(pg_catalog\.replace\(r\.nouveau_prosrc, r\.nouvelle_garde, r\.ancienne_garde\)\)\s*IS DISTINCT FROM pg_catalog\.md5\(r\.ancien_prosrc\)/);
  assert.match(squelette, /r\.nouvelle_acl IS DISTINCT FROM r\.ancienne_acl/);
  assert.match(squelette, /SET definition_md5 = pg_catalog\.md5\(r\.nouveau_prosrc\)/);
  assert.match(squelette, /AND i\.definition_md5 = pg_catalog\.md5\(r\.ancien_prosrc\);/);
  assert.match(squelette, /IF n <> 20 THEN/);
  assert.doesNotMatch(squelette, /'fn_etat_pointage_mission\(/);
  // Hors périmètre volontaire : fin rétroactive (B9 scanner), état de pointage
  // (B5b), helpers d'identité, volet 2 du helper et fonctions de #1124.
  assert.doesNotMatch(squelette, /FUNCTION\s+public\.(?:fn_declarer_fin_retroactive|fn_etat_pointage_mission|est_admin_etablissement|mon_etablissement_id|dec_proteger_\w+|fn_protect_\w+|fn_mes_dpae|fn_rappel_dpae_quotidien|fn_pointer_arrivee|fn_annuler_candidature_soignant|dec_email_contrat_signe_complet)\(/);
});

test('recette SQL sous ROLLBACK branchée dans validate-pr, documentation et ordre de merge présents', () => {
  const sql = read(SQL_SUITE);
  const workflow = read('.github/workflows/validate-pr.yml');
  assert.ok(workflow.includes(`            ${SQL_SUITE}\n`), 'suite SQL absente de SQL_TESTS');
  assert.ok(workflow.includes('node --test tests/node/gardes-null-security-definer.node.mjs'));
  assert.match(sql, /^BEGIN;$/m);
  assert.match(sql, /ROLLBACK;\s*$/);
  assert.match(sql, /RAISE EXCEPTION USING ERRCODE = 'JGN01'/);
  for (const c of CORRECTIFS) {
    assert.ok(sql.includes(`public.${c.name}(`), `${c.name} absente de la recette SQL`);
    // Contrôle d'installation de la recette : garde corrigée et garde LIVE en littéraux, aucune empreinte.
    assert.ok(sql.includes(`        ('${c.signature}',\n         ${litteralSql(c.garde)},\n         ${litteralSql(c.correctif)})`),
      `${c.name} : contrôle d'installation absent de la recette SQL`);
  }
  assert.match(sql, /AND i\.definition_md5 = pg_catalog\.md5\(p\.prosrc\)/);
  assert.match(sql, /public\.fn_regenerer_qr_mission\(/);
  assert.doesNotMatch(sql, /public\.fn_etat_pointage_mission\(/);
  const doc = read(DOC);
  const migration = read(`supabase/migrations/${MIGRATION}`);
  for (const r of REVUES) assert.ok(doc.includes(r.fonction), `${r.fonction} non instruite dans ${DOC}`);
  for (const [branche, version] of FRERES) {
    assert.ok(doc.includes(branche) && doc.includes(version), `${branche} (${version}) absente de l’ordre de merge de ${DOC}`);
    assert.ok(migration.includes(branche) && migration.includes(version), `${branche} (${version}) absente de l’en-tête de la migration`);
  }
});
