import { readFileSync } from 'node:fs';
import { webcrypto } from 'node:crypto';
import { runInNewContext } from 'node:vm';
import ts from 'typescript';
import { describe, expect, it } from 'vitest';

// Exécute le handler réel, avec uniquement Auth, SQL et transport fictifs en mémoire.
// Le canari représente un code inventé ; aucun secret, appel réseau ou compte réel.
const CANARY = '638291';
const USER = 'f1540000-0000-4000-8000-000000000002';
const SID = 'SM' + 'a'.repeat(32);
type Options = {
  type?: string;
  failure?: 'provider400' | 'provider500' | 'network' | 'json' | 'finalization' | 'audit' | 'reservation';
  testAccount?: boolean;
  testSource?: boolean;
  smsPreference?: boolean;
  serviceRole?: boolean;
};

async function exercise(options: Options = {}, sourceOverride?: string) {
  const state = {
    requests: [] as { url: string; body: Record<string, string> }[],
    audits: [] as Record<string, unknown>[],
    finalizations: [] as Record<string, unknown>[],
    logs: [] as string[],
    injected: [] as string[],
  };
  const fail = (name: string): never => { throw new Error(`Unexpected mock I/O: ${name}`); };
  const sb = {
    from(table: string) {
      if (table === 'preferences_notifications') {
        const query = {
          select: () => query,
          eq: () => query,
          maybeSingle: async () => ({ data: { canal_sms: options.smsPreference !== false }, error: null }),
        };
        return query;
      }
      if (table === 'sms_envoyes') return {
        insert: async (row: Record<string, unknown>) => {
          state.audits.push(row);
          if (options.failure === 'audit') state.injected.push('audit');
          return { error: options.failure === 'audit' ? { message: `audit ${CANARY}` } : null };
        },
      };
      if (table === 'journaux_audit') return { insert: async () => ({ error: null }) };
      return fail(`table ${table}`);
    },
    async rpc(name: string, args: Record<string, unknown>) {
      if (name === 'fn_reserver_envoi_sms_idempotent') {
        if (options.failure === 'reservation') { state.injected.push('reservation'); throw new Error(`reservation ${CANARY}`); }
        return { data: { statut: 'RESERVE' }, error: null };
      }
      if (name === 'fn_finaliser_envoi_sms_idempotent') {
        state.finalizations.push(args);
        if (options.failure === 'finalization') state.injected.push('finalization');
        return { error: options.failure === 'finalization' ? { message: `finalization ${CANARY}` } : null };
      }
      return fail(`rpc ${name}`);
    },
  };
  let handler: (request: Request) => Promise<Response> = () => fail('missing handler');
  const log = (...args: unknown[]) => state.logs.push(args.map(value => {
    if (value && typeof value === 'object') {
      const v = value as { message?: unknown; stack?: unknown };
      return [String(value), v.message, v.stack, JSON.stringify(value)].join('|');
    }
    return String(value);
  }).join(' '));
  const modules: Record<string, unknown> = {
    'npm:@supabase/supabase-js@2.99.2': { createClient: () => sb },
    '../_shared/rate-limit.ts': { applyRateLimit: async () => true, getClientIp: () => '192.0.2.1' },
    '../_shared/cors.ts': {
      corsHeaders: {},
      jsonResponse: (_req: Request, body: unknown, status = 200) => new Response(JSON.stringify(body), { status }),
      preflightResponse: () => new Response(null, { status: 204 }),
    },
    '../_shared/admin-auth.ts': {
      verifyUserOrServiceRole: async () => ({ ok: true, isServiceRole: options.serviceRole !== false, userId: USER, role: 'ADMIN_PLATEFORME' }),
      verifyAdminOrServiceRole: async () => ({ ok: true, userId: USER }),
    },
    '../_shared/test-account.ts': {
      resolveOperationalTestAccount: async () => ({ ok: true, isTest: !!options.testAccount }),
      resolveOperationalTestSource: async () => ({ ok: true, isTest: !!options.testSource }),
    },
  };
  const source = sourceOverride ?? readFileSync('supabase/functions/send-sms/index.ts', 'utf8');
  const code = ts.transpileModule(source, { compilerOptions: { target: ts.ScriptTarget.ES2022, module: ts.ModuleKind.CommonJS } }).outputText;
  runInNewContext(code, {
    exports: {}, require: (name: string) => modules[name] ?? fail(`import ${name}`),
    Deno: {
      env: { get: (name: string) => ({ SUPABASE_URL: 'https://example.invalid', SUPABASE_SERVICE_ROLE_KEY: 'fixture-only', SUPABASE_ANON_KEY: 'fixture-anon-only',
        TWILIO_ACCOUNT_SID: 'AC_fixture', TWILIO_AUTH_TOKEN: 'fixture-only', TWILIO_FROM_NUMBER: '+33123456789' } as Record<string, string>)[name] },
      serve: (fn: typeof handler) => { handler = fn; },
    },
    console: { error: log, warn: log, info: log, log },
    Request, Response, URLSearchParams, TextEncoder, crypto: webcrypto, btoa, Error,
    fetch: async (url: string, init: RequestInit) => {
      state.requests.push({ url, body: Object.fromEntries(new URLSearchParams(String(init.body))) });
      if (['network', 'json', 'provider400', 'provider500'].includes(options.failure ?? '')) state.injected.push(options.failure!);
      if (options.failure === 'network') throw new Error(`transport ${CANARY}`);
      if (options.failure === 'json') return { ok: true, status: 200, json: async () => { throw new Error(`invalid JSON ${CANARY}`); } };
      const status = options.failure === 'provider400' ? 400 : options.failure === 'provider500' ? 500 : 201;
      return new Response(JSON.stringify({ sid: SID, message: `provider echo ${CANARY}`, body: CANARY }), { status });
    },
  });
  const response = await handler(new Request('https://example.invalid/functions/v1/send-sms', {
    method: 'POST', headers: { Authorization: 'Bearer fixture-only', 'Content-Type': 'application/json' },
    body: JSON.stringify({ type: options.type ?? 'OTP_SIGNATURE', telephone: '+33612345678',
      contenu: `Votre code est ${CANARY}`, destinataire_id: USER, idempotency_key: 'fixture.sms.redaction' }),
  }));
  return { ...state, status: response.status, body: await response.json() };
}

describe('send-sms — aucun code OTP dans les sorties hors transport', () => {
  for (const type of ['OTP_VERIFICATION_TELEPHONE', 'OTP_SIGNATURE']) {
    it(`${type} : transporte le code exact et masque uniquement l’audit`, async () => {
      const r = await exercise({ type });
      expect(r.status).toBe(200);
      expect(r.body).toEqual({ success: true, sid: SID, to: '+33612345678' });
      expect(r.requests).toHaveLength(1);
      expect(r.requests[0].body).toEqual({ To: '+33612345678', From: '+33123456789', Body: `Jolene: Votre code est ${CANARY}` });
      expect(r.audits).toHaveLength(1);
      expect(r.audits[0].contenu).toBe('Jolene: [CODE OTP MASQUÉ]');
      expect(r.finalizations[0]).toMatchObject({ p_statut: 'ENVOYE', p_provider_id: SID, p_erreur: null });
      expect(JSON.stringify({ audits: r.audits, finalizations: r.finalizations, body: r.body, logs: r.logs })).not.toContain(CANARY);
    });

    for (const failure of ['provider400', 'provider500', 'network', 'json', 'finalization', 'audit', 'reservation'] as const) {
      it(`${type} : ${failure} ne recopie aucun diagnostic contenant le code`, async () => {
        const r = await exercise({ type, failure });
        expect(r.injected).toEqual([failure]);
        expect(r.status).toBe(failure === 'audit' ? 200 : failure === 'provider400' ? 502 : failure === 'reservation' ? 500 : 503);
        expect(r.requests).toHaveLength(failure === 'reservation' ? 0 : 1);
        expect(JSON.stringify({ audits: r.audits, finalizations: r.finalizations, body: r.body, logs: r.logs })).not.toContain(CANARY);
        if (['provider500', 'network', 'json'].includes(failure)) expect(r.finalizations[0]).toMatchObject({ p_statut: 'INDETERMINE' });
        if (failure === 'provider400') expect(r.finalizations[0]).toMatchObject({ p_statut: 'ERREUR' });
      });
    }
  }

  it('le SMS ordinaire garde son contenu envoyé et journalisé', async () => {
    const r = await exercise({ type: 'CUSTOM' });
    expect(r.status).toBe(200);
    expect(r.audits[0].contenu).toBe(`Jolene: Votre code est ${CANARY}`);
    expect(r.requests[0].body.Body).toBe(r.audits[0].contenu);
  });

  for (const gate of ['testAccount', 'testSource'] as const) {
    it(`${gate} reste exclu même pour un OTP`, async () => {
      const r = await exercise({ [gate]: true });
      expect(r.body).toMatchObject({ success: true, skipped: true, reason: gate === 'testAccount' ? 'test_account' : 'test_source' });
      expect(r.requests).toHaveLength(0);
      expect(r.audits).toHaveLength(0);
    });
  }

  it('préférences et droits navigateur restent identiques', async () => {
    const signature = await exercise({ smsPreference: false });
    expect(signature.body).toMatchObject({ skipped: true, reason: 'preference_user_off' });
    expect(signature.requests).toHaveLength(0);
    const telephone = await exercise({ type: 'OTP_VERIFICATION_TELEPHONE', smsPreference: false });
    expect(telephone.status).toBe(200);
    expect(telephone.requests).toHaveLength(1);
    const navigateur = await exercise({ serviceRole: false });
    expect(navigateur.status).toBe(403);
    expect(navigateur.requests).toHaveLength(0);
  });

  it('témoin négatif : le défaut historique réintroduit expose le canari', async () => {
    const source = readFileSync('supabase/functions/send-sms/index.ts', 'utf8');
    const previous = source.replace('const contenuJournal = otpTransactionnel', "const contenuJournal = type === 'OTP_VERIFICATION_TELEPHONE'");
    expect(previous).not.toBe(source);
    const r = await exercise({ type: 'OTP_SIGNATURE' }, previous);
    expect(r.audits[0].contenu).toContain(CANARY);
  });
});
