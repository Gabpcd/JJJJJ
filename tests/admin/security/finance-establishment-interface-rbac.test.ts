import { createHash } from 'node:crypto';
import { readFileSync } from 'node:fs';
import { describe, expect, it } from 'vitest';

const read = (path: string) => readFileSync(path, 'utf8');
const migration = read('supabase/migrations/20260801180304_securiser_finances_etablissement.sql');
const listPage = read('src/pages/FacturationEtablissement.tsx');
const detailPage = read('src/pages/DetailFacture.tsx');
const navigation = read('src/components/BarreNavigation.tsx');
const missionPayment = read('src/components/WorkflowPaiementMission.tsx');
const connectPayment = read('supabase/functions/stripe-connect-pay-mission/index.ts');

const reviewedFunctions = [
  'fn_mes_permissions_etab',
  'fn_obligations_financieres',
  'fn_mes_factures',
  'fn_paiements_etablissement',
  'fn_detail_facture',
  'fn_declarer_paiement_soignant',
  'fn_modifier_reference_paiement',
  'fn_consulter_rib_soignant',
  'fn_generer_facture_mensuelle',
  'fn_generer_facture_rate_limited',
  'fn_declarer_virement',
  'fn_mode_paiement_mission',
] as const;

function finalFunctionBody(functionName: string): string {
  const plain = `CREATE FUNCTION public.${functionName}`;
  const replace = `CREATE OR REPLACE FUNCTION public.${functionName}`;
  const start = Math.max(migration.lastIndexOf(plain), migration.lastIndexOf(replace));
  expect(start, `${functionName}: définition absente`).toBeGreaterThanOrEqual(0);
  const definition = migration.slice(start);
  const bodyMarker = definition.match(/\bAS\s+(\$[a-z_]*\$|\$\$)/i);
  expect(bodyMarker, `${functionName}: délimiteur absent`).not.toBeNull();
  const marker = bodyMarker![1];
  const bodyStart = bodyMarker!.index! + bodyMarker![0].length;
  const bodyEnd = definition.indexOf(marker, bodyStart);
  expect(bodyEnd, `${functionName}: fin du corps absente`).toBeGreaterThan(bodyStart);
  return definition.slice(bodyStart, bodyEnd);
}

describe('Finances établissement — cohérence interface et RBAC', () => {
  it('reste idempotente lorsque la CI staging rejoue la migration', () => {
    expect(migration).toContain('DO $rename_finance_internals$');
    for (const internalName of [
      'fn_obligations_financieres_internal_20260801()',
      'fn_mes_factures_internal_20260801()',
      'fn_paiements_etablissement_internal_20260801()',
      'fn_detail_facture_internal_20260801(uuid)',
      'fn_declarer_paiement_soignant_internal_20260801(uuid,numeric,text,text,date,boolean)',
      'fn_modifier_reference_paiement_internal_20260801(uuid,text)',
      'fn_consulter_rib_soignant_internal_20260801(uuid)',
      'fn_generer_facture_mensuelle_internal_20260801(uuid)',
    ]) {
      expect(migration).toContain(`to_regprocedure('public.${internalName}') IS NULL`);
    }
    for (const functionName of reviewedFunctions) {
      expect(migration).toContain(`CREATE OR REPLACE FUNCTION public.${functionName}`);
    }
  });

  it('sépare la consultation financière des mutations sur toutes les interfaces', () => {
    expect(migration).toContain("'lecture_paiement', public.fn_a_permission_etablissement('lecture_paiement'");
    expect(navigation).toContain('etabPermissions.lecture_paiement || etabPermissions.paiement');
    for (const source of [listPage, detailPage, missionPayment]) {
      expect(source).toContain('permissions.lecture_paiement || permissions.paiement');
    }
    for (const source of [listPage, detailPage, missionPayment]) {
      expect(source).toContain('permissions.paiement');
      expect(source).toContain('canManagePayments');
    }
    expect(listPage).toContain('Accès à la facturation refusé');
    expect(detailPage).toContain('Accès à la facture refusé');
  });

  it('bloque le contournement PostgREST par les politiques financières', () => {
    for (const policy of [
      'pol_fact_select',
      'fh_select_own',
      'pol_paim_select',
      'pol_transfer_select',
    ]) {
      expect(migration).toContain(`CREATE POLICY ${policy}`);
    }
    expect(migration.match(/fn_a_permission_etablissement\('lecture_paiement'/g)?.length)
      .toBeGreaterThanOrEqual(8);
    expect(migration).toContain('CREATE POLICY pol_rib_select');
    expect(migration).toContain("fn_a_permission_etablissement('paiement', etablissement_id)");
  });

  it('interdit carte et virement manuel pour SEPA et Chorus', () => {
    expect(migration).toContain("v_mode_commission = 'SEPA_DEBIT'");
    expect(migration).toContain('v_facture.est_secteur_public');
    expect(migration).toContain("'PAIEMENT_SEPA_AUTOMATIQUE'");
    expect(listPage).toContain("etab?.mode_paiement_commission !== 'SEPA_DEBIT'");
    expect(detailPage).toContain("etab?.mode_paiement_commission === 'SEPA_DEBIT'");
    expect(detailPage).toContain('!facture.est_secteur_public');
  });

  it('accepte le net réel du bulletin salarié sans le remplacer par l’estimation à 78 %', () => {
    const declarationBody = finalFunctionBody('fn_declarer_paiement_soignant');
    expect(declarationBody).not.toContain('v_mission.net_estime');
    expect(declarationBody).not.toContain('v_mission.net_a_payer, 0) * 0.78');
    expect(declarationBody).toContain('MONTANT_NET_SALARIE_SUPERIEUR_AU_BRUT');
    expect(declarationBody).toContain('v_montant_du := round(p_montant, 2)');
    expect(declarationBody).toContain('p_montant IS NULL OR p_montant <= 0');
    expect(listPage).toContain("mission.type_contrat_applique === 'SALARIE'");
    expect(listPage).toContain("? ''");
    expect(listPage).toContain('Estimation indicative avant paie/PAS');
    expect(listPage).toContain("L'estimation n'est pas utilisée automatiquement");
  });

  it('ne transforme pas le retour Stripe en succès avant confirmation serveur', () => {
    expect(connectPayment).toContain('facture_honoraire: factureHonoraires.id');
    expect(connectPayment).toContain('mission: mission_id');
    expect(listPage).toContain("Promise<'CONFIRME' | 'ECHEC' | 'EN_ATTENTE'>");
    expect(listPage).toContain("['CHARGE_REUSSI', 'TRANSFERE', 'PAYE']");
    expect(listPage).toContain("statut === 'ECHOUE'");
    expect(listPage).toContain('La confirmation est encore en cours');
    expect(listPage).toContain('onComplete: () => void finaliserRetourConnect');
  });

  it('facture la commission en plus et transfère 100 % des honoraires au soignant', () => {
    expect(connectPayment).toContain('const totalCents = commissionCents + soignantCents');
    expect(connectPayment).toContain('unit_amount: commissionCents');
    expect(connectPayment).toContain('unit_amount: soignantCents');
    expect(connectPayment).toContain('amount: soignantCents');
    expect(connectPayment).toContain('transfer.amount !== soignantCents');
  });

  it('recapture chaque SECURITY DEFINER avec le hash exact et des ACL vérifiées', () => {
    for (const functionName of reviewedFunctions) {
      const bodyHash = createHash('md5').update(finalFunctionBody(functionName)).digest('hex');
      expect(
        migration,
        `${functionName}: hash absent de la recapture explicite`,
      ).toContain(`definition_md5 = '${bodyHash}'`);
    }
    expect(migration).toContain('DO $assert_finance_etablissement_security$');
    expect(migration).toContain("has_function_privilege('anon', p.oid, 'EXECUTE')");
    expect(migration).toContain("has_function_privilege('authenticated', p.oid, 'EXECUTE')");
    expect(migration).toContain('Sous-routines financières internes exposées');
  });
});
