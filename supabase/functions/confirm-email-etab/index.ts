// confirm-email-etab — Endpoint public de validation du lien e-mail professionnel.
// L'utilisateur clique sur le lien dans son e-mail pro (https://jolene.app/confirm-email-etab?token=xxx),
// le front redirige vers cette edge function. En succès, redirige vers /etablissement/verification-email-ok.

import { createClient } from 'npm:@supabase/supabase-js@2';

const APP_URL = Deno.env.get('APP_URL') || 'https://jolene.app';

Deno.serve(async (req) => {
  const url = new URL(req.url);

  if (req.method === 'OPTIONS') {
    return new Response(null, {
      headers: {
        'Access-Control-Allow-Origin': '*',
        'Access-Control-Allow-Methods': 'GET, OPTIONS',
        'Access-Control-Allow-Headers': 'content-type',
      },
    });
  }

  const token = url.searchParams.get('token');
  if (!token || token.length < 32) {
    return redirect(`${APP_URL}/etablissement/verification-email-erreur?reason=token_invalide`);
  }

  try {
    const supabaseUrl = Deno.env.get('SUPABASE_URL')!;
    const serviceKey = Deno.env.get('SUPABASE_SERVICE_ROLE_KEY')!;
    const admin = createClient(supabaseUrl, serviceKey, { auth: { persistSession: false } });

    const { data, error } = await admin.rpc('fn_confirmer_email_etab', { p_token: token });

    if (error) {
      return redirect(`${APP_URL}/etablissement/verification-email-erreur?reason=erreur_serveur`);
    }

    const result = data as { success: boolean; error?: string; etablissement_id?: string };

    if (!result?.success) {
      const reason = result?.error?.includes('expiré') ? 'token_expire' : 'token_invalide';
      return redirect(`${APP_URL}/etablissement/verification-email-erreur?reason=${reason}`);
    }

    return redirect(`${APP_URL}/etablissement/verification-email-ok`);
  } catch {
    return redirect(`${APP_URL}/etablissement/verification-email-erreur?reason=erreur_serveur`);
  }
});

function redirect(location: string): Response {
  return new Response(null, {
    status: 302,
    headers: { Location: location },
  });
}
