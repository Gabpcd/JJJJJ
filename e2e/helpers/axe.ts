import AxeBuilder from '@axe-core/playwright';
import type { Page, TestInfo } from '@playwright/test';
import { expect } from '@playwright/test';

/**
 * Helper pour audits axe-core dans les tests E2E.
 *
 * Usage typique :
 *   import { runAxe, expectNoCriticalA11y } from './helpers/axe';
 *   const results = await runAxe(page);
 *   expectNoCriticalA11y(results);
 *
 * Pour échec doux (warning seulement), passer { soft: true }.
 */

export async function runAxe(page: Page, opts: { include?: string; tags?: string[] } = {}) {
  let builder = new AxeBuilder({ page });

  // Tags WCAG 2.1 AA par défaut
  builder = builder.withTags(opts.tags || ['wcag2a', 'wcag2aa', 'wcag21a', 'wcag21aa']);

  if (opts.include) {
    builder = builder.include(opts.include);
  }

  return await builder.analyze();
}

/**
 * Échoue le test si des violations CRITIQUES ou SÉRIEUSES sont détectées.
 * Les violations modérées et mineures sont juste loggées (soft).
 */
export function expectNoCriticalA11y(
  results: Awaited<ReturnType<typeof runAxe>>,
  testInfo?: TestInfo,
): void {
  const critical = results.violations.filter((v) => v.impact === 'critical');
  const serious = results.violations.filter((v) => v.impact === 'serious');
  const moderate = results.violations.filter((v) => v.impact === 'moderate');
  const minor = results.violations.filter((v) => v.impact === 'minor');

  const summary = (label: string, viols: typeof results.violations) =>
    viols.length === 0
      ? `[${label}] 0 violation`
      : `[${label}] ${viols.length} violation(s):\n` +
        viols
          .map(
            (v) =>
              `  - ${v.id} (${v.help})\n    ${v.helpUrl}\n    Nodes: ${v.nodes.length}\n    Première occurrence: ${v.nodes[0]?.html?.slice(0, 200) || ''}`,
          )
          .join('\n');

  const fullReport = [
    summary('CRITICAL', critical),
    summary('SERIOUS', serious),
    summary('MODERATE', moderate),
    summary('MINOR', minor),
  ].join('\n');

  // Attache le rapport complet aux artifacts pour debug
  if (testInfo) {
    testInfo.attach('axe-report', { body: fullReport, contentType: 'text/plain' });
  }

  if (critical.length + serious.length > 0) {
    throw new Error(`Violations a11y CRITICAL ou SERIOUS détectées :\n${fullReport}`);
  }

  // Modéré + mineur : juste logger (soft warn)
  if (moderate.length + minor.length > 0) {
    console.warn(`A11y warnings (non bloquants) :\n${summary('MODERATE', moderate)}\n${summary('MINOR', minor)}`);
  }
}

/** Soft mode : log uniquement, ne fait pas échouer le test (utile pour pages WIP). */
export function softCheckA11y(results: Awaited<ReturnType<typeof runAxe>>): void {
  const total = results.violations.length;
  if (total > 0) {
    console.warn(
      `[axe soft] ${total} violation(s) détectée(s) :`,
      results.violations.map((v) => `${v.impact}/${v.id}`).join(', '),
    );
  }
}
