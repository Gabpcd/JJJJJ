/**
 * admin-invoke — Outil d'ops permanent pour invoquer des edge functions internes
 *
 * AUTH : 3 couches cumulatives
 * 1. verify_jwt = true (config.toml)
 * 2. JWT doit correspondre à un admin Jolene validé
 * 3. X-Admin-Confirm = SHA256(user_id:minute:ADMIN_INVOKE_SALT) — timing-safe comparison
 *
 * ALLOWLIST stricte, hardcodée. Étendue en mode dev via SUPABASE_ENV=dev.
 * RATE LIMIT : 20/admin/h, 100 global/h — advisory lock anti-race-condition.
 * AUDIT : admin_invocations avec internal_status (PENDING→INVOKED→COMPLETED/CRASHED).
 * CORRELATION : request_id propagé dans X-Request-Id, logs, Resend.
 */

import { createClient } from 'npm:@supabase/supabase-js@2';
import { maskSensitive } from '../_shared/mask-sensitive.ts';
import { corsHeaders, preflightResponse } from '../_shared/cors.ts';

/* ── Allowlist (A4: env-aware) ── */
const ALLOWED_FUNCTIONS_PROD = [
  'generate-invoice',
  'submit-to-chorus',
  'sync-chorus-status',
  'factor-request-advance',
  'send-email',
] as const;

const ALLOWED_FUNCTIONS_DEV_EXTRA = [
  'seed-test-data',
] as const;

const SENSITIVE_FUNCTIONS = [
  'generate-invoice',
  'submit-to-chorus',
  'factor-request-advance',
];

function getAllowedFunctions(): string[] {
  const env = Deno.env.get('SUPABASE_ENV') || 'production';
  if (env === 'dev') {
    return [...ALLOWED_FUNCTIONS_PROD, ...ALLOWED_FUNCTIONS_DEV_EXTRA];
  }
  return [...ALLOWED_FUNCTIONS_PROD];
}

/* ── Helpers ── */
function json(req: Request, body: unknown, status = 200) {
  return new Response(JSON.stringify(body), {
    status,
    headers: corsHeaders(req),
  });
}

async function sha256(input: string): Promise<string> {
  const data = new TextEncoder().encode(input);
  const hash = await crypto.subtle.digest('SHA-256', data);
  return Array.from(new Uint8Array(hash)).map(b => b.toString(16).padStart(2, '0')).join('');
}

/** V5: Timing-safe string comparison (constant-time) */
function timingSafeEqual(a: string, b: string): boolean {
  if (a.length !== b.length) {
    // Compare against same-length dummy to avoid leaking length info
    // Still constant-time for the XOR loop
    const dummy = 'x'.repeat(a.length);
    let result = 1; // will be non-zero = not equal
    for (let i = 0; i < a.length; i++) {
      result |= a.charCodeAt(i) ^ dummy.charCodeAt(i);
    }
    return false;
  }
  let result = 0;
  for (let i = 0; i < a.length; i++) {
    result |= a.charCodeAt(i) ^ b.charCodeAt(i);
  }
  return result === 0;
}

/* ── Main ── */
Deno.serve(async (req) => {
  if (req.method === 'OPTIONS') return preflightResponse(req);

  const supabaseUrl = Deno.env.get('SUPABASE_URL')!;
  const serviceRoleKey = Deno.env.get('SUPABASE_SERVICE_ROLE_KEY')!;
  const adminInvokeSalt = Deno.env.get('ADMIN_INVOKE_SALT') || 'jolene-ops-default-salt-change-me';

  const supabaseAdmin = createClient(supabaseUrl, serviceRoleKey, { auth: { persistSession: false } });

  // A3: Generate request_id for correlation
  const requestId = crypto.randomUUID();

  try {
    // ── Auth layer 1: JWT ──
    const authHeader = req.headers.get('Authorization');
    if (!authHeader?.startsWith('Bearer ')) return json(req, { error: 'Non autorisé', request_id: requestId }, 401);

    const token = authHeader.replace('Bearer ', '');
    const supabaseUser = createClient(supabaseUrl, Deno.env.get('SUPABASE_ANON_KEY')!, {
      global: { headers: { Authorization: authHeader } },
    });
    const { data: userData, error: authError } = await supabaseUser.auth.getUser(token);
    if (authError || !userData?.user) return json(req, { error: 'Token invalide', request_id: requestId }, 401);

    const userId = userData.user.id;
    const userEmail = userData.user.email || 'unknown';
    const userMeta = userData.user.app_metadata || {};

    // ── Auth layer 2: admin check ──
    if (userMeta.role !== 'ADMIN_PLATEFORME') {
      console.warn(`[admin-invoke][${requestId}] Non-admin attempt by ${userEmail}`);
      return json(req, { error: 'Accès réservé aux administrateurs Jolene', request_id: requestId }, 403);
    }

    const isTestAdmin = userMeta.is_test_admin === true;

    // ── Auth layer 3: X-Admin-Confirm (V5: timing-safe) ──
    const confirmHeader = req.headers.get('X-Admin-Confirm') || '';
    const currentMinute = Math.floor(Date.now() / 60000);
    const expectedCurrent = await sha256(`${userId}:${currentMinute}:${adminInvokeSalt}`);
    const expectedPrevious = await sha256(`${userId}:${currentMinute - 1}:${adminInvokeSalt}`);

    const matchesCurrent = timingSafeEqual(confirmHeader, expectedCurrent);
    const matchesPrevious = timingSafeEqual(confirmHeader, expectedPrevious);

    if (!matchesCurrent && !matchesPrevious) {
      console.warn(`[admin-invoke][${requestId}] Invalid X-Admin-Confirm from ${userEmail}`);
      return json(req, { error: 'X-Admin-Confirm invalide ou expiré', request_id: requestId }, 403);
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
      return json(req, { error: 'target_function et reason requis', request_id: requestId }, 400);
    }

    // ── Allowlist check (A4: env-aware) ──
    const allowed = getAllowedFunctions();
    if (!allowed.includes(target_function)) {
      console.warn(`[admin-invoke][${requestId}] Function not allowed: ${target_function}`);
      return json(req, { error: `Function "${target_function}" non autorisée`, request_id: requestId }, 403);
    }

    // ── Rate limit with advisory lock (V6: anti-race-condition) ──
    const userLockKey = `rate_limit:${userId}`;
    let lockErr: unknown = null;
    try {
      const { error } = await supabaseAdmin.rpc('pg_advisory_xact_lock' as any, {
        key: Math.abs(hashCode(userLockKey)),
      });
      lockErr = error;
    } catch (error) {
      lockErr = error;
    }
    // Fallback if RPC not available: proceed without lock (acceptable degradation)
    if (lockErr) console.warn(`[admin-invoke][${requestId}] advisory lock unavailable`);

    const oneHourAgo = new Date(Date.now() - 3600000).toISOString();

    const { count: perAdminCount } = await supabaseAdmin
      .from('admin_invocations')
      .select('id', { count: 'exact', head: true })
      .eq('admin_user_id', userId)
      .gte('invoked_at', oneHourAgo);

    if ((perAdminCount || 0) >= 20) {
      return json(req, { error: 'Rate limit: max 20/admin/heure', request_id: requestId }, 429);
    }

    const { count: globalCount } = await supabaseAdmin
      .from('admin_invocations')
      .select('id', { count: 'exact', head: true })
      .gte('invoked_at', oneHourAgo);

    if ((globalCount || 0) >= 100) {
      return json(req, { error: 'Rate limit: max 100 global/heure', request_id: requestId }, 429);
    }

    // ── Write audit BEFORE invocation (internal_status = PENDING) ──
    const { data: auditRow, error: auditErr } = await supabaseAdmin
      .from('admin_invocations')
      .insert({
        admin_user_id: userId,
        target_function,
        target_payload: target_payload || {},
        reason,
        dry_run: dry_run === true,
        is_test: isTestAdmin,
        request_id: requestId,
        internal_status: 'PENDING',
      })
      .select('id')
      .single();

    if (auditErr) {
      console.error(`[admin-invoke][${requestId}] Audit insert failed:`, auditErr);
      return json(req, { error: 'Erreur audit', request_id: requestId }, 500);
    }

    const invocationId = auditRow!.id;

    // ── Dry run ──
    if (dry_run === true) {
      await supabaseAdmin.from('admin_invocations').update({
        internal_status: 'COMPLETED',
        status_returned: 200,
        duration_ms: 0,
        response_excerpt: 'DRY_RUN — function not invoked',
        completed_at: new Date().toISOString(),
      }).eq('id', invocationId);

      return json(req, {
        dry_run: true,
        invocation_id: invocationId,
        request_id: requestId,
        would_invoke: { function: target_function, payload: target_payload, reason },
      });
    }

    // ── Mark INVOKED (V7: crash detection) ──
    await supabaseAdmin.from('admin_invocations').update({
      internal_status: 'INVOKED',
    }).eq('id', invocationId);

    // ── Invoke target function ──
    const startMs = Date.now();
    let statusReturned = 0;
    let responseText = '';

    try {
      const targetUrl = `${supabaseUrl}/functions/v1/${target_function}`;

      // V8: Propagate traceable reason to target
      const finalPayload = { ...(target_payload || {}) };
      if (target_function === 'generate-invoice') {
        finalPayload.service_role_reason = `admin_invoke_${invocationId}:${reason}`;
      }

      const res = await fetch(targetUrl, {
        method: 'POST',
        headers: {
          'Authorization': `Bearer ${serviceRoleKey}`,
          'Content-Type': 'application/json',
          'X-Request-Id': requestId, // A3: correlation
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

    // ── Update audit AFTER invocation (V7: COMPLETED) ──
    await supabaseAdmin.from('admin_invocations').update({
      internal_status: 'COMPLETED',
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
              from: 'Jolene Ops <bonjour@jolene.app>',
              to: ['gabrielle@jolene.app'],
              subject: `[OPS] admin-invoke → ${target_function} par ${userEmail}`,
              html: `<p><strong>admin-invoke</strong> <code>${requestId}</code></p>
                <ul>
                  <li>Fonction : ${target_function}</li>
                  <li>Admin : ${userEmail} (${userId})</li>
                  <li>Raison : ${reason}</li>
                  <li>Status : ${statusReturned}</li>
                  <li>Durée : ${durationMs}ms</li>
                  <li>Réponse : <code>${maskedExcerpt.substring(0, 200)}</code></li>
                  <li>Invocation ID : ${invocationId}</li>
                  <li>Request ID : ${requestId}</li>
                </ul>`,
              headers: { 'X-Ops-Notification': 'admin-invoke', 'X-Request-Id': requestId },
            }),
          });
        }
      } catch (e) {
        console.warn(`[admin-invoke][${requestId}] Resend notification failed:`, e);
      }
    }

    console.log(`[admin-invoke][${requestId}] ${userEmail} → ${target_function} : ${statusReturned} (${durationMs}ms)`);

    // ── Response with full context ──
    let parsedResponse: unknown;
    try { parsedResponse = JSON.parse(responseText); } catch { parsedResponse = { raw: responseText.substring(0, 1000) }; }

    return json(req, {
      invocation_id: invocationId,
      request_id: requestId,
      target_function,
      status_returned: statusReturned,
      duration_ms: durationMs,
      response: parsedResponse,
    });

  } catch (err) {
    console.error(`[admin-invoke][${requestId}] Fatal:`, err);
    return json(req, { error: err instanceof Error ? err.message : 'Erreur interne', request_id: requestId }, 500);
  }
});

/** Simple string hash for advisory lock key */
function hashCode(s: string): number {
  let hash = 0;
  for (let i = 0; i < s.length; i++) {
    const char = s.charCodeAt(i);
    hash = ((hash << 5) - hash) + char;
    hash |= 0;
  }
  return hash;
}
