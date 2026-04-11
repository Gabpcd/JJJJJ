// Pro Santé Connect — étape 2 : échange le code, vérifie le JWT, crée ou lie le soignant,
// et redirige vers le frontend avec un token de session magique.
import { createClient } from "npm:@supabase/supabase-js@2";
import { jwtVerify, createRemoteJWKSet } from "npm:jose@5.9.6";

const PSC_ENDPOINTS = {
  sandbox: {
    issuer: "https://auth.bas.psc.esante.gouv.fr/auth/realms/esante-wallet",
    token: "https://auth.bas.psc.esante.gouv.fr/auth/realms/esante-wallet/protocol/openid-connect/token",
    jwks: "https://auth.bas.psc.esante.gouv.fr/auth/realms/esante-wallet/protocol/openid-connect/certs",
    userinfo: "https://auth.bas.psc.esante.gouv.fr/auth/realms/esante-wallet/protocol/openid-connect/userinfo",
  },
  production: {
    issuer: "https://auth.esw.esante.gouv.fr/auth/realms/esante-wallet",
    token: "https://auth.esw.esante.gouv.fr/auth/realms/esante-wallet/protocol/openid-connect/token",
    jwks: "https://auth.esw.esante.gouv.fr/auth/realms/esante-wallet/protocol/openid-connect/certs",
    userinfo: "https://auth.esw.esante.gouv.fr/auth/realms/esante-wallet/protocol/openid-connect/userinfo",
  },
};

// Mapping des professions PSC → enum Jolene type_profession
// Les codes professions PSC suivent la nomenclature ANS (table G_15)
function mapPscProfessionToJolene(code?: string, libelle?: string): string | null {
  const c = (code || "").toString();
  const l = (libelle || "").toLowerCase();
  // Médecin
  if (c === "10" || l.includes("médecin") || l.includes("medecin")) return "MEDECIN";
  // Chirurgien-dentiste
  if (c === "40" || l.includes("dentiste")) return "DENTISTE";
  // Pharmacien
  if (c === "21" || l.includes("pharmacien")) return "PHARMACIEN";
  // Sage-femme
  if (c === "50" || l.includes("sage")) return "SAGE_FEMME";
  // Infirmier
  if (c === "60" || l.includes("infirm")) return "IDE";
  // Kiné
  if (c === "70" || l.includes("kiné") || l.includes("kine") || l.includes("masseur")) return "KINE";
  // Aide-soignant
  if (c === "93" || l.includes("aide-soignant") || l.includes("aide soignant")) return "AS";
  // Auxiliaire puériculture
  if (l.includes("puéricult") || l.includes("puericult")) return "AP";
  // Défaut : IDE (le plus commun)
  return "IDE";
}

function redirectToFrontend(url: string, params: Record<string, string>) {
  const target = new URL(url);
  for (const [k, v] of Object.entries(params)) target.searchParams.set(k, v);
  return new Response(null, { status: 302, headers: { Location: target.toString() } });
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

    if (!code || !state) {
      return redirectToFrontend(callbackPage, { status: "error", message: "Paramètres manquants" });
    }

    const env = (Deno.env.get("PSC_ENVIRONMENT") || "sandbox") as "sandbox" | "production";
    const clientId = Deno.env.get("PSC_CLIENT_ID");
    const clientSecret = Deno.env.get("PSC_CLIENT_SECRET");
    const redirectUri = Deno.env.get("PSC_REDIRECT_URI");

    if (!clientId || !clientSecret || !redirectUri) {
      return redirectToFrontend(callbackPage, { status: "error", message: "PSC non configuré côté serveur" });
    }

    const supabaseAdmin = createClient(
      Deno.env.get("SUPABASE_URL") ?? "",
      Deno.env.get("SUPABASE_SERVICE_ROLE_KEY") ?? "",
      { auth: { persistSession: false } }
    );

    // 1. Récupérer la session OIDC stockée (code_verifier, nonce, intention)
    const { data: session, error: sessionErr } = await supabaseAdmin
      .from("psc_auth_sessions")
      .select("nonce, code_verifier, intention, expire_le")
      .eq("state", state)
      .maybeSingle();

    if (sessionErr || !session) {
      return redirectToFrontend(callbackPage, { status: "error", message: "Session invalide ou expirée" });
    }

    if (new Date(session.expire_le) < new Date()) {
      await supabaseAdmin.from("psc_auth_sessions").delete().eq("state", state);
      return redirectToFrontend(callbackPage, { status: "error", message: "Session expirée" });
    }

    // Supprimer la session une fois consommée
    await supabaseAdmin.from("psc_auth_sessions").delete().eq("state", state);

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
    });

    if (!tokenRes.ok) {
      const errBody = await tokenRes.text();
      console.error("PSC token exchange failed:", tokenRes.status, errBody);
      return redirectToFrontend(callbackPage, { status: "error", message: "Échec de l'échange de code PSC" });
    }

    const tokens = await tokenRes.json();
    const idToken = tokens.id_token as string;
    const accessToken = tokens.access_token as string;

    // 3. Vérifier la signature du id_token avec JWKS PSC
    const jwks = createRemoteJWKSet(new URL(PSC_ENDPOINTS[env].jwks));
    const { payload } = await jwtVerify(idToken, jwks, {
      issuer: PSC_ENDPOINTS[env].issuer,
      audience: clientId,
    });

    // Vérifier le nonce
    if ((payload as any).nonce !== session.nonce) {
      return redirectToFrontend(callbackPage, { status: "error", message: "Nonce PSC invalide" });
    }

    // 4. Enrichir avec les userinfo (pour obtenir RPPS/profession détaillée)
    let userinfo: Record<string, unknown> = {};
    try {
      const uiRes = await fetch(PSC_ENDPOINTS[env].userinfo, {
        headers: { Authorization: `Bearer ${accessToken}` },
      });
      if (uiRes.ok) userinfo = await uiRes.json();
    } catch (e) {
      console.warn("PSC userinfo failed:", e);
    }

    // 5. Extraire les infos soignant (les claims peuvent varier selon la carte CPS/e-CPS)
    const claims = { ...(payload as any), ...userinfo };
    const pscSub = String(claims.sub || "");
    const rpps = String(claims.preferred_username || claims.SubjectRefPro?.exercices?.[0]?.numeroIdentificationPP || claims.numeroIdentificationPP || claims.given_name_id || "").replace(/^8/, "").substring(0, 11);
    const prenom = String(claims.given_name || claims.firstName || "");
    const nom = String(claims.family_name || claims.lastName || "").toUpperCase();
    const email = (claims.email as string) || null;
    const professionCode = claims.SubjectRefPro?.exercices?.[0]?.codeProfession || claims.codeProfession;
    const professionLibelle = claims.SubjectRefPro?.exercices?.[0]?.libelleProfession || claims.libelleProfession;
    const profession = mapPscProfessionToJolene(professionCode, professionLibelle);

    if (!pscSub) {
      return redirectToFrontend(callbackPage, { status: "error", message: "Identifiant PSC manquant" });
    }

    // 6. Chercher un soignant existant par psc_sub, puis par RPPS, puis par email
    let soignantId: string | null = null;
    let isNewUser = false;

    // 6.a. par psc_sub (lien déjà établi)
    const { data: byPscSub } = await supabaseAdmin
      .from("soignants")
      .select("id, email")
      .eq("psc_sub", pscSub)
      .is("supprime_le", null)
      .maybeSingle();

    if (byPscSub) {
      soignantId = byPscSub.id;
    } else if (rpps) {
      // 6.b. par RPPS (premier login PSC d'un soignant déjà inscrit manuellement)
      const { data: byRpps } = await supabaseAdmin
        .from("soignants")
        .select("id, email")
        .eq("numero_rpps", rpps)
        .is("supprime_le", null)
        .maybeSingle();
      if (byRpps) soignantId = byRpps.id;
    }

    if (!soignantId && email) {
      // 6.c. par email (fallback)
      const { data: byEmail } = await supabaseAdmin
        .from("soignants")
        .select("id")
        .eq("email", email)
        .is("supprime_le", null)
        .maybeSingle();
      if (byEmail) soignantId = byEmail.id;
    }

    // 7. Créer un nouveau compte si aucun match
    if (!soignantId) {
      if (!email) {
        return redirectToFrontend(callbackPage, {
          status: "error",
          message: "Votre carte PSC ne fournit pas d'email. Contactez le support.",
        });
      }
      if (!profession) {
        return redirectToFrontend(callbackPage, { status: "error", message: "Profession PSC non reconnue" });
      }

      // Créer auth.user
      const { data: newUser, error: createErr } = await supabaseAdmin.auth.admin.createUser({
        email,
        email_confirm: true,
        app_metadata: { role: "SOIGNANT", auth_provider: "psc" },
        user_metadata: { prenom, nom, source: "psc" },
      });

      if (createErr || !newUser?.user) {
        console.error("Cannot create auth user:", createErr);
        return redirectToFrontend(callbackPage, { status: "error", message: "Impossible de créer le compte" });
      }

      soignantId = newUser.user.id;

      // Créer profil soignant
      const { error: profileErr } = await supabaseAdmin.from("soignants").insert({
        id: soignantId,
        email,
        prenom,
        nom,
        profession: profession as any,
        numero_rpps: rpps || null,
        rpps_verifie: !!rpps,
        rpps_verifie_le: rpps ? new Date().toISOString() : null,
        rpps_nom_api: nom,
        rpps_prenom_api: prenom,
        rpps_profession_api: profession,
        psc_sub: pscSub,
        psc_linked_le: new Date().toISOString(),
        psc_last_login: new Date().toISOString(),
      } as any);

      if (profileErr) {
        console.error("Cannot create soignant profile:", profileErr);
        await supabaseAdmin.auth.admin.deleteUser(soignantId);
        return redirectToFrontend(callbackPage, { status: "error", message: "Impossible de créer le profil" });
      }

      isNewUser = true;
    } else {
      // 8. Mettre à jour le soignant existant : lier PSC et refresh données vérifiées
      await supabaseAdmin
        .from("soignants")
        .update({
          psc_sub: pscSub,
          psc_linked_le: new Date().toISOString(),
          psc_last_login: new Date().toISOString(),
          numero_rpps: rpps || undefined,
          rpps_verifie: rpps ? true : undefined,
          rpps_verifie_le: rpps ? new Date().toISOString() : undefined,
          rpps_nom_api: nom || undefined,
          rpps_prenom_api: prenom || undefined,
        } as any)
        .eq("id", soignantId);
    }

    // 9. Récupérer l'email de l'utilisateur pour générer un magic link
    const { data: userData } = await supabaseAdmin.auth.admin.getUserById(soignantId);
    const userEmail = userData?.user?.email;
    if (!userEmail) {
      return redirectToFrontend(callbackPage, { status: "error", message: "Email utilisateur introuvable" });
    }

    // 10. Générer un magic link (type=magiclink) pour créer la session côté frontend
    const { data: linkData, error: linkErr } = await supabaseAdmin.auth.admin.generateLink({
      type: "magiclink",
      email: userEmail,
    });

    if (linkErr || !linkData?.properties?.hashed_token) {
      console.error("generateLink error:", linkErr);
      return redirectToFrontend(callbackPage, { status: "error", message: "Impossible de créer la session" });
    }

    // 11. Rediriger vers le frontend avec le token_hash (le front appellera verifyOtp)
    return redirectToFrontend(callbackPage, {
      status: "success",
      token_hash: linkData.properties.hashed_token,
      new_user: isNewUser ? "1" : "0",
    });
  } catch (err: unknown) {
    console.error("psc-callback error:", err);
    return redirectToFrontend(callbackPage, {
      status: "error",
      message: err instanceof Error ? err.message : "Erreur interne",
    });
  }
});
