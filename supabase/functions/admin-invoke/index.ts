/**
 * admin-invoke — Outil d'ops permanent pour invoquer des edge functions internes
 *
 * AUTH : 3 couches cumulatives
 * 1. verify_jwt = true (config.toml)
 * 2. JWT doit correspondre à un admin Jolene (est_admin_valide())
 * 3. Header X-Admin-Confirm = SHA256(user_id + ":" + minute_window + ":" + ADMIN_INVOKE_SALT)
 *
 * ALLOWLIST stricte, hardcodée, pas configurable depuis la base.
 * RATE LIMIT : 20/admin/h, 100 global/h (query DB).
 * AUDIT : chaque appel écrit dans admin_invocations (avant + après).
 * NOTIFICATION : email Resend sur fonctions sensibles (sauf dry_run).
 */

import { createClient } from 'npm:@supabase/supabase-js@2';
import { maskSensitive } from '../_shared/mask-sensitive.ts';

/* ── Allowlist ── */
const ALLOWED_FUNCTIONS = [
  'generate-invoice',
  'submit-to-chorus',
  'sync-chorus-status',
  'factor-request-advance',
  'send-email',
] as const;

const SENSITIVE_FUNCTIONS = [
  'generate-invoice',
  'submit-to-chorus',
  'factor-request-advance',
];

/* ── Helpers ── */
function json(body: unknown, status = 200) {
  return new Response(JSON.stringify(body), {
    status,
    headers: { 'Content-Type': 'application/json' },
  });
}

async function sha256(input: string): Promise<string> {
  const data = new TextEncoder().encode(input);
  const hash = await crypto.subtle.digest('SHA-256', data);
  return Array.from(new Uint8Array(hash)).map(b => b.toString(16).padStart(2, '0')).join('');
}

/* ── Main ── */
Deno.serve(async (req) => {
  if (req.method === 'OPTIONS') return new Response(null, { status: 204 });

  const supabaseUrl = Deno.env.get('SUPABASE_URL')!;
  const serviceRoleKey = Deno.env.get('SUPABASE_SERVICE_ROLE_KEY')!;
  const adminInvokeSalt = Deno.env.get('ADMIN_INVOKE_SALT') || 'jolene-ops-default-salt-change-me';

  const supabaseAdmin = createClient(supabaseUrl, serviceRoleKey, { auth: { persistSession: false } });

  try {
    // ── Auth layer 1: JWT (enforced by verify_jwt=true in config.toml) ──
    const authHeader = req.headers.get('Authorization');
    if (!authHeader?.startsWith('Bearer ')) return json({ error: 'Non autorisé' }, 401);

    const token = authHeader.replace('Bearer ', '');
    const supabaseUser = createClient(supabaseUrl, Deno.env.get('SUPABASE_ANON_KEY')!, {
      global: { headers: { Authorization: authHeader } },
    });
    const { data: userData, error: authError } = await supabaseUser.auth.getUser(token);
    if (authError || !userData?.user) return json({ error: 'Token invalide' }, 401);

    const userId = userData.user.id;
    const userEmail = userData.user.email || 'unknown';

    // ── Auth layer 2: admin check ──
    const { data: isAdmin } = await supabaseAdmin.rpc('est_admin_valide');
    // est_admin_valide() uses auth.uid() which is set by the JWT context,
    // but since we're calling from service_role, we need to check directly
    const { data: adminCheck } = await supabaseAdmin
      .from('auth.users' as any)
      .select('raw_app_meta_data')
      .eq('id', userId)
      .single()
      .catch(() => ({ data: null }));

    // Direct check since service_role bypasses RLS
    const userMeta = userData.user.app_metadata || {};
    if (userMeta.role !== 'ADMIN_PLATEFORME') {
      console.warn(`[admin-invoke] Non-admin attempt by ${userEmail} (${userId})`);
      return json({ error: 'Accès réservé aux administrateurs Jolene' }, 403);
    }

    const isTestAdmin = userMeta.is_test_admin === true;

    // ── Auth layer 3: X-Admin-Confirm header ──
    const confirmHeader = req.headers.get('X-Admin-Confirm') || '';
    const currentMinute = Math.floor(Date.now() / 60000);
    const expectedHashCurrent = await sha256(`${userId}:${currentMinute}:${adminInvokeSalt}`);
    const expectedHashPrevious = await sha256(`${userId}:${currentMinute - 1}:${adminInvokeSalt}`);

    if (confirmHeader !== expectedHashCurrent && confirmHeader !== expectedHashPrevious) {
      console.warn(`[admin-invoke] Invalid X-Admin-Confirm from ${userEmail}`);
      return json({ error: 'X-Admin-Confirm invalide ou expiré (validité 1-2 min)' }, 403);
    }

    // ── Parse body ──
    const body = await req.json();
    const { target_function, target_payload, reason, dry_run } = body as {
      target_function: string;
      target_payload: Record<string, unknown>;
      reason: string;
      dry_run?: boolean;
    };

    if (!target_function || !reason) {
      return json({ error: 'target_function et reason requis' }, 400);
    }

    // ── Allowlist check ──
    if (!ALLOWED_FUNCTIONS.includes(target_function as any)) {
      console.warn(`[admin-invoke] Function not allowed: ${target_function} by ${userEmail}`);
      return json({ error: `Function "${target_function}" non autorisée. Allowlist: ${ALLOWED_FUNCTIONS.join(', ')}` }, 403);
    }

    // ── Rate limit (query DB) ──
    const oneHourAgo = new Date(Date.now() - 3600000).toISOString();

    const { count: perAdminCount } = await supabaseAdmin
      .from('admin_invocations')
      .select('id', { count: 'exact', head: true })
      .eq('admin_user_id', userId)
      .gte('invoked_at', oneHourAgo);

    if ((perAdminCount || 0) >= 20) {
      return json({ error: 'Rate limit: max 20 invocations par admin par heure' }, 429);
    }

    const { count: globalCount } = await supabaseAdmin
      .from('admin_invocations')
      .select('id', { count: 'exact', head: true })
      .gte('invoked_at', oneHourAgo);

    if ((globalCount || 0) >= 100) {
      return json({ error: 'Rate limit: max 100 invocations globales par heure' }, 429);
    }

    // ── Write audit BEFORE invocation ──
    const { data: auditRow, error: auditErr } = await supabaseAdmin
      .from('admin_invocations')
      .insert({
        admin_user_id: userId,
        target_function,
        target_payload: target_payload || {},
        reason,
        dry_run: dry_run === true,
        is_test: isTestAdmin,
      })
      .select('id')
      .single();

    if (auditErr) {
      console.error('[admin-invoke] Audit insert failed:', auditErr);
      return json({ error: 'Erreur audit' }, 500);
    }

    const invocationId = auditRow!.id;

    // ── Dry run ──
    if (dry_run === true) {
      await supabaseAdmin.from('admin_invocations').update({
        status_returned: 200,
        duration_ms: 0,
        response_excerpt: 'DRY_RUN — function not invoked',
        completed_at: new Date().toISOString(),
      }).eq('id', invocationId);

      return json({
        dry_run: true,
        invocation_id: invocationId,
        would_invoke: {
          function: target_function,
          payload: target_payload,
          reason,
        },
      });
    }

    // ── Invoke target function ──
    const startMs = Date.now();
    let statusReturned = 0;
    let responseText = '';

    try {
      const targetUrl = `${supabaseUrl}/functions/v1/${target_function}`;

      // For generate-invoice, inject service_role_reason
      let finalPayload = target_payload || {};
      if (target_function === 'generate-invoice') {
        finalPayload = { ...finalPayload, service_role_reason: `admin_replay_${userId}` };
      }

      const res = await fetch(targetUrl, {
        method: 'POST',
        headers: {
          'Authorization': `Bearer ${serviceRoleKey}`,
          'Content-Type': 'application/json',
        },
        body: JSON.stringify(finalPayload),
      });

      statusReturned = res.status;
      responseText = await res.text();
    } catch (err) {
      statusReturned = 500;
      responseText = `Fetch error: ${err instanceof Error ? err.message : String(err)}`;
    }

    const durationMs = Date.now() - startMs;
    const maskedExcerpt = maskSensitive(responseText, 500);

    // ── Update audit AFTER invocation ──
    await supabaseAdmin.from('admin_invocations').update({
      status_returned: statusReturned,
      duration_ms: durationMs,
      response_excerpt: maskedExcerpt,
      completed_at: new Date().toISOString(),
    }).eq('id', invocationId);

    // ── Notification Resend on sensitive functions (not dry_run) ──
    if (SENSITIVE_FUNCTIONS.includes(target_function)) {
      try {
        const RESEND_API_KEY = Deno.env.get('RESEND_API_KEY');
        if (RESEND_API_KEY) {
          await fetch('https://api.resend.com/emails', {
            method: 'POST',
            headers: {
              'Authorization': `Bearer ${RESEND_API_KEY}`,
              'Content-Type': 'application/json',
            },
            body: JSON.stringify({
              from: 'Jolene Ops <noreply@jolene.app>',
              to: ['gabrielle@jolene.app'],
              subject: `[OPS] admin-invoke → ${target_function} par ${userEmail}`,
              html: `<p><strong>admin-invoke</strong></p>
                <ul>
                  <li>Fonction : ${target_function}</li>
                  <li>Admin : ${userEmail} (${userId})</li>
                  <li>Raison : ${reason}</li>
                  <li>Status : ${statusReturned}</li>
                  <li>Durée : ${durationMs}ms</li>
                  <li>Réponse : <code>${maskedExcerpt.substring(0, 200)}</code></li>
                  <li>ID invocation : ${invocationId}</li>
                </ul>`,
              headers: { 'X-Ops-Notification': 'admin-invoke' },
            }),
          });
        }
      } catch (e) {
        console.warn('[admin-invoke] Notification Resend failed:', e);
      }
    }

    console.log(`[admin-invoke] ${userEmail} → ${target_function} : ${statusReturned} (${durationMs}ms)`);

    // ── Parse response for client ──
    let parsedResponse: unknown;
    try { parsedResponse = JSON.parse(responseText); } catch { parsedResponse = { raw: responseText.substring(0, 1000) }; }

    return json({
      invocation_id: invocationId,
      target_function,
      status_returned: statusReturned,
      duration_ms: durationMs,
      response: parsedResponse,
    });

  } catch (err) {
    console.error('[admin-invoke] Fatal:', err);
    return json({ error: err instanceof Error ? err.message : 'Erreur interne' }, 500);
  }
});
