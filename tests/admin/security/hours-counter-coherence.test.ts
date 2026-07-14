import { readFileSync } from "node:fs";
import { describe, expect, it } from "vitest";

const migrationPath =
  "supabase/migrations/20260714122337_corriger_compteurs_heures_canoniques.sql";
const migration = readFileSync(migrationPath, "utf8");

function functionBody(schema: string, name: string): string {
  const marker = new RegExp(
    `CREATE(?: OR REPLACE)? FUNCTION ${schema}\\.${name}\\b`,
  );
  const match = marker.exec(migration);
  const start = match?.index ?? -1;
  expect(start, `${schema}.${name} doit être redéfinie`).toBeGreaterThanOrEqual(
    0,
  );
  const remainder = migration.slice(start + 1);
  const nextMatch = /\nCREATE(?: OR REPLACE)? FUNCTION /.exec(remainder);
  const end = nextMatch ? start + 1 + nextMatch.index : migration.length;
  return migration.slice(start, end);
}

describe("compteurs d’heures — source canonique et seuil exact", () => {
  it("centralise les quatre valeurs numériques dans un helper privé", () => {
    const helper = functionBody("private", "fn_heures_exercice_verifiees");

    expect(helper).toMatch(/heures_jolene\s+numeric/i);
    expect(helper).toMatch(/heures_externes_validees\s+numeric/i);
    expect(helper).toMatch(/heures_externes_en_attente\s+numeric/i);
    expect(helper).toMatch(/heures_totales\s+numeric/i);
    expect(helper).toMatch(/\bstatut\s*=\s*'TERMINEE'/i);
    expect(helper).toContain("heures_reelles");
    expect(helper).toMatch(
      /FROM public\.presences pr[\s\S]*?WHERE pr\.mission_id\s*=\s*m\.id[\s\S]*?AND pr\.soignant_id\s*=\s*m\.soignant_assigne_id/i,
    );
    expect(helper).toMatch(/\bstatut_validation\s*=\s*'VALIDE'/i);
    expect(helper).not.toMatch(/::integer/i);
    expect(migration).toContain(
      "REVOKE ALL ON FUNCTION private.fn_heures_exercice_verifiees(uuid)",
    );
  });

  it("applique le seuil de la profession requise par la mission", () => {
    const seuil = functionBody("private", "fn_seuil_heures_liberal");

    expect(seuil).toContain("p_profession_mission");
    expect(seuil).toContain("WHEN 'IDE' THEN 3200");
    expect(seuil).toContain("WHEN 'KINE' THEN");
    expect(seuil).toContain("WHEN 'HEURES_2240' THEN 2240");
    expect(seuil).toContain("WHEN 'ZONE_SOUS_DOTEE' THEN 0");
    expect(migration).toContain(
      "REVOKE ALL ON FUNCTION private.fn_seuil_heures_liberal(uuid, text)",
    );
  });

  it("resynchronise les caches par recalcul et non par incrément", () => {
    const resync = functionBody(
      "private",
      "fn_resynchroniser_compteurs_soignant",
    );

    expect(resync).toContain("private.fn_heures_exercice_verifiees");
    expect(resync).toContain("heures_plateforme");
    expect(resync).toContain("heures_cumulees");
    expect(resync).toContain("eligible_conversion_3200h");
    expect(resync).toContain("total_missions_terminees");
    expect(resync).not.toMatch(
      /heures_(?:plateforme|cumulees)\s*=\s*[^,;]+\+/i,
    );
    expect(migration).toContain(
      "REVOKE ALL ON FUNCTION private.fn_resynchroniser_compteurs_soignant(uuid)",
    );
  });

  it("branche le recalcul sur les missions, présences et heures externes", () => {
    expect(migration).toMatch(/CREATE TRIGGER[\s\S]*?ON public\.missions/i);
    expect(migration).toMatch(/CREATE TRIGGER[\s\S]*?ON public\.presences/i);
    expect(migration).toMatch(
      /CREATE TRIGGER[\s\S]*?ON public\.heures_externes_soignants/i,
    );
    expect(migration).toContain("DROP TRIGGER IF EXISTS dec_heures_plateforme");
    expect(migration).toContain("DROP TRIGGER IF EXISTS dec_maj_compteurs");
  });

  it("expose un compteur décimal cohérent sans croire le cache du profil", () => {
    const compteur = functionBody("public", "fn_compteur_heures_soignant");

    expect(compteur).toMatch(/heures_jolene\s+numeric/i);
    expect(compteur).toMatch(/heures_externes_validees\s+numeric/i);
    expect(compteur).toMatch(/heures_externes_en_attente\s+numeric/i);
    expect(compteur).toMatch(/heures_totales\s+numeric/i);
    expect(compteur).toContain("private.fn_heures_exercice_verifiees");
    expect(compteur).not.toMatch(/s\.heures_cumulees|s\.heures_plateforme/i);
  });

  it("ferme l’activation sous le seuil métier et retire la table legacy", () => {
    const activation = functionBody("public", "fn_activer_liberal");
    const assignment = functionBody(
      "public",
      "dec_verifier_eligibilite_liberal",
    );

    expect(activation).toContain("private.fn_heures_exercice_verifiees");
    expect(activation).toContain("private.fn_seuil_heures_liberal");
    expect(activation).toMatch(/heures_totales\s*<\s*v_seuil_heures/i);
    expect(activation).not.toMatch(
      /\bFROM\s+(?:public\.)?heures_externes\b/i,
    );
    expect(assignment).toContain("private.fn_heures_exercice_verifiees");
    expect(assignment).toContain("NEW.profession_requise::text");
    expect(assignment).toContain("private.fn_seuil_heures_liberal");
    expect(assignment).toContain("SELECT h.heures_totales");
    expect(assignment).toMatch(
      /v_heures_cumulees[\s\S]*?<\s*v_seuil_heures/i,
    );
  });

  it("réserve le seed de preuve validée aux fixtures serveur", () => {
    const seed = functionBody(
      "public",
      "fn_test_seed_heures_externes_validees",
    );

    expect(seed).toMatch(/auth\.role\(\)|auth\.jwt\(\)|request\.jwt\.claim\.role/i);
    expect(seed).toContain("'service_role'");
    expect(seed).toContain("heures_externes_soignants");
    expect(migration).toMatch(
      /GRANT\s+EXECUTE\s+ON\s+FUNCTION\s+public\.fn_test_seed_heures_externes_validees\s*\(\s*uuid,\s*numeric\s*\)\s+TO\s+service_role/i,
    );
    expect(migration).not.toMatch(
      /GRANT\s+EXECUTE\s+ON\s+FUNCTION\s+public\.fn_test_seed_heures_externes_validees\s*\(\s*uuid,\s*numeric\s*\)\s+TO\s+(?:PUBLIC|anon|authenticated)/i,
    );
  });
});
