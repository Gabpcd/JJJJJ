import { readFileSync } from 'node:fs';
import { join } from 'node:path';
import { describe, expect, it } from 'vitest';

const migration = readFileSync(
  join(
    process.cwd(),
    'supabase/migrations/20260714003439_corriger_fonctions_runtime_lint.sql',
  ),
  'utf8',
);

describe('correctifs runtime des fonctions PostgreSQL', () => {
  it('rend chaque remplacement chirurgical exact et fail-closed', () => {
    expect(migration).toContain('jolene_replace_function_fragment');
    expect(migration).toContain('IF v_occurrences <> 1 THEN');
    expect(migration).toContain('Remplacement refusé pour %');
    expect(migration).toContain(
      'DROP FUNCTION pg_temp.jolene_replace_function_fragment',
    );
  });

  it('construit les problèmes documentaires comme un vrai text[]', () => {
    expect(migration).toContain('v_problemes text[] := ARRAY[]::text[]');
    expect(migration.match(/v_problemes := array_append\(/g)).toHaveLength(4);
    expect(migration).not.toContain("v_problemes := v_problemes || '");
  });

  it('interdit la lecture documentaire croisée hors service_role/admin complet', () => {
    const coherenceFunction = migration.match(
      /CREATE OR REPLACE FUNCTION public\.fn_verifier_coherence_documents\([\s\S]*?\$function\$;/,
    )?.[0];

    expect(coherenceFunction).toBeDefined();
    expect(coherenceFunction).toContain("= 'service_role'");
    expect(coherenceFunction).toContain('public.fn_compte_auth_actif() IS NOT TRUE');
    expect(coherenceFunction).toContain(
      'v_soignant_id IS DISTINCT FROM v_uid AND NOT v_is_service_role',
    );
    expect(coherenceFunction).toContain('public.est_admin_valide()');
    expect(coherenceFunction?.match(/ERRCODE = '42501'/g)).toHaveLength(2);
  });

  it('utilise le régime effectif figé et le défaut salarié pour l’annulation', () => {
    expect(migration).toContain(
      "COALESCE(v_contrat.type_contrat, v_mission.type_contrat_applique::text, 'SALARIE')",
    );
  });

  it('valide les présences sans table temporaire partagée par la session', () => {
    const replacement = migration.match(
      /CREATE OR REPLACE FUNCTION public\.fn_valider_presences_lot[\s\S]*?\$function\$;/,
    )?.[0];

    expect(replacement).toBeDefined();
    expect(replacement).toContain('WITH maj AS');
    expect(replacement).toContain('RETURNING p.id, p.mission_id, p.soignant_id');
    expect(replacement).toContain('jsonb_array_elements(v_validees)');
    expect(replacement).toContain(
      "public.fn_a_permission_etablissement('pointage', v_etab_id) IS NOT TRUE",
    );
    expect(replacement).not.toContain('CREATE TEMP TABLE');
    expect(replacement).not.toContain('_validees_lot');
  });

  it('réserve la modification de tolérance aux responsables du profil établissement', () => {
    const replacement = migration.match(
      /CREATE OR REPLACE FUNCTION public\.fn_modifier_tolerance_pointage_etab[\s\S]*?\$function\$;/,
    )?.[0];

    expect(replacement).toBeDefined();
    expect(replacement).toContain(
      "public.fn_a_permission_etablissement('profil_etab', v_etab_id) IS NOT TRUE",
    );
    expect(replacement!.indexOf("'profil_etab'")).toBeLessThan(
      replacement!.indexOf('UPDATE public.etablissements'),
    );
  });

  it('écrit uniquement dans les colonnes réelles des établissements et alertes', () => {
    expect(migration).toContain('modifie_le = now()');
    expect(migration).toContain(
      "OLD.statut_verification = 'VERIFIE'",
    );
    expect(migration).toContain(
      "AND NEW.statut_verification = 'EN_COURS'",
    );
    expect(migration).toContain('AND NEW.peut_publier_missions IS FALSE');
    expect(migration).toContain("'resolution_admin', jsonb_build_object(");
    expect(migration).toContain("'resolu_par', auth.uid()");

    const alertFunction = migration.match(
      /CREATE OR REPLACE FUNCTION public\.fn_admin_resoudre_alerte[\s\S]*?\$function\$;/,
    )?.[0];
    expect(alertFunction).toBeDefined();
    expect(alertFunction).toContain('resolu_motif = COALESCE');
    expect(alertFunction).not.toMatch(/\bresolu_par\s*=/);
  });

  it('ne place plus de libellé textuel dans litiges.resolu_par UUID', () => {
    const closeFunction = migration.match(
      /CREATE OR REPLACE FUNCTION public\.fn_cloturer_litige\([\s\S]*?\$function\$;/,
    )?.[0];

    expect(closeFunction).toBeDefined();
    expect(closeFunction?.match(/resolu_par = v_uid/g)).toHaveLength(2);
    expect(closeFunction).not.toContain("resolu_par = 'ADMIN'");
    expect(closeFunction).not.toContain("resolu_par = 'ACCORD_MUTUEL'");
  });

  it('autorise le litige avant de lire son statut', () => {
    const closeFunction = migration.match(
      /CREATE OR REPLACE FUNCTION public\.fn_cloturer_litige\([\s\S]*?\$function\$;/,
    )?.[0];

    expect(closeFunction).toBeDefined();
    expect(closeFunction).toContain(
      'IF v_uid IS NULL OR public.fn_compte_auth_actif() IS NOT TRUE THEN',
    );
    expect(closeFunction).toContain('l.soignant_id = v_uid');
    expect(closeFunction).toContain(
      'l.etablissement_id = v_etablissement_id',
    );
    expect(closeFunction?.match(/OR v_est_admin/g)).toHaveLength(2);
    expect(closeFunction?.match(/'contrats', l\.etablissement_id/g)).toHaveLength(2);
    expect(closeFunction).toContain("SET statut = 'RESOLU_ADMIN'");
    expect(closeFunction).toContain("SET statut = 'RESOLU_ACCORD_PARTIES'");
    expect(closeFunction).toContain('v_litige.payload_modifications IS NOT NULL');
    expect(closeFunction).not.toContain("'CLOTURE'");
    expect(closeFunction).toContain('FOR UPDATE');
    expect(closeFunction).toContain('Litige introuvable ou accès refusé');
    expect(closeFunction!.indexOf('IF v_litige.statut')).toBeGreaterThan(
      closeFunction!.indexOf('OR v_est_admin'),
    );
  });

  it('lie chaque double accord au payload JSONB exact sous verrou de ligne', () => {
    const payloadFunction = migration.match(
      /CREATE OR REPLACE FUNCTION public\.fn_cloturer_litige_avec_payload\([\s\S]*?\$function\$;/,
    )?.[0];
    const accordTrigger = migration.match(
      /CREATE OR REPLACE FUNCTION public\.fn_trg_litige_accord_mutuel\([\s\S]*?\$function\$;/,
    )?.[0];

    expect(payloadFunction).toBeDefined();
    expect(payloadFunction).toContain('public.fn_compte_auth_actif() IS NOT TRUE');
    expect(payloadFunction).toContain("'contrats', l.etablissement_id");
    expect(payloadFunction).toContain('FOR UPDATE');
    expect(payloadFunction).toContain(
      'p_payload IS DISTINCT FROM v_litige.payload_modifications',
    );
    expect(payloadFunction).toContain("accord_soignant = (v_role = 'soignant')");
    expect(payloadFunction).toContain(
      "accord_etablissement = (v_role = 'etablissement')",
    );
    expect(payloadFunction).not.toContain("statut = 'RESOLU'");

    expect(accordTrigger).toBeDefined();
    expect(accordTrigger).toContain("NEW.statut := 'REVUE_ADMIN'");
    expect(accordTrigger).toContain("NEW.statut := 'RESOLU_ACCORD_PARTIES'");
    expect(migration).toContain(
      'REVOKE UPDATE ON TABLE public.litiges FROM anon, authenticated',
    );
  });

  it('type explicitement toutes les sources de destinataires admin', () => {
    expect(migration).toContain(
      'FROM public.fn_list_admin_user_ids() AS admins(admin_user_id)',
    );
    expect(migration).toContain(
      'FROM public.fn_list_admin_user_ids() AS admins(uid)',
    );
    expect(migration).toContain(
      'COALESCE(array_agg(admin_user_id), ARRAY[]::uuid[])',
    );
    expect(migration).toContain("'LITIGE_EXEC'");
    expect(migration).toContain("'CRON_ALERTES'");
    expect(migration).not.toContain("'LITIGE_ACCORD_FINANCIER'");
    expect(migration).not.toContain("'CRON_ALERTE_ADMIN'");
  });

  it('ne contient aucune mutation directe de données de démonstration', () => {
    expect(migration).not.toMatch(/\bDELETE\s+FROM\s+public\./i);
    expect(migration).not.toMatch(/\bTRUNCATE\b/i);
    expect(migration).not.toMatch(/\best_compte_test\b/i);
    expect(migration).not.toMatch(/@jolene(?:-demo)?\./i);
  });
});
