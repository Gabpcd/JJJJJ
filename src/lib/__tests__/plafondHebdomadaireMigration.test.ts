import { readFileSync } from 'node:fs';
import { resolve } from 'node:path';
import { describe, expect, it } from 'vitest';

const migration = readFileSync(
  resolve(process.cwd(), 'supabase/migrations/20260713164254_corriger_plafond_hebdomadaire_multi_semaines.sql'),
  'utf8',
);

describe('plafond hebdomadaire multi-semaines', () => {
  it('ventile les créneaux sur chaque semaine civile Europe/Paris', () => {
    expect(migration).toContain('CREATE OR REPLACE FUNCTION public.fn_heures_mission_semaine');
    expect(migration).toContain("p_semaine_debut::timestamp AT TIME ZONE 'Europe/Paris'");
    expect(migration).toContain('least(mc.fin, b.fin_ts) - greatest(mc.debut, b.debut_ts)');
  });

  it('utilise la même ventilation dans la pré-vérification et le trigger', () => {
    expect(migration.match(/SELECT \* FROM public\.fn_semaines_mission/g)).toHaveLength(2);
    expect(migration).toContain('public.fn_heures_soignant_semaine(');
    expect(migration).not.toContain('v_heures_semaine + COALESCE(v_mission.duree_heures');
  });

  it('garde les helpers internes hors de la Data API', () => {
    expect(migration).toContain(
      'REVOKE ALL ON FUNCTION public.fn_heures_mission_semaine(uuid, date) FROM PUBLIC, anon, authenticated;',
    );
    expect(migration).toContain(
      'REVOKE ALL ON FUNCTION public.fn_semaines_mission(uuid) FROM PUBLIC, anon, authenticated;',
    );
  });

  it('refuse le repli global pour une mission multi-créneaux sans créneaux', () => {
    expect(migration).toContain('AND COALESCE(m.nb_creneaux, 0) <= 1');
  });

  it('sérialise par soignant avant la vérification du plafond', () => {
    const verrou = migration.indexOf('PERFORM pg_advisory_xact_lock(');
    const verification = migration.indexOf("IF v_choix = 'SALARIE' THEN", verrou);

    expect(verrou).toBeGreaterThan(-1);
    expect(migration).toContain("hashtextextended('jolene:attribution:' || p_soignant_id::text, 0)");
    expect(verification).toBeGreaterThan(verrou);
  });

  it('ferme le contrôle si le planning multi-créneaux est incomplet', () => {
    expect(migration.match(/PLANNING_HEBDOMADAIRE_INDISPONIBLE/g)?.length).toBeGreaterThanOrEqual(2);
    expect(migration.match(/v_nb_creneaux_valides < /g)).toHaveLength(2);

    const gardeFinalisation = migration.indexOf('v_nb_creneaux_valides < v_mission.nb_creneaux');
    const boucleFinalisation = migration.indexOf('FOR v_semaine IN', gardeFinalisation);
    expect(gardeFinalisation).toBeGreaterThan(-1);
    expect(boucleFinalisation).toBeGreaterThan(gardeFinalisation);

    const gardeTrigger = migration.indexOf('v_nb_creneaux_valides < NEW.nb_creneaux');
    const conformeTrigger = migration.indexOf("'PLAFOND_48H_HEBDO', 'CONFORME'", gardeTrigger);
    expect(conformeTrigger).toBeGreaterThan(gardeTrigger);
  });

  it('compte les pauses dans la complétude mais jamais dans les heures', () => {
    const gardesCompletude = [...migration.matchAll(/SELECT count\(\*\)::integer INTO v_nb_creneaux_valides([\s\S]*?)IF v_nb_creneaux_valides/g)]
      .map((match) => match[1]);

    expect(gardesCompletude).toHaveLength(2);
    gardesCompletude.forEach((garde) => expect(garde).not.toContain('NOT mc.est_pause'));
    expect(migration).toContain('AND NOT mc.est_pause');
  });
});
