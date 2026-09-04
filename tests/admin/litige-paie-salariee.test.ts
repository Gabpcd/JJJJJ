import { readFileSync } from 'node:fs';
import { join } from 'node:path';
import { describe, expect, it } from 'vitest';

const migration = readFileSync(
  join(process.cwd(), 'supabase/migrations/20260903203000_resoudre_litiges_paie_salariee.sql'),
  'utf8',
);

describe('résolution admin des litiges de paie salariée', () => {
  it('route le salariat hors du circuit des factures honoraires', () => {
    expect(migration).toContain("type_contrat_applique::text, '') = 'SALARIE'");
    expect(migration).toContain('fn_admin_resoudre_litige_salarie');
    expect(migration).toContain('RECTIFICATION_PAIE_SALARIEE');
  });

  it('préserve le document précédent et crée un rectificatif lié au litige', () => {
    expect(migration).toContain("SET statut = 'ANNULE'");
    expect(migration).toContain('bulletin_precedent_id');
    expect(migration).toContain("'RECTIFICATIF'");
    expect(migration).toContain('bulletins_paie_unique_actif_mission');
  });

  it('recalcule les cotisations et la commission à partir des heures arbitrées', () => {
    expect(migration).toContain("set_config('jolene.heures_litige_override'");
    expect(migration).toContain("set_config('jolene.admin_override_gel', v_mission.id::text");
    expect(migration).toContain('DROP TRIGGER IF EXISTS trg_calculer_financier');
    expect(migration).toContain('CREATE TRIGGER zzzz_calculer_financier');
    expect(migration).toContain(
      'ROUND((v_total_brut + NEW.montant_ifm) * v_taux_icp, 2)',
    );
    expect(migration).toContain('fn_calculer_cotisations(v_mission.id)');
    expect(migration).toContain('v_commission_delta_ht');
    expect(migration).toContain('FACTURE_COMPLEMENTAIRE');
  });

  it('ne réclame aucune double authentification à l’administratrice', () => {
    expect(migration).toContain('public.est_admin() IS NOT TRUE');
    expect(migration).not.toContain('aal2');
    expect(migration).not.toContain('AAL2');
  });

  it('ne réécrit pas un paiement déjà confirmé et expose la régularisation', () => {
    expect(migration).toContain('v_regularisation_paiement');
    expect(migration).toContain("ps.statut IN ('CONFIRME', 'RESOLU')");
    expect(migration).toContain("'regularisation_paiement_requise'");
    expect(migration).not.toContain('UPDATE public.paiements_soignant');
  });
});
