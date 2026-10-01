import { performance } from 'node:perf_hooks';
import { documentBytes, refuse, requireReady, sha256 } from './f1-cloud-core.mjs';

export const FORMATS = Object.freeze([
  { name: 'iphone', engine: 'webkit', device: 'iPhone 13', viewport: { width: 390, height: 844 } },
  { name: 'android', engine: 'chromium', device: 'Pixel 7' },
  { name: 'ipad-portrait', engine: 'webkit', device: 'iPad Pro 11', viewport: { width: 820, height: 1180 } },
  { name: 'ipad-paysage', engine: 'webkit', device: 'iPad Pro 11', viewport: { width: 1180, height: 820 } },
  { name: 'ordinateur', engine: 'chromium', device: 'Desktop Chrome', viewport: { width: 1440, height: 900 } },
]);

// No Auth, REST, Storage or Edge response is manufactured by these actions.
// Navigation and network preflight are independently required by the UI adapter.
export async function loginForm(page, actor, expect) {
  if (!['SOIGNANT', 'ETABLISSEMENT'].includes(actor?.role)) refuse('F1_ACTOR_INVALID');
  await page.goto('/connexion');
  // Every context starts with empty storage. Exercise the same visible choice
  // as a user; never prefill consent or hide the delayed banner.
  const refuseCookies = page.getByRole('button', { name: 'Refuser', exact: true });
  await expect(refuseCookies).toBeVisible();
  await refuseCookies.click();
  await expect(refuseCookies).toHaveCount(0);
  await page.getByLabel('Email', { exact: true }).fill(actor.email);
  await page.getByLabel('Mot de passe', { exact: true }).fill(actor.password);
  await page.getByRole('button', { name: 'Se connecter', exact: true }).click();
  await expect(page).toHaveURL(actor.role === 'SOIGNANT'
    ? /\/soignant\/tableau-de-bord$/ : /\/etablissement\/tableau-de-bord$/);
}

export async function openDocumentScreenF1(page,actor,manifest,expect) {
  const marker=`RECETTE F1 SYNTHETIQUE ${manifest.sql.runId}`;
  if(actor.role==='SOIGNANT')await page.getByRole('link',{name:`Voir la mission ${marker}`,exact:true}).click();
  else {const card=page.locator('.card-base').filter({has:page.getByRole('heading',{level:3,name:marker,exact:true})});
    await expect(card).toHaveCount(1);await card.getByRole('button',{name:'Voir détail',exact:true}).click();}
  await expect(page.getByRole('heading',{level:1,name:marker,exact:true})).toBeVisible();
}

export async function downloadPdf(page, button, document) {
  const start = performance.now();
  // allSettled prevents a late click/download action surviving an early rejection.
  const results = await Promise.allSettled([page.waitForEvent('download', { timeout: 25000 }), button.click()]);
  const download = results[0].status === 'fulfilled' ? results[0].value : null;
  try {
    if (results.some(r => r.status !== 'fulfilled') || !download || await download.failure()) refuse('F1_DOWNLOAD_FAILED');
    const filename = `${document.number.replace(/[^a-zA-Z0-9._-]+/g, '-')}.pdf`;
    if (download.suggestedFilename() !== filename) refuse('F1_DOWNLOAD_NAME');
    const stream = await download.createReadStream();
    if (!stream) refuse('F1_DOWNLOAD_FAILED');
    const chunks = []; let length = 0;
    for await (const chunk of stream) {
      length += chunk.length;
      if (length > 25 * 1024 * 1024) { stream.destroy(); refuse('F1_DOWNLOAD_SIZE'); }
      chunks.push(chunk);
    }
    return { ...documentBytes(Buffer.concat(chunks), { ...document.pdf, format: 'pdf' }),
      duration_ms: Math.max(0, Math.round(performance.now() - start)) };
  } finally { if (download) await download.delete(); }
}

/** For the same two reconciled documents: 2 downloads, then reload, then 2.
 * The deployed UI must contain the independently reviewed EN_COURS access fix.
 * A caller must open the actual document card via visible SPA navigation. */
export async function verifyDocumentCard({ page, expect, documents, drain, capture, onStep = async () => {} }) {
  if (!Array.isArray(documents) || documents.length !== 2
    || documents[0].kind !== 'FACTURE' || documents[1].kind !== 'FACTURE'
    || documents[0].slot !== 'original' || documents[1].slot !== 'replacement'
    || documents[0].id === documents[1].id || documents[0].number === documents[1].number) refuse('F1_DOCUMENT_SET');
  const downloads = [];
  for (const reload of [false, true]) {
    await onStep(reload?'reload':'documents');
    if (reload) { await drain(); await page.reload(); }
    const card=page.locator('.card-base').filter({has:page.getByRole('heading',{level:3,
      name:/^(?:Vos documents d’honoraires pour cette mission|Documents d’honoraires du soignant)$/})});
    await expect(card).toHaveCount(1);await expect(card.getByText('2 documents',{exact:true})).toBeVisible();
    const net=card.locator('div').filter({has:page.getByText('Net facturé',{exact:true})}).filter({has:page.getByText('72,00 €',{exact:true})});
    await expect(net.first()).toBeVisible();
    for (const document of documents) {
      const row=card.locator('.space-y-2.p-3').filter({has:page.getByText(document.number,{exact:true})});
      await expect(row).toHaveCount(1);await expect(row.getByText(document.slot==='original'?'Remplacée':'Émise',{exact:true})).toBeVisible();
      const button = row.getByRole('button', { name: `Télécharger le PDF ${document.number}`, exact: true });
      await expect(button).toBeVisible();
      await expect(button).toBeEnabled();
      await button.evaluate(element => element.scrollIntoView({ block: 'center', behavior: 'instant' }));
      await onStep(`${reload?'reload_':''}download_${document.slot}`);
      downloads.push({ slot: document.slot, reload, ...await downloadPdf(page, button, document) });
    }
    await drain();
    // capture must reject browser/network errors and only screenshot authenticated
    // synthetic content; never a login page, storage URL, trace, HAR or session.
    await capture(reload ? 'reload' : 'documents');
  }
  return downloads;
}

/** Capture short portions after real scrolling, with the normal fixed chrome.
 * Hit-testing all four inset corners refuses an obscured portion. */
export async function captureDocumentPortionsF1(page, role, expect, capture) {
  const title = role === 'SOIGNANT' ? 'Vos documents d’honoraires pour cette mission' : 'Documents d’honoraires du soignant';
  const card = page.locator('.card-base').filter({has:page.getByRole('heading',{level:3,name:title,exact:true})});
  await expect(card).toHaveCount(1);
  if(await card.locator('input').count())refuse('F1_CAPTURE_SCOPE');
  const rows=card.locator('.space-y-2.p-3');await expect(rows).toHaveCount(2);
  for(const [part,locator] of [['header',card.locator(':scope > div').nth(0)],['totals',card.locator(':scope > div').nth(1)],['original',rows.nth(0)],['replacement',rows.nth(1)]]) {
    await locator.evaluate(element=>element.scrollIntoView({block:'center',behavior:'instant'}));
    await expect.poll(()=>locator.evaluate(element=>{const r=element.getBoundingClientRect();return r.top>=0&&r.bottom<=innerHeight&&r.left>=0&&r.right<=innerWidth&&[[r.left+2,r.top+2],[r.right-2,r.top+2],[r.left+2,r.bottom-2],[r.right-2,r.bottom-2]].every(([x,y])=>element.contains(document.elementFromPoint(x,y)));})).toBe(true);
    await capture(locator,part);
  }
}

/** Own contexts and awaited network tasks must be closed before finalize/Auth. */
export async function closeContexts(entries) {
  const results = await Promise.allSettled(entries.map(async ({ context, network }) => {
    let failed = false;
    try { network.close(); } catch { failed = true; }
    try { await network.drain(); } catch { failed = true; }
    try { await context.close(); } catch { failed = true; }
    if (failed) refuse('F1_CONTEXT_CLOSE_FAILED');
  }));
  if (results.some(r => r.status === 'rejected')) refuse('F1_CONTEXT_CLOSE_FAILED');
}

/** Real browser matrix wired to the manually gated CLI. The reviewed network and
 * SPA-navigation adapters are mandatory; neither can be replaced by permissive
 * fallbacks. Public observations never include actor identity or credentials. */
export async function uiMatrixF1({ ctx, preflight, manifest, documents, installNetwork, openScreen,
  capture, observe = async () => {}, env = {}, loadPlaywright = () => import('@playwright/test') }) {
  requireReady(preflight, ctx);
  if (typeof installNetwork !== 'function' || typeof openScreen !== 'function' || typeof capture !== 'function'
    || manifest?.members?.length !== 2
    || manifest.members[0].role !== 'SOIGNANT' || manifest.members[1].role !== 'ETABLISSEMENT') refuse('F1_UI_ADAPTER_PENDING');
  const pw = await loadPlaywright();
  const browsers = new Map(), entries = new Set(), observations = [];
  const browserEnv = Object.fromEntries(['PATH', 'HOME', 'TMPDIR', 'XDG_RUNTIME_DIR', 'DISPLAY', 'WAYLAND_DISPLAY']
    .filter(key => typeof env[key] === 'string').map(key => [key, env[key]]));
  let failed = false;let point={format:null,role:null,phase:'setup'};
  const mark=async phase=>{point={...point,phase};await observe({...point,state:'running'});};
  try {
    for (const format of FORMATS) {
      if (!browsers.has(format.engine)) browsers.set(format.engine, await pw[format.engine].launch({ env: browserEnv }));
      for (const actor of manifest.members) {
        point={format:format.name,role:actor.role,phase:'context'};await mark('context');
        const context = await browsers.get(format.engine).newContext({ ...pw.devices[format.device],
          ...(format.viewport ? { viewport: format.viewport, screen: format.viewport } : {}),
          baseURL: 'http://127.0.0.1:8904', locale: 'fr-FR', timezoneId: 'Europe/Paris',
          acceptDownloads: true, serviceWorkers: 'block' });
        // Record ownership before an interception setup can fail.
        const entry = { context, network: { close() {}, async drain() {} } };
        entries.add(entry);
        const network = await installNetwork(context, actor, manifest, documents, {format:format.name,role:actor.role});
        if (!['close', 'drain', 'assert'].every(key => typeof network?.[key] === 'function')) refuse('F1_UI_ADAPTER_PENDING');
        entry.network = network;
        await context.routeWebSocket('**/*', socket => socket.close());
        const page = await context.newPage();
        page.setDefaultTimeout(20000); page.setDefaultNavigationTimeout(25000);
        let errors = 0;
        page.on('pageerror', () => { errors++; });
        page.on('console', message => { if (message.type() === 'error') errors++; });
        const drain = async () => {
          await entry.network.drain(); await entry.network.assert();
          if (errors) refuse('F1_BROWSER_ERROR');
        };
        await mark('login');await loginForm(page, actor, pw.expect);
        // Use the user's SPA link; hard goto can cancel still-pending dashboard RPCs.
        await mark('mission_navigation');await openScreen(page, actor, manifest, pw.expect);
        const downloads = await verifyDocumentCard({ page, expect: pw.expect, documents, drain,onStep:mark,
          capture: async phase => { await drain(); await capture(page, { format: format.name, role: actor.role, phase }); } });
        await drain();
        if (typeof network.complete === 'function') network.complete();
        await mark('close_context');await closeContexts([entry]); entries.delete(entry);
        if (errors) refuse('F1_BROWSER_ERROR');
        observations.push({ format: format.name, role: actor.role, downloads });
      }
    }
  } catch(error) { failed = true;try {await observe({...point,state:'failed',category:error?.message==='F1_BROWSER_ERROR'?'browser':error?.name==='TimeoutError'?'timeout':error?.name==='AssertionError'?'assertion':'other',exception_sha256:sha256(String(error?.message??''))});}catch{} }
  finally {
    try { await closeContexts([...entries]); } catch { failed = true; }
    const closed = await Promise.allSettled([...browsers.values()].map(browser => browser.close()));
    if (closed.some(r => r.status === 'rejected')) failed = true;
  }
  if (failed) refuse('F1_UI_FAILED_CONTEXTS_FINALIZED');
  return { contextsClosed: true, observations };
}
