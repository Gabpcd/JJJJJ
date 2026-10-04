import { test, expect, type Page } from '@playwright/test';
import { readFileSync } from 'node:fs';
import { createHash } from 'node:crypto';
import { readBrowserInput } from '../browser-input.mjs';

// This file receives only synthetic credentials and the target's public anon key.
// Never put the service key, database dump or raw checkpoint into this input.
const fixture = readBrowserInput();
type Member = { id: string; email: string; password: string; role: string };
const missionTitle = 'RECETTE CONNECT TEST SYNTHETIQUE connect-test-restore-' + fixture.run.slice('jolene-restore-drill-'.length);
const route = (role: string) => `/${role === 'SOIGNANT' ? 'soignant' : 'etablissement'}/missions/${fixture.missionId}`;
const pdfButton = (page: Page) => page.getByRole('button', { name: `Télécharger le PDF ${fixture.invoiceNumber}`, exact: true });
const hash = (bytes: Buffer) => createHash('sha256').update(bytes).digest('hex');

test.beforeEach(async ({ context, page }) => {
  // Only a consent preference; no session, user, role or backend response injected.
  await page.addInitScript(() => localStorage.setItem('cookie-consent', 'refused'));
  let externalAttempts = 0, pageErrors = 0;
  context.on('page', extra => extra.on('pageerror', () => pageErrors++));
  page.on('pageerror', () => pageErrors++);
  await context.route('**/*', async request => {
    const url = new URL(request.request().url());
    if (url.origin === fixture.appUrl || url.origin === fixture.apiUrl || ['blob:', 'data:'].includes(url.protocol)) return request.continue();
    externalAttempts++; return request.abort('blockedbyclient');
  });
  // Real sockets can only reach the internal Docker network. No fake Realtime.
  // The absent Realtime service is a declared limitation, never a console-clean claim.
  (page as any).__restoreFailures = () => ({ externalAttempts, pageErrors });
});
test.afterEach(async ({ page }) => {
  expect((page as any).__restoreFailures(), 'No external resource or unhandled App failure').toEqual({ externalAttempts: 0, pageErrors: 0 });
});

async function login(page: Page, member: Member) {
  await page.goto('/connexion');
  await page.locator('input[type=email]').fill(member.email);
  await page.locator('input[type=password]').first().fill(member.password);
  const authenticated = page.waitForResponse(response => response.url().startsWith(fixture.apiUrl + '/auth/v1/token?grant_type=password')
    && response.request().method() === 'POST');
  await page.getByTestId('login-submit').click();
  expect((await authenticated).status()).toBe(200);
  await expect(page).toHaveURL(new RegExp(`/${member.role === 'SOIGNANT' ? 'soignant' : 'etablissement'}/`));
  // Finish the real post-login navigation before opening a second document.
  if (member.role === 'SOIGNANT') await expect(page.getByRole('heading', { level: 1, name: /^(Bonjour|Bonsoir),/ })).toBeVisible();
  else await expect(page.getByTestId('dashboard-etablissement-ready')).toBeAttached();
  expect(await access(page, member.id, false)).toMatchObject({ userStatus: 200, sameUser: true });
}

async function invoiceVisible(page: Page, member: Member) {
  await expect(page.getByRole('heading', { level: 1, name: missionTitle, exact: true })).toBeVisible();
  if (member.role === 'SOIGNANT') {
    await expect(page.getByRole('region', { name: 'Planning exact de la mission', exact: true }).getByText('8 h au total', { exact: true })).toBeVisible();
  } else {
    await expect(page.getByText('2 créneaux · 8 h planifiées au total', { exact: true })).toBeVisible();
  }
  const title = member.role === 'SOIGNANT' ? 'Vos documents d’honoraires pour cette mission' : 'Documents d’honoraires du soignant';
  const card = page.locator('.card-base').filter({ has: page.getByRole('heading', { name: title, exact: true }) });
  await expect(card.getByText('1 document', { exact: true })).toBeVisible();
  const row = card.locator('.space-y-2.p-3').filter({ has: page.getByText(fixture.invoiceNumber, { exact: true }) });
  await expect(row).toHaveCount(1);
  await expect(row.getByText('Émise', { exact: true })).toBeVisible();
  await expect(row.getByText(/^80,00\s*€$/)).toBeVisible();
  await expect(pdfButton(page)).toBeEnabled();
}

async function access(page: Page, userId: string | null, checkDocument = true) {
  // Tokens never leave page.evaluate. No replacement of the actual App session.
  return page.evaluate(async ({ apiUrl, anonKey, id, invoiceId, objectKey, check }) => {
    const storageKey = `sb-${new URL(apiUrl).hostname.split('.')[0]}-auth-token`;
    const session = JSON.parse(sessionStorage.getItem(storageKey) || 'null');
    const token = id ? session?.access_token : anonKey;
    if (typeof token !== 'string') return { sessionPresent: false };
    const headers = { apikey: anonKey, Authorization: 'Bearer ' + token, 'X-Supabase-Api-Version': '2024-01-01' };
    let identity: any = null, userStatus = 0;
    if (id) {
      const user = await fetch(apiUrl + '/auth/v1/user', { headers, redirect: 'error' });
      userStatus = user.status; identity = await user.json();
    }
    if (!check) return { userStatus, sameUser: identity?.id === id };
    const rows = await fetch(apiUrl + '/rest/v1/factures_honoraires?select=id&id=eq.' + invoiceId, { headers, redirect: 'error' });
    const records = await rows.json();
    const signed = await fetch(apiUrl + '/storage/v1/object/sign/jolene-documents/' + objectKey, {
      method: 'POST', headers: { ...headers, 'Content-Type': 'application/json' }, body: JSON.stringify({ expiresIn: 60 }), redirect: 'error',
    });
    const result = await signed.json();
    return { userStatus, sameUser: id !== null && identity?.id === id, rowStatus: rows.status,
      exactInvoice: Array.isArray(records) && records.length === 1 && records[0].id === invoiceId,
      emptyRows: Array.isArray(records) && records.length === 0,
      signStatus: signed.status, signedPresent: typeof (result.signedURL ?? result.signedUrl) === 'string' };
  }, { apiUrl: fixture.apiUrl, anonKey: fixture.anonKey, id: userId, invoiceId: fixture.invoiceId,
    objectKey: fixture.pdfKey, check: checkDocument });
}

async function download(page: Page) {
  const pending = page.waitForEvent('download');
  await pdfButton(page).click();
  const file = await pending;
  expect(await file.failure()).toBeNull();
  const path = await file.path();
  expect(path !== null).toBe(true);
  const bytes = readFileSync(path!);
  expect(bytes.length).toBe(fixture.pdfBytes);
  expect(hash(bytes)).toBe(fixture.pdfSha256);
  expect(bytes.subarray(0, 5).toString()).toBe('%PDF-');
  expect(bytes.toString('utf8')).toContain(`RESTORE SYNTHETIC ONLY ${fixture.invoiceId} - 4h x EUR20 = EUR80 - NO PAYMENT`);
  // No attachment: a failed assertion is retained only in the private raw JSON.
}

for (const [caseId, index] of [['RESTORE_OWNER_S', 0], ['RESTORE_OWNER_E', 1]] as const) test(caseId, async ({ page }) => {
  const member: Member = fixture.members[index];
  await login(page, member);
  await page.goto(route(member.role));
  await invoiceVisible(page, member);
  expect(await access(page, member.id)).toMatchObject({ userStatus: 200, sameUser: true, rowStatus: 200, exactInvoice: true,
    signStatus: 200, signedPresent: true });
  await download(page);
  await page.reload();
  await invoiceVisible(page, member);
  expect(await access(page, member.id)).toMatchObject({ userStatus: 200, sameUser: true, rowStatus: 200, exactInvoice: true,
    signStatus: 200, signedPresent: true });
  await download(page);
});

for (const [caseId, index] of [['RESTORE_OTHER_S', 2], ['RESTORE_OTHER_E', 3]] as const) test(caseId, async ({ page }) => {
  const member: Member = fixture.members[index];
  await login(page, member);
  await page.goto(route(member.role));
  // This fixture is EN_COURS and assigned: the canonical mission RLS also
  // denies both outsiders. Open mission discovery is outside this scenario.
  for (let pass = 0; pass < 2; pass++) {
    // Absence is asserted only after the real route has resolved, never during a spinner.
    await expect(page.getByRole('heading', { level: 1, name: member.role === 'SOIGNANT' ? 'Mission introuvable' : 'Impossible de charger la mission', exact: true })).toBeVisible();
    await expect(pdfButton(page)).toHaveCount(0);
    const result = await access(page, member.id);
    expect(result).toMatchObject({ userStatus: 200, sameUser: true, rowStatus: 200, exactInvoice: false, emptyRows: true, signedPresent: false });
    expect([400, 403, 404]).toContain(result.signStatus);
    if (pass === 0) await page.reload();
  }
  await expect(pdfButton(page)).toHaveCount(0);
});

test('RESTORE_ANONYMOUS', async ({ page }) => {
  await page.goto(route('SOIGNANT'));
  for (let pass = 0; pass < 2; pass++) {
    await expect(page).toHaveURL(/\/connexion/);
    await expect(page.getByTestId('login-submit')).toBeVisible();
    const result = await access(page, null);
    expect(result.exactInvoice).toBe(false);
    expect(result.signedPresent).toBe(false);
    expect(result.rowStatus === 200 ? result.emptyRows : [401, 403].includes(result.rowStatus!)).toBe(true);
    expect([400, 401, 403, 404]).toContain(result.signStatus);
    await expect(pdfButton(page)).toHaveCount(0);
    if (pass === 0) await page.reload();
  }
});
