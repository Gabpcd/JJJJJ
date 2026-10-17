import { expect, test, type Page } from '@playwright/test';
import { creerMissionSimulee, ids } from './helpers/recette-complete-mission';

// Vrais route /soignant/presences, bouton QR, Dialog et Html5Qrcode.
// API, caméra (flux canvas) et résultat BarcodeDetector simulés : aucune caméra
// physique ni mutation réelle. Aucun composant ni callback applicatif remplacé.
async function simulerCamera(page: Page, mode: 'ok' | 'refus' | 'attente' | 'absente' = 'ok') {
  await page.addInitScript(modeCamera => {
    const state = {
      qr: null as string | null,
      demandes: 0,
      decodages: 0,
      streams: [] as MediaStream[],
      autoriser: null as (() => void) | null,
    };
    (window as any).__qrSimulation = state;
    Object.defineProperty(window, 'BarcodeDetector', { configurable: true, value: class {
      static async getSupportedFormats() { return ['qr_code']; }
      async detect() {
        state.decodages++;
        return state.qr === null ? [] : [{ rawValue: state.qr, format: 'qr_code',
          boundingBox: { x: 0, y: 0, width: 250, height: 250 }, cornerPoints: [] }];
      }
    } });
    Object.defineProperty(navigator, 'mediaDevices', { configurable: true, value: modeCamera === 'absente' ? undefined : {
      async getUserMedia() {
        state.demandes++;
        if (modeCamera === 'refus') throw new DOMException('Permission denied', 'NotAllowedError');
        if (modeCamera === 'attente') await new Promise<void>(resolve => { state.autoriser = resolve; });
        const canvas = document.createElement('canvas');
        canvas.width = 640; canvas.height = 480;
        const ctx = canvas.getContext('2d')!;
        let frame = 0;
        const dessiner = () => { ctx.fillStyle = frame++ % 2 ? '#fff' : '#fefefe'; ctx.fillRect(0, 0, 640, 480); };
        dessiner();
        const stream = canvas.captureStream(10);
        const timer = window.setInterval(dessiner, 100);
        for (const track of stream.getTracks()) {
          const stop = track.stop.bind(track);
          track.stop = () => { window.clearInterval(timer); stop(); };
        }
        state.streams.push(stream);
        return stream;
      },
      async enumerateDevices() { return [{ kind: 'videoinput', deviceId: 'camera-simulee', label: 'Caméra simulée' }]; },
    } });
  }, mode);
}

async function statsCamera(page: Page) {
  return page.evaluate(() => {
    const s = (window as any).__qrSimulation;
    return { demandes: s.demandes as number, decodages: s.decodages as number, flux: s.streams.length as number,
      pistesActives: s.streams.flatMap((stream: MediaStream) => stream.getTracks()).filter((track: MediaStreamTrack) => track.readyState === 'live').length as number };
  });
}

function fixture() {
  const simulation = creerMissionSimulee();
  const { state } = simulation;
  state.contratCree = true;
  Object.assign(state.contrat, { statut: 'SIGNE_COMPLET', signature_soignant: true, signature_etablissement: true });
  Object.assign(state.mission, { statut: 'ASSIGNEE', soignant_assigne_id: ids.soignant });
  return simulation;
}

test('QR web — clic, annulation, QR malformé, pointage unique et reprise après rechargement', async ({ context, page }, info) => {
  const simulation = fixture(); const { state } = simulation;
  await simulation.installer(context, 'SOIGNANT');
  await simulerCamera(page);
  await page.clock.setFixedTime(new Date('2026-09-24T07:00:00Z'));
  await page.goto('/soignant/presences?tab=aujourdhui');
  const qr = page.getByRole('button', { name: 'QR', exact: true });
  await expect(qr).toBeVisible();
  expect((await statsCamera(page)).demandes).toBe(0);
  await qr.click();
  const dialog = page.getByRole('dialog', { name: 'Scanner le QR de pointage' });
  await expect(dialog).toBeVisible();
  await expect(dialog.getByRole('button', { name: '📷 Scanner le QR code', exact: true })).toHaveCount(0);
  await expect.poll(async () => (await statsCamera(page)).decodages).toBeGreaterThan(0);
  await info.attach('qr-ouvert-aria', { body: await dialog.ariaSnapshot(), contentType: 'text/plain' });
  await page.screenshot({ path: info.outputPath('qr-ouvert.png'), animations: 'disabled' });
  await dialog.getByRole('button', { name: 'Annuler le scan QR' }).click();
  await expect(dialog).toBeHidden();
  await expect.poll(async () => (await statsCamera(page)).pistesActives).toBe(0);
  expect(state.calls.filter(call => call.name === 'fn_scanner_code_pointage')).toHaveLength(0);

  await qr.click(); await expect(dialog).toBeVisible();
  await page.evaluate(() => { (window as any).__qrSimulation.qr = 'https://exemple.invalid/654321'; });
  await expect(dialog.getByRole('alert')).toHaveText('QR non reconnu. Saisissez le code à 6 chiffres.');
  expect(state.calls.filter(call => call.name === 'fn_scanner_code_pointage')).toHaveLength(0);
  expect((await statsCamera(page)).pistesActives).toBe(1);
  await info.attach('qr-malforme-aria', { body: await dialog.ariaSnapshot(), contentType: 'text/plain' });

  state.scanTimes.push('2026-09-24T07:00:00Z');
  // La même valeur reste présente à toutes les frames : une seule mutation.
  await page.evaluate(() => { (window as any).__qrSimulation.qr = '654321'; });
  await expect(dialog.getByText('Pointage enregistré — segment ouvert', { exact: true })).toBeVisible();
  await expect(dialog).toBeHidden();
  await expect.poll(async () => (await statsCamera(page)).pistesActives).toBe(0);
  await expect(page.getByRole('button', { name: 'Pointer mon départ / pause', exact: true })).toBeVisible();
  expect(state.calls.filter(call => call.name === 'fn_scanner_code_pointage')).toHaveLength(1);
  expect(state.segments).toHaveLength(1);
  expect(state.segments[0].fin).toBeNull();
  const camera = await statsCamera(page);
  expect(camera.demandes).toBe(4); // permission + lecteur, sur deux ouvertures
  await page.reload();
  await expect(page.getByRole('button', { name: 'Pointer mon départ / pause', exact: true })).toBeVisible();
  await expect(dialog).toBeHidden();
  expect((await statsCamera(page)).demandes).toBe(0);
  expect(state.calls.filter(call => call.name === 'fn_scanner_code_pointage')).toHaveLength(1);
  expect(state.unknown).toEqual([]); expect(state.errors).toEqual([]);
  await info.attach('qr-reprise-aria', { body: await page.locator('main').ariaSnapshot(), contentType: 'text/plain' });
  await info.attach('qr-mutations-et-camera-simulees', { body: JSON.stringify({ camera, segments: state.segments,
    scans: state.calls.filter(call => call.name === 'fn_scanner_code_pointage') }, null, 2), contentType: 'application/json' });
  expect(await page.evaluate(() => document.documentElement.scrollWidth <= document.documentElement.clientWidth)).toBe(true);
});

for (const mode of ['refus', 'absente'] as const) {
  test(`QR web — caméra ${mode}, fermeture et saisie manuelle conservée`, async ({ context, page }, info) => {
    const simulation = fixture(); const { state } = simulation;
    await simulation.installer(context, 'SOIGNANT'); await simulerCamera(page, mode);
    await page.clock.setFixedTime(new Date('2026-09-24T07:00:00Z'));
    await page.goto('/soignant/presences?tab=aujourdhui');
    await page.getByRole('button', { name: 'QR', exact: true }).click();
    const dialog = page.getByRole('dialog', { name: 'Scanner le QR de pointage' });
    await expect(dialog.getByRole('alert')).toContainText(mode === 'refus'
      ? 'Accès à la caméra refusé.' : 'Impossible d’ouvrir la caméra');
    expect(state.calls.filter(call => call.name === 'fn_scanner_code_pointage')).toHaveLength(0);
    await info.attach(`camera-${mode}-aria`, { body: await dialog.ariaSnapshot(), contentType: 'text/plain' });
    await dialog.getByRole('button', { name: 'Annuler le scan QR' }).click();
    await expect(dialog).toBeHidden();
    state.scanTimes.push('2026-09-24T07:00:00Z');
    await page.getByRole('textbox', { name: 'Code de pointage à 6 chiffres' }).fill('654321');
    await page.getByRole('button', { name: 'Pointer mon arrivée', exact: true }).click();
    await expect(page.getByRole('button', { name: 'Pointer mon départ / pause', exact: true })).toBeVisible();
    expect(state.calls.filter(call => call.name === 'fn_scanner_code_pointage')).toHaveLength(1);
    expect((await statsCamera(page)).pistesActives).toBe(0);
    expect(state.unknown).toEqual([]); expect(state.errors).toEqual([]);
  });
}

test('QR web — annuler pendant la permission ne démarre pas une caméra tardive', async ({ context, page }, info) => {
  const simulation = fixture(); const { state } = simulation;
  await simulation.installer(context, 'SOIGNANT'); await simulerCamera(page, 'attente');
  await page.clock.setFixedTime(new Date('2026-09-24T07:00:00Z'));
  await page.goto('/soignant/presences?tab=aujourdhui');
  await page.getByRole('button', { name: 'QR', exact: true }).click();
  const dialog = page.getByRole('dialog', { name: 'Scanner le QR de pointage' });
  await expect(dialog).toBeVisible();
  await expect.poll(async () => (await statsCamera(page)).demandes).toBe(1);
  await dialog.getByRole('button', { name: 'Annuler le scan QR' }).click();
  await expect(dialog).toBeHidden();
  await page.evaluate(() => { (window as any).__qrSimulation.autoriser(); });
  await expect.poll(async () => (await statsCamera(page)).flux).toBe(1);
  await expect.poll(async () => (await statsCamera(page)).pistesActives).toBe(0);
  expect((await statsCamera(page)).demandes).toBe(1);
  expect((await statsCamera(page)).decodages).toBe(0);
  expect(state.calls.filter(call => call.name === 'fn_scanner_code_pointage')).toHaveLength(0);
  expect(state.unknown).toEqual([]); expect(state.errors).toEqual([]);
  await info.attach('qr-annule-permission-aria', { body: await page.locator('main').ariaSnapshot(), contentType: 'text/plain' });
});
