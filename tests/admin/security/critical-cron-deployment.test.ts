import { readFileSync } from "node:fs";
import { describe, expect, it } from "vitest";

const root = process.cwd();
const migration = readFileSync(
  `${root}/supabase/migrations/20260729121442_securiser_auth_et_crons_critiques.sql`,
  "utf8",
);
const bootstrapDependencies = readFileSync(
  `${root}/supabase/migrations/20260729143000_reinstaller_dependances_auth_storage_apres_bootstrap.sql`,
  "utf8",
);
const productionWorkflow = readFileSync(
  `${root}/.github/workflows/deploy-supabase.yml`,
  "utf8",
);
const stagingWorkflow = readFileSync(
  `${root}/.github/workflows/deploy-supabase-staging.yml`,
  "utf8",
);
const validationWorkflow = readFileSync(
  `${root}/.github/workflows/validate-pr.yml`,
  "utf8",
);

const criticalJobs = [
  "litige-escalation-cron",
  "email-cron-hourly-immediate",
  "email-cron-daily",
  "process-stripe-refunds-15min",
  "escrow-debit-echeance",
  "escrow-release",
  "jolene_process_externalisations",
  "weekly-invoicing-cron",
] as const;

describe("déploiement fail-closed des crons critiques", () => {
  it("recapture huit jobs et le monitor tous inactifs dans la migration", () => {
    for (const job of criticalJobs) {
      expect(migration, job).toContain(`'${job}'`);
    }
    expect(migration).toContain("'jolene-monitor-crons-edge-critiques'");
    expect(migration).toContain(
      "PERFORM cron.alter_job(job_id := v_job_id, active := false)",
    );
    expect(migration).toContain(
      "CREATE OR REPLACE FUNCTION private.fn_desactiver_crons_edge_critiques()",
    );
    expect(migration).toContain(
      "CREATE OR REPLACE FUNCTION public.fn_ops_desactiver_crons_edge_critiques()",
    );
    expect(migration).toContain("RAISE EXCEPTION 'Un job Edge critique a été activé avant les sondes'");
  });

  it("lie l'activation aux huit request_id exacts et reste atomique", () => {
    expect(migration).toContain(
      "private.fn_etat_sondes_crons_edge_critiques(p_sondes)",
    );
    expect(migration).toContain(
      "l.request_id = (p_sondes ->> v_job)::bigint",
    );
    expect(migration).toContain("p_confirmation IS DISTINCT FROM 'AUTH_PROBES_OK'");
    expect(migration).toContain(
      "v_etat_final := private.fn_etat_activation_crons_edge_critiques()",
    );
    expect(migration).toContain(
      "cardinality(v_acquisition_active) = 0",
    );
    expect(migration).toContain("'jolene_acquisition_bmo_mensuel'");
    expect(migration).toContain("'jolene_acquisition_boamp_quotidien'");
    expect(
      migration.match(/'jolene_crm_generer_taches'/g),
    ).toHaveLength(3);
    expect(migration).toContain("GRANT USAGE ON SCHEMA private TO service_role");
    expect(migration).toContain(
      "has_schema_privilege('service_role', 'private', 'USAGE')",
    );
    expect(migration).toContain(
      "has_function_privilege('service_role', v_signature, 'EXECUTE')",
    );
  });

  it("sonde réellement après les Edge puis active et vérifie l'état en prod", () => {
    const disableIndex = productionWorkflow.indexOf(
      "fn_ops_desactiver_crons_edge_critiques",
    );
    const deploymentIndex = productionWorkflow.indexOf(
      "Deploy every function listed in supabase/config.toml",
    );
    const probeIndex = productionWorkflow.indexOf(
      "fn_ops_sonder_crons_edge_critiques",
    );
    const activateIndex = productionWorkflow.indexOf(
      "fn_ops_activer_crons_edge_critiques",
    );
    const finalStateIndex = productionWorkflow.indexOf(
      "fn_ops_etat_activation_crons_edge_critiques",
    );
    expect(disableIndex).toBeGreaterThanOrEqual(0);
    expect(deploymentIndex).toBeGreaterThanOrEqual(0);
    expect(disableIndex).toBeLessThan(deploymentIndex);
    expect(probeIndex).toBeGreaterThan(deploymentIndex);
    expect(activateIndex).toBeGreaterThan(probeIndex);
    expect(finalStateIndex).toBeGreaterThan(activateIndex);
    expect(productionWorkflow).toContain("for attempt in $(seq 1 18)");
    expect(productionWorkflow).toContain(".ok == 8");
    expect(productionWorkflow).toContain("p_confirmation: \"AUTH_PROBES_OK\"");
    expect(productionWorkflow).toContain("(.critiques_actifs | length) == 9");
    expect(productionWorkflow).toContain("(.acquisition_active | length) == 0");
    expect(productionWorkflow).toContain(
      "(.critiques_desactives | length) == 9",
    );
  });

  it("intègre la facturation quotidienne à 06:00 Europe/Paris et remonte ses échecs", () => {
    const weekly = readFileSync(
      `${root}/supabase/functions/weekly-invoicing-cron/index.ts`,
      "utf8",
    );
    expect(migration).toContain("('weekly-invoicing-cron', '0 4,5 * * *')");
    expect(migration).toContain("AT TIME ZONE %L) = 6");
    expect(weekly).toContain("status: summary.success ? 200 : 500");
    expect(weekly).toContain("data?.success !== true");
    expect(weekly).toContain("!r.success && !r.skipped");
  });

  it("applique les migrations locales en staging sans activer les crons", () => {
    expect(stagingWorkflow).toContain(
      "Link to STAGING and push pending local migrations",
    );
    expect(stagingWorkflow).toContain("supabase db push");
    expect(stagingWorkflow).toContain("--include-all");
    expect(stagingWorkflow).toContain("'20260729121419'");
    expect(stagingWorkflow).toContain("'20260729121442'");
    expect(stagingWorkflow).toContain("'20260729121443'");
    expect(stagingWorkflow).toContain("'20260729134515'");
    expect(stagingWorkflow).toContain("'20260729143000'");
    expect(stagingWorkflow).toContain("ACTIVE_CRITICAL");
    expect(stagingWorkflow).toContain(
      "private.fn_sonder_crons_edge_critiques()",
    );
    expect(stagingWorkflow).toContain(".ok == 8");
    expect(stagingWorkflow).toContain("active_count");
    expect(stagingWorkflow).not.toContain(
      "fn_ops_activer_crons_edge_critiques",
    );
  });

  it("reconstruit le staging sans toucher la prod ni perdre les dépendances gérées", () => {
    expect(stagingWorkflow).toContain(
      "group: jolene-supabase-staging-writes",
    );
    expect(validationWorkflow).toContain(
      "group: jolene-supabase-staging-writes",
    );
    expect(stagingWorkflow).toContain(
      "Ce bootstrap exige la confirmation explicite reset_first=true",
    );
    expect(stagingWorkflow.match(/mejpriaetwgtcstbgfid/g)?.length)
      .toBeGreaterThanOrEqual(5);
    expect(stagingWorkflow.match(/flripxtsyegjshnhzjkz/g)?.length)
      .toBeGreaterThanOrEqual(3);
    expect(stagingWorkflow).toContain(
      "DROP SCHEMA IF EXISTS private CASCADE",
    );
    expect(stagingWorkflow).toContain(
      "TRUNCATE TABLE supabase_migrations.schema_migrations",
    );
    expect(stagingWorkflow).toContain(
      "supabase db query --linked --agent=no --output csv",
    );
    expect(stagingWorkflow).toContain(
      "SELECT version, statements::text AS statements, name",
    );
    const inventoryReplayIndex = stagingWorkflow.indexOf(
      "20260729121443_figer_inventaire_security_definer.sql",
    );
    const launchAssertionsIndex = stagingWorkflow.indexOf(
      "Assert launch migrations on STAGING without cron activation",
    );
    expect(inventoryReplayIndex).toBeGreaterThanOrEqual(0);
    expect(launchAssertionsIndex).toBeGreaterThan(inventoryReplayIndex);
    expect(stagingWorkflow).toContain(
      "\\\\copy supabase_migrations.schema_migrations(version, statements, name)",
    );
    expect(stagingWorkflow).not.toContain("migrations-data.sql");
    expect(stagingWorkflow).not.toContain(
      "schema_migrations(version, statements, name, created_by)",
    );
    expect(stagingWorkflow).toContain(
      "aws-0-${REGION}.pooler.supabase.com:5432",
    );
    expect(
      stagingWorkflow.match(/--single-transaction/g),
    ).toHaveLength(2);
    expect(stagingWorkflow).not.toContain(
      "@db.${REF}.supabase.co:5432",
    );
    expect(stagingWorkflow).not.toContain(
      "DROP SCHEMA IF EXISTS supabase_migrations",
    );
    expect(stagingWorkflow).toContain("GHOST_MIGRATIONS");
    expect(stagingWorkflow).toContain("STORAGE_POLICIES");
    expect(stagingWorkflow).toContain("PRIVATE_BUCKETS");
    expect(stagingWorkflow).toContain("REALTIME_TABLES");
    expect(stagingWorkflow).toContain("AUTH_TRIGGER");
    expect(stagingWorkflow).toContain("RELIABILITY_VIEW");

    expect(
      bootstrapDependencies.trimStart().startsWith(
        "-- DROP SCHEMA public CASCADE",
      ),
    ).toBe(true);
    expect(bootstrapDependencies).toContain("\nBEGIN;\n");
    expect(bootstrapDependencies.trimEnd().endsWith("COMMIT;")).toBe(true);
    expect(bootstrapDependencies.match(/CREATE POLICY /g)).toHaveLength(8);
    expect(bootstrapDependencies).toContain(
      "CREATE TRIGGER trg_auth_user_deleted_cleanup",
    );
    expect(bootstrapDependencies).toContain(
      "ALTER PUBLICATION supabase_realtime ADD TABLE",
    );
    expect(bootstrapDependencies).toContain(
      "private.fn_reconcilier_crons_edge_critiques_inactifs()",
    );
    expect(bootstrapDependencies).toContain(
      "REVOKE ALL ON SCHEMA private FROM PUBLIC, anon, authenticated",
    );
    expect(bootstrapDependencies).toContain(
      "GRANT USAGE ON SCHEMA private TO service_role",
    );
    expect(bootstrapDependencies).toContain(
      "to_regclass('extensions.vm_fiabilite_soignants') IS NULL",
    );
    expect(bootstrapDependencies).toContain(
      "CREATE VIEW extensions.vm_fiabilite_soignants",
    );
    expect(bootstrapDependencies).not.toContain(
      "CREATE OR REPLACE VIEW extensions.vm_fiabilite_soignants",
    );
  });

  it("rend chaque email cron déterministement idempotent", () => {
    const emailCron = readFileSync(
      `${root}/supabase/functions/email-cron/index.ts`,
      "utf8",
    );
    expect(emailCron).toContain("async function invokeIdempotentEmail");
    expect(emailCron).toContain("idempotency_key: idempotencyKey");
    expect(emailCron).toContain("crypto.subtle.digest");
    expect(
      [...emailCron.matchAll(/functions\.invoke\(\s*["']send-email["']/g)]
        .length,
    ).toBe(1);
    expect(
      [...emailCron.matchAll(/invokeIdempotentEmail\(/g)].length,
    ).toBeGreaterThanOrEqual(7);
    expect(emailCron).toContain("results.email_queue_erreurs = queueErrors");
    expect(emailCron).toContain("status: success ? 200 : 500");
    expect(emailCron).toContain("Number(value) < 0");
  });

  it("réserve durablement chaque SMS interne avant Twilio", () => {
    const emailCron = readFileSync(
      `${root}/supabase/functions/email-cron/index.ts`,
      "utf8",
    );
    const sendSms = readFileSync(
      `${root}/supabase/functions/send-sms/index.ts`,
      "utf8",
    );
    const externalisations = readFileSync(
      `${root}/supabase/functions/process-externalisation-actions/index.ts`,
      "utf8",
    );

    expect(migration).toContain("private.sms_dispatch_idempotency");
    expect(migration).toContain("fn_reserver_envoi_sms_idempotent");
    expect(migration).toContain("fn_finaliser_envoi_sms_idempotent");
    expect(migration).toContain(
      "v_ligne.statut IN ('EN_COURS', 'INDETERMINE')",
    );
    expect(sendSms).toContain("auth.isServiceRole && !idempotencyKey");
    expect(sendSms).toContain("reservationStatus === 'DEJA_ENVOYE'");
    expect(sendSms).toContain("reservationStatus === 'INDETERMINE'");
    expect(sendSms).toContain("await finalizeIdempotency('ENVOYE'");
    expect(sendSms.indexOf("fn_reserver_envoi_sms_idempotent")).toBeLessThan(
      sendSms.indexOf("twilioRes = await fetch"),
    );

    expect(emailCron).toContain("async function invokeIdempotentSms");
    expect(emailCron).toContain("'sms_rappel_mission_j1'");
    expect(emailCron).toContain("`email-queue.sms.${email.id}`");
    expect(emailCron).toContain("markSentError || !markedSent");
    expect(emailCron).toContain(".eq('statut', 'EN_ATTENTE')");
    expect(emailCron).toContain(
      "la ligne reste EN_ATTENTE pour une reprise idempotente",
    );
    expect(emailCron).not.toContain("email_queue mark ENVOYE failed");
    expect(sendSms).toContain("const ambiguousProviderFailure = twilioRes.status >= 500");
    expect(sendSms).toContain(
      "ambiguousProviderFailure ? 'INDETERMINE' : 'ERREUR'",
    );
    expect(externalisations).toContain(
      "idempotency_key: `externalisation.${action.id}.sms`",
    );
  });

  it("n'acquitte un push interne qu'après livraison, skip explicite ou fallback", () => {
    const sendPush = readFileSync(
      `${root}/supabase/functions/send-push/index.ts`,
      "utf8",
    );
    const sendEmail = readFileSync(
      `${root}/supabase/functions/send-email/index.ts`,
      "utf8",
    );
    const externalisations = readFileSync(
      `${root}/supabase/functions/process-externalisation-actions/index.ts`,
      "utf8",
    );

    expect(migration).toContain("private.push_dispatch_idempotency");
    expect(migration).toContain("fn_reserver_envoi_push_idempotent");
    expect(migration).toContain("fn_finaliser_envoi_push_idempotent");
    expect(sendPush).toContain("IDEMPOTENCY_KEY_PATTERN.test(idempotencyKey)");
    expect(sendPush.indexOf("fn_reserver_envoi_push_idempotent")).toBeLessThan(
      sendPush.indexOf("for (const t of tokens || [])"),
    );
    expect(sendPush).toContain("PUSH_PROVIDER_NOT_CONFIGURED");
    expect(sendPush).toContain("providerErrors.length > 0");
    expect(sendPush).toContain("'INDETERMINE'");
    expect(sendPush).toContain(
      "const fallbackIdempotencyKey = `push-fallback.${requestFingerprint}`",
    );
    expect(sendPush).toContain("fallbackData?.success !== true");
    expect(sendEmail).toContain("'NOTIFICATION_PUSH_FALLBACK'");
    expect(sendEmail).toContain("case 'NOTIFICATION_PUSH_FALLBACK':");

    expect(externalisations).toContain(
      "idempotency_key: `externalisation.${action.id}.push`",
    );
    expect(externalisations).toContain(
      "idempotency_key: `externalisation.${action.id}.dpae-push`",
    );
    expect(externalisations).toContain("validatePushResponse");
    expect(externalisations).toContain("data?.success === true");
    expect(externalisations).toContain(
      "delivered || intentionallySkipped || fallbackDelivered",
    );
  });

  it("remonte les échecs métier au contrôleur HTTP au lieu d'un faux 200", () => {
    const expectations = [
      ["escrow-debit-echeance", "const success = echoues === 0"],
      ["escrow-release", "const success = echecs === 0"],
      ["process-stripe-refunds", "const success = failed === 0"],
      [
        "process-externalisation-actions",
        "const runSucceeded = failed === 0 && ackFailed === 0",
      ],
    ] as const;
    for (const [slug, successGuard] of expectations) {
      const source = readFileSync(
        `${root}/supabase/functions/${slug}/index.ts`,
        "utf8",
      );
      expect(source, slug).toContain(successGuard);
      expect(source, slug).toMatch(
        /status:\s*(?:success|runSucceeded)\s*\?\s*200\s*:\s*500/,
      );
    }
  });
});
