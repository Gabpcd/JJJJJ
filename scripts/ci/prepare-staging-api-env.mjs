import { appendFileSync } from 'node:fs';

// Une seule destination autorisée : aucune charge ni fixture sur production.
const ref = process.env.STAGING_SUPABASE_PROJECT_REF;
if (ref !== 'mejpriaetwgtcstbgfid') throw new Error('Staging Jolene attendu ; aucun repli production.');
const token = process.env.STAGING_SUPABASE_ACCESS_TOKEN;
if (!token || !process.env.GITHUB_ENV) throw new Error('Accès staging ou fichier environnement CI absent.');
const response = await fetch(`https://api.supabase.com/v1/projects/${ref}/api-keys`, {
  headers: { Authorization: `Bearer ${token}` }, signal: AbortSignal.timeout(30_000),
});
if (!response.ok) throw new Error(`Lecture des accès staging impossible (HTTP ${response.status}).`);
const keys = await response.json();
const anon = keys.find(k => k.name === 'anon')?.api_key;
const service = keys.find(k => k.name === 'service_role')?.api_key;
if (!anon || !service) throw new Error('Clés staging attendues absentes.');
const vars = {
  STAGING_SUPABASE_URL: `https://${ref}.supabase.co`,
  STAGING_SUPABASE_ANON_KEY: anon,
  STAGING_SUPABASE_SERVICE_ROLE_KEY: service,
};
for (const [name, value] of Object.entries(vars)) {
  if (/[\r\n]/.test(value)) throw new Error('Valeur environnement invalide.');
  if (name !== 'STAGING_SUPABASE_URL') console.log(`::add-mask::${value}`);
  appendFileSync(process.env.GITHUB_ENV, `${name}=${value}\n`);
}
console.log('Accès staging résolus ; production exclue.');
