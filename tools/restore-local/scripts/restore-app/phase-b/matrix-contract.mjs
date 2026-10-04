// Fixed case IDs are the complete titles in the pinned spec, never arbitrary annotations.
export const CASE_IDS = Object.freeze(['RESTORE_OWNER_S', 'RESTORE_OWNER_E', 'RESTORE_OTHER_S', 'RESTORE_OTHER_E', 'RESTORE_ANONYMOUS']);
export const PROJECT_IDS = Object.freeze(['ipad-portrait', 'ipad-paysage', 'iphone', 'android', 'ordinateur']);
const requireValue = ok => { if (!ok) throw new Error('RESTORE_REPORT_MATRIX'); };
export function assertRestoreMatrix(rawReport, projectedTests, side) {
  requireValue(['source', 'target'].includes(side));
  const expected = new Set((side === 'source' ? CASE_IDS.slice(0, 2) : CASE_IDS).flatMap(caseId =>
    (side === 'source' ? ['ordinateur'] : PROJECT_IDS).map(project => caseId + ':' + project)));
  const rawCases = [];
  const visit = suites => {
    requireValue(Array.isArray(suites));
    for (const suite of suites) {
      requireValue(Array.isArray(suite.specs));
      for (const spec of suite.specs) {
        requireValue(CASE_IDS.includes(spec.title) && Array.isArray(spec.tests));
        for (const result of spec.tests) rawCases.push({ caseId: spec.title, project: result.projectName });
      }
      if (suite.suites !== undefined) visit(suite.suites);
    }
  };
  // projectReport has already checked depth, source location, report shape and
  // outcomes. Its traversal order must match these raw identities exactly.
  visit(rawReport.suites);
  requireValue(rawCases.length === expected.size && projectedTests.length === expected.size);
  const seen = new Set();
  const identified = projectedTests.map((result, index) => {
    const { caseId, project } = rawCases[index];
    const pair = caseId + ':' + project;
    requireValue(expected.has(pair) && !seen.has(pair) && result.project === project
      && result.file === 'e2e/restore-app.spec.ts' && result.expectedStatus === 'passed'
      && result.attempts.length === 1 && result.attempts[0].retry === 0);
    seen.add(pair);
    // Only one of the five constants can be added to the closed public projection.
    return { ...result, caseId };
  });
  requireValue(seen.size === expected.size && [...expected].every(pair => seen.has(pair)));
  return identified;
}
