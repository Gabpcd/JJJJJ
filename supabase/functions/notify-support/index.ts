/**
 * notify-support — relaie un événement (message de contact, litige, …) vers la
 * boîte support@jolene.app par email (Resend).
 *
 * Appelée en service_role uniquement (depuis une RPC SECURITY DEFINER ou un
 * trigger via net.http_post). Ne dépend pas de send-email (qui résout le
 * destinataire à partir d'un user_id) : ici la cible est une adresse fixe.
 *
 * Body : {
 *   sujet, corps, expediteur_nom?, expediteur_email?, source?, lien?,
 *   compte_id? | expediteur_id? | destinataire_id? | mission_id?,
 *   system_alert?: true // réservé à la liste blanche service_role
 * }
 */
import { createClient } from 'npm:@supabase/supabase-js@2';
import { resolveOperationalTestAccount } from '../_shared/test-account.ts';

function corsHeaders(req: Request) {
  return {
    'Access-Control-Allow-Origin': req.headers.get('origin') || '*',
    'Access-Control-Allow-Headers': 'authorization, x-client-info, apikey, content-type',
    'Content-Type': 'application/json',
  };
}

const SUPPORT_EMAIL = 'support@jolene.app';
const UUID_RE = /^[0-9a-f]{8}-[0-9a-f]{4}-[1-5][0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$/i;
const EMAIL_RE = /^[^@\s]+@[^@\s]+\.[^@\s]+$/;
const SYSTEM_ALERT_SOURCES = new Set([
  'tripwire-paiement',
]);

type Classification =
  | { ok: true; isTest: boolean; accountIds: string[] }
  | { ok: false; error: string };

function suppliedUuid(
  body: Record<string, unknown>,
  key: string,
): { supplied: false } | { supplied: true; value: string | null } {
  if (!(key in body) || body[key] === null || body[key] === '') {
    return { supplied: false };
  }
  const raw = typeof body[key] === 'string' ? body[key].trim() : '';
  return { supplied: true, value: UUID_RE.test(raw) ? raw : null };
}

async function classifyOperationalSource(
  admin: ReturnType<typeof createClient>,
  body: Record<string, unknown>,
  senderEmail?: string,
): Promise<Classification> {
  // Exception fermée et explicitement bornée pour les alertes purement
  // système, sans compte métier (premier euro). Ce chemin n'est atteint
  // qu'après authentification service_role de la fonction.
  if (body.system_alert === true) {
    const source = typeof body.source === 'string' ? body.source.trim() : '';
    if (!SYSTEM_ALERT_SOURCES.has(source)) {
      return { ok: false, error: 'source alerte système non autorisée' };
    }
    return { ok: true, isTest: false, accountIds: [] };
  }

  const accountIds = new Set<string>();

  for (const key of [
    'compte_id',
    'expediteur_id',
    'destinataire_id',
    'soignant_id',
    'etablissement_id',
  ]) {
    const candidate = suppliedUuid(body, key);
    if (!candidate.supplied) continue;
    if (!candidate.value) {
      return { ok: false, error: `identifiant ${key} invalide` };
    }
    accountIds.add(candidate.value);
  }

  const missionId = suppliedUuid(body, 'mission_id');
  if (missionId.supplied) {
    if (!missionId.value) {
      return { ok: false, error: 'identifiant mission_id invalide' };
    }
    const { data: mission, error } = await admin
      .from('missions')
      .select('etablissement_id,soignant_assigne_id')
      .eq('id', missionId.value)
      .maybeSingle();
    if (error || !mission || typeof mission.etablissement_id !== 'string') {
      return { ok: false, error: 'classification mission indisponible' };
    }
    accountIds.add(mission.etablissement_id);
    if (typeof mission.soignant_assigne_id === 'string') {
      accountIds.add(mission.soignant_assigne_id);
    }
  }

  // Les RPC de contact historiques transmettent l'email Auth mais pas toujours
  // l'UUID. La résolution reste serveur-only et échoue fermée si l'adresse
  // n'appartient pas à un compte opérationnel connu.
  if (accountIds.size === 0 && senderEmail && EMAIL_RE.test(senderEmail)) {
    const { data: userId, error } = await admin.rpc(
      'fn_admin_get_user_id_by_email',
      { p_email: senderEmail.toLowerCase() },
    );
    if (error || typeof userId !== 'string' || !UUID_RE.test(userId)) {
      return { ok: false, error: 'classification expéditeur indisponible' };
    }
    accountIds.add(userId);
  }

  if (accountIds.size === 0) {
    return { ok: false, error: 'source opérationnelle non identifiable' };
  }

  let isTest = false;
  for (const accountId of accountIds) {
    const classification = await resolveOperationalTestAccount(admin, accountId);
    if (!classification.ok) {
      return { ok: false, error: classification.error };
    }
    isTest ||= classification.isTest;
  }
  return { ok: true, isTest, accountIds: [...accountIds] };
}

function escapeHtml(s: unknown): string {
  return String(s ?? '')
    .replace(/&/g, '&amp;').replace(/</g, '&lt;').replace(/>/g, '&gt;')
    .replace(/"/g, '&quot;').replace(/'/g, '&#39;');
}

Deno.serve(async (req) => {
  if (req.method === 'OPTIONS') return new Response(null, { status: 204, headers: corsHeaders(req) });
  const headers = corsHeaders(req);

  try {
    // Auth : service_role uniquement (legacy JWT, sb_secret_ env, ou vault).
    const token = (req.headers.get('Authorization') || '').replace('Bearer ', '');
    const serviceRoleKey = Deno.env.get('SUPABASE_SERVICE_ROLE_KEY') || '';
    const secretKey = Deno.env.get('SUPABASE_SECRET_KEY') || '';
    let authorized = token && (token === serviceRoleKey || (!!secretKey && token === secretKey));

    if (!authorized && token) {
      // Fallback vault (le cron envoie le sb_secret_* du vault, cf. _shared/admin-auth)
      try {
        const sb = createClient(Deno.env.get('SUPABASE_URL')!, serviceRoleKey || secretKey);
        const { data } = await sb.rpc('fn_lire_secret_cron');
        if (data && token === data) authorized = true;
      } catch { /* ignore */ }
    }
    if (!authorized) {
      return new Response(JSON.stringify({ error: 'Non autorisé' }), { status: 401, headers });
    }

    const body = await req.json().catch(() => ({})) as Record<string, unknown>;
    const sujet: string = (body.sujet || 'Nouveau message').toString().slice(0, 200);
    const corps: string = (body.corps || '').toString().slice(0, 5000);
    const expediteurNom: string = (body.expediteur_nom || '').toString().slice(0, 120);
    const expediteurEmail: string | undefined = body.expediteur_email?.toString().trim();
    const source: string = (body.source || 'contact').toString();
    const lien: string | undefined = body.lien?.toString();

    const adminKey = serviceRoleKey || secretKey;
    if (!adminKey) {
      return new Response(JSON.stringify({
        error: 'Classification du compte indisponible',
      }), { status: 503, headers });
    }
    const admin = createClient(
      Deno.env.get('SUPABASE_URL')!,
      adminKey,
      { auth: { persistSession: false } },
    );
    const classification = await classifyOperationalSource(
      admin,
      body,
      expediteurEmail,
    );
    if (!classification.ok) {
      console.error('[notify-support] classification refusée', classification.error);
      return new Response(JSON.stringify({
        error: 'Classification du compte indisponible',
      }), { status: 503, headers });
    }
    if (classification.isTest) {
      await Promise.resolve(admin.from('journaux_audit').insert({
        acteur_id: null,
        type_acteur: 'SYSTEME',
        action: 'NOTIFICATION_SKIPPED',
        type_ressource: 'email',
        id_ressource: classification.accountIds[0],
        details: {
          fonction: 'notify-support',
          canal: 'EMAIL',
          raison: 'test_account',
          source,
          comptes_classes: classification.accountIds,
        },
      })).catch(() => {});
      return new Response(JSON.stringify({
        success: true,
        skipped: true,
        reason: 'test_account',
      }), { status: 200, headers });
    }

    const RESEND_API_KEY = Deno.env.get('RESEND_API_KEY');
    if (!RESEND_API_KEY) {
      return new Response(JSON.stringify({ success: true, skipped: true, reason: 'resend_non_configure' }), { status: 200, headers });
    }

    const html = `
<!DOCTYPE html><html><head><meta charset="utf-8"></head>
<body style="margin:0;padding:0;background:#F8FAFC;font-family:'Segoe UI',Arial,sans-serif;">
  <div style="max-width:600px;margin:0 auto;background:white;border-radius:12px;overflow:hidden;">
    <div style="background:#0F172A;padding:22px 24px;display:flex;align-items:center;gap:10px;">
      <img src="https://jolene.app/icon-192x192.png" alt="" width="32" height="32" style="display:block;border-radius:7px;" />
      <span style="color:#E04590;font-size:22px;font-weight:bold;">Jolene — Support</span>
    </div>
    <div style="padding:28px 24px;">
      <p style="color:#64748B;font-size:12px;text-transform:uppercase;letter-spacing:1px;margin:0 0 6px;">${escapeHtml(source)}</p>
      <h2 style="color:#0F172A;margin:0 0 14px;">${escapeHtml(sujet)}</h2>
      <div style="background:#FDF2F8;border-left:4px solid #E04590;padding:16px 18px;border-radius:0 8px 8px 0;color:#334155;white-space:pre-wrap;">${escapeHtml(corps)}</div>
      <p style="color:#475569;font-size:13px;margin-top:18px;">
        ${expediteurNom ? `<strong>De :</strong> ${escapeHtml(expediteurNom)}<br/>` : ''}
        ${expediteurEmail ? `<strong>Email :</strong> <a href="mailto:${escapeHtml(expediteurEmail)}">${escapeHtml(expediteurEmail)}</a><br/>` : ''}
        ${lien ? `<strong>Lien :</strong> <a href="https://jolene.app${escapeHtml(lien)}">https://jolene.app${escapeHtml(lien)}</a>` : ''}
      </p>
    </div>
  </div>
</body></html>`;

    const res = await fetch('https://api.resend.com/emails', {
      method: 'POST',
      headers: { 'Authorization': `Bearer ${RESEND_API_KEY}`, 'Content-Type': 'application/json' },
      body: JSON.stringify({
        from: 'Jolene <bonjour@jolene.app>',
        to: [SUPPORT_EMAIL],
        reply_to: expediteurEmail && EMAIL_RE.test(expediteurEmail) ? expediteurEmail : 'gabrielle@jolene.app',
        subject: `[${source}] ${sujet}`,
        html,
      }),
    });

    if (!res.ok) {
      const t = await res.text();
      console.error('[notify-support] Resend error', res.status, t.slice(0, 300));
      return new Response(JSON.stringify({ error: 'Échec envoi email', status: res.status }), { status: 502, headers });
    }
    return new Response(JSON.stringify({ success: true }), { status: 200, headers });
  } catch (err) {
    console.error('[notify-support]', err);
    return new Response(JSON.stringify({ error: err instanceof Error ? err.message : 'Erreur interne' }), { status: 500, headers });
  }
});
