import { existsSync, readFileSync } from 'node:fs';
import { join } from 'node:path';
import { describe, expect, it } from 'vitest';

const root = process.cwd();
const read = (path: string) => readFileSync(join(root, path), 'utf8');

const migrationPath = 'supabase/migrations/20260729121419_requalifier_donnees_prelaunch_et_supprimer_mfa_admin.sql';
const migration = read(migrationPath);
const route = read('src/components/RouteProtegee.tsx');
const edgeAuth = read('supabase/functions/_shared/admin-auth.ts');
const config = read('supabase/config.toml');
const sendEmail = read('supabase/functions/send-email/index.ts');
const sendPush = read('supabase/functions/send-push/index.ts');
const sendSms = read('supabase/functions/send-sms/index.ts');
const emailCron = read('supabase/functions/email-cron/index.ts');
const testAccount = read('supabase/functions/_shared/test-account.ts');
const avisParrainage = read('supabase/functions/avis-parrainage/index.ts');
const digestHebdo = read('supabase/functions/digest-hebdo/index.ts');
const relanceInactifs = read('supabase/functions/relance-inactifs/index.ts');
const notifySupport = read('supabase/functions/notify-support/index.ts');
const contactForm = read('supabase/functions/contact-form/index.ts');
const edgeLaunchInventory = read(
  'supabase/functions/EDGE_FUNCTIONS_LAUNCH_INVENTORY.md',
);
const deployProd = read('.github/workflows/deploy-supabase.yml');
const deployStaging = read('.github/workflows/deploy-supabase-staging.yml');
const passwordVerifier = read('scripts/verify-admin-passwords.mjs');
const passwordFixtureGuard = read(
  'scripts/check-admin-password-fixtures.mjs',
);
const seedDemo = read('scripts/seed-demo.ts');
const e2eAuth = read('e2e/helpers/auth.ts');

function uppercaseStringLiterals(source: string): string[] {
  return [...source.matchAll(/'([A-Z][A-Z0-9_]*)'/g)]
    .map((match) => match[1]);
}

describe('pré-lancement : données test, effets externes et absence de MFA', () => {
  it('requalifie tout le stock opérationnel présent au déploiement', () => {
    expect(migration).toContain("UPDATE public.soignants");
    expect(migration).toContain("UPDATE public.etablissements");
    expect(migration).not.toContain('2026-07-30');
    expect(migration).toContain(
      'WHERE est_compte_test IS DISTINCT FROM true',
    );
    expect(migration).toContain('est_compte_test = true');
    expect(migration).not.toMatch(/\bUPDATE\s+public\.prospects_/i);
    expect(migration).not.toMatch(/\bDELETE\s+FROM\s+public\.prospects_/i);
    expect(migration).not.toMatch(/\bTRUNCATE\b/i);
  });

  it('conserve la provenance opérationnelle lors du relais SMS de la queue', () => {
    const queueSmsRelay = emailCron.slice(
      emailCron.indexOf("email.type?.startsWith('SMS_')"),
      emailCron.indexOf('// Email classique'),
    );
    expect(queueSmsRelay).toContain('data: email.data');
  });

  it('couvre les fixtures nommées et dérive le statut test de chaque mission', () => {
    for (const fixture of [
      'Hôpital Saint-Louis',
      'EHPAD Les Jardins de Belleville',
      'Clinique du Parc Monceau',
      "'julie'",
      "'thomas'",
      "'léa'",
    ]) {
      expect(migration).toContain(fixture);
    }
    expect(migration).toContain(
      'CREATE OR REPLACE FUNCTION private.fn_mission_lie_compte_test',
    );
    expect(migration).toContain('OR COALESCE(s.est_compte_test, false)');
    expect(migration).toContain(
      'private.fn_mission_lie_compte_test(m.id) IS DISTINCT FROM true',
    );
  });

  it('force les nouveaux comptes en test et sépare symétriquement les cohortes', () => {
    expect(migration).toContain(
      'ALTER COLUMN est_compte_test SET DEFAULT true',
    );
    expect(migration).toContain(
      'CREATE OR REPLACE FUNCTION private.fn_forcer_compte_test_prelaunch()',
    );
    expect(
      migration.match(/CREATE TRIGGER trg_forcer_compte_test_prelaunch/g)
        ?.length,
    ).toBe(2);
    expect(migration).toContain(
      'CREATE OR REPLACE FUNCTION private.fn_comptes_meme_cohorte_test',
    );
    expect(migration).toContain(
      'GRANT USAGE ON SCHEMA private TO authenticated, service_role',
    );
    expect(migration).toContain(
      "has_schema_privilege('authenticated', 'private', 'USAGE')",
    );
    expect(migration).toContain(
      "has_schema_privilege('anon', 'private', 'USAGE')",
    );
    expect(migration).toContain(
      'L’USAGE de private exposerait des fonctions inattendues',
    );
    expect(migration).toContain(
      'AND s.est_compte_test = e.est_compte_test',
    );
    expect(migration).toContain(
      'fn_resoudre_contrat_mission doit rester SECURITY INVOKER',
    );
    expect(migration).toContain(
      'CREATE POLICY missions_masquer_etabs_test',
    );
    expect(migration).toContain('CREATE POLICY pol_cand_insert');
    const candidaturePolicy = migration.slice(
      migration.indexOf('CREATE POLICY pol_cand_insert'),
      migration.indexOf(
        'CREATE OR REPLACE FUNCTION public.fn_resoudre_contrat_mission',
      ),
    );
    expect(
      candidaturePolicy.match(/fn_comptes_meme_cohorte_test/g)?.length,
    ).toBe(2);

    for (const functionName of [
      'public.fn_resoudre_contrat_mission',
      'public.fn_postuler_mission',
      'public.fn_etablissements_safe',
      'public.fn_compteur_soignants_disponibles',
      'public.fn_vivier_disponibilites',
      'public.fn_rechercher_soignants_etab',
    ]) {
      const start = migration.lastIndexOf(
        `CREATE OR REPLACE FUNCTION ${functionName}`,
      );
      expect(start).toBeGreaterThan(-1);
      expect(migration.slice(start, start + 12_000)).toContain(
        'private.fn_comptes_meme_cohorte_test',
      );
    }

    for (const functionName of [
      'public.fn_apercu_marche_profession',
      'public.fn_missions_publiques_etablissement',
      'public.fn_etablissement_public',
    ]) {
      const start = migration.lastIndexOf(
        `CREATE OR REPLACE FUNCTION ${functionName}`,
      );
      expect(start).toBeGreaterThan(-1);
      expect(migration.slice(start, start + 8_000)).toContain(
        'est_compte_test IS FALSE',
      );
    }
    expect(migration).toContain(
      'GRANT EXECUTE ON FUNCTION public.fn_missions_publiques_etablissement(uuid)',
    );
    expect(migration).toContain('TO anon, authenticated, service_role');
    expect(migration).toContain(
      "'public.fn_missions_publiques_etablissement(uuid)'",
    );
    expect(migration).toContain("'anon'");
  });

  it('filtre les fixtures des KPI réels et des surfaces publiques/indexées', () => {
    expect(migration).toContain('CREATE OR REPLACE FUNCTION public.fn_admin_kpi()');
    expect(migration).toContain('CREATE OR REPLACE FUNCTION public.fn_admin_graphiques()');
    expect(migration).toContain(
      'CREATE OR REPLACE FUNCTION public.fn_admin_cockpit_fondateur()',
    );
    expect(migration.match(/est_compte_test IS FALSE/g)?.length).toBeGreaterThan(20);
    for (const signature of [
      'public.fn_mission_publique(uuid)',
      'public.fn_missions_publiques_recherche(text,text)',
      'public.fn_missions_ouvertes_sitemap()',
      'public.fn_etablissements_avec_missions_ouvertes()',
    ]) {
      expect(migration).toContain(`'${signature}'::regprocedure`);
    }
    expect(migration).toContain(
      'CREATE OR REPLACE FUNCTION public.fn_etablissements_avec_missions_ouvertes()',
    );
    expect(migration).toContain(
      'private.fn_mission_lie_compte_test(m.id) IS FALSE',
    );
    expect(migration).toContain(
      'CREATE OR REPLACE FUNCTION public.fn_admin_metriques_argent()',
    );
    expect(migration).toMatch(
      /'etab_a_valider'[\s\S]*?e\.est_compte_test IS FALSE[\s\S]*?'a_des_donnees_test'/,
    );
  });

  it('échoue fermé avant tout envoi email ou push réel', () => {
    expect(testAccount).toContain("from('soignants')");
    expect(testAccount).toContain("from('etablissements')");
    expect(testAccount).toContain("from('membres_etablissement')");
    expect(testAccount).toContain("from('equipe_admin')");
    expect(testAccount).toContain(
      'export async function resolveOperationalTestSource',
    );
    expect(testAccount).toContain("from('litiges')");
    expect(testAccount).toContain("from('missions')");
    expect(testAccount).toContain(".eq('actif', true)");
    expect(testAccount).toContain('if (soignantResult.error || etablissementResult.error)');
    expect(testAccount).toContain("return { ok: false, error: 'compte opérationnel inconnu' }");

    expect(sendEmail).toContain('resolveOperationalTestAccount(');
    expect(sendEmail).toContain("reason: 'test_account'");
    expect(sendEmail.indexOf('const testAccount = await resolveOperationalTestAccount('))
      .toBeLessThan(sendEmail.indexOf("fetch('https://api.resend.com/emails'"));
    expect(sendEmail.indexOf('const sourceAccount = await resolveOperationalTestSource('))
      .toBeLessThan(sendEmail.indexOf("fetch('https://api.resend.com/emails'"));
    expect(sendEmail).toContain("reason: 'test_source'");

    expect(sendPush).toContain('resolveOperationalTestAccount(');
    expect(sendPush).toContain("reason: 'test_account'");
    expect(sendPush.indexOf('const testAccount = await resolveOperationalTestAccount('))
      .toBeLessThan(sendPush.indexOf('.from("tokens_push")'));
    expect(sendPush.indexOf('const sourceAccount = await resolveOperationalTestSource('))
      .toBeLessThan(sendPush.indexOf('.from("tokens_push")'));
    expect(sendPush).toContain("reason: 'test_source'");

    expect(sendSms).toContain('resolveOperationalTestAccount(');
    expect(sendSms).toContain("reason: 'test_account'");
    expect(sendSms).toContain('const classificationUserId = destinataireId');
    expect(sendSms.indexOf('const testAccount = await resolveOperationalTestAccount('))
      .toBeLessThan(sendSms.indexOf('const accountSid = Deno.env.get("TWILIO_ACCOUNT_SID")'));
    expect(sendSms.indexOf('const testAccount = await resolveOperationalTestAccount('))
      .toBeLessThan(sendSms.indexOf('const twilioRes = await fetch(twilioUrl'));
    expect(sendSms.indexOf('const sourceAccount = await resolveOperationalTestSource('))
      .toBeLessThan(sendSms.indexOf('const twilioRes = await fetch(twilioUrl'));
    expect(sendSms).toContain("reason: 'test_source'");
    expect(sendSms).not.toMatch(
      /type\s*!==\s*['"]OTP_VERIFICATION_TELEPHONE['"][\s\S]{0,200}resolveOperationalTestAccount/,
    );

    expect(migration).toContain('CREATE OR REPLACE FUNCTION public.dec_email_invitation_equipe_etab()');
    expect(migration).toContain('AND e.est_compte_test IS FALSE');
  });

  it('protège les quatre envois Resend opérationnels directs', () => {
    for (const source of [avisParrainage, digestHebdo, relanceInactifs]) {
      expect(source).toContain('resolveOperationalTestAccount(');
      expect(source).toContain('raison: "test_account"');
      expect(source.indexOf('resolveOperationalTestAccount('))
        .toBeLessThan(source.indexOf('fetch("https://api.resend.com/emails"'));
    }

    expect(notifySupport).toContain('classifyOperationalSource(');
    expect(notifySupport).toContain('resolveOperationalTestAccount(');
    expect(notifySupport).toContain("reason: 'test_account'");
    expect(notifySupport).toContain("'fn_admin_get_user_id_by_email'");
    expect(notifySupport).toContain("'source opérationnelle non identifiable'");
    expect(notifySupport).toContain('const SYSTEM_ALERT_SOURCES = new Set([');
    expect(notifySupport).toContain("'tripwire-paiement'");
    expect(notifySupport).toContain(
      "return { ok: false, error: 'source alerte système non autorisée' }",
    );
    expect(notifySupport.indexOf(
      'const classification = await classifyOperationalSource(',
    ))
      .toBeGreaterThan(notifySupport.indexOf('if (!authorized)'));
    expect(notifySupport.indexOf(
      'const classification = await classifyOperationalSource(',
    ))
      .toBeLessThan(notifySupport.indexOf("fetch('https://api.resend.com/emails'"));

    expect(migration).toContain(
      'CREATE OR REPLACE FUNCTION public.fn_trg_litige_notify_support()',
    );
    expect(migration).toContain("'mission_id', NEW.mission_id");
    expect(migration).toContain(
      'CREATE OR REPLACE FUNCTION public.fn_tripwire_alerte(',
    );
    expect(migration).toContain("'source', 'tripwire-paiement'");
    expect(migration).toContain("'system_alert', true");
  });

  it('réserve les tripwires premier euro aux seules données réelles', () => {
    const functionBody = (name: string) => {
      const start = migration.lastIndexOf(
        `CREATE OR REPLACE FUNCTION public.${name}()`,
      );
      expect(start, name).toBeGreaterThanOrEqual(0);
      const end = migration.indexOf('$function$;', start);
      expect(end, name).toBeGreaterThan(start);
      return migration.slice(start, end);
    };
    const mandate = functionBody('fn_trg_tripwire_premier_mandat_sepa');
    const connect = functionBody('fn_trg_tripwire_premier_connect_complet');
    const payment = functionBody('fn_trg_tripwire_premier_payment_intent');

    expect(mandate).toContain(
      'NEW.est_compte_test IS DISTINCT FROM false',
    );
    expect(mandate).toContain('e.est_compte_test IS FALSE');
    expect(connect.match(/est_compte_test IS FALSE/g)).toHaveLength(2);
    expect(payment.match(/est_compte_test IS FALSE/g)).toHaveLength(4);
    for (const [name, body] of [
      ['mandat SEPA', mandate],
      ['Connect', connect],
      ['PaymentIntent', payment],
    ] as const) {
      expect(
        body.indexOf('est_compte_test'),
        `${name}: classification réelle avant alerte`,
      ).toBeLessThan(body.indexOf('PERFORM public.fn_tripwire_alerte'));
      expect(body).toContain('IF EXISTS (');
    }
  });

  it('borne et déduplique les OTP signature et notifications urgentes', () => {
    const functionBody = (name: string) => {
      const start = migration.lastIndexOf(
        `CREATE OR REPLACE FUNCTION public.${name}(`,
      );
      expect(start, name).toBeGreaterThanOrEqual(0);
      const end = migration.indexOf('$function$;', start);
      expect(end, name).toBeGreaterThan(start);
      return migration.slice(start, end);
    };
    const otp = functionBody('fn_envoyer_otp_signature');
    const urgent = functionBody('fn_trg_auto_notify_mission_urgente');

    expect(otp).toContain('pg_advisory_xact_lock');
    expect(otp).toContain("'otp-signature.'");
    expect(otp).toContain("'idempotency_key', v_idempotency_key");
    expect(otp.indexOf('v_idempotency_key :='))
      .toBeLessThan(otp.indexOf("'/functions/v1/send-sms'"));

    expect(urgent).toContain(
      'v_etab.est_compte_test IS DISTINCT FROM false',
    );
    expect(urgent).toContain('s.est_compte_test IS FALSE');
    expect(urgent.indexOf('v_etab.est_compte_test IS DISTINCT FROM false'))
      .toBeLessThan(urgent.indexOf('INSERT INTO public.notifications'));
    expect(urgent).toContain('RETURNING id INTO v_notification_id');
    for (const key of [
      "'mission-urgente.push.' || v_notification_id::text",
      "'mission-urgente.email.' || v_notification_id::text",
      "'mission-urgente.sms.' || v_notification_id::text",
    ]) {
      expect(urgent).toContain(key);
    }
    const smsCall = urgent.slice(
      urgent.indexOf("'/functions/v1/send-sms'"),
      urgent.indexOf('v_count := v_count + 1'),
    );
    expect(smsCall).toContain("'mission_id', NEW.id");
    expect(smsCall).toContain("'notification_id', v_notification_id");
  });

  it('classe explicitement le contact public et l’acquisition inactive', () => {
    expect(edgeLaunchInventory).toContain(
      '`admin-invoke` | `SYSTEME_ADMIN_PROTEGE`',
    );
    expect(contactForm).toContain("verifyTurnstileToken");
    expect(contactForm).toContain("applyRateLimit('contact-form'");
    expect(edgeLaunchInventory).toContain(
      '`contact-form` | `PUBLIC_INBOUND_ALLOWED`',
    );
    expect(edgeLaunchInventory).toContain(
      '`sales-outreach` | `ACQUISITION_INACTIVE`',
    );
    expect(edgeLaunchInventory).toContain(
      '`sales-outreach-batch` | `ACQUISITION_INACTIVE`',
    );
    expect(edgeLaunchInventory).toContain(
      'growth_config.automatisations_marketing_actives != true',
    );
  });

  it('rend les emails idempotents, auditables et cohérents avec la marque Jolene', () => {
    expect(sendEmail).toContain(
      "const BRAND_LOGO_URL = 'https://jolene.app/logo-jolene-carre.png'",
    );
    expect(sendEmail).toContain('alt="Jolene"');
    expect(sendEmail).not.toContain('❤️ Jolene');
    expect(sendEmail).toContain("resendHeaders['Idempotency-Key'] = idempotencyKey");
    expect(sendEmail).toContain("'fn_reserver_envoi_email_idempotent' as any");
    expect(sendEmail).toContain("'fn_finaliser_envoi_email_idempotent' as any");
    expect(sendEmail).toContain(".upsert(emailAudit, { onConflict: 'idempotency_key' })");

    expect(migration).toContain(
      'CREATE TABLE IF NOT EXISTS private.email_dispatch_idempotency',
    );
    expect(migration).toContain(
      'CREATE OR REPLACE FUNCTION public.fn_reserver_envoi_email_idempotent',
    );
    expect(migration).toContain(
      'CREATE OR REPLACE FUNCTION public.fn_finaliser_envoi_email_idempotent',
    );
    expect(migration).toContain(
      'ADD CONSTRAINT emails_envoyes_idempotency_key_key',
    );
    expect(migration).toContain("'DPAE_DECLAREE_SOIGNANT'");
    expect(migration).toContain("'PARRAINAGE_PRIME_VERSEE'");
    expect(migration).toContain("'CONFIRMATION_EMAIL_PRO_ETAB'");
    expect(migration).toContain("'DPAE_ANNULATION_RAPPEL'");
    expect(sendEmail).toContain("'PARRAINAGE_PRIME_VERSEE'");
    expect(sendEmail).toContain("'CONFIRMATION_EMAIL_PRO_ETAB'");
    expect(sendEmail).toContain("'DPAE_ANNULATION_RAPPEL'");
    expect(migration).toContain(
      "'idempotency_key', 'invitation-equipe-etab:' || NEW.id::text",
    );

    expect(migration).toContain(
      'CREATE OR REPLACE FUNCTION public.fn_envoyer_rappels_notation_j1()',
    );
    expect(migration).toContain(
      "'notation-j1:etab-vers-soignant:' || v_mission.id::text",
    );
    expect(migration).toContain(
      "'notation-j1:soignant-vers-etab:' || v_mission.id::text",
    );
    expect(
      migration.match(/ON CONFLICT \(mission_id, sens\) DO NOTHING/g)?.length,
    ).toBeGreaterThanOrEqual(2);
    expect(migration).toContain('JOIN etablissements e ON e.id = m.etablissement_id');
    expect(migration).toContain('JOIN soignants s ON s.id = m.soignant_assigne_id');
    expect(migration).toContain(
      'CREATE TABLE IF NOT EXISTS private.notation_email_dispatch',
    );
    expect(migration).toContain(
      'CREATE OR REPLACE FUNCTION private.fn_controler_rappels_notation_j1()',
    );
    expect(migration).toContain('LEFT JOIN net._http_response');
    expect(migration).toContain(
      'v_dispatch.status_code BETWEEN 200 AND 299',
    );
    expect(migration).toContain("SET statut = 'REESSAI'");
    expect(migration).toContain("SET statut = 'ECHEC'");
    expect(migration).toContain("'RAPPEL_NOTATION_HTTP_FAILED'");
    expect(migration).toContain("'RAPPEL_NOTATION_ENQUEUE_FAILED'");
    expect(sendEmail).toContain('status: response.ok ? 200 : 502');
    expect(sendEmail).toContain(
      "error: 'Fournisseur email non configuré'",
    );
    expect(sendEmail).toContain('status: 503');
  });

  it('garde les templates, types autorisés et contraintes d’audit synchronisés', () => {
    const allowedBlock = sendEmail.match(
      /const ALLOWED_TYPES = new Set\(\[([\s\S]*?)\]\);/,
    )?.[1];
    const constraintBlock = migration.match(
      /ADD CONSTRAINT emails_envoyes_type_check CHECK \([\s\S]*?ARRAY\[([\s\S]*?)\]::text\[\]\)/,
    )?.[1];
    expect(allowedBlock).toBeDefined();
    expect(constraintBlock).toBeDefined();

    const allowed = [...new Set(
      uppercaseStringLiterals(allowedBlock || ''),
    )].sort();
    const rendered = [...new Set(
      [...sendEmail.matchAll(/case '([A-Z][A-Z0-9_]*)'/g)]
        .map((match) => match[1]),
    )].sort();
    const persisted = new Set(
      uppercaseStringLiterals(constraintBlock || ''),
    );

    expect(rendered).toEqual(allowed);
    expect(
      allowed.filter((type) => !persisted.has(type)),
    ).toEqual([]);
  });

  it('authentifie avant quota et exempte uniquement service_role', () => {
    const rateLimitCalls = sendEmail.match(
      /applyRateLimit\('send-email'/g,
    ) || [];
    expect(rateLimitCalls).toHaveLength(1);
    const userAuth = sendEmail.indexOf(
      "const { data: { user }, error: authError }",
    );
    const rateLimit = sendEmail.indexOf(
      "&& applyRateLimit('send-email'",
    );
    expect(userAuth).toBeGreaterThan(-1);
    expect(rateLimit).toBeGreaterThan(userAuth);
    expect(sendEmail.slice(rateLimit - 80, rateLimit))
      .toContain('!isServiceRole');
  });

  it('supprime le MFA de la route, de l’Edge partagé et de la base', () => {
    expect(route).not.toContain('AdminMfaGate');
    expect(route).not.toContain('ADMIN_EMAILS_SANS_MFA');
    expect(edgeAuth).not.toContain('getClaims(');
    expect(edgeAuth).not.toContain("'aal2'");
    expect(edgeAuth).not.toContain('auth.aal');
    expect(edgeAuth).toContain("role === 'ADMIN_PLATEFORME'");
    expect(edgeAuth).toContain('isConfirmedAuthUser');
    expect(edgeAuth).toContain('hasFullLaunchAdminAccess');

    expect(existsSync(join(root, 'src/components/admin/AdminMfaGate.tsx'))).toBe(false);
    expect(existsSync(join(root, 'supabase/functions/admin-2fa/index.ts'))).toBe(false);
    expect(config).not.toContain('[functions.admin-2fa]');

    expect(migration).toContain('DELETE FROM auth.mfa_factors');
    expect(migration).toContain('DROP FUNCTION IF EXISTS public.fn_lire_email_2fa(uuid)');
    expect(migration).toContain('DROP TABLE IF EXISTS public.admin_2fa_codes CASCADE');
    expect(migration).toContain('DROP TABLE IF EXISTS public.admin_securite CASCADE');
    expect(migration).not.toContain("auth.jwt() ->> 'aal'");
  });

  it('prune explicitement admin-2fa en production et staging', () => {
    for (const workflow of [deployProd, deployStaging]) {
      expect(workflow).toContain("RETIRED_EDGE_FUNCTIONS: 'admin-2fa'");
      expect(workflow).toContain('supabase functions delete "$fn"');
      expect(workflow).toContain('La fonction retirée $fn existe encore à distance');
      expect(workflow).not.toContain('functions delete --all');
      expect(workflow.indexOf('supabase functions delete "$fn"'))
        .toBeGreaterThan(workflow.indexOf('supabase functions deploy "$fn"'));
    }
  });

  it('vérifie les mots de passe admin sans jamais les écrire ni les modifier', () => {
    expect(passwordVerifier).toContain('JOLENE_ADMIN_CANONICAL_PASSWORD');
    expect(passwordVerifier).toContain('auth.admin.listUsers');
    expect(passwordVerifier).toContain("user.app_metadata?.role === 'ADMIN_PLATEFORME'");
    expect(passwordVerifier).toContain('auth.signInWithPassword');
    expect(passwordVerifier).not.toContain('updateUserById');
    expect(passwordVerifier).not.toContain('createUser');
    expect(passwordVerifier).not.toContain('encrypted_password');
    expect(passwordVerifier).not.toMatch(
      /console\.(?:log|error)\([^)]*canonicalPassword/,
    );
    expect(seedDemo).toContain('PROTECTED_ADMIN_EMAILS');
    expect(seedDemo).toContain("'admin@jolene.app'");
    expect(seedDemo).toContain("'gabrielle.pcd@outlook.com'");
    expect(seedDemo).toContain("'ops-test@jolene.app'");
    expect(seedDemo).toContain(
      "existing.app_metadata?.role === 'ADMIN_PLATEFORME'",
    );
    expect(seedDemo).toContain(
      "existing.user_metadata?.role === 'ADMIN_PLATEFORME'",
    );
    expect(seedDemo).toContain(".from('equipe_admin')");
    expect(seedDemo).toContain(".eq('user_id', existing.id)");
    expect(seedDemo).not.toContain('Password : ${DEMO_PASSWORD}');
    expect(passwordFixtureGuard).toContain(
      'Mutation de mot de passe Auth non autorisée',
    );
    expect(passwordFixtureGuard).toContain('PROTECTED_ADMIN_EMAILS.has(DEMO_EMAIL)');
    expect(passwordFixtureGuard).toContain(".from('equipe_admin')");
    expect(e2eAuth).toContain('process.env.JOLENE_ADMIN_CANONICAL_PASSWORD');
    expect(e2eAuth).not.toMatch(
      /email:\s*'admin@jolene\.app'[\s\S]{0,200}password:[^\n]*'Playwright!Test2026'/,
    );
  });
});
