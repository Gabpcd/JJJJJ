/**
 * sync-chorus-status — STUB (cron horaire, pending PISTE credentials)
 *
 * Quand activé : interroge PISTE pour MAJ les statuts des factures
 * soumises à Chorus Pro. Pour l'instant, log et retourne 200.
 *
 * Déclenché par un cron Supabase (à configurer dans le dashboard) :
 * SELECT net.http_post('https://flripxtsyegjshnhzjkz.supabase.co/functions/v1/sync-chorus-status', ...);
 */

import { createClient } from 'npm:@supabase/supabase-js@2';

Deno.serve(async (req) => {
  if (req.method === 'OPTIONS') return new Response(null, { status: 204 });

  try {
    const supabaseAdmin = createClient(
      Deno.env.get('SUPABASE_URL')!,
      Deno.env.get('SUPABASE_SERVICE_ROLE_KEY')!,
      { auth: { persistSession: false } },
    );

    const pisteClientId = Deno.env.get('PISTE_CLIENT_ID');
    if (!pisteClientId) {
      console.log('[sync-chorus-status] PISTE credentials pending — skipping sync');
      return new Response(JSON.stringify({
        skipped: true,
        reason: 'PISTE credentials not configured',
      }), { status: 200, headers: { 'Content-Type': 'application/json' } });
    }

    // Find submissions that need status check
    const { data: pendingSubmissions } = await supabaseAdmin
      .from('chorus_submissions')
      .select('id, invoice_id, piste_request_id, status')
      .in('status', ['submitted', 'pending'])
      .order('created_at', { ascending: true })
      .limit(50);

    if (!pendingSubmissions || pendingSubmissions.length === 0) {
      console.log('[sync-chorus-status] No pending submissions to check');
      return new Response(JSON.stringify({
        checked: 0,
        message: 'No pending submissions',
      }), { status: 200, headers: { 'Content-Type': 'application/json' } });
    }

    console.log(`[sync-chorus-status] TODO: Check ${pendingSubmissions.length} submissions against PISTE API`);

    // TODO: For each submission with a piste_request_id:
    // 1. Get OAuth2 token
    // 2. Call consulter-historique-facture
    // 3. Update chorus_submissions.status
    // 4. Update factures_honoraires.chorus_submission_status
    // 5. If rejected: store error_code + error_message, alert admin

    return new Response(JSON.stringify({
      checked: 0,
      pending: pendingSubmissions.length,
      message: 'Real PISTE sync not yet implemented — pending activation',
    }), { status: 200, headers: { 'Content-Type': 'application/json' } });

  } catch (err) {
    console.error('sync-chorus-status error:', err);
    return new Response(JSON.stringify({ error: 'Erreur interne' }), { status: 500, headers: { 'Content-Type': 'application/json' } });
  }
});
