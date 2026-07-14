import { createClient } from "npm:@supabase/supabase-js@2";
import { applyRateLimit, getClientIp } from "../_shared/rate-limit.ts";
import { appelerAnthropic } from "../_shared/anthropic.ts";
import { verifyAdminOrServiceRole, verifyUserOrServiceRole } from "../_shared/admin-auth.ts";
import { canManageEstablishment } from "../_shared/etablissement-auth.ts";
import { corsHeaders } from "../_shared/cors.ts";
import {
  openEstablishmentReview,
  resolveEstablishmentReview,
} from "../_shared/establishment-review.ts";
import {
  corporateNameMatches,
  ibanLast4,
  isValidIban,
  normalizeIban,
  sanitizeBankAnalysis,
  strictAiVerificationQuality,
  validateDocumentFile,
} from "../_shared/verification-rules.ts";

async function sha256Hex(value: string | ArrayBuffer): Promise<string> {
  const source = typeof value === "string"
    ? new TextEncoder().encode(value)
    : value;
  const digest = await crypto.subtle.digest("SHA-256", source);
  return Array.from(new Uint8Array(digest))
    .map((byte) => byte.toString(16).padStart(2, "0"))
    .join("");
}

// Vérification IA du RIB d'un établissement (PDF ou image). Confirme que le document
// est bien un RIB et que le titulaire du compte correspond à l'établissement.

Deno.serve(async (req) => {
  if (req.method === "OPTIONS") return new Response(null, { headers: corsHeaders(req) });
  try {
    const auth = await verifyUserOrServiceRole(req);
    if (!auth.ok) return new Response(JSON.stringify({ error: auth.error }), { status: auth.status, headers: { ...corsHeaders(req), "Content-Type": "application/json" } });
    const body = await req.json().catch(() => ({}));
    const action = body?.action === "cleanup_orphan" ? "cleanup_orphan" : "verify";
    if (body?.warm === true) {
      if (!auth.isServiceRole) {
        const adminAuth = await verifyAdminOrServiceRole(req);
        if (!adminAuth.ok) return new Response(JSON.stringify({ error: adminAuth.error }), { status: adminAuth.status, headers: { ...corsHeaders(req), "Content-Type": "application/json" } });
      }
      return new Response(JSON.stringify({ warm: true, configured: !!Deno.env.get("ANTHROPIC_API_KEY") }), { headers: { ...corsHeaders(req), "Content-Type": "application/json" } });
    }

    const supabaseUrl = Deno.env.get("SUPABASE_URL")!;
    const serviceKey = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")!;
    const supabase = createClient(supabaseUrl, serviceKey, { auth: { persistSession: false } });
    if (!auth.isServiceRole) {
      if (applyRateLimit("verify-rib-etab", getClientIp(req), { max: 8, windowMs: 60000 })) return new Response(JSON.stringify({ error: "Trop de vérifications. Réessayez dans 1 minute." }), { status: 429, headers: { ...corsHeaders(req), "Content-Type": "application/json" } });
    }

    const { etablissement_id } = body;
    if (!etablissement_id) throw new Error("etablissement_id requis");
    if (!auth.isServiceRole && !(await canManageEstablishment(supabase, auth.userId, etablissement_id))) {
      const adminAuth = await verifyAdminOrServiceRole(req);
      if (!adminAuth.ok) return new Response(JSON.stringify({ error: "Accès refusé" }), { status: 403, headers: { ...corsHeaders(req), "Content-Type": "application/json" } });
    }

    if (action === "cleanup_orphan") {
      const sourcePath = String(body?.rib_s3_key || "");
      const cheminAutorise = sourcePath.startsWith(`${etablissement_id}/rib-etablissement-`)
        && !sourcePath.includes("..")
        && !sourcePath.includes("\\");
      if (!cheminAutorise) return new Response(JSON.stringify({ error: "Chemin de RIB non autorisé" }), {
        status: 403,
        headers: { ...corsHeaders(req), "Content-Type": "application/json" },
      });
      const { data: reference, error: referenceError } = await supabase
        .from("etablissements")
        .select("id")
        .eq("rib_s3_key", sourcePath)
        .limit(1)
        .maybeSingle();
      if (referenceError) throw referenceError;
      if (reference) return new Response(JSON.stringify({ error: "Ce RIB est encore référencé" }), {
        status: 409,
        headers: { ...corsHeaders(req), "Content-Type": "application/json" },
      });
      const { error: removeError } = await supabase.storage.from("jolene-documents").remove([sourcePath]);
      if (removeError) throw new Error("Nettoyage du RIB incomplet");
      return new Response(JSON.stringify({ success: true }), {
        headers: { ...corsHeaders(req), "Content-Type": "application/json" },
      });
    }

    const anthropicKey = Deno.env.get("ANTHROPIC_API_KEY");
    if (!anthropicKey) throw new Error("ANTHROPIC_API_KEY non configurée");

    const { data: etab, error: etabError } = await supabase.from("etablissements")
      .select("id, verification_source_version, nom, siret_raison_sociale, finess_raison_sociale, rib_s3_key")
      .eq("id", etablissement_id).maybeSingle();
    if (etabError) throw new Error("Impossible de lire le profil établissement");
    if (!etab) throw new Error("Établissement introuvable");
    const e = etab as Record<string, any>;
    const appliquerVerdict = async (
      coherent: boolean | null,
      resultat: Record<string, unknown>,
      last4: string | null = null,
    ) => {
      if (!auth.isServiceRole && !(await canManageEstablishment(supabase, auth.userId, etablissement_id))) {
        const adminAuth = await verifyAdminOrServiceRole(req);
        if (!adminAuth.ok) return false;
      }
      const { data, error } = await supabase.rpc(
        "fn_appliquer_verification_rib_etablissement",
        {
          p_etablissement_id: etablissement_id,
          p_version_attendue: Number(e.verification_source_version),
          p_rib_s3_key: e.rib_s3_key ?? null,
          p_nom_etablissement: e.nom ?? null,
          p_siret_raison_sociale: e.siret_raison_sociale ?? null,
          p_finess_raison_sociale: e.finess_raison_sociale ?? null,
          p_coherent: coherent,
          p_resultat: resultat,
          p_iban_last4: last4,
        },
      );
      if (error) throw new Error(`Persistance atomique RIB impossible: ${error.code || error.message}`);
      return data === true;
    };
    const sourceChangee = () => new Response(JSON.stringify({
      success: false,
      code: "VERIFICATION_SOURCE_CHANGED",
      error: "Le RIB ou le profil a changé pendant la vérification. Relancez le contrôle.",
    }), { status: 409, headers: { ...corsHeaders(req), "Content-Type": "application/json" } });
    if (!(etab as any).rib_s3_key) return new Response(JSON.stringify({ success: true, coherent: null, reason: "Aucun RIB téléversé" }), { headers: { ...corsHeaders(req), "Content-Type": "application/json" } });
    const ribPath = String((etab as any).rib_s3_key);
    if (!ribPath.startsWith(`${etablissement_id}/`) || ribPath.includes("..")) {
      return new Response(JSON.stringify({ error: "Chemin de RIB non autorisé" }), {
        status: 403,
        headers: { ...corsHeaders(req), "Content-Type": "application/json" },
      });
    }

    const { data: fileData, error: fileErr } = await supabase.storage.from("jolene-documents").download(ribPath);
    if (fileErr || !fileData) throw new Error("Impossible de télécharger le RIB");
    const arrayBuffer = await fileData.arrayBuffer();
    const bytes = new Uint8Array(arrayBuffer);
    const fileValidation = validateDocumentFile(bytes, fileData.type);
    if (!fileValidation.ok) {
      const motifs: Record<string, string> = {
        EMPTY: "Le RIB est vide.",
        TOO_LARGE: "Le RIB dépasse 10 Mo.",
        UNSUPPORTED_MIME: "Le type MIME déclaré du RIB est absent ou non autorisé.",
        INVALID_SIGNATURE: "Le contenu du RIB ne correspond pas à son type MIME déclaré.",
      };
      const motif = motifs[fileValidation.code];
      const applique = await appliquerVerdict(false, {
        verdict_final: "REJETE",
        motif,
        controle_fichier: fileValidation.code,
        regle_version: "2026-07-14",
      });
      if (!applique) return sourceChangee();
      return new Response(JSON.stringify({ success: true, coherent: false, motif }), {
        headers: { ...corsHeaders(req), "Content-Type": "application/json" },
      });
    }

    const sourceVersion = Number(e.verification_source_version);
    const sourceBytes = bytes.buffer.slice(
      bytes.byteOffset,
      bytes.byteOffset + bytes.byteLength,
    ) as ArrayBuffer;
    const ribSourceSha256 = await sha256Hex(sourceBytes);
    const mettreEnRevue = async (
      cause: string,
      motif: string,
      resultat: Record<string, unknown> = {},
      ibanNormalise: string | null = null,
    ): Promise<Response> => {
      const applique = await appliquerVerdict(null, {
        ...resultat,
        verdict_final: "EN_ATTENTE",
        motif,
        revue_manuelle_requise: true,
        cause_revue: cause,
        regle_version: "2026-07-14",
      });
      if (!applique) return sourceChangee();

      const ibanLastFour = ibanNormalise ? ibanLast4(ibanNormalise) : null;
      const ibanFingerprint = ibanNormalise
        ? await sha256Hex(
          `${etablissement_id}|${sourceVersion}|${ribPath}|${ibanNormalise}`,
        )
        : null;
      try {
        const revueId = await openEstablishmentReview(
          supabase as unknown as Parameters<typeof openEstablishmentReview>[0],
          etablissement_id,
          "VERIFY_RIB_ETABLISSEMENT",
          motif,
          {
            cause,
            verification_source_version: sourceVersion,
            verification_source_version_apres_verdict: sourceVersion + 1,
            rib_s3_key: ribPath,
            rib_source_sha256_v1: ribSourceSha256,
            source_snapshot: {
              verification_source_version: sourceVersion,
              rib_s3_key: ribPath,
              nom: e.nom ?? null,
              siret_raison_sociale: e.siret_raison_sociale ?? null,
              finess_raison_sociale: e.finess_raison_sociale ?? null,
            },
            // Seuls un suffixe et une empreinte salée sont transmis à la file.
            // L'IBAN complet ne quitte jamais la mémoire de cette invocation.
            iban_last4: ibanLastFour,
            iban_fingerprint_sha256_v1: ibanFingerprint,
          },
        );
        await supabase.rpc("fn_ecrire_audit_safe" as any, {
          p_acteur_id: etablissement_id,
          p_type_acteur: "SYSTEME",
          p_action: "VERIFICATION_DOCUMENT",
          p_type_ressource: "etablissement",
          p_id_ressource: etablissement_id,
          p_cle_s3: ribPath,
          p_details: {
            sous_action: "RIB_ETABLISSEMENT_REVUE_OUVERTE",
            cause,
            revue_id: revueId,
            verification_source_version: sourceVersion,
            rib_source_sha256_v1: ribSourceSha256,
            iban_last4: ibanLastFour,
          },
          p_ip: null,
          p_navigateur: "edge-function/verify-rib-etablissement",
        });
        return new Response(JSON.stringify({
          success: true,
          coherent: null,
          verdict: "EN_ATTENTE",
          motif,
          revue_manuelle: true,
          revue_id: revueId,
        }), {
          status: 202,
          headers: { ...corsHeaders(req), "Content-Type": "application/json" },
        });
      } catch (reviewError) {
        console.error(
          "[verify-rib-etablissement] ouverture revue impossible",
          String(reviewError).slice(0, 300),
        );
        return new Response(JSON.stringify({
          success: false,
          code: "REVIEW_QUEUE_FAILED",
          error: "La revue du RIB n'a pas pu être enregistrée. Réessayez.",
        }), {
          status: 503,
          headers: { ...corsHeaders(req), "Content-Type": "application/json" },
        });
      }
    };

    let binary = "";
    for (let i = 0; i < bytes.length; i += 8192) { const chunk = bytes.subarray(i, Math.min(i + 8192, bytes.length)); for (let j = 0; j < chunk.length; j++) binary += String.fromCharCode(chunk[j]); }
    const base64 = btoa(binary);
    const mime = fileValidation.mime;
    const isPdf = mime === "application/pdf";

    const raisonSociale = (etab as any).siret_raison_sociale || (etab as any).finess_raison_sociale || (etab as any).nom || "";

    const systemPrompt = `Tu es un vérificateur de RIB (Relevé d'Identité Bancaire). Analyse le document et réponds UNIQUEMENT en JSON valide:
{
  "est_rib": true/false,
  "titulaire_extrait": "nom du titulaire du compte" ou null,
  "iban_extrait": "IBAN complet sans espaces" ou null,
  "banque": "nom de la banque" ou null,
  "titulaire_correspond": true/false/null,
  "document_lisible": true/false,
  "document_complet": true/false,
  "indices_falsification": [] ou ["..."],
  "score_confiance": 0-100,
  "confiance": "HAUTE"/"MOYENNE"/"FAIBLE",
  "motif": null ou "string",
  "verdict": "VERIFIE"/"EN_ATTENTE"/"REJETE"
}
Règles:
- est_rib = true seulement si c'est bien un RIB (IBAN + BIC + titulaire), pas une facture/contrat/autre. Extrais l'IBAN complet : il sera validé puis supprimé côté serveur.
- titulaire_correspond : compare le titulaire du compte à l'établissement attendu (tolère casse/accents/forme juridique ; un RIB pro est au nom de l'établissement).
- FALSIFICATION : signale toute retouche → verdict EN_ATTENTE.
- verdict REJETE si ce n'est pas un RIB ou illisible.
- verdict VERIFIE si RIB lisible + titulaire correspond + 0 falsification + confiance haute.
- verdict EN_ATTENTE sinon (titulaire différent, doute, falsification).`;
    const userMessage = `RIB à vérifier pour l'établissement:\n- Titulaire attendu (établissement): "${raisonSociale}"\nVérifie que c'est bien un RIB et que le titulaire correspond.`;

    const content: any[] = [{ type: "text", text: userMessage }];
    if (isPdf) content.push({ type: "document", source: { type: "base64", media_type: "application/pdf", data: base64 } });
    else content.push({ type: "image", source: { type: "base64", media_type: mime, data: base64 } });

    const aiController = new AbortController();
    const aiTimeout = setTimeout(() => aiController.abort(), 20000);
    const ai = await appelerAnthropic({ apiKey: anthropicKey, system: systemPrompt, content, maxTokens: 900, signal: aiController.signal });
    clearTimeout(aiTimeout);
    if (!ai.ok && ai.status === 0) {
      const estTimeout = aiController.signal.aborted;
      return mettreEnRevue(
        estTimeout ? "AI_TIMEOUT" : "AI_NETWORK_ERROR",
        estTimeout
          ? "La vérification automatique du RIB a expiré — revue humaine requise."
          : "Le service de vérification du RIB est momentanément inaccessible — revue humaine requise.",
        {
          erreur_anthropic: {
            status: estTimeout ? "timeout" : "network",
            at: new Date().toISOString(),
          },
        },
      );
    }
    if (!ai.ok) {
      return mettreEnRevue(
        `AI_HTTP_${ai.status}`,
        "Le service de vérification du RIB a refusé la demande — revue humaine requise.",
        {
          erreur_anthropic: {
            status: ai.status,
            at: new Date().toISOString(),
          },
        },
      );
    }
    const aiData = ai.data;
    const rawContent = aiData.content?.[0]?.text || "";
    let analysis: any;
    try { const m = rawContent.match(/\{[\s\S]*\}/); analysis = m ? JSON.parse(m[0]) : null; } catch { analysis = null; }
    if (!analysis) {
      return mettreEnRevue(
        "AI_PARSE_ERROR",
        "La réponse automatique sur le RIB était illisible — revue humaine requise.",
        {
          erreur_parse: {
            raw_length: rawContent.length,
            at: new Date().toISOString(),
          },
        },
      );
    }

    const quality = strictAiVerificationQuality(analysis);
    const indicesFalsif = quality.indicators;
    const normalizedIban = normalizeIban(analysis.iban_extrait);
    const ibanPresent = normalizedIban.length > 0;
    const ibanValide = isValidIban(normalizedIban);
    const raisonSocialeMatch = corporateNameMatches(raisonSociale, analysis.titulaire_extrait);
    let coherent: boolean | null = null;
    let motif: string | null = null;
    let causeRevue: string | null = null;

    if (analysis.verdict === "REJETE" || analysis.est_rib === false || analysis.document_lisible === false) {
      coherent = false;
      motif = analysis.motif || "Le document n'est pas un RIB lisible.";
    } else if (ibanPresent && !ibanValide) {
      coherent = false;
      motif = "Le checksum de l'IBAN est invalide.";
    } else if (analysis.titulaire_correspond === false && raisonSocialeMatch === false) {
      coherent = false;
      motif = "Le titulaire du RIB ne correspond pas à l'établissement.";
    } else if (!quality.antifraudComplete) {
      coherent = null;
      motif = "Le contrôle antifraude est absent ou mal formé — vérification manuelle requise.";
      causeRevue = "ANTIFRAUD_INCOMPLETE";
    } else if (indicesFalsif.length > 0) {
      coherent = null;
      motif = "Indices de falsification détectés — vérification manuelle requise.";
      causeRevue = "FALSIFICATION_INDICATORS";
    } else if (
      analysis.verdict === "VERIFIE" && analysis.est_rib === true &&
      analysis.document_lisible === true && analysis.document_complet === true &&
      analysis.titulaire_correspond === true && raisonSocialeMatch === true &&
      ibanValide && quality.highConfidence
    ) {
      coherent = true;
      motif = "RIB vérifié : IBAN valide et titulaire concordant.";
    } else {
      coherent = null;
      motif = analysis.motif || "L'IBAN ou le titulaire doit être confirmé manuellement.";
      causeRevue = "AI_INCONCLUSIVE";
    }

    const analysisPersisted = sanitizeBankAnalysis({
      ...(analysis as Record<string, unknown>),
      score_confiance: quality.score,
      confiance: quality.confidence,
      indices_falsification: indicesFalsif,
      antifraude_complete: quality.antifraudComplete,
    });
    if (coherent === null) {
      return mettreEnRevue(
        causeRevue || "AI_INCONCLUSIVE",
        motif || "Le RIB doit être confirmé manuellement.",
        analysisPersisted,
        normalizedIban || null,
      );
    }
    const applique = await appliquerVerdict(
      coherent,
      {
        ...analysisPersisted,
        verdict_final: coherent ? "VERIFIE" : "REJETE",
        motif_serveur: motif,
        revue_manuelle_requise: false,
        regle_version: "2026-07-14",
      },
      coherent === true ? ibanLast4(normalizedIban) : null,
    );
    if (!applique) return sourceChangee();
    if (coherent === true) {
      await resolveEstablishmentReview(
        supabase as unknown as Parameters<typeof resolveEstablishmentReview>[0],
        etablissement_id,
        "VERIFY_RIB_ETABLISSEMENT",
      );
    }
    await supabase.rpc("fn_ecrire_audit_safe" as any, { p_acteur_id: etablissement_id, p_type_acteur: "SYSTEME", p_action: "VERIFICATION_DOCUMENT", p_type_ressource: "etablissement", p_id_ressource: etablissement_id, p_cle_s3: ribPath, p_details: { sous_action: "RIB_ETABLISSEMENT_IA", coherent, verdict_ia: analysis.verdict, est_rib: analysis.est_rib, antifraude_complete: quality.antifraudComplete, falsification: indicesFalsif.length > 0 }, p_ip: null, p_navigateur: "edge-function/verify-rib-etablissement" });

    return new Response(JSON.stringify({ success: true, coherent, motif, analysis: analysisPersisted }), { headers: { ...corsHeaders(req), "Content-Type": "application/json" } });
  } catch (e: any) {
    console.error("verify-rib-etablissement error:", e);
    return new Response(JSON.stringify({ error: e?.message || "Une erreur interne est survenue." }), { status: 500, headers: { ...corsHeaders(req), "Content-Type": "application/json" } });
  }
});
