#!/usr/bin/env node
import { createHash } from 'node:crypto';
import { execFileSync } from 'node:child_process';
import { existsSync, readFileSync } from 'node:fs';
import { resolve } from 'node:path';
import { pathToFileURL } from 'node:url';

export const sources = [
  ['20260808150856_aligner_mandat_facturation_tva_et_periodes.sql', '9aa8f417caece8047f3699e73028b461f5e62778968ab9746bcf150f99f66b62'],
  ['20260903203000_resoudre_litiges_paie_salariee.sql', '26a4cc9150a3b9351ff1b091cf70affd75f0163d957e9c7b6c922a167fc3ece6'],
];
const signature = 'public.fn_admin_resoudre_litige_intelligent(uuid,text,text,numeric,numeric,text)';
const canonicalMd5 = '1d1a6d0593e1899ff2c58c48a38f3a4d';
const duplicatedMd5 = '8cc14fc83a8e1adc73ebcda417074d84';
const guardedMd5 = '5a13493bf67426d968d0d75aad16b86c';
const guardVersion = '20260930091209';
const hash = (value, algorithm = 'md5') => createHash(algorithm).update(value).digest('hex');

// Produit du SQL seulement, jamais de connexion. Le workflow l'envoie uniquement
// au projet staging sous son verrou d'écriture, AVANT la transaction des PR.
export function reconciliationSql({ projectRef, sourceTexts, registry }) {
  if (projectRef !== 'mejpriaetwgtcstbgfid') throw new Error('Réconciliation réservée au staging Jolene.');
  if (!Array.isArray(registry) || registry.some(row => typeof row?.version !== 'string')) throw new Error('Registre staging invalide.');
  if (!Array.isArray(sourceTexts) || sourceTexts.length !== 2) throw new Error('Deux sources main requises.');
  // Les petits dépôts de tests et les bases antérieures à cette fonctionnalité
  // n'ont pas ce routeur. Une absence partielle reste une erreur explicite.
  if (sourceTexts.every(value => value === null)) return "SELECT 'Réconciliation litige sans objet pour cette base' AS diagnostic;\n";
  for (let i = 0; i < sources.length; i++) {
    if (typeof sourceTexts[i] !== 'string' || hash(sourceTexts[i], 'sha256') !== sources[i][1]) throw new Error('Source main litige absente ou empreinte inattendue.');
  }
  // Un staging encore vierge doit d'abord recevoir ses migrations main via la
  // CLI. La réconciliation ne se substitue jamais à une migration manquante.
  if (sources.some(([name]) => !registry.some(row => row.version === name.slice(0,14)))) {
    if (registry.some(row => row.version === guardVersion)) throw new Error('Historique litige incomplet malgré la garde appliquée.');
    return "SELECT 'Réconciliation litige différée : migrations main encore manquantes' AS diagnostic;\n";
  }
  const start = sourceTexts[0].indexOf('CREATE OR REPLACE FUNCTION public.fn_admin_resoudre_litige_intelligent(');
  const tail = sourceTexts[0].slice(start);
  const end = tail.indexOf('$body$;', tail.indexOf('AS $body$') + 10);
  if (start < 0 || end < 0) throw new Error('Définition main litige introuvable.');
  const initial = tail.slice(0, end + '$body$;'.length);
  const marker = sourceTexts[1].split('$marker$')[1];
  const injection = sourceTexts[1].split('$injection$')[1];
  const canonical = initial.replace(marker, injection);
  const body = canonical.split('AS $body$')[1].split('$body$')[0];
  if (hash(body) !== canonicalMd5
      || hash(body.replace(marker, injection).replace(marker, injection)) !== duplicatedMd5) {
    throw new Error('Rapprochement déterministe litige invalide.');
  }
  const guardApplied = registry.some(row => row.version === guardVersion);
  const expected = guardApplied ? guardedMd5 : canonicalMd5;
  return `-- Correction persistante de la BASE STAGING, distincte des migrations PR.
-- Exactement deux injections historiques supplémentaires ; aucun autre corps accepté.
DO $reconcile_staging$
DECLARE
  p record;
  apres record;
BEGIN
  SELECT * INTO p FROM pg_proc WHERE oid = '${signature}'::regprocedure;
  IF NOT FOUND OR p.prosecdef IS DISTINCT FROM true
    OR pg_get_userbyid(p.proowner) IS DISTINCT FROM 'postgres'
    OR p.proconfig IS DISTINCT FROM ARRAY['search_path=public, extensions']::text[]
    OR has_function_privilege('anon',p.oid,'EXECUTE') IS DISTINCT FROM false
    OR has_function_privilege('authenticated',p.oid,'EXECUTE') IS DISTINCT FROM true
    OR has_function_privilege('service_role',p.oid,'EXECUTE') IS DISTINCT FROM true
    OR EXISTS (SELECT 1 FROM aclexplode(coalesce(p.proacl,acldefault('f',p.proowner))) a
               WHERE a.grantee=0 AND a.privilege_type='EXECUTE') THEN
    RAISE EXCEPTION 'Droits staging litige inattendus : aucune réconciliation';
  END IF;
  IF md5(p.prosrc) = '${expected}' THEN RETURN; END IF;
  IF ${guardApplied ? 'true' : 'false'} OR md5(p.prosrc) IS DISTINCT FROM '${duplicatedMd5}' THEN
    RAISE EXCEPTION 'Corps staging litige inexpliqué : aucune réconciliation';
  END IF;
  EXECUTE $canonical_definition$${canonical}$canonical_definition$;
  SELECT * INTO apres FROM pg_proc WHERE oid=p.oid;
  IF md5(apres.prosrc) IS DISTINCT FROM '${canonicalMd5}'
    OR ROW(apres.proacl,apres.proowner,apres.proconfig,apres.prosecdef)
       IS DISTINCT FROM ROW(p.proacl,p.proowner,p.proconfig,p.prosecdef) THEN
    RAISE EXCEPTION 'Réconciliation staging litige non conforme';
  END IF;
  RAISE NOTICE 'Base staging litige normalisée depuis les migrations main, sans changer les ACL';
END;
$reconcile_staging$;
`;
}

if (process.argv[1] && import.meta.url === pathToFileURL(resolve(process.argv[1])).href) {
  try {
    const [baseDir, registryPath] = process.argv.slice(2);
    if (!baseDir || !registryPath || !/^[a-f0-9]{40}$/.test(process.env.BASE_SHA ?? '')) throw new Error('Base main exacte et registre requis.');
    if (execFileSync('git', ['-C', baseDir, 'rev-parse', 'HEAD'], { encoding: 'utf8' }).trim() !== process.env.BASE_SHA) throw new Error('Worktree hors base main.');
    if (execFileSync('git', ['-C', baseDir, 'status', '--porcelain', '--', 'supabase/migrations'], { encoding: 'utf8' }).trim()) throw new Error('Sources main modifiées.');
    const sourceTexts = sources.map(([name]) => {
      const path = resolve(baseDir, 'supabase/migrations', name);
      return existsSync(path) ? readFileSync(path, 'utf8') : null;
    });
    process.stdout.write(reconciliationSql({ projectRef: process.env.STAGING_SUPABASE_PROJECT_REF,
      sourceTexts, registry: JSON.parse(readFileSync(registryPath, 'utf8')) }));
  } catch (error) {
    console.error(`::error::${error instanceof Error ? error.message : 'Réconciliation staging refusée.'}`);
    process.exitCode = 1;
  }
}
