import { defineConfig } from "vitest/config";
import path from "path";

// Config DÉDIÉE à la suite de non-régression facturation (`tests/invoicing/`).
// Isolée de vitest.config.ts (jsdom, include src/) pour que `npm test` ne tente
// PAS de lancer ces tests d'intégration DB. Cible : le maillon
// `test:regression:invoicing` de la chaîne CI `npm run test:regression`.
//
// NB : 7 des 8 tests sont des tests d'INTÉGRATION (connexion pg réelle) — ils
// exigent l'env DB (comme `test:schema`), donc CI-only ; `facturx-generator`
// est pur et tourne partout. La chaîne `test:regression` est CI-only par nature
// (schema + e2e ont les mêmes prérequis).
export default defineConfig({
  test: {
    environment: "node",
    include: ["tests/invoicing/**/*.{test,spec}.{ts,tsx}"],
  },
  resolve: {
    alias: { "@": path.resolve(__dirname, "./src") },
  },
});
