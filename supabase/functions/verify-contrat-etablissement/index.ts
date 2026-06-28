import { createClient } from "npm:@supabase/supabase-js@2";
import { applyRateLimit, getClientIp } from "../_shared/rate-limit.ts";

// Vérification IA du contrat de service d'un établissement.
// Lit le PDF téléversé via Anthropic, vérifie que c'est bien un contrat, extrait le
// SIRET + la raison sociale + le(s) signataire(s), et confronte au SIRET vérifié et
// à l'identité du représentant de l'établissement. coherent=true uniquement si tout
// concorde et qu'aucun indice de falsification n'est détecté. Appelée à l'upload ET
// au re-upload (modification du contrat).

function getCorsOrigin(req: Request): string {
  const origin = req.headers.get("origin") || "";
  if (
    origin === "https://jolene.app" ||
    origin === "https://app.jolene.app" ||
    origin === "https://www.jolene.app" ||
    origin === "http://localhost:5173" ||
    origin === "http://localhost:8080"
  ) {
    return origin;
  }
  return "https://jolene.app";
}

function corsHeaders(req: Request) {
  return {
    "Access-Control-Allow-Origin": getCorsOrigin(req),
    "Access-Control-Allow-Headers": "authorization, x-client-info, apikey, content-type, x-supabase-client-platform, x-supabase-client-platform-version, x-supabase-client-runtime, x-supabase-client-runtime-version",
  };
}

let _cachedVaultSecret: string | null = null;
async function getVaultSecret(sb: any): Promise<string> {
  if (_cachedVaultSecret) return _cachedVaultSecret;
  const env = Deno.env.get("SUPABASE_SECRET_KEY") || "";
  if (env) { _cachedVaultSecret = env; return env; }
  try {
    const { data } = await sb.rpc("fn_lire_secret_cron");
    if (data && typeof data === "string") { _cachedVaultSecret = data; return data; }
  } catch { /* ignore */ }
  return "";
}

function norm(s: string | null | undefined): string {
  return (s || "").toString().normalize("NFD").replace(/[̀-ͯ]/g, "").toLowerCase().replace(/[^a-z0-9]/g, "");
}

Deno.serve(async (req) => {
  if (req.method === "OPTIONS") return new Response(null, { headers: corsHeaders(req) });

  try {
    const body = await req.clone().json().catch(() => ({}));
    if (body?.warm === true) {
      return new Response(JSON.stringify({ warm: true }), {
        headers: { ...corsHeaders(req), "Content-Type": "application/json" },
      });
    }

    const authHeader = req.headers.get("Authorization");
    if (!authHeader?.startsWith("Bearer ")) {
      return new Response(JSON.stringify({ error: "Non autorisé" }), {
        status: 401, headers: { ...corsHeaders(req), "Content-Type": "application/json" },
      });
    }

    const supabaseUrl = Deno.env.get("SUPABASE_URL")!;
    const serviceKey = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")!;
    const token = authHeader.replace("Bearer ", "");
    const supabase = createClient(supabaseUrl, serviceKey, { auth: { persistSession: false } });
    const vaultSecret = await getVaultSecret(supabase);
    const isServiceRole = token === serviceKey || (vaultSecret && token === vaultSecret);

    let authUserId: string | null = null;
    if (!isServiceRole) {
      const supabaseAuth = createClient(supabaseUrl, Deno.env.get("SUPABASE_ANON_KEY")!);
      const { data: { user }, error: authError } = await supabaseAuth.auth.getUser(token);
      if (authError || !user) {
        return new Response(JSON.stringify({ error: "Token invalide" }), {
          status: 401, headers: { ...corsHeaders(req), "Content-Type": "application/json" },
        });
      }
      authUserId = user.id;
      if (applyRateLimit("verify-contrat-etab", getClientIp(req), { max: 8, windowMs: 60_000 })) {
        return new Response(JSON.stringify({ error: "Trop de vérifications. Réessayez dans 1 minute." }), {
          status: 429, headers: { ...corsHeaders(req), "Content-Type": "application/json" },
        });
      }
    }

    const { etablissement_id } = await req.json();
    if (!etablissement_id) throw new Error("etablissement_id requis");

    // Sécurité : un établissement ne peut vérifier que SON propre contrat.
    if (!isServiceRole && authUserId && etablissement_id !== authUserId) {
      return new Response(JSON.stringify({ error: "Accès refusé" }), {
        status: 403, headers: { ...corsHeaders(req), "Content-Type": "application/json" },
      });
    }

    const anthropicKey = Deno.env.get("ANTHROPIC_API_KEY");
    if (!anthropicKey) throw new Error("ANTHROPIC_API_KEY non configurée");

    const { data: etab } = await supabase
      .from("etablissements")
      .select("id, nom, siret, siret_raison_sociale, finess_raison_sociale, representant_nom, representant_prenom, contrat_url")
      .eq("id", etablissement_id)
      .maybeSingle();
    if (!etab) throw new Error("Établissement introuvable");
    if (!(etab as any).contrat_url) {
      return new Response(JSON.stringify({ success: true, coherent: null, reason: "Aucun contrat téléversé" }), {
        headers: { ...corsHeaders(req), "Content-Type": "application/json" },
      });
    }

    const { data: fileData, error: fileErr } = await supabase.storage
      .from("jolene-documents")
      .download((etab as any).contrat_url);
    if (fileErr || !fileData) throw new Error("Impossible de télécharger le contrat");

    const arrayBuffer = await fileData.arrayBuffer();
    const bytes = new Uint8Array(arrayBuffer);
    let binary = "";
    for (let i = 0; i < bytes.length; i += 8192) {
      const chunk = bytes.subarray(i, Math.min(i + 8192, bytes.length));
      for (let j = 0; j < chunk.length; j++) binary += String.fromCharCode(chunk[j]);
    }
    const base64 = btoa(binary);

    const raisonSociale = (etab as any).siret_raison_sociale || (etab as any).finess_raison_sociale || (etab as any).nom || "";
    const representant = `${(etab as any).representant_prenom || ""} ${(etab as any).representant_nom || ""}`.trim();

    const systemPrompt = `Tu es un vérificateur de contrats de service pour une plateforme de mise en relation de soignants. Analyse le document PDF fourni et réponds UNIQUEMENT en JSON valide avec cette structure exacte:
{
  "est_contrat": true/false,
  "type_detecte": "string décrivant le type de document",
  "siret_extrait": "le SIRET (14 chiffres) lu sur le document" ou null,
  "raison_sociale_extraite": "la raison sociale / nom de l'établissement signataire" ou null,
  "signataire_extrait": "le nom du signataire / représentant lu" ou null,
  "siret_correspond": true/false/null,
  "raison_sociale_correspond": true/false/null,
  "signataire_correspond": true/false/null,
  "document_lisible": true/false,
  "indices_falsification": ["liste des indices de retouche/montage"] ou [],
  "score_confiance": 0-100,
  "motif": null ou "string expliquant un éventuel problème",
  "verdict": "VERIFIE"/"EN_ATTENTE"/"REJETE"
}

Règles:
- est_contrat = true seulement si c'est bien un CONTRAT (contrat de service / prestation / mandat), pas une facture, un RIB, une pièce d'identité, etc.
- Compare le SIRET lu au SIRET attendu fourni (siret_correspond), la raison sociale (raison_sociale_correspond, tolère casse/accents/forme juridique), le signataire au représentant attendu (signataire_correspond, tolère casse/accents/ordre).
- DÉTECTION DE FALSIFICATION : signale toute retouche (polices incohérentes, zones recouvertes, montage). Au moindre indice sérieux → verdict "EN_ATTENTE".
- verdict = "REJETE" si ce n'est PAS un contrat, ou illisible.
- verdict = "VERIFIE" si c'est un contrat lisible, SIRET + raison sociale + signataire correspondent, 0 falsification, confiance haute.
- verdict = "EN_ATTENTE" sinon (incohérence SIRET/identité, doute, falsification) → revue admin.`;

    const userMessage = `Contrat de service à vérifier pour l'établissement:
- Raison sociale attendue: "${raisonSociale}"
- SIRET attendu: "${(etab as any).siret || "non renseigné"}"
- Représentant attendu: "${representant || "non renseigné"}"

Vérifie que le document est bien un contrat et que ces informations concordent.`;

    const aiController = new AbortController();
    const aiTimeout = setTimeout(() => aiController.abort(), 25_000);
    let aiResponse: Response;
    try {
      aiResponse = await fetch("https://api.anthropic.com/v1/messages", {
        method: "POST",
        headers: { "x-api-key": anthropicKey, "anthropic-version": "2023-06-01", "Content-Type": "application/json" },
        body: JSON.stringify({
          model: "claude-sonnet-4-6",
          max_tokens: 1200,
          system: systemPrompt,
          messages: [{ role: "user", content: [
            { type: "text", text: userMessage },
            { type: "document", source: { type: "base64", media_type: "application/pdf", data: base64 } },
          ] }],
        }),
        signal: aiController.signal,
      });
    } catch (e) {
      clearTimeout(aiTimeout);
      const estTimeout = (e as any)?.name === "AbortError";
      await supabase.from("etablissements").update({
        contrat_ia_resultat: { erreur_anthropic: { status: estTimeout ? "timeout" : "network", at: new Date().toISOString() } },
      } as any).eq("id", etablissement_id);
      return new Response(JSON.stringify({ success: true, coherent: null, reason: estTimeout ? "AI timeout" : "AI network error" }), {
        headers: { ...corsHeaders(req), "Content-Type": "application/json" },
      });
    }
    clearTimeout(aiTimeout);

    if (!aiResponse.ok) {
      const errText = await aiResponse.text();
      await supabase.from("etablissements").update({
        contrat_ia_resultat: { erreur_anthropic: { status: aiResponse.status, body_excerpt: errText.slice(0, 1500), at: new Date().toISOString() } },
      } as any).eq("id", etablissement_id);
      return new Response(JSON.stringify({ success: true, coherent: null, reason: "AI unavailable" }), {
        headers: { ...corsHeaders(req), "Content-Type": "application/json" },
      });
    }

    const aiData = await aiResponse.json();
    const rawContent = aiData.content?.[0]?.text || "";
    let analysis: any;
    try {
      const m = rawContent.match(/\{[\s\S]*\}/);
      analysis = m ? JSON.parse(m[0]) : null;
    } catch { analysis = null; }

    if (!analysis) {
      await supabase.from("etablissements").update({
        contrat_ia_resultat: { erreur_parse: { raw_excerpt: rawContent.slice(0, 1500), at: new Date().toISOString() } },
      } as any).eq("id", etablissement_id);
      return new Response(JSON.stringify({ success: true, coherent: null, reason: "Parse error" }), {
        headers: { ...corsHeaders(req), "Content-Type": "application/json" },
      });
    }

    // Comparaisons côté serveur (ne pas faire confiance à l'IA seule pour le SIRET).
    const siretAttendu = norm((etab as any).siret);
    const siretExtrait = norm(analysis.siret_extrait);
    const siretMatch = siretAttendu && siretExtrait ? siretAttendu === siretExtrait : null;
    const indicesFalsif = Array.isArray(analysis.indices_falsification) ? analysis.indices_falsification : [];

    let coherent: boolean;
    let motif: string | null = null;
    if (analysis.verdict === "REJETE" || analysis.est_contrat === false) {
      coherent = false;
      motif = analysis.motif || "Le document fourni n'est pas un contrat.";
    } else if (indicesFalsif.length > 0) {
      coherent = false;
      motif = `Indices de falsification : ${indicesFalsif.join(", ")}.`;
    } else if (siretMatch === false) {
      coherent = false;
      motif = `SIRET du contrat (${analysis.siret_extrait || "?"}) différent du SIRET vérifié (${(etab as any).siret}).`;
    } else if (analysis.verdict === "VERIFIE" && analysis.raison_sociale_correspond !== false && analysis.signataire_correspond !== false) {
      coherent = true;
      motif = "Contrat vérifié : type, SIRET et identité concordants.";
    } else {
      coherent = false;
      motif = analysis.motif || "Concordance SIRET/identité non confirmée — revue manuelle requise.";
    }

    await supabase.from("etablissements").update({
      contrat_ia_resultat: { ...analysis, siret_match_serveur: siretMatch },
      contrat_ia_coherent: coherent,
      contrat_ia_verifie_le: new Date().toISOString(),
    } as any).eq("id", etablissement_id);

    await supabase.rpc("fn_ecrire_audit_safe" as any, {
      p_acteur_id: etablissement_id,
      p_type_acteur: "SYSTEME",
      p_action: "CONTRAT_ETAB_VERIFICATION_IA",
      p_type_ressource: "etablissement",
      p_id_ressource: etablissement_id,
      p_cle_s3: (etab as any).contrat_url,
      p_details: { coherent, verdict_ia: analysis.verdict, siret_match: siretMatch, est_contrat: analysis.est_contrat, falsification: indicesFalsif.length > 0 },
      p_ip: null,
      p_navigateur: "edge-function/verify-contrat-etablissement",
    });

    return new Response(
      JSON.stringify({ success: true, coherent, motif, analysis }),
      { headers: { ...corsHeaders(req), "Content-Type": "application/json" } }
    );
  } catch (e: any) {
    console.error("verify-contrat-etablissement error:", e);
    return new Response(
      JSON.stringify({ error: e?.message || "Une erreur interne est survenue." }),
      { status: 500, headers: { ...corsHeaders(req), "Content-Type": "application/json" } }
    );
  }
});
