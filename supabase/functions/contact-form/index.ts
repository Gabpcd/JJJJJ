// Formulaire de contact public → email vers support@jolene.app via Resend.
// FROM bonjour@jolene.app (domaine vérifié) · reply_to = email du visiteur, pour
// que Gabrielle réponde directement depuis la boîte support. Public (verify_jwt
// désactivé) avec honeypot anti-bot + validation + bornage longueur.

function getCorsOrigin(req: Request): string {
  const o = req.headers.get("origin") || "";
  if (["https://jolene.app", "https://app.jolene.app", "https://www.jolene.app", "http://localhost:5173", "http://localhost:8080"].includes(o)) return o;
  return "https://jolene.app";
}
function cors(req: Request) {
  return { "Access-Control-Allow-Origin": getCorsOrigin(req), "Access-Control-Allow-Headers": "authorization, x-client-info, apikey, content-type", "Content-Type": "application/json" };
}
const esc = (s: string) => String(s).replace(/&/g, "&amp;").replace(/</g, "&lt;").replace(/>/g, "&gt;");

Deno.serve(async (req) => {
  if (req.method === "OPTIONS") return new Response(null, { headers: cors(req) });
  if (req.method !== "POST") return new Response(JSON.stringify({ error: "Méthode non autorisée" }), { status: 405, headers: cors(req) });
  try {
    const { nom, email, sujet, message, hp } = await req.json().catch(() => ({}));

    // Honeypot : un bot remplit le champ caché → on fait semblant d'accepter.
    if (hp) return new Response(JSON.stringify({ success: true }), { headers: cors(req) });

    const nomT = String(nom || "").trim().slice(0, 120);
    const emailT = String(email || "").trim().slice(0, 160);
    const sujetT = String(sujet || "").trim().slice(0, 160) || "Message via le formulaire de contact";
    const messageT = String(message || "").trim().slice(0, 4000);

    if (!nomT || !/^[^@\s]+@[^@\s]+\.[^@\s]+$/.test(emailT) || messageT.length < 5) {
      return new Response(JSON.stringify({ error: "Merci de renseigner votre nom, un email valide et un message." }), { status: 400, headers: cors(req) });
    }

    const RESEND = Deno.env.get("RESEND_API_KEY");
    if (!RESEND) return new Response(JSON.stringify({ error: "Service email indisponible." }), { status: 500, headers: cors(req) });

    const r = await fetch("https://api.resend.com/emails", {
      method: "POST",
      headers: { "Authorization": `Bearer ${RESEND}`, "Content-Type": "application/json" },
      body: JSON.stringify({
        from: "Formulaire Jolene <bonjour@jolene.app>",
        to: ["support@jolene.app"],
        reply_to: emailT,
        subject: `[Contact] ${sujetT}`,
        html: `<div style="font-family:-apple-system,Segoe UI,Helvetica,Arial,sans-serif;font-size:14px;line-height:1.6;color:#1E293B">
          <p><strong>De :</strong> ${esc(nomT)} &lt;${esc(emailT)}&gt;</p>
          <p><strong>Sujet :</strong> ${esc(sujetT)}</p>
          <hr style="border:none;border-top:1px solid #eee"/>
          <p style="white-space:pre-wrap">${esc(messageT)}</p>
        </div>`,
      }),
    });
    if (!r.ok) {
      const detail = await r.text().catch(() => "");
      return new Response(JSON.stringify({ error: "Envoi impossible, réessayez plus tard.", detail: detail.slice(0, 200) }), { status: 502, headers: cors(req) });
    }
    return new Response(JSON.stringify({ success: true }), { headers: cors(req) });
  } catch (e) {
    return new Response(JSON.stringify({ error: (e as Error)?.message || "Erreur interne" }), { status: 500, headers: cors(req) });
  }
});
