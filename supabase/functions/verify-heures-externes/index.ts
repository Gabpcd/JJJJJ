import { createClient } from "npm:@supabase/supabase-js@2";
import { applyRateLimit, getClientIp } from "../_shared/rate-limit.ts";
import { appelerAnthropic } from "../_shared/anthropic.ts";
import { corsHeaders } from "../_shared/cors.ts";
import {
  corporateNameMatches,
  normalizeIsoCivilDate,
  personNameMatches,
  strictAiVerificationQuality,
  validateDocumentFile,
} from "../_shared/verification-rules.ts";

// Vérification IA d'une attestation d'heures externes (parcours 3200h libéral).
// Lit le document téléversé via Anthropic Vision, extrait le nombre d'heures +
// l'établissement + la période, et confronte au déclaré. Aucun résultat IA ne
// passe automatiquement à VALIDE : seuls les fichiers conclusivement invalides
// peuvent être rejetés ; tous les autres attendent une décision admin AAL2.

function wait(ms: number) {
  return new Promise((resolve) => setTimeout(resolve, ms));
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

async function loadHeureWithRetry(supabase: any, id: string, attempts = 4) {
  for (let attempt = 0; attempt < attempts; attempt++) {
    const { data, error, status, statusText } = await supabase
      .from("heures_externes_soignants")
      .select("id, soignant_id, etablissement_nom, etablissement_type, date_debut, date_fin, heures_declarees, attestation_url, attestation_nom_fichier, version_source")
      .eq("id", id)
      .maybeSingle();

    console.log(`[verify-heures-externes] attempt ${attempt + 1}: data=${!!data}, error=${error?.message || 'none'}, status=${status}, statusText=${statusText}`);

    if (data) return data;

    if (error && !error.message?.includes("not found") && status !== 406) {
      throw new Error(`Erreur base de données: ${error.message}`);
    }

    if (attempt < attempts - 1) await wait(350 * (attempt + 1));
  }
  throw new Error("Déclaration d'heures introuvable");
}

// Fallback réservé aux anciens objets dont Storage ne conservait pas le MIME.
function devinerMime(nom: string | null): string {
  const n = (nom || "").toLowerCase();
  if (n.endsWith(".pdf")) return "application/pdf";
  if (n.endsWith(".png")) return "image/png";
  if (n.endsWith(".webp")) return "image/webp";
  return "image/jpeg";
}

function snapshotSource(ligne: any) {
  return {
    id: ligne.id,
    soignant_id: ligne.soignant_id,
    etablissement_nom: ligne.etablissement_nom,
    etablissement_type: ligne.etablissement_type ?? null,
    date_debut: ligne.date_debut,
    date_fin: ligne.date_fin,
    heures_declarees: ligne.heures_declarees,
    attestation_url: ligne.attestation_url,
    attestation_nom_fichier: ligne.attestation_nom_fichier ?? null,
    version_source: ligne.version_source,
  };
}

async function sha256Hex(bytes: Uint8Array): Promise<string> {
  const copied = Uint8Array.from(bytes);
  const digest = await crypto.subtle.digest("SHA-256", copied.buffer);
  return Array.from(new Uint8Array(digest))
    .map((octet) => octet.toString(16).padStart(2, "0"))
    .join("");
}

async function finaliserVerification(
  supabaseAdmin: any,
  ligne: any,
  params: {
    empreintePreuve: string;
    verdict: "EN_ATTENTE" | "REJETE";
    rejetConclusif: boolean;
    heuresExtraites: number | null;
    coherence: boolean | null;
    resultat: Record<string, unknown>;
    commentaire: string;
  },
) {
  const { data, error } = await supabaseAdmin.rpc(
    "fn_service_finaliser_heures_externes",
    {
      p_id: ligne.id,
      p_snapshot_source: snapshotSource(ligne),
      p_empreinte_preuve_sha256: params.empreintePreuve,
      p_verdict: params.verdict,
      p_rejet_conclusif: params.rejetConclusif,
      p_heures_extraites: params.heuresExtraites,
      p_coherence: params.coherence,
      p_resultat_ia: params.resultat,
      p_commentaire: params.commentaire,
    },
  );
  if (error) throw error;
  return data as {
    success?: boolean;
    statut?: "EN_ATTENTE" | "REJETE";
    error_code?: string;
    error?: string;
    preuve_dupliquee?: boolean;
  } | null;
}

function reponseConflitFinalisation(req: Request, resultat: { error?: string } | null) {
  return new Response(
    JSON.stringify({ error: resultat?.error || "La déclaration a changé pendant la vérification" }),
    {
      status: 409,
      headers: { ...corsHeaders(req), "Content-Type": "application/json" },
    },
  );
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
        status: 401,
        headers: { ...corsHeaders(req), "Content-Type": "application/json" },
      });
    }

    const supabaseUrl = Deno.env.get("SUPABASE_URL")!;
    const serviceKey = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")!;
    const token = authHeader.replace("Bearer ", "");
    const supabaseAdmin = createClient(supabaseUrl, serviceKey, { auth: { persistSession: false } });
    const vaultSecret = await getVaultSecret(supabaseAdmin);
    const isServiceRole = token === serviceKey || (vaultSecret && token === vaultSecret);

    let authUserId: string | null = null;
    if (!isServiceRole) {
      const supabaseAuth = createClient(supabaseUrl, Deno.env.get("SUPABASE_ANON_KEY")!);
      const { data: { user }, error: authError } = await supabaseAuth.auth.getUser(token);
      if (authError || !user) {
        return new Response(JSON.stringify({ error: "Token invalide" }), {
          status: 401,
          headers: { ...corsHeaders(req), "Content-Type": "application/json" },
        });
      }
      authUserId = user.id;
      if (applyRateLimit('verify-heures-externes', getClientIp(req), { max: 10, windowMs: 60_000 })) {
        return new Response(JSON.stringify({ error: 'Trop de vérifications. Réessayez dans 1 minute.' }), {
          status: 429,
          headers: { ...corsHeaders(req), 'Content-Type': 'application/json' },
        });
      }
    }

    const action = typeof body?.action === "string" ? body.action : "verify";
    const heure_externe_id = body?.heure_externe_id;

    if (action === "cleanup_orphan") {
      if (isServiceRole || !authUserId) {
        return new Response(JSON.stringify({ error: "Action réservée au propriétaire du dépôt" }), {
          status: 403,
          headers: { ...corsHeaders(req), "Content-Type": "application/json" },
        });
      }
      const path = String(body?.attestation_url || "");
      const pathAutorise = path.startsWith(`${authUserId}/heures-externes/`)
        && !path.includes("..")
        && !path.includes("\\");
      if (!pathAutorise) {
        return new Response(JSON.stringify({ error: "Chemin d'attestation non autorisé" }), {
          status: 403,
          headers: { ...corsHeaders(req), "Content-Type": "application/json" },
        });
      }
      const { data: reference, error: referenceError } = await supabaseAdmin.from("heures_externes_soignants")
        .select("id")
        .eq("attestation_url", path)
        .limit(1)
        .maybeSingle();
      if (referenceError) throw referenceError;
      if (reference) {
        return new Response(JSON.stringify({ error: "Cette attestation est déjà rattachée à une déclaration" }), {
          status: 409,
          headers: { ...corsHeaders(req), "Content-Type": "application/json" },
        });
      }
      const { error: removeError } = await supabaseAdmin.storage.from("jolene-documents").remove([path]);
      if (removeError) throw new Error("Nettoyage du dépôt incomplet");
      return new Response(JSON.stringify({ success: true }), {
        headers: { ...corsHeaders(req), "Content-Type": "application/json" },
      });
    }

    if (action === "delete") {
      if (!heure_externe_id) throw new Error("heure_externe_id requis");
      const { data: ligneASupprimer, error: ligneError } = await supabaseAdmin
        .from("heures_externes_soignants")
        .select("id, soignant_id, statut_validation, attestation_url")
        .eq("id", heure_externe_id)
        .maybeSingle();
      if (ligneError) throw ligneError;
      if (!ligneASupprimer) {
        // Reprise idempotente : si la ligne a déjà été supprimée mais
        // que le nettoyage Storage a échoué, le propriétaire peut renvoyer
        // le chemin qu'il avait reçu. Aucune autre preuve de son espace ne peut
        // être ciblée par cette branche.
        const retryPath = String(body?.attestation_url || "");
        const nouveauChemin = authUserId && retryPath.startsWith(`${authUserId}/heures-externes/`);
        const ancienChemin = authUserId
          && retryPath.startsWith(`${authUserId}/`)
          && retryPath.slice(`${authUserId}/`.length).length > 0
          && !retryPath.slice(`${authUserId}/`.length).includes("/");
        if (!isServiceRole && authUserId && (nouveauChemin || ancienChemin)
          && !retryPath.includes("..") && !retryPath.includes("\\")) {
          const { data: reference, error: referenceError } = await supabaseAdmin
            .from("heures_externes_soignants")
            .select("id")
            .eq("attestation_url", retryPath)
            .limit(1)
            .maybeSingle();
          if (referenceError) throw referenceError;
          if (!reference) {
            const retryBucket = nouveauChemin ? "jolene-documents" : "attestations-heures-externes";
            const { error: retryRemoveError } = await supabaseAdmin.storage.from(retryBucket).remove([retryPath]);
            if (retryRemoveError) throw new Error("Suppression du fichier impossible");
            return new Response(JSON.stringify({ success: true, resumed_cleanup: true }), {
              headers: { ...corsHeaders(req), "Content-Type": "application/json" },
            });
          }
        }
        return new Response(JSON.stringify({ error: "Déclaration introuvable" }), {
          status: 404,
          headers: { ...corsHeaders(req), "Content-Type": "application/json" },
        });
      }
      if (!isServiceRole && ligneASupprimer.soignant_id !== authUserId) {
        return new Response(JSON.stringify({ error: "Accès refusé" }), {
          status: 403,
          headers: { ...corsHeaders(req), "Content-Type": "application/json" },
        });
      }
      if (!isServiceRole && ligneASupprimer.statut_validation !== "EN_ATTENTE") {
        return new Response(JSON.stringify({ error: "Seule une déclaration en attente peut être supprimée" }), {
          status: 409,
          headers: { ...corsHeaders(req), "Content-Type": "application/json" },
        });
      }
      const path = ligneASupprimer.attestation_url ? String(ligneASupprimer.attestation_url) : null;
      if (path && (!path.startsWith(`${ligneASupprimer.soignant_id}/`) || path.includes("..") || path.includes("\\"))) {
        return new Response(JSON.stringify({ error: "Chemin d'attestation non autorisé" }), {
          status: 403,
          headers: { ...corsHeaders(req), "Content-Type": "application/json" },
        });
      }
      let deleteQuery = supabaseAdmin.from("heures_externes_soignants")
        .delete()
        .eq("id", heure_externe_id)
        .eq("soignant_id", ligneASupprimer.soignant_id);
      if (!isServiceRole) deleteQuery = deleteQuery.eq("statut_validation", "EN_ATTENTE");
      const { data: deleted, error: deleteError } = await deleteQuery.select("id").maybeSingle();
      if (deleteError) throw new Error("Suppression de la déclaration impossible");
      if (!deleted) {
        return new Response(JSON.stringify({ error: "La déclaration a changé ; actualisez avant de la supprimer" }), {
          status: 409,
          headers: { ...corsHeaders(req), "Content-Type": "application/json" },
        });
      }
      // La ligne est supprimée en premier : un incident Storage ne laisse
      // jamais une preuve référencée mais introuvable. Le chemin envoyé par
      // le client permet une reprise idempotente au prochain essai.
      if (path) {
        const bucket = path.includes("/heures-externes/")
          ? "jolene-documents"
          : "attestations-heures-externes";
        const { error: removeError } = await supabaseAdmin.storage.from(bucket).remove([path]);
        if (removeError) throw new Error("Déclaration supprimée, mais nettoyage du fichier à reprendre");
      }
      return new Response(JSON.stringify({ success: true }), {
        headers: { ...corsHeaders(req), "Content-Type": "application/json" },
      });
    }

    if (action !== "verify") {
      return new Response(JSON.stringify({ error: "Action inconnue" }), {
        status: 400,
        headers: { ...corsHeaders(req), "Content-Type": "application/json" },
      });
    }
    if (!heure_externe_id) throw new Error("heure_externe_id requis");

    const anthropicKey = Deno.env.get("ANTHROPIC_API_KEY");

    const supabase = supabaseAdmin;
    const ligne = await loadHeureWithRetry(supabase, heure_externe_id);

    // Charger nom/prénom du soignant pour gate concordance identité.
    const { data: soignantData } = await supabase
      .from("soignants")
      .select("nom, prenom")
      .eq("id", ligne.soignant_id)
      .maybeSingle();
    const soignantNom = (soignantData as any)?.nom || "";
    const soignantPrenom = (soignantData as any)?.prenom || "";
    const nomCompletSoignant = `${soignantPrenom} ${soignantNom}`.trim();

    // Sécurité : un soignant ne peut vérifier que SES propres déclarations.
    if (!isServiceRole && authUserId && ligne.soignant_id !== authUserId) {
      return new Response(JSON.stringify({ error: "Accès refusé" }), {
        status: 403,
        headers: { ...corsHeaders(req), "Content-Type": "application/json" },
      });
    }

    if (!ligne.attestation_url) {
      // Pas d'attestation → impossible de vérifier par IA, on laisse EN_ATTENTE.
      return new Response(JSON.stringify({ success: true, verdict: "EN_ATTENTE", reason: "Aucune attestation" }), {
        headers: { ...corsHeaders(req), "Content-Type": "application/json" },
      });
    }

    const attestationPath = String(ligne.attestation_url);
    if (
      !attestationPath.startsWith(`${ligne.soignant_id}/`)
      || attestationPath.includes("..")
      || attestationPath.includes("\\")
    ) {
      return new Response(JSON.stringify({ error: "Chemin d'attestation non autorisé" }), {
        status: 403,
        headers: { ...corsHeaders(req), "Content-Type": "application/json" },
      });
    }

    // Lecture CAS avant tout appel externe ; la RPC de finalisation répète ce
    // contrôle sous FOR UPDATE sur le snapshot complet.
    const { data: sourceCourante, error: sourceError } = await supabase
      .from("heures_externes_soignants")
      .select("id")
      .eq("id", heure_externe_id)
      .eq("attestation_url", attestationPath)
      .eq("version_source", ligne.version_source)
      .eq("statut_validation", "EN_ATTENTE")
      .maybeSingle();
    if (sourceError) throw sourceError;
    if (!sourceCourante) {
      return reponseConflitFinalisation(req, null);
    }

    // Les nouveaux dépôts utilisent le bucket privé reproductible. Le fallback
    // conserve la lecture des attestations historiques sans déplacer les données.
    const nouveauBucket = attestationPath.includes("/heures-externes/");
    const bucketPrincipal = nouveauBucket ? "jolene-documents" : "attestations-heures-externes";
    const bucketSecours = nouveauBucket ? "attestations-heures-externes" : "jolene-documents";
    let { data: fileData, error: fileErr } = await supabase.storage
      .from(bucketPrincipal)
      .download(attestationPath);
    if (fileErr || !fileData) {
      const fallback = await supabase.storage.from(bucketSecours).download(attestationPath);
      fileData = fallback.data;
      fileErr = fallback.error;
    }
    if (fileErr || !fileData) throw new Error("Impossible de télécharger l'attestation");

    const arrayBuffer = await fileData.arrayBuffer();
    const bytes = new Uint8Array(arrayBuffer);
    const empreintePreuve = await sha256Hex(bytes);
    const declaredMime = fileData.type && fileData.type !== "application/octet-stream"
      ? fileData.type
      : devinerMime(ligne.attestation_nom_fichier);
    const fileValidation = validateDocumentFile(bytes, declaredMime);
    if (!fileValidation.ok) {
      const motifs: Record<string, string> = {
        EMPTY: "L'attestation est vide.",
        TOO_LARGE: "L'attestation dépasse 10 Mo.",
        UNSUPPORTED_MIME: "Le type de l'attestation n'est pas autorisé.",
        INVALID_SIGNATURE: "Le contenu de l'attestation ne correspond pas à son format déclaré.",
      };
      const motif = motifs[fileValidation.code];
      const rejected = await finaliserVerification(supabaseAdmin, ligne, {
        empreintePreuve,
        verdict: "REJETE",
        rejetConclusif: true,
        heuresExtraites: null,
        coherence: null,
        resultat: {
          controle_fichier: fileValidation.code,
          rejet_conclusif_serveur: true,
        },
        commentaire: motif,
      });
      if (!rejected?.success) return reponseConflitFinalisation(req, rejected);
      return new Response(JSON.stringify({ success: true, verdict: "REJETE", reason: motif }), {
        headers: { ...corsHeaders(req), "Content-Type": "application/json" },
      });
    }
    if (!anthropicKey) {
      const pending = await finaliserVerification(supabaseAdmin, ligne, {
        empreintePreuve,
        verdict: "EN_ATTENTE",
        rejetConclusif: false,
        heuresExtraites: null,
        coherence: null,
        resultat: { erreur_anthropic: { status: "configuration_absente" } },
        commentaire: "Analyse automatique indisponible. Revue manuelle requise.",
      });
      if (!pending?.success) return reponseConflitFinalisation(req, pending);
      return new Response(JSON.stringify({ success: true, verdict: "EN_ATTENTE", reason: "AI unavailable" }), {
        headers: { ...corsHeaders(req), "Content-Type": "application/json" },
      });
    }
    const chunkSize = 8192;
    let binary = "";
    for (let i = 0; i < bytes.length; i += chunkSize) {
      const chunk = bytes.subarray(i, Math.min(i + chunkSize, bytes.length));
      for (let j = 0; j < chunk.length; j++) {
        binary += String.fromCharCode(chunk[j]);
      }
    }
    const base64 = btoa(binary);

    const mimeEffectif = fileValidation.mime;
    const isPdf = mimeEffectif === "application/pdf";

    const systemPrompt = `Tu es un vérificateur d'attestations d'heures de travail pour des soignants (parcours d'installation en libéral, seuil réglementaire d'expérience). Analyse le document fourni et réponds UNIQUEMENT en JSON valide avec cette structure exacte:
{
  "est_attestation_heures": true/false,
  "type_detecte": "string décrivant le type de document détecté",
  "heures_total": nombre entier d'heures travaillées lu sur le document ou null,
  "etablissement_detecte": "string" ou null,
  "date_debut_detectee": "YYYY-MM-DD" ou null,
  "date_fin_detectee": "YYYY-MM-DD" ou null,
  "nom_extrait": "le nom de famille lu sur le document" ou null,
  "prenom_extrait": "le prénom lu sur le document" ou null,
  "nom_correspond": true/false/null,
  "document_lisible": true/false,
  "document_complet": true/false,
  "score_confiance": 0-100,
  "confiance": "HAUTE"/"MOYENNE"/"FAIBLE",
  "indices_falsification": ["liste des indices de retouche/montage détectés"] ou [],
  "motif_rejet": null ou "string expliquant le problème",
  "verdict": "VERIFIE"/"EN_ATTENTE"/"REJETE"
}

Règles:
- Une attestation d'heures peut être : attestation d'employeur, certificat de travail, contrat + relevés, bulletins de paie cumulés, attestation Pôle emploi/France Travail.
- "heures_total" = nombre TOTAL d'heures travaillées sur la période. Si le document donne un nombre de mois/années sans heures précises, estime à null (ne devine pas).
- nom_correspond : compare le nom/prénom lu sur le document au nom du soignant fourni (tolère casse/accents/ordre). null si aucun nom lisible.
- document_complet = true seulement si toutes les pages/zones utiles à l'identité, la période et aux heures sont visibles.
- DÉTECTION DE FALSIFICATION : examine les signes de retouche/montage (polices incohérentes, bords de texte flous/pixellisés, zones recouvertes, arrière-plan altéré). Liste tout signe dans "indices_falsification". Au moindre indice sérieux, verdict = "EN_ATTENTE" et motif_rejet = "Indices de falsification détectés".
- verdict = "VERIFIE" si c'est bien une attestation d'heures lisible, mentionnant un volume d'heures, confiance HAUTE, ET nom_correspond = true.
- verdict = "EN_ATTENTE" si document lisible mais volume d'heures absent/ambigu, ou confiance MOYENNE, ou nom_correspond = false/null.
- verdict = "REJETE" si ce n'est clairement PAS une attestation d'heures/de travail, ou document illisible/tronqué, ou confiance FAIBLE.`;

    const userMessage = `Attestation déclarée pour:
- Soignant déclaré: "${nomCompletSoignant}"
- Établissement déclaré: "${ligne.etablissement_nom}"${ligne.etablissement_type ? ` (${ligne.etablissement_type})` : ""}
- Période déclarée: du ${ligne.date_debut} au ${ligne.date_fin}
- Heures déclarées: ${ligne.heures_declarees} h
Fichier: ${ligne.attestation_nom_fichier || "attestation"}

Lis le document, extrais le nombre réel d'heures travaillées, l'établissement, la période, et vérifie la concordance du nom avec le soignant déclaré.`;

    const anthropicContent: any[] = [{ type: "text", text: userMessage }];
    if (isPdf) {
      anthropicContent.push({
        type: "document",
        source: { type: "base64", media_type: "application/pdf", data: base64 },
      });
    } else {
      anthropicContent.push({
        type: "image",
        source: { type: "base64", media_type: mimeEffectif, data: base64 },
      });
    }

    const aiController = new AbortController();
    const aiTimeout = setTimeout(() => aiController.abort(), 20_000);
    let ai;
    try {
      ai = await appelerAnthropic({
        apiKey: anthropicKey,
        system: systemPrompt,
        content: anthropicContent,
        maxTokens: 1000,
        signal: aiController.signal,
      });
    } catch (e) {
      clearTimeout(aiTimeout);
      const estTimeout = (e as any)?.name === "AbortError";
      console.error("Anthropic call failed:", estTimeout ? "timeout 20s" : e);
      const pending = await finaliserVerification(supabaseAdmin, ligne, {
        empreintePreuve,
        verdict: "EN_ATTENTE",
        rejetConclusif: false,
        heuresExtraites: null,
        coherence: null,
        resultat: {
          erreur_anthropic: { status: estTimeout ? "timeout" : "network" },
        },
        commentaire: "Analyse automatique indisponible. Revue manuelle requise.",
      });
      if (!pending?.success) return reponseConflitFinalisation(req, pending);
      return new Response(JSON.stringify({ success: true, verdict: "EN_ATTENTE", reason: estTimeout ? "AI timeout" : "AI network error" }), {
        headers: { ...corsHeaders(req), "Content-Type": "application/json" },
      });
    }
    clearTimeout(aiTimeout);

    if (!ai.ok) {
      const errText = ai.body;
      console.error("Anthropic API failed:", ai.status, errText);
      const pending = await finaliserVerification(supabaseAdmin, ligne, {
        empreintePreuve,
        verdict: "EN_ATTENTE",
        rejetConclusif: false,
        heuresExtraites: null,
        coherence: null,
        resultat: {
          erreur_anthropic: { status: ai.status, body_length: errText.length },
        },
        commentaire: "Analyse automatique indisponible. Revue manuelle requise.",
      });
      if (!pending?.success) return reponseConflitFinalisation(req, pending);
      return new Response(JSON.stringify({ success: true, verdict: "EN_ATTENTE", reason: "AI unavailable" }), {
        headers: { ...corsHeaders(req), "Content-Type": "application/json" },
      });
    }

    const aiData = ai.data;
    const rawContent = aiData.content?.[0]?.text || "";

    let analysis: any;
    try {
      const jsonMatch = rawContent.match(/\{[\s\S]*\}/);
      analysis = jsonMatch ? JSON.parse(jsonMatch[0]) : null;
    } catch {
      analysis = null;
    }

    if (!analysis) {
      const pending = await finaliserVerification(supabaseAdmin, ligne, {
        empreintePreuve,
        verdict: "EN_ATTENTE",
        rejetConclusif: false,
        heuresExtraites: null,
        coherence: null,
        resultat: { erreur_parse: { raw_length: rawContent.length } },
        commentaire: "Résultat automatique inexploitable. Revue manuelle requise.",
      });
      if (!pending?.success) return reponseConflitFinalisation(req, pending);
      return new Response(JSON.stringify({ success: true, verdict: "EN_ATTENTE", reason: "Parse error" }), {
        headers: { ...corsHeaders(req), "Content-Type": "application/json" },
      });
    }

    // Gates côté code (concordance identité + falsification, comme verify-document).
    const quality = strictAiVerificationQuality(analysis);
    const indicesFalsif = quality.indicators;
    const nomCorrespond = personNameMatches(
      soignantNom,
      soignantPrenom,
      analysis.nom_extrait,
      analysis.prenom_extrait,
    );
    const etablissementCorrespond = corporateNameMatches(
      ligne.etablissement_nom,
      analysis.etablissement_detecte,
    );
    const dateDebutExtraite = normalizeIsoCivilDate(analysis.date_debut_detectee);
    const dateFinExtraite = normalizeIsoCivilDate(analysis.date_fin_detectee);
    const periodeCorrespond = dateDebutExtraite && dateFinExtraite
      ? dateDebutExtraite <= ligne.date_debut && dateFinExtraite >= ligne.date_fin
      : null;

    // Cohérence heures extraites vs déclarées : tolérance = max(5% du déclaré, 40h).
    const heuresExtraites = typeof analysis.heures_total === "number" && Number.isFinite(analysis.heures_total)
      ? Math.round(analysis.heures_total)
      : null;
    const declare = Number(ligne.heures_declarees) || 0;
    const tolerance = Math.max(declare * 0.05, 40);
    let coherence: boolean | null = null;
    if (heuresExtraites !== null) {
      coherence = Math.abs(heuresExtraites - declare) <= tolerance;
    }

    // Un rejet IA n'est conclusif que si le document complet et lisible est
    // clairement d'un autre type, à haute confiance, sans contrôle antifraude
    // incomplet. Identité, établissement, période ou heures divergents restent
    // des signaux de revue : ils ne déclenchent jamais seuls un rejet.
    const rejetConclusif = analysis.est_attestation_heures === false
      && analysis.document_lisible === true
      && analysis.document_complet === true
      && quality.highConfidence
      && quality.antifraudComplete
      && indicesFalsif.length === 0;

    let statut: "EN_ATTENTE" | "REJETE" = rejetConclusif ? "REJETE" : "EN_ATTENTE";
    let commentaire: string;
    if (rejetConclusif) {
      commentaire = typeof analysis.motif_rejet === "string" && analysis.motif_rejet.trim()
        ? analysis.motif_rejet.trim().slice(0, 1000)
        : "Le fichier lisible n'est conclusivement pas une attestation d'heures.";
    } else if (nomCorrespond === false) {
      commentaire = "L'identité lue diverge du profil. Revue manuelle requise.";
    } else if (etablissementCorrespond === false) {
      commentaire = "L'établissement lu diverge de la déclaration. Revue manuelle requise.";
    } else if (periodeCorrespond === false) {
      commentaire = "La période lue ne couvre pas la période déclarée. Revue manuelle requise.";
    } else if (!quality.antifraudComplete || indicesFalsif.length > 0) {
      commentaire = indicesFalsif.length > 0
        ? `Indices à examiner : ${indicesFalsif.join(", ")}`.slice(0, 1000)
        : "Contrôle antifraude incomplet. Revue manuelle requise.";
    } else if (
      analysis.verdict === "VERIFIE"
      && analysis.est_attestation_heures === true
      && analysis.document_lisible === true
      && analysis.document_complet === true
      && quality.highConfidence
      && declare > 0
      && heuresExtraites !== null
      && coherence === true
      && nomCorrespond === true
      && etablissementCorrespond === true
      && periodeCorrespond === true
    ) {
      commentaire = `Contrôles automatiques concordants (${heuresExtraites} h lues). Validation humaine requise.`;
    } else if (heuresExtraites !== null && coherence === false) {
      commentaire = `Écart détecté : ${heuresExtraites} h lues vs ${declare} h déclarées. Revue manuelle requise.`;
    } else {
      commentaire = "Volume ou concordances non établis avec certitude. Revue manuelle requise.";
    }

    const resultatPersisted = {
      est_attestation_heures: typeof analysis.est_attestation_heures === "boolean" ? analysis.est_attestation_heures : null,
      type_detecte: typeof analysis.type_detecte === "string" ? analysis.type_detecte.slice(0, 200) : null,
      heures_total: heuresExtraites,
      etablissement_detecte: typeof analysis.etablissement_detecte === "string" ? analysis.etablissement_detecte.slice(0, 300) : null,
      date_debut_detectee: dateDebutExtraite,
      date_fin_detectee: dateFinExtraite,
      nom_extrait: typeof analysis.nom_extrait === "string" ? analysis.nom_extrait.slice(0, 150) : null,
      prenom_extrait: typeof analysis.prenom_extrait === "string" ? analysis.prenom_extrait.slice(0, 150) : null,
      document_lisible: typeof analysis.document_lisible === "boolean" ? analysis.document_lisible : null,
      document_complet: typeof analysis.document_complet === "boolean" ? analysis.document_complet : null,
      score_confiance: quality.score,
      confiance: quality.confidence,
      indices_falsification: indicesFalsif,
      verdict: typeof analysis.verdict === "string" ? analysis.verdict.slice(0, 30) : null,
      identite_match_serveur: nomCorrespond,
      etablissement_match_serveur: etablissementCorrespond,
      periode_match_serveur: periodeCorrespond,
      coherence_heures_serveur: coherence,
      rejet_conclusif_serveur: rejetConclusif,
    };
    const finalisation = await finaliserVerification(supabaseAdmin, ligne, {
      empreintePreuve,
      verdict: statut,
      rejetConclusif,
      heuresExtraites,
      coherence,
      resultat: resultatPersisted,
      commentaire,
    });
    if (!finalisation?.success) {
      return reponseConflitFinalisation(req, finalisation);
    }
    statut = finalisation.statut || "EN_ATTENTE";

    return new Response(
      JSON.stringify({
        success: true,
        verdict: statut,
        heures_extraites: heuresExtraites,
        coherence,
        identite_correspond: nomCorrespond,
        etablissement_correspond: etablissementCorrespond,
        periode_correspond: periodeCorrespond,
        preuve_dupliquee: finalisation.preuve_dupliquee === true,
      }),
      { headers: { ...corsHeaders(req), "Content-Type": "application/json" } }
    );
  } catch (e: any) {
    console.error("verify-heures-externes error:", e);
    return new Response(
      JSON.stringify({ error: e?.message || "Une erreur interne est survenue." }),
      { status: 500, headers: { ...corsHeaders(req), "Content-Type": "application/json" } }
    );
  }
});
