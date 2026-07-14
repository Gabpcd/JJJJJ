import { readFileSync } from 'node:fs';
import { describe, expect, it } from 'vitest';

const migration = readFileSync(
  'supabase/migrations/20260714070000_corriger_moyenne_44h_12_semaines.sql',
  'utf8',
);

describe('moyenne salariée de 44 h sur 12 semaines glissantes', () => {
  it('résout le régime depuis la mission et exclut explicitement le libéral', () => {
    expect(migration).toContain('NEW.type_contrat_applique::text');
    expect(migration).toContain('NEW.choix_contrat_soignant');
    expect(migration).toContain("IF v_regime = 'LIBERAL' THEN");
    expect(migration).not.toMatch(/type_exercice\s*=\s*'LIBERAL'/);
  });

  it('ventile la mission par semaine réelle et contrôle toutes les fenêtres affectées', () => {
    expect(migration.match(/public\.fn_semaines_mission\(NEW\.id\)/g)?.length).toBeGreaterThanOrEqual(2);
    expect(migration).toContain('CROSS JOIN generate_series(0, 11) AS offsets(n)');
    expect(migration).toContain('public.fn_heures_soignant_semaine(');
    expect(migration).toContain('v_heures_total / 12.0');
    expect(migration).toContain('v_fin_fenetre - 77');
  });

  it('sérialise les attributions et borne les heures externes déclarées', () => {
    expect(migration).toContain("hashtextextended('jolene:attribution:'");
    expect(migration).toContain('heures_salarie BETWEEN 0 AND 168');
    expect(migration).toContain("CHECK (semaine_du = date_trunc('week', semaine_du)::date)");
    expect(migration).toContain('attestation_honneur IS TRUE');
    expect(migration).toContain('CREATE TRIGGER trg_00_verrouiller_attestation_temps_travail');
    expect(migration).toContain('CREATE TRIGGER trg_90_alerter_attestation_temps_travail');
    expect(migration).toContain('UPDATE OF soignant_id, semaine_du, heures_salarie');
    expect(migration).toContain('OLD.soignant_id IS DISTINCT FROM NEW.soignant_id');
    expect(migration).toContain("'jolene:attribution:' || OLD.soignant_id::text");
    expect(migration).toContain("'VIOLATION_ALERTEE'");
    expect(migration).toContain("'REVUE_HUMAINE_MISSION_DEJA_AFFECTEE'");
  });

  it('exécute la vérification après mise à jour pour lire le planning projeté', () => {
    expect(migration).toContain('DROP TRIGGER IF EXISTS trg_dec_verifier_moyenne_44h_before_update');
    expect(migration).toContain('CREATE TRIGGER trg_dec_verifier_moyenne_44h_after_update');
    expect(migration).toContain('AFTER UPDATE OF');
    expect(migration).toContain('DROP TRIGGER IF EXISTS dec_mission_plafond_48h_before_update');
    expect(migration).toContain('CREATE TRIGGER dec_mission_plafond_48h_after_update');
    expect(migration).toContain('CREATE TRIGGER trg_95_alerter_temps_travail_effectif');
    expect(migration).toContain("NEW.statut <> 'TERMINEE'");
    expect(migration).toContain("'HEURES_EFFECTIVES_TERMINEES'");
    expect(migration).toContain("'REVUE_HUMAINE_FAIT_ACCOMPLI'");
  });
});
