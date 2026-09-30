import { test, expect, type WebSocketRoute } from '@playwright/test';
import { communicationsSimulees } from './helpers/recette-complete-communications';
import { ids, now, preuveMission, type RoleRecette } from './helpers/recette-complete-mission';

// Bridge Phoenix simulé : le vrai SDK ouvre, ferme et réabonne ses canaux.
// Aucun connectToServer(), aucun serveur Supabase ni fournisseur contacté.
for (const role of ['SOIGNANT', 'ADMIN_ETABLISSEMENT'] as RoleRecette[]) {
  test(`${role} : coupure, rattrapage, erreur visible, nouvel essai et rechargement`, async ({ context, page }, info) => {
    const state = await communicationsSimulees(context, role);
    const uid = role === 'SOIGNANT' ? ids.soignant : ids.etablissement;
    const prefix = role === 'SOIGNANT' ? 'soignant' : 'etablissement';
    const consoleErrors: string[] = [], pageErrors: string[] = [], protocol: string[] = [];
    page.on('console', message => { if (message.type() === 'error') consoleErrors.push(message.text()); });
    page.on('pageerror', error => pageErrors.push(error.message));
    await context.addInitScript(() => localStorage.setItem('notif_sound', 'off'));
    await context.route('https://fonts.googleapis.com/**', route => route.fulfill({ contentType: 'text/css', body: '' }));
    let paused = false, failReads = false, failedReads = 0;
    type Join = { socket: WebSocketRoute; joinRef: string; ref: string; topic: string; filters: any[]; array: boolean; ready: boolean };
    const joins: Join[] = [], sockets = new Set<WebSocketRoute>();
    const send = (j: Join, event: string, payload: any, ref: string | null = j.ref) => {
      j.socket.send(JSON.stringify(j.array ? [j.joinRef, ref, j.topic, event, payload] : { join_ref: j.joinRef, ref, topic: j.topic, event, payload }));
    };
    const accept = (j: Join) => {
      j.ready = true;
      send(j, 'phx_reply', { status: 'ok', response: { postgres_changes: j.filters.map((filter, id) => ({ ...filter, id: id + 1 })) } });
      if (j.topic.includes('notifications:')) protocol.push('notifications:subscribed');
    };
    await context.routeWebSocket('**/realtime/v1/**', socket => {
      sockets.add(socket);
      socket.onClose(() => { sockets.delete(socket); joins.filter(j => j.socket === socket).forEach(j => j.ready = false); });
      socket.onMessage(raw => {
        const message = JSON.parse(String(raw));
        const [joinRef, ref, topic, event, payload] = Array.isArray(message)
          ? message : [message.join_ref, message.ref, message.topic, message.event, message.payload];
        const j = { socket, joinRef, ref, topic, filters: payload?.config?.postgres_changes ?? [], array: Array.isArray(message), ready: false };
        if (event === 'phx_join') { joins.push(j); if (!paused) accept(j); }
        else if (event === 'phx_leave' || event === 'heartbeat') send(j, 'phx_reply', { status: 'ok', response: {} });
      });
    });
    await context.route('**/rest/v1/notifications?**', async route => {
      const request = route.request(), url = new URL(request.url());
      if (request.method() === 'PATCH') {
        const idsFilter = url.searchParams.get('id');
        const idsCibles = idsFilter?.startsWith('in.(') ? idsFilter.slice(4, -1).split(',').map(id => id.replaceAll('"', '')) : null;
        state.notifications.filter(n => url.searchParams.get('destinataire_id') === `eq.${n.destinataire_id}`
          && (url.searchParams.get('lue') !== 'eq.false' || !n.lue)
          && (!idsCibles || idsCibles.includes(n.id))).forEach(n => n.lue = request.postDataJSON().lue);
        return route.fulfill({ status: 200, json: null });
      }
      if (!['GET', 'HEAD'].includes(request.method())) return route.fallback();
      if (failReads) { failedReads += 1; return route.fulfill({ status: 503, json: { message: 'Lecture indisponible, simulation locale' } }); }
      const rows = state.notifications.filter(n => url.searchParams.get('destinataire_id') === `eq.${n.destinataire_id}` && (url.searchParams.get('lue') !== 'eq.false' || !n.lue));
      return route.fulfill({ status: 200, json: rows.slice(0, 50), headers: { 'access-control-allow-origin': '*', 'access-control-expose-headers': 'content-range', 'content-range': `0-${Math.max(0, rows.length - 1)}/${rows.length}` } });
    });
    const makeRow = (id: string) => ({ id, destinataire_id: uid, titre: `Notification ${id}`, corps: 'Créée dans la fixture locale uniquement.', type: 'SYSTEME', lue: false, lien: null, cree_le: now });
    const disconnect = () => {
      paused = true; protocol.push('transport:closed');
      for (const socket of sockets) socket.close({ code: 1012, reason: 'Coupure de recette simulée' });
      sockets.clear(); joins.forEach(j => j.ready = false);
    };
    const resume = () => { paused = false; joins.filter(j => sockets.has(j.socket) && !j.ready).forEach(accept); };
    const emit = (row: ReturnType<typeof makeRow>) => {
      for (const j of joins.filter(j => j.ready && sockets.has(j.socket) && j.topic.includes('notifications:'))) {
        send(j, 'postgres_changes', { ids: [1], data: { type: 'INSERT', schema: 'public', table: 'notifications', commit_timestamp: now, record: row, old_record: {}, columns: [] } }, null);
      }
    };
    const bell = (count: number, failed = false) => page.getByRole('button', { name: `${count ? `Notifications, ${count} non lue${count > 1 ? 's' : ''}` : 'Notifications'}${failed ? ', actualisation nécessaire' : ''}`, exact: true }).filter({ visible: true });
    try {
      await page.goto(`/${prefix}/messagerie`);
      await expect(bell(1)).toBeVisible();
      await expect.poll(() => protocol.includes('notifications:subscribed')).toBe(true);
      await bell(1).click();
      const dialog = page.getByRole('dialog', { name: 'Notifications', exact: true });
      await expect(dialog.getByText('Notification fictive de recette', { exact: true })).toBeVisible();
      await preuveMission(page, info, `${prefix}-notifications-avant`);
      disconnect();
      await expect(dialog.getByRole('alert')).toContainText('Connexion aux notifications interrompue');
      state.notifications.push(makeRow('pendant-coupure'));
      resume();
      await expect(dialog.getByText('Notification pendant-coupure', { exact: true })).toBeVisible();
      await expect(bell(2)).toBeVisible();
      await expect(page.locator('[data-sonner-toast]')).toHaveCount(0);
      emit(makeRow('pendant-coupure'));
      const fresh = makeRow('après-reprise'); state.notifications.push(fresh); emit(fresh); emit(fresh);
      await expect(bell(3)).toBeVisible();
      await expect(dialog.getByText(fresh.titre, { exact: true })).toHaveCount(1);
      await expect(page.locator('[data-sonner-toast]')).toHaveCount(1);
      await preuveMission(page, info, `${prefix}-notifications-rattrapees`);
      disconnect(); state.notifications.push(makeRow('après-erreur')); failReads = true; resume();
      await expect(dialog.getByRole('alert')).toContainText('Impossible d’actualiser');
      await expect(dialog.getByText('Notification pendant-coupure', { exact: true })).toBeVisible();
      await expect(bell(3, true)).toBeVisible();
      await preuveMission(page, info, `${prefix}-notifications-erreur-reprise`);
      failReads = false; await dialog.getByRole('button', { name: 'Réessayer', exact: true }).click();
      await expect(dialog.getByText('Notification après-erreur', { exact: true })).toBeVisible();
      await expect(bell(4)).toBeVisible(); await expect(dialog.getByRole('alert')).toHaveCount(0);
      await dialog.getByRole('button', { name: 'Fermer les notifications' }).click();
      await page.reload(); await expect(bell(4)).toBeVisible(); await bell(4).click();
      await expect(dialog.getByText('Notification pendant-coupure', { exact: true })).toHaveCount(1);
      await expect(dialog.getByText('Notification après-erreur', { exact: true })).toHaveCount(1);
      await expect(page.locator('[data-sonner-toast]')).toHaveCount(0);
      await preuveMission(page, info, `${prefix}-notifications-rechargement`);
      // Lecture individuelle puis changement du badge affiché, sans navigation ni reload.
      await dialog.getByRole('button', { name: /^Notification fictive de recette Non lue/ }).click();
      await expect(bell(3)).toBeVisible();
      await dialog.getByRole('button', { name: 'Fermer les notifications' }).click();
      const viewport = page.viewportSize()!;
      await page.setViewportSize(viewport.width < 768 ? { width: 1180, height: 820 } : { width: 390, height: 844 });
      await expect(bell(3)).toBeVisible();
      await preuveMission(page, info, `${prefix}-notifications-lecture-breakpoint`);

      // Le PATCH de la fixture respecte tous les filtres : 50 IDs seulement laisseraient 10 non lues.
      state.notifications = Array.from({ length: 60 }, (_, i) => makeRow(`série-${i}`));
      const autreUid = role === 'SOIGNANT' ? ids.etablissement : ids.soignant;
      state.notifications.push({ ...makeRow('autre-compte'), destinataire_id: autreUid });
      await bell(3).click(); await expect(bell(60)).toBeVisible();
      await expect(dialog.getByText('Notification série-0', { exact: true })).toBeVisible();
      await expect(dialog.getByText('Notification série-59', { exact: true })).toHaveCount(0);
      await dialog.getByRole('button', { name: 'Tout marquer comme lu', exact: true }).click();
      await expect(bell(0)).toBeVisible();
      expect(state.notifications.filter(n => n.destinataire_id === uid && !n.lue)).toHaveLength(0);
      expect(state.notifications.find(n => n.destinataire_id === autreUid)?.lue).toBe(false);
      await dialog.getByRole('button', { name: 'Fermer les notifications' }).click();
      await page.setViewportSize(viewport);
      await expect(bell(0)).toBeVisible();
      await preuveMission(page, info, `${prefix}-notifications-toutes-lues-breakpoint`);
      expect(pageErrors).toEqual([]); expect(state.errors).toEqual([]); expect(state.unknown).toEqual([]); expect(state.external).toEqual([]);
      // Les erreurs 503 provoquées sont conservées et vérifiées, jamais filtrées ou masquées.
      expect(failedReads).toBeGreaterThan(0);
      expect(consoleErrors).toHaveLength(failedReads);
      for (const error of consoleErrors) expect(error).toMatch(/Failed to load resource.*503/);
    } finally {
      await info.attach('reconnexion-simulation', { body: JSON.stringify({ role, protocol, failedReads, consoleErrors, pageErrors, unknown: state.unknown, external: state.external }, null, 2), contentType: 'application/json' });
    }
  });
}
