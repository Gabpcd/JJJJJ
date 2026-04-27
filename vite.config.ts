import { defineConfig } from "vite";
import react from "@vitejs/plugin-react-swc";
import path from "path";

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
  plugins: [react()].filter(Boolean),
  resolve: {
    alias: {
      "@": path.resolve(__dirname, "./src"),
    },
  },
  build: {
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
