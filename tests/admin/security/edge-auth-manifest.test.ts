import { readFileSync, existsSync } from "node:fs";
import { describe, expect, it } from "vitest";

const root = process.cwd();
const config = readFileSync(`${root}/supabase/config.toml`, "utf8");
const manifest = JSON.parse(
  readFileSync(`${root}/supabase/EDGE_AUTH_MANIFEST.json`, "utf8"),
) as {
  snapshot: Record<string, number>;
  entries: Array<{
    slug: string;
    verify_jwt: boolean;
    auth_class: string;
    guard_all: string[];
    justification: string;
  }>;
};

const configured = new Map<string, boolean>();
for (const match of config.matchAll(
  /\[functions\.([^\]]+)\]\s*\nverify_jwt = (true|false)/g,
)) {
  configured.set(match[1], match[2] === "true");
}

function functionSource(slug: string): string {
  return readFileSync(
    `${root}/supabase/functions/${slug}/index.ts`,
    "utf8",
  );
}

function withoutComments(source: string): string {
  return source
    .replace(/\/\*[\s\S]*?\*\//g, "")
    .replace(/^\s*\/\/.*$/gm, "");
}

function expectGuardBeforeEffect(
  slug: string,
  guard: RegExp,
  effect: RegExp,
  fromMainHandler = false,
): void {
  let source = withoutComments(functionSource(slug));
  if (fromMainHandler) {
    const handlerIndex = source.indexOf("Deno.serve");
    expect(handlerIndex, `${slug}: handler Deno.serve absent`).toBeGreaterThanOrEqual(0);
    source = source.slice(handlerIndex);
  }
  const guardIndex = source.search(guard);
  const effectIndex = source.search(effect);
  expect(guardIndex, `${slug}: décision d'authentification absente`).toBeGreaterThanOrEqual(0);
  expect(effectIndex, `${slug}: effet privilégié témoin absent`).toBeGreaterThanOrEqual(0);
  expect(
    guardIndex,
    `${slug}: l'effet privilégié précède la décision d'authentification`,
  ).toBeLessThan(effectIndex);
}

describe("inventaire explicite d'authentification des Edge Functions", () => {
  it("fige les 76 fonctions distantes, dont admin-2fa retirée", () => {
    expect(manifest.entries).toHaveLength(76);
    expect(new Set(manifest.entries.map((entry) => entry.slug)).size).toBe(76);
    expect(manifest.snapshot.remote_total).toBe(76);
    expect(manifest.snapshot.remote_verify_jwt_false).toBe(71);
    expect(manifest.snapshot.local_total_after_admin_2fa_retirement).toBe(75);
    expect(manifest.snapshot.local_verify_jwt_false).toBe(70);
  });

  it("classe chaque fonction locale et interdit toute dérive config/manifeste", () => {
    expect(configured.size).toBe(75);
    for (const [slug, verifyJwt] of configured) {
      const entry = manifest.entries.find((candidate) => candidate.slug === slug);
      expect(entry, `fonction non classée: ${slug}`).toBeDefined();
      expect(entry?.verify_jwt, `verify_jwt incohérent: ${slug}`).toBe(verifyJwt);
      expect(entry?.auth_class, `classe absente: ${slug}`).toBeTruthy();
      expect(entry?.justification.length, `justification absente: ${slug}`).toBeGreaterThan(15);
    }
  });

  it("refuse verify_jwt=false sans garde exécutable déclaré", () => {
    for (const entry of manifest.entries) {
      if (entry.auth_class === "RETIRED" || entry.verify_jwt) continue;
      const sourcePath = `${root}/supabase/functions/${entry.slug}/index.ts`;
      expect(existsSync(sourcePath), `source absente: ${entry.slug}`).toBe(true);
      // Un nom présent uniquement dans un commentaire ne peut jamais satisfaire
      // l'inventaire. Les tests sémantiques ci-dessous vérifient en plus les
      // appels et leur ordre avant le premier effet privilégié.
      const source = withoutComments(readFileSync(sourcePath, "utf8"));
      expect(entry.guard_all.length, `aucun garde: ${entry.slug}`).toBeGreaterThan(0);
      for (const marker of entry.guard_all) {
        expect(source, `${entry.slug}: garde manquant ${marker}`).toContain(marker);
      }
    }
  });

  it("valide les appels réels des gardes corrigés et leur ordre avant effets", () => {
    const sharedUserGuardFunctions = [
      "verify-rpps",
      "verify-finess",
      "verify-document",
      "verify-contrat-etablissement",
      "verify-rib-etablissement",
      "chorus-pro-deposit",
      "stripe-connect-status",
      "calendar-sync",
      "delete-account",
      "psc-logout",
    ];
    for (const slug of sharedUserGuardFunctions) {
      const source = withoutComments(functionSource(slug));
      expect(
        source,
        `${slug}: helper importé mais jamais appelé`,
      ).toMatch(/await\s+verifyUserOrServiceRole\s*\(\s*req\s*\)/);
      expect(
        source,
        `${slug}: résultat du helper non refusé fail-closed`,
      ).toMatch(/if\s*\(\s*!auth\.ok\s*\)/);
    }

    expectGuardBeforeEffect(
      "set-user-claims",
      /const\s+isAuthorized\s*=\s*timingSafeEqual\s*\(/,
      /\.auth\.admin\.updateUserById\s*\(/,
      true,
    );
    expectGuardBeforeEffect(
      "notify-support",
      /if\s*\(\s*!authorized\s*\)/,
      /await\s+fetch\s*\(/,
      true,
    );
    expectGuardBeforeEffect(
      "swan-webhook",
      /if\s*\(\s*!constantTimeSecretEquals\s*\(/,
      /\.rpc\s*\(\s*["']fn_swan_webhook_reclamer["']/,
      true,
    );

    const invoiceSource = withoutComments(functionSource("generate-invoice"));
    const invoiceHandler = invoiceSource.slice(invoiceSource.indexOf("Deno.serve"));
    expect(invoiceHandler).toMatch(
      /if\s*\(\s*isServiceRole\s*\)[\s\S]*validateServiceRoleReason\s*\(/,
    );
    expect(invoiceHandler).toMatch(
      /else\s*\{[\s\S]*supabaseUser\.auth\.getUser\s*\(\s*token\s*\)/,
    );
    expectGuardBeforeEffect(
      "generate-invoice",
      /const\s+isServiceRole\s*=\s*token\s*===\s*serviceRoleKey/,
      /\.from\s*\(/,
      true,
    );
  });

  it("impose le helper partagé aux sept crons Edge critiques", () => {
    const critical = [
      "email-cron",
      "escrow-debit-echeance",
      "escrow-release",
      "litige-escalation-cron",
      "process-externalisation-actions",
      "process-stripe-refunds",
      "weekly-invoicing-cron",
    ];
    for (const slug of critical) {
      const source = withoutComments(functionSource(slug));
      expect(source).toMatch(
        /await\s+verifyCronServiceAuth\s*\(\s*req\s*,/,
      );
      expect(source).toMatch(/if\s*\(\s*!auth\.ok\s*\)/);
      expect(source).toMatch(/isCronAuthProbe\s*\(\s*req\s*\)/);
      expect(source).not.toContain("async function bearerAutorise");
    }
  });

  it("retire définitivement admin-2fa du dépôt et de la config", () => {
    expect(configured.has("admin-2fa")).toBe(false);
    expect(existsSync(`${root}/supabase/functions/admin-2fa/index.ts`)).toBe(false);
  });
});
