import { expect, test } from '@playwright/test';
import { simulerSoignant, entrer, aller, sansDebordement } from './helpers/recette-complete-soignant';
import { preuve } from './helpers/recette-complete-etablissement';

// États de lecture simulés, pas une preuve de remboursement Stripe.
test('soignant — paiement annulé visible et séparé des revenus à venir et versés', async ({ page }, info) => {
  const etat = await simulerSoignant(page);
  etat.profile.type_exercice = 'LIBERAL'; etat.profile.statut_liberal = 'ACTIF';
  const lignes = [
    { mission_id: 'recette-annulee', etablissement_nom: 'Clinique Annulation', honoraires_cents: 25500, etat: 'ANNULE' },
    { mission_id: 'recette-reservee', etablissement_nom: 'Clinique Réservation', honoraires_cents: 9000, etat: 'RESERVE' },
    { mission_id: 'recette-versee', etablissement_nom: 'Clinique Versement', honoraires_cents: 10000, etat: 'VERSE' },
  ].map(l => ({ ...l, mission_intitule: 'Mission de recette', date_affichee: null, mission_date: '2026-09-28', a_litige: false }));
  etat.overrides.set('fn_mes_paiements_escrow', lignes);
  await entrer(page, 'connexion');
  await aller(page, '/soignant/mes-gains');
  const annules = page.getByRole('region', { name: 'Paiements rapides annulés' });
  await expect(annules.getByText('Paiement annulé', { exact: true })).toBeVisible();
  await expect(annules).toContainText(/255,00\s*€/);
  await expect(annules).not.toContainText('Clinique Réservation');
  await expect(annules).not.toContainText('Clinique Versement');
  await expect(page.getByText('Réservé', { exact: true })).toBeVisible();
  await expect(page.getByText('Versé', { exact: true })).toBeVisible();
  await sansDebordement(page);
  await preuve(page, 'paiements-avec-annulation', info);
  etat.overrides.set('fn_mes_paiements_escrow', [lignes[0]]);
  await page.reload();
  await expect(annules.getByText('Paiement annulé', { exact: true })).toBeVisible();
  await expect(page.getByText('Réservé', { exact: true })).toHaveCount(0);
  await expect(page.getByText('Versé', { exact: true })).toHaveCount(0);
  await preuve(page, 'paiement-annule-apres-rechargement', info);
  expect(etat.unknown).toEqual([]); expect(etat.errors).toEqual([]);
});
