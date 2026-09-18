import { useEffect, useRef, useState } from "react";
import { Link, useNavigate, useLocation } from "react-router-dom";
import { supabase } from "@/integrations/supabase/client";
import { AuthLayout } from "@/components/AuthLayout";
import { ChargementPage } from "@/components/ChargementPage";

/** Propriétaire unique du callback, aussi lorsque le WebView est déjà ouvert. */
export async function confirmerInscription(
  url: Pick<Location, "search" | "hash">,
) {
  const query = new URLSearchParams(url.search);
  const hash = new URLSearchParams(url.hash.replace(/^#/, ""));
  const type = hash.get("type") || query.get("type");
  if (type && type !== "signup" && type !== "email")
    throw new Error("Lien invalide");
  let result;
  if (hash.get("access_token") && hash.get("refresh_token") && type) {
    result = await supabase.auth.setSession({
      access_token: hash.get("access_token")!,
      refresh_token: hash.get("refresh_token")!,
    });
  } else if (query.get("code")) {
    result = await supabase.auth.exchangeCodeForSession(query.get("code")!);
  } else if (query.get("token_hash") && type) {
    result = await supabase.auth.verifyOtp({
      token_hash: query.get("token_hash")!,
      type: type === "signup" ? "signup" : "email",
    });
  } else {
    throw new Error("Lien invalide");
  }
  if (result.error || !result.data.session)
    throw new Error("Lien invalide ou expiré");
}

export default function ConfirmationInscription() {
  const navigate = useNavigate();
  const { search, hash } = useLocation();
  const operation = useRef<{ url: string; promise: Promise<void> } | null>(
    null,
  );
  const [error, setError] = useState(false);
  useEffect(() => {
    let active = true;
    // Un second effet StrictMode partage l'échange du code à usage unique.
    const url = `${search}${hash}`;
    if (operation.current?.url !== url) {
      setError(false);
      operation.current = {
        url,
        promise: confirmerInscription({ search, hash }),
      };
    }
    operation.current.promise
      .then(() => {
        if (active) navigate("/inscription/reprendre", { replace: true });
      })
      .catch(() => {
        if (active) setError(true);
      })
      .finally(() => {
        if (active && window.location.pathname === "/inscription/confirmer") {
          window.history.replaceState(null, "", "/inscription/confirmer");
        }
      });
    return () => {
      active = false;
    };
  }, [navigate, search, hash]);
  if (!error) return <ChargementPage />;
  return (
    <AuthLayout backTo="/connexion">
      <div className="card-base max-w-lg space-y-4">
        <h1 className="text-xl font-bold">Reprendre votre inscription</h1>
        <p role="alert">
          Ce lien n’a pas pu être validé. S’il a déjà confirmé votre email,
          connectez-vous pour retrouver votre inscription.
        </p>
        <Link to="/connexion" className="btn-primary block text-center">
          Se connecter
        </Link>
      </div>
    </AuthLayout>
  );
}
