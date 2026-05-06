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
// Mode dev : si TURNSTILE_SECRET_KEY n'est pas configurée dans les secrets
// Supabase, on retourne success=true. Cela permet au code d'être déployé
// avant que Gabrielle ait créé les clés Cloudflare. Une fois la secret
// `TURNSTILE_SECRET_KEY` ajoutée au dashboard Supabase, la vérification
// devient bloquante automatiquement.

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
): Promise<TurnstileResult> {
  const secretKey = Deno.env.get('TURNSTILE_SECRET_KEY');

  if (!secretKey) {
    console.warn('[Turnstile] TURNSTILE_SECRET_KEY non configurée — vérification désactivée (mode dev).');
    return { success: true };
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
      return { success: true, hostname: data.hostname, challenge_ts: data.challenge_ts };
    }
    console.warn('[Turnstile] Verification refusée', data['error-codes']);
    return { success: false, error: 'Vérification anti-bot échouée. Rafraîchissez la page.' };
  } catch (err) {
    console.error('[Turnstile] Exception', err);
    return { success: false, error: 'Vérification anti-bot indisponible. Réessayez.' };
  }
}
