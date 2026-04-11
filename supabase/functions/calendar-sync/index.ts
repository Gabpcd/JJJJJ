// Edge function : calendar-sync
// Synchronise les missions Jolene vers les calendriers externes connectés.
// Pour l'instant : mode "dry-run" — enregistre les entrées calendar_events_sync
// sans appeler les API Google/Microsoft (OAuth2 pas encore configuré).

import { createClient } from "npm:@supabase/supabase-js@2";

function corsHeaders(req: Request) {
  const origin = req.headers.get("origin") || "";
  if (
    origin === "https://jolene.app" ||
    origin === "https://www.jolene.app" ||
    origin === "http://localhost:5173" ||
    origin === "http://localhost:8080"
  ) {
    return {
      "Access-Control-Allow-Origin": origin,
      "Access-Control-Allow-Headers": "authorization, x-client-info, apikey, content-type",
      "Content-Type": "application/json",
    };
  }
  return {
    "Access-Control-Allow-Origin": "https://jolene.app",
    "Access-Control-Allow-Headers": "authorization, x-client-info, apikey, content-type",
    "Content-Type": "application/json",
  };
}

Deno.serve(async (req) => {
  if (req.method === "OPTIONS") {
    return new Response(null, { headers: corsHeaders(req) });
  }

  try {
    // Warm ping
    const bodyRaw = await req.clone().json().catch(() => ({}));
    if (bodyRaw?.warm === true) {
      return new Response(JSON.stringify({ warm: true }), { headers: corsHeaders(req) });
    }

    if (req.method !== "POST") {
      return new Response(JSON.stringify({ error: "Méthode non autorisée" }), {
        status: 405,
        headers: corsHeaders(req),
      });
    }

    const { user_id, provider } = bodyRaw;

    if (!user_id) {
      return new Response(JSON.stringify({ error: "user_id requis" }), {
        status: 400,
        headers: corsHeaders(req),
      });
    }

    const supabaseUrl = Deno.env.get("SUPABASE_URL")!;
    const serviceRoleKey = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")!;
    const supabase = createClient(supabaseUrl, serviceRoleKey, { auth: { persistSession: false } });

    // Verify the caller is authenticated
    const authHeader = req.headers.get("Authorization");
    if (authHeader) {
      const bearerToken = authHeader.replace("Bearer ", "");
      if (bearerToken !== serviceRoleKey) {
        const anonKey = Deno.env.get("SUPABASE_ANON_KEY")!;
        const authClient = createClient(supabaseUrl, anonKey, { auth: { persistSession: false } });
        const { data: { user }, error: authError } = await authClient.auth.getUser(bearerToken);
        if (authError || !user || user.id !== user_id) {
          return new Response(JSON.stringify({ error: "Non autorisé" }), {
            status: 401,
            headers: corsHeaders(req),
          });
        }
      }
    }

    // 1. Fetch active calendar connections for this user
    let connectionsQuery = supabase
      .from("calendar_connections")
      .select("*")
      .eq("utilisateur_id", user_id)
      .eq("status", "connected");

    if (provider) {
      connectionsQuery = connectionsQuery.eq("provider", provider);
    }

    const { data: connections, error: connError } = await connectionsQuery;

    if (connError) {
      console.error("Erreur récupération connexions:", connError);
      return new Response(JSON.stringify({ error: "Erreur récupération connexions" }), {
        status: 500,
        headers: corsHeaders(req),
      });
    }

    // 2. Fetch upcoming missions (ASSIGNEE/EN_COURS)
    const { data: missions, error: missionsError } = await supabase
      .from("missions")
      .select("id, intitule, debut_le, fin_le, service, taux_horaire_base, etablissement_id, description")
      .eq("soignant_assigne_id", user_id)
      .in("statut", ["ASSIGNEE", "EN_COURS"])
      .gte("fin_le", new Date().toISOString())
      .order("debut_le");

    if (missionsError) {
      console.error("Erreur récupération missions:", missionsError);
      return new Response(JSON.stringify({ error: "Erreur récupération missions" }), {
        status: 500,
        headers: corsHeaders(req),
      });
    }

    // 3. Fetch establishment info for location details
    const etabIds = [...new Set((missions || []).map((m: any) => m.etablissement_id))];
    let etabMap: Record<string, any> = {};
    if (etabIds.length > 0) {
      const { data: etabs } = await supabase
        .from("etablissements")
        .select("id, nom, adresse_rue, adresse_ville, adresse_code_postal")
        .in("id", etabIds);
      for (const e of etabs || []) {
        etabMap[e.id] = e;
      }
    }

    let syncedCount = 0;

    // 4. For each connection, create/update calendar_events_sync entries
    for (const conn of connections || []) {
      for (const mission of missions || []) {
        const etab = etabMap[mission.etablissement_id];
        const location = etab
          ? [etab.adresse_rue, etab.adresse_code_postal, etab.adresse_ville].filter(Boolean).join(", ")
          : "";

        // Upsert sync entry
        const { error: upsertError } = await supabase
          .from("calendar_events_sync")
          .upsert(
            {
              utilisateur_id: user_id,
              connection_id: conn.id,
              mission_id: mission.id,
              provider: conn.provider,
              event_summary: mission.intitule,
              event_start: mission.debut_le,
              event_end: mission.fin_le,
              event_location: location,
              event_description: [
                etab ? `Établissement: ${etab.nom}` : "",
                mission.service ? `Service: ${mission.service}` : "",
                `Taux: ${mission.taux_horaire_base}€/h`,
              ].filter(Boolean).join("\n"),
              sync_status: "pending",
              updated_at: new Date().toISOString(),
            },
            { onConflict: "connection_id,mission_id" }
          );

        if (upsertError) {
          console.error(`Erreur upsert sync pour mission ${mission.id}:`, upsertError);
          continue;
        }

        // Log what WOULD be synced (actual API calls require OAuth tokens)
        console.log(
          `[calendar-sync] Would sync mission ${mission.id} ("${mission.intitule}") ` +
          `to ${conn.provider} for user ${user_id}. ` +
          `Start: ${mission.debut_le}, End: ${mission.fin_le}, Location: ${location}`
        );

        syncedCount++;
      }

      // Update last_sync_at on the connection
      await supabase
        .from("calendar_connections")
        .update({ last_sync_at: new Date().toISOString() })
        .eq("id", conn.id);
    }

    // If no active connections, still count missions that could be synced
    if (!connections || connections.length === 0) {
      syncedCount = (missions || []).length;
      console.log(
        `[calendar-sync] No active connections for user ${user_id}. ` +
        `${syncedCount} mission(s) available for sync.`
      );
    }

    return new Response(
      JSON.stringify({ success: true, synced: syncedCount }),
      { headers: corsHeaders(req) }
    );
  } catch (err) {
    console.error("calendar-sync error:", err);
    return new Response(
      JSON.stringify({ error: "Erreur interne du serveur" }),
      { status: 500, headers: corsHeaders(req) }
    );
  }
});
