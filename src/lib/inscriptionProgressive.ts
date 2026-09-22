import { supabase } from "@/integrations/supabase/client";
import { extraireErreurEdgeFn } from "@/lib/erreurs";
import { getAttribution } from "@/lib/attribution";
import { reinitialiserCacheRole } from "@/hooks/useRole";

export type TypeCompteInscription = "SOIGNANT" | "ETABLISSEMENT";
export interface ParcoursInscription {
  user_id: string;
  type_compte: TypeCompteInscription;
  donnees: Record<string, unknown>;
  modifie_le: string;
}

export interface CompteRapideInput {
  type: TypeCompteInscription;
  email: string;
  password: string;
  profession: string;
  nom: string;
  cgu: boolean;
  cgv: boolean;
  captchaToken?: string;
}

export async function demarrerParcours(
  input: Omit<CompteRapideInput, "email" | "password" | "captchaToken">,
) {
  const { data, error } = await supabase.rpc("fn_demarrer_inscription" as any, {
    p_type_compte: input.type,
    p_profession: input.profession || null,
    p_nom: input.nom || null,
    p_cgu: input.cgu,
    p_cgv: input.cgv,
  });
  if (error) throw error;
  reinitialiserCacheRole();
  return data as unknown as ParcoursInscription;
}

export async function creerCompteRapide(
  input: CompteRapideInput,
  confirmer = false,
): Promise<"confirmation" | "cree"> {
  const email = input.email.trim().toLowerCase();
  const intention = {
    type: input.type,
    profession: input.profession,
    nom: input.nom,
    cgu: input.cgu,
    cgv: input.cgv,
  };
  const options = input.captchaToken
    ? { captchaToken: input.captchaToken }
    : {};
  const {
    data: { session: existante },
  } = await supabase.auth.getSession();
  if (existante?.user.email?.trim().toLowerCase() === email) {
    await demarrerParcours(intention);
    return "cree";
  }
  const response = confirmer
    ? await supabase.auth.signInWithPassword({
        email,
        password: input.password,
        options,
      })
    : await supabase.auth.signUp({
        email,
        password: input.password,
        options: {
          ...options,
          data: { inscription_progressive: intention },
          emailRedirectTo: "https://jolene.app/inscription/confirmer",
        },
      });
  const compteExistant =
    response.error &&
    /already.*registered|user.*registered/i.test(response.error.message);
  const fauxUtilisateur =
    !response.error &&
    !response.data.session &&
    response.data.user?.identities?.length === 0;
  if (compteExistant || fauxUtilisateur) {
    // Ne jamais consommer une seconde fois le même jeton Turnstile. Le prochain
    // clic utilise signIn avec un widget renouvelé par le formulaire.
    throw Object.assign(
      new Error(
        "Ce compte existe déjà. Cliquez sur « Se connecter et continuer » pour le reprendre.",
      ),
      { code: "SIGN_IN_REQUIRED" },
    );
  }
  if (response.error) throw response.error;
  if (!response.data.session) return "confirmation";
  await demarrerParcours(intention);
  return "cree";
}

export async function chargerParcours(): Promise<ParcoursInscription | null> {
  const {
    data: { user },
    error: authError,
  } = await supabase.auth.getUser();
  if (authError) throw authError;
  if (!user) return null;
  const { data, error } = await supabase
    .from("parcours_inscription" as any)
    .select("user_id,type_compte,donnees,modifie_le")
    .eq("user_id", user.id)
    .maybeSingle();
  if (error) throw error;
  return data as unknown as ParcoursInscription | null;
}

export async function enregistrerParcours(donnees: Record<string, unknown>) {
  const { data, error } = await supabase.rpc(
    "fn_enregistrer_parcours_inscription" as any,
    { p_donnees: donnees },
  );
  if (error) throw error;
  return data as unknown as ParcoursInscription;
}

export function restaurerFormulaire<T extends Record<string, unknown>>(
  initial: T,
  donnees: Record<string, unknown>,
): T {
  const result = { ...initial };
  for (const key of Object.keys(initial)) {
    if (["email", "motDePasse", "confirmMdp", "lat", "lng"].includes(key))
      continue;
    const value = donnees[key];
    if (key === "estSalarieEtablissement" && typeof value === "boolean") {
      (result as Record<string, unknown>)[key] = value;
      continue;
    }
    if (
      Array.isArray(initial[key])
        ? Array.isArray(value) && value.every((v) => typeof v === "string")
        : typeof initial[key] === typeof value &&
          value !== undefined &&
          value !== null
    ) {
      (result as Record<string, unknown>)[key] = value;
    }
  }
  return result;
}

export function donneesFormulaire(form: Record<string, unknown>) {
  return Object.fromEntries(
    Object.entries(form).filter(
      ([key]) =>
        ![
          "email",
          "motDePasse",
          "confirmMdp",
          "lat",
          "lng",
          "turnstileToken",
          "etudiant_details",
        ].includes(key),
    ),
  );
}

export async function finaliserProfil(
  type: TypeCompteInscription,
  form: Record<string, any>,
) {
  const {
    data: { session },
  } = await supabase.auth.getSession();
  if (!session)
    throw new Error("Reconnectez-vous pour reprendre votre inscription.");
  await enregistrerParcours(donneesFormulaire(form));
  const body =
    type === "SOIGNANT"
      ? {
          prenom: form.prenom,
          nom: form.nom,
          telephone: form.telephone || null,
          dateNaissance: form.dateNaissance,
          profession: form.profession,
          typesContrat: form.typesContrat,
          rpps: form.rpps || null,
          rayon: form.rayon,
          est_etudiant: form.estEtudiant ?? false,
          etudiant_details: form.etudiant_details || null,
        }
      : {
          nom: form.nom,
          siret: form.siret,
          finess: form.finess || null,
          type: form.type,
          adresse_rue: form.rue || null,
          adresse_ville: form.ville,
          adresse_code_postal: form.codePostal || null,
          adresse_departement: form.departement || null,
          email_contact: form.emailContact || session.user.email,
          telephone_contact: form.telephoneContact || null,
          numero_licence: form.numeroLicence || null,
        };
  const { data, error } = await supabase.functions.invoke(
    type === "SOIGNANT" ? "register-soignant" : "register-etablissement",
    {
      headers: { Authorization: `Bearer ${session.access_token}` },
      body: {
        ...body,
        navigateur: navigator.userAgent,
        attribution: getAttribution(),
      },
    },
  );
  const result =
    data ?? (error ? await extraireErreurEdgeFn(null, error) : null);
  if (error || result?.ok === false || result?.error) {
    throw Object.assign(
      new Error(
        result?.message ||
          result?.error ||
          "Votre saisie est conservée. Réessayez.",
      ),
      {
        code: result?.code,
        details: result?.details,
      },
    );
  }
  reinitialiserCacheRole();
  const { error: refreshError } = await supabase.auth.refreshSession();
  if (refreshError)
    throw new Error(
      "Votre profil est enregistré. Reconnectez-vous pour ouvrir votre espace.",
    );
}
