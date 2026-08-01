import { readFileSync } from 'node:fs';
import { join } from 'node:path';
import { describe, expect, it } from 'vitest';

const migrationPath =
  'supabase/migrations/20260801205804_reparer_missions_test_et_stats_rh_planning_exact.sql';
const migration = readFileSync(join(process.cwd(), migrationPath), 'utf8');
const repair = migration.slice(
  migration.indexOf('DO $reparer_missions_test$'),
  migration.indexOf(
    'CREATE OR REPLACE FUNCTION public.fn_stats_rh_etablissement()',
  ),
);
const rhFunction = migration.slice(
  migration.indexOf(
    'CREATE OR REPLACE FUNCTION public.fn_stats_rh_etablissement()',
  ),
  migration.indexOf(
    'REVOKE ALL ON FUNCTION public.fn_stats_rh_etablissement()',
  ),
);
const assertions = migration.slice(migration.indexOf('DO $assertions$'));

describe('rattrapage mission test et prévisionnel RH exact', () => {
  it('borne le rattrapage aux deux parties explicitement test', () => {
    expect(repair).toContain('e.est_compte_test IS TRUE');
    expect(repair).toContain('s.est_compte_test IS TRUE');
    expect(repair).toContain('sc.est_compte_test IS DISTINCT FROM TRUE');
    expect(repair).toContain('sp.est_compte_test IS DISTINCT FROM TRUE');
    expect(repair).toContain('ss.est_compte_test IS DISTINCT FROM TRUE');
    expect(repair).toContain('s_lie.est_compte_test IS DISTINCT FROM TRUE');
    expect(repair).toContain("m.statut IN ('ASSIGNEE', 'EN_COURS')");
    expect(repair).not.toMatch(
      /(?:UPDATE|DELETE FROM)\s+public\.(?:etablissements|soignants|missions)\b/i,
    );
  });

  it('répare le contrat absent de façon idempotente et inclut la fixture signalée', () => {
    expect(migration).toContain(
      "'0f180010-0000-4000-8000-000000000001'::uuid",
    );
    expect(repair).toContain('INSERT INTO public.contrats_mission');
    expect(repair).toContain('public.fn_generer_numero_contrat_safe(');
    expect(repair).toContain('FROM public.templates_contrat tc');
    expect(repair).toContain("tc.est_actif IS TRUE");
    expect(repair).toContain('public.fn_html_escape(');
    expect(repair).toContain("'{{numero_contrat}}'");
    expect(repair).toContain("'EN_ATTENTE_SIGNATURES'");
    expect(repair).toContain("cm.statut NOT IN ('ANNULE', 'EXPIRE')");
    expect(repair).toContain(
      "NULLIF(pg_catalog.btrim(cm.contenu_html), '') IS NOT NULL",
    );
    expect(repair).not.toContain("'TEST-RATTRAPAGE-'");
    expect(repair).not.toMatch(/\bNULL\s*,\s*'EN_ATTENTE_SIGNATURES'/);
  });

  it('ne neutralise que les EFFECTIF sans preuve et sans finance', () => {
    expect(repair).toContain('DELETE FROM public.mission_creneaux mc');
    expect(repair).toContain("mc.type_creneau = 'EFFECTIF'");
    expect(repair).toContain('scan.creneau_effectif_id = mc.id');
    expect(repair).toContain('p.pointage_arrivee_le IS NOT NULL');
    expect(repair).toContain('p.pointage_depart_le IS NOT NULL');
    expect(repair).toContain('FROM public.factures f');
    expect(repair).toContain('FROM public.factures_honoraires fh');
    expect(assertions).toContain('FROM public.factures f');
    expect(assertions).toContain('FROM public.factures_honoraires fh');
    expect(migration).toContain('unproven_effective_slots_deleted');
    expect(migration).not.toContain('orphan_effective_slots_deleted');
    expect(repair).not.toMatch(/(?:UPDATE|DELETE FROM)\s+public\.factures\b/i);
    expect(repair).not.toMatch(
      /(?:UPDATE|DELETE FROM)\s+public\.factures_honoraires\b/i,
    );
  });

  it('calcule le futur depuis les créneaux exacts pour ASSIGNEE et EN_COURS', () => {
    expect(rhFunction).toContain('planning_total AS');
    expect(rhFunction).toContain('planning_futur AS');
    expect(rhFunction).toContain('planning_confirme AS');
    expect(rhFunction).toContain("mc.type_creneau = 'PREVISIONNEL'");
    expect(rhFunction).toContain('mc.debut >= v_now');
    expect(rhFunction).toContain(
      "WHERE statut IN ('ASSIGNEE', 'EN_COURS')",
    );
    expect(rhFunction).toContain(
      '* heures_futures / NULLIF(heures_totales, 0)',
    );
    expect(rhFunction).toContain("'heures_prevues'");
    expect(rhFunction).not.toContain(
      "'assignees_total', (SELECT COUNT(*) FROM missions",
    );
  });

  it('calcule les heures terminées depuis EFFECTIF, sinon PREVISIONNEL', () => {
    expect(rhFunction).toContain('WITH heures_terminees_exactes AS');
    expect(rhFunction).toContain("mc.type_creneau = 'EFFECTIF'");
    expect(rhFunction).toContain("mc.type_creneau = 'PREVISIONNEL'");
    expect(rhFunction).toContain(
      "effectif.type_creneau = 'EFFECTIF'",
    );
    expect(rhFunction).toContain('SELECT pg_catalog.sum(hte.heures)');
    expect(rhFunction).toContain('COALESCE(hte.heures, 0) AS heures');
    expect(rhFunction).not.toContain('(fin_le - debut_le)');
    expect(rhFunction).not.toContain('(m.fin_le - m.debut_le)');
  });

  it('conserve le cloisonnement SECURITY DEFINER et l’inventaire', () => {
    expect(rhFunction).toContain('SECURITY DEFINER');
    expect(rhFunction).toContain("SET search_path TO ''");
    expect(migration).toContain(
      'REVOKE ALL ON FUNCTION public.fn_stats_rh_etablissement()',
    );
    expect(migration).toContain('FROM PUBLIC, anon');
    expect(migration).toContain('TO authenticated, service_role');
    expect(migration).toContain(
      "WHERE signature = 'fn_stats_rh_etablissement()'",
    );
    expect(migration).not.toContain('__FN_STATS_RH_MD5__');
  });
});
