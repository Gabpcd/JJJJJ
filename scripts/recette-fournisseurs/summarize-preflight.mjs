// Closed display projection only; never an authorization or readiness gate.
import { constants, openSync, closeSync, fstatSync, readSync, realpathSync } from 'node:fs';
import { resolve } from 'node:path';
import { fileURLToPath } from 'node:url';

const groups = Object.freeze({ migrations: 'Migrations', edgeFunctions: 'Fonctions Edge',
  sqlFunctions: 'Fonctions SQL', edgeSecretNames: 'Noms de secrets Edge', vaultNames: 'Noms Vault',
  crons: 'Crons', queues: 'Files financières', stripeSandbox: 'Compte Stripe TEST', stripeWebhooks: 'Webhooks TEST' });
const issues = Object.freeze({ OBSERVATION_TIME_INVALID: 'Date d’observation invalide.', SOURCE_INVALID: 'Référence source invalide.',
  STAGING_TOKEN_ABSENT: 'Accès staging indisponible.', STRIPE_TEST_KEY_ABSENT_OR_INVALID: 'Accès Stripe TEST indisponible.',
  MIGRATIONS_MISMATCH: 'Migrations différentes de la référence candidate.', EDGE_FUNCTION_MISSING_OR_INACTIVE: 'Fonction Edge absente ou inactive.',
  ACTIVE_CRONS_PRESENT: 'Crons actifs présents.', STRIPE_TEST_ACCOUNT_RESTRICTED: 'Compte Stripe TEST restreint.',
  STRIPE_TEST_CAPABILITIES_UNKNOWN: 'Capacités du compte Stripe TEST inconnues.', STAGING_WEBHOOK_ROUTE_MISSING: 'Route webhook staging absente.',
  COLLECTION_SOURCE_OR_RUNTIME_INVALID: 'Collecte impossible : source ou exécution non confirmée.',
  ...Object.fromEntries(Object.entries(groups).map(([key,label]) => [`${key.toUpperCase()}_UNAVAILABLE_OR_INVALID`, `${label} : lecture indisponible ou réponse invalide.`])),
});
const limitations = Object.freeze({
  DEPLOYED_EDGE_CONTENT_NOT_COMPARED: 'Contenu Edge déployé non comparé à la candidate.',
  SQL_DIGESTS_NOT_COMPARED_TO_CANDIDATE: 'Définitions SQL non comparées à la candidate.',
  COHORT_GUARDS_NOT_ATTESTED: 'Gardes des cohortes non attestés.',
  VAULT_VALUE_ROUTING_NOT_READ: 'Routage des valeurs Vault non vérifié.',
  SMS_DELIVERY_NOT_PROVEN: 'Réception réelle de SMS non prouvée.',
  EDGE_STRIPE_ACCOUNT_NOT_VERIFIED: 'Compte Stripe utilisé par les Edge non vérifié.',
  CONNECT_WEBHOOK_SCOPE_NOT_PROVEN: 'Portée Connect des webhooks non prouvée.',
  FOREIGN_QUEUE_OWNERSHIP_NOT_CLASSIFIED: 'Propriété des files étrangères non classée.',
  SNAPSHOT_NOT_TRANSACTIONAL: 'Lectures sans snapshot transactionnel.',
});
const object = value => value !== null && typeof value === 'object' && !Array.isArray(value);
const knownList = (value, allowed) => Array.isArray(value) && value.length <= 64 && value.every(code => typeof code === 'string' && Object.hasOwn(allowed,code));
const refusal = '**Qualification : NON PRÊT.** Aucun transport ni circuit intégré validé. Le collecteur conserve son code de sortie 2.';

export function summarizePreflight(report) {
  const lines = ['## Inventaire fournisseurs', '', refusal, ''];
  if (!object(report) || report.status !== 'NON_PRET' || report.readyForTransports !== false
    || report.integratedFlowReady !== false || !knownList(report.issues,issues)) {
    return lines.concat('Collecte non confirmée : rapport absent, invalide ou diagnostic non reconnu.', '').join('\n');
  }
  const normal = report.version === 1 && report.readOnly === true && report.providerMutations === 0
    && object(report.checks) && Object.keys(report.checks).every(key => Object.hasOwn(groups,key))
    && Object.values(report.checks).every(check => object(check) && ['OBSERVED','UNKNOWN'].includes(check.status))
    && knownList(report.unknowns,limitations) && new Set(report.unknowns).size === Object.keys(limitations).length;
  const checks = normal ? report.checks : {};
  const observed = Object.keys(groups).filter(name => checks[name]?.status === 'OBSERVED').length;
  const complete = normal && observed === Object.keys(groups).length;
  lines.push(`**Collecte : ${complete ? 'complète' : 'incomplète ou non confirmée'} (${observed}/9 groupes déclarés observés).**`,
    'Une lecture aboutie peut constater une anomalie. Ce compteur ne valide ni les réglages ni les transports.', '',
    '| Groupe | Lecture |', '| --- | --- |');
  for (const [name,label] of Object.entries(groups)) {
    const state = checks[name]?.status;
    lines.push(`| ${label} | ${state === 'OBSERVED' ? 'Observée' : state === 'UNKNOWN' ? 'Inconnue ou invalide' : 'Non collectée'} |`);
  }
  const platform = checks.edgeSecretNames?.status === 'OBSERVED'
    ? checks.edgeSecretNames.present?.STRIPE_PLATFORM_WEBHOOK_SECRET : undefined;
  lines.push('', `Nom explicite de signature plateforme : **${platform === true ? 'présent' : platform === false ? 'absent' : 'non observé'}**. L’alias historique reste inventorié séparément ; les valeurs et le raccordement ne sont pas vérifiés.`, '', 'Constats de collecte :');
  if (report.issues.length) for (const code of [...new Set(report.issues)]) lines.push(`- ${issues[code]}`);
  else lines.push('- Aucun constat additionnel déclaré ; les limites suivantes restent bloquantes.');
  lines.push('', 'Limites permanentes de cet inventaire :');
  for (const text of Object.values(limitations)) lines.push(`- ${text}`);
  lines.push('');
  return lines.join('\n');
}

export function readPreflightReport(path = 'recette-fournisseurs-preflight.json') {
  const fd = openSync(path, constants.O_RDONLY | constants.O_NOFOLLOW);
  try {
    const stat = fstatSync(fd), limit = 1024 * 1024;
    if (!stat.isFile() || stat.size <= 0 || stat.size > limit) throw new Error('INVALID_REPORT');
    const buffer = Buffer.alloc(limit + 1);
    let size = 0, read;
    while (size < buffer.length && (read = readSync(fd, buffer, size, buffer.length-size, null)) > 0) size += read;
    if (size > limit) throw new Error('INVALID_REPORT');
    return JSON.parse(new TextDecoder('utf-8', { fatal: true }).decode(buffer.subarray(0,size)));
  } finally { closeSync(fd); }
}

if (process.argv[1] && realpathSync(resolve(process.argv[1])) === realpathSync(fileURLToPath(import.meta.url))) {
  try { process.stdout.write(summarizePreflight(readPreflightReport())); }
  catch {
    process.stdout.write(`## Inventaire fournisseurs\n\n${refusal}\n\nCollecte non confirmée : rapport absent ou illisible.\n`);
    process.exitCode = 1;
  }
}
