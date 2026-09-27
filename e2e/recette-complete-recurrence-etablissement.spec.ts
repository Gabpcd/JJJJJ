import { expect, test } from '@playwright/test';
import { definirHoraire, definirPeriode, ouvrirRecurrence, verifierIsolation } from './helpers/recette-complete-recurrence-etablissement';
import { preuve } from './helpers/recette-complete-etablissement';

test.use({ actionTimeout: 15_000 });

test('récurrence : six journées de neuf heures bloquées, puis limite exacte de 48 h autorisée sans publication', async ({ page }, info) => {
  const simulation = await ouvrirRecurrence(page);
  await definirPeriode(page, '2030-10-14', '2030-10-19');
  await definirHoraire(page, '2030-10-14', '07:00', '16:00');
  await page.getByRole('button', { name: 'Appliquer le 1er horaire aux jours sélectionnés', exact: true }).click();
  for (const jour of ['14', '15', '16', '17', '18', '19']) {
    await expect(page.getByLabel(`Début du créneau 1 du 2030-10-${jour}`, { exact: true })).toHaveValue('07:00');
    await expect(page.getByLabel(`Fin du créneau 1 du 2030-10-${jour}`, { exact: true })).toHaveValue('16:00');
  }
  const alertes = page.getByRole('alert');
  await expect(alertes).toHaveCount(1);
  await expect(alertes).toContainText('Semaine du 14/10 : 54 h travaillées. Maximum légal : 48 h/semaine.');
  await expect(alertes.locator('p').filter({ hasText: '54 h travaillées' })).toHaveCount(1);
  await expect(page.getByTestId('recap-semaines')).toContainText('54 h');
  const publier = page.getByRole('button', { name: /^Publier la mission(?: \(\d+ créneaux\))?$/ });
  await expect(publier).toBeDisabled();
  await expect(page.getByRole('dialog')).toHaveCount(0);
  await preuve(page, 'recurrence-54h-erreur-unique', info);

  await definirHoraire(page, '2030-10-14', '07:00', '15:00');
  await page.getByRole('button', { name: 'Appliquer le 1er horaire aux jours sélectionnés', exact: true }).click();
  await expect(alertes).toHaveCount(0);
  await expect(page.getByTestId('recap-semaines')).toContainText('48 h');
  await expect(page.getByText('Aperçu exact · 6 créneaux', { exact: true })).toBeVisible();
  await expect(publier).toBeEnabled();
  await publier.click();
  const recap = page.getByRole('dialog');
  await expect(recap).toContainText('48h00');
  await expect(recap).toContainText('1440.00 €');
  await expect(recap).toContainText('Planning exact · 6 créneaux');
  await expect(recap.getByRole('button', { name: '📤 Publier', exact: true })).toBeEnabled();
  await preuve(page, 'recurrence-48h-recap-sans-publication', info);
  await verifierIsolation(page, simulation);
});

test('récurrence : pause entre deux créneaux exclue du total et exception préservée à l’extension de période', async ({ page }, info) => {
  const simulation = await ouvrirRecurrence(page);
  await definirPeriode(page, '2030-10-14');
  await definirHoraire(page, '2030-10-14', '07:00', '12:00');
  await page.getByTestId('jour-planning-2030-10-14').getByRole('button', { name: 'Ajouter un créneau ce jour', exact: true }).click();
  await definirHoraire(page, '2030-10-14', '13:00', '17:00', 2);
  await expect(page.getByRole('alert')).toHaveCount(0);
  await expect(page.getByTestId('recap-semaines')).toContainText('9 h');
  await page.getByLabel('Dernière date affichée *', { exact: true }).fill('2030-10-15');
  await expect(page.getByLabel('Début du créneau 2 du 2030-10-14', { exact: true })).toHaveValue('13:00');
  await expect(page.getByLabel('Fin du créneau 2 du 2030-10-14', { exact: true })).toHaveValue('17:00');
  await expect(page.getByTestId('jour-planning-2030-10-15').getByRole('checkbox')).not.toBeChecked();
  await expect(page.getByTestId('recap-semaines')).toContainText('9 h');
  await page.getByRole('button', { name: /^Publier la mission(?: \(\d+ créneaux\))?$/ }).click();
  const recap = page.getByRole('dialog');
  await expect(recap).toContainText('Planning exact · 2 créneaux');
  await expect(recap).toContainText('9h00');
  await expect(recap).toContainText('270.00 €');
  await expect(recap).toContainText('07:00 → lundi 14 octobre 2030 · 12:00');
  await expect(recap).toContainText('13:00 → lundi 14 octobre 2030 · 17:00');
  await preuve(page, 'recurrence-pause-exclue-exception-preservee', info);
  await verifierIsolation(page, simulation);
});

test('récurrence : nuit dimanche–lundi explicite et répartition exacte entre deux semaines', async ({ page }, info) => {
  const simulation = await ouvrirRecurrence(page);
  await definirPeriode(page, '2030-10-20');
  await definirHoraire(page, '2030-10-20', '22:00', '06:00');
  await expect(page.getByRole('alert')).toHaveCount(1);
  await expect(page.getByRole('button', { name: /^Publier la mission(?: \(\d+ créneaux\))?$/ })).toBeDisabled();
  await page.getByLabel('Date de fin du créneau 1 du 2030-10-20', { exact: true }).selectOption('LENDEMAIN');
  await expect(page.getByRole('alert')).toHaveCount(0);
  const semaines = page.getByTestId('recap-semaines');
  await expect(semaines.locator('div').filter({ has: page.getByText('Semaine du 14/10', { exact: true }) }).last()).toHaveText('Semaine du 14/102 h');
  await expect(semaines.locator('div').filter({ has: page.getByText('Semaine du 21/10', { exact: true }) }).last()).toHaveText('Semaine du 21/106 h');
  await page.getByRole('button', { name: /^Publier la mission(?: \(\d+ créneaux\))?$/ }).click();
  const recap = page.getByRole('dialog');
  await expect(recap).toContainText('8h00');
  await expect(recap).toContainText('240.00 €');
  await expect(recap).toContainText('dimanche 20 octobre 2030 · 22:00 → lundi 21 octobre 2030 · 06:00');
  await expect(recap).toContainText('Nuit (21h-6h) — ~8h estimées');
  await preuve(page, 'recurrence-nuit-deux-semaines', info);
  await verifierIsolation(page, simulation);
});

test('récurrence : duplication conserve les trois créneaux, la pause et la nuit sans remplacer le planning par son enveloppe', async ({ page }, info) => {
  const simulation = await ouvrirRecurrence(page, true);
  await expect(page.getByLabel('Intitulé *', { exact: true })).toHaveValue('Planning source — pause et nuit');
  await expect(page.getByLabel('Première date affichée *', { exact: true })).toHaveValue('2030-10-14');
  await expect(page.getByLabel('Dernière date affichée *', { exact: true })).toHaveValue('2030-10-16');
  await expect(page.getByLabel('Fin du créneau 1 du 2030-10-14', { exact: true })).toHaveValue('12:00');
  await expect(page.getByLabel('Début du créneau 2 du 2030-10-14', { exact: true })).toHaveValue('13:00');
  await expect(page.getByTestId('jour-planning-2030-10-15').getByRole('checkbox')).not.toBeChecked();
  await expect(page.getByLabel('Début du créneau 1 du 2030-10-16', { exact: true })).toHaveValue('22:00');
  await expect(page.getByLabel('Fin du créneau 1 du 2030-10-16', { exact: true })).toHaveValue('06:00');
  await expect(page.getByLabel('Date de fin du créneau 1 du 2030-10-16', { exact: true })).toHaveValue('LENDEMAIN');
  await expect(page.getByRole('alert')).toHaveCount(0);
  await expect(page.getByTestId('recap-semaines')).toContainText('17 h');
  await page.getByRole('button', { name: /^Publier la mission(?: \(\d+ créneaux\))?$/ }).click();
  const recap = page.getByRole('dialog');
  await expect(recap).toContainText('Planning exact · 3 créneaux');
  await expect(recap).toContainText('17h00');
  await expect(recap).toContainText('510.00 €');
  await expect(recap).toContainText('mercredi 16 octobre 2030 · 22:00 → jeudi 17 octobre 2030 · 06:00');
  await preuve(page, 'recurrence-duplication-exacte', info);
  await verifierIsolation(page, simulation);
});
