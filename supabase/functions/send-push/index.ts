import { serve } from "https://deno.land/std@0.168.0/http/server.ts"
import { createClient } from "https://esm.sh/@supabase/supabase-js@2"

function getCorsOrigin(req: Request): string {
  const origin = req.headers.get("origin") || "";
  if (origin.endsWith(".lovable.app")) return origin;
  const allowed = ["https://app.jolene.app", "https://jolene-app.lovable.app", "http://localhost:5173"];
  return allowed.includes(origin) ? origin : allowed[0];
}

const FCM_SERVER_KEY = Deno.env.get("FCM_SERVER_KEY");

serve(async (req) => {
  const corsHeaders = { "Access-Control-Allow-Origin": getCorsOrigin(req), "Content-Type": "application/json" };
  if (req.method === "OPTIONS") {
    return new Response(null, { headers: { ...corsHeaders, "Access-Control-Allow-Headers": "authorization, content-type", "Access-Control-Allow-Methods": "POST" }});
  }
  try {
    const authHeader = req.headers.get("Authorization");
    if (!authHeader?.startsWith("Bearer ")) return new Response(JSON.stringify({ error: "Non autorisé" }), { status: 401, headers: corsHeaders });

    const token = authHeader.replace("Bearer ", "");
    const supabaseUrl = Deno.env.get("SUPABASE_URL")!;
    const supabaseAuth = createClient(supabaseUrl, Deno.env.get("SUPABASE_ANON_KEY")!);
    const { data: { user }, error: authError } = await supabaseAuth.auth.getUser(token);
    if (authError || !user) return new Response(JSON.stringify({ error: "Token invalide" }), { status: 401, headers: corsHeaders });

    const { destinataire_id, titre, corps, lien } = await req.json();
    if (!destinataire_id || !titre) return new Response(JSON.stringify({ error: "destinataire_id et titre requis" }), { status: 400, headers: corsHeaders });

    const supabaseAdmin = createClient(supabaseUrl, Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")!);

    // Récupérer les tokens push du destinataire
    const { data: tokens } = await supabaseAdmin
      .from("tokens_push")
      .select("token")
      .eq("utilisateur_id", destinataire_id);

    if (!tokens || tokens.length === 0) {
      return new Response(JSON.stringify({ sent: false, message: "Aucun token push" }), { headers: corsHeaders });
    }

    if (!FCM_SERVER_KEY) {
      return new Response(JSON.stringify({ sent: false, message: "FCM non configuré" }), { headers: corsHeaders });
    }

    let sent = 0;
    for (const t of tokens) {
      const res = await fetch("https://fcm.googleapis.com/fcm/send", {
        method: "POST",
        headers: {
          "Authorization": `key=${FCM_SERVER_KEY}`,
          "Content-Type": "application/json",
        },
        body: JSON.stringify({
          to: t.token,
          notification: {
            title: titre,
            body: corps || "",
            click_action: lien || "https://app.jolene.app",
            icon: "/favicon.svg",
          },
          data: {
            lien: lien || "/",
          },
        }),
      });
      if (res.ok) sent++;
    }

    return new Response(JSON.stringify({ sent: sent, total: tokens.length }), { headers: corsHeaders });
  } catch {
    return new Response(JSON.stringify({ error: "Erreur interne" }), { status: 500, headers: corsHeaders });
  }
});
