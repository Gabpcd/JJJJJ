import { describe, expect, it } from 'vitest';
import { readFileSync } from 'node:fs';
import { resolve } from 'node:path';

const read = (path: string) => readFileSync(resolve(process.cwd(), path), 'utf8');

const migration = read('supabase/migrations/20260720112022_sourcing_officiel_et_priorisation.sql');
const rpps = read('supabase/functions/import-annuaire-rpps/index.ts');
const finess = read('supabase/functions/import-finess/index.ts');
const cockpit = read('src/components/admin/AdminSourcingCockpit.tsx');
const sales = read('src/pages/admin/AdminSales.tsx');
const relanceInactifs = read('supabase/functions/relance-inactifs/index.ts');
const digestHebdo = read('supabase/functions/digest-hebdo/index.ts');
const avisParrainage = read('supabase/functions/avis-parrainage/index.ts');

describe('sourcing acquisition silencieux', () => {
  it('uses current official directories instead of the deprecated CNAM export', () => {
    expect(rpps).toContain('annuaire-sante-extractions-des-donnees-en-libre-acces');
    expect(rpps).toContain('ANNUAIRE_SANTE_RPPS');
    expect(rpps).toContain('PS_LibreAcces_Personne_activite');
    expect(rpps).not.toContain('annuaire-sante-de-la-cnam-deprecie');
    expect(finess).toContain('finess_etablissements.csv');
    expect(finess).toContain('FINESS_DATA_GOUV');
    expect(finess).not.toContain('2ce43ade-8d2c-4d1d-81da-ca06c82abc68');
    expect(rpps).toContain('const TAILLE_UPSERT = 25');
    expect(rpps).toContain('const BUDGET_MS = 20_000');
    expect(finess).toContain('const TAILLE_UPSERT = 100');
  });

  it('covers mission professions and retains stable official identifiers', () => {
    for (const profession of [
      'IDE', 'AS', 'AES', 'AUXILIAIRE_PUERICULTURE', 'IBODE', 'IADE',
      'SAGE_FEMME', 'KINE', 'MEDECIN', 'DENTISTE', 'PHARMACIEN',
      'MANIPULATEUR_RADIO', 'PREPARATEUR_PHARMA', 'DIETETICIEN',
      'ERGOTHERAPEUTE', 'PSYCHOMOTRICIEN', 'ORTHOPHONISTE',
    ]) {
      expect(rpps).toContain(`return "${profession}"`);
    }
    expect(migration).toContain('ADD COLUMN IF NOT EXISTS numero_rpps text');
    expect(migration).toContain('ADD COLUMN IF NOT EXISTS finess_structure text');
    expect(migration).toContain('uq_sales_contacts_source_prospect');
    expect(migration).not.toMatch(/UPDATE public\.prospects_(soignants|etablissements)[\s\S]*SET source_maj_le/);
  });

  it('never turns discovery into automatic outreach', () => {
    expect(migration).toContain('sequence_active, prochaine_action_le');
    expect(migration).toMatch(/p_score,\s*false, NULL/);
    expect(migration).toContain("'sequence_active', false");
    expect(cockpit).toContain('Aucun envoi automatique');
    expect(cockpit).toContain('sans séquence de contact active');
    expect(cockpit).toContain("fn_sourcing_lancer_import");
    expect(migration).toContain("'automatisations_marketing_actives', 'false'");
    for (const campagne of [relanceInactifs, digestHebdo, avisParrainage]) {
      expect(campagne).toContain('automatisations_marketing_actives');
      expect(campagne).toContain('PRELANCEMENT_AUTOMATISATIONS_MARKETING_DESACTIVEES');
      expect(campagne).toContain('envoyes: 0');
    }
    for (const source of [rpps, finess, cockpit]) {
      expect(source).not.toContain('sales-outreach');
      expect(source).not.toContain('sales-outreach-batch');
    }
  });

  it('makes acquisition the first admin sales view with dedupe and demand scoring', () => {
    expect(sales).toContain(">('sourcing')");
    expect(sales).toContain('<AdminSourcingCockpit');
    expect(cockpit).toContain('Exclure CRM + inscrits');
    expect(cockpit).toContain('Nouveaux depuis 30 jours');
    expect(migration).toContain('missions_ouvertes');
    expect(migration).toContain('deja_inscrit');
    expect(migration).toContain('deja_crm');
    expect(migration).toContain("'jolene_sourcing_rpps_hebdo'");
    expect(migration).toContain("'jolene_sourcing_finess_hebdo'");
    expect(migration).toContain("'silencieux', true");
  });
});
