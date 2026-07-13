// Pro Santé Connect — étape 2 : échange le code, vérifie le JWT, crée ou lie le soignant,
// et redirige vers le frontend avec un token de session magique.
import { createClient } from "npm:@supabase/supabase-js@2.99.2";
import { createRemoteJWKSet, jwtVerify } from "npm:jose@5.9.6";
import {
  extractPscProfession,
  extractRppsEvidence,
  extractVerifiedEmail,
  isProfessionCompatible,
  type JoleneProfession,
  resolvePscEnvironment,
} from "../_shared/psc-security.ts";

const PSC_ENDPOINTS = {
  sandbox: {
    issuer: "https://auth.bas.esw.esante.gouv.fr/auth/realms/esante-wallet",
    token:
      "https://auth.bas.esw.esante.gouv.fr/auth/realms/esante-wallet/protocol/openid-connect/token",
    jwks:
      "https://auth.bas.esw.esante.gouv.fr/auth/realms/esante-wallet/protocol/openid-connect/certs",
    userinfo:
      "https://auth.bas.esw.esante.gouv.fr/auth/realms/esante-wallet/protocol/openid-connect/userinfo",
  },
  production: {
    issuer: "https://auth.esw.esante.gouv.fr/auth/realms/esante-wallet",
    token:
      "https://auth.esw.esante.gouv.fr/auth/realms/esante-wallet/protocol/openid-connect/token",
    jwks:
      "https://auth.esw.esante.gouv.fr/auth/realms/esante-wallet/protocol/openid-connect/certs",
    userinfo:
      "https://auth.esw.esante.gouv.fr/auth/realms/esante-wallet/protocol/openid-connect/userinfo",
  },
};

function redirectToFrontend(url: string, params: Record<string, string>) {
  const target = new URL(url);
  for (const [k, v] of Object.entries(params)) target.searchParams.set(k, v);
  return new Response(null, {
    status: 302,
    headers: { Location: target.toString() },
  });
}

type UnknownRecord = Record<string, unknown>;

interface ExistingSoignant {
  id: string;
  email: string | null;
  profession: string | null;
  numero_rpps: string | null;
  rpps_verifie: boolean | null;
  psc_sub: string | null;
}

function asRecord(value: unknown): UnknownRecord | null {
  return value !== null && typeof value === "object" && !Array.isArray(value)
    ? value as UnknownRecord
    : null;
}

function cleanName(value: unknown, uppercase = false): string {
  if (typeof value !== "string") return "";
  const normalized = value.trim().replace(/\s+/g, " ").slice(0, 120);
  return uppercase ? normalized.toLocaleUpperCase("fr-FR") : normalized;
}

function manualReview(callbackPage: string, message: string): Response {
  return redirectToFrontend(callbackPage, { status: "error", message });
}

function profileIsCompatible(
  profile: ExistingSoignant,
  pscProfession: JoleneProfession,
  verifiedRpps: string | null,
  pscSub: string,
): boolean {
  if (!isProfessionCompatible(profile.profession, pscProfession)) return false;
  if (profile.psc_sub && profile.psc_sub !== pscSub) return false;
  if (
    verifiedRpps && profile.numero_rpps && profile.numero_rpps !== verifiedRpps
  ) return false;
  return true;
}

Deno.serve(async (req) => {
  const appUrl = Deno.env.get("PSC_FRONTEND_URL") || "https://jolene.app";
  const callbackPage = `${appUrl}/auth/psc/callback`;

  try {
    const url = new URL(req.url);
    const code = url.searchParams.get("code");
    const state = url.searchParams.get("state");
    const error = url.searchParams.get("error");
    const errorDescription = url.searchParams.get("error_description");

    if (error) {
      return redirectToFrontend(callbackPage, {
        status: "error",
        message: errorDescription || error,
      });
    }

    if (
      !code || code.length > 4096 ||
      !state || !/^[A-Za-z0-9_-]{43}$/.test(state)
    ) {
      return redirectToFrontend(callbackPage, {
        status: "error",
        message: "Paramètres manquants",
      });
    }

    // Environnement explicite obligatoire : aucune bascule silencieuse vers BAS.
    const env = resolvePscEnvironment(Deno.env.get("PSC_ENVIRONMENT"));
    const clientId = Deno.env.get("PSC_CLIENT_ID");
    const clientSecret = Deno.env.get("PSC_CLIENT_SECRET");
    const redirectUri = Deno.env.get("PSC_REDIRECT_URI");
    const supabaseUrl = Deno.env.get("SUPABASE_URL");
    const serviceRoleKey = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY");

    if (
      !env || !clientId || !clientSecret || !redirectUri || !supabaseUrl ||
      !serviceRoleKey
    ) {
      return redirectToFrontend(callbackPage, {
        status: "error",
        message: "PSC non configuré côté serveur",
      });
    }

    const supabaseAdmin = createClient(
      supabaseUrl,
      serviceRoleKey,
      { auth: { persistSession: false } },
    );

    // 1. Consommer atomiquement la session OIDC. Deux callbacks concurrents ne
    // peuvent pas réutiliser le même state/code_verifier.
    const { data: session, error: sessionErr } = await supabaseAdmin
      .from("psc_auth_sessions")
      .delete()
      .eq("state", state)
      .select("nonce, code_verifier, intention, expire_le")
      .maybeSingle();

    if (sessionErr || !session) {
      return redirectToFrontend(callbackPage, {
        status: "error",
        message: "Session invalide ou expirée",
      });
    }

    if (new Date(session.expire_le) < new Date()) {
      return redirectToFrontend(callbackPage, {
        status: "error",
        message: "Session expirée",
      });
    }

    // 2. Échanger le code contre les tokens
    const tokenRes = await fetch(PSC_ENDPOINTS[env].token, {
      method: "POST",
      headers: { "Content-Type": "application/x-www-form-urlencoded" },
      body: new URLSearchParams({
        grant_type: "authorization_code",
        code,
        redirect_uri: redirectUri,
        client_id: clientId,
        client_secret: clientSecret,
        code_verifier: session.code_verifier,
      }),
      signal: AbortSignal.timeout(10_000),
    });

    if (!tokenRes.ok) {
      console.error("PSC token exchange failed:", tokenRes.status);
      return redirectToFrontend(callbackPage, {
        status: "error",
        message: "Échec de l'échange de code PSC",
      });
    }

    const tokens = asRecord(await tokenRes.json().catch(() => null));
    const idToken = typeof tokens?.id_token === "string" ? tokens.id_token : "";
    const accessToken = typeof tokens?.access_token === "string"
      ? tokens.access_token
      : "";
    if (!idToken || !accessToken) {
      return redirectToFrontend(callbackPage, {
        status: "error",
        message: "Réponse PSC invalide",
      });
    }

    // 3. Vérifier la signature du id_token avec JWKS PSC
    const jwks = createRemoteJWKSet(new URL(PSC_ENDPOINTS[env].jwks));
    const { payload } = await jwtVerify(idToken, jwks, {
      issuer: PSC_ENDPOINTS[env].issuer,
      audience: clientId,
      algorithms: ["RS256"],
    });

    // Vérifier le nonce
    if ((payload as any).nonce !== session.nonce) {
      return redirectToFrontend(callbackPage, {
        status: "error",
        message: "Nonce PSC invalide",
      });
    }

    const signedClaims = payload as UnknownRecord;
    const pscSub = typeof signedClaims.sub === "string"
      ? signedClaims.sub.trim()
      : "";
    if (!pscSub || pscSub.length > 512) {
      return redirectToFrontend(callbackPage, {
        status: "error",
        message: "Identifiant PSC manquant",
      });
    }

    // 4. UserInfo est requis pour les données professionnelles scope_all. Son
    // `sub` doit être strictement identique à celui du jeton signé (OIDC Core).
    let userinfo: UnknownRecord | null = null;
    try {
      const uiRes = await fetch(PSC_ENDPOINTS[env].userinfo, {
        headers: { Authorization: `Bearer ${accessToken}` },
        signal: AbortSignal.timeout(8_000),
      });
      if (!uiRes.ok) {
        console.error("PSC userinfo failed:", uiRes.status);
        return redirectToFrontend(callbackPage, {
          status: "error",
          message: "Données PSC indisponibles",
        });
      }
      userinfo = asRecord(await uiRes.json().catch(() => null));
    } catch (e) {
      console.warn(
        "PSC userinfo unavailable:",
        e instanceof Error ? e.name : "unknown",
      );
      return redirectToFrontend(callbackPage, {
        status: "error",
        message: "Données PSC indisponibles",
      });
    }

    if (!userinfo || userinfo.sub !== pscSub) {
      return redirectToFrontend(callbackPage, {
        status: "error",
        message: "Identité PSC incohérente",
      });
    }

    // 5. Preuves déterministes : code TRE_G15 explicite, RPPS complet + Luhn,
    // email utilisable uniquement avec email_verified=true.
    const professionEvidence = extractPscProfession(signedClaims, userinfo);
    if (!professionEvidence) {
      return manualReview(
        callbackPage,
        "Profession PSC non reconnue ou multiple. Vérification manuelle requise.",
      );
    }
    const profession = professionEvidence.profession;

    const rppsEvidence = extractRppsEvidence(signedClaims, userinfo);
    if (rppsEvidence.status === "invalid") {
      return manualReview(
        callbackPage,
        "Identifiant RPPS PSC incohérent. Vérification manuelle requise.",
      );
    }
    const rpps = rppsEvidence.status === "verified" ? rppsEvidence.rpps : null;

    const emailEvidence = extractVerifiedEmail(signedClaims, userinfo);
    if (emailEvidence.status === "invalid") {
      return manualReview(
        callbackPage,
        "Email PSC incohérent. Vérification manuelle requise.",
      );
    }
    const verifiedEmail = emailEvidence.status === "verified"
      ? emailEvidence.email
      : null;

    const prenom = cleanName(userinfo.given_name ?? signedClaims.given_name);
    const nom = cleanName(
      userinfo.family_name ?? signedClaims.family_name,
      true,
    );
    if (!prenom || !nom) {
      return manualReview(
        callbackPage,
        "Identité PSC incomplète. Vérification manuelle requise.",
      );
    }

    // 6. Chercher un soignant existant par psc_sub, puis par RPPS, puis par email
    let soignantId: string | null = null;
    let existingProfile: ExistingSoignant | null = null;
    let isNewUser = false;
    const profileSelect =
      "id, email, profession, numero_rpps, rpps_verifie, psc_sub";

    // 6.a. par psc_sub (lien déjà établi)
    const { data: byPscSub, error: byPscSubError } = await supabaseAdmin
      .from("soignants")
      .select(profileSelect)
      .eq("psc_sub", pscSub)
      .is("supprime_le", null)
      .maybeSingle();

    if (byPscSubError) throw new Error("PSC_PROFILE_LOOKUP_FAILED");

    if (byPscSub) {
      existingProfile = byPscSub as ExistingSoignant;
    } else if (rpps) {
      // 6.b. uniquement avec une preuve RPPS complète et valide.
      const { data: byRpps, error: byRppsError } = await supabaseAdmin
        .from("soignants")
        .select(profileSelect)
        .eq("numero_rpps", rpps)
        .is("supprime_le", null)
        .maybeSingle();
      if (byRppsError) throw new Error("PSC_PROFILE_LOOKUP_FAILED");
      if (byRpps) existingProfile = byRpps as ExistingSoignant;
    }

    if (!existingProfile && verifiedEmail) {
      // 6.c. Le rapprochement email est interdit sans `email_verified: true`.
      const { data: byEmail, error: byEmailError } = await supabaseAdmin
        .from("soignants")
        .select(profileSelect)
        // Les emails de profil sont normalisés en minuscules à l'inscription.
        // Une égalité stricte évite que `%` ou `_` dans un email OIDC soient
        // interprétés comme des jokers SQL par `ilike`.
        .eq("email", verifiedEmail)
        .is("supprime_le", null)
        .limit(2);
      if (byEmailError) throw new Error("PSC_PROFILE_LOOKUP_FAILED");
      if ((byEmail?.length ?? 0) > 1) {
        return manualReview(
          callbackPage,
          "Plusieurs comptes correspondent. Vérification manuelle requise.",
        );
      }
      if (byEmail?.[0]) existingProfile = byEmail[0] as ExistingSoignant;
    }

    if (existingProfile) {
      if (!profileIsCompatible(existingProfile, profession, rpps, pscSub)) {
        return manualReview(
          callbackPage,
          "Les informations PSC ne correspondent pas au compte existant. Vérification manuelle requise.",
        );
      }
      soignantId = existingProfile.id;
    }

    // 7. Créer un nouveau compte si aucun match
    if (!soignantId) {
      if (!verifiedEmail) {
        return manualReview(
          callbackPage,
          "Votre email PSC n'est pas vérifié. Vérification manuelle requise avant création du compte.",
        );
      }

      // Créer auth.user
      const { data: newUser, error: createErr } = await supabaseAdmin.auth.admin
        .createUser({
          email: verifiedEmail,
          email_confirm: true,
          app_metadata: { role: "SOIGNANT", auth_provider: "psc" },
          user_metadata: { prenom, nom, source: "psc" },
        });

      if (createErr || !newUser?.user) {
        console.error("Cannot create auth user:", createErr);
        return redirectToFrontend(callbackPage, {
          status: "error",
          message: "Impossible de créer le compte",
        });
      }

      soignantId = newUser.user.id;

      // Créer profil soignant
      const { error: profileErr } = await supabaseAdmin.from("soignants")
        .insert({
          id: soignantId,
          email: verifiedEmail,
          prenom,
          nom,
          profession,
          numero_rpps: rpps,
          rpps_verifie: rpps !== null,
          rpps_verifie_le: rpps ? new Date().toISOString() : null,
          rpps_nom_api: rpps ? nom : null,
          rpps_prenom_api: rpps ? prenom : null,
          rpps_profession_api: rpps ? profession : null,
          psc_sub: pscSub,
          psc_linked_le: new Date().toISOString(),
          psc_last_login: new Date().toISOString(),
        } as any);

      if (profileErr) {
        console.error("Cannot create soignant profile:", profileErr);
        await supabaseAdmin.auth.admin.deleteUser(soignantId);
        return redirectToFrontend(callbackPage, {
          status: "error",
          message: "Impossible de créer le profil",
        });
      }

      isNewUser = true;
    } else {
      // 8. Lier/actualiser le compte seulement après compatibilité profession,
      // PSC sub et éventuel RPPS. Une absence de preuve ne dégrade ni ne valide.
      const now = new Date().toISOString();
      const update: Record<string, unknown> = {
        psc_sub: pscSub,
        psc_linked_le: existingProfile?.psc_sub ? undefined : now,
        psc_last_login: now,
      };
      if (rpps) {
        update.numero_rpps = rpps;
        update.rpps_verifie = true;
        update.rpps_verifie_le = now;
        update.rpps_nom_api = nom;
        update.rpps_prenom_api = prenom;
        update.rpps_profession_api = profession;
      }
      for (const key of Object.keys(update)) {
        if (update[key] === undefined) delete update[key];
      }
      const { error: updateError } = await supabaseAdmin
        .from("soignants")
        .update(update)
        .eq("id", soignantId);
      if (updateError) throw new Error("PSC_PROFILE_UPDATE_FAILED");
    }

    // 9. Récupérer l'email de l'utilisateur pour générer un magic link
    const { data: userData, error: userError } = await supabaseAdmin.auth.admin
      .getUserById(soignantId);
    const userEmail = userData?.user?.email;
    if (userError || !userEmail) {
      return redirectToFrontend(callbackPage, {
        status: "error",
        message: "Email utilisateur introuvable",
      });
    }

    // 10. Générer un magic link (type=magiclink) pour créer la session côté frontend
    const { data: linkData, error: linkErr } = await supabaseAdmin.auth.admin
      .generateLink({
        type: "magiclink",
        email: userEmail,
      });

    if (linkErr || !linkData?.properties?.hashed_token) {
      console.error("generateLink error:", linkErr);
      return redirectToFrontend(callbackPage, {
        status: "error",
        message: "Impossible de créer la session",
      });
    }

    // 11. Rediriger vers le frontend avec le token_hash (le front appellera verifyOtp)
    return redirectToFrontend(callbackPage, {
      status: "success",
      token_hash: linkData.properties.hashed_token,
      new_user: isNewUser ? "1" : "0",
    });
  } catch (err: unknown) {
    console.error(
      "psc-callback error:",
      err instanceof Error ? err.name : "unknown",
    );
    return redirectToFrontend(callbackPage, {
      status: "error",
      message: "Erreur interne",
    });
  }
});
