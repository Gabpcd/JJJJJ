import { expect, test } from '@playwright/test';
import { simulerEtablissement, entrer as entrerEtablissement, preuve as preuveEtablissement, ids as idsEtab, mission, allerA }
  from './helpers/recette-complete-etablissement';
import { simulerSoignant, entrer as entrerSoignant, aller, preuve as preuveSoignant } from './helpers/recette-complete-soignant';

// B9, migration 20261128150000 : fn_creer_notification n'est plus appelable par un compte. Simulation fermée
// (réponses simulées, aucun envoi, aucune base) : chaque parcours web qui l'appelait passe par sa RPC bornée, et le
// classement affiche le prénom et l'initiale renvoyés par le serveur. La preuve d'autorisation reste la suite SQL.
test.setTimeout(240_000);
const sansAppelPrimitive = (appels: string[]) => expect(appels.filter(a => a.includes('fn_creer_notification'))).toEqual([]);

test('SOIGNANT — classement : prénom et initiale du nom, aucun nom complet', async ({ page }, info) => {
  const state = await simulerSoignant(page);
  state.overrides.set('fn_top_soignants', [
    { prenom: 'Alice', nom: 'S.', profession: 'IDE', note_moyenne: 4.8, score_fiabilite: 90, total_missions_terminees: 12 },
    { prenom: 'Bastien', nom: 'R.', profession: 'IDE', note_moyenne: 4.5, score_fiabilite: 84, total_missions_terminees: 7 },
  ]);
  await entrerSoignant(page, 'connexion');
  await aller(page, '/soignant/classement');
  await expect(page.getByRole('heading', { name: 'Classement soignants' })).toBeVisible();
  await expect(page.getByText('Alice S.', { exact: true })).toBeVisible();
  await expect(page.getByText('Bastien R.', { exact: true })).toBeVisible();
  await preuveSoignant(page, 'b9-classement-initiales', info);
  const appels = state.calls.filter(c => c.name === 'fn_top_soignants');
  expect(appels.at(-1)?.body).toEqual({ p_profession: null, p_limit: 10 });
  sansAppelPrimitive(state.calls.map(c => c.name));
  expect(state.unknown).toEqual([]); expect(state.errors).toEqual([]);
});

test('ÉTABLISSEMENT — alerte du pool d’urgence : une seule RPC serveur, refus affiché sans envoi', async ({ page }, info) => {
  const { etat } = await simulerEtablissement(page); etat.donnees = true;
  mission.est_urgente = true;
  const pool = [{ soignant_id: idsEtab.soignant, id: idsEtab.soignant, prenom: 'Camille', nom: 'Recette', score_fiabilite: 90,
    distance_km: 3.2, urgence_rayon_km: 15, telephone: null }];
  etat.overrides.set('fn_soignants_urgence', pool);
  const alertes: unknown[] = []; const emails: unknown[] = [];
  let refus = true;
  await page.route('**/rest/v1/rpc/fn_alerter_pool_urgence', async route => {
    const req = route.request();
    expect(['127.0.0.1', 'localhost']).toContain(new URL(req.url()).hostname);
    expect(req.method()).toBe('POST');
    alertes.push(req.postDataJSON());
    if (refus) return route.fulfill({ status: 403, json: { code: '42501', message: 'Mission introuvable ou hors de votre établissement' },
      headers: { 'access-control-allow-origin': '*' } });
    return route.fulfill({ json: { success: true, notifies: 1, deja_notifies: 0 }, headers: { 'access-control-allow-origin': '*' } });
  });
  await page.route('**/functions/v1/send-email', async route => {
    if (route.request().method() === 'OPTIONS') return route.fulfill({ status: 204, headers: { 'access-control-allow-origin': '*', 'access-control-allow-headers': '*' } });
    emails.push(route.request().postDataJSON());
    return route.fulfill({ json: { success: true }, headers: { 'access-control-allow-origin': '*' } });
  });
  await entrerEtablissement(page, 'connexion');
  await allerA(page, `/etablissement/missions/${idsEtab.mission}`);
  const bouton = page.getByRole('button', { name: 'Alerter le pool', exact: true });
  await expect(bouton).toBeVisible();
  await preuveEtablissement(page, 'b9-pool-avant', info);

  // Refus du serveur : message d'erreur, bouton réutilisable, aucun e-mail parti.
  await bouton.click();
  await expect(page.getByText('Erreur lors de l\'envoi des alertes. Veuillez réessayer.', { exact: true })).toBeVisible();
  await expect(bouton).toBeEnabled();
  expect(emails).toEqual([]);
  await preuveEtablissement(page, 'b9-pool-refus', info);

  // Accepté : une seule alerte serveur, puis l'e-mail du pool ; bouton « Pool alerté ».
  refus = false;
  await bouton.click();
  await expect(page.getByText('1 soignant alerté', { exact: true })).toBeVisible();
  await expect(page.getByRole('button', { name: 'Pool alerté', exact: true })).toBeDisabled();
  expect(alertes).toEqual([{ p_mission_id: idsEtab.mission }, { p_mission_id: idsEtab.mission }]);
  await expect.poll(() => emails.length).toBe(1);
  expect(emails[0]).toMatchObject({ type: 'MISSION_URGENTE', destinataire_id: idsEtab.soignant });
  await preuveEtablissement(page, 'b9-pool-alerte', info);
  sansAppelPrimitive(etat.appels);
  expect(etat.erreurs).toEqual([]);
});

test('ADMIN — relance du mandat : texte posé par le serveur, échec de la notification signalé', async ({ page }, info) => {
  const { etat } = await simulerEtablissement(page);
  etat.overrides.set('fn_get_my_role', { role: 'ADMIN_PLATEFORME' });
  etat.overrides.set('fn_admin_mes_acces', { acces_total: true, groupes: [] });
  etat.overrides.set('fn_admin_mandats_stats', { total_soignants: 1, mandat_signe: 0, mandat_non_signe: 1, total_factures_honoraires: 0,
    montant_factures_honoraires_total: 0, montant_factures_honoraires_impayees: 0 });
  etat.overrides.set('soignants', [{ id: idsEtab.soignant, prenom: 'Camille', nom: 'Recette', email: 'camille-recette@example.invalid',
    profession: 'IDE', mandat_facturation_signe: false, mandat_facturation_signe_le: null, mandat_facturation_version: null,
    cree_le: '2026-10-01T10:00:00Z' }]);
  const relances: unknown[] = []; let panne = true;
  await page.route('**/rest/v1/rpc/fn_admin_relancer_mandat_facturation', async route => {
    const req = route.request();
    expect(req.method()).toBe('POST');
    relances.push(req.postDataJSON());
    if (panne) return route.fulfill({ status: 503, json: { message: 'Service de recette indisponible' }, headers: { 'access-control-allow-origin': '*' } });
    return route.fulfill({ json: '79000000-0000-4000-8000-0000000000b9', headers: { 'access-control-allow-origin': '*' } });
  });
  await page.route('**/functions/v1/send-email', async route => {
    if (route.request().method() === 'OPTIONS') return route.fulfill({ status: 204, headers: { 'access-control-allow-origin': '*', 'access-control-allow-headers': '*' } });
    expect(route.request().postDataJSON()).toMatchObject({ type: 'ADMIN_BROADCAST', destinataire_id: idsEtab.soignant });
    return route.fulfill({ json: { success: true }, headers: { 'access-control-allow-origin': '*' } });
  });
  await page.addInitScript(({ id }) => sessionStorage.setItem('sb-127-auth-token', JSON.stringify({
    user: { id, email: 'admin-recette@example.invalid', email_confirmed_at: '2026-10-01T10:00:00Z', app_metadata: { role: 'ADMIN_PLATEFORME' }, user_metadata: {}, aud: 'authenticated', role: 'authenticated' },
    access_token: 'simulation-admin', refresh_token: 'simulation-admin-refresh', token_type: 'bearer',
    expires_in: 3600, expires_at: Math.floor(Date.now() / 1000) + 3600,
  })), { id: idsEtab.user });

  await page.goto('/admin/mandats-facturation');
  const relancer = page.getByRole('button', { name: 'Relancer', exact: true }).first();
  await expect(relancer).toBeVisible();
  await preuveEtablissement(page, 'b9-mandat-avant', info);
  await relancer.click();
  await expect(page.getByText('Email envoyé, mais la notification in-app a échoué. Vérifiez avant de relancer.', { exact: true })).toBeVisible();
  // Le toast d'erreur, une fois en place, ne recouvre pas le bouton à relancer (sur téléphone il recouvrait le bas de la
  // carte, et la page ne défilait pas assez pour le dégager) : centre et bas du bouton atteignables par un toucher.
  const toastEchec = page.locator('[data-sonner-toast][data-mounted="true"]', { hasText: 'la notification in-app a échoué' });
  await expect(toastEchec).toBeVisible();
  await toastEchec.evaluate(async el => {
    await new Promise(r => requestAnimationFrame(() => requestAnimationFrame(r)));
    await Promise.allSettled(el.getAnimations({ subtree: true }).map(a => a.finished));
  });
  const pointsCouverts = await relancer.evaluate(b => {
    const r = b.getBoundingClientRect();
    return [[r.left + r.width / 2, r.top + r.height / 2], [r.left + 16, r.bottom - 4], [r.left + r.width / 2, r.bottom - 4], [r.right - 16, r.bottom - 4]]
      .filter(([x, y]) => { const h = document.elementFromPoint(x, y); return !h || !b.contains(h); }).length;
  });
  expect(pointsCouverts).toBe(0);
  await preuveEtablissement(page, 'b9-mandat-notification-echec', info);
  panne = false;
  await relancer.click();
  await expect(page.getByText('Camille Recette relancé(e) — notification + email envoyés.', { exact: true })).toBeVisible();
  expect(relances).toEqual([{ p_soignant_id: idsEtab.soignant }, { p_soignant_id: idsEtab.soignant }]);
  await preuveEtablissement(page, 'b9-mandat-relance', info);
  sansAppelPrimitive(etat.appels);
  expect(etat.erreurs).toEqual([]);
});
