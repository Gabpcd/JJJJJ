import { readFileSync } from 'node:fs';
import { join } from 'node:path';
import { describe, expect, it } from 'vitest';

const migration = readFileSync(
  join(process.cwd(), 'supabase/migrations/20260713222000_durcir_verifications_preproduction.sql'),
  'utf8',
);

const finaliserInscription = readFileSync(
  join(process.cwd(), 'src/pages/FinaliserInscriptionEtab.tsx'),
  'utf8',
);

const contratTravail = readFileSync(
  join(process.cwd(), 'src/components/BlocContratTravailMission.tsx'),
  'utf8',
);

describe('preuves documentaires immuables dans Storage', () => {
  it('retire toute politique client permettant de réécrire ou supprimer une preuve', () => {
    expect(migration).toContain('DROP POLICY IF EXISTS pol_storage_jolene_update');
    expect(migration).toContain('DROP POLICY IF EXISTS pol_storage_jolene_delete');
    expect(migration).not.toMatch(/CREATE POLICY pol_storage_jolene_update/i);
    expect(migration).not.toMatch(/CREATE POLICY pol_storage_jolene_delete/i);
  });

  it('conserve uniquement les capacités client nécessaires au dépôt et à la lecture', () => {
    expect(migration).toMatch(/CREATE POLICY pol_storage_jolene_insert[\s\S]*FOR INSERT TO authenticated/i);
    expect(migration).toMatch(/CREATE POLICY pol_storage_jolene_select[\s\S]*FOR SELECT TO authenticated/i);
  });

  it('versionne chaque RIB établissement sans jamais écraser une preuve existante', () => {
    expect(finaliserInscription).toContain('rib-etablissement-${Date.now()}-${globalThis.crypto.randomUUID()}');
    expect(finaliserInscription).toMatch(/\.upload\(path, ribFile, \{ upsert: false,/);
    expect(finaliserInscription).not.toMatch(/rib\.[^`]*`[\s\S]{0,200}upsert:\s*true/);
  });

  it('versionne chaque contrat de travail mission sans upsert Storage', () => {
    expect(contratTravail).toContain('${Date.now()}-${globalThis.crypto.randomUUID()}-contrat.pdf');
    expect(contratTravail).toMatch(/\.upload\(path, file, \{ upsert: false,/);
    expect(contratTravail).not.toContain('contrats-travail/${missionId}/contrat.pdf');
  });
});
