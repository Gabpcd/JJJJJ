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
const enrichissementAnnuaire = read('supabase/functions/enrich-prospects-annuaire/index.ts');
const enrichissementCron = read('supabase/migrations/20260720171500_enrichissement_annuaire_borne.sql');
const compteursTempsReel = read('supabase/migrations/20260721101228_fix_admin_acquisition_realtime.sql');
const runtimeSourcing = read('supabase/migrations/20260721101451_fix_sourcing_runtime_watchdogs.sql');
const postgrestCache = read('supabase/migrations/20260720172000_postgrest_cache_timeout.sql');

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
    expect(rpps).toContain('"statement timeout"');
    expect(rpps).toContain('retrying: true');
    expect(rpps).toContain('2 ** reprisesTimeout');
    expect(rpps).toContain('detailsInterrompu?.fichier === FICHIER');
    expect(rpps).toContain('"connection reset"');
    expect(rpps).toContain('const HEARTBEAT_STALE_MS = 5 * 60 * 1000');
    expect(rpps).toContain('const watchdog = body.watchdog === true');
    expect(runtimeSourcing).toContain("'jolene_sourcing_rpps_watchdog'");
    expect(runtimeSourcing).toContain("body := '{\"watchdog\":true}'::jsonb");
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

  it('keeps background directory enrichment bounded on the full RPPS dataset', () => {
    expect(enrichissementAnnuaire).toContain('fn_reclamer_prospects_enrichissement');
    expect(enrichissementAnnuaire).toContain('fn_terminer_prospects_enrichissement');
    expect(enrichissementAnnuaire).toContain('avecConcurrenceBornee');
    expect(enrichissementAnnuaire).toContain('prospects,\n      6,');
    expect(enrichissementAnnuaire).toContain('SYSTEMES_FINESS_ACCEPTES');
    expect(enrichissementAnnuaire).toContain('https://finess.esante.gouv.fr');
    expect(enrichissementAnnuaire).toContain('http://finess.esante.gouv.fr');
    expect(enrichissementAnnuaire).toContain('estIdentifiantFinessExact');
    expect(enrichissementAnnuaire).toContain('correspondances.length === 1');
    expect(enrichissementAnnuaire).toContain('correspondances.length > 1');
    expect(enrichissementAnnuaire).toContain('champEstVide(prospect.email)');
    expect(enrichissementAnnuaire).toContain('champEstVide(prospect.telephone)');
    expect(enrichissementAnnuaire).not.toContain('includes("finess")');
    expect(enrichissementAnnuaire).toContain('urn:oid:1.2.250.1.71.4.2.1');
    expect(enrichissementAnnuaire).toContain('praticiensRppsExacts');
    expect(enrichissementAnnuaire).toContain('resource?.resourceType === "Practitioner"');
    expect(enrichissementAnnuaire).toContain('`${IDNPS_SYSTEM}|8${rpps}`');
    expect(enrichissementAnnuaire).toContain('telephone.replace(/\\D/g, "").length >= 9');
    expect(enrichissementAnnuaire).toContain('reste_a_traiter: resteATraiter');
    expect(enrichissementAnnuaire).not.toContain('count: "exact"');
    expect(enrichissementAnnuaire).not.toContain('.from(table).update');
    expect(compteursTempsReel).toContain('FOR UPDATE SKIP LOCKED');
    expect(compteursTempsReel).toContain('REFERENCING OLD TABLE AS old_rows NEW TABLE AS new_rows');
    expect(enrichissementCron).toContain("'enrich-prospects-etab'");
    expect(enrichissementCron).toContain("'enrich-prospects-soignant'");
    expect(runtimeSourcing).toContain("'3,13,23,33,43,53 * * * *'");
    expect(enrichissementCron).not.toContain('sales-outreach');
    expect(sales).toContain('d.reste_a_traiter');
  });

  it('uses maintained exact counters instead of national count queries', () => {
    expect(compteursTempsReel).toContain('CREATE TABLE IF NOT EXISTS public.prospection_compteurs');
    expect(compteursTempsReel).toContain('CREATE OR REPLACE FUNCTION public.fn_admin_prospection_stats()');
    expect(sales).toContain("supabase.rpc('fn_admin_prospection_stats'");
    expect(sales).toContain('Base soignants');
    expect(sales).toContain('Base établissements');
    expect(sales).toContain("return estNombreCompteur(value) ? value.toLocaleString('fr-FR') : '—'");
    expect(sales).not.toContain("count: 'exact', head: true");
    const locks = compteursTempsReel.match(/LOCK TABLE public\.prospects_soignants, public\.prospects_etablissements/g) ?? [];
    expect(locks).toHaveLength(2);
  });

  it('preserves Corsica and overseas department codes in every prospect filter', () => {
    expect(compteursTempsReel).toContain("WHEN v_departement ~ '^\\d$' THEN lpad(v_departement, 2, '0')");
    expect(runtimeSourcing).toContain("WHEN v_departement ~ '^\\d$' THEN lpad(v_departement, 2, '0')");
    expect(compteursTempsReel).not.toContain("p.departement = lpad(v_departement, 2, '0')");
    expect(runtimeSourcing).not.toContain("p.departement = lpad(v_departement, 2, '0')");
  });

  it('gives only the PostgREST cache builder a longer startup window', () => {
    expect(postgrestCache).toContain("ALTER ROLE authenticator SET statement_timeout = ''120s''");
    expect(postgrestCache).not.toMatch(/ALTER ROLE (anon|authenticated)/);
  });
});
