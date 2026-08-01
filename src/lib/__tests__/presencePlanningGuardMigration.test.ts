import { readFileSync } from 'node:fs';
import { describe, expect, it } from 'vitest';

const migration = readFileSync(
  'supabase/migrations/20260801130000_securiser_validation_presences_planning_exact.sql',
  'utf8',
);

describe('garde serveur de validation des présences', () => {
  it('couvre toute transition de présence vers validée', () => {
    expect(migration).toContain('BEFORE UPDATE OF valide_par_etablissement');
    expect(migration).toContain('OLD.valide_par_etablissement IS DISTINCT FROM TRUE');
    expect(migration).toContain('NEW.valide_par_etablissement IS TRUE');
  });

  it('attend le dernier prévisionnel et refuse un effectif ouvert', () => {
    expect(migration).toContain("mc.type_creneau = 'PREVISIONNEL'");
    expect(migration).toContain('mc.fin > pg_catalog.statement_timestamp()');
    expect(migration).toContain("mc.type_creneau = 'EFFECTIF'");
    expect(migration).toContain('AND mc.fin IS NULL');
    expect(migration).toContain('Aucun pointage terminé');
  });

  it('limite le repli legacy aux missions ponctuelles de 24 heures', () => {
    expect(migration).toContain("v_mission.fin_le > v_mission.debut_le + interval '24 hours'");
    expect(migration).toContain('Le planning détaillé doit être terminé');
  });
});
