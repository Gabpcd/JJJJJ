import { createClient } from "npm:@supabase/supabase-js@2";
import { applyRateLimit, getClientIp } from "../_shared/rate-limit.ts";
import { appelerAnthropic } from "../_shared/anthropic.ts";
import { verifyAdminOrServiceRole, verifyUserOrServiceRole } from "../_shared/admin-auth.ts";
import { canManageEstablishment } from "../_shared/etablissement-auth.ts";
import { corsHeaders } from "../_shared/cors.ts";
import {
  corporateNameMatches,
  normalizeProfessionalIdentifier,
  personNameMatches,
  strictAiVerificationQuality,
} from "../_shared/verification-rules.ts";

// Vérification IA du contrat de service d'un établissement.
// Lit le PDF téléversé via Anthropic, vérifie que c'est bien un contrat, extrait le
// SIRET + la raison sociale + le(s) signataire(s), et confronte au SIRET vérifié et
// à l'identité du représentant de l'établissement. coherent=true uniquement si tout
// concorde et qu'aucun indice de falsification n'est détecté. Appelée à l'upload ET
// au re-upload (modification du contrat).

Deno.serve(async (req) => {
  if (req.method === "OPTIONS") return new Response(null, { headers: corsHeaders(req) });

  try {
    const auth = await verifyUserOrServiceRole(req);
    if (!auth.ok) return new Response(JSON.stringify({ error: auth.error }), {
      status: auth.status, headers: { ...corsHeaders(req), "Content-Type": "application/json" },
    });
    const body = await req.json().catch(() => ({}));
    const action = body?.action === "cleanup_orphan" ? "cleanup_orphan" : "verify";
    if (body?.warm === true) {
      if (!auth.isServiceRole) {
        const adminAuth = await verifyAdminOrServiceRole(req);
        if (!adminAuth.ok) return new Response(JSON.stringify({ error: adminAuth.error }), {
          status: adminAuth.status, headers: { ...corsHeaders(req), "Content-Type": "application/json" },
        });
      }
      return new Response(JSON.stringify({ warm: true, configured: !!Deno.env.get("ANTHROPIC_API_KEY") }), {
        headers: { ...corsHeaders(req), "Content-Type": "application/json" },
      });
    }

    const supabaseUrl = Deno.env.get("SUPABASE_URL")!;
    const serviceKey = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")!;
    const supabase = createClient(supabaseUrl, serviceKey, { auth: { persistSession: false } });
    if (!auth.isServiceRole) {
      if (applyRateLimit("verify-contrat-etab", getClientIp(req), { max: 8, windowMs: 60_000 })) {
        return new Response(JSON.stringify({ error: "Trop de vérifications. Réessayez dans 1 minute." }), {
          status: 429, headers: { ...corsHeaders(req), "Content-Type": "application/json" },
        });
      }
    }

    const { etablissement_id } = body;
    if (!etablissement_id) throw new Error("etablissement_id requis");

    if (!auth.isServiceRole && !(await canManageEstablishment(supabase, auth.userId, etablissement_id))) {
      const adminAuth = await verifyAdminOrServiceRole(req);
      if (!adminAuth.ok) return new Response(JSON.stringify({ error: "Accès refusé" }), {
        status: 403, headers: { ...corsHeaders(req), "Content-Type": "application/json" },
      });
    }

    if (action === "cleanup_orphan") {
      const sourcePath = String(body?.contrat_url || "");
      const cheminAutorise = sourcePath.startsWith(`${etablissement_id}/contrat-service-`)
        && sourcePath.endsWith(".pdf")
        && !sourcePath.includes("..")
        && !sourcePath.includes("\\");
      if (!cheminAutorise) return new Response(JSON.stringify({ error: "Chemin de contrat non autorisé" }), {
        status: 403,
        headers: { ...corsHeaders(req), "Content-Type": "application/json" },
      });
      const { data: reference, error: referenceError } = await supabase
        .from("etablissements")
        .select("id")
        .eq("contrat_url", sourcePath)
        .limit(1)
        .maybeSingle();
      if (referenceError) throw referenceError;
      if (reference) return new Response(JSON.stringify({ error: "Ce contrat est encore référencé" }), {
        status: 409,
        headers: { ...corsHeaders(req), "Content-Type": "application/json" },
      });
      const { error: removeError } = await supabase.storage.from("jolene-documents").remove([sourcePath]);
      if (removeError) throw new Error("Nettoyage du contrat incomplet");
      return new Response(JSON.stringify({ success: true }), {
        headers: { ...corsHeaders(req), "Content-Type": "application/json" },
      });
    }

    const anthropicKey = Deno.env.get("ANTHROPIC_API_KEY");
    if (!anthropicKey) throw new Error("ANTHROPIC_API_KEY non configurée");

    const { data: etab, error: etabError } = await supabase
      .from("etablissements")
      .select("id, verification_source_version, nom, siret, siret_raison_sociale, finess_raison_sociale, representant_nom, representant_prenom, contrat_url")
      .eq("id", etablissement_id)
      .maybeSingle();
    if (etabError) throw new Error("Impossible de lire le profil établissement");
    if (!etab) throw new Error("Établissement introuvable");
    const e = etab as Record<string, any>;
    const appliquerVerdict = async (
      coherent: boolean | null,
      resultat: Record<string, unknown>,
    ) => {
      if (!auth.isServiceRole && !(await canManageEstablishment(supabase, auth.userId, etablissement_id))) {
        const adminAuth = await verifyAdminOrServiceRole(req);
        if (!adminAuth.ok) return false;
      }
      const { data, error } = await supabase.rpc(
        "fn_appliquer_verification_contrat_etablissement",
        {
          p_etablissement_id: etablissement_id,
          p_version_attendue: Number(e.verification_source_version),
          p_contrat_url: e.contrat_url ?? null,
          p_nom_etablissement: e.nom ?? null,
          p_siret: e.siret ?? null,
          p_siret_raison_sociale: e.siret_raison_sociale ?? null,
          p_finess_raison_sociale: e.finess_raison_sociale ?? null,
          p_representant_nom: e.representant_nom ?? null,
          p_representant_prenom: e.representant_prenom ?? null,
          p_coherent: coherent,
          p_resultat: resultat,
        },
      );
      if (error) throw new Error(`Persistance atomique contrat impossible: ${error.code || error.message}`);
      return data === true;
    };
    const sourceChangee = () => new Response(JSON.stringify({
      success: false,
      code: "VERIFICATION_SOURCE_CHANGED",
      error: "Le contrat ou le profil a changé pendant la vérification. Relancez le contrôle.",
    }), { status: 409, headers: { ...corsHeaders(req), "Content-Type": "application/json" } });
    if (!(etab as any).contrat_url) {
      return new Response(JSON.stringify({ success: true, coherent: null, reason: "Aucun contrat téléversé" }), {
        headers: { ...corsHeaders(req), "Content-Type": "application/json" },
      });
    }
    const contratPath = String((etab as any).contrat_url);
    if (!contratPath.startsWith(`${etablissement_id}/`) || contratPath.includes('..')) {
      return new Response(JSON.stringify({ error: "Chemin de contrat non autorisé" }), {
        status: 403, headers: { ...corsHeaders(req), "Content-Type": "application/json" },
      });
    }

    const { data: fileData, error: fileErr } = await supabase.storage
      .from("jolene-documents")
      .download((etab as any).contrat_url);
    if (fileErr || !fileData) throw new Error("Impossible de télécharger le contrat");

    const arrayBuffer = await fileData.arrayBuffer();
    if (arrayBuffer.byteLength === 0 || arrayBuffer.byteLength > 10 * 1024 * 1024) {
      const applique = await appliquerVerdict(false, {
        verdict_final: "REJETE",
        motif: "PDF vide ou supérieur à 10 Mo.",
      });
      if (!applique) return sourceChangee();
      return new Response(JSON.stringify({ success: true, coherent: false, motif: "PDF vide ou supérieur à 10 Mo." }), {
        headers: { ...corsHeaders(req), "Content-Type": "application/json" },
      });
    }
    const bytes = new Uint8Array(arrayBuffer);
    if (String.fromCharCode(...bytes.slice(0, 5)) !== '%PDF-') {
      const applique = await appliquerVerdict(false, {
        verdict_final: "REJETE",
        motif: "Le fichier n'est pas un PDF valide.",
      });
      if (!applique) return sourceChangee();
      return new Response(JSON.stringify({ success: true, coherent: false, motif: "Le fichier n'est pas un PDF valide." }), {
        headers: { ...corsHeaders(req), "Content-Type": "application/json" },
      });
    }
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
  "signataire_nom_extrait": "le nom de famille du signataire lu" ou null,
  "signataire_prenom_extrait": "le prénom du signataire lu" ou null,
  "siret_correspond": true/false/null,
  "raison_sociale_correspond": true/false/null,
  "signataire_correspond": true/false/null,
  "document_lisible": true/false,
  "document_complet": true/false,
  "indices_falsification": ["liste des indices de retouche/montage"] ou [],
  "score_confiance": 0-100,
  "confiance": "HAUTE"/"MOYENNE"/"FAIBLE",
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
    let ai: Awaited<ReturnType<typeof appelerAnthropic>>;
    try {
      ai = await appelerAnthropic({
        apiKey: anthropicKey,
        system: systemPrompt,
        content: [
          { type: "text", text: userMessage },
          { type: "document", source: { type: "base64", media_type: "application/pdf", data: base64 } },
        ],
        maxTokens: 1200,
        signal: aiController.signal,
      });
    } catch (e) {
      clearTimeout(aiTimeout);
      const estTimeout = (e as any)?.name === "AbortError";
      const applique = await appliquerVerdict(null, {
        erreur_anthropic: { status: estTimeout ? "timeout" : "network", at: new Date().toISOString() },
      });
      if (!applique) return sourceChangee();
      return new Response(JSON.stringify({ success: true, coherent: null, reason: estTimeout ? "AI timeout" : "AI network error" }), {
        headers: { ...corsHeaders(req), "Content-Type": "application/json" },
      });
    }
    clearTimeout(aiTimeout);

    if (!ai.ok) {
      const applique = await appliquerVerdict(null, {
        erreur_anthropic: { status: ai.status, body_excerpt: ai.body.slice(0, 1500), at: new Date().toISOString() },
      });
      if (!applique) return sourceChangee();
      return new Response(JSON.stringify({ success: true, coherent: null, reason: "AI unavailable" }), {
        headers: { ...corsHeaders(req), "Content-Type": "application/json" },
      });
    }

    const aiData = ai.data;
    const rawContent = aiData.content?.[0]?.text || "";
    let analysis: any;
    try {
      const m = rawContent.match(/\{[\s\S]*\}/);
      analysis = m ? JSON.parse(m[0]) : null;
    } catch { analysis = null; }

    if (!analysis) {
      const applique = await appliquerVerdict(null, {
        erreur_parse: { raw_length: rawContent.length, at: new Date().toISOString() },
      });
      if (!applique) return sourceChangee();
      return new Response(JSON.stringify({ success: true, coherent: null, reason: "Parse error" }), {
        headers: { ...corsHeaders(req), "Content-Type": "application/json" },
      });
    }

    // Comparaisons côté serveur (ne pas faire confiance à l'IA seule pour le SIRET).
    const siretAttendu = normalizeProfessionalIdentifier((etab as any).siret);
    const siretExtrait = normalizeProfessionalIdentifier(analysis.siret_extrait);
    const siretMatch = siretAttendu && siretExtrait ? siretAttendu === siretExtrait : null;
    const raisonSocialeMatch = corporateNameMatches(raisonSociale, analysis.raison_sociale_extraite);
    const signataireMatch = personNameMatches(
      (etab as any).representant_nom,
      (etab as any).representant_prenom,
      analysis.signataire_nom_extrait,
      analysis.signataire_prenom_extrait,
    );
    const quality = strictAiVerificationQuality(analysis);
    const indicesFalsif = quality.indicators;

    let coherent: boolean | null = null;
    let motif: string | null = null;
    const verdictsAutorises = new Set(["VERIFIE", "EN_ATTENTE", "REJETE"]);
    let verdictFinal = typeof analysis.verdict === "string" && verdictsAutorises.has(analysis.verdict)
      ? analysis.verdict
      : "EN_ATTENTE";
    if (analysis.verdict === "REJETE" || analysis.est_contrat === false || analysis.document_lisible === false) {
      coherent = false;
      verdictFinal = "REJETE";
      motif = analysis.motif || "Le document fourni n'est pas un contrat.";
    } else if (!quality.antifraudComplete) {
      coherent = null;
      verdictFinal = "EN_ATTENTE";
      motif = "Le contrôle antifraude est absent ou mal formé — vérification manuelle requise.";
    } else if (indicesFalsif.length > 0) {
      coherent = null;
      verdictFinal = "EN_ATTENTE";
      motif = "Indices de falsification détectés — vérification manuelle requise.";
    } else if (siretMatch === false) {
      coherent = false;
      verdictFinal = "REJETE";
      motif = `SIRET du contrat (${analysis.siret_extrait || "?"}) différent du SIRET vérifié (${(etab as any).siret}).`;
    } else if (
      analysis.verdict === "VERIFIE" && analysis.est_contrat === true &&
      analysis.document_lisible === true && analysis.document_complet === true && quality.highConfidence &&
      siretMatch === true && analysis.siret_correspond === true &&
      raisonSocialeMatch === true && analysis.raison_sociale_correspond === true &&
      signataireMatch === true && analysis.signataire_correspond === true
    ) {
      coherent = true;
      verdictFinal = "VERIFIE";
      motif = "Contrat vérifié : type, SIRET et identité concordants.";
    } else {
      coherent = null;
      verdictFinal = "EN_ATTENTE";
      motif = analysis.motif || "Concordance SIRET/identité non confirmée — revue manuelle requise.";
    }

    const analysisPersisted = {
      ...analysis,
      score_confiance: quality.score,
      confiance: quality.confidence,
      indices_falsification: indicesFalsif,
      antifraude_complete: quality.antifraudComplete,
      verdict_final: verdictFinal,
      siret_match_serveur: siretMatch,
      raison_sociale_match_serveur: raisonSocialeMatch,
      signataire_match_serveur: signataireMatch,
    };
    const applique = await appliquerVerdict(coherent, analysisPersisted);
    if (!applique) return sourceChangee();

    await supabase.rpc("fn_ecrire_audit_safe" as any, {
      p_acteur_id: etablissement_id,
      p_type_acteur: "SYSTEME",
      p_action: "VERIFICATION_DOCUMENT",
      p_type_ressource: "etablissement",
      p_id_ressource: etablissement_id,
      p_cle_s3: (etab as any).contrat_url,
      p_details: { coherent, verdict_ia: analysis.verdict, siret_match: siretMatch, est_contrat: analysis.est_contrat, antifraude_complete: quality.antifraudComplete, falsification: indicesFalsif.length > 0 },
      p_ip: null,
      p_navigateur: "edge-function/verify-contrat-etablissement",
    });

    return new Response(
      JSON.stringify({
        success: true,
        coherent,
        verdict: verdictFinal,
        motif,
        analysis: { type_detecte: analysis.type_detecte ?? null, score_confiance: quality.score },
      }),
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
