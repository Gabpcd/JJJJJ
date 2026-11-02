import { createHash } from 'node:crypto';
import { readFileSync, readdirSync } from 'node:fs';
import { describe, expect, it } from 'vitest';

// Lot 4 B1 (B9) : fn_obtenir_missions_swipe renvoie `score = null` quand aucune
// ligne matching_scores n'existe, au lieu d'un « 0/100 » fabriqué.
// Relevés LIVE production en lecture seule (02/11/2026) :
//   md5(pg_get_functiondef(oid)) et md5(prosrc) de public.fn_obtenir_missions_swipe(integer).
const LIVE_FUNCTIONDEF_MD5 = '1d4708a06d88a43c10331d1a51e61edb';
const LIVE_PROSRC_MD5 = '8b9597449427a7fa639715b22c76a6a6';
const LIVE_ACL = '{postgres=X/postgres,authenticated=X/postgres,service_role=X/postgres}';
const NOUVEAU_PROSRC_MD5 = '014d6b764e55730da0a614e919d64c10';
const NOUVEAU_FUNCTIONDEF_MD5 = 'e1031b572d1bb8f397afd124783e192a';
const LIGNE_LIVE = "          'score', COALESCE(ms.score_global, 0),\n";
const LIGNE_NOUVELLE = "          'score', ms.score_global,\n";
const EN_TETE = "CREATE OR REPLACE FUNCTION public.fn_obtenir_missions_swipe(p_limit integer DEFAULT 20)\n"
  + ' RETURNS jsonb\n LANGUAGE plpgsql\n SECURITY DEFINER\n SET search_path TO \'public\'\nAS $function$';

const read = (path: string) => readFileSync(path, 'utf8');
const md5 = (texte: string) => createHash('md5').update(texte).digest('hex');
// Forme exacte de pg_get_functiondef pour cette fonction (vérifiée contre le md5 LIVE).
const functiondef = (corps: string) => `${EN_TETE}${corps}$function$\n`;

const fichiers = readdirSync('supabase/migrations').filter(nom => nom.endsWith('_score_matching_inconnu_null.sql'));
const migration = fichiers.length === 1 ? read(`supabase/migrations/${fichiers[0]}`) : '';
const sansCommentaires = migration.replace(/--[^\n]*/g, '');

function corpsMigration(sql: string): string {
  const debut = sql.indexOf(EN_TETE);
  expect(debut, 'CREATE OR REPLACE de fn_obtenir_missions_swipe absent').toBeGreaterThanOrEqual(0);
  const ouverture = debut + EN_TETE.length;
  const fin = sql.indexOf('$function$;', ouverture);
  expect(fin).toBeGreaterThan(ouverture);
  return sql.slice(ouverture, fin);
}

function corpsSchema(sql: string): string {
  const debut = sql.indexOf('CREATE OR REPLACE FUNCTION "public"."fn_obtenir_missions_swipe"(');
  expect(debut).toBeGreaterThanOrEqual(0);
  const ouverture = sql.indexOf('AS $$', debut) + 'AS $$'.length;
  return sql.slice(ouverture, sql.indexOf('$$;', ouverture));
}

describe('B1 — score de matching inconnu = NULL (fn_obtenir_missions_swipe)', () => {
  it('une seule migration, horodatée après B0 (20261102150000), sans BEGIN/COMMIT', () => {
    expect(fichiers).toHaveLength(1);
    const version = fichiers[0].slice(0, 14);
    expect(fichiers[0]).toMatch(/^\d{14}_score_matching_inconnu_null\.sql$/);
    expect(Number(version)).toBeGreaterThan(20261102150000);
    expect(migration).not.toMatch(/^\s*(BEGIN|COMMIT|ROLLBACK)\s*;/im);
  });

  it('le nouveau corps est la définition LIVE à une seule ligne près', () => {
    const corps = corpsMigration(migration);
    expect(corps.split(LIGNE_NOUVELLE)).toHaveLength(2);
    expect(corps).not.toContain(LIGNE_LIVE);
    const live = corps.replace(LIGNE_NOUVELLE, LIGNE_LIVE);
    expect(md5(live)).toBe(LIVE_PROSRC_MD5);
    expect(md5(functiondef(live))).toBe(LIVE_FUNCTIONDEF_MD5);
    expect(md5(corps)).toBe(NOUVEAU_PROSRC_MD5);
    expect(md5(functiondef(corps))).toBe(NOUVEAU_FUNCTIONDEF_MD5);
  });

  it('seul le champ score change : tri, ordre et breakdown gardent leur repli', () => {
    const corps = corpsMigration(migration);
    expect(corps.split('COALESCE(ms.score_global, 0)')).toHaveLength(3);
    expect(corps).toContain('SELECT (COALESCE(ms.score_global, 0) + floor(random() * 13))::int AS tri,');
    expect(corps).toContain('ORDER BY COALESCE(ms.score_global, 0) DESC, m.est_urgente DESC, m.cree_le DESC');
    expect(corps).toContain("'breakdown', COALESCE(ms.breakdown, '{}'::jsonb),");
    expect(corps).toContain('LEFT JOIN public.matching_scores ms ON ms.mission_id = m.id AND ms.soignant_id = v_uid');
  });

  it('préconditions LIVE avant le CREATE, postconditions après, échec explicite sinon', () => {
    const create = migration.indexOf(EN_TETE);
    const avant = migration.slice(0, create);
    const apres = migration.slice(create);
    for (const attendu of [LIVE_FUNCTIONDEF_MD5, LIVE_PROSRC_MD5, LIVE_ACL, 'RPC_UTILISATEUR_AUTH_INTERNE']) {
      expect(avant).toContain(`'${attendu}'`);
    }
    expect(avant).toMatch(/RAISE EXCEPTION 'SCORE_MATCHING_SOURCE_DIVERGENTE/);
    for (const attendu of [NOUVEAU_FUNCTIONDEF_MD5, NOUVEAU_PROSRC_MD5, LIVE_ACL]) {
      expect(apres).toContain(`'${attendu}'`);
    }
    expect(apres).toMatch(/RAISE EXCEPTION 'SCORE_MATCHING_REDEFINITION_INCOMPLETE/);
  });

  it('aucun GRANT, REVOKE, DROP, ALTER ni écriture hors inventaire SECURITY DEFINER', () => {
    expect(sansCommentaires).not.toMatch(/\b(GRANT|REVOKE|DROP|ALTER|TRUNCATE|DELETE|INSERT)\b/i);
    expect([...sansCommentaires.matchAll(/\bUPDATE\s+([\w.]+)/gi)].map(m => m[1]))
      .toEqual(['private.security_definer_inventory']);
    expect(sansCommentaires).toMatch(/SET definition_md5 = pg_catalog\.md5\(p\.prosrc\)/);
    expect(sansCommentaires).toContain("i.signature = 'fn_obtenir_missions_swipe(integer)'");
    const etiquettes = [...sansCommentaires.matchAll(/\$([a-z_]*)\$/g)].map(m => m[1]);
    expect(new Set(etiquettes)).toEqual(new Set(['avant_score_matching', 'function', 'apres_score_matching']));
  });

  it('le dump de référence supabase/schema/public.sql suit la nouvelle définition', () => {
    expect(md5(corpsSchema(read('supabase/schema/public.sql')))).toBe(NOUVEAU_PROSRC_MD5);
  });

  it('une régression SQL exécutée en CI prouve score réel, zéro réel et score inconnu', () => {
    const suite = 'tests/lot21/d4-cascade-profession-mission.test.sql';
    expect(read('.github/workflows/validate-pr.yml')).toContain(suite);
    const sql = read(suite);
    for (const cas of ['D4-T21B', 'D4-T21C', 'D4-T21D']) expect(sql).toContain(`'${cas}:`);
    expect(sql).toContain("jsonb_typeof(v_result->'missions'->0->'score') IS DISTINCT FROM 'null'");
    expect(sql.trim()).toMatch(/ROLLBACK;$/);
  });
});
