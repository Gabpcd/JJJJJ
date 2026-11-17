import { afterEach, describe, expect, it } from "vitest";
import {
  memoriserSaisie,
  oublierSaisie,
  oublierToutesLesSaisies,
  reprendreSaisie,
} from "./saisieInscriptionEnCours";

const compte = { user_id: "u1", type_compte: "SOIGNANT" };
const serveur = { prenom: "", nom: "Recette", profession: "MEDECIN", rayon: 30 };

describe("saisie d'inscription en cours", () => {
  afterEach(() => oublierToutesLesSaisies());

  it("reprend la saisie de l'onglet sur un brouillon serveur inchangé", () => {
    memoriserSaisie({ ...compte, donnees: serveur }, { ...serveur, prenom: "Camille", estEtudiant: true });
    expect(reprendreSaisie({ ...compte, donnees: { ...serveur } })).toEqual({
      donnees: { ...serveur, prenom: "Camille", estEtudiant: true },
      depuisOnglet: true,
    });
  });

  it("sans saisie mémorisée, rend le brouillon serveur tel quel", () => {
    expect(reprendreSaisie({ ...compte, donnees: { prenom: "Alex" } })).toEqual({ donnees: { prenom: "Alex" }, depuisOnglet: false });
    expect(reprendreSaisie({ ...compte, donnees: null })).toEqual({ donnees: {}, depuisOnglet: false });
  });

  it("ignore et oublie la saisie quand le brouillon serveur a été modifié ailleurs (revue B8 #1137, B1)", () => {
    memoriserSaisie({ ...compte, donnees: serveur }, { ...serveur, prenom: "Camille" });
    const corrige = { ...serveur, nom: "Recette-Martin" };
    expect(reprendreSaisie({ ...compte, donnees: corrige })).toEqual({ donnees: corrige, depuisOnglet: false });
    // Oubliée : même si le serveur revenait à l'ancienne version, rien ne ressort.
    expect(reprendreSaisie({ ...compte, donnees: serveur })).toEqual({ donnees: serveur, depuisOnglet: false });
  });

  it("un champ apparu côté serveur et absent de l'ancien brouillon compte comme une modification", () => {
    memoriserSaisie({ ...compte, donnees: { nom: "Recette" } }, { nom: "Recette", siret: "" });
    expect(reprendreSaisie({ ...compte, donnees: { nom: "Recette", siret: "12345678901234" } }).depuisOnglet).toBe(false);
  });

  it("un changement serveur hors des champs du formulaire ne fait pas perdre la saisie", () => {
    memoriserSaisie({ ...compte, donnees: serveur }, { ...serveur, prenom: "Camille" });
    const avecMission = { ...serveur, missionChoisie: "m-42", brouillonMission: true };
    expect(reprendreSaisie({ ...compte, donnees: avecMission })).toEqual({
      donnees: { ...avecMission, prenom: "Camille" },
      depuisOnglet: true,
    });
  });

  it("ne donne jamais la saisie d'un compte à un autre compte ou à un autre type", () => {
    memoriserSaisie({ ...compte, donnees: serveur }, { ...serveur, prenom: "Camille" });
    expect(reprendreSaisie({ user_id: "u2", type_compte: "SOIGNANT", donnees: serveur }).depuisOnglet).toBe(false);
    expect(reprendreSaisie({ user_id: "u1", type_compte: "ETABLISSEMENT", donnees: serveur }).depuisOnglet).toBe(false);
  });

  it("copie la saisie : une modification ultérieure de l'objet source ne fuit pas", () => {
    const saisie: Record<string, unknown> = { ...serveur, prenom: "Camille" };
    memoriserSaisie({ ...compte, donnees: serveur }, saisie);
    saisie.prenom = "Autre";
    expect(reprendreSaisie({ ...compte, donnees: serveur }).donnees.prenom).toBe("Camille");
  });

  it("oublie la saisie d'un compte, puis toutes les saisies", () => {
    memoriserSaisie({ ...compte, donnees: serveur }, { ...serveur, prenom: "Camille" });
    oublierSaisie(compte);
    expect(reprendreSaisie({ ...compte, donnees: serveur }).depuisOnglet).toBe(false);
    memoriserSaisie({ ...compte, donnees: serveur }, { ...serveur, prenom: "Camille" });
    memoriserSaisie({ user_id: "u2", type_compte: "ETABLISSEMENT", donnees: {} }, { nom: "Clinique" });
    oublierToutesLesSaisies();
    expect(reprendreSaisie({ ...compte, donnees: serveur }).depuisOnglet).toBe(false);
    expect(reprendreSaisie({ user_id: "u2", type_compte: "ETABLISSEMENT", donnees: {} }).depuisOnglet).toBe(false);
  });
});
