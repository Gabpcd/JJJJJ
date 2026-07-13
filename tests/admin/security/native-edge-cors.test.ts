import { existsSync, readFileSync, readdirSync, statSync } from 'node:fs';
import { join, relative } from 'node:path';
import ts from 'typescript';
import { describe, expect, it } from 'vitest';

const ROOT = process.cwd();
const SRC_ROOT = join(ROOT, 'src');
const FUNCTIONS_ROOT = join(ROOT, 'supabase/functions');
const NATIVE_ORIGINS = ['capacitor://localhost', 'https://localhost'] as const;

function sourceFiles(directory: string): string[] {
  return readdirSync(directory).flatMap((entry) => {
    const path = join(directory, entry);
    if (statSync(path).isDirectory()) return sourceFiles(path);
    return /\.(?:ts|tsx)$/.test(entry) ? [path] : [];
  });
}

function normaliseFunctionSlug(value: string): string | null {
  const slug = value.split('?')[0]?.trim();
  return slug && /^[a-z0-9-]+$/.test(slug) ? slug : null;
}

function collectStringLiterals(node: ts.Node, values: Set<string>): void {
  if (ts.isStringLiteralLike(node)) values.add(node.text);
  node.forEachChild((child) => collectStringLiterals(child, values));
}

let cachedFrontendEdgeFunctions: { slugs: Set<string>; unresolved: string[] } | null = null;

function frontendEdgeFunctions(): { slugs: Set<string>; unresolved: string[] } {
  if (cachedFrontendEdgeFunctions) return cachedFrontendEdgeFunctions;
  const slugs = new Set<string>();
  const unresolved: string[] = [];

  for (const file of sourceFiles(SRC_ROOT)) {
    const source = readFileSync(file, 'utf8');
    const sourceFile = ts.createSourceFile(
      file,
      source,
      ts.ScriptTarget.Latest,
      true,
      file.endsWith('.tsx') ? ts.ScriptKind.TSX : ts.ScriptKind.TS,
    );

    const visit = (node: ts.Node): void => {
      if (
        ts.isCallExpression(node)
        && ts.isPropertyAccessExpression(node.expression)
        && node.expression.name.text === 'invoke'
        && ts.isPropertyAccessExpression(node.expression.expression)
        && node.expression.expression.name.text === 'functions'
      ) {
        const names = new Set<string>();
        if (node.arguments[0]) collectStringLiterals(node.arguments[0], names);
        const resolved = [...names]
          .map(normaliseFunctionSlug)
          .filter((value): value is string => value !== null);
        if (resolved.length === 0) {
          const position = sourceFile.getLineAndCharacterOfPosition(node.getStart(sourceFile));
          unresolved.push(`${relative(ROOT, file)}:${position.line + 1}`);
        }
        resolved.forEach((slug) => slugs.add(slug));
      }
      node.forEachChild(visit);
    };
    visit(sourceFile);

    for (const match of source.matchAll(/\/functions\/v1\/([a-z0-9-]+)/g)) {
      slugs.add(match[1]);
    }
  }

  cachedFrontendEdgeFunctions = { slugs, unresolved };
  return cachedFrontendEdgeFunctions;
}

describe('CORS natif de toutes les Edge Functions appelées par le frontend', () => {
  it('le helper partagé autorise explicitement les deux origines Capacitor', () => {
    const sharedCors = readFileSync(join(FUNCTIONS_ROOT, '_shared/cors.ts'), 'utf8');
    for (const origin of NATIVE_ORIGINS) expect(sharedCors).toContain(`'${origin}'`);
  });

  it('résout statiquement chaque nom de fonction invoqué', () => {
    const { unresolved } = frontendEdgeFunctions();
    expect(unresolved).toEqual([]);
  }, 20_000);

  it('chaque fonction appelée existe et utilise le helper partagé ou une whitelist native complète', () => {
    const { slugs } = frontendEdgeFunctions();
    expect(slugs.size).toBeGreaterThan(30);

    const failures: string[] = [];
    for (const slug of [...slugs].sort()) {
      const path = join(FUNCTIONS_ROOT, slug, 'index.ts');
      if (!existsSync(path)) {
        failures.push(`${slug}: fichier Edge Function absent`);
        continue;
      }

      const source = readFileSync(path, 'utf8');
      const usesSharedCors = /from\s+['"]\.\.\/_shared\/cors\.ts['"]/.test(source)
        && /\b(?:corsHeaders|jsonResponse|preflightResponse)\(req\b/.test(source);
      const hasCompleteLocalWhitelist = source.includes('Access-Control-Allow-Origin')
        && NATIVE_ORIGINS.every((origin) => source.includes(origin));

      if (!usesSharedCors && !hasCompleteLocalWhitelist) {
        failures.push(`${slug}: origines Capacitor incomplètes`);
      }
    }

    expect(failures).toEqual([]);
  }, 20_000);
});
