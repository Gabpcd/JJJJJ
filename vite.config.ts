import { defineConfig } from "vite";
import react from "@vitejs/plugin-react-swc";
import { sentryVitePlugin } from "@sentry/vite-plugin";
import path from "path";

// Upload des source maps Sentry. Activé UNIQUEMENT quand le projet Sentry
// est confirmé créé (env SENTRY_UPLOAD_ENABLED=true) ET que le token est
// présent. Sans le flag, le plugin est désactivé pour éviter un log rouge
// "Project not found" dans Vercel quand Gabrielle n'a pas encore créé le
// projet Sentry. Le build reste fonctionnel — Sentry tag les events via
// `release: __APP_VERSION__` au runtime, sans sourcemaps désobfusquées.
const sentryUploadEnabled = process.env.SENTRY_UPLOAD_ENABLED === 'true';
const sentryAuthToken = process.env.SENTRY_AUTH_TOKEN;
const sentryOrg = process.env.SENTRY_ORG || 'jolene';
const sentryProject = process.env.SENTRY_PROJECT || 'jolene-frontend';
const shouldUploadSourcemaps = sentryUploadEnabled && Boolean(sentryAuthToken);

// Release identifier : SHA git court Vercel en prod, fallback timestamp dev.
// Match les sourcemaps uploadées par sentryVitePlugin pour stack traces lisibles.
const APP_VERSION =
  process.env.VERCEL_GIT_COMMIT_SHA?.slice(0, 8) ||
  process.env.GIT_COMMIT_SHA?.slice(0, 8) ||
  `dev-${new Date().toISOString().slice(0, 10)}`;

// https://vitejs.dev/config/
export default defineConfig(({ mode }) => ({
  server: {
    // host: true => écoute sur 0.0.0.0 + :: pour compatibilité IPv4 + IPv6.
    // L'ancienne valeur "::" plantait avec EAFNOSUPPORT dans les sandboxes
    // sans support IPv6 (CI/conteneurs minimaux).
    host: true,
    port: 8080,
    hmr: {
      overlay: false,
    },
  },
  plugins: [
    react(),
    // Active l'upload des source maps Sentry à chaque build prod si le token
    // est présent. Sans token (dev local, preview Vercel sans secret) le
    // plugin est omis, le build reste rapide.
    shouldUploadSourcemaps && sentryAuthToken
      ? sentryVitePlugin({
          authToken: sentryAuthToken,
          org: sentryOrg,
          project: sentryProject,
          telemetry: false,
          // Lie les sourcemaps à la release courante pour désobfuscation propre
          release: { name: APP_VERSION, create: true, finalize: true },
          sourcemaps: {
            assets: './dist/**',
            // Les cartes servent uniquement à Sentry : elles ne doivent être
            // ni exposées par Vercel ni embarquées dans les apps natives.
            filesToDeleteAfterUpload: './dist/**/*.map',
          },
          // Si l'org/projet Sentry n'existe pas (ou que le token n'a pas
          // accès), on log un warning au lieu de polluer les logs Vercel
          // avec une stack d'erreur. Le build n'est pas bloqué de toutes
          // façons (le plugin n'est pas critique), mais le warning
          // explicite est plus clean.
          errorHandler: (err) => {
            console.warn('[sentry-vite-plugin] non-bloquant :', err.message);
          },
        })
      : null,
  ].filter(Boolean) as any[],
  resolve: {
    alias: {
      "@": path.resolve(__dirname, "./src"),
    },
  },
  define: {
    // Injecté dans main.tsx pour Sentry.init({ release })
    __APP_VERSION__: JSON.stringify(APP_VERSION),
  },
  build: {
    // Sans upload Sentry explicite, aucune source map de production n'est
    // publiée. Avec upload, le mode hidden évite les sourceMappingURL puis le
    // plugin supprime les fichiers après envoi.
    sourcemap: shouldUploadSourcemaps ? 'hidden' : false,
    rolldownOptions: {
      output: {
        codeSplitting: {
          groups: [
            { name: 'vendor-react', test: /node_modules\/(?:react|react-dom|react-router|react-router-dom)\// },
            { name: 'vendor-query', test: /node_modules\/@tanstack\/react-query\// },
            { name: 'vendor-charts', test: /node_modules\/(?:recharts|d3-[^/]+)\// },
            { name: 'vendor-supabase', test: /node_modules\/@supabase\// },
            { name: 'vendor-pdf', test: /node_modules\/(?:jspdf|jspdf-autotable)\// },
            { name: 'vendor-date', test: /node_modules\/date-fns\// },
            { name: 'vendor-ui', test: /node_modules\/(?:sonner|@radix-ui\/react-(?:dialog|select|tooltip))\// },
          ],
        },
      },
    },
  },
}));
