import { serve } from "https://deno.land/std@0.168.0/http/server.ts";
import { createClient } from "npm:@supabase/supabase-js@2";

function getCorsOrigin(req: Request): string {
  const origin = req.headers.get("origin") || "";
  if (
    origin === "https://app.jolene.app" ||
    origin === "https://jolene.app" ||
    origin === "http://localhost:5173" ||
    origin === "http://localhost:8080"
  ) {
    return origin;
  }
  return "https://app.jolene.app";
}

function corsHeaders(req: Request) {
  return {
    "Access-Control-Allow-Origin": getCorsOrigin(req),
    "Access-Control-Allow-Headers": "authorization, x-client-info, apikey, content-type, x-supabase-client-platform, x-supabase-client-platform-version, x-supabase-client-runtime, x-supabase-client-runtime-version",
  };
}

function wait(ms: number) {
  return new Promise((resolve) => setTimeout(resolve, ms));
}

async function loadDocumentWithRetry(supabase: any, documentId: string, attempts = 4) {
  for (let attempt = 0; attempt < attempts; attempt++) {
    const { data, error, status, statusText } = await supabase
      .from("documents_soignants")
      .select("id, soignant_id, type_document, nom_fichier, s3_cle, s3_bucket, type_mime")
      .eq("id", documentId)
      .maybeSingle();

    console.log(`[verify-document] attempt ${attempt + 1}: data=${!!data}, error=${error?.message || 'none'}, status=${status}, statusText=${statusText}`);

    if (data) return data;

    // If there's a real error (not just "row not found"), fail immediately
    if (error && !error.message?.includes("not found") && status !== 406) {
      throw new Error(`Erreur base de données: ${error.message}`);
    }

    // Only retry if document simply doesn't exist yet (race condition after insert)
    if (attempt < attempts - 1) await wait(350 * (attempt + 1));
  }
  throw new Error("Document introuvable");
}

serve(async (req) => {
  if (req.method === "OPTIONS") return new Response(null, { headers: corsHeaders(req) });

  try {
    // Auth: verify JWT user or service_role
    const authHeader = req.headers.get("Authorization");
    if (!authHeader?.startsWith("Bearer ")) {
      return new Response(JSON.stringify({ error: "Non autorisé" }), {
        status: 401,
        headers: { ...corsHeaders(req), "Content-Type": "application/json" },
      });
    }

    const supabaseUrl = Deno.env.get("SUPABASE_URL")!;
    const serviceKey = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")!;
    const token = authHeader.replace("Bearer ", "");
    const isServiceRole = token === serviceKey;

    if (!isServiceRole) {
      const supabaseAuth = createClient(supabaseUrl, Deno.env.get("SUPABASE_ANON_KEY")!);
      const { data: { user }, error: authError } = await supabaseAuth.auth.getUser(token);
      if (authError || !user) {
        return new Response(JSON.stringify({ error: "Token invalide" }), {
          status: 401,
          headers: { ...corsHeaders(req), "Content-Type": "application/json" },
        });
      }
    }

    const { document_id } = await req.json();
    if (!document_id) throw new Error("document_id requis");

    const anthropicKey = Deno.env.get("ANTHROPIC_API_KEY");
    if (!anthropicKey) throw new Error("ANTHROPIC_API_KEY non configurée — nécessaire pour la vérification IA des documents");

    const supabase = createClient(supabaseUrl, serviceKey, { auth: { persistSession: false } });

    // 1. Get document info (retry to handle race condition after insert)
    const doc = await loadDocumentWithRetry(supabase, document_id);

    // 2. Get soignant info for name matching
    const { data: soignant } = await supabase
      .from("soignants")
      .select("prenom, nom")
      .eq("id", doc.soignant_id)
      .single();

    // 3. Download document from storage
    const { data: fileData, error: fileErr } = await supabase.storage
      .from(doc.s3_bucket)
      .download(doc.s3_cle);
    if (fileErr || !fileData) throw new Error("Impossible de télécharger le fichier");

    // 4. Convert to base64 (chunked to avoid stack overflow)
    const arrayBuffer = await fileData.arrayBuffer();
    const bytes = new Uint8Array(arrayBuffer);
    const chunkSize = 8192;
    let binary = "";
    for (let i = 0; i < bytes.length; i += chunkSize) {
      const chunk = bytes.subarray(i, Math.min(i + chunkSize, bytes.length));
      for (let j = 0; j < chunk.length; j++) {
        binary += String.fromCharCode(chunk[j]);
      }
    }
    const base64 = btoa(binary);

    // Whitelist allowed MIME types for security
    const ALLOWED_MIME_TYPES = ["image/jpeg", "image/png", "image/webp", "image/heic", "application/pdf"];
    if (doc.type_mime && !ALLOWED_MIME_TYPES.includes(doc.type_mime)) {
      await supabase.rpc("fn_update_document_verification", {
        p_document_id: document_id,
        p_statut_verification: "REJETE",
        p_motif_rejet: `Type de fichier non autorisé: ${doc.type_mime}`,
      });
      return new Response(JSON.stringify({ success: true, verdict: "REJETE", reason: "Unsupported MIME type" }), {
        headers: { ...corsHeaders(req), "Content-Type": "application/json" },
      });
    }

    const isImage = doc.type_mime?.startsWith("image/");
    const isPdf = doc.type_mime === "application/pdf";

    // Type document labels
    const typeLabels: Record<string, string> = {
      CARTE_IDENTITE: "Carte d'identité ou Passeport",
      PASSEPORT: "Passeport",
      TITRE_SEJOUR: "Titre de séjour",
      DIPLOME: "Diplôme d'État",
      RPPS_ADELI: "Attestation RPPS ou ADELI",
      RCP_ASSURANCE: "Assurance Responsabilité Civile Professionnelle",
      RIB: "Relevé d'Identité Bancaire",
      KBIS: "Extrait KBIS",
      ATTESTATION_URSSAF: "Attestation URSSAF",
      AUTORISATION_EXERCICE: "Autorisation d'exercice",
      FORMATION_OBLIGATOIRE: "Certificat de formation obligatoire",
    };

    const typeLabel = typeLabels[doc.type_document] || doc.type_document;
    const nomComplet = soignant ? `${soignant.prenom} ${soignant.nom}` : "inconnu";

    // 5. Call AI for analysis
    const systemPrompt = `Tu es un vérificateur de documents professionnels de santé. Analyse le document fourni et réponds UNIQUEMENT en JSON valide avec cette structure exacte:
{
  "type_correspond": true/false,
  "type_detecte": "string décrivant le type de document détecté",
  "date_expiration": "YYYY-MM-DD" ou null,
  "date_emission": "YYYY-MM-DD" ou null,
  "nom_correspond": true/false/null,
  "nom_detecte": "string" ou null,
  "nom_extrait": "le nom de famille lu sur le document" ou null,
  "prenom_extrait": "le prénom lu sur le document" ou null,
  "score_confiance": 0-100,
  "document_lisible": true/false,
  "document_complet": true/false,
  "confiance": "HAUTE"/"MOYENNE"/"FAIBLE",
  "motif_rejet": null ou "string expliquant le problème",
  "verdict": "VERIFIE"/"EN_ATTENTE"/"REJETE"
}

Règles:
- verdict = "VERIFIE" si type correspond, document lisible et complet, confiance HAUTE
- verdict = "EN_ATTENTE" si doute sur le type, nom, ou confiance MOYENNE
- verdict = "REJETE" si clairement pas le bon type, document illisible/tronqué, ou confiance FAIBLE
- Pour un RIB: pas de date d'expiration, vérifie juste que c'est bien un RIB
- Pour une CNI/Passeport: extrais la date d'expiration si visible
- Pour une assurance RCP: extrais la date de fin de validité
- IMPORTANT: Si le document déclaré est un "Diplôme d'État" mais que le fichier est clairement une carte d'identité, passeport ou tout autre document non-diplôme, verdict = "REJETE" avec motif "Le document fourni n'est pas un diplôme"`;

    const userMessage = `Document déclaré comme: "${typeLabel}"
Nom du soignant: "${nomComplet}"
Fichier: ${doc.nom_fichier}

Analyse ce document et vérifie sa conformité.`;

    const messages: any[] = [
      { role: "system", content: systemPrompt },
    ];

    // Gemini supports PDF and images natively via data URL
    const mimeType = isPdf ? "application/pdf" : (doc.type_mime || "application/octet-stream");

    if (isImage || isPdf) {
      messages.push({
        role: "user",
        content: [
          { type: "text", text: userMessage },
          {
            type: "image_url",
            image_url: { url: `data:${mimeType};base64,${base64}` },
          },
        ],
      });
    } else {
      messages.push({ role: "user", content: userMessage });
    }

    // Anthropic Claude API pour la vérification IA
    let aiResponse: Response | null = null;
    let aiSource = "anthropic";

    {
      const anthropicKey = Deno.env.get("ANTHROPIC_API_KEY");
      if (anthropicKey) {
        aiSource = "anthropic";
        console.log("Falling back to Anthropic API");
        const anthropicMessages = [];
        const lastMsg = messages[messages.length - 1];
        if (Array.isArray(lastMsg.content)) {
          const anthropicContent = lastMsg.content.map((block: any) => {
            if (block.type === "text") return { type: "text", text: block.text };
            if (block.type === "image_url") {
              const dataUrl = block.image_url.url;
              const match = dataUrl.match(/^data:([^;]+);base64,(.+)$/);
              if (match) {
                return { type: "image", source: { type: "base64", media_type: match[1], data: match[2] } };
              }
            }
            return { type: "text", text: "[unsupported block]" };
          });
          anthropicMessages.push({ role: "user", content: anthropicContent });
        } else {
          anthropicMessages.push({ role: "user", content: lastMsg.content });
        }

        aiResponse = await fetch("https://api.anthropic.com/v1/messages", {
          method: "POST",
          headers: {
            "x-api-key": anthropicKey,
            "anthropic-version": "2023-06-01",
            "Content-Type": "application/json",
          },
          body: JSON.stringify({
            model: "claude-sonnet-4-20250514",
            max_tokens: 1000,
            system: messages[0].content,
            messages: anthropicMessages,
          }),
        });

        if (!aiResponse.ok) {
          console.error("Anthropic API also failed:", aiResponse.status);
        }
      }
    }

    if (!aiResponse || !aiResponse.ok) {
      await supabase.rpc("fn_update_document_verification", {
        p_document_id: document_id, p_statut_verification: "EN_ATTENTE", p_motif_rejet: null,
      });
      return new Response(JSON.stringify({ success: true, verdict: "EN_ATTENTE", reason: "AI unavailable" }), {
        headers: { ...corsHeaders(req), "Content-Type": "application/json" },
      });
    }

    const aiData = await aiResponse.json();
    // Handle both OpenAI format (Lovable) and Anthropic format
    let rawContent = "";
    if (aiSource === "anthropic") {
      rawContent = aiData.content?.[0]?.text || "";
    } else {
      rawContent = aiData.choices?.[0]?.message?.content || "";
    }
    const content = rawContent;

    // Parse JSON from response
    let analysis: any;
    try {
      const jsonMatch = content.match(/\{[\s\S]*\}/);
      analysis = jsonMatch ? JSON.parse(jsonMatch[0]) : null;
    } catch {
      analysis = null;
    }

    if (!analysis) {
      await supabase.rpc("fn_update_document_verification", {
        p_document_id: document_id, p_statut_verification: "EN_ATTENTE",
      });

      return new Response(JSON.stringify({ success: true, verdict: "EN_ATTENTE", reason: "Parse error" }), {
        headers: { ...corsHeaders(req), "Content-Type": "application/json" },
      });
    }

    // 6. Update document with results via RPC (bypasses protective triggers)
    await supabase.rpc("fn_update_document_verification", {
      p_document_id: document_id,
      p_statut_verification: analysis.verdict || "EN_ATTENTE",
      p_motif_rejet: analysis.motif_rejet || null,
      p_valide_depuis: analysis.date_emission || null,
      p_valide_jusqua: analysis.date_expiration || null,
      p_verifie_le: analysis.verdict === "VERIFIE" ? new Date().toISOString() : null,
    });

    // 6b. Store AI-extracted name fields for identity cross-check
    const nomExtraitIa = analysis.nom_extrait || null;
    const prenomExtraitIa = analysis.prenom_extrait || null;
    const scoreConfianceIa = typeof analysis.score_confiance === "number" ? analysis.score_confiance : null;

    // Normalize for accent-insensitive, composite-name-tolerant comparison
    // Same logic as verify-rpps: NFD decompose + strip diacriticals + lowercase + trim
    const normalize = (s: string) => (s || "").toLowerCase().normalize("NFD").replace(/[\u0300-\u036f]/g, "").trim();
    const nomDocNorm = normalize(nomExtraitIa || "");
    const nomProfilNorm = normalize(soignant?.nom || "");
    const prenomDocNorm = normalize(prenomExtraitIa || "");
    const prenomProfilNorm = normalize(soignant?.prenom || "");

    // Bidirectional containment (handles composite names: "DUPONT-MARTIN" matches "DUPONT")
    const nomMatch = nomDocNorm && nomProfilNorm
      ? nomDocNorm.includes(nomProfilNorm) || nomProfilNorm.includes(nomDocNorm)
      : null;
    // First 3 chars for first name (handles "Jean-Pierre" vs "Jean")
    const prenomMatch = prenomDocNorm && prenomProfilNorm
      ? prenomDocNorm.slice(0, 3) === prenomProfilNorm.slice(0, 3)
      : null;
    const coherenceNom = nomMatch !== null ? (nomMatch && (prenomMatch === null || prenomMatch)) : null;

    await supabase.from("documents_soignants").update({
      resultat_ia: analysis,
      nom_extrait_ia: nomExtraitIa,
      prenom_extrait_ia: prenomExtraitIa,
      score_confiance_ia: scoreConfianceIa,
      coherence_nom: coherenceNom,
    } as any).eq("id", document_id);

    // 7. Audit
    await supabase.rpc("fn_ecrire_audit_safe" as any, {
      p_acteur_id: doc.soignant_id,
      p_type_acteur: "SYSTEME",
      p_action: "DOCUMENT_VERIFICATION_AUTO",
      p_type_ressource: "document",
      p_id_ressource: document_id,
      p_cle_s3: doc.s3_cle,
      p_details: {
        verdict: analysis.verdict,
        type_detecte: analysis.type_detecte,
        confiance: analysis.confiance,
        nom_correspond: analysis.nom_correspond,
        type_correspond: analysis.type_correspond,
      },
      p_ip: null,
      p_navigateur: "edge-function/verify-document",
    });

    return new Response(
      JSON.stringify({ success: true, verdict: analysis.verdict, analysis }),
      { headers: { ...corsHeaders(req), "Content-Type": "application/json" } }
    );
  } catch (e) {
    console.error("verify-document error:", e);
    return new Response(
      JSON.stringify({ error: "Une erreur interne est survenue." }),
      { status: 500, headers: { ...corsHeaders(req), "Content-Type": "application/json" } }
    );
  }
});
