import { createHash } from 'node:crypto';
import { expect, test, type BrowserContext, type Page } from '@playwright/test';
import { creerActionsNationales } from './helpers/recette-complete-actions-nationales';
import { ids, type RoleRecette } from './helpers/recette-complete-mission';

// Décodage réel des pixels du QRCodeSVG rendu par l'établissement : aucun mock
// Html5Qrcode, ZXing, BarcodeDetector ni callback de scan. Seul le périphérique
// caméra est remplacé par un canvas MediaStream. Le serveur et sa rotation de
// code restent simulés : ce test ne prouve ni le SQL/RLS ni une caméra physique.
async function cameraDepuisImage(page: Page) {
  await page.addInitScript(() => {
    // Choisir le véritable décodeur ZXing fourni par Html5Qrcode sur tous les
    // moteurs, sans injecter une fausse réponse BarcodeDetector.
    Reflect.deleteProperty(window, 'BarcodeDetector');
    if ('BarcodeDetector' in window) throw new Error('Le décodeur ZXing réel ne peut pas être sélectionné');
    const state = { image: null as HTMLImageElement | null, demandes: 0, frames: 0, streams: [] as MediaStream[] };
    (window as any).__qrPixels = state;
    Object.defineProperty(navigator, 'mediaDevices', { configurable: true, value: {
      async getUserMedia() {
        state.demandes++;
        const canvas = document.createElement('canvas');
        canvas.width = 768; canvas.height = 768;
        const ctx = canvas.getContext('2d')!;
        ctx.imageSmoothingEnabled = false;
        const dessiner = () => {
          ctx.fillStyle = state.frames % 2 ? '#fff' : '#fefefe';
          ctx.fillRect(0, 0, canvas.width, canvas.height);
          // Image centrée, marge blanche suffisante, QR entier dans le cadre
          // de 250 px du scanner sur les cinq largeurs de la recette.
          if (state.image) ctx.drawImage(state.image, 258, 258, 252, 252);
          state.frames++;
        };
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
      async enumerateDevices() { return [{ kind: 'videoinput', deviceId: 'qr-pixels', label: 'Image QR de l’établissement' }]; },
    } });
  });
}

async function presenterImage(page: Page, svg: string) {
  // On transmet une image vectorielle issue du DOM E, jamais les six chiffres
  // ni un résultat de décodage au navigateur S.
  await page.evaluate(async source => {
    const image = new Image();
    await new Promise<void>((resolve, reject) => {
      image.onload = () => resolve();
      image.onerror = () => reject(new Error('Image QR établissement illisible'));
      image.src = `data:image/svg+xml;charset=utf-8,${encodeURIComponent(source)}`;
    });
    (window as any).__qrPixels.image = image;
  }, svg);
}

async function cameraStats(page: Page) {
  return page.evaluate(() => {
    const s = (window as any).__qrPixels;
    return { demandes: s.demandes as number, frames: s.frames as number,
      barcodeDetectorPresent: 'BarcodeDetector' in window,
      pistesActives: s.streams.flatMap((stream: MediaStream) => stream.getTracks()).filter((track: MediaStreamTrack) => track.readyState === 'live').length as number };
  });
}

async function ouvrirLecteur(page: Page) {
  await page.evaluate(() => { (window as any).__qrPixels.image = null; });
  await page.getByRole('button', { name: 'QR', exact: true }).click();
  const dialog = page.getByRole('dialog', { name: 'Scanner le QR de pointage' });
  await expect(dialog).toBeVisible();
  await expect(dialog.locator('video')).toBeVisible();
  await expect.poll(async () => (await cameraStats(page)).pistesActives).toBe(1);
  return dialog;
}

for (const permissionEtab of ['PROPRIETAIRE', 'POINTAGE_ONLY'] as const) {
test(`QR réel — ${permissionEtab} — pixels établissement, un pointage, nouveau QR puis rejet de l’ancien code`, async ({ browser, context, page }, info) => {
  const simulation = creerActionsNationales();
  const { state, control } = simulation;
  state.contratCree = true;
  Object.assign(state.contrat, { statut: 'SIGNE_COMPLET', signature_soignant: true, signature_etablissement: true });
  Object.assign(state.mission, { statut: 'ASSIGNEE', soignant_assigne_id: ids.soignant });
  control.heurePointage = '2026-09-24T07:00:00.000Z';

  // Le harnais existant change control.codePointage exclusivement après un
  // pointage accepté. Compléter seulement sa lecture d'état côté frontend.
  const installer = async (target: BrowserContext, role: RoleRecette) => {
    await simulation.installer(target, role);
    if (role === 'ADMIN_ETABLISSEMENT' && permissionEtab === 'POINTAGE_ONLY') {
      const headers = { 'access-control-allow-origin': '*', 'access-control-allow-headers': '*', 'access-control-allow-methods': 'GET,POST,OPTIONS' };
      await target.route('**/rest/v1/rpc/fn_mes_permissions_etab', async route => {
        const request = route.request();
        if (!['127.0.0.1', 'localhost'].includes(new URL(request.url()).hostname)) return route.abort();
        if (request.method() === 'OPTIONS') return route.fulfill({ status: 204, headers });
        expect(request.method()).toBe('POST');
        expect(request.headers().authorization).toBe('Bearer simulation-mission-ADMIN_ETABLISSEMENT');
        const body = request.postDataJSON();
        expect([null, ids.etablissement]).toContain(body.p_etablissement_id ?? null);
        state.calls.push({ role, name: 'fn_mes_permissions_etab', method: request.method(), body });
        return route.fulfill({ headers, json: { success: true, role: permissionEtab, etablissement_id: ids.etablissement,
          permissions: Object.fromEntries(['gerer_equipe', 'supprimer_compte', 'profil_etab', 'paiement', 'lecture_paiement',
            'missions', 'candidatures', 'contrats', 'pointage', 'rh', 'lecture', 'lecture_pointage'].map(name => [name,
              ['pointage', 'lecture', 'lecture_pointage'].includes(name)])) } });
      });
      // RLS des contrats inchangée : aucune ligne n'est accessible à ce membre.
      await target.route('**/rest/v1/contrats_mission?*', async route => {
        const request = route.request();
        if (!['127.0.0.1', 'localhost'].includes(new URL(request.url()).hostname)) return route.abort();
        if (request.method() === 'OPTIONS') return route.fulfill({ status: 204, headers });
        expect(request.method()).toBe('GET');
        expect(request.headers().authorization).toBe('Bearer simulation-mission-ADMIN_ETABLISSEMENT');
        state.calls.push({ role, name: 'contrats_mission', method: request.method(), body: null });
        return route.fulfill({ headers, json: [] });
      });
      await target.route('**/rest/v1/rpc/fn_presences_detail_mission', async route => {
        const request = route.request();
        if (!['127.0.0.1', 'localhost'].includes(new URL(request.url()).hostname)) return route.abort();
        if (request.method() === 'OPTIONS') return route.fulfill({ status: 204, headers });
        expect(request.method()).toBe('POST');
        expect(request.headers().authorization).toBe('Bearer simulation-mission-ADMIN_ETABLISSEMENT');
        expect(request.postDataJSON()).toEqual({ p_mission_id: ids.mission });
        state.calls.push({ role, name: 'fn_presences_detail_mission', method: request.method(), body: request.postDataJSON() });
        return route.fulfill({ headers, json: { pointage_effectue: !!state.presence, heures_planifiees: state.mission.duree_heures,
          pointage_arrivee: state.presence?.pointage_arrivee_le ?? null,
          pointage_depart: state.presence?.pointage_depart_le ?? null, pauses: [], nb_pauses: 0 } });
      });
    }
    await target.route('**/rest/v1/rpc/fn_etat_pointage_mission', async route => {
      const request = route.request(); const url = new URL(request.url());
      if (!['127.0.0.1', 'localhost'].includes(url.hostname)) return route.abort();
      const headers = { 'access-control-allow-origin': '*', 'access-control-allow-headers': '*', 'access-control-allow-methods': 'POST,OPTIONS' };
      if (request.method() === 'OPTIONS') return route.fulfill({ status: 204, headers });
      expect(request.method()).toBe('POST');
      expect(request.headers().authorization).toBe(`Bearer simulation-mission-${role}`);
      const body = request.postDataJSON();
      expect(body).toEqual({ p_mission_id: ids.mission });
      state.calls.push({ role, name: 'fn_etat_pointage_mission', method: request.method(), body });
      const ouvert = state.segments.some(segment => !segment.fin);
      return route.fulfill({ headers, json: { statut: state.mission.statut, segment_ouvert: ouvert,
        prochain_type_scan: ouvert ? 'FERMETURE' : 'OUVERTURE', segments: state.segments,
        code_pointage_actif: role === 'ADMIN_ETABLISSEMENT' ? control.codePointage : null } });
    });
  };

  await installer(context, 'SOIGNANT'); await cameraDepuisImage(page);
  await page.clock.setFixedTime(new Date(control.heurePointage));
  const etabContext = await browser.newContext({ ...info.project.use });
  await installer(etabContext, 'ADMIN_ETABLISSEMENT');
  const etab = await etabContext.newPage();
  await etab.clock.setFixedTime(new Date(control.heurePointage));
  const scans = () => state.calls.filter(call => call.name === 'fn_scanner_code_pointage');
  const lecturesE = () => state.calls.filter(call => call.name === 'fn_etat_pointage_mission' && call.role === 'ADMIN_ETABLISSEMENT').length;
  const formatCode = (code: string) => `${code.slice(0, 3)} ${code.slice(3)}`;
  try {
    await etab.goto(permissionEtab === 'POINTAGE_ONLY'
      ? `/etablissement/presences/mission/${ids.mission}` : `/etablissement/missions/${ids.mission}`);
    const carte = etab.getByRole('heading', { name: 'Code de pointage', exact: true }).locator('..').locator('..');
    const qrE = carte.locator('svg[width="150"][height="150"]');
    const premierCode = control.codePointage;
    await expect(carte.getByText(formatCode(premierCode), { exact: true })).toBeVisible();
    const codeRendu = await carte.getByText(formatCode(premierCode), { exact: true }).evaluate(element => {
      const range = document.createRange();
      range.selectNodeContents(element);
      const rect = element.getBoundingClientRect();
      const parent = element.parentElement!.getBoundingClientRect();
      const style = getComputedStyle(element.parentElement!);
      return { lignes: range.getClientRects().length,
        contenuVisible: rect.left >= parent.left + parseFloat(style.paddingLeft)
          && rect.right <= parent.right - parseFloat(style.paddingRight) };
    });
    expect(codeRendu).toEqual({ lignes: 1, contenuVisible: true });
    await expect(qrE).toBeVisible();
    const premierSvg = await qrE.evaluate(svg => new XMLSerializer().serializeToString(svg));
    await info.attach('qr-etablissement-initial.svg', { body: premierSvg, contentType: 'image/svg+xml' });
    await info.attach('qr-etablissement-initial-aria', { body: await carte.ariaSnapshot(), contentType: 'text/plain' });

    // Une lecture automatique supplémentaire ne suffit pas à changer le QR.
    const avantPolling = lecturesE();
    await expect.poll(lecturesE, { timeout: 12_000 }).toBeGreaterThan(avantPolling);
    await expect(carte.getByText(formatCode(premierCode), { exact: true })).toBeVisible();
    expect(await qrE.evaluate(svg => new XMLSerializer().serializeToString(svg))).toBe(premierSvg);
    expect(scans()).toHaveLength(0);

    await page.goto('/soignant/presences?tab=aujourdhui');
    let dialog = await ouvrirLecteur(page);
    expect((await cameraStats(page)).barcodeDetectorPresent).toBe(false);
    expect(scans()).toHaveLength(0);
    await presenterImage(page, premierSvg);
    await expect(dialog.getByText('Pointage enregistré — segment ouvert', { exact: true })).toBeVisible();
    await expect(dialog).toBeHidden();
    await expect.poll(async () => (await cameraStats(page)).pistesActives).toBe(0);
    expect(scans()).toHaveLength(1);
    expect(scans()[0].body).toMatchObject({ p_code: premierCode, p_metadata: { id_terminal: expect.any(String) } });
    expect(state.segments).toHaveLength(1); expect(state.segments[0].fin).toBeNull();
    const secondCode = control.codePointage;
    expect(secondCode).not.toBe(premierCode);

    // Le vrai écran E se rafraîchit sans rechargement ni injection de son DOM.
    await etab.bringToFront();
    await expect(carte.getByText(formatCode(secondCode), { exact: true })).toBeVisible();
    await expect(carte.getByText('Segment en cours', { exact: true })).toBeVisible();
    const secondSvg = await qrE.evaluate(svg => new XMLSerializer().serializeToString(svg));
    expect(secondSvg).not.toBe(premierSvg);
    await info.attach('qr-etablissement-renouvele.svg', { body: secondSvg, contentType: 'image/svg+xml' });
    await info.attach('qr-etablissement-renouvele-aria', { body: await carte.ariaSnapshot(), contentType: 'text/plain' });
    await carte.screenshot({ path: info.outputPath('qr-renouvele.png'), animations: 'disabled' });

    // Représenter les pixels de l'ancien QR doit produire son ancien code,
    // puis un refus serveur simulé, sans fermer le segment ni changer le QR E.
    await page.bringToFront(); dialog = await ouvrirLecteur(page);
    await presenterImage(page, premierSvg);
    await expect(dialog.getByText('Code de pointage invalide ou expiré. Demande le code actuel à l’établissement.', { exact: true })).toBeVisible();
    expect(scans()).toHaveLength(2); expect(scans()[1].body.p_code).toBe(premierCode);
    expect(state.segments[0].fin).toBeNull(); expect(control.codePointage).toBe(secondCode);
    await dialog.getByRole('button', { name: 'Annuler le scan QR' }).click();
    await expect(dialog).toBeHidden();
    await expect.poll(async () => (await cameraStats(page)).pistesActives).toBe(0);

    // Le nouveau SVG doit lui aussi être lisible : une unique fermeture.
    control.heurePointage = '2026-09-24T08:00:00.000Z';
    await page.clock.setFixedTime(new Date(control.heurePointage));
    await etab.clock.setFixedTime(new Date(control.heurePointage));
    dialog = await ouvrirLecteur(page); await presenterImage(page, secondSvg);
    await expect(dialog.getByText('Pointage enregistré — segment fermé', { exact: true })).toBeVisible();
    await expect(dialog).toBeHidden();
    await expect.poll(async () => (await cameraStats(page)).pistesActives).toBe(0);
    expect(scans()).toHaveLength(3); expect(scans()[2].body.p_code).toBe(secondCode);
    expect(state.segments).toHaveLength(1); expect(state.segments[0].fin).toBe(control.heurePointage);
    const troisiemeCode = control.codePointage;
    expect(troisiemeCode).not.toBe(secondCode);
    await etab.bringToFront();
    await expect(carte.getByText(formatCode(troisiemeCode), { exact: true })).toBeVisible();
    await expect(carte.getByText('Segment en cours', { exact: true })).toHaveCount(0);
    await etab.reload();
    await expect(carte.getByText(formatCode(troisiemeCode), { exact: true })).toBeVisible();
    expect(state.calls.some(call => call.role === 'ADMIN_ETABLISSEMENT' && call.name === 'fn_contrat_signe_pour_pointage')).toBe(true);
    if (permissionEtab === 'POINTAGE_ONLY') {
      expect(state.calls.filter(call => call.role === 'ADMIN_ETABLISSEMENT' && call.name === 'contrats_mission')).toEqual([]);
    }
    const camera = await cameraStats(page);
    expect(camera.demandes).toBe(6);
    expect(camera.frames).toBeGreaterThan(0);
    expect(camera.barcodeDetectorPresent).toBe(false);
    await page.reload();
    await expect(page.getByRole('button', { name: 'Pointer mon arrivée / ma reprise', exact: true })).toBeVisible();
    expect(scans()).toHaveLength(3);
    expect(state.unknown).toEqual([]); expect(state.errors).toEqual([]);
    await info.attach('preuve-decodage-reel-api-simulee', { body: JSON.stringify({
      niveau: 'Html5Qrcode/ZXing réel ; images QRCodeSVG établissement ; caméra canvas, permissions et backend simulés', permissionEtab,
      codes: [premierCode, secondCode, troisiemeCode],
      imagesSha256: [premierSvg, secondSvg].map(svg => createHash('sha256').update(svg).digest('hex')),
      scans: scans(), segments: state.segments, camera,
    }, null, 2), contentType: 'application/json' });
  } finally {
    await etabContext.close();
  }
});
}
