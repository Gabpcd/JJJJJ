import { createClient } from "npm:@supabase/supabase-js@2";
import { corsHeaders } from "../_shared/cors.ts";

function escapeIcal(str: string): string {
  return (str || "").replace(/\\/g, "\\\\").replace(/;/g, "\\;").replace(/,/g, "\\,").replace(/\n/g, "\\n");
}

function formatIcalDate(d: Date): string {
  return d.toISOString().replace(/[-:]/g, "").replace(/\.\d{3}/, "");
}

Deno.serve(async (req) => {
  if (req.method === "OPTIONS") {
    return new Response(null, { headers: corsHeaders(req) });
  }

  const url = new URL(req.url);
  const uid = url.searchParams.get("uid");
  const token = url.searchParams.get("token");

  if (!uid || !token) {
    return new Response("Missing uid or token", { status: 400, headers: corsHeaders(req) });
  }

  // Validate UUID format (defense-in-depth)
  const UUID_REGEX = /^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$/i;
  if (!UUID_REGEX.test(uid)) {
    return new Response("Invalid uid", { status: 400, headers: corsHeaders(req) });
  }

  const supabaseUrl = Deno.env.get("SUPABASE_URL")!;
  const serviceRoleKey = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")!;
  const supabase = createClient(supabaseUrl, serviceRoleKey);

  // Verify token against stored token
  const { data: tokenRow, error: tokenError } = await supabase
    .from("tokens_calendrier")
    .select("token")
    .eq("soignant_id", uid)
    .single();

  if (tokenError || !tokenRow || tokenRow.token !== token) {
    return new Response("Unauthorized", { status: 401, headers: corsHeaders(req) });
  }

  const { data: missions, error } = await supabase
    .from("missions")
    .select("id, intitule, debut_le, fin_le, service, taux_horaire_base, etablissement_id, description")
    .eq("soignant_assigne_id", uid)
    .in("statut", ["ASSIGNEE", "EN_COURS"])
    .order("debut_le");

  if (error) {
    return new Response("Erreur interne", { status: 500, headers: corsHeaders(req) });
  }

  // Fetch establishment info and the exact worked schedule.
  const etabIds = [...new Set((missions || []).map((m: any) => m.etablissement_id))];
  const missionIds = (missions || []).map((m: any) => m.id);
  const etabMap: Record<string, any> = {};
  const creneauxMap: Record<string, any[]> = {};
  const [etabsResult, creneauxResult] = await Promise.all([
    etabIds.length > 0
      ? supabase
        .from("etablissements")
        .select("id, nom, adresse_rue, adresse_ville, adresse_code_postal")
        .in("id", etabIds)
      : Promise.resolve({ data: [], error: null }),
    missionIds.length > 0
      ? supabase
        .from("mission_creneaux")
        .select("id, mission_id, debut, fin, est_pause, type_creneau")
        .in("mission_id", missionIds)
        .eq("type_creneau", "PREVISIONNEL")
        .eq("est_pause", false)
        .not("fin", "is", null)
        .order("debut")
      : Promise.resolve({ data: [], error: null }),
  ]);

  if (etabsResult.error || creneauxResult.error) {
    return new Response("Erreur interne", { status: 500, headers: corsHeaders(req) });
  }
  for (const e of etabsResult.data || []) {
    etabMap[e.id] = e;
  }
  for (const creneau of creneauxResult.data || []) {
    (creneauxMap[creneau.mission_id] ||= []).push(creneau);
  }

  // Build iCal
  const lines: string[] = [
    "BEGIN:VCALENDAR",
    "VERSION:2.0",
    "PRODID:-//Jolene//Missions//FR",
    "CALSCALE:GREGORIAN",
    "METHOD:PUBLISH",
    "X-WR-CALNAME:Jolene - Missions",
    "X-WR-TIMEZONE:Europe/Paris",
  ];

  const maintenant = new Date();
  for (const m of missions || []) {
    const etab = etabMap[m.etablissement_id];
    const lieu = etab ? `${etab.adresse_rue || ""}, ${etab.adresse_code_postal || ""} ${etab.adresse_ville || ""}` : "";
    const desc = [
      etab ? `Établissement: ${etab.nom}` : "",
      m.service ? `Service: ${m.service}` : "",
      `Taux horaire: ${m.taux_horaire_base}€/h`,
    ].filter(Boolean).join("\\n");

    const planifies = creneauxMap[m.id] || [];
    const dureeGlobale = new Date(m.fin_le).getTime() - new Date(m.debut_le).getTime();
    // Compatibilité avec les anciennes missions ponctuelles seulement. Une
    // mission longue sans planning détaillé ne devient jamais un événement
    // continu de plusieurs semaines.
    const evenements = planifies.length > 0
      ? planifies
      : dureeGlobale > 0 && dureeGlobale <= 24 * 60 * 60_000
        ? [{ id: "ponctuelle", debut: m.debut_le, fin: m.fin_le }]
        : [];

    for (const [index, creneau] of evenements.entries()) {
      lines.push("BEGIN:VEVENT");
      lines.push(`UID:${m.id}-${creneau.id || index}@jolene`);
      lines.push(`DTSTART:${formatIcalDate(new Date(creneau.debut))}`);
      lines.push(`DTEND:${formatIcalDate(new Date(creneau.fin))}`);
      lines.push(`SUMMARY:${escapeIcal(m.intitule)}`);
      lines.push(`LOCATION:${escapeIcal(lieu.trim())}`);
      lines.push(`DESCRIPTION:${desc}`);
      lines.push(`DTSTAMP:${formatIcalDate(maintenant)}`);
      lines.push("END:VEVENT");
    }
  }

  lines.push("END:VCALENDAR");

  return new Response(lines.join("\r\n"), {
    headers: {
      ...corsHeaders(req),
      "Content-Type": "text/calendar; charset=utf-8",
      "Content-Disposition": 'attachment; filename="missions.ics"',
      "Cache-Control": "no-cache, no-store, must-revalidate",
    },
  });
});
