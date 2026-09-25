import { expect, test, type Page } from '@playwright/test';
import { simulerEtablissement, entrer as entrerEtab, allerA, preuve, email, stabiliserLectures } from './helpers/recette-complete-etablissement';
import { simulerSoignant, entrer as entrerSoignant, aller, sansDebordement } from './helpers/recette-complete-soignant';

const preferences = { global: { canal_email: false, canal_sms: false, canal_push: false, canal_in_app: true }, par_evenement: [{ type_evenement: 'LITIGE_OUVERT', canal: 'EMAIL', actif: false }] };

for (const role of ['soignant', 'etablissement'] as const) {
  test(`${role} — préférences : 503, réessai, choix conservés et sauvegarde`, async ({ page }, info) => {
    const soignant = role === 'soignant' ? await simulerSoignant(page) : null;
    const etab = role === 'etablissement' ? (await simulerEtablissement(page)).etat : null;
    const pannes = soignant?.failures ?? etab!.pannes;
    const overrides = soignant?.overrides ?? etab!.overrides;
    const preferencesRole = structuredClone(preferences);
    if (etab) preferencesRole.par_evenement.push(
      { type_evenement: 'NOUVELLE_MISSION_MATCHANT_FILTRE', canal: 'EMAIL', actif: true },
      { type_evenement: 'NOUVEAU_SOIGNANT_MATCHANT_FILTRE', canal: 'EMAIL', actif: false },
    );
    overrides.set('fn_obtenir_mes_preferences_notifications', preferencesRole);
    pannes.add('fn_obtenir_mes_preferences_notifications');
    if (soignant) await entrerSoignant(page, 'connexion'); else await entrerEtab(page, 'connexion');
    if (soignant) await aller(page, `/${role}/parametres/notifications`); else await allerA(page, `/${role}/parametres/notifications`);
    await expect(page.getByRole('alert').filter({ hasText: 'Vos choix enregistrés sont conservés' })).toBeVisible();
    await expect(page.getByRole('button', { name: /Enregistrer/ })).toHaveCount(0);
    const ecritures = () => soignant ? soignant.calls.filter(c => c.name === 'fn_modifier_preferences_notifications').map(c => c.body) : etab!.operations.filter(c => c.nom === 'fn_modifier_preferences_notifications').map(c => c.payload);
    expect(ecritures()).toEqual([]);
    await preuve(page, `${role}-preferences-erreur`, info);
    pannes.delete('fn_obtenir_mes_preferences_notifications');
    await page.getByRole('button', { name: 'Réessayer' }).click();
    await expect(page.getByRole('switch', { name: 'Email', exact: true })).not.toBeChecked();
    await expect(page.getByRole('switch', { name: 'Notifications push (mobile / web)', exact: true })).not.toBeChecked();
    await page.getByRole('button', { name: /Enregistrer/ }).click();
    await expect(page.getByText('Préférences enregistrées', { exact: true })).toBeVisible();
    expect(ecritures()).toEqual([expect.objectContaining({ p_canal_email: false, p_canal_push: false, p_par_evenement: preferencesRole.par_evenement })]);
    if (etab) {
      await page.getByRole('switch', { name: 'Email', exact: true }).click();
      const alerte = page.getByRole('switch', { name: /EMAIL pour Nouveaux soignants disponibles/ });
      await expect(alerte).not.toBeChecked();
      await alerte.click();
      await expect(alerte).toBeChecked();
      await page.getByRole('button', { name: /Enregistrer/ }).click();
      await expect.poll(() => ecritures().length).toBe(2);
      expect(ecritures()[1]).toMatchObject({ p_canal_email: true, p_par_evenement: expect.arrayContaining([
        { type_evenement: 'NOUVELLE_MISSION_MATCHANT_FILTRE', canal: 'EMAIL', actif: true },
        { type_evenement: 'NOUVEAU_SOIGNANT_MATCHANT_FILTRE', canal: 'EMAIL', actif: true },
      ]) });
      await expect(page.getByRole('button', { name: /Enregistrer/ })).toBeEnabled();
      await alerte.click();
      await page.getByRole('button', { name: /Enregistrer/ }).click();
      await expect.poll(() => ecritures().length).toBe(3);
      expect(ecritures()[2]).toMatchObject({ p_par_evenement: expect.arrayContaining([
        { type_evenement: 'NOUVELLE_MISSION_MATCHANT_FILTRE', canal: 'EMAIL', actif: false },
        { type_evenement: 'NOUVEAU_SOIGNANT_MATCHANT_FILTRE', canal: 'EMAIL', actif: false },
      ]) });
    }
    await sansDebordement(page);
    await preuve(page, `${role}-preferences-reprise`, info);
    expect(soignant?.unknown ?? etab!.inconnues).toEqual([]);
    expect(soignant?.errors ?? etab!.erreurs).toEqual([]);
  });
}

const etabs = [
  { id: '89000000-0000-4000-8000-000000000001', nom: 'Clinique A — simulation', adresse_ville: 'Paris', adresse_departement: '75', type: 'CLINIQUE' },
  { id: '89000000-0000-4000-8000-000000000002', nom: 'Clinique B — simulation', adresse_ville: 'Lyon', adresse_departement: '69', type: 'CLINIQUE' },
];
async function fixtureGroupe(page: Page, invite = false) {
  const { etat } = await simulerEtablissement(page);
  etat.overrides.set('fn_get_my_role', { role: invite ? 'ADMIN_ETABLISSEMENT' : 'ADMIN_GROUPE', etablissement_id: invite ? etabs[0].id : null });
  const etatGroupe = { panne: true, idsLus: [] as string[] };
  await page.route('**/rest/v1/**', async route => {
    const req = route.request(), url = new URL(req.url()), nom = url.pathname.split('/').pop();
    if (!['admins_groupe_sante', 'etablissements', 'missions'].includes(nom!)) return route.fallback();
    if (!['GET', 'HEAD'].includes(req.method())) {
      etat.inconnues.push(`${req.method()} ${url.pathname}`);
      return route.fulfill({ status: 501, json: { message: 'Mutation non préparée' } });
    }
    if (nom === 'admins_groupe_sante') return route.fulfill({ json: { groupe_id: 'groupe-fictif', groupes_sante: { nom: 'Groupe de recette' } } });
    if (nom === 'etablissements') {
      const id = url.searchParams.get('id');
      if (id) etatGroupe.idsLus.push(id);
      if (invite && url.searchParams.get('select')?.includes('groupes_sante')) {
        if (etatGroupe.panne) return route.fulfill({ status: 503, json: { message: 'Service de recette indisponible' } });
        return route.fulfill({ json: { groupe_sante_id: 'groupe-fictif', groupes_sante: { nom: 'Groupe de recette' } } });
      }
      const liste = id ? etabs.filter(e => `eq.${e.id}` === id) : etabs;
      return route.fulfill({ json: req.headers().accept?.includes('object') ? liste[0] ?? null : liste });
    }
    if (etatGroupe.panne) return route.fulfill({ status: 503, json: { message: 'Service de recette indisponible' } });
    const selection = etabs.filter(e => url.searchParams.get('etablissement_id')?.includes(e.id));
    if (req.method() === 'HEAD') {
      const count = url.searchParams.get('statut') === 'eq.OUVERTE' ? selection.length : 0;
      return route.fulfill({ headers: { 'content-range': count ? `0-${count - 1}/${count}` : '*/0' }, body: '' });
    }
    const lignes = selection.map(e => ({ etablissement_id: e.id, statut: 'OUVERTE' }));
    return route.fulfill({ json: lignes });
  });
  await page.goto('/connexion');
  await page.getByLabel('Email', { exact: true }).fill(email);
  await page.getByLabel('Mot de passe', { exact: true }).fill('Mot!Solide-Recette2026');
  await page.getByRole('button', { name: 'Se connecter', exact: true }).click();
  await expect(page).toHaveURL(invite ? /\/etablissement\/tableau-de-bord$/ : /\/groupe\/tableau-de-bord$/);
  return { etat, etatGroupe };
}

test('groupe — statistiques en panne, réessai et sélection sans fausses lignes', async ({ page }, info) => {
  const { etat, etatGroupe } = await fixtureGroupe(page);
  await expect(page.getByRole('alert').filter({ hasText: 'statistiques du groupe' })).toBeVisible();
  await expect(page.getByRole('table')).toHaveCount(0);
  await preuve(page, 'groupe-erreur-statistiques', info);
  etatGroupe.panne = false;
  await page.getByRole('button', { name: 'Réessayer' }).click();
  await expect(page.getByRole('table').getByText(etabs[1].nom)).toBeVisible();
  await page.getByRole('combobox', { name: 'Établissement', exact: true }).selectOption(etabs[0].id);
  await expect(page.getByRole('table').getByText(etabs[0].nom)).toBeVisible();
  await expect(page.getByRole('table').getByText(etabs[1].nom)).toHaveCount(0);
  const kpi = page.getByText('Établissements actifs', { exact: true }).locator('../..');
  await expect(kpi).toContainText('1');
  await sansDebordement(page);
  await preuve(page, 'groupe-selection-reprise', info);
  await stabiliserLectures(page);
  expect(etat.inconnues).toEqual([]);
  expect(etat.erreurs).toEqual([]);
});

test('établissement invité — groupe lié au scope, panne distincte et réessai', async ({ page }, info) => {
  const { etat, etatGroupe } = await fixtureGroupe(page, true);
  await allerA(page, '/etablissement/parametres?tab=operations');
  await expect(page.getByRole('alert').filter({ hasText: 'informations du groupe' })).toBeVisible();
  await expect(page.getByText('Établissement indépendant', { exact: true })).toHaveCount(0);
  etatGroupe.panne = false;
  await page.getByRole('button', { name: 'Réessayer', exact: true }).click();
  await expect(page.getByRole('heading', { name: 'Groupe de recette', exact: true })).toBeVisible();
  await expect(page.getByText('📍 Vous êtes ici', { exact: true })).toBeVisible();
  expect(etatGroupe.idsLus).toContain(`eq.${etabs[0].id}`);
  await sansDebordement(page);
  await preuve(page, 'etab-invite-groupe-reprise', info);
  await stabiliserLectures(page);
  expect(etat.inconnues).toEqual([]);
  expect(etat.erreurs).toEqual([]);
});
