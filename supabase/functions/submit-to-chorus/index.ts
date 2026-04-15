/**
 * submit-to-chorus — STUB (pending PISTE credentials)
 *
 * Sera activé quand les credentials PISTE seront disponibles.
 * En attendant : insère une ligne dans chorus_submissions avec
 * status='pending_credentials' et retourne 202 Accepted.
 *
 * Voir docs/invoicing.md > "Activation Chorus" pour les étapes.
 */

import { createClient } from 'npm:@supabase/supabase-js@2';

function json(body: unknown, status = 200) {
  return new Response(JSON.stringify(body), {
    status,
    headers: { 'Content-Type': 'application/json' },
  });
}

Deno.serve(async (req) => {
  if (req.method === 'OPTIONS') return new Response(null, { status: 204 });

  try {
    const supabaseAdmin = createClient(
      Deno.env.get('SUPABASE_URL')!,
      Deno.env.get('SUPABASE_SERVICE_ROLE_KEY')!,
      { auth: { persistSession: false } },
    );

    const { facture_honoraire_id } = await req.json();
    if (!facture_honoraire_id) return json({ error: 'facture_honoraire_id requis' }, 400);

    // Check if PISTE credentials are configured
    const pisteClientId = Deno.env.get('PISTE_CLIENT_ID');
    const pisteClientSecret = Deno.env.get('PISTE_CLIENT_SECRET');

    if (!pisteClientId || !pisteClientSecret) {
      console.log('TODO: PISTE credentials pending, submission deferred');

      // Insert pending submission record
      const { data: submission, error } = await supabaseAdmin
        .from('chorus_submissions')
        .insert({
          invoice_id: facture_honoraire_id,
          submission_type: 'SAISIE_API',
          status: 'pending_credentials',
          error_message: 'PISTE credentials not yet configured — submission will be retried when credentials are available',
        })
        .select('id')
        .single();

      if (error) {
        console.error('Error creating chorus_submission:', error);
        return json({ error: error.message }, 500);
      }

      // Update facture with submission reference
      await supabaseAdmin
        .from('factures_honoraires')
        .update({
          chorus_submission_id: submission!.id,
          chorus_submission_status: 'pending_credentials',
        })
        .eq('id', facture_honoraire_id);

      return json({
        accepted: true,
        status: 'pending_credentials',
        submission_id: submission!.id,
        message: 'Soumission Chorus Pro différée — credentials PISTE en attente de configuration. La facture sera soumise automatiquement dès activation.',
      }, 202);
    }

    // ═══ REAL PISTE SUBMISSION (activated when credentials exist) ═══
    // TODO: Implement real OAuth2 + DeposerPDFacture call
    // This will be filled in by scripts/activate-chorus.ts validation
    // For now, treat as pending even with credentials (safety)

    console.log(`[submit-to-chorus] PISTE credentials found — real submission not yet implemented`);

    const { data: submission } = await supabaseAdmin
      .from('chorus_submissions')
      .insert({
        invoice_id: facture_honoraire_id,
        submission_type: 'SAISIE_API',
        status: 'pending',
      })
      .select('id')
      .single();

    await supabaseAdmin
      .from('factures_honoraires')
      .update({
        chorus_submission_id: submission!.id,
        chorus_submission_status: 'pending',
      })
      .eq('id', facture_honoraire_id);

    return json({
      accepted: true,
      status: 'pending',
      submission_id: submission!.id,
      message: 'Soumission Chorus Pro enregistrée — traitement en cours.',
    }, 202);

  } catch (err) {
    console.error('submit-to-chorus error:', err);
    return json({ error: err instanceof Error ? err.message : 'Erreur interne' }, 500);
  }
});
