import { expect, test, type BrowserContext, type Locator } from '@playwright/test';
import { runAxe } from './helpers/axe';
import { communicationsSimulees, conversationId } from './helpers/recette-complete-communications';
import { ids, now, type RoleRecette } from './helpers/recette-complete-mission';

test.use({ contextOptions: { reducedMotion: 'reduce' } });

async function conversationRemplie(context: BrowserContext, role: RoleRecette) {
  const state = await communicationsSimulees(context, role);
  const auteur = role === 'SOIGNANT' ? ids.soignant : ids.etablissement;
  const autre = role === 'SOIGNANT' ? ids.etablissement : ids.soignant;
  const messages = [
    { auteur_id: autre, contenu: 'Message reçu : rendez-vous à l’accueil.', est_admin: false, heure: '08:51' },
    { auteur_id: auteur, contenu: 'Message envoyé : arrivée confirmée.', est_admin: false, heure: '08:52' },
    { auteur_id: '71000000-0000-4000-8000-000000000011', contenu: 'Message de l’administration : dossier vérifié.', est_admin: true, heure: '08:53' },
    { auteur_id: '71000000-0000-4000-8000-000000000012', contenu: 'L’équipe a confirmé le rendez-vous.', est_admin: false, heure: '08:54' },
  ].map((message, index) => ({
    ...message,
    id: `message-accessibilite-${index}`,
    conversation_id: conversationId,
    lu: true,
    cree_le: `2026-09-24T06:${51 + index}:00.000Z`,
  }));
  const lectures: string[] = [];
  await context.route('**/rest/v1/messages_chat**', async route => {
    const request = route.request();
    if (request.method() !== 'GET') return route.fallback();
    const url = new URL(request.url());
    expect(url.origin).toBe('http://127.0.0.1:8890');
    expect(url.searchParams.get('conversation_id')).toBe(`eq.${conversationId}`);
    expect(url.searchParams.get('order')).toBe('cree_le.desc');
    expect(url.searchParams.get('limit')).toBe('500');
    expect(request.headers().authorization).toBe(`Bearer simulation-mission-${role}`);
    lectures.push(request.method());
    state.callsCommunications.push('messages_chat:GET');
    return route.fulfill({ status: 200, json: [...messages].reverse() });
  });
  return { state, messages, lectures };
}

async function contrasteBulle(bulle: Locator) {
  // Axe ne calcule pas le contraste sur background-image. Vérifier aussi
  // les petits textes et horodatages sur tous les segments du dégradé rendu.
  const rendu = await bulle.evaluate(element => {
    const canvas = document.createElement('canvas'); canvas.width = canvas.height = 1;
    const contexte = canvas.getContext('2d')!;
    const rgba = (couleur: string) => {
      contexte.clearRect(0, 0, 1, 1); contexte.fillStyle = couleur;
      contexte.fillRect(0, 0, 1, 1);
      return Array.from(contexte.getImageData(0, 0, 1, 1).data);
    };
    const style = getComputedStyle(element);
    const fonds = style.backgroundImage === 'none'
      ? [rgba(style.backgroundColor)]
      : (style.backgroundImage.match(/rgba?\([^)]+\)/g) ?? []).map(rgba);
    const opacites: number[] = [];
    for (let parent: Element | null = element; parent; parent = parent.parentElement) {
      opacites.push(Number(getComputedStyle(parent).opacity));
    }
    return {
      fonds, opacites,
      textes: Array.from(element.querySelectorAll('p')).map(paragraphe => ({
        texte: paragraphe.textContent,
        couleur: rgba(getComputedStyle(paragraphe).color),
        opacite: Number(getComputedStyle(paragraphe).opacity),
      })),
    };
  });
  expect(rendu.fonds.length, 'Fond effectif de la bulle identifié').toBeGreaterThan(0);
  expect(rendu.opacites.every(opacite => opacite === 1), 'Bulle et ancêtres opaques').toBe(true);
  const luminance = (couleur: number[]) => couleur.slice(0, 3).reduce((total, composante, index) => {
    const s = composante / 255;
    return total + [0.2126, 0.7152, 0.0722][index] * (s <= 0.04045 ? s / 12.92 : ((s + 0.055) / 1.055) ** 2.4);
  }, 0);
  const echantillons = [...rendu.fonds];
  for (let index = 1; index < rendu.fonds.length; index++) {
    for (let pas = 1; pas < 32; pas++) {
      const t = pas / 32;
      echantillons.push(rendu.fonds[index].map((valeur, canal) => rendu.fonds[index - 1][canal] * (1 - t) + valeur * t));
    }
  }
  for (const fond of rendu.fonds) expect(fond[3], 'Fond opaque pour le calcul').toBe(255);
  return rendu.textes.map(texte => {
    expect(texte.couleur[3], 'Couleur de texte opaque').toBe(255);
    expect(texte.opacite, 'Texte et horodatage opaques').toBe(1);
    const premier = luminance(texte.couleur);
    return { ...texte, minimum: Math.min(...echantillons.map(fond => {
      const second = luminance(fond);
      return (Math.max(premier, second) + 0.05) / (Math.min(premier, second) + 0.05);
    })) };
  });
}

for (const theme of ['light', 'dark'] as const) test.describe(`MESSAGERIE ACCESSIBLE ${theme}`, () => {
  test.use({ colorScheme: theme });
  for (const role of ['SOIGNANT', 'ADMIN_ETABLISSEMENT'] as const) {
    test(`${role} — conversation remplie, textes et horodatages lisibles`, async ({ context, page }, info) => {
      const { state, messages, lectures } = await conversationRemplie(context, role);
      const prefixe = role === 'SOIGNANT' ? 'soignant' : 'etablissement';
      await context.addInitScript(theme => {
        if (location.origin === 'http://127.0.0.1:8890') localStorage.setItem('theme', theme);
      }, theme);
      await page.clock.setFixedTime(new Date(now));
      try {
        await page.goto(`/${prefixe}/messagerie`);
        const conversation = page.getByRole('button', { name: /Dernier échange simulé/ });
        await expect(conversation).toBeVisible();
        await conversation.click();
        await expect(page).toHaveURL(new RegExp(`/${prefixe}/messagerie\\?conv=${conversationId}$`));
        for (const message of messages) {
          const texte = page.getByText(message.contenu, { exact: true });
          await texte.scrollIntoViewIfNeeded();
          await expect(texte).toBeInViewport();
          await expect(texte.locator('..').getByText(message.heure, { exact: true })).toBeVisible();
        }
        await expect(page.getByText('Admin Jolene', { exact: true })).toBeVisible();
        await expect(page.getByText('Équipe établissement', { exact: true })).toHaveCount(role === 'ADMIN_ETABLISSEMENT' ? 1 : 0);
        await expect(page.getByRole('textbox', { name: 'Saisir un message', exact: true })).toBeVisible();
        await expect(page.getByRole('button', { name: 'Envoyer le message', exact: true })).toBeDisabled();
        await page.waitForLoadState('networkidle');
        await page.evaluate(() => document.fonts.ready);
        const axe = await runAxe(page);
        const contrastes = [];
        for (const message of messages) {
          contrastes.push(...await contrasteBulle(page.getByText(message.contenu, { exact: true }).locator('..')));
        }
        const geometrie = await page.evaluate(() => ({ document: document.documentElement.scrollWidth, viewport: innerWidth }));
        await info.attach('messagerie-axe', { body: JSON.stringify(axe, null, 2), contentType: 'application/json' });
        await info.attach('messagerie-contrastes', { body: JSON.stringify(contrastes, null, 2), contentType: 'application/json' });
        await info.attach('messagerie-geometrie', { body: JSON.stringify(geometrie), contentType: 'application/json' });
        await info.attach('messagerie-aria', { body: await page.locator('body').ariaSnapshot(), contentType: 'text/plain' });
        if (['iphone', 'ipad-portrait', 'ipad-paysage'].includes(info.project.name)) {
          await info.attach(`messagerie-${prefixe}-${theme}`, { body: await page.screenshot({ animations: 'disabled' }), contentType: 'image/png' });
        }
        const retour = page.getByRole('button', { name: 'Retour aux conversations', exact: true });
        if (await retour.isVisible()) await retour.click();
        const archives = page.getByRole('tab', { name: /^Archivées/ });
        await archives.click();
        await expect(archives).toHaveAttribute('aria-selected', 'true');
        const conversationArchivee = page.getByRole('button', { name: /Échange archivé simulé/ });
        await expect(conversationArchivee).toBeVisible();
        await expect(conversationArchivee.getByText('Archivée — lecture seule', { exact: true })).toBeVisible();
        const axeArchives = await runAxe(page);
        const geometrieArchives = await page.evaluate(() => ({ document: document.documentElement.scrollWidth, viewport: innerWidth }));
        await info.attach('archives-axe', { body: JSON.stringify(axeArchives, null, 2), contentType: 'application/json' });
        await info.attach('archives-geometrie', { body: JSON.stringify(geometrieArchives), contentType: 'application/json' });
        if (['iphone', 'ipad-portrait', 'ipad-paysage'].includes(info.project.name)) {
          await info.attach(`archives-${prefixe}-${theme}`, { body: await page.screenshot({ animations: 'disabled' }), contentType: 'image/png' });
        }
        expect(axe.violations.filter(v => v.impact === 'serious' || v.impact === 'critical'), 'Axe sur la conversation remplie').toEqual([]);
        expect(axeArchives.violations.filter(v => v.impact === 'serious' || v.impact === 'critical'), 'Axe sur la liste des conversations archivées').toEqual([]);
        expect(contrastes.filter(texte => texte.minimum < 4.5), 'Contraste AA des textes, horodatages et libellés Admin/Équipe').toEqual([]);
        expect(geometrie.document, 'Aucun débordement horizontal').toBeLessThanOrEqual(geometrie.viewport + 1);
        expect(geometrieArchives.document, 'Aucun débordement horizontal des archives').toBeLessThanOrEqual(geometrieArchives.viewport + 1);
        expect(lectures.length, 'Historique réellement chargé depuis la fixture').toBeGreaterThan(0);
        expect(state.callsCommunications.filter(appel => appel.startsWith('messages_chat:')).every(appel => appel === 'messages_chat:GET')).toBe(true);
        expect(state.unknown).toEqual([]); expect(state.errors).toEqual([]);
        // Le helper bloque déjà tout trafic externe par route.abort. Les
        // imports CSS de polices bloqués sont les seuls appels attendus ici.
        expect(state.external.filter(origin => origin !== 'https://fonts.googleapis.com'), 'Aucun service externe sollicité').toEqual([]);
      } finally {
        await info.attach('messagerie-fixture-stricte', { body: JSON.stringify({ role, lectures, unknown: state.unknown, errors: state.errors, externalBlockedByFixture: state.external, calls: state.callsCommunications }, null, 2), contentType: 'application/json' });
      }
    });
  }
});
