import { describe, expect, it } from 'vitest';
import { readFileSync } from 'node:fs';
import { resolve } from 'node:path';

const read = (path: string) => readFileSync(resolve(process.cwd(), path), 'utf8');

describe('P0 Edge security guards', () => {
  it('never trusts a decoded service_role payload', () => {
    const source = read('supabase/functions/_shared/admin-auth.ts');
    expect(source).not.toMatch(/payload\?\.role\s*===\s*['"]service_role/);
    expect(source).not.toContain('atob(padded)');
    expect(source).toContain('auth.getUser(bearer)');
    expect(source).toContain('auth.getClaims(bearer)');
    expect(source).toContain("auth.aal !== 'aal2'");
    expect(source).toContain('expiresAt: Date.now() + 5 * 60_000');
    expect(source).toContain('if (deletedAt)');
  });

  it('protects SMS, push and calendar endpoints', () => {
    const sms = read('supabase/functions/send-sms/index.ts');
    const push = read('supabase/functions/send-push/index.ts');
    const calendar = read('supabase/functions/calendar-sync/index.ts');
    for (const source of [sms, push, calendar]) {
      expect(source).toContain('verifyUserOrServiceRole(req)');
      expect(source).toContain('fn_verifier_rate_limit');
    }
    expect(sms).toContain('Destinataire non autorise');
    expect(sms).toContain('Destinataire hors du pool autorise');
    expect(push).toContain('Destinataire hors du pool autorise');
    expect(push).toContain('safeScalarData(dataPayload)');
    expect(push).toContain('canonicalNotificationType(type_evenement)');
    expect(push).toContain("raw.includes('URGENCE')");
    expect(push).toContain(".select('canal_push')");
    expect(push).toContain('else if (plat === "IOS")');
    expect(push).toContain('else if (plat === "ANDROID")');
    expect(push).not.toContain('plat === "IOS" || plat === "ANDROID"');
    expect(push).not.toContain('iOS en fallback');
    expect(push).toContain('isAllowedWebPushEndpoint(t.endpoint)');
    expect(push).toContain("host.endsWith('.push.apple.com')");
    expect(push).toContain("host.endsWith('.notify.windows.com')");
    expect(push).toContain('PUSH_TOKENS_UNAVAILABLE');
    expect(push).toContain('PUSH_TOKEN_CLEANUP_UNAVAILABLE');
    expect(push).not.toContain('lien || "/"');
    expect(push).not.toContain('url: lien || "https://jolene.app"');
    expect(calendar).toContain("auth.userId !== user_id");
  });

  it('reserves one immutable account family before either registration', () => {
    const soignant = read('supabase/functions/register-soignant/index.ts');
    const etablissement = read('supabase/functions/register-etablissement/index.ts');
    const migration = read('supabase/migrations/20260712230000_p0_securite_auth_rls.sql');
    for (const source of [soignant, etablissement]) {
      expect(source).toContain("'fn_reserver_type_compte'");
      expect(source).toContain('p_claim_token: claimToken');
      expect(source).toContain("'fn_finaliser_type_compte'");
      expect(source).toContain('if (!suppressionAuthAutorisee || inscriptionFinalisee) return');
    }
    expect(migration).toContain('CREATE TABLE IF NOT EXISTS public.types_comptes_auth');
    expect(migration).toContain('pg_advisory_xact_lock');
    expect(migration).toContain("'ACCOUNT_TYPE_MISMATCH'");
    expect(migration).toContain("'ACCOUNT_REGISTRATION_IN_PROGRESS'");
    expect(migration).toContain('claim_token = p_claim_token');
    expect(migration).toContain('REVOKE ALL PRIVILEGES ON TABLE public.types_comptes_auth FROM PUBLIC, anon, authenticated');
    expect(migration).toContain('trg_protect_famille_compte_membre_etablissement');
    expect(migration).toContain("v_type IS DISTINCT FROM 'ETABLISSEMENT'");
    expect(migration).toContain('updates[.]push[.]services[.]mozilla[.]com');
    expect(migration).not.toContain("v_endpoint !~ '^https://'");
  });

  it('resolves the admin account before MFA without weakening aal2 privileges', () => {
    const roleFix = read('supabase/migrations/20260713165730_corriger_resolution_role_admin_avant_mfa.sql');
    const p0 = read('supabase/migrations/20260712230000_p0_securite_auth_rls.sql');
    const protectedRoute = read('src/components/RouteProtegee.tsx');

    expect(roleFix).toContain("u.raw_app_meta_data ->> 'role' = 'ADMIN_PLATEFORME'");
    expect(roleFix).toContain('u.email_confirmed_at IS NOT NULL');
    expect(roleFix).toContain('ea.actif IS NOT TRUE');
    expect(roleFix).not.toContain('IF public.est_admin() THEN');
    expect(p0).toContain("COALESCE(auth.jwt() ->> 'aal', '') = 'aal2'");
    expect(protectedRoute).toContain('<AdminMfaGate>{children}</AdminMfaGate>');
  });

  it('preserves the Lot 21 protected candidature transitions and ACLs', () => {
    const lot21 = read('supabase/migrations/20260712163000_lot21_finaliser_cascade_profession_mission.sql');
    const p0 = read('supabase/migrations/20260712230000_p0_securite_auth_rls.sql');
    expect(lot21).toContain("'jolene.candidature_rpc_mission_id'");
    expect(lot21).toContain('GRANT EXECUTE ON FUNCTION public.fn_repondre_proposition(uuid, boolean) TO authenticated, service_role');
    expect(p0).toContain("current_setting('jolene.candidature_rpc_mission_id', true)");
    expect(p0).not.toMatch(/REVOKE[^;]*fn_repondre_proposition/);
    expect(p0).not.toMatch(/CREATE OR REPLACE FUNCTION public\.fn_protect_candidature_statut/);
  });

  it('logs out only the current push installation', () => {
    const auth = read('src/contexts/AuthContext.tsx');
    const device = read('src/lib/pushDeviceToken.ts');
    const migration = read('supabase/migrations/20260712230000_p0_securite_auth_rls.sql');
    expect(auth).toContain('desactiverPushAppareilCourant');
    expect(auth).not.toContain("supabase.rpc('fn_supprimer_mes_tokens_push'");
    expect(device).toContain("'fn_desactiver_mon_token_push'");
    expect(device).toContain('if (token)');
    expect(device).toContain('PushNotifications.unregister()');
    expect(migration).toContain('CREATE OR REPLACE FUNCTION public.fn_desactiver_mon_token_push');
    expect(migration).toContain('WHERE utilisateur_id = v_uid');
    expect(migration).toContain("'scope', 'CURRENT_DEVICE'");
    expect(migration).toContain('REVOKE ALL ON FUNCTION public.fn_supprimer_mes_tokens_push() FROM authenticated');
  });

  it('keeps Pro Sante Connect callable from native shells', () => {
    const authorize = read('supabase/functions/psc-authorize/index.ts');
    const logout = read('supabase/functions/psc-logout/index.ts');
    const diagnostic = read('supabase/functions/psc-test-connexion/index.ts');
    for (const source of [authorize, logout, diagnostic]) {
      expect(source).toContain('../_shared/cors.ts');
      expect(source).not.toContain('const allowed = [');
    }
    expect(authorize).toContain("p_action: 'edge_psc_authorize'");
    expect(authorize).toContain("applyRateLimit('psc-authorize'");
    expect(logout).toContain('verifyUserOrServiceRole(req)');
  });

  it('returns NON_DEMANDE without touching Stripe when no onboarding exists', () => {
    const source = read('supabase/functions/stripe-connect-status/index.ts');
    expect(source).toContain('../_shared/cors.ts');
    expect(source).toContain('verifyUserOrServiceRole(req)');
    expect(source).toContain("onboarding.statut === 'NON_DEMANDE'");
    expect(source.indexOf("return jsonResponse(req, NON_DEMANDE)")).toBeLessThan(
      source.indexOf('new Stripe(stripeSecretKey'),
    );
    expect(source).toContain('onboardingError');
  });

  it('deletes the Auth account after business anonymisation', () => {
    const source = read('supabase/functions/delete-account/index.ts');
    expect(source).toContain('soignantError || etablissementError || membershipError');
    expect(source).toContain("error_code: 'ACCOUNT_PROFILE_CONFLICT'");
    expect(source).toContain("error_code: 'DERNIER_PROPRIETAIRE'");
    expect(source).toContain("error_code: 'DERNIER_PROPRIETAIRE_GROUPE'");
    expect(source).toContain(".from('admins_groupe_sante')");
    expect(source).toContain("admin.auth.admin.signOut(bearer, 'global')");
    expect(source).toContain('admin.auth.admin.deleteUser(auth.userId, true)');
    expect(source).toContain("role: 'DELETED'");
  });

  it('keeps one push token owner and makes anti-fraud decisions actionable', () => {
    const migration = read('supabase/migrations/20260712230000_p0_securite_auth_rls.sql');
    expect(migration).toContain('ADD CONSTRAINT tokens_push_token_key UNIQUE (token)');
    expect(migration).toContain('ON CONFLICT (token) DO UPDATE SET');
    expect(migration).toContain('utilisateur_id = EXCLUDED.utilisateur_id');
    expect(migration).toContain('trg_mirror_teleportation_alerte_systeme');
    expect(migration).toContain('SUSPENSION_REVIEW_CREATED');
    expect(migration).toContain("'automatic_suspension', false");
  });

  it('requires API key and secret and checks every read permission', () => {
    const source = read('supabase/functions/api-v1/index.ts');
    expect(source).toContain("req.headers.get('x-api-key')");
    expect(source).toContain("req.headers.get('x-api-secret')");
    expect(source).toContain("'missions:read'");
    expect(source).toContain("'presences:read'");
    expect(source).toContain("'factures:read'");
    expect(source).toContain('constantTimeEqual');
  });

  it('fails Turnstile closed except explicit HTTP localhost development', () => {
    const helper = read('supabase/functions/_shared/verify-turnstile.ts');
    const contact = read('supabase/functions/contact-form/index.ts');
    expect(helper).toContain('TURNSTILE_ALLOW_DEV_BYPASS');
    expect(helper).toContain('/^http:\\/\\/(localhost|127\\.0\\.0\\.1)');
    expect(helper).toContain('Protection anti-bot indisponible');
    expect(contact).toContain('verifyTurnstileToken(');
    expect(contact).toContain("applyRateLimit('contact-form'");
    expect(contact).toContain("p_action: 'edge_contact_email'");
    expect(contact).toContain("p_action: 'edge_contact_ip'");
  });

  it('rate-limits public RPPS lookup without consuming the sign-up captcha', () => {
    const verify = read('supabase/functions/verify-rpps/index.ts');
    const finess = read('supabase/functions/verify-finess/index.ts');
    const siret = read('supabase/functions/verify-siret/index.ts');
    const register = read('supabase/functions/register-soignant/index.ts');
    expect(verify).toContain("p_action: 'edge_verify_rpps'");
    expect(verify).toContain("applyRateLimit('verify-rpps'");
    expect(verify).not.toContain('verifyTurnstileToken(');
    expect(verify).toContain("Deno.env.get('ALLOW_DEMO_IDENTIFIERS') === 'true'");
    expect(register).toContain("user.email?.toLowerCase().endsWith('@jolene-demo.dev')");
    expect(register).toContain("Deno.env.get('ALLOW_DEMO_IDENTIFIERS') === 'true'");
    expect(finess).toContain("p_action: 'edge_verify_finess'");
    expect(siret).toContain("p_action: 'edge_verify_siret'");
    for (const source of [verify, finess, siret]) {
      expect(source).toContain('../_shared/cors.ts');
      expect(source).toContain('fn_verifier_rate_limit');
    }
  });

  it('fails notification preference checks closed on every channel', () => {
    const email = read('supabase/functions/send-email/index.ts');
    const sms = read('supabase/functions/send-sms/index.ts');
    const push = read('supabase/functions/send-push/index.ts');
    expect(email).toContain('ALWAYS_SEND_TRANSACTIONAL_TYPES');
    expect(email).toContain('verifyAdminOrServiceRole(req)');
    expect(email).toContain(".select('canal_email')");
    expect(email).toContain("status: 503");
    expect(sms).toContain(".select('canal_sms')");
    expect(push).toContain(".select('canal_push')");
    for (const source of [email, sms, push]) {
      expect(source).toContain('Verification des preferences indisponible');
    }
  });
});
