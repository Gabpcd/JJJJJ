// Edge function : calendar-sync
// Synchronise les missions Jolene vers les calendriers externes connectes.
// Pour l'instant : mode "dry-run" -- enregistre les entrees calendar_events_sync
// sans appeler les API Google/Microsoft (OAuth2 pas encore configure).

import { createClient } from "npm:@supabase/supabase-js@2.99.2";
import { jsonResponse, preflightResponse } from '../_shared/cors.ts';
import { verifyAdminOrServiceRole, verifyUserOrServiceRole } from '../_shared/admin-auth.ts';
import { applyRateLimit, getClientIp } from '../_shared/rate-limit.ts';

Deno.serve(async (req) => {
  if (req.method === "OPTIONS") {
    return preflightResponse(req);
  }

  try {
    if (req.method !== "POST") {
      return jsonResponse(req, { error: "Methode non autorisee" }, 405);
    }

    const auth = await verifyUserOrServiceRole(req);
    if (!auth.ok) return jsonResponse(req, { error: auth.error }, auth.status);

    const bodyRaw = await req.json().catch(() => null) as Record<string, unknown> | null;
    if (!bodyRaw || Array.isArray(bodyRaw)) {
      return jsonResponse(req, { error: 'Corps JSON invalide' }, 400);
    }
    if (bodyRaw.warm === true) {
      const adminAuth = await verifyAdminOrServiceRole(req);
      if (!adminAuth.ok) return jsonResponse(req, { error: adminAuth.error }, adminAuth.status);
      return jsonResponse(req, { warm: true });
    }

    const user_id = typeof bodyRaw.user_id === 'string' ? bodyRaw.user_id : '';
    const provider = typeof bodyRaw.provider === 'string' ? bodyRaw.provider.trim() : null;

    if (!/^[0-9a-f]{8}-[0-9a-f-]{27}$/i.test(user_id)) {
      return jsonResponse(req, { error: "user_id UUID requis" }, 400);
    }
    if (provider && !/^[a-z0-9_-]{1,40}$/i.test(provider)) {
      return jsonResponse(req, { error: 'provider invalide' }, 400);
    }

    const supabaseUrl = Deno.env.get("SUPABASE_URL")!;
    const serviceRoleKey = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")!;
    const supabase = createClient(supabaseUrl, serviceRoleKey, { auth: { persistSession: false } });

    if (!auth.isServiceRole) {
      if (auth.userId !== user_id) {
        return jsonResponse(req, { error: 'Non autorise' }, 403);
      }
      if (applyRateLimit('calendar-sync', `${user_id}:${getClientIp(req)}`, { max: 3, windowMs: 60_000 })) {
        return jsonResponse(req, { error: 'Synchronisations trop frequentes' }, 429);
      }
      const { data: allowed, error: rateError } = await supabase.rpc('fn_verifier_rate_limit', {
        p_cle: user_id,
        p_action: 'edge_calendar_sync',
        p_max_tentatives: 20,
        p_fenetre_secondes: 3600,
      });
      if (rateError || allowed !== true) {
        return jsonResponse(req, { error: 'Limite horaire de synchronisation atteinte' }, 429);
      }
    }

    let connectionsQuery = supabase
      .from("calendar_connections")
      .select("*")
      .eq("utilisateur_id", user_id)
      .eq("sync_enabled", true);

    if (provider) {
      connectionsQuery = connectionsQuery.eq("provider", provider);
    }

    const { data: connections, error: connError } = await connectionsQuery;

    if (connError) {
      console.error("Erreur recuperation connexions:", connError);
      return jsonResponse(req, { error: "Erreur recuperation connexions" }, 500);
    }

    const { data: missions, error: missionsError } = await supabase
      .from("missions")
      .select("id, intitule, debut_le, fin_le, service, taux_horaire_base, etablissement_id, description")
      .eq("soignant_assigne_id", user_id)
      .in("statut", ["ASSIGNEE", "EN_COURS"])
      .gte("fin_le", new Date().toISOString())
      .order("debut_le");

    if (missionsError) {
      console.error("Erreur recuperation missions:", missionsError);
      return jsonResponse(req, { error: "Erreur recuperation missions" }, 500);
    }

    const etabIds = [...new Set((missions || []).map((m: any) => m.etablissement_id))];
    const etabMap: Record<string, any> = {};
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

    for (const conn of connections || []) {
      for (const mission of missions || []) {
        const etab = etabMap[mission.etablissement_id];
        const location = etab
          ? [etab.adresse_rue, etab.adresse_code_postal, etab.adresse_ville].filter(Boolean).join(", ")
          : "";

        const { error: upsertError } = await supabase
          .from("calendar_events_sync")
          .upsert(
            {
              connection_id: conn.id,
              mission_id: mission.id,
              sync_direction: "PUSH",
              last_synced_at: null,
            },
            { onConflict: "connection_id,mission_id" }
          );

        if (upsertError) {
          console.error(`Erreur upsert sync pour mission ${mission.id}:`, upsertError);
          continue;
        }

        console.log(
          `[calendar-sync] Would sync mission ${mission.id} ("${mission.intitule}") ` +
          `to ${conn.provider} for user ${user_id}. ` +
          `Start: ${mission.debut_le}, End: ${mission.fin_le}, Location: ${location}`
        );

        syncedCount++;
      }

      await supabase
        .from("calendar_connections")
        .update({ last_sync_at: new Date().toISOString() })
        .eq("id", conn.id);
    }

    if (!connections || connections.length === 0) {
      syncedCount = (missions || []).length;
      console.log(
        `[calendar-sync] No active connections for user ${user_id}. ` +
        `${syncedCount} mission(s) available for sync.`
      );
    }

    return jsonResponse(req, { success: true, synced: syncedCount });
  } catch (err) {
    console.error("calendar-sync error:", err);
    return jsonResponse(req, { error: "Erreur interne du serveur" }, 500);
  }
});
