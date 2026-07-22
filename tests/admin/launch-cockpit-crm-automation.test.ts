import { readFileSync } from 'node:fs';
import { describe, expect, it } from 'vitest';

const read = (path: string) => readFileSync(path, 'utf8');
const migration = read('supabase/migrations/20260719165647_cockpit_lancement_et_crm_automatise.sql');
const cockpit = read('src/pages/admin/AdminCockpitLancement.tsx');
const crm = read('src/components/admin/AdminCrmAutomation.tsx');
const sales = read('src/pages/admin/AdminSales.tsx');
const outreach = read('supabase/functions/sales-outreach/index.ts');
const outreachBatch = read('supabase/functions/sales-outreach-batch/index.ts');
const stopGuard = read('supabase/migrations/20260722134000_sales_outreach_stop_guard.sql');

describe('Cockpit de lancement et CRM automatisé', () => {
  it('sépare explicitement le réel, le test et la vue combinée sans supprimer les démos', () => {
    expect(migration).toContain("v_scope NOT IN ('REEL', 'TEST', 'TOUS')");
    expect(migration).toContain("v_scope = 'TEST' AND s.est_compte_test");
    expect(migration).toContain("v_scope = 'REEL' AND NOT s.est_compte_test");
    expect(migration).toContain("v_scope = 'TEST' AND e.est_compte_test");
    expect(migration).toContain("v_scope = 'REEL' AND NOT e.est_compte_test");
    expect(migration).not.toMatch(/delete\s+from\s+public\.(soignants|etablissements|missions)/i);
    expect(cockpit).toContain("useState<ScopeDonnees>('REEL')");
    expect(cockpit).toContain('Profession requise par la mission');
  });

  it('protège les tâches et le journal CRM par RLS et par privilèges', () => {
    expect(migration).toContain('CREATE TABLE IF NOT EXISTS public.sales_taches');
    expect(migration).toContain('CREATE TABLE IF NOT EXISTS public.sales_activites');
    expect(migration).toContain('ALTER TABLE public.sales_taches ENABLE ROW LEVEL SECURITY');
    expect(migration).toContain('ALTER TABLE public.sales_activites ENABLE ROW LEVEL SECURITY');
    expect(migration).toContain('REVOKE ALL ON TABLE public.sales_taches FROM PUBLIC, anon');
    expect(migration).toContain('REVOKE ALL ON TABLE public.sales_activites FROM PUBLIC, anon');
    expect(migration).toContain('USING (public.est_admin())');
    expect(migration).toContain('WITH CHECK (public.est_admin())');
  });

  it('automatise la planification de manière idempotente tout en respectant STOP', () => {
    expect(migration).toContain('CREATE OR REPLACE FUNCTION public.fn_crm_generer_taches()');
    expect(migration).toContain('c.ne_plus_contacter IS FALSE');
    expect(migration).toContain("ne_plus_contacter = p_resultat IN ('PAS_INTERESSE', 'STOP')");
    expect(migration).toContain("WHEN p_resultat = 'INSCRIT' THEN 'INSCRIT'");
    expect(migration).toContain("WHEN p_resultat = 'INTERESSE' THEN COALESCE(p_prochaine_action_le, now() + interval '1 day')");
    expect(migration).not.toContain("WHEN p_resultat IN ('INTERESSE', 'INSCRIT') THEN 'INSCRIT'");
    expect(migration).toContain("WHERE jobname = 'jolene_crm_generer_taches'");
    expect(migration).toContain('PERFORM cron.unschedule(v_job.jobid)');
    expect(migration).toContain('$job$SELECT public.fn_crm_generer_taches();$job$');
    expect(migration).not.toMatch(/net\.http|resend\.com|api\.resend/i);
    expect(crm).toContain('Depuis cet écran, aucun appel, email ou message n’est envoyé sans une action humaine explicite.');
  });

  it('journalise les emails existants et garde le CRM accessible après le sourcing', () => {
    expect(outreach).toContain('fn_crm_enregistrer_email_envoye');
    expect(outreachBatch).toContain('fn_crm_enregistrer_email_envoye');
    expect(outreachBatch).toContain('verifyAdminOrServiceRole');
    expect(outreachBatch).toContain('automatisations_marketing_actives');
    expect(outreachBatch).toContain('PRELANCEMENT_AUTOMATISATIONS_MARKETING_DESACTIVEES');
    expect(outreachBatch.indexOf('automatisations_marketing_actives')).toBeLessThan(outreachBatch.indexOf('https://api.resend.com/emails'));
    expect(sales).toContain("type SalesTab = 'sourcing' | 'crm'");
    expect(sales).toContain("const tab: SalesTab = estSalesTab(tabParam) ? tabParam : 'sourcing'");
    expect(sales).toContain('Cibles prioritaires');
    expect(sales).toContain('Actions du jour');
    expect(sales).toContain('<AdminCrmAutomation');
  });

  it('bloque STOP et OPPOSITION avant tout appel à Resend', () => {
    expect(stopGuard).toContain('fn_sales_outreach_est_interdit');
    expect(stopGuard).toContain('ne_plus_contacter');
    expect(stopGuard).toContain("c.statut = 'PERDU'");
    expect(stopGuard).toContain("p.statut_sourcing = 'OPPOSITION'");
    expect(stopGuard).toContain('lower(btrim(c.email))');
    expect(stopGuard).toContain('regexp_replace');
    expect(stopGuard).toContain('FROM PUBLIC, anon, authenticated');
    expect(stopGuard).toContain('TO service_role');
    expect(stopGuard).toContain('CREATE OR REPLACE FUNCTION public.fn_admin_crm_tableau');
    expect(stopGuard).toContain('AND sc.ne_plus_contacter IS FALSE');
    expect(stopGuard).toContain("AND sc.statut <> 'PERDU'");

    for (const source of [outreach, outreachBatch]) {
      expect(source).toContain('fn_sales_outreach_est_interdit');
      expect(source.indexOf('fn_sales_outreach_est_interdit'))
        .toBeLessThan(source.indexOf('https://api.resend.com/emails'));
      expect(source).toContain('CONTACT_INTERDIT_STOP');
    }
  });

  it('réserve les annuaires à la qualification et bloque les actions d’un contact STOP', () => {
    expect(sales).toContain("'a_rappeler', 'ne_plus_contacter'");
    expect(sales).toContain('Qualification interne uniquement');
    expect(sales).toContain('Ajouter aux prospects');
    expect(sales).toContain('Contact bloqué.');
    expect(sales).toContain('disabled={c.ne_plus_contacter}');
    expect(crm).toContain('ne_plus_contacter: boolean');
    expect(crm).toContain('!contactCrmBloque(tache)');
    expect(crm).toContain('Contact bloqué — aucune action ni prise de contact autorisée.');
  });
});
