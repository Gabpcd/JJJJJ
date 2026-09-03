import { readFileSync } from 'node:fs';
import { describe, expect, it } from 'vitest';

const generator = readFileSync(
  'supabase/functions/generate-contrat-mission-pdf/index.ts',
  'utf8',
);
const migration = readFileSync(
  'supabase/migrations/20260903191000_corriger_rendu_contrats_timezone_signature.sql',
  'utf8',
);

describe('rendu contractuel France', () => {
  it('formate les instants et la date de signature dans le fuseau métier', () => {
    expect(generator).toContain("const BUSINESS_TIME_ZONE = 'Europe/Paris'");
    // début, fin et date de signature doivent tous être rendus dans le même
    // fuseau métier ; un comptage exact empêche qu'un des trois régresse.
    expect(generator.match(/timeZone: BUSINESS_TIME_ZONE/g)).toHaveLength(3);
  });

  it('accorde la période d’essai sans produire « 1 jours »', () => {
    expect(generator).toContain("periodeEssaiJours === 1 ? 'jour' : 'jours'");
    expect(generator).toContain('periode_essai_libelle: escapeHtml(periodeEssaiLibelle)');
    expect(migration).toContain("'{{periode_essai_libelle}}'");
  });

  it('reste exact quel que soit le mode de signature choisi', () => {
    expect(migration).toContain('en deux exemplaires signés électroniquement dans Jolene');
    expect(migration).not.toContain("SET contenu_html = 'en deux exemplaires électroniques signés via OTP SMS Jolene'");
  });
});
