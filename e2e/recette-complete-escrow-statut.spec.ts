import { expect, test } from '@playwright/test';
import { creerSuiviSimule } from './helpers/recette-complete-suivi-mission';
import { ids, now, preuveMission } from './helpers/recette-complete-mission';

for (const role of ['SOIGNANT', 'ADMIN_ETABLISSEMENT'] as const) {
  test(`${role} : prélèvement, remboursement demandé puis confirmé, panne et accès limité`, async ({ context, page }, info) => {
    const { state, installer, suivi } = creerSuiviSimule();
    state.mission.statut = 'TERMINEE'; state.mission.soignant_assigne_id = ids.soignant;
    state.mission.type_contrat_applique = 'LIBERAL'; state.contratCree = true;
    suivi.escrow = [{ statut: 'DEBITE', paye_le: null }];
    await installer(context, role); await page.clock.setFixedTime(new Date(now));
    await page.goto(`/${role === 'SOIGNANT' ? 'soignant' : 'etablissement'}/missions/${ids.mission}`);
    if (role === 'ADMIN_ETABLISSEMENT') await page.getByRole('button', { name: 'Fermer', exact: true }).click();
    const suiviUi = page.getByRole('region', { name: 'Suivi de la mission', exact: true });
    await suiviUi.getByRole('button', { name: 'Afficher le détail du suivi' }).click();
    const reglement = suiviUi.getByTestId('suivi-reglement');
    const actualiser = async () => { await suiviUi.getByRole('button', { name: 'Actualiser le suivi' }).click(); };
    await expect(reglement).toContainText('Fonds prélevés');
    if (role === 'ADMIN_ETABLISSEMENT') {
      await expect(page.getByText('Paiement suivi par Jolene', { exact: true })).toBeVisible();
      await expect(page.getByRole('button', { name: 'Déclarer le paiement effectué' })).toHaveCount(0);
      await expect(page.getByText('Honoraires à verser au soignant', { exact: false })).toHaveCount(0);
    }
    suivi.escrow[0].statut = 'REMBOURSE_EN_COURS'; await actualiser();
    await expect(reglement).toContainText('Remboursement en cours');
    await expect(reglement).not.toContainText('Remboursement confirmé');
    await preuveMission(page, info, `${role}-remboursement-en-cours`);
    suivi.escrow[0].statut = 'REMBOURSE'; await actualiser();
    await expect(reglement).toContainText('Remboursement confirmé');
    await expect(reglement).toContainText('remboursés à l’établissement');
    await expect(reglement).not.toContainText('Réception enregistrée');
    await expect(page.getByText('Montant à verser au soignant', { exact: false })).toHaveCount(0);
    await preuveMission(page, info, `${role}-remboursement-confirme`);
    suivi.erreurs.add('fn_suivi_escrow_mission'); await actualiser();
    await expect(reglement).toContainText('Information indisponible');
    await expect(suiviUi.getByRole('alert')).toBeVisible();
    suivi.erreurs.clear(); await actualiser();
    await expect(reglement).toContainText('Remboursement confirmé');
    if (role === 'ADMIN_ETABLISSEMENT') {
      const lecturesAvant = suivi.lectures.filter(l => l.table === 'fn_suivi_escrow_mission').length;
      suivi.financeAutorisee = false; suivi.copiesAutorisees = false; await actualiser();
      await expect(reglement).toContainText('Accès limité');
      expect(suivi.lectures.filter(l => l.table === 'fn_suivi_escrow_mission')).toHaveLength(lecturesAvant);
      await expect(suiviUi.getByRole('link', { name: 'Consulter les finances' })).toHaveCount(0);
    }
    expect(suivi.lectures.filter(l => l.table === 'fn_suivi_escrow_mission').every(l => l.select === 'statut,paye_le' && l.missionId === ids.mission)).toBe(true);
    expect(state.unknown).toEqual([]); expect(state.errors).toEqual([]);
    expect(state.signatures).toHaveLength(0); expect(state.sms).toHaveLength(0); expect(state.emails).toHaveLength(0);
    await info.attach('lectures-simulees-sans-mutation', { body: JSON.stringify(suivi.lectures), contentType: 'application/json' });
  });

  test(`${role} : le remboursement d’une mission en litige ne devient pas un statut inconnu`, async ({ context, page }, info) => {
    const { state, installer, suivi } = creerSuiviSimule();
    state.mission.statut = 'LITIGE'; state.mission.soignant_assigne_id = ids.soignant;
    state.mission.type_contrat_applique = 'LIBERAL'; state.contratCree = true;
    suivi.escrow = [{ statut: 'REMBOURSE', paye_le: null }];
    await installer(context, role);
    await page.goto(`/${role === 'SOIGNANT' ? 'soignant' : 'etablissement'}/missions/${ids.mission}`);
    const suiviUi = page.getByRole('region', { name: 'Suivi de la mission', exact: true });
    await suiviUi.getByRole('button', { name: 'Afficher le détail du suivi' }).click();
    await expect(suiviUi.getByTestId('suivi-mission')).toContainText('Mission marquée en litige');
    await expect(suiviUi.getByTestId('suivi-reglement')).toContainText('Remboursement confirmé');
    await expect(suiviUi).not.toContainText('Le statut de la mission n’est pas reconnu');
    expect(state.errors).toEqual([]); expect(state.unknown).toEqual([]);
    await preuveMission(page, info, `${role}-mission-litige-remboursement-confirme`);
  });
}
