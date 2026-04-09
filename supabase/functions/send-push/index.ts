import { serve } from "https://deno.land/std@0.168.0/http/server.ts"
import { createClient } from "https://esm.sh/@supabase/supabase-js@2"

function getCorsOrigin(req: Request): string {
  const origin = req.headers.get("origin") || "";
  if (
    origin === "https://app.jolene.app" ||
    origin === "https://jolene.app" ||
    origin === "http://localhost:5173" ||
    origin === "http://localhost:8080"
  ) {
    return origin;
  }
  return "https://app.jolene.app";
}

const FCM_SERVER_KEY = Deno.env.get("FCM_SERVER_KEY");

serve(async (req) => {
  const corsHeaders = { "Access-Control-Allow-Origin": getCorsOrigin(req), "Content-Type": "application/json" };
  if (req.method === "OPTIONS") {
    return new Response(null, { headers: { ...corsHeaders, "Access-Control-Allow-Headers": "authorization, x-client-info, apikey, content-type, x-supabase-client-platform, x-supabase-client-platform-version, x-supabase-client-runtime, x-supabase-client-runtime-version", "Access-Control-Allow-Methods": "POST" }});
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

    let sent = 0;
    const totalTokens = tokens?.length || 0;

    // Try push notifications if tokens and FCM are available
    if (totalTokens > 0 && FCM_SERVER_KEY) {
      for (const t of tokens!) {
        try {
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
              data: { lien: lien || "/" },
            }),
          });
          if (res.ok) sent++;
        } catch { /* individual push failure, continue */ }
      }
    }

    // Fallback: send email if no push was delivered
    if (sent === 0) {
      try {
        const serviceRoleKey = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")!;
        await fetch(`${supabaseUrl}/functions/v1/send-email`, {
          method: "POST",
          headers: { "Content-Type": "application/json", "Authorization": `Bearer ${serviceRoleKey}` },
          body: JSON.stringify({
            type: "NOTIFICATION_PUSH_FALLBACK",
            destinataire_id: destinataire_id,
            data: { titre, corps: corps || "", lien: lien || "https://app.jolene.app" },
          }),
        });
      } catch { /* email fallback failed silently */ }
    }

    return new Response(JSON.stringify({ sent, total: totalTokens, email_fallback: sent === 0 }), { headers: corsHeaders });
  } catch {
    return new Response(JSON.stringify({ error: "Erreur interne" }), { status: 500, headers: corsHeaders });
  }
});
