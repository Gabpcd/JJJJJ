import { resolve } from 'node:path';
import { pathToFileURL } from 'node:url';
import { literal as q, manifesteD } from './candidatures-fixture-contract.mjs';
import { sqlAvantD, sqlSeedD, sqlEtatD, sqlCompterD } from './candidatures-fixture-sql.mjs';

// Génération seule, aucun client HTTP/SQL. Le futur runner doit imposer la
// destination staging et son verrou global avant d'exécuter ce texte.
function bloc(sql, nom) {
  const debut = `DO $d_${nom}$`, fin = `END $d_${nom}$;`;
  const start = sql.indexOf(debut), end = sql.indexOf(fin, start);
  if (start < 0 || end < 0 || sql.indexOf(debut, start + 1) >= 0) throw new Error('Bloc SQL D inattendu.');
  return sql.slice(start, end + fin.length);
}
export function sqlRecetteRollbackD(runId, jour) {
  if (!/^[A-Za-z0-9][A-Za-z0-9_-]{0,56}$/.test(runId || '')) throw new Error('Suffixe de preuve SQL D explicite requis.');
  const m = manifesteD(`sql-d2-${runId}`, jour);
  const avant = sqlAvantD(m), seed = bloc(sqlSeedD(m), 'seed');
  const check = bloc(sqlEtatD(m), 'check'), clean = bloc(sqlEtatD(m, true), 'check');
  const lot = `ARRAY[${m.membres.map(a => `${q(a.userId)}::uuid`).join(',')}]`;
  const compte = sqlCompterD(m);
  const claimsServeur = `PERFORM set_config('request.jwt.claim.sub','',true);
PERFORM set_config('request.jwt.claim.role','service_role',true);
PERFORM set_config('request.jwt.claims','{"role":"service_role"}',true);`;
  const refuser = (mutation, attendu) => `BEGIN
${mutation}
EXECUTE ${q(clean)};
RAISE EXCEPTION 'D2 négatif accepté';
EXCEPTION WHEN raise_exception THEN IF SQLERRM<>${q(attendu)} THEN RAISE; END IF;
END;`;
  return `-- D2 SQL ROLLBACK : identités sql-d2 distinctes des futurs comptes Auth API.
-- Aucun mot de passe, session Auth, appel navigateur ou preuve HTTP concurrente.
-- À exécuter seulement sur staging sous verrou global après revue du préflight.
${avant.slice(0, avant.indexOf('DO $d_guard$'))}
DO $recette_d2_rollback$
DECLARE r jsonb; s record;
BEGIN
-- La sentinelle annule toutes les écritures même si un wrapper retire ROLLBACK.
BEGIN
EXECUTE ${q(bloc(avant, 'guard'))};
INSERT INTO auth.users(id,instance_id,email,role,aud,raw_app_meta_data,email_confirmed_at)
VALUES ${m.membres.map((a, i) => `(${q(a.userId)}::uuid,'00000000-0000-0000-0000-000000000000',${q(a.email)},'authenticated','authenticated',${q(JSON.stringify({role:a.role,est_compte_test:true,is_test_playwright:true,load_fixture_kind:'CANDIDATURES_D2',load_fixture_run:m.runId,...(i===2?{etablissement_id:a.userId}:{})}))}::jsonb,now())`).join(',\n')};
EXECUTE ${q(seed)};
EXECUTE ${q(check)};
EXECUTE ${q(compte)} INTO s;
IF s.auth<>3 OR s.profils<>2 OR s.etablissements<>1 OR s.missions<>1 OR s.creneaux<>1 OR s.preferences<>3 OR s.notifications<>0 OR jsonb_array_length(s.candidatures)<>0 THEN RAISE EXCEPTION 'D2 seed incomplet'; END IF;
${m.membres.slice(0,2).map(a => `EXECUTE 'SET LOCAL ROLE authenticated';
PERFORM set_config('request.jwt.claim.sub',${q(a.userId)},true);
PERFORM set_config('request.jwt.claim.role','authenticated',true);
PERFORM set_config('request.jwt.claims',${q(JSON.stringify({sub:a.userId,role:'authenticated'}))},true);
r:=public.fn_confirmer_action_planning_v1(${q(m.missionId)}::uuid,'POSTULER',${q(JSON.stringify([{debut:m.debut,fin:m.fin}]))}::jsonb,${q(m.marker)},NULL,NULL);
IF (r->'success'='true'::jsonb AND NOT(r ? 'error') AND r->>'choix_contrat'='SALARIE' AND r->>'profession_requise'='AS' AND r->'docs_a_completer'='true'::jsonb) IS NOT TRUE THEN RAISE EXCEPTION 'D2 candidature refusée/incomplète'; END IF;
IF NOT EXISTS(SELECT 1 FROM public.candidatures WHERE id=(r->>'candidature_id')::uuid AND mission_id=${q(m.missionId)}::uuid AND soignant_id=${q(a.userId)}::uuid AND statut='EN_ATTENTE' AND type_contrat_choisi='SALARIE') THEN RAISE EXCEPTION 'D2 candidature non relue par propriétaire'; END IF;
EXECUTE 'RESET ROLE';
${claimsServeur}`).join('\n')}
EXECUTE 'SET LOCAL ROLE authenticated';
PERFORM set_config('request.jwt.claim.sub',${q(m.membres[2].userId)},true);
PERFORM set_config('request.jwt.claim.role','authenticated',true);
PERFORM set_config('request.jwt.claims',${q(JSON.stringify({sub:m.membres[2].userId,role:'authenticated'}))},true);
IF (SELECT count(DISTINCT soignant_id) FROM public.candidatures WHERE mission_id=${q(m.missionId)}::uuid)<>2 THEN RAISE EXCEPTION 'D2 lecture établissement incomplète'; END IF;
EXECUTE 'RESET ROLE';
${claimsServeur}
EXECUTE ${q(check)};
EXECUTE ${q(compte)} INTO s;
IF s.notifications<>4 OR jsonb_array_length(s.candidatures)<>2 THEN RAISE EXCEPTION 'D2 effets candidature incomplets'; END IF;
-- Le vrai bloc cleanup doit refuser AVANT son premier DELETE. Chaque mutation
-- est annulée par le sous-bloc EXCEPTION, puis le contrôle valide est rejoué.
${refuser(`UPDATE public.notifications SET lien=NULL WHERE destinataire_id=${q(m.membres[0].userId)}::uuid;`, 'Notification D imprévue ou expédiée')}
EXECUTE ${q(check)};
${refuser(`UPDATE auth.users SET raw_app_meta_data=raw_app_meta_data-'role' WHERE id=${q(m.membres[0].userId)}::uuid;`, 'Auth hors lot D')}
EXECUTE ${q(check)};
EXECUTE ${q(clean)};
EXECUTE ${q(clean)}; -- reprise SQL idempotente, audits conservés
DELETE FROM auth.users WHERE id=ANY(${lot});
EXECUTE ${q(check)};
EXECUTE ${q(compte)} INTO s;
IF s.auth<>0 OR s.profils<>0 OR s.etablissements<>0 OR s.missions<>0 OR s.creneaux<>0 OR s.preferences<>0 OR s.notifications<>0 OR s.limites<>0 OR s.sessions<>0 OR s.identites<>0 OR jsonb_array_length(s.candidatures)<>0 OR s.recu_cleanup<>1 OR s.audits_conserves<2 THEN RAISE EXCEPTION 'D2 cleanup incomplet ou audits perdus'; END IF;
BEGIN
EXECUTE ${q(seed)};
RAISE EXCEPTION 'D2 seed tardif accepté';
EXCEPTION WHEN raise_exception THEN IF SQLERRM<>'Run D déjà préparé/nettoyé : seed tardif refusé' THEN RAISE; END IF;
END;
RAISE EXCEPTION USING ERRCODE='JD201',MESSAGE='D2 preuve réussie, fixtures annulées';
EXCEPTION WHEN SQLSTATE 'JD201' THEN NULL;
END;
EXECUTE ${q(compte)} INTO s;
IF s.auth<>0 OR s.profils<>0 OR s.etablissements<>0 OR s.missions<>0 OR s.creneaux<>0 OR s.preferences<>0 OR s.notifications<>0 OR s.limites<>0 OR s.sessions<>0 OR s.identites<>0 OR jsonb_array_length(s.candidatures)<>0 OR s.audits_conserves<>0 OR s.recu_cleanup<>0 THEN RAISE EXCEPTION 'D2 sentinelle rollback incomplète'; END IF;
END $recette_d2_rollback$;
ROLLBACK;
SELECT 'D2_SQL_ROLLBACK' AS preuve, true AS annule;
`;
}
if (process.argv[1] && import.meta.url === pathToFileURL(resolve(process.argv[1])).href) {
  try { process.stdout.write(sqlRecetteRollbackD(process.argv[2], process.argv[3])); }
  catch { console.error('Run suffixe et jour explicites requis pour générer la preuve SQL D2.'); process.exitCode = 1; }
}
