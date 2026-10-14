// Closed numeric projection of three in-memory signup audit attachments.
// Never open attachment paths or return private strings, messages or URLs.
const MAX_BYTES = 8 * 1024 * 1024;
const MAX_EVENTS = 2048;
const MAX_ERRORS = 256;
const ROLES = { soignant: 40, etab: 39 };
const PHASES = new Set(['navigation', 'settling', 'inspection']);
const SCOPES = new Set(['previous-document', 'current-document', 'unknown']);
const RPC_EVENTS = new Set(['request', 'response', 'requestfinished', 'requestfailed']);
const FAILURE_CODES = new Set(['HTTP2_NO_ERROR', 'CANCELLED_OR_ABORTED', 'OTHER']);
const WS_EVENTS = new Set(['websocket-requested', 'websocket-closed', 'websocket-error', 'console-websocket-error']);
const integer = (value, max) => Number.isSafeInteger(value) && value >= 0 && value <= max;
const object = value => value !== null && typeof value === 'object' && !Array.isArray(value);
function check(value) { if (!value) throw new Error('SIGNUP_AUDIT_REFUSED'); }
function text(value, max = 65536) { check(typeof value === 'string' && value.length <= max); return value; }
function array(value, max) { check(Array.isArray(value) && value.length <= max); return value; }
function status(value) { check(value === null || (integer(value, 599) && value >= 100)); return value; }
function tally(map, value) { const key = JSON.stringify(value); map.set(key, (map.get(key) || 0) + 1); }
function totals(map) { return [...map].map(([key, count]) => ({ ...JSON.parse(key), count })); }

function attachment(attachments, name) {
  const found = attachments.filter(item => object(item) && item.name === name);
  check(found.length === 1);
  const item = found[0];
  check(item.contentType === 'application/json' && !Object.hasOwn(item, 'path'));
  const body = text(item.body, Math.ceil(MAX_BYTES / 3) * 4);
  check(body.length % 4 === 0 && /^[A-Za-z0-9+/]*={0,2}$/.test(body));
  const bytes = Buffer.from(body, 'base64');
  check(bytes.length <= MAX_BYTES && bytes.toString('base64') === body);
  try { return JSON.parse(bytes.toString('utf8')); }
  catch { throw new Error('SIGNUP_AUDIT_REFUSED'); }
}

function category(raw) {
  const value = text(raw);
  if (value.includes('HTTP/2 Error: NO_ERROR')) return 'HTTP2_NO_ERROR';
  if (/WebSocket connection\b/.test(value)) return 'WEBSOCKET';
  if (/Failed to load resource\b/.test(value)) return 'RESOURCE_LOAD';
  if (/Failed to fetch|Load failed|NetworkError/.test(value)) return 'FETCH_FAILED';
  if (/Content Security Policy/.test(value)) return 'CSP';
  return 'OTHER';
}

function endpoint(raw) {
  const value = text(raw, 2048);
  if (value === '/rest/v1/rpc/fn_get_my_role') return 'ROLE_RPC';
  if (value === '/rest/v1/rpc/fn_messages_non_lus') return 'UNREAD_MESSAGES_RPC';
  if (/^\/rest\/v1\/rpc\/[a-zA-Z0-9_]+$/.test(value)) return 'OTHER_RPC';
  if (/^\/rest\/v1\/[a-zA-Z0-9_]+$/.test(value)) return 'REST_RESOURCE';
  if (/^\/functions\/v1\/[a-zA-Z0-9_-]+$/.test(value)) return 'EDGE_FUNCTION';
  if (/^\/auth\/v1\//.test(value)) return 'AUTH';
  if (/^\/storage\/v1\//.test(value)) return 'STORAGE';
  return 'OTHER';
}

export function projectSignupFinalAudit(result, { phase, file }) {
  if (!['series-c-ios', 'series-c-android'].includes(phase)
    || file !== 'e2e/non-regression/signup-series-c-audit.spec.ts') return undefined;
  const attachments = result.attachments ?? [];
  check(Array.isArray(attachments) && attachments.length <= 100);
  const known = attachments.filter(item => object(item) && Object.keys(ROLES).some(role =>
    [`audit-compte-neuf-${role}.json`, `audit-compte-neuf-transport-${role}.json`, `audit-compte-neuf-role-http-${role}.json`].includes(item.name)));
  // A test failing before the final audit has no such attachments. Its original
  // failed/timedOut result still determines the phase outcome, never this absence.
  if (!known.length) return undefined;
  const role = Object.keys(ROLES).find(candidate => known.some(item => item.name === `audit-compte-neuf-${candidate}.json`));
  check(role && known.length === 3);
  const routeCount = ROLES[role];
  const viewports = phase === 'series-c-ios' ? ['375x667', '390x844', '440x956'] : ['412x915'];
  const audit = array(attachment(attachments, `audit-compte-neuf-${role}.json`), routeCount * viewports.length);
  check(audit.length === routeCount * viewports.length);
  const rows = [];
  for (let index = 0; index < audit.length; index++) {
    const row = audit[index];
    const routeIndex = index % routeCount;
    const viewportIndex = Math.floor(index / routeCount);
    check(object(row) && row.viewport === viewports[viewportIndex]);
    // The route remains private, but repeated viewports must retain its ordinal.
    text(row.route, 256);
    check(viewportIndex === 0 || row.route === audit[routeIndex].route);
    const consoleErrors = array(row.consoleErrors, MAX_ERRORS);
    const pageErrors = array(row.pageErrors, MAX_ERRORS);
    const apiErrors = array(row.apiErrors, MAX_ERRORS);
    const consoleCategories = new Map(), pageCategories = new Map(), apiResponses = new Map();
    for (const value of consoleErrors) tally(consoleCategories, { category: category(value) });
    for (const value of pageErrors) tally(pageCategories, { category: category(value) });
    for (const value of apiErrors) {
      check(object(value) && integer(value.status, 599) && value.status >= 400);
      tally(apiResponses, { endpoint: endpoint(value.path), status: value.status });
    }
    if (consoleErrors.length || pageErrors.length || apiErrors.length) rows.push({
      routeIndex, viewportIndex, consoleCount: consoleErrors.length,
      pageErrorCount: pageErrors.length, apiErrorCount: apiErrors.length,
      consoleCategories: totals(consoleCategories), pageCategories: totals(pageCategories), apiResponses: totals(apiResponses),
    });
  }

  const roleHttp = attachment(attachments, `audit-compte-neuf-role-http-${role}.json`);
  check(object(roleHttp) && roleHttp.truncated === false);
  const rpc = new Map();
  for (const event of array(roleHttp.events, MAX_EVENTS)) {
    check(object(event) && integer(event.navigationId, routeCount * viewports.length)
      && Number.isSafeInteger(event.matrixIndex) && event.matrixIndex >= -1 && event.matrixIndex < routeCount
      && PHASES.has(event.phase) && SCOPES.has(event.scope) && RPC_EVENTS.has(event.event)
      && (event.failureCode === null || FAILURE_CODES.has(event.failureCode)));
    status(event.httpStatus);
    if (event.navigationId === 0) { check(event.matrixIndex === -1); continue; }
    const routeIndex = (event.navigationId - 1) % routeCount;
    const viewportIndex = Math.floor((event.navigationId - 1) / routeCount);
    check(event.matrixIndex === routeIndex);
    if (event.event === 'requestfailed' || (event.httpStatus !== null && event.httpStatus >= 400)) tally(rpc, {
      routeIndex, viewportIndex, event: event.event, phase: event.phase, scope: event.scope,
      failureCode: event.failureCode, status: event.httpStatus,
    });
  }

  const websocket = new Map();
  for (const event of array(attachment(attachments, `audit-compte-neuf-transport-${role}.json`), MAX_EVENTS)) {
    check(object(event) && integer(event.matrixIndex, routeCount - 1) && PHASES.has(event.phase)
      && WS_EVENTS.has(event.event) && integer(event.connectionAttempt, MAX_EVENTS)
      && integer(event.subsequentAttempts, MAX_EVENTS));
    status(event.httpStatus);
    if (event.event === 'websocket-error' || event.event === 'console-websocket-error') tally(websocket, {
      routeIndex: event.matrixIndex,
      // The existing WS collector has no viewport/navigation identity. Do not
      // infer one from timestamps or error ordering across page navigations.
      viewportIndex: null, event: event.event, phase: event.phase, status: event.httpStatus,
    });
  }
  return { schemaVersion: 1, role, routeCount, viewportCount: viewports.length,
    inspectedCount: audit.length, rows, roleRpcFailures: totals(rpc), websocketErrors: totals(websocket) };
}
