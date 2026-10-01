import { expect, test } from '@playwright/test';
import { simulerEtablissement, entrer, allerA, stabiliserLectures } from './helpers/recette-complete-etablissement';
import { preuve } from './helpers/recette-complete-soignant';

// Préférences persistées uniquement dans la fixture HTTP locale. Les taps du
// push vers la candidature sont couverts par notification-candidature.spec.ts.
// Aucun relais Apple/Google/Web Push, compte réel ou livraison physique ici.
test('candidature : préférences push globale et événement, gestes puis reload', async ({ page }, info) => {
  const { etat } = await simulerEtablissement(page);
  const prefs = { global: { canal_email: true, canal_push: true, canal_sms: false, canal_in_app: true },
    par_evenement: [] as { type_evenement: string; canal: string; actif: boolean }[] };
  const writes: Record<string, unknown>[] = [];
  await page.route('**/rest/v1/rpc/fn_obtenir_mes_preferences_notifications', route => route.fulfill({ json: prefs }));
  await page.route('**/rest/v1/rpc/fn_modifier_preferences_notifications', route => {
    const body = route.request().postDataJSON();
    expect(route.request().method()).toBe('POST');
    expect(Object.keys(body).sort()).toEqual(['p_canal_email','p_canal_in_app','p_canal_push','p_canal_sms','p_par_evenement'].sort());
    writes.push(body);
    prefs.global = { canal_email: body.p_canal_email, canal_in_app: body.p_canal_in_app, canal_push: body.p_canal_push, canal_sms: body.p_canal_sms };
    prefs.par_evenement = body.p_par_evenement;
    return route.fulfill({ json: { success: true } });
  });
  await entrer(page, 'connexion');
  await allerA(page, '/etablissement/parametres/notifications');
  const global = page.getByRole('switch', { name: 'Notifications push (mobile / web)', exact: true });
  const event = page.getByRole('switch', { name: /^PUSH pour Nouvelle candidature reçue/ });
  const save = page.getByRole('button', { name: 'Enregistrer', exact: true });
  await expect(global).toHaveAttribute('aria-checked','true');
  await global.click(); await expect(event).toBeDisabled(); await save.click();
  await expect(page.getByText('Préférences enregistrées', { exact: true })).toBeVisible();
  await stabiliserLectures(page); await page.reload();
  await expect(global).toHaveAttribute('aria-checked','false'); await expect(event).toBeDisabled();
  await preuve(page, 'candidatures-push-global-desactive', info, true);
  await global.click(); await expect(event).toBeEnabled(); await event.click(); await save.click();
  await expect.poll(() => writes.length).toBe(2); await stabiliserLectures(page); await page.reload();
  await expect(global).toHaveAttribute('aria-checked','true');
  await expect(event).toHaveAttribute('aria-checked','false');
  await event.evaluate(element => element.scrollIntoView({ block: 'center' }));
  await expect(event).toBeInViewport();
  await expect.poll(() => event.evaluate(element => {
    const rect = element.getBoundingClientRect();
    return element.contains(document.elementFromPoint(rect.x + rect.width / 2, rect.y + rect.height / 2));
  }), { message: 'Le bouton push candidature est visible et atteint sans masquer les barres fixes' }).toBe(true);
  const viewport = info.outputPath('candidatures-push-evenement-viewport.png');
  await page.screenshot({ path: viewport, fullPage: false, scale: 'css' });
  await info.attach('candidatures-push-evenement-viewport', { path: viewport, contentType: 'image/png' });
  await preuve(page, 'candidatures-push-evenement-desactive', info, true);
  await event.click(); await save.click(); await expect.poll(() => writes.length).toBe(3);
  await stabiliserLectures(page); await page.reload();
  await expect(global).toHaveAttribute('aria-checked','true'); await expect(event).toHaveAttribute('aria-checked','true');
  expect(writes.map(x => x.p_canal_push)).toEqual([false,true,true]);
  expect((writes[1].p_par_evenement as typeof prefs.par_evenement).find(x => x.type_evenement === 'CANDIDATURE_RECUE' && x.canal === 'PUSH')?.actif).toBe(false);
  expect((writes[2].p_par_evenement as typeof prefs.par_evenement).find(x => x.type_evenement === 'CANDIDATURE_RECUE' && x.canal === 'PUSH')?.actif).toBe(true);
  expect(etat.erreurs).toEqual([]); expect(etat.inconnues).toEqual([]);
  await info.attach('preferences-simulees', { body: JSON.stringify(writes), contentType: 'application/json' });
});
