import { defineConfig } from "vitest/config";
import react from "@vitejs/plugin-react-swc";
import path from "path";

export default defineConfig({
  plugins: [react()],
  test: {
    environment: "jsdom",
    globals: true,
    setupFiles: ["./src/test/setup.ts"],
    include: [
      "src/**/*.{test,spec}.{ts,tsx}",
      "tests/admin/**/*.{test,spec}.{ts,tsx}",
      "tests/security/registration-recovery.test.ts",
    ],
  },
  resolve: {
    alias: {
      "@": path.resolve(__dirname, "./src"),
      // Exécuter le parseur de production Edge sous Vitest, sans le dupliquer.
      "npm:pdf-lib@1.17.1": path.resolve(__dirname, "./node_modules/pdf-lib"),
    },
  },
});
