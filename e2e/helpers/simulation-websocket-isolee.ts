import { test as base, expect, type BrowserContext, type Page } from '@playwright/test';

type JournalWebSocket = { interceptees: string[]; echappees: string[] };
const journaux = new WeakMap<BrowserContext, JournalWebSocket>();
const destination = (url: string) => {
  const socket = new URL(url);
  // Ni paramètres d'API ni token dans les preuves.
  return `${socket.protocol}//${socket.host}${socket.pathname}`;
};

// Réservé aux specs qui fabriquent une session Auth. Aucun parcours backend réel
// n'importe cette fixture. Le garde-fou du contexte empêche une connexion oubliée
// et échoue le test ; l'interception attendue reste celle de chaque page simulée.
export const test = base.extend<{ surveillanceWebSocket: void }>({
  surveillanceWebSocket: [async ({ context }, use, info) => {
    const journal: JournalWebSocket = { interceptees: [], echappees: [] };
    journaux.set(context, journal);
    // Les routes Auth/REST de page restent prioritaires. Une ressource extérieure
    // non simulée n'atteint aucun fournisseur depuis ces seuls tests fictifs.
    await context.route('**/*', route => {
      const url = new URL(route.request().url());
      return ['127.0.0.1', 'localhost'].includes(url.hostname) ? route.continue() : route.abort();
    });
    await context.routeWebSocket('**/*', socket => {
      journal.echappees.push(destination(socket.url()));
      socket.close();
    });
    try {
      await use();
    } finally {
      await info.attach('websockets-simules', {
        body: JSON.stringify(journal, null, 2), contentType: 'application/json',
      });
      journaux.delete(context);
      expect(journal.echappees, 'WebSocket sans interception de page : connexion fermée par sécurité').toEqual([]);
    }
  }, { auto: true }],
});

export async function isolerWebSocketsSimules(page: Page) {
  const journal = journaux.get(page.context());
  if (!journal) throw new Error('La session fictive doit utiliser la fixture de surveillance WebSocket.');
  await page.routeWebSocket('**/*', socket => {
    journal.interceptees.push(destination(socket.url()));
    socket.close();
  });
  return journal;
}
