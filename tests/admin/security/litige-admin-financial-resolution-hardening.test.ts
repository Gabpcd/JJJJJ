import { readFileSync } from 'node:fs';
import { describe, expect, it } from 'vitest';

const migration = readFileSync(
  'supabase/migrations/20260714003439_corriger_fonctions_runtime_lint.sql',
  'utf8',
);
const modal = readFileSync(
  'src/components/admin/litiges/LitigeResolutionModal.tsx',
  'utf8',
);

function finalFunction(name: string): string {
  const marker = `CREATE OR REPLACE FUNCTION public.${name}`;
  const start = migration.lastIndexOf(marker);
  expect(start).toBeGreaterThan(0);
  const end = migration.indexOf('$function$;', start);
  expect(end).toBeGreaterThan(start);
  return migration.slice(start, end + '$function$;'.length);
}

describe('résolution financière admin des litiges', () => {
  it('verrouille toutes les lignes avant de décider et refuse les états terminaux', () => {
    const fn = finalFunction('fn_admin_resoudre_litige');

    expect(fn.match(/FOR UPDATE/g)?.length).toBeGreaterThanOrEqual(4);
    expect(fn).toContain("v_litige.statut NOT IN (");
    expect(fn).toContain("'REVUE_ADMIN'");
    expect(fn).toContain("'Ce litige est déjà résolu ou non modifiable.'");
    expect(fn).toContain("GET DIAGNOSTICS v_rows = ROW_COUNT");
    expect(fn).toContain("RAISE EXCEPTION 'Résolution concurrente refusée'");
  });

  it('applique la matrice exacte des actions et bloque les doubles documents', () => {
    const fn = finalFunction('fn_admin_resoudre_litige');

    expect(fn).toContain("v_facture.statut <> 'BROUILLON'");
    expect(fn).toContain("v_facture.statut NOT IN ('EMISE', 'EN_RETARD')");
    expect(fn).toContain("v_facture.statut <> 'PAYEE'");
    expect(fn).toContain("v_action = 'AUCUNE' AND v_ajustement_demande");
    expect(fn).toContain("'Une facture de remplacement existe déjà.'");
    expect(fn).toContain("'Un avoir actif existe déjà pour cette facture.'");
    expect(fn).toContain("'Un avoir exige un montant corrigé strictement inférieur");
  });

  it('applique l’accord exact ou audite explicitement son remplacement', () => {
    const fn = finalFunction('fn_admin_resoudre_litige');
    const financialMutation = fn.indexOf("IF v_action = 'RECALCUL'");
    const markResolved = fn.indexOf('UPDATE public.litiges');

    expect(fn).toContain('v_litige.accord_soignant IS NOT TRUE');
    expect(fn).toContain('v_litige.accord_etablissement IS NOT TRUE');
    expect(fn).toContain('v_litige.modifications_executees IS TRUE');
    expect(fn).toContain('v_montant_payload');
    expect(fn).toContain('v_heures_payload');
    expect(fn).toContain("'LITIGE_ACCORD_REMPLACE_PAR_DECISION_ADMIN'");
    expect(fn).toContain("'accord_payload_remplace', v_payload");
    expect(fn).toContain("'accord_payload_applique'");
    expect(fn).toContain('modifications_executees = CASE');
    expect(financialMutation).toBeGreaterThan(0);
    expect(markResolved).toBeGreaterThan(financialMutation);
  });

  it('borne les nombres côté serveur et dans la modale sans s’y fier', () => {
    const fn = finalFunction('fn_admin_resoudre_litige');

    expect(fn).toContain("p_ajuster_heures::text IN ('NaN', 'Infinity', '-Infinity')");
    expect(fn).toContain('p_ajuster_heures > 168');
    expect(fn).toContain('p_ajuster_taux < 0.01');
    expect(fn).toContain('p_ajuster_taux > 1000');
    expect(fn).toContain("'NEUTRE'");
    expect(modal).toContain('Number.isFinite(heuresNum)');
    expect(modal).toContain('Number.isFinite(tauxNum)');
    expect(modal).toContain('min="0.01"');
    expect(modal).toContain('max="168"');
    expect(modal.match(/min="0\.01"/g)?.length).toBe(2);
    expect(modal).toContain('max="1000"');
  });

  it('traite le total convenu en TTC et refuse le remboursement auto Connect', () => {
    const fn = finalFunction('fn_admin_resoudre_litige');

    expect(fn).toContain('v_nouveau_montant_ttc := round(v_montant_payload, 2)');
    expect(fn).toContain('v_nouveau_montant_ttc - v_nouveau_montant_ht');
    expect(fn).toContain('v_diff_ttc := round');
    expect(fn).toContain('round(v_diff_ttc * 100)::integer');
    expect(fn).toContain('IF v_transfer_trouve THEN');
    expect(fn).toContain("v_mode_remboursement := 'VIREMENT_MANUEL'");
    expect(fn).toContain("v_transfer.statut NOT IN ('ECHOUE', 'ANNULEE', 'REMBOURSE')");
    expect(fn).toContain('stripe_checkout_session_id');
  });

  it('sérialise l’ouverture et borne le motif sans audit legacy pré-autorisation', () => {
    const typed = finalFunction('fn_ouvrir_litige_rate_limited');
    const typedStart = migration.lastIndexOf(
      'CREATE OR REPLACE FUNCTION public.fn_ouvrir_litige_rate_limited(\n  p_mission_id uuid,\n  p_type_litige',
    );
    const typedEnd = migration.indexOf('$function$;', typedStart);
    const typedExact = migration.slice(typedStart, typedEnd);
    const wrapperStart = migration.lastIndexOf(
      'CREATE OR REPLACE FUNCTION public.fn_ouvrir_litige_rate_limited(\n  p_mission_id uuid,\n  p_motif text',
    );
    const wrapperEnd = migration.indexOf('$function$;', wrapperStart);
    const wrapper = migration.slice(wrapperStart, wrapperEnd);

    expect(typedStart).toBeGreaterThan(0);
    expect(typedExact).toContain('length(trim(COALESCE(p_motif');
    expect(typedExact).toContain('> 2000');
    expect(typedExact).toContain('FROM public.missions m');
    expect(typedExact).toContain('FOR UPDATE');
    expect(typedExact).toContain("f.statut IN ('EMISE', 'EN_RETARD', 'PAYEE')");
    expect(typedExact).toContain(
      "ELSIF p_type_litige = 'DESACCORD_HEURES_POINTAGE'",
    );
    expect(typedExact).toContain(
      "f.statut IN ('BROUILLON', 'EMISE', 'EN_RETARD', 'PAYEE')",
    );
    expect(wrapperStart).toBeGreaterThan(typedStart);
    expect(wrapper).not.toContain('fn_ecrire_audit');
    expect(wrapper).toContain("'AUTRE'::public.type_litige");
    expect(typed).toBeTruthy();
  });
});
