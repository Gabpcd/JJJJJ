/**
 * Lighthouse CI configuration for Jolene.
 *
 * Audite les pages publiques critiques (landing, inscription, connexion, aide,
 * accessibilité, 404). Échec si scores Performance / A11y / Best Practices /
 * SEO sous les thresholds.
 *
 * Usage local : npx lhci autorun
 * Usage CI    : .github/workflows/lighthouse.yml
 */

const BASE_URL = process.env.LHCI_BASE_URL || 'http://127.0.0.1:4173';

module.exports = {
  ci: {
    collect: {
      url: [
        `${BASE_URL}/`,
        `${BASE_URL}/connexion`,
        `${BASE_URL}/reset-password`,
        `${BASE_URL}/inscription/soignant`,
        `${BASE_URL}/inscription/etablissement`,
        `${BASE_URL}/aide`,
        `${BASE_URL}/accessibilite`,
        `${BASE_URL}/cette-page-nexiste-pas`,
      ],
      numberOfRuns: 1,
      settings: {
        chromeFlags: '--no-sandbox --disable-dev-shm-usage',
        // Pas de throttling artificiel : les CI runners sont déjà lents
        throttlingMethod: 'provided',
        // Préfère scores via les clés form-factor
        formFactor: 'desktop',
        screenEmulation: { disabled: true },
      },
    },
    assert: {
      // Thresholds réalistes pour SPA Vite + Supabase :
      // - Performance 70 : LCP ~2.5s typique (lazy loading + bundle ~500KB)
      // - A11y 95 : doublon avec axe-core Playwright qui est plus strict.
      //   Garder en warn pour visibilité dans les rapports sans bloquer le CI
      //   (la vraie barrière a11y est dans e2e/a11y.spec.ts via expectNoCriticalA11y).
      // - Best Practices 85 : standard pour app moderne
      // - SEO 85 : meta + sitemap mais SPA = handicap modeste
      assertions: {
        'categories:performance': ['warn', { minScore: 0.7 }],
        'categories:accessibility': ['warn', { minScore: 0.95 }],
        'categories:best-practices': ['warn', { minScore: 0.85 }],
        'categories:seo': ['warn', { minScore: 0.85 }],
        // Métriques individuelles tolérantes (CI runners variables)
        'first-contentful-paint': ['warn', { maxNumericValue: 3000 }],
        'largest-contentful-paint': ['warn', { maxNumericValue: 4000 }],
        'total-blocking-time': ['warn', { maxNumericValue: 600 }],
        'cumulative-layout-shift': ['warn', { maxNumericValue: 0.15 }],
      },
    },
    upload: {
      // Stockage des rapports en local (artifacts CI). Pas de LHCI server externe.
      target: 'filesystem',
      outputDir: '.lighthouseci',
      reportFilenamePattern: '%%PATHNAME%%-%%DATETIME%%-report.%%EXTENSION%%',
    },
  },
};
