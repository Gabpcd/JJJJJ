import { createHash } from 'node:crypto';
import { chmodSync, existsSync, mkdirSync, readFileSync, writeFileSync } from 'node:fs';
import { dirname, resolve } from 'node:path';
import { pathToFileURL } from 'node:url';
import { loadEnv } from 'vite';

export const EXPECTED_ANDROID_PACKAGE = 'app.jolene';
export const EXPECTED_FIREBASE_PROJECT_ID = 'jolene-app-d91fd';
export const EXPECTED_SUPABASE_PROJECT_REF = 'flripxtsyegjshnhzjkz';
export const EXPECTED_SUPABASE_URL = `https://${EXPECTED_SUPABASE_PROJECT_REF}.supabase.co`;
// Empreinte de la clé sb_publishable publique de production. Elle lie une clé
// moderne, qui ne contient pas le project ref, au bon projet sans la recopier
// dans les erreurs ni dans les logs du préflight.
export const EXPECTED_SUPABASE_PUBLISHABLE_KEY_SHA256 = '97309ec66438497eb5ee1a369a55133f1d0bd449c0ea052787883b5c86c416cc';

const PUBLIC_MOBILE_ENV_NAMES = [
  'VITE_STRIPE_PUBLISHABLE_KEY',
  'VITE_SUPABASE_URL',
  'VITE_SUPABASE_PUBLISHABLE_KEY',
  'VITE_SENTRY_DSN',
];

function fail(message) {
  throw new Error(`Préflight mobile refusé — ${message}`);
}

function requiredValue(env, name) {
  const value = env[name]?.trim();
  if (!value) fail(`${name} manquante.`);
  return value;
}

function parseJsonWithoutLeaking(raw, label) {
  try {
    return JSON.parse(raw);
  } catch {
    fail(`${label} n'est pas un JSON valide.`);
  }
}

function decodeJwtPayloadWithoutLeaking(token) {
  try {
    const parts = token.split('.');
    if (parts.length !== 3) return null;
    return JSON.parse(Buffer.from(parts[1], 'base64url').toString('utf8'));
  } catch {
    return null;
  }
}

function normalizedUrlWithoutTrailingSlash(value) {
  try {
    const url = new URL(value);
    if (url.username || url.password || url.search || url.hash) return null;
    return `${url.protocol}//${url.host}${url.pathname.replace(/\/+$/, '')}`;
  } catch {
    return null;
  }
}

export function decodeGoogleServices(env) {
  const encoded = env.GOOGLE_SERVICES_JSON_BASE64?.trim();
  const plain = env.GOOGLE_SERVICES_JSON?.trim();

  if (encoded && plain) {
    fail('GOOGLE_SERVICES_JSON_BASE64 et GOOGLE_SERVICES_JSON sont définies simultanément. Garder une seule source.');
  }

  if (encoded) {
    try {
      return Buffer.from(encoded, 'base64').toString('utf8');
    } catch {
      fail('GOOGLE_SERVICES_JSON_BASE64 est illisible.');
    }
  }

  return plain || null;
}

export function validateGoogleServices(document) {
  if (!document || typeof document !== 'object' || Array.isArray(document)) {
    fail('google-services.json a une structure invalide.');
  }

  if (document.project_info?.project_id !== EXPECTED_FIREBASE_PROJECT_ID) {
    fail('google-services.json ne cible pas le projet Firebase de production Jolene.');
  }

  const matchingClient = Array.isArray(document.client)
    ? document.client.find(
        (client) => client?.client_info?.android_client_info?.package_name === EXPECTED_ANDROID_PACKAGE,
      )
    : null;

  if (!matchingClient) {
    fail(`google-services.json ne contient pas l'application Android ${EXPECTED_ANDROID_PACKAGE}.`);
  }

  const mobileSdkAppId = matchingClient.client_info?.mobilesdk_app_id;
  if (typeof mobileSdkAppId !== 'string' || !/^1:\d+:android:[a-f0-9]+$/i.test(mobileSdkAppId)) {
    fail('google-services.json ne contient pas un identifiant Firebase Android valide.');
  }

  const hasApiKey = Array.isArray(matchingClient.api_key)
    && matchingClient.api_key.some((entry) => typeof entry?.current_key === 'string' && entry.current_key.trim());
  if (!hasApiKey) {
    fail('google-services.json ne contient pas la clé API publique de l’application Android.');
  }

  if (typeof document.project_info?.project_number !== 'string' || !/^\d+$/.test(document.project_info.project_number)) {
    fail('google-services.json ne contient pas un numéro de projet Firebase valide.');
  }

  return true;
}

export function validateStripeConfiguration(env) {
  const key = requiredValue(env, 'VITE_STRIPE_PUBLISHABLE_KEY');
  const profile = env.MOBILE_BUILD_PROFILE || 'store';
  const developmentOverride = profile === 'development' && env.ALLOW_NON_LIVE_STRIPE_KEY === '1';

  if (!['store', 'development'].includes(profile)) {
    fail('MOBILE_BUILD_PROFILE doit valoir store ou development.');
  }

  if (/^pk_live_[A-Za-z0-9]{16,}$/.test(key)) return true;

  if (developmentOverride && /^pk_test_[A-Za-z0-9]{16,}$/.test(key)) return true;

  if (profile === 'development') {
    fail('VITE_STRIPE_PUBLISHABLE_KEY doit être une clé publiable live, ou une clé test avec ALLOW_NON_LIVE_STRIPE_KEY=1.');
  }

  fail('VITE_STRIPE_PUBLISHABLE_KEY doit être une clé publiable Stripe live pour un build store.');
}

export function validateSupabaseConfiguration(env, runtimeClientSource) {
  const rawUrl = requiredValue(env, 'VITE_SUPABASE_URL');
  const key = requiredValue(env, 'VITE_SUPABASE_PUBLISHABLE_KEY');
  const normalizedUrl = normalizedUrlWithoutTrailingSlash(rawUrl);

  if (normalizedUrl !== EXPECTED_SUPABASE_URL) {
    fail('VITE_SUPABASE_URL ne cible pas le projet Supabase de production Jolene.');
  }

  if (key.startsWith('sb_secret_') || key.includes('service_role')) {
    fail('VITE_SUPABASE_PUBLISHABLE_KEY contient une clé serveur interdite dans une application mobile.');
  }

  if (key.startsWith('sb_publishable_')) {
    if (!/^sb_publishable_[A-Za-z0-9_-]{16,}$/.test(key)) {
      fail('VITE_SUPABASE_PUBLISHABLE_KEY a un format invalide.');
    }
    const fingerprint = createHash('sha256').update(key, 'utf8').digest('hex');
    if (fingerprint !== EXPECTED_SUPABASE_PUBLISHABLE_KEY_SHA256) {
      fail('VITE_SUPABASE_PUBLISHABLE_KEY ne correspond pas à la clé publique du projet de production.');
    }
  } else {
    const payload = decodeJwtPayloadWithoutLeaking(key);
    if (!payload || payload.iss !== 'supabase' || payload.role !== 'anon'
      || payload.ref !== EXPECTED_SUPABASE_PROJECT_REF) {
      fail('VITE_SUPABASE_PUBLISHABLE_KEY ne correspond pas à la clé publique anon du projet de production.');
    }
    if (typeof payload.exp === 'number' && payload.exp * 1000 <= Date.now()) {
      fail('VITE_SUPABASE_PUBLISHABLE_KEY est expirée.');
    }
  }

  if (typeof runtimeClientSource !== 'string') {
    fail('le client Supabase embarqué est introuvable.');
  }

  const runtimeUsesEnvironment = runtimeClientSource.includes('import.meta.env.VITE_SUPABASE_URL')
    && runtimeClientSource.includes('import.meta.env.VITE_SUPABASE_PUBLISHABLE_KEY');

  if (!runtimeUsesEnvironment) {
    const runtimeUrl = runtimeClientSource.match(/const\s+SUPABASE_URL\s*=\s*["']([^"']+)["']/)?.[1];
    const runtimeKey = runtimeClientSource.match(/const\s+SUPABASE_PUBLISHABLE_KEY\s*=\s*["']([^"']+)["']/)?.[1];
    if (normalizedUrlWithoutTrailingSlash(runtimeUrl || '') !== EXPECTED_SUPABASE_URL || runtimeKey !== key) {
      fail('la configuration Supabase embarquée ne correspond pas aux variables publiques validées.');
    }
  }

  return true;
}

export function validateSentryConfiguration(env) {
  const dsn = requiredValue(env, 'VITE_SENTRY_DSN');

  try {
    const url = new URL(dsn);
    const valid = url.protocol === 'https:'
      && Boolean(url.username)
      && !url.password
      && /(^|\.)ingest(?:\.[a-z0-9-]+)?\.sentry\.io$/i.test(url.hostname)
      && /^\/\d+\/?$/.test(url.pathname);
    if (!valid) fail('VITE_SENTRY_DSN n’est pas un DSN public Sentry de production valide.');
  } catch {
    fail('VITE_SENTRY_DSN n’est pas un DSN public Sentry de production valide.');
  }

  return true;
}

export function validatePublicMobileConfiguration(env, runtimeClientSource) {
  for (const name of PUBLIC_MOBILE_ENV_NAMES) requiredValue(env, name);
  if (env.VITE_ENV && env.VITE_ENV !== 'production' && env.MOBILE_BUILD_PROFILE === 'store') {
    fail('VITE_ENV doit valoir production pour un build store.');
  }

  validateStripeConfiguration(env);
  validateSupabaseConfiguration(env, runtimeClientSource);
  validateSentryConfiguration(env);
  return true;
}

export function prepareMobileSecrets({ env, rootDirectory = process.cwd() }) {
  const googleServicesPath = resolve(rootDirectory, 'android/app/google-services.json');
  const supabaseClientPath = resolve(rootDirectory, 'src/integrations/supabase/client.ts');
  const publicSupabaseClientPath = resolve(rootDirectory, 'src/integrations/supabase/public-client.ts');
  const requireMobileSecrets = env.REQUIRE_MOBILE_SECRETS === '1';
  const googleServices = decodeGoogleServices(env);

  if (googleServices) {
    const parsed = parseJsonWithoutLeaking(googleServices, 'la configuration Firebase fournie');
    validateGoogleServices(parsed);
    mkdirSync(dirname(googleServicesPath), { recursive: true });
    writeFileSync(googleServicesPath, `${googleServices.trim()}\n`, { mode: 0o600 });
    chmodSync(googleServicesPath, 0o600);
    console.log('Configuration Firebase Android générée et validée.');
  } else if (!existsSync(googleServicesPath)) {
    const message = 'android/app/google-services.json manque ; fournir GOOGLE_SERVICES_JSON ou GOOGLE_SERVICES_JSON_BASE64.';
    if (requireMobileSecrets) fail(message);
    console.warn(message);
  }

  if (existsSync(googleServicesPath)) {
    const parsed = parseJsonWithoutLeaking(
      readFileSync(googleServicesPath, 'utf8'),
      'android/app/google-services.json',
    );
    validateGoogleServices(parsed);
  }

  if (requireMobileSecrets) {
    if (!existsSync(supabaseClientPath)) fail('le client Supabase embarqué est introuvable.');
    const runtimeClientSource = readFileSync(supabaseClientPath, 'utf8');
    validatePublicMobileConfiguration(env, runtimeClientSource);
    if (existsSync(publicSupabaseClientPath)) {
      validateSupabaseConfiguration(env, readFileSync(publicSupabaseClientPath, 'utf8'));
    }
    console.log('Préflight mobile validé : Firebase, Supabase, Stripe et Sentry sont configurés pour la production.');
  }
}

export function loadMobileEnvironment(processEnvironment = process.env, rootDirectory = process.cwd()) {
  const profile = processEnvironment.MOBILE_BUILD_PROFILE || 'store';
  const mode = profile === 'development' ? 'development' : 'production';
  const fileEnvironment = loadEnv(mode, rootDirectory, '');
  return { ...fileEnvironment, ...processEnvironment, MOBILE_BUILD_PROFILE: profile };
}

const isMainModule = process.argv[1]
  && pathToFileURL(resolve(process.argv[1])).href === import.meta.url;

if (isMainModule) {
  const rootDirectory = process.cwd();
  prepareMobileSecrets({
    env: loadMobileEnvironment(process.env, rootDirectory),
    rootDirectory,
  });
}
