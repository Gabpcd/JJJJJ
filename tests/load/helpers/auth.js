// Helpers k6 — authentification Supabase API directe (pas via edge functions).
//
// On utilise les endpoints `/auth/v1/*` directement parce que :
// - register-soignant edge function a un rate limit 5 req / IP / 10min
//   (anti-abuse), incompatible avec un test 100 VUs from CI runner unique.
// - On veut mesurer la capacité brute de l'auth Supabase, pas l'edge fn wrapper.
//
// Pour les tests d'inscription massive, on utilise donc :
//   POST /auth/v1/signup            → mesure capacité auth Supabase pure
//
// Pour login : POST /auth/v1/token?grant_type=password
//
// Pour les RPCs authentifiés : on récupère le JWT via login puis on l'utilise
// dans Authorization: Bearer.

import http from 'k6/http';
import { check } from 'k6';

export const SUPABASE_URL = __ENV.STAGING_SUPABASE_URL;
export const ANON_KEY = __ENV.STAGING_SUPABASE_ANON_KEY;
export const SERVICE_ROLE_KEY = __ENV.STAGING_SUPABASE_SERVICE_ROLE_KEY || '';

if (!SUPABASE_URL || !ANON_KEY) {
  throw new Error('STAGING_SUPABASE_URL et STAGING_SUPABASE_ANON_KEY requis dans env');
}

/** Headers anon (lectures publiques + auth flows). */
export function anonHeaders() {
  return {
    apikey: ANON_KEY,
    'Content-Type': 'application/json',
  };
}

/** Headers service_role (bypass RLS — uniquement pour seed/cleanup). */
export function serviceRoleHeaders() {
  if (!SERVICE_ROLE_KEY) throw new Error('STAGING_SUPABASE_SERVICE_ROLE_KEY requis');
  return {
    apikey: SERVICE_ROLE_KEY,
    Authorization: `Bearer ${SERVICE_ROLE_KEY}`,
    'Content-Type': 'application/json',
  };
}

/** Headers authentifiés (avec JWT user). */
export function authedHeaders(jwt) {
  return {
    apikey: ANON_KEY,
    Authorization: `Bearer ${jwt}`,
    'Content-Type': 'application/json',
  };
}

/**
 * Login Supabase password grant. Retourne {access_token, user} ou null.
 *
 * IMPORTANT : ne pas mettre de tags dynamiques (email) sinon explosion
 * cardinalité métriques k6. On tag par scénario uniquement.
 */
export function login(email, password) {
  const url = `${SUPABASE_URL}/auth/v1/token?grant_type=password`;
  const res = http.post(
    url,
    JSON.stringify({ email, password }),
    { headers: anonHeaders(), tags: { name: 'auth_login' } },
  );
  const ok = check(res, {
    'login 200': (r) => r.status === 200,
    'login has access_token': (r) => {
      try { return !!r.json('access_token'); } catch { return false; }
    },
  });
  if (!ok) return null;
  return res.json();
}

/**
 * Signup Supabase. Retourne {access_token, user} ou null.
 * 100 VUs simultanés : Supabase peut throttler, on accepte 429 comme info.
 */
export function signup(email, password, metadata = {}) {
  const url = `${SUPABASE_URL}/auth/v1/signup`;
  const res = http.post(
    url,
    JSON.stringify({ email, password, data: metadata }),
    { headers: anonHeaders(), tags: { name: 'auth_signup' } },
  );
  check(res, {
    'signup 200/201/429': (r) => [200, 201, 429].includes(r.status),
  });
  if (res.status === 429) return { rateLimited: true, status: 429 };
  if (res.status >= 400) return null;
  return res.json();
}

/** Récupère le JWT du compte test fixe (réutilisable entre runs). */
export function loginTestAccount(role) {
  const password = __ENV.LOAD_TEST_PASSWORD;
  if (!password) throw new Error('LOAD_TEST_PASSWORD requis dans env');
  const email = role === 'SOIGNANT'
    ? 'playwright-soignant@jolene.app'
    : 'playwright-etab@jolene.app';
  return login(email, password);
}
