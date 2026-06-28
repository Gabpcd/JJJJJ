import { createClient } from "npm:@supabase/supabase-js@2";
import { applyRateLimit, getClientIp } from "../_shared/rate-limit.ts";

// Vérification IA du contrat de travail d'une mission salariée.
// Confirme que le PDF est bien un contrat de travail (CDD/CDI) et que les parties
// (soignant salarié + établissement employeur) concordent avec la mission.

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
function norm(s: string | null | undefined): string {
  return (s || "").toString().normalize("NFD").replace(/[̀-ͯ]/g, "").toLowerCase().replace(/[^a-z0-9]/g, "");
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

    const { mission_id } = await req.json();
    if (!mission_id) throw new Error("mission_id requis");

    const anthropicKey = Deno.env.get("ANTHROPIC_API_KEY");
    if (!anthropicKey) throw new Error("ANTHROPIC_API_KEY non configurée");

    const { data: ct } = await supabase
      .from("contrats_travail_missions")
      .select("id, mission_id, etablissement_id, soignant_id, pdf_s3_key")
      .eq("mission_id", mission_id)
      .order("uploaded_at", { ascending: false })
      .limit(1)
      .maybeSingle();
    if (!ct) throw new Error("Contrat de travail introuvable pour cette mission");

    // Sécurité : seul l'étab employeur (ou service role) peut déclencher la vérif.
    if (!isServiceRole && authUserId && (ct as any).etablissement_id !== authUserId) {
      return new Response(JSON.stringify({ error: "Accès refusé" }), { status: 403, headers: { ...corsHeaders(req), "Content-Type": "application/json" } });
    }

    const [{ data: soig }, { data: etab }] = await Promise.all([
      supabase.from("soignants").select("nom, prenom").eq("id", (ct as any).soignant_id).maybeSingle(),
      supabase.from("etablissements").select("nom, siret_raison_sociale, finess_raison_sociale").eq("id", (ct as any).etablissement_id).maybeSingle(),
    ]);
    const soignantNom = `${(soig as any)?.prenom || ""} ${(soig as any)?.nom || ""}`.trim();
    const etabNom = (etab as any)?.siret_raison_sociale || (etab as any)?.finess_raison_sociale || (etab as any)?.nom || "";

    const { data: fileData, error: fileErr } = await supabase.storage.from("jolene-documents").download((ct as any).pdf_s3_key);
    if (fileErr || !fileData) throw new Error("Impossible de télécharger le contrat de travail");
    const arrayBuffer = await fileData.arrayBuffer();
    const bytes = new Uint8Array(arrayBuffer);
    let binary = "";
    for (let i = 0; i < bytes.length; i += 8192) { const chunk = bytes.subarray(i, Math.min(i + 8192, bytes.length)); for (let j = 0; j < chunk.length; j++) binary += String.fromCharCode(chunk[j]); }
    const base64 = btoa(binary);

    const systemPrompt = `Tu es un vérificateur de contrats de travail (CDD/CDI) pour des missions de soignants salariés. Analyse le PDF et réponds UNIQUEMENT en JSON valide:
{
  "est_contrat_travail": true/false,
  "type_detecte": "string (CDD, CDI, autre)",
  "salarie_extrait": "nom du salarié lu" ou null,
  "employeur_extrait": "nom de l'employeur lu" ou null,
  "salarie_correspond": true/false/null,
  "employeur_correspond": true/false/null,
  "document_lisible": true/false,
  "indices_falsification": [] ou ["..."],
  "score_confiance": 0-100,
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
    let aiResponse: Response;
    try {
      aiResponse = await fetch("https://api.anthropic.com/v1/messages", { method: "POST", headers: { "x-api-key": anthropicKey, "anthropic-version": "2023-06-01", "Content-Type": "application/json" }, body: JSON.stringify({ model: "claude-sonnet-4-6", max_tokens: 1000, system: systemPrompt, messages: [{ role: "user", content: [{ type: "text", text: userMessage }, { type: "document", source: { type: "base64", media_type: "application/pdf", data: base64 } }] }] }), signal: aiController.signal });
    } catch (e) {
      clearTimeout(aiTimeout);
      const estTimeout = (e as any)?.name === "AbortError";
      await supabase.from("contrats_travail_missions").update({ ia_resultat: { erreur_anthropic: { status: estTimeout ? "timeout" : "network", at: new Date().toISOString() } } } as any).eq("id", (ct as any).id);
      return new Response(JSON.stringify({ success: true, coherent: null, reason: estTimeout ? "AI timeout" : "AI network error" }), { headers: { ...corsHeaders(req), "Content-Type": "application/json" } });
    }
    clearTimeout(aiTimeout);
    if (!aiResponse.ok) {
      const errText = await aiResponse.text();
      await supabase.from("contrats_travail_missions").update({ ia_resultat: { erreur_anthropic: { status: aiResponse.status, body_excerpt: errText.slice(0, 1500), at: new Date().toISOString() } } } as any).eq("id", (ct as any).id);
      return new Response(JSON.stringify({ success: true, coherent: null, reason: "AI unavailable" }), { headers: { ...corsHeaders(req), "Content-Type": "application/json" } });
    }
    const aiData = await aiResponse.json();
    const rawContent = aiData.content?.[0]?.text || "";
    let analysis: any;
    try { const m = rawContent.match(/\{[\s\S]*\}/); analysis = m ? JSON.parse(m[0]) : null; } catch { analysis = null; }
    if (!analysis) {
      await supabase.from("contrats_travail_missions").update({ ia_resultat: { erreur_parse: { raw_excerpt: rawContent.slice(0, 1500), at: new Date().toISOString() } } } as any).eq("id", (ct as any).id);
      return new Response(JSON.stringify({ success: true, coherent: null, reason: "Parse error" }), { headers: { ...corsHeaders(req), "Content-Type": "application/json" } });
    }

    const indicesFalsif = Array.isArray(analysis.indices_falsification) ? analysis.indices_falsification : [];
    let coherent: boolean; let motif: string | null = null;
    if (analysis.verdict === "REJETE" || analysis.est_contrat_travail === false) { coherent = false; motif = analysis.motif || "Le document n'est pas un contrat de travail."; }
    else if (indicesFalsif.length > 0) { coherent = false; motif = `Indices de falsification : ${indicesFalsif.join(", ")}.`; }
    else if (analysis.verdict === "VERIFIE" && analysis.salarie_correspond !== false && analysis.employeur_correspond !== false) { coherent = true; motif = "Contrat de travail vérifié : type et parties concordants."; }
    else { coherent = false; motif = analysis.motif || "Concordance salarié/employeur non confirmée — revue manuelle requise."; }

    await supabase.from("contrats_travail_missions").update({ ia_resultat: analysis, ia_coherent: coherent, ia_verifie_le: new Date().toISOString() } as any).eq("id", (ct as any).id);
    await supabase.rpc("fn_ecrire_audit_safe" as any, { p_acteur_id: (ct as any).etablissement_id, p_type_acteur: "SYSTEME", p_action: "CONTRAT_TRAVAIL_VERIFICATION_IA", p_type_ressource: "mission", p_id_ressource: mission_id, p_cle_s3: (ct as any).pdf_s3_key, p_details: { coherent, verdict_ia: analysis.verdict, est_contrat_travail: analysis.est_contrat_travail, falsification: indicesFalsif.length > 0 }, p_ip: null, p_navigateur: "edge-function/verify-contrat-travail" });

    return new Response(JSON.stringify({ success: true, coherent, motif, analysis }), { headers: { ...corsHeaders(req), "Content-Type": "application/json" } });
  } catch (e: any) {
    console.error("verify-contrat-travail error:", e);
    return new Response(JSON.stringify({ error: e?.message || "Une erreur interne est survenue." }), { status: 500, headers: { ...corsHeaders(req), "Content-Type": "application/json" } });
  }
});
