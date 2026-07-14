import { readFileSync } from 'node:fs';
import { describe, expect, it } from 'vitest';

const migration = readFileSync(
  'supabase/migrations/20260714003439_corriger_fonctions_runtime_lint.sql',
  'utf8',
);

function finalExecutorDefinition(): string {
  const marker =
    'CREATE OR REPLACE FUNCTION public.fn_executer_modifications_litige';
  const start = migration.lastIndexOf(marker);
  expect(start).toBeGreaterThan(0);
  const end = migration.indexOf('$function$;', start);
  expect(end).toBeGreaterThan(start);
  return migration.slice(start, end + '$function$;'.length);
}

describe('exécution financière des accords de litige', () => {
  it('verrouille la ligne et exige le double consentement horodaté', () => {
    const fn = finalExecutorDefinition();

    expect(fn).toContain('FOR UPDATE');
    expect(fn).toContain('v_litige.accord_soignant IS NOT TRUE');
    expect(fn).toContain('v_litige.accord_etablissement IS NOT TRUE');
    expect(fn).toContain('v_litige.accord_soignant_le IS NULL');
    expect(fn).toContain('v_litige.accord_etablissement_le IS NULL');
  });

  it('refuse les trois anciens chemins capables de générer un avoir inexact', () => {
    const fn = finalExecutorDefinition();

    expect(fn).toContain("'MODIFICATION_HORAIRES'");
    expect(fn).toContain("'MODIFICATION_MONTANT'");
    expect(fn).toContain("'MIXTE'");
    expect(fn).toContain("'RESOLUTION_FINANCIERE_MANUELLE_REQUISE'");
    expect(fn).toContain("'manual_resolution_required', true");
    expect(fn).not.toContain("'AVOIR_PDF_GENERATION'");
  });

  it('automatise seulement les chemins prouvables et contrôle leur résultat', () => {
    const fn = finalExecutorDefinition();
    const annulation = fn.indexOf('public.fn_annuler_mission_complete(');
    const compensation = fn.indexOf(
      'public.fn_appliquer_compensation_partielle(',
    );
    const markExecuted = fn.indexOf('SET modifications_executees = true');

    expect(fn).toContain("v_litige.statut <> 'REVUE_ADMIN'");
    expect(fn).toContain('public.est_admin() IS NOT TRUE');
    expect(fn).toContain(
      `COALESCE(v_result @> '{"success": true}'::jsonb, false) IS NOT TRUE`,
    );
    expect(fn).toContain("RAISE EXCEPTION 'Échec atomique");
    expect(annulation).toBeGreaterThan(0);
    expect(compensation).toBeGreaterThan(annulation);
    expect(markExecuted).toBeGreaterThan(compensation);
  });

  it('ne marque exécuté qu’après validation stricte du payload stocké', () => {
    const fn = finalExecutorDefinition();
    const schemaGate = fn.indexOf("'Schéma de proposition stocké invalide'");
    const markExecuted = fn.indexOf('SET modifications_executees = true');

    expect(fn).toContain(
      "jsonb_typeof(v_payload->'modifications') IS DISTINCT FROM 'object'",
    );
    expect(fn).toContain(
      "jsonb_typeof(v_payload->'justification') IS DISTINCT FROM 'string'",
    );
    expect(fn).toContain("v_payload - ARRAY[");
    expect(schemaGate).toBeGreaterThan(0);
    expect(markExecuted).toBeGreaterThan(schemaGate);
  });

  it('rend l’audit final obligatoire et transactionnel', () => {
    const fn = finalExecutorDefinition();

    expect(fn).toContain('v_audit_result := public.fn_ecrire_audit_safe(');
    expect(fn).toContain("p_action := 'LITIGE_RESOLUTION'");
    expect(fn).toContain("'evenement', 'LITIGE_MODIFICATIONS_EXECUTEES'");
    expect(fn).toContain(
      `COALESCE(v_audit_result @> '{"success": true}'::jsonb, false)`,
    );
    expect(fn).toContain("RAISE EXCEPTION 'Audit d''exécution d''accord non écrit");
  });
});
