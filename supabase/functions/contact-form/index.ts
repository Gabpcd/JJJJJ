// Formulaire de contact public protege par Turnstile + quotas anti-spam.

import { createClient } from 'npm:@supabase/supabase-js@2.99.2';
import { jsonResponse, preflightResponse } from '../_shared/cors.ts';
import { applyRateLimit, getClientIp } from '../_shared/rate-limit.ts';
import { verifyTurnstileToken } from '../_shared/verify-turnstile.ts';

const esc = (value: string) => value
  .replace(/&/g, '&amp;')
  .replace(/</g, '&lt;')
  .replace(/>/g, '&gt;')
  .replace(/"/g, '&quot;')
  .replace(/'/g, '&#039;');

async function fingerprint(value: string): Promise<string> {
  const digest = await crypto.subtle.digest('SHA-256', new TextEncoder().encode(value));
  return [...new Uint8Array(digest)].slice(0, 16)
    .map((octet) => octet.toString(16).padStart(2, '0')).join('');
}

Deno.serve(async (req) => {
  if (req.method === 'OPTIONS') return preflightResponse(req);
  if (req.method !== 'POST') return jsonResponse(req, { error: 'Methode non autorisee' }, 405);

  try {
    const contentLength = Number(req.headers.get('content-length') || '0');
    if (Number.isFinite(contentLength) && contentLength > 16_384) {
      return jsonResponse(req, { error: 'Message trop volumineux' }, 413);
    }

    const ip = getClientIp(req);
    if (applyRateLimit('contact-form', ip, { max: 3, windowMs: 60 * 60_000 })) {
      return jsonResponse(req, { error: 'Trop de messages. Reessayez plus tard.' }, 429);
    }

    const body = await req.json().catch(() => null) as Record<string, unknown> | null;
    if (!body || Array.isArray(body)) return jsonResponse(req, { error: 'Corps JSON invalide' }, 400);

    // Honeypot : reponse neutre, mais sans appel fournisseur payant.
    if (body.hp) return jsonResponse(req, { success: true });

    const captcha = await verifyTurnstileToken(
      typeof body.turnstileToken === 'string' ? body.turnstileToken : null,
      ip,
      req.headers.get('origin'),
    );
    if (!captcha.success) return jsonResponse(req, { error: captcha.error }, 403);

    const nom = String(body.nom || '').trim().slice(0, 120);
    const email = String(body.email || '').trim().toLowerCase().slice(0, 160);
    const sujet = String(body.sujet || '').replace(/[\r\n]+/g, ' ').trim().slice(0, 160)
      || 'Message via le formulaire de contact';
    const message = String(body.message || '').trim().slice(0, 4000);

    if (nom.length < 2 || !/^[^@\s]+@[^@\s]+\.[^@\s]+$/.test(email) || message.length < 5) {
      return jsonResponse(req, { error: 'Nom, email valide et message requis.' }, 400);
    }

    const emailFingerprint = await fingerprint(email);
    if (applyRateLimit('contact-form-email', emailFingerprint, { max: 3, windowMs: 24 * 60 * 60_000 })) {
      return jsonResponse(req, { error: 'Quota quotidien atteint pour cette adresse.' }, 429);
    }

    // Le quota memoire absorbe les rafales. Le quota PostgreSQL reste fiable
    // entre plusieurs instances Edge et ne stocke jamais l'adresse/IP en clair.
    const supabaseUrl = Deno.env.get('SUPABASE_URL') || '';
    const serviceRoleKey = Deno.env.get('SUPABASE_SERVICE_ROLE_KEY') || '';
    if (!supabaseUrl || !serviceRoleKey) {
      return jsonResponse(req, { error: 'Service indisponible.' }, 503);
    }
    const admin = createClient(supabaseUrl, serviceRoleKey, { auth: { persistSession: false } });
    const checks = [admin.rpc('fn_verifier_rate_limit', {
      p_cle: emailFingerprint,
      p_action: 'edge_contact_email',
      p_max_tentatives: 3,
      p_fenetre_secondes: 86400,
    })];
    if (ip !== 'unknown') {
      checks.push(admin.rpc('fn_verifier_rate_limit', {
        p_cle: await fingerprint(ip),
        p_action: 'edge_contact_ip',
        p_max_tentatives: 10,
        p_fenetre_secondes: 86400,
      }));
    }
    const rateChecks = await Promise.all(checks);
    if (rateChecks.some(({ error }) => error)) {
      console.error('[contact-form] quota distribue indisponible');
      return jsonResponse(req, { error: 'Service temporairement indisponible.' }, 503);
    }
    if (rateChecks.some(({ data }) => data !== true)) {
      return jsonResponse(req, { error: 'Quota quotidien atteint.' }, 429);
    }

    const resendKey = Deno.env.get('RESEND_API_KEY');
    if (!resendKey) return jsonResponse(req, { error: 'Service email indisponible.' }, 503);

    const response = await fetch('https://api.resend.com/emails', {
      method: 'POST',
      headers: { Authorization: `Bearer ${resendKey}`, 'Content-Type': 'application/json' },
      body: JSON.stringify({
        from: 'Formulaire Jolene <bonjour@jolene.app>',
        to: ['support@jolene.app'],
        reply_to: email,
        subject: `[Contact] ${sujet}`,
        html: `<div style="font-family:-apple-system,Segoe UI,Helvetica,Arial,sans-serif;font-size:14px;line-height:1.6;color:#1E293B">
          <p><strong>De :</strong> ${esc(nom)} &lt;${esc(email)}&gt;</p>
          <p><strong>Sujet :</strong> ${esc(sujet)}</p>
          <hr style="border:none;border-top:1px solid #eee"/>
          <p style="white-space:pre-wrap">${esc(message)}</p>
        </div>`,
      }),
    });
    if (!response.ok) {
      console.error('[contact-form] Resend HTTP', response.status);
      return jsonResponse(req, { error: 'Envoi impossible, reessayez plus tard.' }, 502);
    }
    return jsonResponse(req, { success: true });
  } catch (error) {
    console.error('[contact-form] erreur', error);
    return jsonResponse(req, { error: 'Erreur interne' }, 500);
  }
});
