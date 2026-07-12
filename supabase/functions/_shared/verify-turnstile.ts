// Helper partagé pour la vérification d'un token Cloudflare Turnstile.
//
// Utilisation typique dans une edge function :
//
//   import { verifyTurnstileToken } from "../_shared/verify-turnstile.ts";
//   const turnstile = await verifyTurnstileToken(body.turnstileToken, clientIp);
//   if (!turnstile.success) {
//     return new Response(JSON.stringify({ error: turnstile.error }),
//       { status: 403, headers: { 'Content-Type': 'application/json' } });
//   }
//
// Mode dev explicite uniquement : le bypass exige a la fois
// TURNSTILE_ALLOW_DEV_BYPASS=true ET une origine HTTP localhost. Une coquille
// native Capacitor utilise https://localhost et ne beneficie jamais du bypass.

const VERIFY_URL = 'https://challenges.cloudflare.com/turnstile/v0/siteverify';

export interface TurnstileResult {
  success: boolean;
  error?: string;
  hostname?: string;
  challenge_ts?: string;
}

export async function verifyTurnstileToken(
  token: string | undefined | null,
  remoteIp?: string,
  requestOrigin?: string | null,
): Promise<TurnstileResult> {
  const secretKey = Deno.env.get('TURNSTILE_SECRET_KEY');

  if (!secretKey) {
    const devBypass = Deno.env.get('TURNSTILE_ALLOW_DEV_BYPASS') === 'true';
    const localOrigin = /^http:\/\/(localhost|127\.0\.0\.1)(:\d+)?$/i.test(requestOrigin || '');
    if (devBypass && localOrigin) {
      console.warn('[Turnstile] bypass local explicite actif');
      return { success: true, hostname: 'localhost' };
    }
    console.error('[Turnstile] secret absent hors bypass local explicite');
    return { success: false, error: 'Protection anti-bot indisponible. Reessayez plus tard.' };
  }

  if (!token) {
    return { success: false, error: 'Captcha manquant. Veuillez confirmer que vous n\'êtes pas un robot.' };
  }

  const formData = new FormData();
  formData.append('secret', secretKey);
  formData.append('response', token);
  if (remoteIp && remoteIp !== 'unknown') formData.append('remoteip', remoteIp);

  try {
    const response = await fetch(VERIFY_URL, { method: 'POST', body: formData });
    if (!response.ok) {
      console.error('[Turnstile] HTTP error', response.status);
      return { success: false, error: 'Vérification anti-bot indisponible. Réessayez.' };
    }
    const data = await response.json();
    if (data.success === true) {
      const allowedHostnames = (Deno.env.get('TURNSTILE_ALLOWED_HOSTNAMES') || 'jolene.app,www.jolene.app,localhost')
        .split(',').map((value) => value.trim().toLowerCase()).filter(Boolean);
      const hostname = String(data.hostname || '').toLowerCase();
      if (!hostname || !allowedHostnames.includes(hostname)) {
        console.warn('[Turnstile] hostname refuse', hostname);
        return { success: false, error: 'Verification anti-bot invalide.' };
      }
      return { success: true, hostname: data.hostname, challenge_ts: data.challenge_ts };
    }
    console.warn('[Turnstile] Verification refusée', data['error-codes']);
    return { success: false, error: 'Vérification anti-bot échouée. Rafraîchissez la page.' };
  } catch (err) {
    console.error('[Turnstile] Exception', err);
    return { success: false, error: 'Vérification anti-bot indisponible. Réessayez.' };
  }
}
