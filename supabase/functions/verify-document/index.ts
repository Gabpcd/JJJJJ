import { createClient } from "npm:@supabase/supabase-js@2";
import { applyRateLimit, getClientIp } from "../_shared/rate-limit.ts";
import { appelerAnthropic } from "../_shared/anthropic.ts";
import { safeStringifyError } from "../_shared/errors.ts";
import { corsHeaders } from "../_shared/cors.ts";
import { verifyAdminOrServiceRole, verifyUserOrServiceRole } from "../_shared/admin-auth.ts";
import {
  corporateNameMatches,
  diplomaMatchesDeclaredProfession,
  isValidIban,
  normalizeIban,
  personNameMatches,
  professionalIdentifierMatches,
  sanitizeBankAnalysis,
} from "../_shared/verification-rules.ts";

function wait(ms: number) {
  return new Promise((resolve) => setTimeout(resolve, ms));
}

async function sha256Hex(value: string): Promise<string> {
  const digest = await crypto.subtle.digest(
    'SHA-256',
    new TextEncoder().encode(value),
  );
  return Array.from(new Uint8Array(digest))
    .map((byte) => byte.toString(16).padStart(2, '0'))
    .join('');
}

const IDENTITY_DOCUMENT_TYPES = new Set([
  "CARTE_IDENTITE",
  "PASSEPORT",
  "TITRE_SEJOUR",
]);

const ALLOWED_VERDICTS = new Set(["VERIFIE", "EN_ATTENTE", "REJETE"]);
const verificationAttempts = new WeakMap<object, string>();

// Bornes du numéro d'année DANS le cursus demandé au modèle. Elles empêchent
// une année hallucinéе (p. ex. 99) de satisfaire toutes les équivalences SQL
// fondées sur un simple seuil minimum.
const SCOLARITE_MAX_ANNEE_VALIDEE: Record<string, number> = {
  IFSI: 3,
  IFAS: 1,
  MEDECINE_DFGSM: 3,
  MEDECINE_DFASM: 3,
  PHARMACIE: 9,
  MAIEUTIQUE: 6,
  ODONTOLOGIE: 9,
  KINE: 5,
  ERGOTHERAPIE: 3,
  PSYCHOMOTRICITE: 3,
  MANIP_RADIO: 3,
};

function hasExpectedFileSignature(bytes: Uint8Array, mime: string | null): boolean {
  if (!mime) return false;
  if (mime === "application/pdf") {
    return bytes.length >= 5 && String.fromCharCode(...bytes.subarray(0, 5)) === "%PDF-";
  }
  if (mime === "image/jpeg") {
    return bytes.length >= 3 && bytes[0] === 0xff && bytes[1] === 0xd8 && bytes[2] === 0xff;
  }
  if (mime === "image/png") {
    const png = [0x89, 0x50, 0x4e, 0x47, 0x0d, 0x0a, 0x1a, 0x0a];
    return bytes.length >= png.length && png.every((value, index) => bytes[index] === value);
  }
  if (mime === "image/webp") {
    return bytes.length >= 12
      && String.fromCharCode(...bytes.subarray(0, 4)) === "RIFF"
      && String.fromCharCode(...bytes.subarray(8, 12)) === "WEBP";
  }
  return false;
}

async function saveDocumentFields(
  supabase: any,
  documentId: string,
  fields: Record<string, unknown>,
): Promise<void> {
  const attemptId = verificationAttempts.get(supabase as object);
  if (!attemptId) throw new Error("Tentative de vérification absente");
  const { data, error } = await supabase
    .from("documents_soignants")
    .update(fields)
    .eq("id", documentId)
    .eq("verification_attempt_id", attemptId)
    .select("id")
    .maybeSingle();
  if (error || !data) {
    throw new Error(`Écriture document impossible: ${error?.code || error?.message || "ligne absente"}`);
  }
}

async function saveDocumentVerdict(
  supabase: any,
  params: Record<string, unknown>,
): Promise<void> {
  const attemptId = verificationAttempts.get(supabase as object);
  if (!attemptId) throw new Error("Tentative de vérification absente");
  const statut = params.p_statut_verification;
  const { data, error } = await supabase
    .from("documents_soignants")
    .update({
      statut_verification: statut,
      motif_rejet: params.p_motif_rejet ?? null,
      valide_depuis: statut === "REJETE" ? null : (params.p_valide_depuis ?? null),
      valide_jusqua: statut === "REJETE" ? null : (params.p_valide_jusqua ?? null),
      verifie_le: statut === "VERIFIE" ? (params.p_verifie_le ?? new Date().toISOString()) : null,
      verification_attempt_id: null,
      modifie_le: new Date().toISOString(),
    })
    .eq("id", params.p_document_id)
    .eq("verification_attempt_id", attemptId)
    .select("id")
    .maybeSingle();
  if (error || !data) {
    throw new Error(`Écriture verdict impossible: ${error?.code || error?.message || "tentative remplacée"}`);
  }
}

async function markDocumentForManualReview(
  supabase: any,
  documentId: string,
  attemptId: string | null,
  motif: string,
  code: string,
): Promise<boolean> {
  const { data, error } = await supabase.rpc(
    "fn_document_marquer_revue_manuelle" as any,
    {
      p_document_id: documentId,
      p_attempt_id: attemptId,
      p_service: "VERIFY_DOCUMENT",
      p_motif: motif.slice(0, 1000),
      // Ne jamais pousser le chemin Storage, le contenu IA ou un IBAN dans la
      // file : seul un code technique borné est utile à l'exploitation.
      p_details: { code: code.slice(0, 100) },
    },
  );
  if (error || data?.success !== true) {
    console.error(
      "Mise en file de revue impossible:",
      error?.code || error?.message || data?.error_code || "UNKNOWN",
    );
    return false;
  }
  return true;
}

async function beginDocumentVerification(
  supabase: any,
  doc: any,
  attemptId: string,
): Promise<void> {
  const { data, error } = await supabase
    .from("documents_soignants")
    .update({
      verification_attempt_id: attemptId,
      statut_verification: "EN_ATTENTE",
      motif_rejet: "Vérification automatique en cours.",
      valide_depuis: null,
      valide_jusqua: null,
      verifie_le: null,
      resultat_ia: null,
      nom_extrait_ia: null,
      prenom_extrait_ia: null,
      score_confiance_ia: null,
      coherence_nom: null,
      modifie_le: new Date().toISOString(),
    })
    .eq("id", doc.id)
    .eq("soignant_id", doc.soignant_id)
    .eq("s3_bucket", doc.s3_bucket)
    .eq("s3_cle", doc.s3_cle)
    .eq("type_document", doc.type_document)
    .is("supprime_le", null)
    .select("id")
    .maybeSingle();
  if (error || !data) {
    throw new Error(`Démarrage vérification impossible: ${error?.code || error?.message || "source modifiée"}`);
  }
  verificationAttempts.set(supabase as object, attemptId);
}

/** Accepte uniquement une vraie date civile ISO, sans normalisation permissive. */
function normalizeIsoDate(value: unknown): string | null {
  if (typeof value !== "string") return null;
  const trimmed = value.trim();
  const match = /^(\d{4})-(\d{2})-(\d{2})$/.exec(trimmed);
  if (!match) return null;
  const year = Number(match[1]);
  const month = Number(match[2]);
  const day = Number(match[3]);
  const parsed = new Date(Date.UTC(year, month - 1, day));
  if (
    parsed.getUTCFullYear() !== year
    || parsed.getUTCMonth() !== month - 1
    || parsed.getUTCDate() !== day
  ) return null;
  return trimmed;
}

function addCalendarMonthsIso(isoDate: string, months: number): string {
  const [year, month, day] = isoDate.split("-").map(Number);
  const firstOfTarget = new Date(Date.UTC(year, month - 1 + months, 1));
  const targetYear = firstOfTarget.getUTCFullYear();
  const targetMonth = firstOfTarget.getUTCMonth();
  const lastDay = new Date(Date.UTC(targetYear, targetMonth + 1, 0)).getUTCDate();
  const targetDay = Math.min(day, lastDay);
  return `${targetYear.toString().padStart(4, "0")}-${(targetMonth + 1).toString().padStart(2, "0")}-${targetDay.toString().padStart(2, "0")}`;
}

async function loadDocumentWithRetry(supabase: any, documentId: string, attempts = 4) {
  for (let attempt = 0; attempt < attempts; attempt++) {
    const { data, error, status, statusText } = await supabase
      .from("documents_soignants")
      .select("id, soignant_id, type_document, nom_fichier, s3_cle, s3_bucket, type_mime")
      .eq("id", documentId)
      .is("supprime_le", null)
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
  let reviewContext: {
    supabase: any;
    documentId: string;
    attemptId: string;
  } | null = null;
  if (req.method === "OPTIONS") return new Response(null, { headers: corsHeaders(req) });

  try {
    const auth = await verifyUserOrServiceRole(req);
    if (!auth.ok) return new Response(JSON.stringify({ error: auth.error }), {
      status: auth.status,
      headers: { ...corsHeaders(req), "Content-Type": "application/json" },
    });

    const body = await req.json().catch(() => ({}));
    if (body?.warm === true) {
      if (!auth.isServiceRole) {
        const adminAuth = await verifyAdminOrServiceRole(req);
        if (!adminAuth.ok) return new Response(JSON.stringify({ error: adminAuth.error }), {
          status: adminAuth.status,
          headers: { ...corsHeaders(req), "Content-Type": "application/json" },
        });
      }
      const anthropicKey = Deno.env.get("ANTHROPIC_API_KEY") || "";
      if (body?.probe === true) {
        const probeRateKey = `${auth.userId || "service"}:${getClientIp(req)}`;
        if (applyRateLimit("verify-document-probe", probeRateKey, { max: 6, windowMs: 60_000 })) {
          return new Response(JSON.stringify({
            configured: !!anthropicKey,
            reachable: false,
            model: null,
            status: 429,
          }), {
            status: 429,
            headers: { ...corsHeaders(req), "Content-Type": "application/json" },
          });
        }
        if (!anthropicKey) {
          return new Response(JSON.stringify({
            configured: false,
            reachable: false,
            model: null,
            status: 0,
          }), { headers: { ...corsHeaders(req), "Content-Type": "application/json" } });
        }

        const probeController = new AbortController();
        const probeTimeout = setTimeout(() => probeController.abort(), 10_000);
        try {
          const probe = await appelerAnthropic({
            apiKey: anthropicKey,
            system: "Test technique de disponibilité. Réponds uniquement OK.",
            content: "OK",
            maxTokens: 1,
            signal: probeController.signal,
          });
          return new Response(JSON.stringify({
            configured: true,
            reachable: probe.ok,
            model: probe.model || null,
            status: probe.status,
          }), { headers: { ...corsHeaders(req), "Content-Type": "application/json" } });
        } catch {
          return new Response(JSON.stringify({
            configured: true,
            reachable: false,
            model: null,
            status: 0,
          }), { headers: { ...corsHeaders(req), "Content-Type": "application/json" } });
        } finally {
          clearTimeout(probeTimeout);
        }
      }
      return new Response(JSON.stringify({
        warm: true,
        configured: !!anthropicKey,
      }), { headers: { ...corsHeaders(req), "Content-Type": "application/json" } });
    }

    const supabaseUrl = Deno.env.get("SUPABASE_URL")!;
    const serviceKey = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")!;
    const supabaseAdmin = createClient(supabaseUrl, serviceKey, { auth: { persistSession: false } });
    if (!auth.isServiceRole) {
      if (applyRateLimit('verify-document', getClientIp(req), { max: 10, windowMs: 60_000 })) {
        return new Response(JSON.stringify({ error: 'Trop de vérifications. Réessayez dans 1 minute.' }), {
          status: 429,
          headers: { ...corsHeaders(req), 'Content-Type': 'application/json' },
        });
      }
    }

    if (body?.action === "cleanup_orphan") {
      const sourcePath = typeof body?.s3_cle === "string" ? body.s3_cle : "";
      const segments = sourcePath.split("/");
      const ownerId = segments[0] || "";
      const uuidRe = /^[0-9a-f]{8}-[0-9a-f]{4}-[1-5][0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$/i;
      const cheminAutorise = sourcePath.length <= 512
        && segments.length === 4
        && uuidRe.test(ownerId)
        && segments[1] === "documents"
        && /^[A-Z0-9_]+$/.test(segments[2] || "")
        && /^[A-Za-z0-9._-]+$/.test(segments[3] || "")
        && !sourcePath.includes("..")
        && !sourcePath.includes("\\");
      if (!cheminAutorise) return new Response(JSON.stringify({ error: "Chemin de document non autorisé" }), {
        status: 403,
        headers: { ...corsHeaders(req), "Content-Type": "application/json" },
      });

      let peutNettoyer = auth.isServiceRole || auth.userId === ownerId;
      if (!peutNettoyer && !auth.isServiceRole) {
        const adminAuth = await verifyAdminOrServiceRole(req);
        peutNettoyer = adminAuth.ok;
      }
      if (!peutNettoyer) return new Response(JSON.stringify({ error: "Accès refusé" }), {
        status: 403,
        headers: { ...corsHeaders(req), "Content-Type": "application/json" },
      });

      // Un objet déjà rattaché n'est jamais supprimé par cette action,
      // même s'il est ensuite marqué supprimé logiquement. Le cycle de vie
      // de ces preuves actives/historiques reste géré par la modération.
      const { data: reference, error: referenceError } = await supabaseAdmin
        .from("documents_soignants")
        .select("id")
        .eq("s3_bucket", "jolene-documents")
        .eq("s3_cle", sourcePath)
        .limit(1)
        .maybeSingle();
      if (referenceError) throw new Error(`Contrôle de référence impossible: ${referenceError.code || referenceError.message}`);
      if (reference) return new Response(JSON.stringify({ error: "Ce document est encore référencé" }), {
        status: 409,
        headers: { ...corsHeaders(req), "Content-Type": "application/json" },
      });

      const { error: removeError } = await supabaseAdmin.storage
        .from("jolene-documents")
        .remove([sourcePath]);
      if (removeError) throw new Error("Nettoyage du document incomplet");
      return new Response(JSON.stringify({ success: true }), {
        headers: { ...corsHeaders(req), "Content-Type": "application/json" },
      });
    }

    const { document_id } = body;
    if (!document_id) throw new Error("document_id requis");

    const supabase = supabaseAdmin;

    const doc = await loadDocumentWithRetry(supabase, document_id);

    // Un soignant ne peut analyser que ses propres documents. Les appels
    // serveur et les administrateurs AAL2 actifs restent autorisés.
    if (!auth.isServiceRole && auth.userId !== doc.soignant_id) {
      const adminAuth = await verifyAdminOrServiceRole(req);
      if (!adminAuth.ok) return new Response(JSON.stringify({ error: "Accès refusé" }), {
        status: 403,
        headers: { ...corsHeaders(req), "Content-Type": "application/json" },
      });
    }

    const expectedStoragePrefix = `${doc.soignant_id}/documents/`;
    if (
      doc.s3_bucket !== 'jolene-documents' ||
      typeof doc.s3_cle !== 'string' ||
      !doc.s3_cle.startsWith(expectedStoragePrefix) ||
      doc.s3_cle.includes('..')
    ) {
      return new Response(JSON.stringify({ error: "Chemin de document non autorisé" }), {
        status: 403,
        headers: { ...corsHeaders(req), "Content-Type": "application/json" },
      });
    }

    const { data: soignant, error: soignantError } = await supabase
      .from("soignants")
      .select("prenom, nom, date_naissance, sexe, lieu_naissance_commune, profession, numero_rpps, numero_adeli, rpps_verifie, adeli_verifie")
      .eq("id", doc.soignant_id)
      .is("supprime_le", null)
      .single();
    if (soignantError || !soignant) {
      throw new Error(`Profil soignant introuvable: ${soignantError?.code || soignantError?.message || "ligne absente"}`);
    }

    const { data: documentRule, error: documentRuleError } = await supabase
      .from("documents_requis_par_profession")
      .select("a_expiration, description")
      .eq("profession", soignant.profession)
      .eq("type_document", doc.type_document)
      .maybeSingle();
    if (documentRuleError) {
      throw new Error(`Règle documentaire indisponible: ${documentRuleError.code || documentRuleError.message}`);
    }

    // Chaque réanalyse remplace atomiquement le jeton de la précédente. Toute
    // réponse IA plus ancienne devient alors incapable d'écrire un verdict.
    const verificationAttemptId = crypto.randomUUID();
    await beginDocumentVerification(supabase, doc, verificationAttemptId);
    reviewContext = {
      supabase,
      documentId: document_id,
      attemptId: verificationAttemptId,
    };

    const anthropicKey = Deno.env.get("ANTHROPIC_API_KEY");
    if (!anthropicKey) {
      await markDocumentForManualReview(
        supabase,
        document_id,
        verificationAttemptId,
        "Service de vérification automatique non configuré — demande en attente d'attribution à l'équipe.",
        "AI_NOT_CONFIGURED",
      );
      reviewContext = null;
      return new Response(JSON.stringify({ error: "Service de vérification automatique non configuré" }), {
        status: 503,
        headers: { ...corsHeaders(req), "Content-Type": "application/json" },
      });
    }

    const { data: fileData, error: fileErr } = await supabase.storage
      .from(doc.s3_bucket)
      .download(doc.s3_cle);
    if (fileErr || !fileData) throw new Error("Impossible de télécharger le fichier");

    const arrayBuffer = await fileData.arrayBuffer();
    const bytes = new Uint8Array(arrayBuffer);
    if (bytes.length === 0 || bytes.length > 10 * 1024 * 1024) {
      throw new Error("Fichier vide ou trop volumineux");
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

    const ALLOWED_MIME_TYPES = ["image/jpeg", "image/png", "image/webp", "application/pdf"];
    if (!doc.type_mime || !ALLOWED_MIME_TYPES.includes(doc.type_mime)) {
      await saveDocumentVerdict(supabase, {
        p_document_id: document_id,
        p_statut_verification: "REJETE",
        p_motif_rejet: `Type de fichier non autorisé: ${doc.type_mime}`,
      });
      reviewContext = null;
      return new Response(JSON.stringify({ success: true, verdict: "REJETE", reason: "Unsupported MIME type" }), {
        headers: { ...corsHeaders(req), "Content-Type": "application/json" },
      });
    }
    if (!hasExpectedFileSignature(bytes, doc.type_mime)) {
      await saveDocumentVerdict(supabase, {
        p_document_id: document_id,
        p_statut_verification: "REJETE",
        p_motif_rejet: "Le contenu du fichier ne correspond pas à son format déclaré.",
        p_valide_depuis: null,
        p_valide_jusqua: null,
        p_verifie_le: null,
      });
      reviewContext = null;
      return new Response(JSON.stringify({ success: true, verdict: "REJETE", reason: "Invalid file signature" }), {
        headers: { ...corsHeaders(req), "Content-Type": "application/json" },
      });
    }

    const isImage = doc.type_mime?.startsWith("image/");
    const isPdf = doc.type_mime === "application/pdf";

    const typeLabels: Record<string, string> = {
      CARTE_IDENTITE: "Pièce d'identité (carte nationale d'identité, passeport OU titre de séjour)",
      PASSEPORT: "Passeport",
      TITRE_SEJOUR: "Titre de séjour",
      DIPLOME: "Diplôme d'État",
      RPPS_ADELI: "Attestation RPPS ou ADELI",
      RCP_ASSURANCE: "Assurance Responsabilité Civile Professionnelle",
      VACCINATIONS: "Justificatif de vaccinations professionnelles",
      CASIER_JUDICIAIRE: "Extrait de casier judiciaire (bulletin n° 3)",
      RIB: "Relevé d'Identité Bancaire",
      KBIS: "Extrait KBIS",
      ATTESTATION_URSSAF: "Attestation URSSAF",
      AUTORISATION_EXERCICE: "Autorisation d'exercice",
      MEDECINE_TRAVAIL: "Attestation d'aptitude de la médecine du travail",
      FORMATION_OBLIGATOIRE: "Certificat de formation obligatoire",
      AUTRE: "Autre justificatif professionnel",
      CARTE_ORDRE: "Carte professionnelle délivrée par un ordre de santé",
      ATTESTATION_CPAM: "Attestation d'inscription ou de conventionnement CPAM",
      NOTE_HONORAIRES: "Note d'honoraires",
      ATTESTATION_3200H: "Attestation justifiant des heures d'exercice professionnel",
      ARRET_MALADIE: "Avis d'arrêt de travail (certificat médical d'arrêt maladie, formulaire Cerfa Assurance Maladie)",
      ATTESTATION_SCOLARITE: "Attestation de scolarité ou certificat de passage en année supérieure d'une école de santé (IFSI/soins infirmiers, IFAS/aide-soignant, faculté de pharmacie, etc.)",
      LICENCE_REMPLACEMENT: "Licence de remplacement délivrée par le Conseil de l'Ordre des médecins (autorise un interne en médecine à effectuer des remplacements de médecin)",
      BULLETIN_PAIE: "Bulletin de paie prouvant des heures de travail externes",
      ATTESTATION_EMPLOYEUR: "Attestation employeur prouvant des heures de travail externes",
      CERTIFICAT_TRAVAIL: "Certificat de travail prouvant une période d'emploi externe",
    };

    const typeLabel = typeLabels[doc.type_document] || doc.type_document;
    const exigenceDocumentaire = typeof documentRule?.description === "string"
      ? documentRule.description.trim().slice(0, 1000)
      : "";
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
  "numero_professionnel_extrait": "numéro RPPS ou ADELI complet lu sur le document" ou null,
  "type_identifiant_professionnel": "RPPS" ou "ADELI" ou null,
  "iban_extrait": "IBAN complet lu sur le document, sans espaces" ou null,
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
  "profession_certifiee": "string : profession de santé certifiée par ce diplôme ou cette autorisation d'exercice (IDE, AS, AES, SAGE_FEMME, MEDECIN, PHARMACIEN, KINE, IBODE, IADE, PREPARATEUR_PHARMA, DENTISTE, AUXILIAIRE_PUERICULTURE, MANIPULATEUR_RADIO, ERGOTHERAPEUTE, PSYCHOMOTRICIEN, ORTHOPHONISTE, DIETETICIEN)" ou null,
  "scolarite_formation": "IFSI" ou "IFAS" ou "MEDECINE_DFGSM" ou "MEDECINE_DFASM" ou "PHARMACIE" ou "MAIEUTIQUE" ou "ODONTOLOGIE" ou "KINE" ou "ERGOTHERAPIE" ou "PSYCHOMOTRICITE" ou "MANIP_RADIO" ou "AUTRE" ou null,
  "scolarite_annee_validee": entier (année LA PLUS HAUTE déjà VALIDÉE, comptée DANS LE CURSUS indiqué par scolarite_formation) ou null,
  "licence_remplacement_specialite": "string (spécialité/DES mentionné sur la licence de remplacement)" ou null,
  "employeur_extrait": "nom de l'employeur lu" ou null,
  "periode_debut_extraite": "YYYY-MM-DD" ou null,
  "periode_fin_extraite": "YYYY-MM-DD" ou null,
  "heures_extraites": nombre d'heures prouvées ou null,
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
- Pour un RIB: pas de date d'expiration. Extrais l'IBAN COMPLET dans "iban_extrait" (il sera validé puis supprimé côté serveur), ainsi que le nom du TITULAIRE dans "nom_extrait"/"prenom_extrait". Mets nom_correspond=false si le titulaire est une autre personne.
- Pour une attestation RPPS/ADELI: extrais le numéro professionnel COMPLET dans "numero_professionnel_extrait" et son type dans "type_identifiant_professionnel". Le serveur le comparera exactement au numéro du profil.
- PIÈCE D'IDENTITÉ (CARTE_IDENTITE, PASSEPORT ou TITRE_SEJOUR) : ces trois types sont des preuves officielles d'identité avec photo. Extrais IMPÉRATIVEMENT la date de naissance sous forme YYYY-MM-DD, en plus du nom et du prénom complets. Si la date est absente ou ambiguë, verdict = "EN_ATTENTE". Extrais aussi la date d'expiration si visible, le sexe ("M" ou "F") et la commune de naissance.
- Pour une assurance RCP: extrais la date de fin de validité
- IMPORTANT: Si le document déclaré est un "Diplôme d'État" mais que le fichier est clairement une carte d'identité, passeport ou tout autre document non-diplôme, verdict = "REJETE" avec motif "Le document fourni n'est pas un diplôme"
- PROFESSION CERTIFIÉE PAR LE DIPLÔME (crucial) : pour TOUT diplôme, extrais dans "profession_certifiee" la profession de santé que ce diplôme certifie. Exemples : "Diplôme d'État d'infirmier" → "IDE" ; "Diplôme d'État d'aide-soignant" / "DEAS" → "AS" ; "Diplôme d'État d'accompagnant éducatif et social" / "DEAES" → "AES" ; "Diplôme d'État de sage-femme" → "SAGE_FEMME" ; "Diplôme d'État de masseur-kinésithérapeute" / "DEMK" → "KINE" ; "Diplôme d'État de docteur en médecine" → "MEDECIN" ; "Diplôme d'État de docteur en pharmacie" → "PHARMACIEN" ; "Diplôme d'État d'infirmier de bloc opératoire" → "IBODE" ; "Diplôme d'État d'infirmier anesthésiste" → "IADE" ; "Diplôme d'État d'auxiliaire de puériculture" / "DEAP" → "AUXILIAIRE_PUERICULTURE" ; "Diplôme de préparateur en pharmacie hospitalière" → "PREPARATEUR_PHARMA" ; "Diplôme de chirurgien-dentiste" → "DENTISTE" ; "Diplôme de manipulateur en électroradiologie médicale" / "DEMERM" → "MANIPULATEUR_RADIO" ; "Diplôme d'État d'ergothérapeute" → "ERGOTHERAPEUTE" ; "Diplôme d'État de psychomotricien" → "PSYCHOMOTRICIEN" ; "Certificat de capacité d'orthophoniste" → "ORTHOPHONISTE" ; diplôme français de diététicien (BTS/BUT reconnu) → "DIETETICIEN". Si le diplôme ne correspond à aucune de ces professions, mets null. Cette information est utilisée côté serveur pour vérifier la concordance avec la profession déclarée par le soignant.
- DIPLÔME ÉTRANGER : pour un diplôme, indique "diplome_etranger" = true si le diplôme est délivré par un établissement HORS France (pays/langue/intitulé étranger) et renseigne "pays_diplome". Un diplôme étranger N'EST PAS rejeté automatiquement : il nécessite une autorisation d'exercice (procédure PAE) et une revue par l'administration → verdict = "EN_ATTENTE" avec motif "Diplôme étranger — vérification de l'autorisation d'exercice par l'administration".
- AUTORISATION D'EXERCICE : extrais aussi dans "profession_certifiee" la profession française précise autorisée par la décision. Si elle n'est pas explicitement lisible, verdict = "EN_ATTENTE".
- ATTESTATION DE SCOLARITÉ / CERTIFICAT DE PASSAGE : si le document déclaré est une attestation de scolarité ou un certificat de passage en année supérieure, vérifie que c'est bien un document d'une ÉCOLE / INSTITUT DE FORMATION en santé (verdict REJETE sinon avec motif "Le document n'est pas une attestation de scolarité d'une école de santé"). Renseigne "scolarite_formation" : "IFSI" pour les soins infirmiers (étudiant infirmier / ESI), "IFAS" pour aide-soignant, "MEDECINE_DFGSM" pour la médecine 1er cycle (DFGSM, années 1-3), "MEDECINE_DFASM" pour la médecine 2e cycle (DFASM / externat), "PHARMACIE" pour les études de pharmacie, "MAIEUTIQUE" pour sage-femme/maïeutique, "ODONTOLOGIE" pour chirurgie dentaire, "KINE" pour masso-kinésithérapie (IFMK), "ERGOTHERAPIE" pour ergothérapie, "PSYCHOMOTRICITE" pour psychomotricité, "MANIP_RADIO" pour manipulateur en électroradiologie médicale (MERM), sinon "AUTRE". Renseigne "scolarite_annee_validee" = le numéro de l'année LA PLUS HAUTE DÉJÀ VALIDÉE, COMPTÉE DANS CE CURSUS. ATTENTION : "admis en Xème année" = la (X-1)ème est validée ; "Xème année validée" = X est validée. Exemples exhaustifs : IFSI "admis en 2e année" → 1 ; "2e année validée" → 2 ; "admis en 3e année" → 2 ; "diplômable" → 3. IFAS (1 an) "admis" ou "en cours" → 0 ; "DEAS obtenu" → 1. MEDECINE_DFGSM "DFGSM2 validé" / "admis en DFGSM3" → 2. MEDECINE_DFASM "DFASM1 validé" → 1 ; "admis en DFASM2" → 1 ; "DFASM3 validé / admis en internat" → 3. PHARMACIE "5e année validée AHU" → 5. KINE "admis en K2" → 1. Si l'année validée n'est pas clairement établie (ex : "inscrit en X" sans mention de validation de l'année précédente), mets null et verdict = "EN_ATTENTE" avec motif "Année de scolarité non clairement établie — vérification manuelle requise".
- Pour cette attestation, extrais impérativement la date d'émission. Un document ancien ne doit jamais suffire à confirmer automatiquement un statut étudiant actuel.
- LICENCE DE REMPLACEMENT : si le document déclaré est une licence de remplacement, vérifie que c'est bien un document délivré par un CONSEIL DE L'ORDRE DES MÉDECINS (conseil départemental/national), au nom du soignant (verdict REJETE sinon avec motif "Le document n'est pas une licence de remplacement de l'Ordre des médecins"). Extrais la date de fin de validité dans "date_expiration" (une licence est valable 1 an) et la spécialité/DES dans "licence_remplacement_specialite". Si la licence est expirée (date_expiration passée) → verdict = "EN_ATTENTE" avec motif "Licence de remplacement expirée — renouvellement requis".
- PREUVE D'HEURES EXTERNES : pour un bulletin de paie, une attestation employeur ou un certificat de travail, extrais impérativement l'employeur, la période et le nombre d'heures lorsqu'il figure. Le serveur recoupera ces champs avec la déclaration; toute absence ou divergence impose une revue humaine.`;

    const userMessage = `Document déclaré comme: "${typeLabel}"
Exigence documentaire exacte: "${exigenceDocumentaire || typeLabel}"
Nom du soignant: "${nomComplet}"
Date de naissance du profil: "${soignant?.date_naissance || "non renseignée"}"
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
      await saveDocumentFields(supabase, document_id, {
        resultat_ia: { erreur_anthropic: { status: estTimeout ? "timeout" : "network", at: new Date().toISOString() } },
      });
      await markDocumentForManualReview(
        supabase,
        document_id,
        verificationAttemptId,
        estTimeout
          ? "La vérification automatique a expiré — demande en attente d'attribution à l'équipe."
          : "Le service de vérification automatique est momentanément inaccessible — demande en attente d'attribution à l'équipe.",
        estTimeout ? "AI_TIMEOUT" : "AI_NETWORK_ERROR",
      );
      reviewContext = null;
      return new Response(JSON.stringify({ success: true, verdict: "REVUE_MANUELLE_REQUISE", reason: estTimeout ? "AI timeout" : "AI network error" }), {
        headers: { ...corsHeaders(req), "Content-Type": "application/json" },
      });
    }
    clearTimeout(aiTimeout);

    if (!ai.ok) {
      console.error("Anthropic API failed:", ai.status, ai.body);
      // Persiste l'erreur Anthropic dans resultat_ia pour diagnostic
      // sans avoir à déployer une version debug.
      await saveDocumentFields(supabase, document_id, {
        resultat_ia: {
          erreur_anthropic: {
            status: ai.status,
            body_excerpt: ai.body.slice(0, 1500),
            at: new Date().toISOString(),
          },
        },
      });
      await markDocumentForManualReview(
        supabase,
        document_id,
        verificationAttemptId,
        "Le service de vérification a refusé la demande — demande en attente d'attribution à l'équipe.",
        `AI_HTTP_${ai.status}`,
      );
      reviewContext = null;
      return new Response(JSON.stringify({ success: true, verdict: "REVUE_MANUELLE_REQUISE", reason: "AI unavailable" }), {
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
      await saveDocumentFields(supabase, document_id, {
        resultat_ia: {
          erreur_parse: { raw_length: rawContent.length, at: new Date().toISOString() },
        },
      });
      await markDocumentForManualReview(
        supabase,
        document_id,
        verificationAttemptId,
        "La réponse automatique était illisible — demande en attente d'attribution à l'équipe.",
        "AI_PARSE_ERROR",
      );
      reviewContext = null;
      return new Response(JSON.stringify({ success: true, verdict: "REVUE_MANUELLE_REQUISE", reason: "Parse error" }), {
        headers: { ...corsHeaders(req), "Content-Type": "application/json" },
      });
    }

    const aiVerdict = typeof analysis.verdict === "string"
      ? analysis.verdict.trim().toUpperCase()
      : "";
    const rawDateEmission = analysis.date_emission;
    const rawDateExpiration = analysis.date_expiration;
    const dateEmission = normalizeIsoDate(analysis.date_emission);
    const dateExpiration = normalizeIsoDate(analysis.date_expiration);
    const dateEmissionFournie = rawDateEmission !== null && rawDateEmission !== undefined
      && String(rawDateEmission).trim() !== "";
    const dateExpirationFournie = rawDateExpiration !== null && rawDateExpiration !== undefined
      && String(rawDateExpiration).trim() !== "";
    analysis.date_emission = dateEmission;
    analysis.date_expiration = dateExpiration;

    // Extraction nom + cohérence — calculée AVANT le verdict pour pouvoir BLOQUER.
    const nomExtraitIa = typeof analysis.nom_extrait === "string"
      ? analysis.nom_extrait.trim().slice(0, 200) || null
      : null;
    const prenomExtraitIa = typeof analysis.prenom_extrait === "string"
      ? analysis.prenom_extrait.trim().slice(0, 200) || null
      : null;
    const scoreConfianceIa = typeof analysis.score_confiance === "number"
      && Number.isFinite(analysis.score_confiance)
      && analysis.score_confiance >= 0
      && analysis.score_confiance <= 100
      ? analysis.score_confiance
      : null;
    const confianceIa = typeof analysis.confiance === "string"
      ? analysis.confiance.trim().toUpperCase()
      : null;
    analysis.nom_extrait = nomExtraitIa;
    analysis.prenom_extrait = prenomExtraitIa;
    analysis.score_confiance = scoreConfianceIa;
    analysis.confiance = confianceIa;
    const coherenceNom = personNameMatches(
      soignant?.nom,
      soignant?.prenom,
      nomExtraitIa,
      prenomExtraitIa,
    );
    const estIdentite = IDENTITY_DOCUMENT_TYPES.has(doc.type_document);
    const dateNaissanceProfilRenseignee = typeof soignant?.date_naissance === "string"
      && soignant.date_naissance.trim().length > 0;
    const dateNaissanceProfil = normalizeIsoDate(soignant?.date_naissance);
    const dateNaissanceExtraite = normalizeIsoDate(analysis.date_naissance_extraite);
    const coherenceDateNaissance = estIdentite
      ? dateNaissanceProfilRenseignee
        ? dateNaissanceProfil !== null && dateNaissanceExtraite === dateNaissanceProfil
        : dateNaissanceExtraite !== null
      : null;
    if (estIdentite) {
      // La valeur brute du modèle n'est jamais conservée comme une date fiable.
      analysis.date_naissance_extraite = dateNaissanceExtraite;
      analysis.date_naissance_correspond = coherenceDateNaissance;
    }
    const confianceHaute = confianceIa === "HAUTE"
      && scoreConfianceIa !== null
      && scoreConfianceIa >= 85;

    // GATE DUR de concordance : toute validation automatique exige un nom/prénom
    // effectivement extrait, concordant côté IA ET côté règle déterministe.
    let verdictFinal = ALLOWED_VERDICTS.has(aiVerdict) ? aiVerdict : "EN_ATTENTE";
    let motifRejet = ALLOWED_VERDICTS.has(aiVerdict)
      ? (typeof analysis.motif_rejet === "string" ? analysis.motif_rejet.slice(0, 1000) : null)
      : "Verdict automatique invalide — vérification manuelle requise.";
    const falsificationRenseignee = Array.isArray(analysis.indices_falsification)
      && analysis.indices_falsification.every((indice: unknown) => typeof indice === "string");
    const indicesFalsif: string[] = falsificationRenseignee
      ? analysis.indices_falsification
        .map((indice: string) => indice.trim().slice(0, 500))
        .filter(Boolean)
        .slice(0, 20)
      : [];
    analysis.indices_falsification = indicesFalsif;
    if (verdictFinal === "VERIFIE" && !falsificationRenseignee) {
      verdictFinal = "EN_ATTENTE";
      motifRejet = "L'analyse de falsification est incomplète — vérification manuelle requise.";
    }
    if (verdictFinal === "VERIFIE" && (coherenceNom !== true || analysis.nom_correspond !== true)) {
      verdictFinal = "EN_ATTENTE";
      motifRejet = coherenceNom === false || analysis.nom_correspond === false
        ? "Le nom du document ne correspond pas à celui du profil — vérification manuelle requise."
        : "L'identité n'a pas pu être extraite avec assez de certitude — vérification manuelle requise.";
    }
    // GATE FALSIFICATION : tout indice de retouche/montage → revue humaine (jamais VERIFIE auto).
    if (verdictFinal === "VERIFIE" && indicesFalsif.length > 0) {
      verdictFinal = "EN_ATTENTE";
      motifRejet = "Indices de falsification détectés — vérification manuelle requise.";
    }
    // GATE DIPLÔME ÉTRANGER : un diplôme délivré hors France nécessite l'autorisation
    // d'exercice (PAE) → jamais VERIFIE auto, transmis à l'administration.
    if (
      doc.type_document === "DIPLOME"
      && analysis.diplome_etranger === true
      && verdictFinal === "VERIFIE"
    ) {
      verdictFinal = "EN_ATTENTE";
      motifRejet = `Diplôme étranger${analysis.pays_diplome ? ` (${analysis.pays_diplome})` : ""} — transmis à l'administration pour vérification de l'autorisation d'exercice (procédure PAE). Téléversez votre autorisation d'exercice si vous en disposez.`;
    }

    // Un verdict IA incohérent avec ses propres champs ne peut jamais auto-valider.
    if (
      verdictFinal === "VERIFIE" &&
      (analysis.type_correspond !== true || analysis.document_lisible !== true ||
        analysis.document_complet !== true || !confianceHaute)
    ) {
      verdictFinal = "EN_ATTENTE";
      motifRejet = "Le type, la lisibilité ou la complétude du document doit être confirmé manuellement.";
    }

    const aujourdHuiIso = new Date().toISOString().slice(0, 10);
    if (
      verdictFinal === "VERIFIE"
      && ((dateEmissionFournie && dateEmission === null)
        || (dateExpirationFournie && dateExpiration === null))
    ) {
      verdictFinal = "EN_ATTENTE";
      motifRejet = "Une date du document est invalide ou ambiguë — vérification manuelle requise.";
    }
    if (verdictFinal === "VERIFIE" && dateEmission && dateEmission > aujourdHuiIso) {
      verdictFinal = "EN_ATTENTE";
      motifRejet = "La date d'émission du document est dans le futur — vérification manuelle requise.";
    }
    if (
      verdictFinal === "VERIFIE"
      && dateEmission
      && dateExpiration
      && dateExpiration < dateEmission
    ) {
      verdictFinal = "EN_ATTENTE";
      motifRejet = "La date d'expiration précède la date d'émission — vérification manuelle requise.";
    }

    // Une pièce d'identité ne peut prouver un profil que si sa date de naissance
    // est une vraie date ISO et, quand le profil en possède déjà une, lui est
    // strictement égale. L'IA ne décide jamais seule de cette correspondance.
    if (
      estIdentite
      && verdictFinal === "VERIFIE"
      && (dateNaissanceExtraite === null
        || dateNaissanceExtraite < "1900-01-01"
        || dateNaissanceExtraite >= aujourdHuiIso)
    ) {
      verdictFinal = "EN_ATTENTE";
      motifRejet = "La date de naissance n'a pas pu être extraite avec certitude ou n'est pas plausible — vérification manuelle requise.";
    } else if (
      estIdentite
      && verdictFinal === "VERIFIE"
      && dateNaissanceProfilRenseignee
      && coherenceDateNaissance !== true
    ) {
      verdictFinal = "EN_ATTENTE";
      motifRejet = "La date de naissance du document ne correspond pas exactement à celle du profil — corrigez le profil ou demandez une revue manuelle.";
    }
    const sexeProfil = typeof soignant?.sexe === "string" ? soignant.sexe.trim().toUpperCase() : null;
    const sexeExtrait = typeof analysis.sexe_extrait === "string"
      ? analysis.sexe_extrait.trim().toUpperCase()
      : null;
    analysis.sexe_extrait = sexeExtrait === "M" || sexeExtrait === "F" ? sexeExtrait : null;
    if (
      estIdentite
      && verdictFinal === "VERIFIE"
      && (sexeProfil === "M" || sexeProfil === "F")
      && analysis.sexe_extrait !== null
      && analysis.sexe_extrait !== sexeProfil
    ) {
      verdictFinal = "EN_ATTENTE";
      motifRejet = "Le sexe lu sur la pièce d'identité contredit celui du profil — vérification manuelle requise.";
    }

    // Un document arrivé à expiration ne satisfait plus l'obligation associée.
    if (verdictFinal === "VERIFIE" && dateExpiration) {
      if (dateExpiration <= aujourdHuiIso) {
        verdictFinal = "REJETE";
        motifRejet = "Ce document est expiré. Téléversez une version en cours de validité.";
      }
    }

    if (verdictFinal === "VERIFIE" && documentRule?.a_expiration === true && !dateExpiration) {
      verdictFinal = "EN_ATTENTE";
      motifRejet = "La date d'expiration requise n'a pas pu être extraite avec certitude — vérification manuelle requise.";
    }

    // FIX #2 : renforcement du type — si l'IA dit type_correspond=true mais que
    // les champs discriminants attendus pour CE type sont absents, on rétrograde.
    // Ceci ajoute un recoupement indépendant du jugement IA sur le type.
    if (verdictFinal === "VERIFIE" && analysis.type_correspond === true) {
      const type = doc.type_document;
      let typeDouteuse = false;
      // Un diplôme ou une autorisation d'exercice VERIFIE doit nommer la
      // profession qu'il permet réellement d'exercer.
      if (
        (type === "DIPLOME" && !analysis.profession_certifiee && analysis.diplome_etranger !== true)
        || (type === "AUTORISATION_EXERCICE" && !analysis.profession_certifiee)
      ) typeDouteuse = true;
      // Toute pièce d'identité vérifiée doit avoir une date de naissance et une
      // date de fin de validité certaines.
      if (IDENTITY_DOCUMENT_TYPES.has(type) && (dateNaissanceExtraite === null || !dateExpiration)) {
        typeDouteuse = true;
      }
      // Une RCP VERIFIE devrait avoir une date d'expiration
      if (type === "RCP_ASSURANCE" && !analysis.date_expiration) typeDouteuse = true;
      if (typeDouteuse) {
        verdictFinal = "EN_ATTENTE";
        motifRejet = (motifRejet ? motifRejet + " | " : "") + "Champs attendus manquants pour ce type de document — vérification manuelle requise.";
      }
    }

    // GATE DIPLÔME ↔ PROFESSION : si le diplôme certifie une profession différente
    // de celle déclarée par le soignant → EN_ATTENTE (revue admin). Critique pour
    // les professions sans RPPS (AS, AES, auxiliaire puériculture) qui n'ont aucun
    // recoupement registre officiel. On compare aussi les professions compatibles
    // (ex : IDE peut téléverser un diplôme IBODE car IBODE est une spécialisation IDE).
    if (doc.type_document === "DIPLOME" || doc.type_document === "AUTORISATION_EXERCICE") {
      if (analysis.diplome_etranger !== false && verdictFinal === "VERIFIE") {
        if (doc.type_document === "DIPLOME") {
          verdictFinal = "EN_ATTENTE";
          motifRejet = "Le pays de délivrance du diplôme n'a pas pu être établi — vérification manuelle requise.";
        }
      }
      const diplomeCorrespond = diplomaMatchesDeclaredProfession(
        soignant?.profession,
        analysis.profession_certifiee,
      );
      if (diplomeCorrespond !== true && verdictFinal === "VERIFIE") {
        verdictFinal = "EN_ATTENTE";
        motifRejet = diplomeCorrespond === false
          ? `Le diplôme certifie la profession "${analysis.profession_certifiee}" mais le profil déclare "${soignant?.profession}" — vérification manuelle requise.`
          : "La profession certifiée par le diplôme n'a pas pu être reliée au profil — vérification manuelle requise.";
      }
    }

    // L'attestation RPPS/ADELI doit porter exactement l'identifiant du profil.
    if (doc.type_document === "RPPS_ADELI") {
      const identifierType = typeof analysis.type_identifiant_professionnel === "string"
        ? analysis.type_identifiant_professionnel.trim().toUpperCase()
        : null;
      const expectedIdentifier = identifierType === "RPPS"
        ? soignant?.numero_rpps
        : identifierType === "ADELI"
        ? soignant?.numero_adeli
        : null;
      const registreVerifie = identifierType === "RPPS"
        ? soignant?.rpps_verifie === true
        : identifierType === "ADELI"
        ? soignant?.adeli_verifie === true
        : false;
      const expectedDigits = String(expectedIdentifier ?? "").replace(/\D/g, "");
      const identifiantExtraitEstTexte = typeof analysis.numero_professionnel_extrait === "string";
      const formatValide = identifierType === "RPPS"
        ? /^\d{11}$/.test(expectedDigits)
        : identifierType === "ADELI"
        ? /^\d{9}$/.test(expectedDigits)
        : false;
      const identifierMatch = professionalIdentifierMatches(
        expectedIdentifier,
        analysis.numero_professionnel_extrait,
      );
      if (
        verdictFinal === "VERIFIE"
        && (!identifiantExtraitEstTexte || !formatValide || identifierMatch !== true || !registreVerifie)
      ) {
        verdictFinal = "EN_ATTENTE";
        motifRejet = !registreVerifie
          ? "Le numéro RPPS/ADELI du profil n'est pas encore confirmé par le registre officiel — vérification manuelle requise."
          : identifierMatch === false
          ? "Le numéro RPPS/ADELI du document ne correspond pas à celui du profil — vérification manuelle requise."
          : "Le type ou le format du numéro RPPS/ADELI n'a pas pu être extrait et comparé — vérification manuelle requise.";
      }
    }

    // Les heures externes influencent l'éligibilité et les avantages financiers :
    // la preuve doit être reliée à la déclaration exacte, jamais seulement au nom.
    let heuresSnapshot: {
      employeur_nom: string | null;
      date_debut: string | null;
      date_fin: string | null;
      heures_declarees: number;
      type_preuve: string | null;
    } | null = null;
    const typesPreuvesHeures = new Set([
      "BULLETIN_PAIE", "ATTESTATION_EMPLOYEUR", "CERTIFICAT_TRAVAIL",
    ]);
    if (typesPreuvesHeures.has(doc.type_document) && verdictFinal === "VERIFIE") {
      const { data: heures, error: heuresError } = await supabase
        .from("heures_externes")
        .select("employeur_nom, date_debut, date_fin, heures_declarees, type_preuve")
        .eq("document_id", document_id)
        .eq("soignant_id", doc.soignant_id)
        .maybeSingle();
      const heuresExtraites = typeof analysis.heures_extraites === "number"
        && Number.isFinite(analysis.heures_extraites)
        && analysis.heures_extraites > 0
        ? analysis.heures_extraites
        : null;
      const heuresDeclarees = Number(heures?.heures_declarees);
      if (heures) {
        heuresSnapshot = {
          employeur_nom: heures.employeur_nom ?? null,
          date_debut: heures.date_debut ?? null,
          date_fin: heures.date_fin ?? null,
          heures_declarees: heuresDeclarees,
          type_preuve: heures.type_preuve ?? null,
        };
      }
      const employeurMatch = corporateNameMatches(heures?.employeur_nom, analysis.employeur_extrait);
      const periodeDebutExtraite = normalizeIsoDate(analysis.periode_debut_extraite);
      const periodeFinExtraite = normalizeIsoDate(analysis.periode_fin_extraite);
      const periodeMatch = Boolean(
        heures && periodeDebutExtraite !== null && periodeFinExtraite !== null
        && periodeDebutExtraite === heures.date_debut
        && periodeFinExtraite === heures.date_fin
      );
      const volumeMatch = heuresExtraites !== null && Number.isFinite(heuresDeclarees)
        && Math.abs(heuresExtraites - heuresDeclarees) <= 0.01;
      const typePreuveMatch = heures?.type_preuve === doc.type_document;
      if (heuresError || !heures || employeurMatch !== true || !periodeMatch || !volumeMatch || !typePreuveMatch) {
        verdictFinal = "EN_ATTENTE";
        motifRejet = "L'employeur, la période ou le volume d'heures de la preuve ne concorde pas exactement avec la déclaration — revue manuelle requise.";
      }
    }

    // Un RIB n'est auto-validé que si son IBAN passe le contrôle ISO 13616.
    if (doc.type_document === "RIB" && verdictFinal === "VERIFIE" && !isValidIban(analysis.iban_extrait)) {
      verdictFinal = "EN_ATTENTE";
      motifRejet = "L'IBAN n'a pas pu être lu ou son checksum est invalide — vérification manuelle requise.";
    }

    // IDENTITÉ CLAIREMENT INCOHÉRENTE → REJETE (actionnable) plutôt que EN_ATTENTE
    // (limbo silencieux qui ne se résout jamais sans intervention admin).
    // On exige une CONVERGENCE forte pour éviter de rejeter à tort un cas ambigu
    // (nom de jeune fille, accents…) : l'IA dit nom_correspond=false, ET notre
    // recoupement chaîne de caractères dit coherenceNom=false, ET confiance haute,
    // ET document lisible. Dans ce cas le titulaire est une AUTRE personne →
    // l'utilisateur doit téléverser SON document (critique pour un RIB : on ne
    // verse pas la rémunération sur le compte d'un tiers). Les cas réellement
    // ambigus (un seul signal, confiance moyenne) restent EN_ATTENTE (revue admin).
    if (
      verdictFinal === "EN_ATTENTE" &&
      analysis.nom_correspond === false &&
      coherenceNom === false &&
      confianceHaute &&
      analysis.document_lisible === true &&
      indicesFalsif.length === 0
    ) {
      verdictFinal = "REJETE";
      motifRejet = motifRejet
        || "Le titulaire du document ne correspond pas à votre identité. Téléversez votre propre document.";
    }

    // La date extraite est contrôlée ici, puis écrite avec le verdict dans la
    // transaction finale. Le profil complet y est reverrouillé et comparé au
    // snapshot : aucun changement concurrent ne peut être écrasé.
    if (estIdentite && verdictFinal === "VERIFIE" && doc.soignant_id && dateNaissanceExtraite) {
      const dateProfil = normalizeIsoDate(soignant.date_naissance);
      if (dateProfil !== null && dateProfil !== dateNaissanceExtraite) {
        verdictFinal = "EN_ATTENTE";
        motifRejet = "La date de naissance du document ne correspond pas exactement à celle du profil — corrigez le profil ou demandez une revue manuelle.";
        analysis.date_naissance_correspond = false;
      } else {
        analysis.date_naissance_correspond = true;
      }
    }

    let scolariteProfileUpdate: Record<string, unknown> | null = null;
    if (doc.type_document === "ATTESTATION_SCOLARITE" && verdictFinal === "VERIFIE") {
      const formation = typeof analysis.scolarite_formation === "string"
        ? analysis.scolarite_formation.trim().toUpperCase()
        : null;
      const anneeMax = formation ? SCOLARITE_MAX_ANNEE_VALIDEE[formation] : undefined;
      const anneeValidee = Number.isInteger(analysis.scolarite_annee_validee)
        && analysis.scolarite_annee_validee >= 0
        && anneeMax !== undefined
        && analysis.scolarite_annee_validee <= anneeMax
        ? analysis.scolarite_annee_validee
        : null;
      const emissionScolariteMs = dateEmission
        ? Date.parse(`${dateEmission}T00:00:00Z`)
        : Number.NaN;
      const scolariteRecente = Number.isFinite(emissionScolariteMs)
        && Date.now() - emissionScolariteMs <= 400 * 24 * 60 * 60 * 1000;
      if (!scolariteRecente) {
        verdictFinal = "EN_ATTENTE";
        motifRejet = "L'attestation de scolarité n'est pas datée de l'année en cours — vérification manuelle requise.";
      } else if (!formation || anneeMax === undefined || anneeValidee === null) {
        verdictFinal = "EN_ATTENTE";
        motifRejet = "La formation et l'année validée n'ont pas pu être établies dans les bornes du cursus — vérification manuelle requise.";
      } else {
        const { data: profs, error: profsError } = await supabase.rpc(
          "fn_professions_autorisees_scolarite" as any,
          { p_formation: formation, p_annee_validee: anneeValidee },
        );
        const liste: string[] = Array.isArray(profs)
          ? (profs as any[]).map((row) => typeof row === "string"
            ? row
            : (row?.fn_professions_autorisees_scolarite ?? Object.values(row ?? {})[0]))
            .filter((value): value is string => typeof value === "string")
          : [];
        if (profsError || liste.length === 0 || !liste.includes(soignant.profession)) {
          verdictFinal = "EN_ATTENTE";
          motifRejet = profsError
            ? "Les équivalences de scolarité sont indisponibles — vérification manuelle requise."
            : `Cette scolarité ne permet pas de valider automatiquement la profession « ${soignant.profession} ».`;
        } else {
          scolariteProfileUpdate = {
            scolarite_formation: formation,
            scolarite_annee_validee: anneeValidee,
            // La preuve est validée contre la profession courante. Ne jamais
            // transformer une équivalence plus large en élévation automatique.
            scolarite_profession_autorisee: soignant.profession,
            scolarite_verifiee: true,
            scolarite_verifiee_le: new Date().toISOString(),
            est_etudiant: true,
            modifie_le: new Date().toISOString(),
          };
        }
      }
    }

    let licenceProfileUpdate: Record<string, unknown> | null = null;
    if (doc.type_document === "LICENCE_REMPLACEMENT" && verdictFinal === "VERIFIE") {
      const specialiteLicence = typeof analysis.licence_remplacement_specialite === "string"
        ? analysis.licence_remplacement_specialite.trim().slice(0, 200)
        : "";
      if (soignant.profession !== "MEDECIN") {
        verdictFinal = "EN_ATTENTE";
        motifRejet = "Une licence de remplacement médical ne peut valider qu'un profil médecin — vérification manuelle requise.";
      } else if (!dateEmission || !dateExpiration) {
        verdictFinal = "EN_ATTENTE";
        motifRejet = "Les dates d'émission et de fin de validité de la licence n'ont pas pu être établies — vérification manuelle requise.";
      } else if (dateExpiration > addCalendarMonthsIso(dateEmission, 13)) {
        verdictFinal = "EN_ATTENTE";
        motifRejet = "La durée de validité lue sur la licence est incohérente — vérification manuelle requise.";
      } else if (!specialiteLicence) {
        verdictFinal = "EN_ATTENTE";
        motifRejet = "La spécialité autorisée par la licence n'a pas pu être établie — vérification manuelle requise.";
      } else {
        licenceProfileUpdate = {
          licence_remplacement_verifiee: true,
          licence_remplacement_le: new Date().toISOString(),
          licence_remplacement_valide_jusqua: dateExpiration,
          licence_remplacement_specialite: specialiteLicence,
          est_etudiant: true,
          modifie_le: new Date().toISOString(),
        };
      }
    }

    analysis.verdict_serveur = verdictFinal;
    analysis.motif_serveur = motifRejet;

    // Ne jamais persister ni renvoyer un IBAN complet. Le contrôle a déjà été
    // effectué ci-dessus ; seuls le checksum et les quatre derniers caractères
    // sont conservés pour le support et l'affichage masqué.
    const analysisPersisted: Record<string, any> = doc.type_document === "RIB"
      ? sanitizeBankAnalysis(analysis as Record<string, unknown>)
      : analysis;
    let verifiedRibIban: string | null = null;
    if (doc.type_document === "RIB" && verdictFinal === "VERIFIE") {
      const normalizedIban = normalizeIban(analysis.iban_extrait ?? analysis.iban ?? "");
      if (!isValidIban(normalizedIban)) {
        // Défense en profondeur : la branche RIB ne doit jamais produire une
        // provenance de paiement si le checksum n'est plus valide ici.
        verdictFinal = "EN_ATTENTE";
        motifRejet = "L'IBAN n'a pas pu être validé de façon déterministe — vérification manuelle requise.";
        analysisPersisted.verdict_serveur = verdictFinal;
        analysisPersisted.motif_serveur = motifRejet;
        analysisPersisted.iban_preuve_hash_v1 = null;
      } else {
        // L'IBAN complet n'est jamais persisté. Cette empreinte salée par l'ID
        // immuable du document permet à la RPC d'enregistrement de prouver une
        // égalité exacte avec l'IBAN ressaisi, sans pouvoir reconstruire celui-ci.
        analysisPersisted.iban_preuve_hash_v1 = await sha256Hex(
          `${normalizedIban}:${document_id}`,
        );
        verifiedRibIban = normalizedIban;
      }
    }

    // Analyse, verdict et éventuels effets de scolarité/licence sont écrits
    // dans une seule transaction. La RPC reverrouille document + profil,
    // compare le snapshot complet et refuse toute réponse devenue obsolète.
    const estRejeteFinal = verdictFinal === "REJETE";
    const { data: finalized, error: finalizeError } = await supabase.rpc(
      "fn_finaliser_document_verification" as any,
      {
        p_document_id: document_id,
        p_attempt_id: verificationAttemptId,
        p_expected_soignant_id: doc.soignant_id,
        p_expected_s3_bucket: doc.s3_bucket,
        p_expected_s3_cle: doc.s3_cle,
        p_expected_type_document: doc.type_document,
        p_expected_nom: soignant.nom,
        p_expected_prenom: soignant.prenom,
        p_expected_date_naissance: normalizeIsoDate(soignant.date_naissance),
        p_expected_sexe: soignant.sexe ?? null,
        p_expected_lieu_naissance: soignant.lieu_naissance_commune ?? null,
        p_expected_profession: soignant.profession,
        p_expected_numero_rpps: soignant.numero_rpps ?? null,
        p_expected_numero_adeli: soignant.numero_adeli ?? null,
        p_expected_rpps_verifie: soignant.rpps_verifie === true,
        p_expected_adeli_verifie: soignant.adeli_verifie === true,
        p_statut_verification: verdictFinal,
        p_motif_rejet: motifRejet,
        p_valide_depuis: estRejeteFinal ? null : dateEmission,
        p_valide_jusqua: estRejeteFinal ? null : dateExpiration,
        p_resultat_ia: analysisPersisted,
        p_nom_extrait_ia: nomExtraitIa,
        p_prenom_extrait_ia: prenomExtraitIa,
        p_score_confiance_ia: scoreConfianceIa,
        p_coherence_nom: coherenceNom,
        p_identite_date_naissance: estIdentite ? dateNaissanceExtraite : null,
        p_identite_sexe: estIdentite && ["M", "F"].includes(analysis.sexe_extrait)
          ? analysis.sexe_extrait
          : null,
        p_identite_lieu_naissance: estIdentite && typeof analysis.lieu_naissance_extrait === "string"
          ? analysis.lieu_naissance_extrait
          : null,
        p_scolarite_formation: scolariteProfileUpdate?.scolarite_formation ?? null,
        p_scolarite_annee_validee: scolariteProfileUpdate?.scolarite_annee_validee ?? null,
        p_scolarite_profession: scolariteProfileUpdate?.scolarite_profession_autorisee ?? null,
        p_licence_valide_jusqua: licenceProfileUpdate?.licence_remplacement_valide_jusqua ?? null,
        p_licence_specialite: licenceProfileUpdate?.licence_remplacement_specialite ?? null,
        p_expected_heures_employeur: heuresSnapshot?.employeur_nom ?? null,
        p_expected_heures_date_debut: heuresSnapshot?.date_debut ?? null,
        p_expected_heures_date_fin: heuresSnapshot?.date_fin ?? null,
        p_expected_heures_declarees: heuresSnapshot?.heures_declarees ?? null,
        p_expected_heures_type_preuve: heuresSnapshot?.type_preuve ?? null,
      },
    );
    if (finalizeError || finalized !== true) {
      console.error(
        "Finalisation atomique impossible ou snapshot modifié:",
        finalizeError?.code || finalizeError?.message || "FINALIZATION_REJECTED",
      );
      await markDocumentForManualReview(
        supabase,
        document_id,
        verificationAttemptId,
        "Le profil ou le document a changé pendant le contrôle — demande en attente d'attribution à l'équipe.",
        "FINALIZATION_REJECTED",
      );
      reviewContext = null;
      return new Response(JSON.stringify({
        error: "Le profil ou le document a changé pendant la vérification. Relancez le contrôle.",
      }), {
        status: finalizeError?.code === "40001" ? 409 : 503,
        headers: { ...corsHeaders(req), "Content-Type": "application/json" },
      });
    }

    if (verdictFinal === "EN_ATTENTE") {
      await markDocumentForManualReview(
        supabase,
        document_id,
        null,
        motifRejet || "La vérification automatique n'est pas concluante — demande en attente d'attribution à l'équipe.",
        "AI_REVIEW_REQUIRED",
      );
    } else if (doc.type_document === "RIB" && verdictFinal === "VERIFIE" && verifiedRibIban) {
      // L'IBAN complet ne transite qu'en mémoire entre l'analyse et cette RPC
      // service-role. Il n'est jamais renvoyé, journalisé ni conservé dans le
      // résultat IA ; seule sa liaison chiffrée à cette version du RIB demeure.
      const { data: linked, error: linkError } = await supabase.rpc(
        "fn_lier_iban_verifie_document" as any,
        {
          p_document_id: document_id,
          p_expected_s3_cle: doc.s3_cle,
          p_iban: verifiedRibIban,
        },
      );
      if (linkError || (linked?.success !== true
        && !["IDENTITE_VERIFIEE_REQUISE", "IDENTITE_COURANTE_REQUISE"].includes(linked?.error_code))) {
        console.error(
          "Liaison RIB déterministe impossible:",
          linkError?.code || linkError?.message || linked?.error_code || "UNKNOWN",
        );
        await markDocumentForManualReview(
          supabase,
          document_id,
          null,
          "Le RIB n'a pas pu être lié de façon certaine au compte de versement — demande en attente d'attribution à l'équipe.",
          "RIB_BINDING_FAILED",
        );
        verdictFinal = "EN_ATTENTE";
        motifRejet = "Le RIB doit être revu avant tout versement.";
      }
    }
    reviewContext = null;

    const { error: auditError } = await supabase.rpc("fn_ecrire_audit_safe" as any, {
      p_acteur_id: doc.soignant_id,
      p_type_acteur: "SYSTEME",
      p_action: "DOCUMENT_VERIFICATION_AUTO",
      p_type_ressource: "document",
      p_id_ressource: document_id,
      p_cle_s3: doc.s3_cle,
      p_details: {
        verdict: verdictFinal,
        verdict_ia_brut: analysisPersisted.verdict,
        type_detecte: analysisPersisted.type_detecte,
        confiance: analysisPersisted.confiance,
        nom_correspond: analysisPersisted.nom_correspond,
        coherence_nom: coherenceNom,
        type_correspond: analysisPersisted.type_correspond,
      },
      p_ip: null,
      p_navigateur: "edge-function/verify-document",
    });
    if (auditError) {
      console.error("Audit vérification document impossible:", auditError.code || auditError.message);
    }

    return new Response(
      JSON.stringify({
        success: true,
        verdict: verdictFinal,
        analysis: {
          motif_rejet: motifRejet,
          type_detecte: analysisPersisted.type_detecte ?? null,
          confiance: analysisPersisted.confiance ?? null,
          date_expiration: analysisPersisted.date_expiration ?? null,
          profession_certifiee: analysisPersisted.profession_certifiee ?? null,
        },
      }),
      { headers: { ...corsHeaders(req), "Content-Type": "application/json" } }
    );
  } catch (e: any) {
    console.error("verify-document error:", e);
    if (reviewContext) {
      await markDocumentForManualReview(
        reviewContext.supabase,
        reviewContext.documentId,
        reviewContext.attemptId,
        "La vérification automatique a rencontré une erreur interne — demande en attente d'attribution à l'équipe.",
        "UNHANDLED_VERIFICATION_ERROR",
      ).catch((reviewError) => {
        console.error("Mise en file après erreur interne impossible:", safeStringifyError(reviewError));
      });
    }
    return new Response(
      JSON.stringify({ error: e?.message || "Une erreur interne est survenue." }),
      { status: 500, headers: { ...corsHeaders(req), "Content-Type": "application/json" } }
    );
  }
});
