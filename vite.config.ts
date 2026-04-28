import { defineConfig } from "vite";
import react from "@vitejs/plugin-react-swc";
import { sentryVitePlugin } from "@sentry/vite-plugin";
import path from "path";

// Upload des source maps Sentry uniquement quand SENTRY_AUTH_TOKEN est dispo
// (CI prod Vercel). En dev local sans le token, le plugin est désactivé pour
// ne pas casser le build.
const sentryAuthToken = process.env.SENTRY_AUTH_TOKEN;
const sentryOrg = process.env.SENTRY_ORG || 'jolene';
const sentryProject = process.env.SENTRY_PROJECT || 'jolene-frontend';

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
    sentryAuthToken
      ? sentryVitePlugin({
          authToken: sentryAuthToken,
          org: sentryOrg,
          project: sentryProject,
          telemetry: false,
          sourcemaps: { assets: './dist/**' },
        })
      : null,
  ].filter(Boolean) as any[],
  resolve: {
    alias: {
      "@": path.resolve(__dirname, "./src"),
    },
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
