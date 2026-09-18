import { lazy, Suspense, useEffect, useState } from "react";
import { Link, Navigate, useNavigate } from "react-router-dom";
import { ArrowRight, CheckCircle2, ShieldCheck } from "lucide-react";
import { useAuth } from "@/contexts/AuthContext";
import { AuthLayout } from "@/components/AuthLayout";
import { ChargementPage } from "@/components/ChargementPage";
import { LogoJolene } from "@/components/LogoJolene";
import { PROFESSIONS, getLabelProfession } from "@/lib/constantes";
import { supabase } from "@/integrations/supabase/client";
import {
  chargerParcours,
  demarrerParcours,
  enregistrerParcours,
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
  const [profilCree, setProfilCree] = useState(false);
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
        if (
          data?.type_compte === "ETABLISSEMENT" &&
          roleMetier === "ADMIN_ETABLISSEMENT" &&
          !completer
        )
          setProfilCree(true);
        else {
          navigate(
            roleMetier === "SOIGNANT"
              ? "/soignant/recherche-missions"
              : roleMetier === "ADMIN_ETABLISSEMENT"
                ? "/etablissement/tableau-de-bord"
                : "/",
            { replace: true },
          );
          return;
        }
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
            e?.message ||
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
  return (
    <AuthLayout showBack={false}>
      <div className="card-base max-w-2xl w-full space-y-6">
        <header className="flex justify-between items-center gap-3">
          <LogoJolene
            imageClassName="h-7 w-7"
            nomClassName="text-xl text-rose"
          />
          <button
            className="text-sm text-muted-foreground underline"
            onClick={() => void deconnexion()}
          >
            Se déconnecter
          </button>
        </header>
        {parcours.type_compte === "SOIGNANT" ? (
          <DecouverteSoignant parcours={parcours} />
        ) : (
          <BrouillonEtablissement
            parcours={parcours}
            profilCree={profilCree}
            onSave={setParcours}
          />
        )}
      </div>
    </AuthLayout>
  );
}

interface MissionDecouverte {
  id: string;
  profession_requise: string;
  ville: string | null;
  debut_le: string;
  fin_le: string;
}
function DecouverteSoignant({ parcours }: { parcours: Parcours }) {
  const navigate = useNavigate();
  const [ville, setVille] = useState("");
  const [recherche, setRecherche] = useState("");
  const [missions, setMissions] = useState<MissionDecouverte[]>([]);
  const [loading, setLoading] = useState(true);
  const [error, setError] = useState("");
  const [retry, setRetry] = useState(0);
  useEffect(() => {
    let active = true;
    setLoading(true);
    setError("");
    supabase
      .rpc("fn_missions_decouverte_inscription" as any, {
        p_ville: recherche || null,
      })
      .then(({ data, error }) => {
        if (!active) return;
        if (error)
          setError("Les missions ne peuvent pas être chargées. Réessayez.");
        else setMissions((data as unknown as MissionDecouverte[]) || []);
        setLoading(false);
      });
    return () => {
      active = false;
    };
  }, [recherche, retry]);
  const choisir = async (mission: MissionDecouverte) => {
    try {
      await enregistrerParcours({ missionChoisie: mission.id });
      navigate("/inscription/completer");
    } catch {
      setError("Votre choix n’a pas pu être enregistré. Réessayez.");
    }
  };
  return (
    <>
      <div>
        <p className="text-xs font-bold tracking-widest text-primary mb-2">
          VOTRE COMPTE EST CRÉÉ
        </p>
        <h1 className="text-2xl font-bold">Découvrez vos missions.</h1>
        <p className="text-muted-foreground mt-2">
          {getLabelProfession(String(parcours.donnees.profession || ""))}
        </p>
      </div>
      <form
        className="flex gap-2"
        onSubmit={(e) => {
          e.preventDefault();
          setRecherche(ville.trim());
        }}
      >
        <label className="sr-only" htmlFor="ville-recherche">
          Ville de recherche
        </label>
        <input
          id="ville-recherche"
          className="input-base min-w-0"
          autoComplete="address-level2"
          placeholder="Dans quelle ville ?"
          value={ville}
          onChange={(e) => setVille(e.target.value)}
        />
        <button className="btn-secondary">Rechercher</button>
      </form>
      {loading ? (
        <p role="status">Recherche de missions…</p>
      ) : error ? (
        <div role="alert">
          <p>{error}</p>
          <button
            className="btn-secondary mt-2"
            onClick={() => setRetry((v) => v + 1)}
          >
            Réessayer
          </button>
        </div>
      ) : missions.length ? (
        <div className="space-y-3">
          {missions.map((m) => (
            <button
              key={m.id}
              onClick={() => void choisir(m)}
              className="w-full text-left rounded-xl border border-border p-4 hover:bg-accent/40"
            >
              <strong className="block">
                {getLabelProfession(m.profession_requise)}
              </strong>
              <span className="block text-muted-foreground my-1">
                {m.ville || "France"} ·{" "}
                {new Intl.DateTimeFormat("fr-FR", {
                  dateStyle: "medium",
                }).format(new Date(m.debut_le))}
              </span>
              <span className="text-sm text-primary font-semibold">
                Préparer ma candidature →
              </span>
            </button>
          ))}
        </div>
      ) : (
        <p className="p-4 rounded-xl bg-muted">
          Aucune mission disponible{" "}
          {recherche ? "dans cette ville" : "pour votre profession"} pour le
          moment. Vous pouvez déjà préparer votre profil.
        </p>
      )}
      <Link
        to="/inscription/completer"
        className="flex gap-3 p-4 rounded-xl bg-primary/5 items-center"
      >
        <ShieldCheck className="text-primary shrink-0" />
        <span>
          <strong className="block">Compléter mon profil</strong>
          <span className="text-sm text-muted-foreground">
            À faire lorsque vous souhaitez candidater
          </span>
        </span>
        <ArrowRight className="ml-auto shrink-0" />
      </Link>
    </>
  );
}

function dateLisible(value: string) {
  const date = new Date(value);
  return Number.isNaN(date.getTime())
    ? "Date à compléter"
    : new Intl.DateTimeFormat("fr-FR", { dateStyle: "medium" }).format(date);
}
function texte(value: unknown) {
  return typeof value === "string" ? value : "";
}
function BrouillonEtablissement({
  parcours,
  profilCree,
  onSave,
}: {
  parcours: Parcours;
  profilCree: boolean;
  onSave: (p: Parcours) => void;
}) {
  const d = parcours.donnees;
  const [editing, setEditing] = useState(!d.brouillonMission);
  const [form, setForm] = useState({
    missionProfession: texte(d.missionProfession),
    missionVille: texte(d.missionVille),
    missionDate: texte(d.missionDate),
    missionDebut: texte(d.missionDebut),
    missionFin: texte(d.missionFin),
  });
  const [error, setError] = useState("");
  const [busy, setBusy] = useState(false);
  const save = async (e: React.FormEvent) => {
    e.preventDefault();
    setError("");
    if (
      !form.missionProfession ||
      !form.missionVille.trim() ||
      !form.missionDate
    ) {
      setError("Renseignez la profession, la ville et la date de début.");
      return;
    }
    if (
      form.missionDebut &&
      form.missionFin &&
      form.missionDebut === form.missionFin
    ) {
      setError("Les heures de début et de fin doivent être différentes.");
      return;
    }
    setBusy(true);
    try {
      onSave(await enregistrerParcours({ ...form, brouillonMission: true }));
      setEditing(false);
    } catch {
      setError(
        "Le brouillon n’a pas pu être enregistré. Votre saisie est conservée ; réessayez.",
      );
    } finally {
      setBusy(false);
    }
  };
  return (
    <>
      <div>
        <p className="text-xs font-bold tracking-widest text-primary mb-2">
          VOTRE ESPACE ÉTABLISSEMENT
        </p>
        <h1 className="text-2xl font-bold">
          {editing
            ? "Préparez votre première mission."
            : "Votre brouillon est enregistré."}
        </h1>
        <p className="text-muted-foreground mt-2">
          {texte(d.nom)} · Votre besoin reste privé jusqu’à la publication.
        </p>
      </div>
      {editing ? (
        <form onSubmit={save} noValidate className="space-y-4">
          <div>
            <label
              className="text-sm font-medium block mb-1.5"
              htmlFor="missionProfession"
            >
              Profession recherchée
            </label>
            <select
              id="missionProfession"
              className="input-base"
              value={form.missionProfession}
              onChange={(e) =>
                setForm((v) => ({ ...v, missionProfession: e.target.value }))
              }
            >
              <option value="">Choisir une profession</option>
              {PROFESSIONS.map((p) => (
                <option key={p.valeur} value={p.valeur}>
                  {p.label}
                </option>
              ))}
            </select>
          </div>
          {(
            [
              "missionVille",
              "missionDate",
              "missionDebut",
              "missionFin",
            ] as const
          ).map((key, i) => (
            <div key={key}>
              <label htmlFor={key} className="text-sm font-medium block mb-1.5">
                {
                  [
                    "Ville de la mission",
                    "Date de début",
                    "Heure de début (facultatif)",
                    "Heure de fin (facultatif)",
                  ][i]
                }
              </label>
              <input
                id={key}
                className="input-base"
                type={i === 0 ? "text" : i === 1 ? "date" : "time"}
                value={form[key]}
                onChange={(e) =>
                  setForm((v) => ({ ...v, [key]: e.target.value }))
                }
              />
            </div>
          ))}
          {error && (
            <p className="text-destructive text-sm" role="alert">
              {error}
            </p>
          )}
          <button disabled={busy} className="btn-primary w-full">
            {busy ? "Enregistrement…" : "Enregistrer le brouillon"}
          </button>
          <p className="text-xs text-muted-foreground text-center">
            Ce brouillon n’est pas visible par les soignants.
          </p>
        </form>
      ) : (
        <div className="rounded-xl bg-primary/5 p-5 space-y-3">
          <p className="text-primary flex gap-2 items-center">
            <CheckCircle2 size={20} />
            Brouillon · non publié
          </p>
          <strong className="block">
            {getLabelProfession(form.missionProfession)}
          </strong>
          <p>
            {form.missionVille} · {dateLisible(`${form.missionDate}T12:00:00`)}
          </p>
          <p>
            {form.missionDebut && form.missionFin
              ? `${form.missionDebut}–${form.missionFin}`
              : "Horaires à compléter"}
          </p>
          <button
            className="text-primary underline"
            onClick={() => setEditing(true)}
          >
            Modifier le brouillon
          </button>
        </div>
      )}
      {profilCree ? (
        <>
          <Link
            to="/etablissement/missions/creer?inscription=1"
            className="btn-primary block text-center"
          >
            Reprendre ce brouillon dans mon espace
          </Link>
          <Link
            to="/etablissement/activer"
            className="btn-secondary block text-center"
          >
            Suivre l’activation de mon établissement
          </Link>
        </>
      ) : (
        <Link
          to="/inscription/completer"
          className="btn-secondary flex gap-2 items-center justify-center"
        >
          <ShieldCheck size={20} />
          Activer mon établissement
        </Link>
      )}
      <p className="text-sm text-muted-foreground">
        Les informations de l’établissement et les vérifications se complètent
        avant votre première publication.
      </p>
    </>
  );
}
