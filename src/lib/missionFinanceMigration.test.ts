import { readFileSync } from 'node:fs';
import { resolve } from 'node:path';
import { describe, expect, it } from 'vitest';

const migration = readFileSync(
  resolve(process.cwd(), 'supabase/migrations/20260714000629_unifier_calcul_financier_mission.sql'),
  'utf8',
);
const backfill = readFileSync(
  resolve(process.cwd(), 'supabase/migrations/20260714005500_recalculer_finances_missions_legacy_ciblees.sql'),
  'utf8',
);

describe('migration du calcul financier des missions', () => {
  it('supprime le second moteur qui écrasait le calcul canonique', () => {
    expect(migration).toContain('DROP TRIGGER IF EXISTS trg_calculer_financier');
    expect(migration).toContain('DROP FUNCTION IF EXISTS public.fn_calculer_financier_mission()');
    expect(migration).toContain("t.tgname = 'dec_mission_z_finance'");
  });

  it('calcule le plafond depuis la profession de la mission, jamais le diplôme du profil', () => {
    expect(migration).toContain('rp.profession = NEW.profession_requise');
    expect(migration).not.toMatch(/SELECT\s+profession\s+INTO[\s\S]*FROM\s+public\.soignants/i);
  });

  it('respecte le régime réellement appliqué après attribution', () => {
    expect(migration).toContain('NEW.type_contrat_applique::text');
    expect(migration).toContain("v_regime_effectif IS DISTINCT FROM 'SALARIE'");
    expect(migration).toContain("rp.type_contrat IN ('CDD', 'SALARIE', 'VACATION')");
  });

  it('recalcule uniquement les anciens plafonds impossibles sans triggers métier', () => {
    expect(backfill).toContain('LOCK TABLE public.missions IN ACCESS EXCLUSIVE MODE');
    expect(backfill).toContain('CREATE TEMP TABLE missions_finance_legacy_a_recalculer');
    expect(backfill).toContain('m.rist_plafond_applique IS TRUE');
    expect(backfill).toContain('m.soignant_assigne_id IS NULL');
    expect(backfill).toContain('ENABLE ALWAYS TRIGGER dec_mission_plafond_rist');
    expect(backfill).toContain('ENABLE ALWAYS TRIGGER dec_mission_z_finance');
    expect(backfill).toContain('ENABLE ALWAYS TRIGGER dec_net_estime');
    expect(backfill).toContain('SET LOCAL session_replication_role = replica');
    expect(backfill).toContain('SET LOCAL session_replication_role = origin');
    expect(backfill).toContain('ENABLE TRIGGER dec_mission_plafond_rist');
    expect(backfill).toContain('ENABLE TRIGGER dec_mission_z_finance');
    expect(backfill).toContain('ENABLE TRIGGER dec_net_estime');
    expect(backfill).toContain('SET taux_horaire_base = m.taux_horaire_base');
    expect(backfill).not.toMatch(/\b(?:DELETE|TRUNCATE)\b/i);
  });
});
