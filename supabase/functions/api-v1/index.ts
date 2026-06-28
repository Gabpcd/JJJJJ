import { createClient } from "https://esm.sh/@supabase/supabase-js@2"

Deno.serve(async (req) => {
  const corsHeaders = { "Access-Control-Allow-Origin": "https://jolene.app", "Content-Type": "application/json" };
  if (req.method === "OPTIONS") {
    return new Response(null, { headers: { ...corsHeaders, "Access-Control-Allow-Headers": "authorization, x-api-key, content-type", "Access-Control-Allow-Methods": "GET,POST,PUT" }});
  }
  try {
    const apiKey = req.headers.get("x-api-key");
    if (!apiKey) return new Response(JSON.stringify({ error: "Clé API requise (header x-api-key)" }), { status: 401, headers: corsHeaders });

    const supabase = createClient(Deno.env.get("SUPABASE_URL")!, Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")!);

    const { data: key } = await supabase.from("api_keys").select("*").eq("cle_api", apiKey).eq("actif", true).maybeSingle();
    if (!key) return new Response(JSON.stringify({ error: "Clé API invalide" }), { status: 403, headers: corsHeaders });
    if (key.expire_le && new Date(key.expire_le) < new Date()) return new Response(JSON.stringify({ error: "Clé API expirée" }), { status: 403, headers: corsHeaders });

    // Isolation multi-tenant stricte : une clé DOIT être rattachée à un établissement.
    // Sans ce garde, une clé non scopée (etablissement_id NULL) accède en lecture/écriture
    // à TOUTES les données de TOUS les établissements (missions, présences/PII, factures).
    const etabId = key.etablissement_id;
    if (!etabId) return new Response(JSON.stringify({ error: "Clé API non rattachée à un établissement" }), { status: 403, headers: corsHeaders });

    await supabase.from("api_keys").update({ derniere_utilisation: new Date().toISOString() }).eq("id", key.id);

    const url = new URL(req.url);
    const path = url.pathname.replace(/.*\/api-v1/, "");

    // GET /missions
    if (req.method === "GET" && path === "/missions") {
      const statut = url.searchParams.get("statut");
      let query = supabase.from("missions").select("id, intitule, profession_requise, service, debut_le, fin_le, taux_horaire_base, statut, soignant_assigne_id");
      if (etabId) query = query.eq("etablissement_id", etabId);
      if (statut) query = query.eq("statut", statut);
      const { data, error } = await query.order("debut_le", { ascending: false }).limit(100);
      if (error) { console.error("api-v1 GET /missions error:", error.message); return new Response(JSON.stringify({ error: "Erreur requête" }), { status: 500, headers: corsHeaders }); }
      return new Response(JSON.stringify({ missions: data, count: data?.length }), { headers: corsHeaders });
    }

    // POST /missions
    if (req.method === "POST" && path === "/missions") {
      if (!key.permissions.includes("missions:write")) return new Response(JSON.stringify({ error: "Permission refusée" }), { status: 403, headers: corsHeaders });
      const body = await req.json();
      const { data, error } = await supabase.from("missions").insert({
        etablissement_id: etabId,  // toujours l'étab de la clé — jamais le body (anti cross-tenant)
        intitule: body.intitule,
        profession_requise: body.profession_requise,
        service: body.service,
        debut_le: body.debut_le,
        fin_le: body.fin_le,
        taux_horaire_base: body.taux_horaire_base,
      }).select("id, intitule, statut").single();
      if (error) { console.error("api-v1 POST /missions error:", error.message); return new Response(JSON.stringify({ error: "Erreur création" }), { status: 500, headers: corsHeaders }); }
      return new Response(JSON.stringify({ mission: data }), { status: 201, headers: corsHeaders });
    }

    // GET /presences
    if (req.method === "GET" && path === "/presences") {
      let query = supabase.from("presences").select("id, mission_id, soignant_id, pointage_arrivee_le, pointage_depart_le, validee_par_etablissement, methode_pointage_arrivee");
      if (etabId) {
        const { data: missionIds } = await supabase.from("missions").select("id").eq("etablissement_id", etabId);
        const ids = (missionIds || []).map(m => m.id);
        if (ids.length > 0) query = query.in("mission_id", ids);
        else return new Response(JSON.stringify({ presences: [], count: 0 }), { headers: corsHeaders });
      }
      const { data } = await query.order("pointage_arrivee_le", { ascending: false }).limit(100);
      return new Response(JSON.stringify({ presences: data, count: data?.length }), { headers: corsHeaders });
    }

    // GET /factures
    if (req.method === "GET" && path === "/factures") {
      let query = supabase.from("factures").select("id, numero_facture, statut, montant_ht, montant_tva, montant_ttc, cree_le");
      if (etabId) query = query.eq("etablissement_id", etabId);
      const { data } = await query.order("cree_le", { ascending: false }).limit(50);
      return new Response(JSON.stringify({ factures: data, count: data?.length }), { headers: corsHeaders });
    }

    return new Response(JSON.stringify({
      error: "Endpoint non trouvé",
      endpoints: ["GET /missions", "POST /missions", "GET /presences", "GET /factures"],
      documentation: "https://jolene.app/admin/api"
    }), { status: 404, headers: corsHeaders });
  } catch (e) {
    console.error("api-v1 error:", e); return new Response(JSON.stringify({ error: "Erreur interne" }), { status: 500, headers: corsHeaders });
  }
});
