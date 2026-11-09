import { expect, type BrowserContext, type Page, type Route, type TestInfo } from '@playwright/test';
import { mkdir, writeFile } from 'node:fs/promises';
import path from 'node:path';

/**
 * Recette B9 « gardes NULL » (migration 20261109010957) — niveau SIMULATION.
 * Les réponses ci-dessous reproduisent mot pour mot les corps de refus des
 * fonctions corrigées (tests/security/fixtures/gardes-null-security-definer-live.sql) ;
 * elles ne prouvent ni la garde SQL ni la RLS, exercées par
 * tests/security/gardes-null-security-definer.test.sql (staging, sous ROLLBACK).
 * Ce banc prouve que chaque écran réellement monté rend ces réponses sans fuite,
 * sans erreur de page et sans casser le parcours des appelants légitimes.
 * Écrans sans surface montée (aucune recette UI possible) : QRPointageEtab et
 * CodesPointageMission ne sont importés par aucune route ; fn_valider_alerte_presence,
 * fn_deposer_chorus, fn_generer_facture, fn_diffuser_pool_urgence, fn_annuler_serie,
 * fn_assigner_mission_admin, fn_definir_retrocession_mission et
 * fn_regenerer_qr_mission n'ont aucun appelant web.
 */
export const REFUS = {
  accesRefuse: { error: 'Accès refusé' },
  nonAutorise: { error: 'Non autorisé' },
  dpae: { success: false, error: 'Non autorisé' },
  reclamation: { success: false, error_code: 'NON_AUTORISE', error: 'Vous n\'êtes pas concerné par cet événement' },
} as const;

const cors = { 'access-control-allow-origin': '*', 'access-control-allow-headers': '*', 'access-control-allow-methods': 'GET,POST,PATCH,DELETE,OPTIONS', 'access-control-expose-headers': 'content-range' };

export type AppelRpc = { nom: string; corps: unknown };

/**
 * Surcharge des RPC nommées, enregistrée APRÈS le harnais strict : Playwright
 * exécute les routes dans l'ordre inverse d'enregistrement, toute autre RPC
 * retombe sur le harnais (route.fallback), qui refuse l'inconnu en 501.
 * `active` (facultatif) laisse répondre le harnais tant qu'il renvoie false
 * (ex. avant la révocation d'un membre en cours de session).
 */
export async function surchargerRpc(cible: BrowserContext | Page, reponses: Map<string, (corps: any) => unknown>, appels: AppelRpc[], active: () => boolean = () => true) {
  await cible.route('**/rest/v1/rpc/*', async (route: Route) => {
    const req = route.request();
    const nom = new URL(req.url()).pathname.split('/').pop()!;
    const fabrique = reponses.get(nom);
    if (!fabrique || req.method() !== 'POST' || !active()) return route.fallback();
    const corps = req.postDataJSON();
    appels.push({ nom, corps });
    return route.fulfill({ json: fabrique(corps), headers: cors });
  });
}

/** Ressources tierces neutralisées à la frontière HTTP (aucune police ni SDK réel). */
export async function neutraliserTiers(context: BrowserContext) {
  await context.route('https://fonts.googleapis.com/**', route => route.fulfill({ contentType: 'text/css', body: '' }));
  await context.route('https://js.stripe.com/**', route => route.fulfill({ contentType: 'application/javascript', body: 'window.Stripe = function(){ return {}; };' }));
}

/** Lecture PostgREST d'une table remplacée (ex. RLS qui masque la mission réattribuée). */
export async function surchargerTable(cible: BrowserContext | Page, table: string, lignes: () => unknown[]) {
  await cible.route(url => url.pathname === `/rest/v1/${table}`, async (route: Route) => {
    const req = route.request();
    if (!['GET', 'HEAD'].includes(req.method())) return route.fallback();
    const rows = lignes();
    const objet = req.headers().accept?.includes('object');
    if (objet && rows.length === 0) {
      return route.fulfill({ status: 406, headers: cors, json: { code: 'PGRST116', message: 'Cannot coerce the result to a single JSON object', details: 'The result contains 0 rows' } });
    }
    return route.fulfill({ headers: { ...cors, 'content-range': rows.length ? `0-${rows.length - 1}/${rows.length}` : '*/0' }, json: objet ? rows[0] : rows });
  });
}

/** Preuve : dump ARIA (relisible, diffable) + capture headless en artefact, jamais la preuve. */
export async function preuveGardes(page: Page, info: TestInfo, nom: string) {
  const surface = await page.getByRole('dialog').count() ? page.getByRole('dialog').last()
    : await page.locator('main').count() ? page.locator('main').first() : page.locator('body');
  // Les notifications (NotificationContext « Notifications », sonner « Notifications alt+T »)
  // vivent hors de <main> : elles portent le refus ou la confirmation visible.
  let aria = await surface.ariaSnapshot();
  for (const region of await page.getByRole('region', { name: /^Notifications/ }).all()) {
    if (await region.locator('[role="alert"], [role="status"], li').count()) aria += `\n# notifications\n${await region.ariaSnapshot()}`;
  }
  const dossier = path.resolve('test-results/recette-complete/gardes-null', info.project.name);
  await mkdir(dossier, { recursive: true });
  await writeFile(path.join(dossier, `${nom}.txt`), aria);
  await info.attach(`${nom}-aria`, { body: aria, contentType: 'text/plain' });
  await page.screenshot({ path: path.join(dossier, `${nom}.png`), fullPage: true, animations: 'disabled' });
  expect(await page.evaluate(() => document.documentElement.scrollWidth <= document.documentElement.clientWidth), `${nom} : défilement horizontal`).toBe(true);
  return aria;
}
