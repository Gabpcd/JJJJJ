import { beforeEach, expect, it, vi } from "vitest";
import { StrictMode } from "react";
import { act, render, screen } from "@testing-library/react";
import { BrowserRouter, Route, Routes } from "react-router-dom";
import ConfirmationInscription, {
  confirmerInscription,
} from "./ConfirmationInscription";
const auth = vi.hoisted(() => ({
  setSession: vi.fn(),
  exchangeCodeForSession: vi.fn(),
  verifyOtp: vi.fn(),
}));
vi.mock("@/integrations/supabase/client", () => ({ supabase: { auth } }));
vi.mock("@/components/AuthLayout", () => ({
  AuthLayout: ({ children }: { children: React.ReactNode }) => <>{children}</>,
}));
beforeEach(() => {
  vi.resetAllMocks();
  for (const method of Object.values(auth))
    method.mockResolvedValue({
      data: { session: { user: { id: "owner" } } },
      error: null,
    });
});
it("consomme le lien implicit même après initialisation du client natif", async () => {
  await confirmerInscription({
    search: "",
    hash: "#access_token=access&refresh_token=refresh&type=signup",
  });
  expect(auth.setSession).toHaveBeenCalledExactlyOnceWith({
    access_token: "access",
    refresh_token: "refresh",
  });
});
it("consomme les deux variantes de code sans double échange", async () => {
  await confirmerInscription({ search: "?code=pkce-code", hash: "" });
  expect(auth.exchangeCodeForSession).toHaveBeenCalledExactlyOnceWith(
    "pkce-code",
  );
  expect(auth.verifyOtp).not.toHaveBeenCalled();
  await confirmerInscription({
    search: "?token_hash=otp-hash&type=signup",
    hash: "",
  });
  expect(auth.verifyOtp).toHaveBeenCalledExactlyOnceWith({
    token_hash: "otp-hash",
    type: "signup",
  });
});
it("refuse les liens de récupération et les tokens incomplets", async () => {
  await expect(
    confirmerInscription({
      search: "",
      hash: "#access_token=access&refresh_token=refresh&type=recovery",
    }),
  ).rejects.toThrow();
  await expect(
    confirmerInscription({
      search: "",
      hash: "#access_token=access&type=signup",
    }),
  ).rejects.toThrow();
  expect(auth.setSession).not.toHaveBeenCalled();
});
it("ne valide pas une réponse sans session ou en erreur", async () => {
  auth.exchangeCodeForSession.mockResolvedValue({
    data: { session: null },
    error: new Error("expired"),
  });
  await expect(
    confirmerInscription({ search: "?code=expired", hash: "" }),
  ).rejects.toThrow("expiré");
});
it("consomme un nouveau lien dans le même WebView après un lien expiré, une seule fois par code", async () => {
  auth.exchangeCodeForSession.mockResolvedValueOnce({
    data: { session: null },
    error: { message: "expired" },
  });
  window.history.replaceState(null, "", "/inscription/confirmer?code=expired");
  render(
    <StrictMode>
      <BrowserRouter>
        <Routes>
          <Route
            path="/inscription/confirmer"
            element={<ConfirmationInscription />}
          />
          <Route
            path="/inscription/reprendre"
            element={<p>Inscription reprise</p>}
          />
        </Routes>
      </BrowserRouter>
    </StrictMode>,
  );
  expect(await screen.findByRole("alert")).toHaveTextContent(
    "Ce lien n’a pas pu être validé",
  );
  expect(auth.exchangeCodeForSession).toHaveBeenCalledTimes(1);
  await act(async () => {
    window.history.replaceState(
      null,
      "",
      "/inscription/confirmer?code=new-code",
    );
    window.dispatchEvent(new PopStateEvent("popstate"));
  });
  expect(await screen.findByText("Inscription reprise")).toBeVisible();
  expect(auth.exchangeCodeForSession).toHaveBeenCalledTimes(2);
  expect(window.location.search).toBe("");
  expect(window.location.hash).toBe("");
});
