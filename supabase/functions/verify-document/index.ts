import { createClient } from "npm:@supabase/supabase-js@2";
import { applyRateLimit, getClientIp } from "../_shared/rate-limit.ts";

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

async function loadDocumentWithRetry(supabase: any, documentId: string, attempts = 4) {
  for (let attempt = 0; attempt < attempts; attempt++) {
    const { data, error, status, statusText } = await supabase
      .from("documents_soignants")
      .select("id, soignant_id, type_document, nom_fichier, s3_cle, s3_bucket, type_mime")
      .eq("id", documentId)
      .maybeSingle();

    console.log(`[verify-document] attempt ${attempt + 1}: data=${!!data}, error=${error?.message || 'none'}, status=${status}, statusText=${statusText}`);

    if (data) return data;

    if (error && !error.message?.includes("not found") && status !== 406) {
      throw new Error(`Erreur base de données: ${error.message}`);
    }

    if (attempt < attempts - 1) await wait(350 * (attempt + 1));
  }
  throw new Error("Document introuvable");
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

    if (!isServiceRole) {
      const supabaseAuth = createClient(supabaseUrl, Deno.env.get("SUPABASE_ANON_KEY")!);
      const { data: { user }, error: authError } = await supabaseAuth.auth.getUser(token);
      if (authError || !user) {
        return new Response(JSON.stringify({ error: "Token invalide" }), {
          status: 401,
          headers: { ...corsHeaders(req), "Content-Type": "application/json" },
        });
      }
      if (applyRateLimit('verify-document', getClientIp(req), { max: 10, windowMs: 60_000 })) {
        return new Response(JSON.stringify({ error: 'Trop de vérifications. Réessayez dans 1 minute.' }), {
          status: 429,
          headers: { ...corsHeaders(req), 'Content-Type': 'application/json' },
        });
      }
    }

    const { document_id } = await req.json();
    if (!document_id) throw new Error("document_id requis");

    const anthropicKey = Deno.env.get("ANTHROPIC_API_KEY");
    if (!anthropicKey) throw new Error("ANTHROPIC_API_KEY non configurée — nécessaire pour la vérification IA des documents");

    const supabase = supabaseAdmin;

    const doc = await loadDocumentWithRetry(supabase, document_id);

    const { data: soignant } = await supabase
      .from("soignants")
      .select("prenom, nom")
      .eq("id", doc.soignant_id)
      .single();

    const { data: fileData, error: fileErr } = await supabase.storage
      .from(doc.s3_bucket)
      .download(doc.s3_cle);
    if (fileErr || !fileData) throw new Error("Impossible de télécharger le fichier");

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

    const ALLOWED_MIME_TYPES = ["image/jpeg", "image/png", "image/webp", "image/gif", "application/pdf"];
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
      ARRET_MALADIE: "Avis d'arrêt de travail (certificat médical d'arrêt maladie, formulaire Cerfa Assurance Maladie)",
      ATTESTATION_SCOLARITE: "Attestation de scolarité ou certificat de passage en année supérieure d'une école de santé (IFSI/soins infirmiers, IFAS/aide-soignant, faculté de pharmacie, etc.)",
      LICENCE_REMPLACEMENT: "Licence de remplacement délivrée par le Conseil de l'Ordre des médecins (autorise un interne en médecine à effectuer des remplacements de médecin)",
    };

    const typeLabel = typeLabels[doc.type_document] || doc.type_document;
    const nomComplet = soignant ? `${soignant.prenom} ${soignant.nom}` : "inconnu";

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
  "date_naissance_extraite": "YYYY-MM-DD" ou null,
  "sexe_extrait": "M" ou "F" ou null,
  "lieu_naissance_extrait": "commune de naissance lue" ou null,
  "score_confiance": 0-100,
  "document_lisible": true/false,
  "document_complet": true/false,
  "confiance": "HAUTE"/"MOYENNE"/"FAIBLE",
  "indices_falsification": ["liste des indices de falsification/retouche détectés"] ou [],
  "diplome_etranger": true/false/null,
  "pays_diplome": "string (pays de délivrance du diplôme)" ou null,
  "scolarite_formation": "IFSI" ou "IFAS" ou "MEDECINE_DFGSM" ou "MEDECINE_DFASM" ou "PHARMACIE" ou "AUTRE" ou null,
  "scolarite_annee_validee": entier (année LA PLUS HAUTE déjà VALIDÉE, comptée DANS LE CURSUS indiqué par scolarite_formation) ou null,
  "licence_remplacement_specialite": "string (spécialité/DES mentionné sur la licence de remplacement)" ou null,
  "motif_rejet": null ou "string expliquant le problème",
  "verdict": "VERIFIE"/"EN_ATTENTE"/"REJETE"
}

Règles:
- verdict = "VERIFIE" si type correspond, document lisible et complet, confiance HAUTE
- verdict = "EN_ATTENTE" si doute sur le type, nom, ou confiance MOYENNE
- verdict = "REJETE" si clairement pas le bon type, document illisible/tronqué, ou confiance FAIBLE
- DÉTECTION DE FALSIFICATION (important) : examine les signes de retouche/montage — polices
  incohérentes, alignements/espacements anormaux, bords de texte flous ou pixellisés autour
  des nom/prénom/dates/numéros, zones recouvertes, photo recollée, arrière-plan altéré,
  numéros au format invalide. Liste TOUT signe suspect dans "indices_falsification". S'il y a
  le moindre indice sérieux de falsification, verdict = "EN_ATTENTE" (revue humaine) et
  motif_rejet = "Indices de falsification détectés — vérification manuelle requise"
- Pour un RIB: pas de date d'expiration. Extrais le nom du TITULAIRE du compte dans "nom_extrait"/"prenom_extrait" et vérifie qu'il correspond au nom du soignant (nom_correspond=false si le titulaire est une autre personne)
- Pour une CNI/Passeport: extrais la date d'expiration si visible, ainsi que la date de naissance (date_naissance_extraite), le sexe (sexe_extrait: "M" ou "F"), et la commune de naissance (lieu_naissance_extrait) si lisibles sur le document. Ces informations servent à pré-remplir le profil DPAE du soignant
- Pour une assurance RCP: extrais la date de fin de validité
- IMPORTANT: Si le document déclaré est un "Diplôme d'État" mais que le fichier est clairement une carte d'identité, passeport ou tout autre document non-diplôme, verdict = "REJETE" avec motif "Le document fourni n'est pas un diplôme"
- DIPLÔME ÉTRANGER : pour un diplôme, indique "diplome_etranger" = true si le diplôme est délivré par un établissement HORS France (pays/langue/intitulé étranger) et renseigne "pays_diplome". Un diplôme étranger N'EST PAS rejeté automatiquement : il nécessite une autorisation d'exercice (procédure PAE) et une revue par l'administration → verdict = "EN_ATTENTE" avec motif "Diplôme étranger — vérification de l'autorisation d'exercice par l'administration".
- ATTESTATION DE SCOLARITÉ / CERTIFICAT DE PASSAGE : si le document déclaré est une attestation de scolarité ou un certificat de passage en année supérieure, vérifie que c'est bien un document d'une ÉCOLE / INSTITUT DE FORMATION en santé (verdict REJETE sinon avec motif "Le document n'est pas une attestation de scolarité d'une école de santé"). Renseigne "scolarite_formation" : "IFSI" pour les soins infirmiers (étudiant infirmier / ESI), "IFAS" pour aide-soignant, "MEDECINE_DFGSM" pour la médecine 1er cycle (DFGSM, années 1-3), "MEDECINE_DFASM" pour la médecine 2e cycle (DFASM / externat), "PHARMACIE" pour les études de pharmacie, sinon "AUTRE". Renseigne "scolarite_annee_validee" = le numéro de l'année LA PLUS HAUTE DÉJÀ VALIDÉE, COMPTÉE DANS CE CURSUS (ex IFSI : "admis en 2e année" → 1re année validée → 1 ; "année 2 validée" → 2. MEDECINE_DFGSM : "DFGSM2 validé" → 2. MEDECINE_DFASM : "DFASM2 validé / admis en DFASM3" → 2. PHARMACIE : "5e année validée" → 5). Si l'année validée n'est pas clairement établie, mets null et verdict = "EN_ATTENTE".
- LICENCE DE REMPLACEMENT : si le document déclaré est une licence de remplacement, vérifie que c'est bien un document délivré par un CONSEIL DE L'ORDRE DES MÉDECINS (conseil départemental/national), au nom du soignant (verdict REJETE sinon avec motif "Le document n'est pas une licence de remplacement de l'Ordre des médecins"). Extrais la date de fin de validité dans "date_expiration" (une licence est valable 1 an) et la spécialité/DES dans "licence_remplacement_specialite". Si la licence est expirée (date_expiration passée) → verdict = "EN_ATTENTE" avec motif "Licence de remplacement expirée — renouvellement requis".`;

    const userMessage = `Document déclaré comme: "${typeLabel}"
Nom du soignant: "${nomComplet}"
Fichier: ${doc.nom_fichier}

Analyse ce document et vérifie sa conformité.`;

    const anthropicContent: any[] = [{ type: "text", text: userMessage }];
    if (isPdf) {
      anthropicContent.push({
        type: "document",
        source: { type: "base64", media_type: "application/pdf", data: base64 },
      });
    } else if (isImage) {
      anthropicContent.push({
        type: "image",
        source: { type: "base64", media_type: doc.type_mime || "image/jpeg", data: base64 },
      });
    }

    // Timeout 20s sur l'appel Anthropic : évite de laisser l'UI bloquée en
    // "vérification en cours" indéfiniment si l'API met trop longtemps.
    const aiController = new AbortController();
    const aiTimeout = setTimeout(() => aiController.abort(), 20_000);
    let aiResponse: Response;
    try {
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
          system: systemPrompt,
          messages: [{ role: "user", content: anthropicContent }],
        }),
        signal: aiController.signal,
      });
    } catch (e) {
      clearTimeout(aiTimeout);
      const estTimeout = (e as any)?.name === "AbortError";
      console.error("Anthropic call failed:", estTimeout ? "timeout 20s" : e);
      await supabase.from("documents_soignants").update({
        resultat_ia: { erreur_anthropic: { status: estTimeout ? "timeout" : "network", at: new Date().toISOString() } },
      } as any).eq("id", document_id);
      await supabase.rpc("fn_update_document_verification", {
        p_document_id: document_id, p_statut_verification: "EN_ATTENTE", p_motif_rejet: null,
      });
      return new Response(JSON.stringify({ success: true, verdict: "EN_ATTENTE", reason: estTimeout ? "AI timeout" : "AI network error" }), {
        headers: { ...corsHeaders(req), "Content-Type": "application/json" },
      });
    }
    clearTimeout(aiTimeout);

    if (!aiResponse.ok) {
      const errText = await aiResponse.text();
      console.error("Anthropic API failed:", aiResponse.status, errText);
      // Persiste l'erreur Anthropic dans resultat_ia pour diagnostic
      // sans avoir à déployer une version debug.
      await supabase.from("documents_soignants").update({
        resultat_ia: {
          erreur_anthropic: {
            status: aiResponse.status,
            body_excerpt: errText.slice(0, 1500),
            at: new Date().toISOString(),
          },
        },
      } as any).eq("id", document_id);
      await supabase.rpc("fn_update_document_verification", {
        p_document_id: document_id, p_statut_verification: "EN_ATTENTE", p_motif_rejet: null,
      });
      return new Response(JSON.stringify({ success: true, verdict: "EN_ATTENTE", reason: "AI unavailable" }), {
        headers: { ...corsHeaders(req), "Content-Type": "application/json" },
      });
    }

    const aiData = await aiResponse.json();
    const rawContent = aiData.content?.[0]?.text || "";

    let analysis: any;
    try {
      const jsonMatch = rawContent.match(/\{[\s\S]*\}/);
      analysis = jsonMatch ? JSON.parse(jsonMatch[0]) : null;
    } catch {
      analysis = null;
    }

    if (!analysis) {
      await supabase.from("documents_soignants").update({
        resultat_ia: {
          erreur_parse: { raw_excerpt: rawContent.slice(0, 1500), at: new Date().toISOString() },
        },
      } as any).eq("id", document_id);
      await supabase.rpc("fn_update_document_verification", {
        p_document_id: document_id, p_statut_verification: "EN_ATTENTE",
      });

      return new Response(JSON.stringify({ success: true, verdict: "EN_ATTENTE", reason: "Parse error" }), {
        headers: { ...corsHeaders(req), "Content-Type": "application/json" },
      });
    }

    // Extraction nom + cohérence — calculée AVANT le verdict pour pouvoir BLOQUER.
    const nomExtraitIa = analysis.nom_extrait || null;
    const prenomExtraitIa = analysis.prenom_extrait || null;
    const scoreConfianceIa = typeof analysis.score_confiance === "number" ? analysis.score_confiance : null;

    const normalize = (s: string) => (s || "").toLowerCase().normalize("NFD").replace(/[̀-ͯ]/g, "").trim();
    const nomDocNorm = normalize(nomExtraitIa || "");
    const nomProfilNorm = normalize(soignant?.nom || "");
    const prenomDocNorm = normalize(prenomExtraitIa || "");
    const prenomProfilNorm = normalize(soignant?.prenom || "");

    const nomMatch = nomDocNorm && nomProfilNorm
      ? nomDocNorm.includes(nomProfilNorm) || nomProfilNorm.includes(nomDocNorm)
      : null;
    const prenomMatch = prenomDocNorm && prenomProfilNorm
      ? prenomDocNorm.slice(0, 3) === prenomProfilNorm.slice(0, 3)
      : null;
    const coherenceNom = nomMatch !== null ? (nomMatch && (prenomMatch === null || prenomMatch)) : null;

    // GATE DUR de concordance : si l'IA verdict=VERIFIE mais que le nom extrait NE
    // correspond PAS au profil (coherence_nom === false), on rétrograde en EN_ATTENTE.
    // Un doc EN_ATTENTE ne compte pas comme valide → blocage mission, et passe en
    // revue manuelle admin. On ne fait jamais confiance aveuglément à l'IA sur le nom.
    // Vaut pour TOUS les types (CNI/diplôme/RIB) → couvre les re-uploads après
    // expiration et les changements de RIB (le nom du titulaire doit concorder).
    let verdictFinal = analysis.verdict || "EN_ATTENTE";
    let motifRejet = analysis.motif_rejet || null;
    const indicesFalsif = Array.isArray(analysis.indices_falsification) ? analysis.indices_falsification : [];
    if (verdictFinal === "VERIFIE" && coherenceNom === false) {
      verdictFinal = "EN_ATTENTE";
      motifRejet = "Le nom du document ne correspond pas à celui du profil — vérification manuelle requise.";
    }
    // GATE FALSIFICATION : tout indice de retouche/montage → revue humaine (jamais VERIFIE auto).
    if (verdictFinal === "VERIFIE" && indicesFalsif.length > 0) {
      verdictFinal = "EN_ATTENTE";
      motifRejet = "Indices de falsification détectés — vérification manuelle requise.";
    }
    // GATE DIPLÔME ÉTRANGER : un diplôme délivré hors France nécessite l'autorisation
    // d'exercice (PAE) → jamais VERIFIE auto, transmis à l'administration.
    if (doc.type_document === "DIPLOME" && analysis.diplome_etranger === true) {
      verdictFinal = "EN_ATTENTE";
      motifRejet = `Diplôme étranger${analysis.pays_diplome ? ` (${analysis.pays_diplome})` : ""} — transmis à l'administration pour vérification de l'autorisation d'exercice (procédure PAE). Téléversez votre autorisation d'exercice si vous en disposez.`;
    }

    // Si REJETE : ne PAS écrire valide_depuis/valide_jusqua (dates du mauvais document).
    const estRejeteFinal = verdictFinal === "REJETE";
    await supabase.rpc("fn_update_document_verification", {
      p_document_id: document_id,
      p_statut_verification: verdictFinal,
      p_motif_rejet: motifRejet,
      p_valide_depuis: estRejeteFinal ? null : (analysis.date_emission || null),
      p_valide_jusqua: estRejeteFinal ? null : (analysis.date_expiration || null),
      p_verifie_le: verdictFinal === "VERIFIE" ? new Date().toISOString() : null,
    });

    await supabase.from("documents_soignants").update({
      resultat_ia: analysis,
      nom_extrait_ia: nomExtraitIa,
      prenom_extrait_ia: prenomExtraitIa,
      score_confiance_ia: scoreConfianceIa,
      coherence_nom: coherenceNom,
    } as any).eq("id", document_id);

    // Auto-remplissage DPAE : si CNI/passeport/titre de séjour VERIFIE, propager
    // date_naissance + sexe + lieu_naissance vers le profil soignant (uniquement
    // si les champs sont vides — pas d'écrasement des données existantes).
    const estIdentite = ["CARTE_IDENTITE", "PASSEPORT", "TITRE_SEJOUR"].includes(doc.type_document);
    if (estIdentite && verdictFinal === "VERIFIE" && doc.soignant_id) {
      const updates: Record<string, unknown> = {};
      if (analysis.date_naissance_extraite) updates.date_naissance = analysis.date_naissance_extraite;
      if (analysis.sexe_extrait && ["M", "F"].includes(analysis.sexe_extrait)) updates.sexe = analysis.sexe_extrait;
      if (analysis.lieu_naissance_extrait) updates.lieu_naissance_commune = analysis.lieu_naissance_extrait;
      if (Object.keys(updates).length > 0) {
        // Ne PAS écraser si déjà renseigné — merge conditionnel.
        const { data: currentSoignant } = await supabase.from("soignants")
          .select("date_naissance, sexe, lieu_naissance_commune")
          .eq("id", doc.soignant_id).maybeSingle();
        const cs = currentSoignant as Record<string, unknown> | null;
        const finalUpdates: Record<string, unknown> = {};
        if (updates.date_naissance && !cs?.date_naissance) finalUpdates.date_naissance = updates.date_naissance;
        if (updates.sexe && !cs?.sexe) finalUpdates.sexe = updates.sexe;
        if (updates.lieu_naissance_commune && !cs?.lieu_naissance_commune) finalUpdates.lieu_naissance_commune = updates.lieu_naissance_commune;
        if (Object.keys(finalUpdates).length > 0) {
          await supabase.from("soignants").update({ ...finalUpdates, modifie_le: new Date().toISOString() } as any).eq("id", doc.soignant_id);
        }
      }
    }

    // Attestation de scolarité VERIFIE → on stocke le niveau vérifié + on calcule
    // la profession autorisée (faisant fonction) via la table d'équivalence admin.
    // Marque aussi est_etudiant. L'application de l'équivalence (blocage de la
    // profession trop haute + suggestion) se fait côté inscription/profil.
    if (doc.type_document === "ATTESTATION_SCOLARITE" && verdictFinal === "VERIFIE" && doc.soignant_id) {
      const formation = typeof analysis.scolarite_formation === "string" ? analysis.scolarite_formation : null;
      const anneeValidee = typeof analysis.scolarite_annee_validee === "number" ? analysis.scolarite_annee_validee : null;
      let professionAutorisee: string | null = null;
      if (formation && anneeValidee != null) {
        try {
          const { data: profs } = await supabase.rpc("fn_professions_autorisees_scolarite" as any, {
            p_formation: formation, p_annee_validee: anneeValidee,
          });
          const liste: string[] = Array.isArray(profs)
            ? (profs as any[]).map((r) => typeof r === "string" ? r : (r?.fn_professions_autorisees_scolarite ?? Object.values(r ?? {})[0])).filter(Boolean)
            : [];
          // On retient la profession LA PLUS QUALIFIANTE de l'ensemble autorisé
          // (ex : DFASM2 → {AS, IDE} → IDE).
          const priorite = ["MEDECIN", "SAGE_FEMME", "PHARMACIEN", "IADE", "IBODE", "IDE", "DENTISTE", "KINE", "AS", "AES", "AUXILIAIRE_PUERICULTURE"];
          professionAutorisee = priorite.find((p) => liste.includes(p)) ?? liste[0] ?? null;
        } catch (e) { console.error("fn_professions_autorisees_scolarite échoué:", safeStringifyError(e)); }
      }
      await supabase.from("soignants").update({
        scolarite_formation: formation,
        scolarite_annee_validee: anneeValidee,
        scolarite_profession_autorisee: professionAutorisee,
        scolarite_verifiee: true,
        scolarite_verifiee_le: new Date().toISOString(),
        est_etudiant: true,
        modifie_le: new Date().toISOString(),
      } as any).eq("id", doc.soignant_id);
    }

    // Licence de remplacement VERIFIE → autorise l'exercice « faisant fonction
    // médecin » (remplacement). On stocke la validité + la spécialité, et on
    // marque est_etudiant (interne).
    if (doc.type_document === "LICENCE_REMPLACEMENT" && verdictFinal === "VERIFIE" && doc.soignant_id) {
      await supabase.from("soignants").update({
        licence_remplacement_verifiee: true,
        licence_remplacement_le: new Date().toISOString(),
        licence_remplacement_valide_jusqua: analysis.date_expiration || null,
        licence_remplacement_specialite: typeof analysis.licence_remplacement_specialite === "string" ? analysis.licence_remplacement_specialite : null,
        est_etudiant: true,
        modifie_le: new Date().toISOString(),
      } as any).eq("id", doc.soignant_id);
    }

    await supabase.rpc("fn_ecrire_audit_safe" as any, {
      p_acteur_id: doc.soignant_id,
      p_type_acteur: "SYSTEME",
      p_action: "DOCUMENT_VERIFICATION_AUTO",
      p_type_ressource: "document",
      p_id_ressource: document_id,
      p_cle_s3: doc.s3_cle,
      p_details: {
        verdict: verdictFinal,
        verdict_ia_brut: analysis.verdict,
        type_detecte: analysis.type_detecte,
        confiance: analysis.confiance,
        nom_correspond: analysis.nom_correspond,
        coherence_nom: coherenceNom,
        type_correspond: analysis.type_correspond,
      },
      p_ip: null,
      p_navigateur: "edge-function/verify-document",
    });

    return new Response(
      JSON.stringify({ success: true, verdict: verdictFinal, analysis }),
      { headers: { ...corsHeaders(req), "Content-Type": "application/json" } }
    );
  } catch (e: any) {
    console.error("verify-document error:", e);
    return new Response(
      JSON.stringify({ error: e?.message || "Une erreur interne est survenue." }),
      { status: 500, headers: { ...corsHeaders(req), "Content-Type": "application/json" } }
    );
  }
});
