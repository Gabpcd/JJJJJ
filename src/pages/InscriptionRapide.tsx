import { useState } from "react";
import { Link, useNavigate } from "react-router-dom";
import { ArrowRight, Eye, EyeOff, Loader2 } from "lucide-react";
import { AuthLayout } from "@/components/AuthLayout";
import { LogoJolene } from "@/components/LogoJolene";
import { BoutonProSanteConnect } from "@/components/BoutonProSanteConnect";
import {
  CaptchaTurnstile,
  TURNSTILE_REQUIRED,
} from "@/components/CaptchaTurnstile";
import { SwitchTypeInscription } from "@/components/inscription/SwitchTypeInscription";
import { PROFESSIONS } from "@/lib/constantes";
import {
  creerCompteRapide,
  type TypeCompteInscription,
} from "@/lib/inscriptionProgressive";
import { usePageTitle } from "@/hooks/usePageTitle";

export default function InscriptionRapide({
  type,
}: {
  type: TypeCompteInscription;
}) {
  const navigate = useNavigate();
  const soignant = type === "SOIGNANT";
  usePageTitle(
    soignant ? "Créer mon compte soignant" : "Créer mon compte établissement",
  );
  const [form, setForm] = useState({
    email: "",
    password: "",
    profession: "",
    nom: "",
    cgu: false,
    cgv: false,
  });
  const [visible, setVisible] = useState(false);
  const [busy, setBusy] = useState(false);
  const [confirmation, setConfirmation] = useState(false);
  const [connexionCompte, setConnexionCompte] = useState(false);
  const [errors, setErrors] = useState<Record<string, string>>({});
  const [serviceError, setServiceError] = useState("");
  const [captcha, setCaptcha] = useState<string | null>(null);
  const [captchaVersion, setCaptchaVersion] = useState(0);
  const change = (key: keyof typeof form, value: string | boolean) =>
    setForm((v) => ({ ...v, [key]: value }));
  const submit = async (event: React.FormEvent) => {
    event.preventDefault();
    if (busy) return;
    const next: Record<string, string> = {};
    if (!/^[^\s@]+@[^\s@]+\.[^\s@]+$/.test(form.email.trim()))
      next.email = "Saisissez une adresse email valide.";
    if (form.password.length < 8)
      next.password = "Choisissez un mot de passe de 8 caractères minimum.";
    if (soignant && !form.profession)
      next.profession = "Choisissez votre profession.";
    if (!soignant && !form.nom.trim())
      next.nom = "Indiquez le nom de votre établissement.";
    if (!form.cgu)
      next.cgu = "Acceptez les conditions pour créer votre compte.";
    if (!soignant && !form.cgv)
      next.cgv = "Acceptez les conditions générales de vente.";
    if (TURNSTILE_REQUIRED && !captcha)
      next.captcha = "Terminez la vérification de sécurité.";
    setErrors(next);
    setServiceError("");
    if (Object.keys(next).length) {
      document.getElementById(Object.keys(next)[0])?.focus();
      return;
    }
    setBusy(true);
    try {
      const result = await creerCompteRapide(
        { ...form, type, captchaToken: captcha || undefined },
        confirmation || connexionCompte,
      );
      if (result === "confirmation") setConfirmation(true);
      else {
        setForm((v) => ({ ...v, password: "" }));
        navigate("/inscription/reprendre", { replace: true });
      }
    } catch (error) {
      if ((error as { code?: string })?.code === "SIGN_IN_REQUIRED")
        setConnexionCompte(true);
      const message =
        error instanceof Error
          ? error.message
          : (error as { message?: string })?.message || "";
      setServiceError(
        /ACCOUNT_ALREADY_REGISTERED|ACCOUNT_TYPE_MISMATCH|ACCOUNT_REGISTRATION_INCOMPLETE/.test(
          message,
        )
          ? "Ce compte possède déjà un espace Jolene. Connectez-vous pour le retrouver."
          : /email.*not.*confirmed/i.test(message)
            ? "Votre email n’est pas encore confirmé. Ouvrez le lien reçu, puis réessayez."
            : /invalid.*credentials/i.test(message)
              ? "Vérifiez vos identifiants ou utilisez « Se connecter »."
              : message ||
                "La connexion a été interrompue. Votre saisie est conservée ; réessayez.",
      );
    } finally {
      setBusy(false);
      setCaptcha(null);
      setCaptchaVersion((v) => v + 1);
    }
  };
  const error = (key: string) =>
    errors[key] && (
      <p id={`${key}-erreur`} className="text-sm text-destructive" role="alert">
        {errors[key]}
      </p>
    );
  return (
    <AuthLayout backTo="/connexion">
      <div className="card-base max-w-lg w-full space-y-5">
        <LogoJolene
          className="mx-auto flex w-fit"
          imageClassName="h-7 w-7"
          nomClassName="text-xl text-rose"
        />
        <div>
          <h1 className="text-2xl font-bold text-foreground">
            Créez votre compte.
          </h1>
          <p className="text-muted-foreground mt-2">
            {soignant
              ? "Découvrez les missions. Votre dossier professionnel se complète ensuite."
              : "Préparez votre première mission. Les vérifications viendront avant sa publication."}
          </p>
        </div>
        <SwitchTypeInscription
          actif={soignant ? "soignant" : "etablissement"}
        />
        {soignant && (
          <div className="space-y-2">
            <BoutonProSanteConnect
              intention="signup"
              onSwitchToEmail={() => document.getElementById("email")?.focus()}
            />
            <p className="text-center text-sm text-muted-foreground">
              ou avec votre email
            </p>
          </div>
        )}
        <form onSubmit={submit} noValidate className="space-y-4">
          <div>
            <label htmlFor="email" className="text-sm font-medium block mb-1.5">
              Email
            </label>
            <input
              id="email"
              type="email"
              autoComplete="email"
              className="input-base"
              value={form.email}
              onChange={(e) => {
                change("email", e.target.value);
                setConfirmation(false);
                setConnexionCompte(false);
              }}
              aria-invalid={!!errors.email}
              aria-describedby={errors.email ? "email-erreur" : undefined}
            />
            {error("email")}
          </div>
          <div>
            <label
              htmlFor="password"
              className="text-sm font-medium block mb-1.5"
            >
              Mot de passe
            </label>
            <div className="relative">
              <input
                id="password"
                type={visible ? "text" : "password"}
                autoComplete="new-password"
                className="input-base pr-12"
                value={form.password}
                onChange={(e) => change("password", e.target.value)}
                aria-invalid={!!errors.password}
                aria-describedby="password-aide"
              />
              <button
                className="absolute right-1 inset-y-0 px-3"
                type="button"
                aria-label={
                  visible
                    ? "Masquer le mot de passe"
                    : "Afficher le mot de passe"
                }
                aria-pressed={visible}
                onClick={() => setVisible((v) => !v)}
              >
                {visible ? <EyeOff size={20} /> : <Eye size={20} />}
              </button>
            </div>
            <p
              id="password-aide"
              className="text-sm text-muted-foreground mt-1"
            >
              8 caractères minimum
            </p>
            {error("password")}
          </div>
          {soignant ? (
            <div>
              <label
                htmlFor="profession"
                className="text-sm font-medium block mb-1.5"
              >
                Profession
              </label>
              <select
                id="profession"
                className="input-base"
                value={form.profession}
                onChange={(e) => change("profession", e.target.value)}
                aria-invalid={!!errors.profession}
              >
                <option value="">Choisir ma profession</option>
                {PROFESSIONS.map((p) => (
                  <option key={p.valeur} value={p.valeur}>
                    {p.label}
                  </option>
                ))}
              </select>
              {error("profession")}
            </div>
          ) : (
            <div>
              <label htmlFor="nom" className="text-sm font-medium block mb-1.5">
                Nom de l’établissement
              </label>
              <input
                id="nom"
                maxLength={200}
                autoComplete="organization"
                className="input-base"
                value={form.nom}
                onChange={(e) => change("nom", e.target.value)}
                aria-invalid={!!errors.nom}
              />
              {error("nom")}
            </div>
          )}
          <label className="flex min-h-11 gap-3 items-start py-2 text-sm">
            <input
              id="cgu"
              type="checkbox"
              checked={form.cgu}
              onChange={(e) => change("cgu", e.target.checked)}
              className="h-5 w-5 shrink-0 accent-primary"
            />
            <span>
              J’accepte les{" "}
              <a
                href="/cgu"
                target="_blank"
                rel="noopener noreferrer"
                className="text-primary underline"
              >
                CGU
              </a>{" "}
              et la{" "}
              <a
                href="/confidentialite"
                target="_blank"
                rel="noopener noreferrer"
                className="text-primary underline"
              >
                politique de confidentialité
              </a>
              .
            </span>
          </label>
          {error("cgu")}
          {!soignant && (
            <>
              <label className="flex min-h-11 gap-3 items-start py-2 text-sm">
                <input
                  id="cgv"
                  type="checkbox"
                  checked={form.cgv}
                  onChange={(e) => change("cgv", e.target.checked)}
                  className="h-5 w-5 shrink-0 accent-primary"
                />
                <span>
                  J’accepte les{" "}
                  <a
                    href="/cgv"
                    target="_blank"
                    rel="noopener noreferrer"
                    className="text-primary underline"
                  >
                    conditions générales de vente
                  </a>
                  .
                </span>
              </label>
              {error("cgv")}
            </>
          )}
          <CaptchaTurnstile
            key={captchaVersion}
            onVerify={setCaptcha}
            onExpire={() => setCaptcha(null)}
            onError={() => setCaptcha(null)}
          />
          {error("captcha")}
          {confirmation && (
            <p className="p-4 rounded-xl bg-primary/5 text-sm" role="status">
              Un lien de confirmation vient de vous être envoyé. Ouvrez-le pour
              accéder à votre espace. Vous pouvez aussi revenir ici après
              confirmation.
            </p>
          )}
          {serviceError && (
            <p
              className="p-3 rounded-xl border border-destructive text-destructive text-sm"
              role="alert"
            >
              {serviceError}
            </p>
          )}
          <button
            type="submit"
            disabled={busy}
            className="btn-primary w-full flex justify-center items-center gap-2"
            aria-busy={busy}
          >
            {busy ? (
              <Loader2 className="animate-spin" size={18} />
            ) : (
              <ArrowRight size={18} />
            )}
            {busy
              ? "Création du compte…"
              : connexionCompte
                ? "Se connecter et continuer"
                : confirmation
                  ? "J’ai confirmé mon email"
                  : "Créer mon compte"}
          </button>
          <p className="text-xs text-center text-muted-foreground">
            {soignant
              ? "Aucun document à préparer maintenant."
              : "Aucun SIRET ni document à préparer maintenant."}
          </p>
        </form>
        <p className="text-sm text-center">
          Déjà un compte ?{" "}
          <Link to="/connexion" className="text-primary underline">
            Se connecter
          </Link>
        </p>
      </div>
    </AuthLayout>
  );
}
