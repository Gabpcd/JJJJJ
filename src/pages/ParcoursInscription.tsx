import { lazy, Suspense, useEffect, useState } from "react";
import { Link, Navigate, useNavigate } from "react-router-dom";
import { useAuth } from "@/contexts/AuthContext";
import { AuthLayout } from "@/components/AuthLayout";
import { ChargementPage } from "@/components/ChargementPage";
import { supabase } from "@/integrations/supabase/client";
import {
  chargerParcours,
  demarrerParcours,
  type ParcoursInscription as Parcours,
} from "@/lib/inscriptionProgressive";
import { usePageTitle } from "@/hooks/usePageTitle";

const ProfilSoignant = lazy(() => import("./InscriptionSoignant"));
const ProfilEtablissement = lazy(() => import("./InscriptionEtablissement"));

export default function ParcoursInscription({
  completer = false,
}: {
  completer?: boolean;
}) {
  usePageTitle(completer ? "Compléter mes informations" : "Mon espace Jolene");
  const { user, session, loading: authLoading, deconnexion } = useAuth();
  const navigate = useNavigate();
  const userId = user?.id;
  const [parcours, setParcours] = useState<Parcours | null>(null);
  const [loading, setLoading] = useState(true);
  const [error, setError] = useState("");
  const [retry, setRetry] = useState(0);
  const intentionJson = JSON.stringify(
    session?.user.user_metadata?.inscription_progressive ?? null,
  );
  useEffect(() => {
    if (authLoading || !userId) return;
    let active = true;
    setLoading(true);
    setError("");
    (async () => {
      let data = await chargerParcours();
      const { data: role, error: roleError } =
        await supabase.rpc("fn_get_my_role");
      if (roleError) throw roleError;
      const roleMetier = (role as { role?: string } | null)?.role;
      if (roleMetier && roleMetier !== "INCONNU") {
        if (!active) return;
        navigate(
          roleMetier === "SOIGNANT" ? "/soignant/recherche-missions"
            : roleMetier === "ADMIN_ETABLISSEMENT" ? "/etablissement/tableau-de-bord" : "/",
          { replace: true },
        );
        return;
      }

      if (!data) {
        // Il s'agit d'une intention, pas d'un rôle : la RPC réserve le type et
        // ne peut ni créer un profil vérifié ni modifier un compte existant.
        const intention = JSON.parse(intentionJson);
        if (
          intention &&
          ["SOIGNANT", "ETABLISSEMENT"].includes(intention.type) &&
          intention.cgu === true
        ) {
          data = await demarrerParcours({
            type: intention.type,
            profession:
              typeof intention.profession === "string"
                ? intention.profession
                : "",
            nom: typeof intention.nom === "string" ? intention.nom : "",
            cgu: true,
            cgv: intention.cgv === true,
          });
        }
      }
      if (active) setParcours(data);
    })()
      .catch((e) => {
        if (active)
          setError(
            "Votre espace est momentanément indisponible. Réessayez.",
          );
      })
      .finally(() => {
        if (active) setLoading(false);
      });
    return () => {
      active = false;
    };
  }, [authLoading, userId, completer, navigate, retry, intentionJson]);
  if (authLoading) return <ChargementPage />;
  if (!user || !session) return <Navigate to="/connexion" replace />;
  if (loading) return <ChargementPage />;
  if (error || !parcours)
    return (
      <AuthLayout backTo="/connexion">
        <div className="card-base max-w-lg w-full space-y-4">
          <h1 className="text-xl font-bold">Reprendre votre inscription</h1>
          <p role={error ? "alert" : undefined}>
            {error ||
              "Choisissez votre espace pour terminer la création de votre compte."}
          </p>
          {error ? (
            <button
              className="btn-primary"
              onClick={() => setRetry((v) => v + 1)}
            >
              Réessayer
            </button>
          ) : (
            <>
              <Link
                className="btn-primary block text-center"
                to="/inscription/soignant"
              >
                Je suis soignant
              </Link>
              <Link
                className="btn-secondary block text-center"
                to="/inscription/etablissement"
              >
                Je représente un établissement
              </Link>
            </>
          )}
          <button className="btn-secondary" onClick={() => void deconnexion()}>
            Se déconnecter
          </button>
        </div>
      </AuthLayout>
    );
  if (completer) {
    if (!session.user.email_confirmed_at)
      return <Navigate to="/confirmer-email" replace />;
    return (
      <Suspense fallback={<ChargementPage />}>
        {parcours.type_compte === "SOIGNANT" ? (
          <ProfilSoignant parcours={parcours} />
        ) : (
          <ProfilEtablissement parcours={parcours} />
        )}
      </Suspense>
    );
  }
  return <Navigate to={parcours.type_compte === "SOIGNANT"
    ? "/soignant/recherche-missions" : "/etablissement/tableau-de-bord"} replace />;
}
