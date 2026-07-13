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

  // Fetch establishment info
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

  for (const m of missions || []) {
    const etab = etabMap[m.etablissement_id];
    const lieu = etab ? `${etab.adresse_rue || ""}, ${etab.adresse_code_postal || ""} ${etab.adresse_ville || ""}` : "";
    const desc = [
      etab ? `Établissement: ${etab.nom}` : "",
      m.service ? `Service: ${m.service}` : "",
      `Taux horaire: ${m.taux_horaire_base}€/h`,
    ].filter(Boolean).join("\\n");

    lines.push("BEGIN:VEVENT");
    lines.push(`UID:${m.id}@jolene`);
    lines.push(`DTSTART:${formatIcalDate(new Date(m.debut_le))}`);
    lines.push(`DTEND:${formatIcalDate(new Date(m.fin_le))}`);
    lines.push(`SUMMARY:${escapeIcal(m.intitule)}`);
    lines.push(`LOCATION:${escapeIcal(lieu.trim())}`);
    lines.push(`DESCRIPTION:${desc}`);
    lines.push(`DTSTAMP:${formatIcalDate(new Date())}`);
    lines.push("END:VEVENT");
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
