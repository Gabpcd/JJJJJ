import { createHash } from "node:crypto";
import { readFileSync } from "node:fs";
import { describe, expect, it } from "vitest";

const root = process.cwd();
const manifestPath = `${root}/supabase/SECURITY_DEFINER_MANIFEST.json`;
const inventoryMigrationPath =
  `${root}/supabase/migrations/20260729121443_figer_inventaire_security_definer.sql`;
const prelaunchMigrationPath =
  `${root}/supabase/migrations/20260729121419_requalifier_donnees_prelaunch_et_supprimer_mfa_admin.sql`;
const hardeningMigrationPath =
  `${root}/supabase/migrations/20260729121442_securiser_auth_et_crons_critiques.sql`;
const manifest = JSON.parse(readFileSync(manifestPath, "utf8")) as {
  snapshot: {
    unique_functions: number;
    hash: string;
    local_migrations_included_through: string;
  };
  categories: Record<string, number>;
  entries: Array<{
    signature: string;
    category: string;
    body_md5: string;
    justification: string;
  }>;
};
const inventorySql = readFileSync(inventoryMigrationPath, "utf8");
const hardeningSql = readFileSync(hardeningMigrationPath, "utf8");

function sqlLiteral(value: string): string {
  return value.replace(/''/g, "'");
}

function explicitSqlEntries(): typeof manifest.entries {
  const valuesStart = inventorySql.indexOf(") VALUES");
  const assertionStart = inventorySql.indexOf(
    "DO $assert_explicit_security_definer_manifest$",
  );
  expect(valuesStart).toBeGreaterThanOrEqual(0);
  expect(assertionStart).toBeGreaterThan(valuesStart);
  const values = inventorySql.slice(valuesStart, assertionStart);
  const entryPattern =
    /^\s*\('((?:''|[^'])*)', '((?:''|[^'])*)', '([a-f0-9]{32})', '((?:''|[^'])*)'\)[,;]\s*$/gm;
  return [...values.matchAll(entryPattern)].map((match) => ({
    signature: sqlLiteral(match[1]),
    category: sqlLiteral(match[2]),
    body_md5: match[3],
    justification: sqlLiteral(match[4]),
  }));
}

function finalPublicSecurityDefiners(sql: string): Map<string, string> {
  const declarations = [
    ...sql.matchAll(
      /CREATE OR REPLACE FUNCTION public\.([a-z_][a-z0-9_]*)\s*\(/g,
    ),
  ];
  const result = new Map<string, string>();

  for (let index = 0; index < declarations.length; index++) {
    const declaration = declarations[index];
    const start = declaration.index!;
    const end = declarations[index + 1]?.index ?? sql.length;
    const definition = sql.slice(start, end);
    const bodyMarker = definition.match(/\bAS\s+(\$[a-z_][a-z0-9_]*\$)/i);
    expect(
      bodyMarker,
      `${declaration[1]}: délimiteur de corps introuvable`,
    ).not.toBeNull();
    const header = definition.slice(0, bodyMarker!.index);
    if (!/\bSECURITY\s+DEFINER\b/i.test(header)) continue;

    const marker = bodyMarker![1];
    const contentStart = bodyMarker!.index! + bodyMarker![0].length;
    const bodyEnd = definition.indexOf(marker, contentStart);
    expect(bodyEnd, `${declaration[1]}: fin de corps introuvable`)
      .toBeGreaterThan(contentStart);
    result.set(declaration[1], definition.slice(contentStart, bodyEnd));
  }

  return result;
}

describe("inventaire versionné des SECURITY DEFINER exposées", () => {
  it("fige exactement 422 signatures uniques avec catégorie et empreinte", () => {
    expect(manifest.snapshot.unique_functions).toBe(422);
    expect(manifest.snapshot.hash).toBe("md5(pg_proc.prosrc)");
    expect(manifest.snapshot.local_migrations_included_through).toBe(
      "20260729121442",
    );
    expect(manifest.entries).toHaveLength(422);
    expect(new Set(manifest.entries.map((entry) => entry.signature)).size).toBe(
      422,
    );
    for (const entry of manifest.entries) {
      expect(entry.signature).toMatch(/^[a-z_][a-z0-9_]*\(.*\)$/);
      expect(entry.body_md5).toMatch(/^[a-f0-9]{32}$/);
      expect(entry.justification.length).toBeGreaterThan(30);
      expect(entry.category in manifest.categories).toBe(true);
    }
    for (const [category, expected] of Object.entries(manifest.categories)) {
      expect(
        manifest.entries.filter((entry) => entry.category === category).length,
        category,
      ).toBe(expected);
    }
  });

  it("duplique littéralement le JSON dans la migration sans auto-classification", () => {
    const sqlEntries = explicitSqlEntries();
    expect(sqlEntries).toHaveLength(422);
    expect(sqlEntries).toEqual(manifest.entries);

    const valuesSection = inventorySql.slice(
      inventorySql.indexOf(") VALUES"),
      inventorySql.indexOf("DO $assert_explicit_security_definer_manifest$"),
    );
    expect(valuesSection).not.toMatch(
      /INSERT[\s\S]*SELECT[\s\S]*(?:pg_proc|information_schema)/i,
    );
    expect(inventorySql).toContain("md5(p.prosrc) <> i.definition_md5");
    expect(inventorySql).toContain("SECURITY DEFINER non classées");
    expect(inventorySql).toContain("Corps SECURITY DEFINER modifiés sans revue");
  });

  it("limite l'anonyme aux sept RPC publiques et révoque cinq primitives", () => {
    const publicSignatures = manifest.entries
      .filter((entry) => entry.category === "PUBLIC_VOLONTAIRE")
      .map((entry) => entry.signature)
      .sort();
    expect(publicSignatures).toEqual([
      "fn_apercu_marche_profession(text,double precision,double precision,integer)",
      "fn_mission_publique(uuid)",
      "fn_missions_publiques_recherche(text,text)",
      "fn_pre_request_compte_actif()",
      "fn_professions_autorisees_scolarite(text,integer)",
      "fn_rechercher_aide(text,text)",
      "fn_types_exercice_autorises(text)",
    ]);

    const serviceOnly = manifest.entries
      .filter((entry) => entry.category === "SERVICE_ONLY_REVOQUE")
      .map((entry) => entry.signature)
      .sort();
    expect(serviceOnly).toEqual([
      "fn_calculer_score_matching(uuid,uuid)",
      "fn_conflit_planning_soignant(uuid,uuid)",
      "fn_doit_notifier(uuid,type_evenement_notification,canal_notification)",
      "fn_generer_numero_contrat_safe(text)",
      "fn_sms_doit_envoyer(uuid,text,integer)",
    ]);
  });

  it("rétablit les ACL service-only absentes des migrations historiques", () => {
    const internalFunctions = [
      "fn_auto_resoudre_alertes_crons",
      "fn_publier_notations_echues",
      "fn_recalculer_scores_etablissements",
      "fn_trg_escrow_enqueue_on_terminee",
    ];

    for (const functionName of internalFunctions) {
      expect(
        hardeningSql,
        `${functionName}: révocation anon/auth absente`,
      ).toMatch(
        new RegExp(
          `REVOKE ALL ON FUNCTION public\\.${functionName}\\(\\)`
            + "[\\s\\S]{0,100}?FROM PUBLIC, anon, authenticated",
        ),
      );
      expect(
        hardeningSql,
        `${functionName}: grant service_role absent`,
      ).toMatch(
        new RegExp(
          `GRANT EXECUTE ON FUNCTION public\\.${functionName}\\(\\)`
            + "[\\s\\S]{0,100}?TO service_role",
        ),
      );
    }
  });

  it("calcule les hash de toutes les fonctions réellement redéfinies en 21419", () => {
    const migration = readFileSync(prelaunchMigrationPath, "utf8");
    const definitions = finalPublicSecurityDefiners(migration);
    const reviewed = [...definitions].flatMap(([functionName, body]) => {
      const entries = manifest.entries.filter(
        (candidate) => candidate.signature.startsWith(`${functionName}(`),
      );
      expect(
        entries.length,
        `${functionName}: surcharge manifeste ambiguë`,
      ).toBeLessThanOrEqual(1);
      return entries.map((entry) => ({ functionName, body, entry }));
    });

    expect(reviewed).toHaveLength(15);
    for (const { functionName, body, entry } of reviewed) {
      const bodyMd5 = createHash("md5").update(body).digest("hex");
      expect(bodyMd5, `${functionName}: hash post-migration`).toBe(
        entry.body_md5,
      );
    }
  });

  it("borne à service_role chaque nouvelle SECURITY DEFINER hors manifeste", () => {
    const migration = readFileSync(prelaunchMigrationPath, "utf8");
    const definitions = finalPublicSecurityDefiners(migration);
    const unmanifested = [...definitions.keys()].filter(
      (functionName) =>
        !manifest.entries.some(
          (entry) => entry.signature.startsWith(`${functionName}(`),
        ),
    );

    expect(unmanifested.sort()).toEqual([
      "dec_email_invitation_equipe_etab",
      "fn_envoyer_rappels_notation_j1",
      "fn_finaliser_envoi_email_idempotent",
      "fn_reserver_envoi_email_idempotent",
      "fn_trg_auto_notify_mission_urgente",
      "fn_trg_litige_notify_support",
      "fn_trg_tripwire_premier_connect_complet",
      "fn_trg_tripwire_premier_mandat_sepa",
      "fn_trg_tripwire_premier_payment_intent",
      "fn_tripwire_alerte",
    ]);
    for (const functionName of unmanifested) {
      expect(
        migration,
        `${functionName}: révocation anon/auth absente`,
      ).toMatch(
        new RegExp(
          `REVOKE ALL ON FUNCTION public\\.${functionName}\\([\\s\\S]{0,200}?`
            + "FROM PUBLIC, anon, authenticated",
        ),
      );
      expect(
        migration,
        `${functionName}: grant service_role absent`,
      ).toMatch(
        new RegExp(
          `GRANT EXECUTE ON FUNCTION public\\.${functionName}\\([\\s\\S]{0,200}?`
            + "TO service_role",
        ),
      );
    }
  });
});
