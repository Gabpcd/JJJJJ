import { readFileSync } from 'node:fs';
import { describe, expect, it } from 'vitest';

const read = (path: string) => readFileSync(path, 'utf8');
const migration = read('supabase/migrations/20260719165647_cockpit_lancement_et_crm_automatise.sql');
const cockpit = read('src/pages/admin/AdminCockpitLancement.tsx');
const crm = read('src/components/admin/AdminCrmAutomation.tsx');
const sales = read('src/pages/admin/AdminSales.tsx');
const outreach = read('supabase/functions/sales-outreach/index.ts');
const outreachBatch = read('supabase/functions/sales-outreach-batch/index.ts');

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
    expect(crm).toContain('L’envoi reste validé par un humain.');
  });

  it('journalise les emails existants et ouvre le CRM en premier dans Prospection', () => {
    expect(outreach).toContain('fn_crm_enregistrer_email_envoye');
    expect(outreachBatch).toContain('fn_crm_enregistrer_email_envoye');
    expect(sales).toMatch(/useState<[^>]*'crm'[^>]*>\('crm'\)/);
    expect(sales).toContain('<AdminCrmAutomation');
  });
});
