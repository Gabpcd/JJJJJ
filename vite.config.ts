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
    sentryUploadEnabled && sentryAuthToken
      ? sentryVitePlugin({
          authToken: sentryAuthToken,
          org: sentryOrg,
          project: sentryProject,
          telemetry: false,
          // Lie les sourcemaps à la release courante pour désobfuscation propre
          release: { name: APP_VERSION, create: true, finalize: true },
          sourcemaps: { assets: './dist/**' },
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
    // Génère des .js.map pour permettre à Sentry de désobfusquer les stacks.
    sourcemap: true,
    rollupOptions: {
      output: {
        manualChunks: {
          'vendor-react': ['react', 'react-dom', 'react-router-dom'],
          'vendor-query': ['@tanstack/react-query'],
          'vendor-charts': ['recharts'],
          'vendor-supabase': ['@supabase/supabase-js'],
          'vendor-pdf': ['jspdf', 'jspdf-autotable'],
          'vendor-date': ['date-fns'],
          'vendor-ui': ['sonner', '@radix-ui/react-dialog', '@radix-ui/react-select', '@radix-ui/react-tooltip'],
        },
      },
    },
  },
}));
