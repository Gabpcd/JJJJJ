/**
 * Matrice des modes d'exercice — preuve UI + contrat DB.
 *
 * Activer avec PLAYWRIGHT_MODE_EXERCICE=1. Le compte établissement Playwright
 * doit être une clinique privée validée.
 */
import { test, expect, type Page } from '@playwright/test';
import { adminClient } from '../helpers/db';
import { loginAs } from '../helpers/auth';

const ACTIF = process.env.PLAYWRIGHT_MODE_EXERCICE === '1';

async function choisirProfession(page: Page, profession: string) {
  await page.locator('#mission-profession').click();
  await page.getByTestId(`profession-option-${profession}`).click();
}

test.describe('Matrice profession requise × établissement', () => {
  test.beforeEach(() => {
    test.skip(!ACTIF, 'Activer via PLAYWRIGHT_MODE_EXERCICE=1 (compte étab clinique requis)');
  });

  test('DB : trois niveaux, défaut salarié et profil IADE × mission IDE', async () => {
    const client = adminClient();

    const cas = [
      ['AS', 'CLINIQUE_PRIVEE', 'BLOQUE'],
      ['DENTISTE', 'CLINIQUE_PRIVEE', 'AUTORISE'],
      ['IDE', 'CLINIQUE_PRIVEE', 'NON_PROPOSE'],
      ['PROFESSION_INCONNUE', 'TYPE_INCONNU', 'NON_PROPOSE'],
      ['DENTISTE', 'CENTRE_SANTE', 'BLOQUE'],
      ['MANIPULATEUR_RADIO', 'CLINIQUE_PRIVEE', 'BLOQUE'],
      ['PHARMACIEN', 'CLINIQUE_PRIVEE', 'NON_PROPOSE'],
    ] as const;

    for (const [profession, typeEtab, niveau] of cas) {
      const { data, error } = await client.rpc('fn_mode_exercice', {
        p_profession: profession,
        p_type_etab: typeEtab,
        p_finess_secteur: null,
      });
      expect(error).toBeNull();
      expect((data as { niveau?: string } | null)?.niveau).toBe(niveau);
    }

    const { data: compatible, error: compatError } = await client.rpc(
      'fn_soignant_compatible_mission',
      {
        p_soignant_profession: 'IADE',
        p_soignant_specialite: null,
        p_mission_profession: 'IDE',
        p_mission_specialite: null,
        p_accepte_non_specialises: false,
      },
    );
    expect(compatError).toBeNull();
    expect(compatible).toBe(true);

    const { data: reverseCompatible, error: reverseCompatError } = await client.rpc(
      'fn_soignant_compatible_mission',
      {
        p_soignant_profession: 'IDE',
        p_soignant_specialite: null,
        p_mission_profession: 'IADE',
        p_mission_specialite: null,
        p_accepte_non_specialises: true,
      },
    );
    expect(reverseCompatError).toBeNull();
    expect(reverseCompatible).toBe(false);

    const { data: regleMission } = await client.rpc('fn_mode_exercice', {
      p_profession: 'IDE',
      p_type_etab: 'CLINIQUE_PRIVEE',
      p_finess_secteur: null,
    });
    expect((regleMission as { niveau?: string } | null)?.niveau).toBe('NON_PROPOSE');

    const sources = [
      ['IADE', 'CLINIQUE_PRIVEE', null, 'https://www.fehap.fr/jcms/navigation-internet/upload/docs/application/pdf/2023-02/courrierconjointministeres_30decembre2021_.pdf', 'https://www.legifrance.gouv.fr/ceta/id/CETATEXT000051156546'],
      ['MANIPULATEUR_RADIO', 'CLINIQUE_PRIVEE', null, 'https://www.legifrance.gouv.fr/codes/article_lc/LEGIARTI000033621093', null],
      ['DENTISTE', 'CENTRE_SANTE', null, 'https://www.legifrance.gouv.fr/codes/article_lc/LEGIARTI000047567923', null],
      ['PHARMACIEN', 'CLINIQUE_PRIVEE', null, null, null],
      ['MEDECIN', 'HOPITAL_PUBLIC', 'PUBLIC', null, null],
    ] as const;
    for (const [profession, typeEtab, secteur, sourceUrl, sourceUrlComplementaire] of sources) {
      const { data, error } = await client.rpc('fn_mode_exercice', {
        p_profession: profession,
        p_type_etab: typeEtab,
        p_finess_secteur: secteur,
      });
      expect(error).toBeNull();
      const mode = data as {
        source_url?: string | null;
        source_url_complementaire?: string | null;
      } | null;
      expect(mode?.source_url).toBe(sourceUrl);
      expect(mode?.source_url_complementaire).toBe(sourceUrlComplementaire);
    }
  });

  test('UI clinique : AS bloqué, IDE non proposé, dentiste autorisé', async ({ page }) => {
    await loginAs(page, 'etab');
    await page.goto('/etablissement/missions/creer');

    await choisirProfession(page, 'AS');
    await expect(page.getByText('Mode libéral non disponible', { exact: false })).toBeVisible();
    await expect(page.getByText(/Conseil d'État, 11\/02\/2025, n°491128/)).toBeVisible();
    await expect(page.getByText('Libéral', { exact: true })).toHaveCount(0);

    await choisirProfession(page, 'IDE');
    await expect(page.getByText('Mission proposée en salarié', { exact: false })).toBeVisible();
    await expect(page.getByText(/expose à une requalification/)).toBeVisible();
    await expect(page.getByText('Libéral', { exact: true })).toHaveCount(0);

    await choisirProfession(page, 'DENTISTE');
    await expect(page.getByText('Libéral', { exact: true })).toBeVisible();
    await expect(page.getByText('Mission proposée en salarié', { exact: false })).toHaveCount(0);
    await expect(page.getByText('Mode libéral non disponible', { exact: false })).toHaveCount(0);

    await choisirProfession(page, 'IADE');
    await expect(page.getByText(/lettre interministérielle du 30 décembre 2021/)).toBeVisible();
    await expect(page.getByText(/validée par le Conseil d'État.*n°491128/)).toBeVisible();
    await expect(page.getByRole('link', { name: 'Lire la lettre D21-031940 (texte original)' })).toHaveAttribute(
      'href',
      'https://www.fehap.fr/jcms/navigation-internet/upload/docs/application/pdf/2023-02/courrierconjointministeres_30decembre2021_.pdf',
    );
    await expect(page.getByRole('link', { name: 'Lire l’arrêt n°491128 — cas aide-soignant uniquement' })).toHaveAttribute(
      'href',
      'https://www.legifrance.gouv.fr/ceta/id/CETATEXT000051156546',
    );
    await expect(page.getByText('Accepter aussi les IDE non spécialisés')).toHaveCount(0);

    await choisirProfession(page, 'MANIPULATEUR_RADIO');
    await expect(page.getByRole('link', { name: 'Lire l’article L.4351-1 sur Légifrance' })).toHaveAttribute(
      'href',
      'https://www.legifrance.gouv.fr/codes/article_lc/LEGIARTI000033621093',
    );
  });
});
