import { createClient } from "npm:@supabase/supabase-js@2";
import { corsHeaders } from "../_shared/cors.ts";
import { applyRateLimit, getClientIp } from "../_shared/rate-limit.ts";
import { appelerAnthropic } from "../_shared/anthropic.ts";
import { canManageEstablishment } from "../_shared/etablissement-auth.ts";
import {
  corporateNameMatches,
  personNameMatches,
  strictAiVerificationQuality,
  validateDocumentFile,
} from "../_shared/verification-rules.ts";

// Vérification IA du contrat de travail d'une mission salariée.
// Confirme que le PDF est bien un contrat de travail (CDD/CDI) et que les parties
// (soignant salarié + établissement employeur) concordent avec la mission.

let _cachedVaultSecret: string | null = null;
async function getVaultSecret(sb: any): Promise<string> {
  if (_cachedVaultSecret) return _cachedVaultSecret;
  const env = Deno.env.get("SUPABASE_SECRET_KEY") || "";
  if (env) { _cachedVaultSecret = env; return env; }
  try { const { data } = await sb.rpc("fn_lire_secret_cron"); if (data && typeof data === "string") { _cachedVaultSecret = data; return data; } } catch { /* ignore */ }
  return "";
}
Deno.serve(async (req) => {
  if (req.method === "OPTIONS") return new Response(null, { headers: corsHeaders(req) });
  try {
    const body = await req.clone().json().catch(() => ({}));
    if (body?.warm === true) return new Response(JSON.stringify({ warm: true }), { headers: { ...corsHeaders(req), "Content-Type": "application/json" } });

    const authHeader = req.headers.get("Authorization");
    if (!authHeader?.startsWith("Bearer ")) return new Response(JSON.stringify({ error: "Non autorisé" }), { status: 401, headers: { ...corsHeaders(req), "Content-Type": "application/json" } });

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
      if (authError || !user) return new Response(JSON.stringify({ error: "Token invalide" }), { status: 401, headers: { ...corsHeaders(req), "Content-Type": "application/json" } });
      authUserId = user.id;
      if (applyRateLimit("verify-contrat-travail", getClientIp(req), { max: 8, windowMs: 60000 })) return new Response(JSON.stringify({ error: "Trop de vérifications. Réessayez dans 1 minute." }), { status: 429, headers: { ...corsHeaders(req), "Content-Type": "application/json" } });
    }

    const mission_id = body?.mission_id;
    const action = body?.action === "signed_url"
      ? "signed_url"
      : body?.action === "cleanup_orphan"
        ? "cleanup_orphan"
        : "verify";
    if (!mission_id) throw new Error("mission_id requis");

    if (action === "cleanup_orphan") {
      const sourcePath = String(body?.pdf_s3_key || "");
      const { data: mission, error: missionError } = await supabase
        .from("missions")
        .select("id, etablissement_id")
        .eq("id", mission_id)
        .maybeSingle();
      if (missionError) throw missionError;
      if (!mission) throw new Error("Mission introuvable");
      const peutNettoyer = isServiceRole || (authUserId
        && await canManageEstablishment(supabase, authUserId, String((mission as any).etablissement_id)));
      const cheminAutorise = sourcePath.startsWith(`${(mission as any).etablissement_id}/contrats-travail/${mission_id}/`)
        && !sourcePath.includes("..")
        && !sourcePath.includes("\\");
      if (!peutNettoyer || !cheminAutorise) {
        return new Response(JSON.stringify({ error: "Nettoyage non autorisé" }), {
          status: 403,
          headers: { ...corsHeaders(req), "Content-Type": "application/json" },
        });
      }
      const { data: reference, error: referenceError } = await supabase
        .from("contrats_travail_missions")
        .select("id")
        .eq("pdf_s3_key", sourcePath)
        .limit(1)
        .maybeSingle();
      if (referenceError) throw referenceError;
      if (reference) {
        return new Response(JSON.stringify({ error: "Ce contrat est encore référencé" }), {
          status: 409,
          headers: { ...corsHeaders(req), "Content-Type": "application/json" },
        });
      }
      const { error: removeError } = await supabase.storage.from("jolene-documents").remove([sourcePath]);
      if (removeError) throw new Error("Nettoyage du contrat incomplet");
      return new Response(JSON.stringify({ success: true }), {
        headers: { ...corsHeaders(req), "Content-Type": "application/json" },
      });
    }

    const { data: ct, error: ctError } = await supabase
      .from("contrats_travail_missions")
      .select("id, mission_id, etablissement_id, soignant_id, pdf_s3_key")
      .eq("mission_id", mission_id)
      .order("uploaded_at", { ascending: false })
      .limit(1)
      .maybeSingle();
    if (ctError) throw ctError;
    if (!ct) throw new Error("Contrat de travail introuvable pour cette mission");

    const peutGererEtablissement = !isServiceRole
      && authUserId
      && await canManageEstablishment(supabase, authUserId, String((ct as any).etablissement_id));
    const estSoignantAssigne = !isServiceRole && authUserId === (ct as any).soignant_id;
    if (!isServiceRole && !peutGererEtablissement && !(action === "signed_url" && estSoignantAssigne)) {
      return new Response(JSON.stringify({ error: "Accès refusé" }), {
        status: 403,
        headers: { ...corsHeaders(req), "Content-Type": "application/json" },
      });
    }

    const sourcePath = String((ct as any).pdf_s3_key || "");
    const cheminCourant = sourcePath.startsWith(`${(ct as any).etablissement_id}/contrats-travail/${mission_id}/`);
    const cheminHistorique = sourcePath === `contrats-travail/${mission_id}/contrat.pdf`;
    if (
      (!cheminCourant && !cheminHistorique)
      || sourcePath.includes("..")
      || sourcePath.includes("\\")
    ) {
      return new Response(JSON.stringify({ error: "Chemin de contrat non autorisé" }), {
        status: 403,
        headers: { ...corsHeaders(req), "Content-Type": "application/json" },
      });
    }

    if (action === "signed_url") {
      const { data: signed, error: signedError } = await supabase.storage
        .from("jolene-documents")
        .createSignedUrl(sourcePath, 300);
      if (signedError || !signed?.signedUrl) throw new Error("Lien de téléchargement indisponible");
      return new Response(JSON.stringify({ success: true, signed_url: signed.signedUrl, expires_in: 300 }), {
        headers: { ...corsHeaders(req), "Content-Type": "application/json" },
      });
    }

    const anthropicKey = Deno.env.get("ANTHROPIC_API_KEY");
    if (!anthropicKey) throw new Error("ANTHROPIC_API_KEY non configurée");

    const [{ data: soig }, { data: etab }] = await Promise.all([
      supabase.from("soignants").select("nom, prenom").eq("id", (ct as any).soignant_id).maybeSingle(),
      supabase.from("etablissements").select("nom, siret_raison_sociale, finess_raison_sociale").eq("id", (ct as any).etablissement_id).maybeSingle(),
    ]);
    const soignantNom = `${(soig as any)?.prenom || ""} ${(soig as any)?.nom || ""}`.trim();
    const etabNom = (etab as any)?.siret_raison_sociale || (etab as any)?.finess_raison_sociale || (etab as any)?.nom || "";

    const { data: fileData, error: fileErr } = await supabase.storage.from("jolene-documents").download(sourcePath);
    if (fileErr || !fileData) throw new Error("Impossible de télécharger le contrat de travail");
    const arrayBuffer = await fileData.arrayBuffer();
    const bytes = new Uint8Array(arrayBuffer);
    const fileValidation = validateDocumentFile(bytes, "application/pdf");
    if (!fileValidation.ok) {
      const motif = fileValidation.code === "EMPTY"
        ? "Le contrat est vide."
        : fileValidation.code === "TOO_LARGE"
          ? "Le contrat dépasse 10 Mo."
          : "Le fichier n'est pas un PDF valide.";
      const { data: updated } = await supabase.from("contrats_travail_missions")
        .update({
          ia_resultat: { controle_fichier: fileValidation.code, motif, regle_version: "2026-07-14" },
          ia_coherent: false,
          ia_verifie_le: new Date().toISOString(),
        } as any)
        .eq("id", (ct as any).id)
        .eq("pdf_s3_key", sourcePath)
        .select("id")
        .maybeSingle();
      if (!updated) return new Response(JSON.stringify({ error: "Le contrat a changé pendant la vérification" }), {
        status: 409,
        headers: { ...corsHeaders(req), "Content-Type": "application/json" },
      });
      return new Response(JSON.stringify({ success: true, coherent: false, motif }), {
        headers: { ...corsHeaders(req), "Content-Type": "application/json" },
      });
    }
    let binary = "";
    for (let i = 0; i < bytes.length; i += 8192) { const chunk = bytes.subarray(i, Math.min(i + 8192, bytes.length)); for (let j = 0; j < chunk.length; j++) binary += String.fromCharCode(chunk[j]); }
    const base64 = btoa(binary);

    const systemPrompt = `Tu es un vérificateur de contrats de travail (CDD/CDI) pour des missions de soignants salariés. Analyse le PDF et réponds UNIQUEMENT en JSON valide:
{
  "est_contrat_travail": true/false,
  "type_detecte": "string (CDD, CDI, autre)",
  "salarie_extrait": "nom du salarié lu" ou null,
  "salarie_nom_extrait": "nom de famille du salarié lu" ou null,
  "salarie_prenom_extrait": "prénom du salarié lu" ou null,
  "employeur_extrait": "nom de l'employeur lu" ou null,
  "salarie_correspond": true/false/null,
  "employeur_correspond": true/false/null,
  "document_lisible": true/false,
  "document_complet": true/false,
  "indices_falsification": [] ou ["..."],
  "score_confiance": 0-100,
  "confiance": "HAUTE"/"MOYENNE"/"FAIBLE",
  "motif": null ou "string",
  "verdict": "VERIFIE"/"EN_ATTENTE"/"REJETE"
}
Règles:
- est_contrat_travail = true seulement si c'est bien un CONTRAT DE TRAVAIL (CDD/CDI), pas une facture/attestation/autre.
- Compare le salarié au soignant attendu (salarie_correspond, tolère casse/accents/ordre) et l'employeur à l'établissement attendu (employeur_correspond, tolère forme juridique).
- FALSIFICATION : signale toute retouche → verdict EN_ATTENTE.
- verdict REJETE si ce n'est pas un contrat de travail ou illisible.
- verdict VERIFIE si contrat de travail lisible + salarié + employeur correspondent + 0 falsification + confiance haute.
- verdict EN_ATTENTE sinon.`;
    const userMessage = `Contrat de travail à vérifier:\n- Salarié (soignant) attendu: "${soignantNom}"\n- Employeur (établissement) attendu: "${etabNom}"\nVérifie que c'est bien un contrat de travail et que ces parties concordent.`;

    const aiController = new AbortController();
    const aiTimeout = setTimeout(() => aiController.abort(), 25000);
    let ai;
    try {
      ai = await appelerAnthropic({ apiKey: anthropicKey, system: systemPrompt, content: [{ type: "text", text: userMessage }, { type: "document", source: { type: "base64", media_type: "application/pdf", data: base64 } }], maxTokens: 1000, signal: aiController.signal });
    } catch (e) {
      clearTimeout(aiTimeout);
      const estTimeout = (e as any)?.name === "AbortError";
      await supabase.from("contrats_travail_missions").update({ ia_resultat: { erreur_anthropic: { status: estTimeout ? "timeout" : "network", at: new Date().toISOString() } } } as any).eq("id", (ct as any).id).eq("pdf_s3_key", sourcePath);
      return new Response(JSON.stringify({ success: true, coherent: null, reason: estTimeout ? "AI timeout" : "AI network error" }), { headers: { ...corsHeaders(req), "Content-Type": "application/json" } });
    }
    clearTimeout(aiTimeout);
    if (!ai.ok) {
      await supabase.from("contrats_travail_missions").update({ ia_resultat: { erreur_anthropic: { status: ai.status, body_length: ai.body.length, at: new Date().toISOString() } } } as any).eq("id", (ct as any).id).eq("pdf_s3_key", sourcePath);
      return new Response(JSON.stringify({ success: true, coherent: null, reason: "AI unavailable" }), { headers: { ...corsHeaders(req), "Content-Type": "application/json" } });
    }
    const aiData = ai.data;
    const rawContent = aiData.content?.[0]?.text || "";
    let analysis: any;
    try { const m = rawContent.match(/\{[\s\S]*\}/); analysis = m ? JSON.parse(m[0]) : null; } catch { analysis = null; }
    if (!analysis) {
      await supabase.from("contrats_travail_missions").update({ ia_resultat: { erreur_parse: { raw_length: rawContent.length, at: new Date().toISOString() } } } as any).eq("id", (ct as any).id).eq("pdf_s3_key", sourcePath);
      return new Response(JSON.stringify({ success: true, coherent: null, reason: "Parse error" }), { headers: { ...corsHeaders(req), "Content-Type": "application/json" } });
    }

    const quality = strictAiVerificationQuality(analysis);
    const salarieMatch = personNameMatches(
      (soig as any)?.nom,
      (soig as any)?.prenom,
      analysis.salarie_nom_extrait,
      analysis.salarie_prenom_extrait,
    );
    const employeurMatch = corporateNameMatches(etabNom, analysis.employeur_extrait);
    let coherent: boolean | null = null;
    let motif: string | null = null;
    if (analysis.verdict === "REJETE" || analysis.est_contrat_travail === false || analysis.document_lisible === false) {
      coherent = false;
      motif = analysis.motif || "Le document n'est pas un contrat de travail lisible.";
    } else if (salarieMatch === false) {
      coherent = false;
      motif = "Le salarié indiqué sur le contrat ne correspond pas au soignant de la mission.";
    } else if (employeurMatch === false) {
      coherent = false;
      motif = "L'employeur indiqué sur le contrat ne correspond pas à l'établissement de la mission.";
    } else if (!quality.antifraudComplete || quality.indicators.length > 0) {
      coherent = null;
      motif = quality.indicators.length > 0
        ? "Indices de falsification détectés — revue humaine requise."
        : "Contrôle antifraude incomplet — revue humaine requise.";
    } else if (
      analysis.verdict === "VERIFIE"
      && analysis.est_contrat_travail === true
      && analysis.document_lisible === true
      && analysis.document_complet === true
      && salarieMatch === true
      && employeurMatch === true
      && quality.highConfidence
    ) {
      coherent = true;
      motif = "Contrat de travail vérifié : type, salarié et employeur concordants.";
    } else {
      coherent = null;
      motif = analysis.motif || "Concordance salarié/employeur non confirmée — revue manuelle requise.";
    }

    const resultatPersisted = {
      est_contrat_travail: typeof analysis.est_contrat_travail === "boolean" ? analysis.est_contrat_travail : null,
      type_detecte: typeof analysis.type_detecte === "string" ? analysis.type_detecte.slice(0, 100) : null,
      salarie_extrait: typeof analysis.salarie_extrait === "string" ? analysis.salarie_extrait.slice(0, 300) : null,
      salarie_nom_extrait: typeof analysis.salarie_nom_extrait === "string" ? analysis.salarie_nom_extrait.slice(0, 150) : null,
      salarie_prenom_extrait: typeof analysis.salarie_prenom_extrait === "string" ? analysis.salarie_prenom_extrait.slice(0, 150) : null,
      employeur_extrait: typeof analysis.employeur_extrait === "string" ? analysis.employeur_extrait.slice(0, 300) : null,
      document_lisible: typeof analysis.document_lisible === "boolean" ? analysis.document_lisible : null,
      document_complet: typeof analysis.document_complet === "boolean" ? analysis.document_complet : null,
      indices_falsification: quality.indicators,
      verdict: typeof analysis.verdict === "string" ? analysis.verdict.slice(0, 30) : null,
      motif: typeof analysis.motif === "string" ? analysis.motif.slice(0, 500) : null,
      salarie_match_serveur: salarieMatch,
      employeur_match_serveur: employeurMatch,
      score_confiance_valide: quality.score,
      confiance_valide: quality.confidence,
    };
    const { data: updated, error: updateError } = await supabase.from("contrats_travail_missions")
      .update({ ia_resultat: resultatPersisted, ia_coherent: coherent, ia_verifie_le: new Date().toISOString() } as any)
      .eq("id", (ct as any).id)
      .eq("pdf_s3_key", sourcePath)
      .select("id")
      .maybeSingle();
    if (updateError) throw updateError;
    if (!updated) return new Response(JSON.stringify({ error: "Le contrat a changé pendant la vérification" }), {
      status: 409,
      headers: { ...corsHeaders(req), "Content-Type": "application/json" },
    });
    await supabase.rpc("fn_ecrire_audit_safe" as any, { p_acteur_id: (ct as any).etablissement_id, p_type_acteur: "SYSTEME", p_action: "CONTRAT_TRAVAIL_VERIFICATION_IA", p_type_ressource: "mission", p_id_ressource: mission_id, p_cle_s3: sourcePath, p_details: { coherent, verdict_ia: resultatPersisted.verdict, est_contrat_travail: resultatPersisted.est_contrat_travail, falsification: quality.indicators.length > 0, salarie_match: salarieMatch, employeur_match: employeurMatch }, p_ip: null, p_navigateur: "edge-function/verify-contrat-travail" });

    return new Response(JSON.stringify({
      success: true,
      coherent,
      motif: typeof motif === "string" ? motif.slice(0, 500) : null,
      type_detecte: resultatPersisted.type_detecte,
      salarie_correspond: salarieMatch,
      employeur_correspond: employeurMatch,
    }), { headers: { ...corsHeaders(req), "Content-Type": "application/json" } });
  } catch (e: any) {
    console.error("verify-contrat-travail error:", e);
    return new Response(JSON.stringify({ error: e?.message || "Une erreur interne est survenue." }), { status: 500, headers: { ...corsHeaders(req), "Content-Type": "application/json" } });
  }
});
