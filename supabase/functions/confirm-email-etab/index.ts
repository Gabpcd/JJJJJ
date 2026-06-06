// confirm-email-etab — Endpoint public de validation du lien e-mail professionnel.
// Le lien dans l'e-mail pro pointe DIRECTEMENT sur cette edge function (verify_jwt=false) :
//   https://<project>.supabase.co/functions/v1/confirm-email-etab?token=xxx
// La fonction valide le token et redirige (302) vers une page PUBLIQUE du SPA
// (l'utilisateur peut cliquer depuis son e-mail sans être connecté).

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

  const PAGE = `${APP_URL}/verification-email-etab`;

  const token = url.searchParams.get('token');
  if (!token || token.length < 32) {
    return redirect(`${PAGE}?statut=invalide`);
  }

  try {
    const supabaseUrl = Deno.env.get('SUPABASE_URL')!;
    const serviceKey = Deno.env.get('SUPABASE_SERVICE_ROLE_KEY')!;
    const admin = createClient(supabaseUrl, serviceKey, { auth: { persistSession: false } });

    const { data, error } = await admin.rpc('fn_confirmer_email_etab', { p_token: token });

    if (error) {
      return redirect(`${PAGE}?statut=erreur`);
    }

    const result = data as { success: boolean; error?: string; etablissement_id?: string };

    if (!result?.success) {
      const statut = result?.error?.includes('expiré') ? 'expire' : 'invalide';
      return redirect(`${PAGE}?statut=${statut}`);
    }

    return redirect(`${PAGE}?statut=ok`);
  } catch {
    return redirect(`${PAGE}?statut=erreur`);
  }
});

function redirect(location: string): Response {
  return new Response(null, {
    status: 302,
    headers: { Location: location },
  });
}
