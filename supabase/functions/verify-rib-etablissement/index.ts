import { createClient } from "npm:@supabase/supabase-js@2";
import { applyRateLimit, getClientIp } from "../_shared/rate-limit.ts";
import { appelerAnthropic } from "../_shared/anthropic.ts";

// Vérification IA du RIB d'un établissement (PDF ou image). Confirme que le document
// est bien un RIB et que le titulaire du compte correspond à l'établissement.

function getCorsOrigin(req: Request): string {
  const origin = req.headers.get("origin") || "";
  if (origin === "https://jolene.app" || origin === "https://app.jolene.app" || origin === "https://www.jolene.app" || origin === "http://localhost:5173" || origin === "http://localhost:8080") return origin;
  return "https://jolene.app";
}
function corsHeaders(req: Request) {
  return { "Access-Control-Allow-Origin": getCorsOrigin(req), "Access-Control-Allow-Headers": "authorization, x-client-info, apikey, content-type, x-supabase-client-platform, x-supabase-client-platform-version, x-supabase-client-runtime, x-supabase-client-runtime-version" };
}
let _cachedVaultSecret: string | null = null;
async function getVaultSecret(sb: any): Promise<string> {
  if (_cachedVaultSecret) return _cachedVaultSecret;
  const env = Deno.env.get("SUPABASE_SECRET_KEY") || "";
  if (env) { _cachedVaultSecret = env; return env; }
  try { const { data } = await sb.rpc("fn_lire_secret_cron"); if (data && typeof data === "string") { _cachedVaultSecret = data; return data; } } catch { /* ignore */ }
  return "";
}
function devinerMime(nom: string | null): string {
  const n = (nom || "").toLowerCase();
  if (n.endsWith(".pdf")) return "application/pdf";
  if (n.endsWith(".png")) return "image/png";
  if (n.endsWith(".webp")) return "image/webp";
  return "image/jpeg";
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
      if (applyRateLimit("verify-rib-etab", getClientIp(req), { max: 8, windowMs: 60000 })) return new Response(JSON.stringify({ error: "Trop de vérifications. Réessayez dans 1 minute." }), { status: 429, headers: { ...corsHeaders(req), "Content-Type": "application/json" } });
    }

    const { etablissement_id } = await req.json();
    if (!etablissement_id) throw new Error("etablissement_id requis");
    if (!isServiceRole && authUserId && etablissement_id !== authUserId) return new Response(JSON.stringify({ error: "Accès refusé" }), { status: 403, headers: { ...corsHeaders(req), "Content-Type": "application/json" } });

    const anthropicKey = Deno.env.get("ANTHROPIC_API_KEY");
    if (!anthropicKey) throw new Error("ANTHROPIC_API_KEY non configurée");

    const { data: etab } = await supabase.from("etablissements").select("id, nom, siret_raison_sociale, finess_raison_sociale, rib_s3_key").eq("id", etablissement_id).maybeSingle();
    if (!etab) throw new Error("Établissement introuvable");
    if (!(etab as any).rib_s3_key) return new Response(JSON.stringify({ success: true, coherent: null, reason: "Aucun RIB téléversé" }), { headers: { ...corsHeaders(req), "Content-Type": "application/json" } });

    const { data: fileData, error: fileErr } = await supabase.storage.from("jolene-documents").download((etab as any).rib_s3_key);
    if (fileErr || !fileData) throw new Error("Impossible de télécharger le RIB");
    const arrayBuffer = await fileData.arrayBuffer();
    const bytes = new Uint8Array(arrayBuffer);
    let binary = "";
    for (let i = 0; i < bytes.length; i += 8192) { const chunk = bytes.subarray(i, Math.min(i + 8192, bytes.length)); for (let j = 0; j < chunk.length; j++) binary += String.fromCharCode(chunk[j]); }
    const base64 = btoa(binary);
    const mimeRaw = (fileData as any).type && (fileData as any).type !== "application/octet-stream" ? (fileData as any).type : devinerMime((etab as any).rib_s3_key);
    const ALLOWED = ["image/jpeg", "image/png", "image/webp", "application/pdf"];
    const mime = ALLOWED.includes(mimeRaw) ? mimeRaw : devinerMime((etab as any).rib_s3_key);
    const isPdf = mime === "application/pdf";

    const raisonSociale = (etab as any).siret_raison_sociale || (etab as any).finess_raison_sociale || (etab as any).nom || "";

    const systemPrompt = `Tu es un vérificateur de RIB (Relevé d'Identité Bancaire). Analyse le document et réponds UNIQUEMENT en JSON valide:
{
  "est_rib": true/false,
  "titulaire_extrait": "nom du titulaire du compte" ou null,
  "iban_partiel": "les 4 derniers caractères de l'IBAN" ou null,
  "banque": "nom de la banque" ou null,
  "titulaire_correspond": true/false/null,
  "document_lisible": true/false,
  "indices_falsification": [] ou ["..."],
  "score_confiance": 0-100,
  "motif": null ou "string",
  "verdict": "VERIFIE"/"EN_ATTENTE"/"REJETE"
}
Règles:
- est_rib = true seulement si c'est bien un RIB (IBAN + BIC + titulaire), pas une facture/contrat/autre.
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
      await supabase.from("etablissements").update({ rib_ia_resultat: { erreur_anthropic: { status: estTimeout ? "timeout" : "network", at: new Date().toISOString() } } } as any).eq("id", etablissement_id);
      return new Response(JSON.stringify({ success: true, coherent: null, reason: estTimeout ? "AI timeout" : "AI network error" }), { headers: { ...corsHeaders(req), "Content-Type": "application/json" } });
    }
    if (!ai.ok) {
      await supabase.from("etablissements").update({ rib_ia_resultat: { erreur_anthropic: { status: ai.status, body_excerpt: ai.body.slice(0, 1500), at: new Date().toISOString() } } } as any).eq("id", etablissement_id);
      return new Response(JSON.stringify({ success: true, coherent: null, reason: "AI unavailable" }), { headers: { ...corsHeaders(req), "Content-Type": "application/json" } });
    }
    const aiData = ai.data;
    const rawContent = aiData.content?.[0]?.text || "";
    let analysis: any;
    try { const m = rawContent.match(/\{[\s\S]*\}/); analysis = m ? JSON.parse(m[0]) : null; } catch { analysis = null; }
    if (!analysis) {
      await supabase.from("etablissements").update({ rib_ia_resultat: { erreur_parse: { raw_excerpt: rawContent.slice(0, 1500), at: new Date().toISOString() } } } as any).eq("id", etablissement_id);
      return new Response(JSON.stringify({ success: true, coherent: null, reason: "Parse error" }), { headers: { ...corsHeaders(req), "Content-Type": "application/json" } });
    }

    const indicesFalsif = Array.isArray(analysis.indices_falsification) ? analysis.indices_falsification : [];
    let coherent: boolean; let motif: string | null = null;
    if (analysis.verdict === "REJETE" || analysis.est_rib === false) { coherent = false; motif = analysis.motif || "Le document n'est pas un RIB."; }
    else if (indicesFalsif.length > 0) { coherent = false; motif = `Indices de falsification : ${indicesFalsif.join(", ")}.`; }
    else if (analysis.verdict === "VERIFIE" && analysis.titulaire_correspond !== false) { coherent = true; motif = "RIB vérifié : titulaire concordant."; }
    else { coherent = false; motif = analysis.motif || "Titulaire du RIB non concordant — revue manuelle requise."; }

    await supabase.from("etablissements").update({ rib_ia_resultat: analysis, rib_ia_coherent: coherent, rib_ia_verifie_le: new Date().toISOString() } as any).eq("id", etablissement_id);
    await supabase.rpc("fn_ecrire_audit_safe" as any, { p_acteur_id: etablissement_id, p_type_acteur: "SYSTEME", p_action: "RIB_ETAB_VERIFICATION_IA", p_type_ressource: "etablissement", p_id_ressource: etablissement_id, p_cle_s3: (etab as any).rib_s3_key, p_details: { coherent, verdict_ia: analysis.verdict, est_rib: analysis.est_rib, falsification: indicesFalsif.length > 0 }, p_ip: null, p_navigateur: "edge-function/verify-rib-etablissement" });

    return new Response(JSON.stringify({ success: true, coherent, motif, analysis }), { headers: { ...corsHeaders(req), "Content-Type": "application/json" } });
  } catch (e: any) {
    console.error("verify-rib-etablissement error:", e);
    return new Response(JSON.stringify({ error: e?.message || "Une erreur interne est survenue." }), { status: 500, headers: { ...corsHeaders(req), "Content-Type": "application/json" } });
  }
});
