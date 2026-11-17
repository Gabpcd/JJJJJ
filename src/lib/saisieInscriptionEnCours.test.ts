import { afterEach, describe, expect, it } from "vitest";
import {
  donneesAReprendre,
  memoriserSaisie,
  oublierSaisie,
  oublierToutesLesSaisies,
} from "./saisieInscriptionEnCours";

const soignant = { user_id: "u1", type_compte: "SOIGNANT" };

describe("saisie d'inscription en cours", () => {
  afterEach(() => oublierToutesLesSaisies());

  it("reprend la saisie de l'onglet par-dessus le brouillon serveur", () => {
    memoriserSaisie(soignant, { prenom: "Camille", estEtudiant: true, scolariteFormation: "MEDECINE_DES" });
    expect(donneesAReprendre({ ...soignant, donnees: { prenom: "", profession: "MEDECIN", rayon: 30 } }))
      .toEqual({ prenom: "Camille", profession: "MEDECIN", rayon: 30, estEtudiant: true, scolariteFormation: "MEDECINE_DES" });
  });

  it("sans saisie mémorisée, rend le brouillon serveur tel quel", () => {
    expect(donneesAReprendre({ ...soignant, donnees: { prenom: "Alex" } })).toEqual({ prenom: "Alex" });
    expect(donneesAReprendre({ ...soignant, donnees: null })).toEqual({});
  });

  it("ne donne jamais la saisie d'un compte à un autre compte ou à un autre type", () => {
    memoriserSaisie(soignant, { prenom: "Camille" });
    expect(donneesAReprendre({ user_id: "u2", type_compte: "SOIGNANT", donnees: {} })).toEqual({});
    expect(donneesAReprendre({ user_id: "u1", type_compte: "ETABLISSEMENT", donnees: {} })).toEqual({});
  });

  it("copie la saisie : une modification ultérieure de l'objet source ne fuit pas", () => {
    const donnees: Record<string, unknown> = { prenom: "Camille" };
    memoriserSaisie(soignant, donnees);
    donnees.prenom = "Autre";
    expect(donneesAReprendre({ ...soignant, donnees: {} })).toEqual({ prenom: "Camille" });
  });

  it("oublie la saisie après finalisation et à la déconnexion", () => {
    memoriserSaisie(soignant, { prenom: "Camille" });
    oublierSaisie(soignant);
    expect(donneesAReprendre({ ...soignant, donnees: {} })).toEqual({});
    memoriserSaisie(soignant, { prenom: "Camille" });
    memoriserSaisie({ user_id: "u2", type_compte: "ETABLISSEMENT" }, { nom: "Clinique" });
    oublierToutesLesSaisies();
    expect(donneesAReprendre({ ...soignant, donnees: {} })).toEqual({});
    expect(donneesAReprendre({ user_id: "u2", type_compte: "ETABLISSEMENT", donnees: {} })).toEqual({});
  });
});
