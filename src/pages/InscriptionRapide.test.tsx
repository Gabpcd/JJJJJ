import { fireEvent, render, screen } from "@testing-library/react";
import { MemoryRouter, Route, Routes } from "react-router-dom";
import { beforeEach, expect, it, vi } from "vitest";
import InscriptionRapide from "./InscriptionRapide";
const m = vi.hoisted(() => ({ creer: vi.fn() }));
vi.mock("@/lib/inscriptionProgressive", () => ({ creerCompteRapide: m.creer }));
vi.mock("@/hooks/usePageTitle", () => ({ usePageTitle: () => {} }));
vi.mock("@/components/BoutonProSanteConnect", () => ({
  BoutonProSanteConnect: () => <button type="button">Pro Santé Connect</button>,
}));
vi.mock("@/components/CaptchaTurnstile", () => ({
  CaptchaTurnstile: () => null,
  TURNSTILE_REQUIRED: false,
}));
function ouvrir(type: "SOIGNANT" | "ETABLISSEMENT" = "SOIGNANT") {
  return render(
    <MemoryRouter>
      <Routes>
        <Route path="/" element={<InscriptionRapide type={type} />} />
        <Route path="/inscription/reprendre" element={<p>Espace créé</p>} />
      </Routes>
    </MemoryRouter>,
  );
}
function remplir(type = "SOIGNANT") {
  fireEvent.change(screen.getByLabelText("Email"), {
    target: { value: "test@example.org" },
  });
  fireEvent.change(screen.getByLabelText("Mot de passe"), {
    target: { value: "secretvalide" },
  });
  fireEvent.change(
    screen.getByLabelText(
      type === "SOIGNANT" ? "Profession" : "Nom de l’établissement",
    ),
    { target: { value: type === "SOIGNANT" ? "IDE" : "Résidence Camille" } },
  );
  fireEvent.click(screen.getByRole("checkbox", { name: /CGU/ }));
}
beforeEach(() => {
  vi.resetAllMocks();
  HTMLElement.prototype.scrollTo = vi.fn();
});
it("indique les champs manquants et place le focus, sans requête", () => {
  ouvrir();
  fireEvent.click(screen.getByRole("button", { name: "Créer mon compte" }));
  expect(screen.getByLabelText("Email")).toHaveFocus();
  expect(screen.getByText("Choisissez votre profession.")).toBeVisible();
  expect(m.creer).not.toHaveBeenCalled();
});
it("garde les trois champs après une panne puis permet de réessayer", async () => {
  m.creer
    .mockRejectedValueOnce(new TypeError("Failed to fetch"))
    .mockResolvedValueOnce("cree");
  ouvrir();
  remplir();
  fireEvent.click(screen.getByRole("button", { name: "Créer mon compte" }));
  expect(await screen.findByRole("alert")).toHaveTextContent(
    "Connexion internet instable. Vérifiez votre connexion et réessayez.",
  );
  expect(screen.getByLabelText("Email")).toHaveValue("test@example.org");
  expect(screen.getByLabelText("Profession")).toHaveValue("IDE");
  expect(screen.getByLabelText("Mot de passe")).toHaveValue("secretvalide");
  fireEvent.click(screen.getByRole("button", { name: "Créer mon compte" }));
  expect(await screen.findByText("Espace créé")).toBeVisible();
});
it("présente la confirmation email sans annoncer un espace créé", async () => {
  m.creer.mockResolvedValue("confirmation");
  ouvrir();
  remplir();
  fireEvent.click(screen.getByRole("button", { name: "Créer mon compte" }));
  expect(await screen.findByRole("status")).toHaveTextContent(
    "lien de confirmation",
  );
  fireEvent.click(
    screen.getByRole("button", { name: "J’ai confirmé mon email" }),
  );
  expect(m.creer).toHaveBeenLastCalledWith(expect.anything(), true);
});
it("exige les CGV établissement et crée le compte sans SIRET", async () => {
  m.creer.mockResolvedValue("cree");
  ouvrir("ETABLISSEMENT");
  remplir("ETABLISSEMENT");
  fireEvent.click(screen.getByRole("button", { name: "Créer mon compte" }));
  expect(
    screen.getByText("Acceptez les conditions générales de vente."),
  ).toBeVisible();
  expect(m.creer).not.toHaveBeenCalled();
  fireEvent.click(
    screen.getByRole("checkbox", { name: /conditions générales de vente/ }),
  );
  fireEvent.click(screen.getByRole("button", { name: "Créer mon compte" }));
  expect(await screen.findByText("Espace créé")).toBeVisible();
  expect(m.creer).toHaveBeenCalledWith(
    expect.objectContaining({
      type: "ETABLISSEMENT",
      nom: "Résidence Camille",
      cgv: true,
    }),
    false,
  );
});

it('traduit le refus Supabase de mot de passe divulgué, sans perdre les champs', async () => {
  m.creer.mockRejectedValue({code:'weak_password',message:'Password is known to be weak and easy to guess, please choose a different one.'});
  ouvrir(); remplir();
  fireEvent.click(screen.getByRole('button',{name:'Créer mon compte'}));
  expect(await screen.findByRole('alert')).toHaveTextContent('Ce mot de passe est trop facile à deviner ou a déjà été divulgué. Choisissez un autre mot de passe.');
  expect(screen.getByLabelText('Email')).toHaveValue('test@example.org');
  expect(screen.queryByText(/Password is known/)).not.toBeInTheDocument();
});
