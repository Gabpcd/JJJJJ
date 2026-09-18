import { beforeEach, describe, expect, it, vi } from "vitest";
import {
  creerCompteRapide,
  donneesFormulaire,
  finaliserProfil,
  restaurerFormulaire,
} from "./inscriptionProgressive";

const m = vi.hoisted(() => ({
  signUp: vi.fn(),
  signIn: vi.fn(),
  rpc: vi.fn(),
  invoke: vi.fn(),
  getSession: vi.fn(),
  refresh: vi.fn(),
  signOut: vi.fn(),
}));
vi.mock("@/integrations/supabase/client", () => ({
  supabase: {
    rpc: m.rpc,
    functions: { invoke: m.invoke },
    auth: {
      signUp: m.signUp,
      signInWithPassword: m.signIn,
      getSession: m.getSession,
      refreshSession: m.refresh,
      signOut: m.signOut,
    },
  },
}));
vi.mock("@/hooks/useRole", () => ({ reinitialiserCacheRole: vi.fn() }));
vi.mock("@/lib/attribution", () => ({ getAttribution: () => ({}) }));
const input = {
  type: "SOIGNANT" as const,
  email: "  TEST@example.org ",
  password: "secretvalide",
  profession: "IDE",
  nom: "",
  cgu: true,
  cgv: false,
};
beforeEach(() => {
  vi.resetAllMocks();
  m.rpc.mockResolvedValue({ data: {}, error: null });
  m.getSession.mockResolvedValue({ data: { session: null } });
  m.refresh.mockResolvedValue({ error: null });
});
describe("inscription progressive", () => {
  it("attend la confirmation email avant de créer le brouillon", async () => {
    m.signUp.mockResolvedValue({
      data: { session: null, user: { identities: [{}] } },
      error: null,
    });
    expect(await creerCompteRapide(input)).toBe("confirmation");
    expect(m.rpc).not.toHaveBeenCalled();
    expect(m.signUp).toHaveBeenCalledWith(
      expect.objectContaining({
        email: "test@example.org",
        options: expect.objectContaining({
          data: {
            inscription_progressive: expect.objectContaining({
              type: "SOIGNANT",
            }),
          },
        }),
      }),
    );
  });
  it("reprend un compte confirmé sans le recréer", async () => {
    m.signIn.mockResolvedValue({
      data: { session: { user: { id: "owner" } } },
      error: null,
    });
    expect(await creerCompteRapide(input, true)).toBe("cree");
    expect(m.signUp).not.toHaveBeenCalled();
    expect(m.rpc).toHaveBeenCalledWith(
      "fn_demarrer_inscription",
      expect.objectContaining({
        p_type_compte: "SOIGNANT",
        p_profession: "IDE",
      }),
    );
  });
  it("ne donne pas un espace au faux utilisateur anti-énumération", async () => {
    m.signUp.mockResolvedValue({
      data: { session: null, user: { id: "fake", identities: [] } },
      error: null,
    });
    m.signIn.mockResolvedValue({
      data: { session: null },
      error: new Error("Invalid login credentials"),
    });
    await expect(creerCompteRapide(input)).rejects.toMatchObject({ code: "SIGN_IN_REQUIRED" });
    expect(m.rpc).not.toHaveBeenCalled();
    expect(m.signIn).not.toHaveBeenCalled();
  });
  it("ne restaure ni secrets ni valeurs de type incorrect", () => {
    expect(
      restaurerFormulaire(
        {
          prenom: "",
          motDePasse: "",
          email: "",
          typesContrat: [] as string[],
          rayon: 30,
          estSalarieEtablissement: null,
        },
        {
          prenom: "Camille",
          motDePasse: "secret",
          email: "autre@test.fr",
          typesContrat: ["CDD"],
          rayon: "dangereux",
          estSalarieEtablissement: false,
          role: "ADMIN",
        },
      ),
    ).toEqual({
      prenom: "Camille",
      motDePasse: "",
      email: "",
      typesContrat: ["CDD"],
      rayon: 30,
      estSalarieEtablissement: false,
    });
    expect(
      donneesFormulaire({
        prenom: "Camille",
        motDePasse: "secret",
        confirmMdp: "secret",
        email: "a@b.fr",
        lat: 1,
        lng: 1,
        turnstileToken: "token",
      }),
    ).toEqual({ prenom: "Camille" });
  });
  it("enregistre la saisie et conserve la session lors d’un refus métier", async () => {
    m.getSession.mockResolvedValue({ data: { session: { access_token: "token", user: { email: "test@example.org" } } } });
    m.invoke.mockResolvedValue({
      data: {
        ok: false,
        code: "RPPS_TRAITS_MISMATCH",
        message: "Identité différente",
      },
      error: null,
    });
    await expect(
      finaliserProfil("SOIGNANT", {
        prenom: "Camille",
        profession: "IDE",
        motDePasse: "secret",
      }),
    ).rejects.toMatchObject({ code: "RPPS_TRAITS_MISMATCH" });
    expect(m.rpc).toHaveBeenCalledWith("fn_enregistrer_parcours_inscription", {
      p_donnees: { prenom: "Camille", profession: "IDE" },
    });
    expect(m.signUp).not.toHaveBeenCalled();
    expect(m.signOut).not.toHaveBeenCalled();
    expect(m.refresh).not.toHaveBeenCalled();
  });
  it("réessaie seulement le brouillon après création Auth, sans réutiliser le captcha", async () => {
    m.getSession.mockResolvedValue({ data: { session: { user: { email: "test@example.org" } } } });
    expect(await creerCompteRapide({ ...input, captchaToken: "new-token" })).toBe("cree");
    expect(m.signUp).not.toHaveBeenCalled();
    expect(m.signIn).not.toHaveBeenCalled();
    expect(m.rpc).toHaveBeenCalledWith("fn_demarrer_inscription", expect.anything());
  });
  it("ne prétend pas finaliser sans session", async () => {
    m.getSession.mockResolvedValue({ data: { session: null } });
    await expect(
      finaliserProfil("ETABLISSEMENT", { nom: "Résidence" }),
    ).rejects.toThrow("Reconnectez-vous");
    expect(m.invoke).not.toHaveBeenCalled();
  });
});
