import { expect } from '@playwright/test';
import { test, isolerWebSocketsSimules } from './helpers/simulation-websocket-isolee';

test('session fictive : tentative WebSocket extérieure interceptée avant tout transport serveur', async ({ page }) => {
  const journal = await isolerWebSocketsSimules(page);
  await page.goto('about:blank');
  await page.evaluate(() => new Promise<void>(resolve => {
    const socket = new WebSocket('wss://supabase-simulation.invalid/realtime/v1/websocket?apikey=cle-fictive');
    socket.onclose = () => resolve();
  }));
  expect(journal.interceptees).toEqual(['wss://supabase-simulation.invalid/realtime/v1/websocket']);
  expect(journal.echappees).toEqual([]);
});
