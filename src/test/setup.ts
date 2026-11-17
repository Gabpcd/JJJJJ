import "@testing-library/jest-dom";
import { afterEach } from "vitest";
import { oublierToutesLesSaisies } from "@/lib/saisieInscriptionEnCours";

// La saisie d'inscription vit en mémoire du module : chaque test repart sans
// saisie d'un test précédent (revue B8 #1137, m1).
afterEach(() => oublierToutesLesSaisies());

// Les tests de handlers Edge utilisent Node ; le faux matchMedia concerne le DOM.
if (typeof window !== "undefined") {
  Object.defineProperty(window, "matchMedia", {
    writable: true,
    value: (query: string) => ({
      matches: false,
      media: query,
      onchange: null,
      addListener: () => {},
      removeListener: () => {},
      addEventListener: () => {},
      removeEventListener: () => {},
      dispatchEvent: () => {},
    }),
  });
}
