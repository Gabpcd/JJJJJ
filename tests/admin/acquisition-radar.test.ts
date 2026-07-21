import { describe, expect, it } from 'vitest';
import { readFileSync } from 'node:fs';

const read = (path: string) => readFileSync(path, 'utf8');
const migration = read('supabase/migrations/20260720150152_moteur_acquisition_radar.sql');
const strategies = read('supabase/migrations/20260720153644_acquisition_actions_strategies.sql');
const silentCrm = read('supabase/migrations/20260720155145_acquisition_crm_silencieux.sql');
const precision = read('supabase/migrations/20260720155955_acquisition_metrics_precision.sql');
const realtime = read('supabase/migrations/20260721101450_fix_acquisition_radar_realtime.sql');
const edge = read('supabase/functions/import-signaux-acquisition/index.ts');
const radar = read('src/components/admin/AdminAcquisitionRadar.tsx');
const page = read('src/pages/admin/AdminAcquisition.tsx');
const config = read('supabase/config.toml');

describe('moteur acquisition silencieux', () => {
  it('separe annuaires, signaux, territoires, actions et depenses', () => {
    for (const table of [
      'acquisition_sources',
      'acquisition_signaux',
      'acquisition_territoires',
      'acquisition_actions',
      'acquisition_depenses',
    ]) {
      expect(migration).toContain(`CREATE TABLE IF NOT EXISTS public.${table}`);
      expect(migration).toContain(`ALTER TABLE public.${table} ENABLE ROW LEVEL SECURITY`);
      expect(migration).toContain(`REVOKE ALL ON TABLE public.${table} FROM PUBLIC, anon`);
    }
    expect(migration).toContain('fn_admin_acquisition_radar');
    expect(migration).toContain('fn_admin_acquisition_enregistrer_depense');
    expect(page).toContain('<AdminAcquisitionRadar />');
    expect(page).toContain('fn_admin_acquisition_enregistrer_depense');
  });

  it('ne transforme jamais une decouverte en contact automatique', () => {
    expect(migration).toContain("'automatisations_marketing_actives', 'false'");
    expect(migration).toContain("sequence_active, prochaine_action_le");
    expect(migration).toMatch(/false, NULL, 0, false/);
    expect(silentCrm).toContain('SET sequence_active = false');
    expect(silentCrm).toContain('prochaine_action_le = NULL');
    expect(silentCrm).toContain("'contact_automatique', false");
    expect(migration).toContain("statut text NOT NULL DEFAULT 'BROUILLON'");
    expect(migration).toContain("'contact_automatique', false");
    expect(migration).not.toMatch(/net\.http|resend\.com|send-email|send-sms|sales-outreach/i);
    expect(edge).toContain('contacted: 0');
    expect(edge).toContain('contact_automatique: false');
    expect(edge).not.toMatch(/send-email|send-sms|sales-outreach|resend\.com/i);
    expect(radar).toContain('0 contact auto');
    expect(radar).toContain('CRM silencieux');
  });

  it('importe la demande France Travail avec habilitation explicite', () => {
    expect(edge).toContain('FRANCE_TRAVAIL_CLIENT_ID');
    expect(edge).toContain('FRANCE_TRAVAIL_CLIENT_SECRET');
    expect(edge).toContain('api_offresdemploiv2 o2dsoffre');
    expect(edge).toContain('api.francetravail.io/partenaire/offresdemploi/v2/offres/search');
    expect(edge).toContain('data.gouv.fr/dataservices/api-offres-demploi');
    expect(edge).toContain('Habilitation ou secrets France Travail manquants');
    expect(config).toContain('[functions.import-signaux-acquisition]');
    expect(config).toMatch(/\[functions\.import-signaux-acquisition\]\s+verify_jwt = false/);
  });

  it('mappe les professions exigees par les missions et non un diplome de profil', () => {
    for (const profession of [
      'IDE', 'AS', 'AES', 'AUXILIAIRE_PUERICULTURE', 'IBODE', 'IADE',
      'SAGE_FEMME', 'KINE', 'MEDECIN', 'DENTISTE', 'PHARMACIEN',
      'MANIPULATEUR_RADIO', 'PREPARATEUR_PHARMA', 'DIETETICIEN',
      'ERGOTHERAPEUTE', 'PSYCHOMOTRICIEN', 'ORTHOPHONISTE',
    ]) {
      expect(edge).toContain(`return "${profession}"`);
    }
    expect(migration).toContain('m.profession_requise::text AS profession');
    expect(radar).toContain('La profession est celle demandée par la mission');
  });

  it('rend explicites liquidite, comptes ancres, recurrence et hypothese de revenu', () => {
    expect(migration).toContain("'disponibles_14j'");
    expect(migration).toContain("'ancres'");
    expect(migration).toContain("'recurrence'");
    expect(migration).toContain("'estimation, pas revenu garanti'");
    expect(radar).toContain('Liquidité locale');
    expect(radar).toContain('Comptes ancres');
    expect(radar).toContain('Récurrence et pipeline estimé');
    expect(radar).toContain('Reverse marketplace');
    expect(radar).toContain('revenu_mensuel_estime_ht');
    expect(radar).toContain('Ces montants ne sont pas des revenus garantis');
    expect(precision).toContain('count(DISTINCT s.id) FILTER (WHERE s.tous_documents_valides)');
    expect(precision).toContain("'employeur non communique'");
    expect(precision).toContain('WHERE s.cible_id IS NOT NULL');
    expect(realtime).toContain('demande_interne AS');
    expect(realtime).toContain('commission_observee_mensuelle_ht');
    expect(realtime).toContain('NULLIF(m.montant_commission_ht, 0)');
    expect(realtime).toContain("FILTER (WHERE m.statut = 'TERMINEE')");
    expect(realtime).toContain("FILTER (WHERE m.statut IN ('ASSIGNEE', 'EN_COURS'))");
    expect(realtime).toContain('commission_pipeline_mensuelle_ht');
    expect(realtime).toContain("'commission_observee', 'missions terminees uniquement'");
    expect(realtime).toContain("'pipeline_interne', 'missions assignees ou en cours, distinctes du realise'");
    expect(realtime).toContain('COALESCE(di.commission_pipeline_ht, 0) / GREATEST(v_jours, 1) * 30');
    expect(realtime).not.toContain("FILTER (WHERE m.statut <> 'OUVERTE')");
    expect(realtime).toContain('AND s.etablissement_id IS NULL');
    expect(realtime).toContain("AND v_scope <> 'TEST'");
    expect(realtime).toContain("FROM public.acquisition_territoires WHERE v_scope <> 'TEST'");
    expect(realtime).toContain("LEFT JOIN public.acquisition_territoires t ON v_scope <> 'TEST'");
    expect(realtime).toContain("'scope_test', 'missions, etablissements et soignants de test uniquement; signaux externes et territoires non scopes exclus'");
    expect(realtime).toContain("'contact_automatique', false");
    expect(radar).toContain('actualisation toutes les 60 s');
    expect(radar).toContain('Besoins détectés');
  });

  it('prepare toutes les strategies commerciales sans executer de campagne', () => {
    for (const type of [
      'COMPTE_ANCRE',
      'RENFORCER_VIVIER',
      'REVERSE_MARKETPLACE',
      'RECURRENCE',
      'CIBLER_GROUPE',
      'PARTENARIAT_ECOLE',
      'QUALIFIER_SIGNAL',
    ]) {
      expect(strategies).toContain(`'${type}'`);
    }
    expect(strategies).toContain("'statut', 'BROUILLON'");
    expect(strategies).toContain("'contact_automatique', false");
    expect(strategies).not.toMatch(/net\.http|resend\.com|send-email|send-sms|sales-outreach/i);
    expect(strategies).toContain('NULLIF(m.net_a_payer, 0)');
  });
});
