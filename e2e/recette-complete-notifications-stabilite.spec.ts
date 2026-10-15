import { test, expect, type WebSocketRoute, type JSHandle } from '@playwright/test';
import { communicationsSimulees } from './helpers/recette-complete-communications';
import { ids, now, type RoleRecette } from './helpers/recette-complete-mission';

// Simulation fermée : SDK réel, REST et Phoenix fictifs, jamais connectToServer().
// Le geste utilise le pointeur Playwright aux coordonnées publiques de la fixture,
// y compris aux formats mobiles ; il ne prétend pas être un contrôle tactile physique.
for (const role of ['SOIGNANT', 'ADMIN_ETABLISSEMENT'] as RoleRecette[]) {
  test(`${role} : statut hors du flux des lignes, réessai puis coupure pendant un clic`, async ({ context, page }, info) => {
    const state = await communicationsSimulees(context, role);
    // Même convention que verifierFocusClavier : Option+Tab inclut les boutons
    // sur macOS/WebKit ; les assertions de focus restent strictement identiques.
    const optionTab = process.platform === 'darwin' && page.context().browser()?.browserType().name() === 'webkit';
    const forwardTabChord = optionTab ? 'Alt+Tab' : 'Tab';
    const browserName = page.context().browser()?.browserType().name() ?? null;
    const uid = role === 'SOIGNANT' ? ids.soignant : ids.etablissement;
    const prefix = role === 'SOIGNANT' ? 'soignant' : 'etablissement';
    const destination = `/${prefix}/missions/${ids.mission}`;
    const notification = {
      id: '79000000-0000-4000-8000-000000000096', destinataire_id: uid,
      titre: 'Notification de stabilité simulée', corps: 'Ouvrir la mission fictive.',
      type: 'SYSTEME', lue: false, lien: destination, cree_le: now,
    };
    const interruption = 'Connexion aux notifications interrompue. Réessayez pour actualiser la liste.';
    const pageErrors: string[] = [], consoleErrors: string[] = [];
    let marquages = 0, navigations = 0, souscriptions = 0;
    let paused = false, heldReads = 0, releaseReads: (() => void) | undefined;
    let readGate: Promise<void> | undefined;
    let pointerDown = false;
    let focusAfterDownHandle: JSHandle | undefined;
    let focusAfterDownKind: string | null = null;
    let focusPreservedDuringDisconnection: boolean | null = null;
    type Bounds = { x: number; y: number; width: number; height: number };
    let boundsBefore: Bounds | null = null;
    let boundsAfter: Bounds | null = null;
    page.on('pageerror', error => pageErrors.push(error.message));
    page.on('console', message => { if (message.type() === 'error') consoleErrors.push(message.text()); });
    page.on('framenavigated', frame => {
      if (frame === page.mainFrame() && new URL(frame.url()).pathname === destination) navigations += 1;
    });
    await context.addInitScript(() => localStorage.setItem('notif_sound', 'off'));
    await context.route('https://fonts.googleapis.com/**', route => route.fulfill({ contentType: 'text/css', body: '' }));

    type Join = {
      socket: WebSocketRoute; joinRef: string; ref: string; topic: string;
      filters: Record<string, unknown>[]; array: boolean; ready: boolean;
    };
    const joins: Join[] = [], sockets = new Set<WebSocketRoute>();
    const send = (join: Join, event: string, payload: unknown) => join.socket.send(JSON.stringify(join.array
      ? [join.joinRef, join.ref, join.topic, event, payload]
      : { join_ref: join.joinRef, ref: join.ref, topic: join.topic, event, payload }));
    const accept = (join: Join) => {
      join.ready = true;
      send(join, 'phx_reply', { status: 'ok', response: {
        postgres_changes: join.filters.map((filter, index) => ({ ...filter, id: index + 1 })),
      } });
      if (join.topic.includes('notifications:')) souscriptions += 1;
    };
    await context.routeWebSocket('**/realtime/v1/**', socket => {
      sockets.add(socket);
      socket.onClose(() => {
        sockets.delete(socket);
        joins.filter(join => join.socket === socket).forEach(join => join.ready = false);
      });
      socket.onMessage(raw => {
        const message = JSON.parse(String(raw));
        const [joinRef, ref, topic, event, payload] = Array.isArray(message)
          ? message : [message.join_ref, message.ref, message.topic, message.event, message.payload];
        const join: Join = { socket, joinRef, ref, topic,
          filters: payload?.config?.postgres_changes ?? [], array: Array.isArray(message), ready: false };
        if (event === 'phx_join') { joins.push(join); if (!paused) accept(join); }
        else if (event === 'phx_leave' || event === 'heartbeat') {
          send(join, 'phx_reply', { status: 'ok', response: {} });
        }
      });
    });
    const disconnect = () => {
      paused = true;
      for (const socket of sockets) socket.close({ code: 1012, reason: 'Coupure simulée pendant interaction' });
      sockets.clear();
      joins.forEach(join => join.ready = false);
    };
    const resume = () => {
      paused = false;
      joins.filter(join => sockets.has(join.socket) && !join.ready).forEach(accept);
    };
    await context.route('**/rest/v1/notifications?**', async route => {
      const request = route.request(), url = new URL(request.url());
      expect(['127.0.0.1', 'localhost']).toContain(url.hostname);
      expect(url.searchParams.get('destinataire_id')).toBe(`eq.${uid}`);
      if (request.method() === 'PATCH') {
        expect(url.searchParams.get('id')).toBe(`in.(${notification.id})`);
        expect(request.postDataJSON()).toMatchObject({ lue: true });
        marquages += 1;
        notification.lue = true;
        return route.fulfill({ status: 204 });
      }
      expect(['GET', 'HEAD']).toContain(request.method());
      if (readGate) { heldReads += 1; await readGate; }
      const rows = url.searchParams.get('lue') === 'eq.false' && notification.lue ? [] : [notification];
      return route.fulfill({ status: 200, json: request.method() === 'GET' ? rows : undefined,
        body: request.method() === 'HEAD' ? '' : undefined,
        headers: { 'access-control-allow-origin': '*', 'access-control-expose-headers': 'content-range',
          'content-range': rows.length ? '0-0/1' : '*/0' } });
    });
    const bell = (count: number) => page.getByRole('button', {
      name: new RegExp(`^Notifications${count ? `, ${count} non lue` : ''}(?:, actualisation nécessaire)?$`),
    }).filter({ visible: true });
    const dialog = page.getByRole('dialog', { name: 'Notifications', exact: true });
    const row = dialog.getByRole('button', { name: /^Notification de stabilité simulée Non lue/ });
    const close = dialog.getByRole('button', { name: 'Fermer les notifications', exact: true });
    try {
      await page.goto(`/${prefix}/messagerie`);
      await expect.poll(() => souscriptions).toBeGreaterThan(0);
      await expect(bell(1)).toBeVisible();
      await bell(1).focus();
      await expect(bell(1)).toBeFocused();
      await page.keyboard.press('Enter');
      await expect(row).toBeVisible();
      await expect(dialog.getByRole('status')).toHaveCount(0);
      await expect(dialog.getByRole('alert')).toHaveCount(0);
      await expect(close).toBeFocused();

      // Un réessai utilise les vraies lectures SDK, retenues par un signal explicite.
      // Aucun waitForTimeout ni retry de scénario ou de mutation n'est ajouté.
      const avantReprise = souscriptions;
      disconnect();
      await expect(dialog.getByRole('alert').getByText(interruption, { exact: true })).toBeVisible();
      await expect(close).toBeFocused();
      readGate = new Promise<void>(resolve => { releaseReads = resolve; });
      const retry = dialog.getByRole('button', { name: 'Réessayer', exact: true });
      await page.keyboard.press(forwardTabChord);
      await expect(row).toBeFocused();
      // Le panneau termine son ouverture normale avant la mesure de référence.
      // Le mode trial attend l'actionnabilité sans déclencher la notification.
      await row.click({ trial: true });
      await expect(row).toBeFocused();
      expect(marquages).toBe(0); expect(navigations).toBe(0);
      await page.keyboard.press(forwardTabChord);
      await expect(retry).toBeFocused();
      const beforeLoading = await row.boundingBox();
      expect(beforeLoading).not.toBeNull();
      await retry.click();
      await expect.poll(() => heldReads).toBeGreaterThanOrEqual(2);
      await expect(dialog.getByRole('status')).toHaveText('Actualisation...');
      await expect(retry).toBeDisabled();
      await expect(row).toBeVisible();
      const duringLoading = await row.boundingBox();
      expect(duringLoading).not.toBeNull();
      for (const dimension of ['x', 'y', 'width', 'height'] as const) {
        expect(Math.abs(duringLoading![dimension] - beforeLoading![dimension]), `ligne stable pendant lecture : ${dimension}`).toBeLessThanOrEqual(1);
      }
      releaseReads!(); readGate = undefined;
      // HTTP peut réussir alors que le flux en direct reste interrompu.
      // Le dernier compteur exact demeure visible sans être transformé en « ! ».
      await expect(dialog.getByRole('alert').getByText(interruption, { exact: true })).toBeVisible();
      await expect(bell(1).getByText('1', { exact: true })).toBeVisible();
      await expect(bell(1).getByText('!', { exact: true })).toHaveCount(0);
      await expect(dialog.getByRole('status')).toHaveCount(0);
      resume();
      await expect.poll(() => souscriptions).toBeGreaterThan(avantReprise);
      await expect(dialog.getByRole('status')).toHaveCount(0);
      await expect(dialog.getByRole('alert')).toHaveCount(0);
      await expect(row).toHaveCount(1);
      await expect(page.locator('[data-sonner-toast]')).toHaveCount(0);
      // La fermeture au clavier restitue la cloche ; le rechargement conserve la ligne.
      await page.keyboard.press('Escape');
      await expect(dialog).toHaveCount(0);
      await expect(bell(1)).toBeFocused();
      const avantReload = souscriptions;
      await page.reload();
      await expect.poll(() => souscriptions).toBeGreaterThan(avantReload);
      await expect(bell(1)).toBeVisible();
      await bell(1).focus();
      await expect(bell(1)).toBeFocused();
      await page.keyboard.press('Enter');
      await expect(close).toBeFocused();
      await expect(dialog.getByRole('status')).toHaveCount(0);
      await expect(dialog.getByRole('alert')).toHaveCount(0);
      expect(marquages).toBe(0); expect(navigations).toBe(0);

      // Attendre l'actionnabilité normale puis conserver le point CENTRAL initial.
      // L'erreur arrive réellement via le SDK entre down/up, pas par injection React/DOM.
      await page.keyboard.press(forwardTabChord);
      await expect(row).toBeFocused();
      await row.click({ trial: true });
      boundsBefore = await row.boundingBox();
      expect(boundsBefore).not.toBeNull();
      const point = { x: boundsBefore!.x + boundsBefore!.width / 2,
        y: boundsBefore!.y + boundsBefore!.height / 2 };
      expect(await row.evaluate((element, p) => element.contains(document.elementFromPoint(p.x, p.y)), point)).toBe(true);
      await page.mouse.move(point.x, point.y);
      await expect(row).toBeFocused();
      const rowElement = await row.elementHandle();
      expect(rowElement).not.toBeNull();
      await page.mouse.down(); pointerDown = true;
      // Le comportement natif du pointerdown précède la coupure simulée.
      // Conserver cette identité exacte permet de distinguer leurs effets.
      focusAfterDownHandle = await page.evaluateHandle(() => document.activeElement);
      focusAfterDownKind = await focusAfterDownHandle.evaluate((active, notification) =>
        active === notification ? 'notification' : active === document.body ? 'body'
          : active === document.documentElement ? 'document-root'
            : active === document.querySelector('[role="dialog"][aria-modal="true"]') ? 'dialog' : 'other', rowElement);
      expect(['notification', 'dialog', 'body', 'document-root']).toContain(focusAfterDownKind);
      disconnect();
      await expect(dialog.getByRole('alert').getByText(interruption, { exact: true })).toBeVisible();
      await expect(bell(1).getByText('1', { exact: true })).toBeVisible();
      await expect(bell(1).getByText('!', { exact: true })).toHaveCount(0);
      focusPreservedDuringDisconnection = await focusAfterDownHandle.evaluate(active => document.activeElement === active);
      expect(focusPreservedDuringDisconnection).toBe(true);
      boundsAfter = await row.boundingBox();
      expect(boundsAfter).not.toBeNull();
      for (const dimension of ['x', 'y', 'width', 'height'] as const) {
        expect(Math.abs(boundsAfter![dimension] - boundsBefore![dimension]), `ligne stable : ${dimension}`).toBeLessThanOrEqual(1);
      }
      expect(await row.evaluate((element, p) => element.contains(document.elementFromPoint(p.x, p.y)), point)).toBe(true);
      await page.mouse.up(); pointerDown = false;
      await expect(page).toHaveURL(new RegExp(`${destination}$`));
      // La destination fait partie de la même fixture fermée que la notification.
      // Vérifier le contenu arrivé, puis toutes ses lectures avant le bilan réseau.
      await expect(page.getByRole('heading', { name: state.mission.intitule, exact: true })).toBeVisible();
      await page.waitForLoadState('networkidle');
      await expect(dialog).toHaveCount(0);
      await expect.poll(() => marquages).toBe(1);
      await expect(bell(0)).toBeVisible();
      expect(navigations).toBe(1); expect(notification.lue).toBe(true);
      expect(pageErrors).toEqual([]); expect(consoleErrors).toEqual([]);
      expect(state.errors).toEqual([]); expect(state.unknown).toEqual([]); expect(state.external).toEqual([]);
      expect(state.sms).toEqual([]); expect(state.emails).toEqual([]); expect(state.signatures).toEqual([]);
    } finally {
      releaseReads?.();
      try {
        if (pointerDown) await page.mouse.up();
      } finally {
        await focusAfterDownHandle?.dispose().catch(() => undefined);
        await info.attach('stabilite-notifications-simulation', { body: JSON.stringify({
          role, project: info.project.name, simulatedOnly: true, physicalTouchVerified: false,
          keyboardPlatform: process.platform, browserName, forwardTabChord,
          marquages, navigations, souscriptions, heldReads, boundsBefore, boundsAfter,
          focusAfterDownKind, focusPreservedDuringDisconnection,
          pageErrors, consoleErrors, unknown: state.unknown, external: state.external,
        }, null, 2), contentType: 'application/json' });
      }
    }
  });
}
