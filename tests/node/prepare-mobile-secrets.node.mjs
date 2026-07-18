import assert from 'node:assert/strict';
import { readFileSync } from 'node:fs';
import test from 'node:test';

import {
  EXPECTED_ANDROID_PACKAGE,
  EXPECTED_FIREBASE_PROJECT_ID,
  EXPECTED_SUPABASE_PROJECT_REF,
  EXPECTED_SUPABASE_URL,
  validateGoogleServices,
  validatePublicMobileConfiguration,
  validateStripeConfiguration,
  validateSupabaseConfiguration,
} from '../../scripts/prepare-mobile-secrets.mjs';

function jwt(payload) {
  const encode = (value) => Buffer.from(JSON.stringify(value)).toString('base64url');
  return `${encode({ alg: 'HS256', typ: 'JWT' })}.${encode(payload)}.signature`;
}

const publicSupabaseKey = jwt({
  iss: 'supabase',
  role: 'anon',
  ref: EXPECTED_SUPABASE_PROJECT_REF,
  exp: Math.floor(Date.now() / 1000) + 3600,
});

const runtimeClientWithModernKey = readFileSync(
  new URL('../../src/integrations/supabase/client.ts', import.meta.url),
  'utf8',
);
const publicRuntimeClientWithModernKey = readFileSync(
  new URL('../../src/integrations/supabase/public-client.ts', import.meta.url),
  'utf8',
);
const productionModernKey = runtimeClientWithModernKey.match(
  /sb_publishable_[A-Za-z0-9_-]{16,}/,
)?.[0];
assert.ok(productionModernKey, 'la clé publique moderne de production doit exister dans le fallback du client');

const validEnvironment = {
  MOBILE_BUILD_PROFILE: 'store',
  VITE_ENV: 'production',
  VITE_STRIPE_PUBLISHABLE_KEY: `pk_live_${'a'.repeat(24)}`,
  VITE_SUPABASE_URL: EXPECTED_SUPABASE_URL,
  VITE_SUPABASE_PUBLISHABLE_KEY: publicSupabaseKey,
  VITE_SENTRY_DSN: 'https://public@o123.ingest.sentry.io/456',
};

const validRuntimeClient = `
  const SUPABASE_URL = "${EXPECTED_SUPABASE_URL}";
  const SUPABASE_PUBLISHABLE_KEY = "${publicSupabaseKey}";
`;

const validGoogleServices = {
  project_info: {
    project_number: '123456789',
    project_id: EXPECTED_FIREBASE_PROJECT_ID,
  },
  client: [
    {
      client_info: {
        mobilesdk_app_id: '1:123456789:android:abcdef0123456789',
        android_client_info: { package_name: EXPECTED_ANDROID_PACKAGE },
      },
      api_key: [{ current_key: 'public-firebase-api-key' }],
    },
  ],
};

test('accepte une configuration publique de production complète', () => {
  assert.equal(validatePublicMobileConfiguration(validEnvironment, validRuntimeClient), true);
  assert.equal(validateGoogleServices(validGoogleServices), true);
});

test('un build mobile ne dépend pas de Cloudflare Turnstile', () => {
  assert.equal(validatePublicMobileConfiguration({
    ...validEnvironment,
    VITE_TURNSTILE_SITE_KEY: undefined,
  }, validRuntimeClient), true);

  const packageJson = JSON.parse(readFileSync(new URL('../../package.json', import.meta.url), 'utf8'));
  assert.match(packageJson.scripts['build:mobile'], /VITE_NATIVE_BUILD=true/);
  assert.match(packageJson.scripts['build:mobile'], /VITE_TURNSTILE_SITE_KEY=/);
});

test('refuse une clé Stripe absente ou de test dans un build store', () => {
  assert.throws(
    () => validateStripeConfiguration({ MOBILE_BUILD_PROFILE: 'store' }),
    /VITE_STRIPE_PUBLISHABLE_KEY manquante/,
  );
  assert.throws(
    () => validateStripeConfiguration({
      MOBILE_BUILD_PROFILE: 'store',
      ALLOW_NON_LIVE_STRIPE_KEY: '1',
      VITE_STRIPE_PUBLISHABLE_KEY: `pk_test_${'b'.repeat(24)}`,
    }),
    /clé publiable Stripe live/,
  );
});

test('autorise une clé Stripe test uniquement avec le double opt-in développement', () => {
  const key = `pk_test_${'c'.repeat(24)}`;
  assert.throws(
    () => validateStripeConfiguration({ MOBILE_BUILD_PROFILE: 'development', VITE_STRIPE_PUBLISHABLE_KEY: key }),
    /ALLOW_NON_LIVE_STRIPE_KEY=1/,
  );
  assert.equal(validateStripeConfiguration({
    MOBILE_BUILD_PROFILE: 'development',
    ALLOW_NON_LIVE_STRIPE_KEY: '1',
    VITE_STRIPE_PUBLISHABLE_KEY: key,
  }), true);
});

test('refuse une URL, une clé ou un client Supabase d’un autre projet', () => {
  assert.throws(
    () => validateSupabaseConfiguration({
      VITE_SUPABASE_URL: 'https://example.supabase.co',
      VITE_SUPABASE_PUBLISHABLE_KEY: publicSupabaseKey,
    }, validRuntimeClient),
    /projet Supabase de production/,
  );

  const wrongProjectKey = jwt({
    iss: 'supabase',
    role: 'anon',
    ref: 'anotherprojectref1234',
    exp: 4_000_000_000,
  });
  assert.throws(
    () => validateSupabaseConfiguration({
      VITE_SUPABASE_URL: EXPECTED_SUPABASE_URL,
      VITE_SUPABASE_PUBLISHABLE_KEY: wrongProjectKey,
    }, validRuntimeClient),
    /clé publique anon du projet de production/,
  );

  assert.throws(
    () => validateSupabaseConfiguration(validEnvironment, validRuntimeClient.replace(publicSupabaseKey, wrongProjectKey)),
    /configuration Supabase embarquée/,
  );

  const wrongProjectModernKey = `sb_publishable_${'other_project'.padEnd(32, '_')}`;
  assert.throws(
    () => validateSupabaseConfiguration({
      VITE_SUPABASE_URL: EXPECTED_SUPABASE_URL,
      VITE_SUPABASE_PUBLISHABLE_KEY: wrongProjectModernKey,
    }, runtimeClientWithModernKey),
    (error) => {
      assert.match(error.message, /clé publique du projet de production/);
      assert.equal(error.message.includes(wrongProjectModernKey), false);
      return true;
    },
  );
});

test('accepte uniquement la clé sb_publishable exacte de production', () => {
  assert.equal(validateSupabaseConfiguration({
    VITE_SUPABASE_URL: EXPECTED_SUPABASE_URL,
    VITE_SUPABASE_PUBLISHABLE_KEY: productionModernKey,
  }, runtimeClientWithModernKey), true);
  assert.equal(validateSupabaseConfiguration({
    VITE_SUPABASE_URL: EXPECTED_SUPABASE_URL,
    VITE_SUPABASE_PUBLISHABLE_KEY: productionModernKey,
  }, publicRuntimeClientWithModernKey), true);
});

test('refuse une ancienne clé anon dont l’issuer est falsifié', () => {
  const malformedIssuerKey = jwt({
    iss: 'supaabase',
    role: 'anon',
    ref: EXPECTED_SUPABASE_PROJECT_REF,
    exp: 4_000_000_000,
  });

  assert.throws(
    () => validateSupabaseConfiguration({
      VITE_SUPABASE_URL: EXPECTED_SUPABASE_URL,
      VITE_SUPABASE_PUBLISHABLE_KEY: malformedIssuerKey,
    }, validRuntimeClient),
    /clé publique anon du projet de production/,
  );
});

test('refuse une clé Supabase serveur dans le bundle mobile', () => {
  assert.throws(
    () => validateSupabaseConfiguration({
      VITE_SUPABASE_URL: EXPECTED_SUPABASE_URL,
      VITE_SUPABASE_PUBLISHABLE_KEY: `sb_secret_${'x'.repeat(24)}`,
    }, validRuntimeClient),
    /clé serveur interdite/,
  );
});

test('refuse un google-services.json rattaché à un autre package', () => {
  const wrongPackage = structuredClone(validGoogleServices);
  wrongPackage.client[0].client_info.android_client_info.package_name = 'app.soin.direct';
  assert.throws(() => validateGoogleServices(wrongPackage), new RegExp(EXPECTED_ANDROID_PACKAGE.replace('.', '\\.')));
});

test('les erreurs de validation ne recopient jamais la valeur fournie', () => {
  const sensitiveMarker = 'pk_test_SENSITIVE_MARKER_123456789';
  assert.throws(
    () => validateStripeConfiguration({
      MOBILE_BUILD_PROFILE: 'store',
      VITE_STRIPE_PUBLISHABLE_KEY: sensitiveMarker,
    }),
    (error) => {
      assert.equal(error.message.includes(sensitiveMarker), false);
      return true;
    },
  );
});
