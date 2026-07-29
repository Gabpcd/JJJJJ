import { readFileSync } from 'node:fs';
import { describe, expect, it } from 'vitest';

const source = readFileSync(
  'supabase/functions/stripe-connect-onboard/index.ts',
  'utf8',
);
const androidManifest = readFileSync(
  'android/app/src/main/AndroidManifest.xml',
  'utf8',
);
const appleAppSiteAssociation = readFileSync(
  'public/.well-known/apple-app-site-association',
  'utf8',
);

describe('Stripe Connect onboarding — URL de retour de confiance', () => {
  it('réutilise la décision CORS partagée et refuse toute origine absente ou inconnue', () => {
    expect(source).toContain('import { corsHeaders, getCorsOrigin } from "../_shared/cors.ts"');
    expect(source).toContain('if (!requestOrigin || getCorsOrigin(req) !== requestOrigin) return null');
    expect(source).toContain('if (!returnOrigin)');
    expect(source).toContain('ORIGINE_NON_AUTORISEE');
    expect(source).toContain('status: 403');
  });

  it('limite les callbacks aux origines Jolene production et localhost explicites', () => {
    for (const origin of [
      'https://jolene.app',
      'https://www.jolene.app',
      'https://app.jolene.app',
      'http://localhost:5173',
      'http://localhost:8080',
    ]) {
      expect(source).toContain(`"${origin}"`);
    }

    expect(source).toContain('return STRIPE_WEB_RETURN_ORIGINS.has(requestOrigin) ? requestOrigin : null');
  });

  it('convertit les origines Capacitor autorisées en Universal Link public', () => {
    expect(source).toContain('"https://localhost"');
    expect(source).toContain('"capacitor://localhost"');
    expect(source).toContain('if (NATIVE_APP_ORIGINS.has(requestOrigin))');
    expect(source).toContain('return "https://jolene.app"');
  });

  it('ne construit jamais Account Link depuis le header Origin brut', () => {
    const originGate = source.indexOf('const returnOrigin = getTrustedStripeReturnOrigin(req)');
    const accountCreation = source.indexOf('stripe.accounts.create');
    const accountLink = source.slice(source.indexOf('stripe.accountLinks.create'));

    expect(originGate).toBeGreaterThan(0);
    expect(originGate).toBeLessThan(accountCreation);
    expect(accountLink).toContain('refresh_url: `${returnOrigin}/soignant/stripe-connect?refresh=true`');
    expect(accountLink).toContain('return_url: `${returnOrigin}/soignant/stripe-connect?success=true`');
    expect(source).not.toContain('const origin = req.headers.get("origin") ||');
    expect(accountLink).not.toContain('`${origin}/soignant/stripe-connect');
  });

  it('ouvre les retours Stripe dans les applications Android et iOS', () => {
    expect(androidManifest).toContain('android:pathPrefix="/soignant/stripe-connect"');
    expect(androidManifest).toContain('android:pathPrefix="/etablissement/facturation"');

    const association = JSON.parse(appleAppSiteAssociation);
    const paths = association.applinks.details
      .filter((detail: { appID?: string }) => detail.appID === 'FPQ78HDF4Y.app.jolene')
      .flatMap((detail: { paths?: string[] }) => detail.paths ?? []);
    expect(paths).toContain('/soignant/*');
    expect(paths).toContain('/etablissement/*');
  });

  it('conserve la parité des familles de liens universels iOS et Android', () => {
    const association = JSON.parse(appleAppSiteAssociation);
    const paths = association.applinks.details
      .filter((detail: { appID?: string }) => detail.appID === 'FPQ78HDF4Y.app.jolene')
      .flatMap((detail: { paths?: string[] }) => detail.paths ?? []);
    const sharedFamilies = [
      ['/groupe/*', 'android:pathPrefix="/groupe/"'],
      ['/admin/*', 'android:pathPrefix="/admin/"'],
      ['/connexion', 'android:pathPrefix="/connexion"'],
      ['/inscription/*', 'android:pathPrefix="/inscription/"'],
    ] as const;

    for (const [iosPath, androidPath] of sharedFamilies) {
      expect(paths).toContain(iosPath);
      expect(androidManifest).toContain(androidPath);
    }
  });
});
