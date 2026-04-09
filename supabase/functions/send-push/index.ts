// send-push — Web Push natif (RFC 8030 + VAPID)
// Pas besoin de Firebase ni de clé de service Google.
// Utilise la VAPID key déjà configurée (FIREBASE_VAPID_KEY = clé publique VAPID)
// + une clé privée VAPID (VAPID_PRIVATE_KEY) à générer une seule fois.
//
// Secrets requis :
//   VAPID_PUBLIC_KEY  (= ta FIREBASE_VAPID_KEY existante, encodée en base64url)
//   VAPID_PRIVATE_KEY (à générer, voir ci-dessous)
//   VAPID_SUBJECT     (= mailto:contact@jolene.app)

import { serve } from "https://deno.land/std@0.168.0/http/server.ts";
import { createClient } from "https://esm.sh/@supabase/supabase-js@2";
import webpush from "npm:web-push@3.6.7";

function getCorsOrigin(req: Request): string {
  const origin = req.headers.get("origin") || "";
  if (
    origin === "https://app.jolene.app" ||
    origin === "https://jolene.app" ||
    origin === "http://localhost:5173" ||
    origin.endsWith(".lovable.app") ||
    origin.endsWith(".lovableproject.com")
  ) {
    return origin;
  }
  return "https://app.jolene.app";
}

serve(async (req) => {
  const corsHeaders = {
    "Access-Control-Allow-Origin": getCorsOrigin(req),
    "Content-Type": "application/json",
    "Access-Control-Allow-Headers": "authorization, x-client-info, apikey, content-type, x-supabase-client-platform, x-supabase-client-platform-version, x-supabase-client-runtime, x-supabase-client-runtime-version",
    "Access-Control-Allow-Methods": "POST",
  };
  if (req.method === "OPTIONS") {
    return new Response(null, { headers: corsHeaders });
  }

  try {
    const authHeader = req.headers.get("Authorization");
    if (!authHeader?.startsWith("Bearer ")) {
      return new Response(JSON.stringify({ error: "Non autorisé" }), { status: 401, headers: corsHeaders });
    }

    const supabaseUrl = Deno.env.get("SUPABASE_URL")!;
    const supabaseAuth = createClient(supabaseUrl, Deno.env.get("SUPABASE_ANON_KEY")!);
    const { data: { user }, error: authError } = await supabaseAuth.auth.getUser(authHeader.replace("Bearer ", ""));
    if (authError || !user) {
      return new Response(JSON.stringify({ error: "Token invalide" }), { status: 401, headers: corsHeaders });
    }

    const { destinataire_id, titre, corps, lien } = await req.json();
    if (!destinataire_id || !titre) {
      return new Response(JSON.stringify({ error: "destinataire_id et titre requis" }), { status: 400, headers: corsHeaders });
    }

    const supabaseAdmin = createClient(supabaseUrl, Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")!);

    // Récupérer les tokens push (subscriptions Web Push) du destinataire
    const { data: tokens } = await supabaseAdmin
      .from("tokens_push")
      .select("token, endpoint, p256dh, auth_key")
      .eq("utilisateur_id", destinataire_id);

    let sent = 0;
    const totalTokens = tokens?.length || 0;

    // Configuration VAPID
    const vapidPublicKey = Deno.env.get("VAPID_PUBLIC_KEY");
    const vapidPrivateKey = Deno.env.get("VAPID_PRIVATE_KEY");
    const vapidSubject = Deno.env.get("VAPID_SUBJECT") || "mailto:contact@jolene.app";

    if (totalTokens > 0 && vapidPublicKey && vapidPrivateKey) {
      webpush.setVapidDetails(vapidSubject, vapidPublicKey, vapidPrivateKey);

      const payload = JSON.stringify({
        title: titre,
        body: corps || "",
        icon: "/favicon.svg",
        badge: "/icon-192x192.png",
        data: { url: lien || "https://jolene.app" },
      });

      const expiredTokenIds: string[] = [];

      for (const t of tokens!) {
        try {
          // Essai Web Push standard (endpoint + p256dh + auth)
          if (t.endpoint && t.p256dh && t.auth_key) {
            await webpush.sendNotification(
              {
                endpoint: t.endpoint,
                keys: { p256dh: t.p256dh, auth: t.auth_key },
              },
              payload,
              { TTL: 86400 } // 24h
            );
            sent++;
          }
          // Fallback FCM legacy si c'est un token FCM sans endpoint
          else if (t.token) {
            const fcmKey = Deno.env.get("FCM_SERVER_KEY");
            if (fcmKey) {
              const res = await fetch("https://fcm.googleapis.com/fcm/send", {
                method: "POST",
                headers: { "Authorization": `key=${fcmKey}`, "Content-Type": "application/json" },
                body: JSON.stringify({
                  to: t.token,
                  notification: { title: titre, body: corps || "", click_action: lien || "https://jolene.app", icon: "/favicon.svg" },
                  data: { lien: lien || "/" },
                }),
              });
              if (res.ok) sent++;
            }
          }
        } catch (err: unknown) {
          // Si le push échoue avec 404 ou 410, le token est expiré — le supprimer
          if (err instanceof Error && (err.message.includes("404") || err.message.includes("410") || err.message.includes("expired"))) {
            expiredTokenIds.push(t.token || t.endpoint || "");
          }
        }
      }

      // Nettoyer les tokens expirés
      if (expiredTokenIds.length > 0) {
        for (const tokenId of expiredTokenIds) {
          await supabaseAdmin.from("tokens_push")
            .delete()
            .eq("utilisateur_id", destinataire_id)
            .or(`token.eq.${tokenId},endpoint.eq.${tokenId}`);
        }
      }
    }

    // Fallback : envoyer un email si aucun push n'a été livré
    if (sent === 0) {
      try {
        const serviceRoleKey = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")!;
        await fetch(`${supabaseUrl}/functions/v1/send-email`, {
          method: "POST",
          headers: { "Content-Type": "application/json", "Authorization": `Bearer ${serviceRoleKey}` },
          body: JSON.stringify({
            type: "NOTIFICATION_PUSH_FALLBACK",
            destinataire_id,
            data: { titre, corps: corps || "", lien: lien || "https://jolene.app" },
          }),
        });
      } catch { /* email fallback failed silently */ }
    }

    return new Response(
      JSON.stringify({ sent, total: totalTokens, email_fallback: sent === 0 }),
      { headers: corsHeaders }
    );
  } catch (err) {
    console.error("send-push error:", err);
    return new Response(JSON.stringify({ error: "Erreur interne" }), { status: 500, headers: corsHeaders });
  }
});
