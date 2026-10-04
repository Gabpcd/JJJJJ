import { expect, test, type Locator, type TestInfo } from '@playwright/test';
import { simulerEtablissement, stabiliserLectures, ids as etabIds } from './helpers/recette-complete-etablissement';
import { simulerSoignant, attendreAPI, ids as soignantIds } from './helpers/recette-complete-soignant';

// Frontend App réel, identités et transport entièrement fictifs. Aucun envoi externe.
const litigeId = '71000000-0000-4000-8000-000000000095';
const missionId = '71000000-0000-4000-8000-000000000096';
const titre = 'Mission fictive — contrôle local des messages';
const lecturesRpc = new Set([
  'fn_get_my_role', 'fn_compte_auth_actif', 'fn_admin_mes_acces', 'fn_mon_profil_soignant_complet',
  'fn_mon_etablissement_complet', 'fn_mes_permissions_etab', 'fn_messages_non_lus', 'fn_param_bool',
  'fn_onboarding_soignant_statut', 'fn_etablissements_safe', 'fn_litiges_etablissement',
  'fn_etablissement_public', 'fn_note_moyenne', 'fn_mes_reclamations',
]);
const auditsInertes = new Set(['fn_update_presence', 'fn_audit_connexion', 'fn_ecrire_audit_safe', 'fn_maj_activite_soignant']);
const preuves = new Map<TestInfo, unknown>();
test.afterEach(async ({}, info) => {
  await info.attach('contrat-local-messages', { body: JSON.stringify(preuves.get(info), null, 2), contentType: 'application/json' });
  preuves.delete(info);
});

for (const role of ['SOIGNANT', 'ADMIN_ETABLISSEMENT', 'ADMIN_PLATEFORME'] as const) {
  test(`${role} : fil vide puis peuplé, deux envois visibles et reprise après reload`, async ({ page }, info) => {
    const activer = (element: Locator) => info.project.use.hasTouch ? element.tap() : element.click();
    const id = role === 'SOIGNANT' ? soignantIds.user : etabIds.user;
    const messages: Record<string, unknown>[] = [];
    const envois: { p_litige_id: string; p_contenu: string }[] = [];
    const refus: string[] = [], erreursConsole: string[] = [], audits: string[] = [];
    const compteurs = { messages: 0, listes: 0 };
    page.on('console', message => { if (message.type() === 'error') erreursConsole.push(message.text()); });
    const fixture = role === 'SOIGNANT' ? await simulerSoignant(page) : null;
    const etat = role !== 'SOIGNANT' ? (await simulerEtablissement(page)).etat : null;
    const overrides = fixture?.overrides ?? etat!.overrides;
    const inconnues = fixture?.unknown ?? etat!.inconnues;
    const erreursPage = fixture?.errors ?? etat!.erreurs;
    const stabiliser = () => role === 'SOIGNANT' ? attendreAPI(page) : stabiliserLectures(page);
    preuves.set(info, { role, simulationSeulement: true, envois, compteurs, refus, erreursConsole, erreursPage, inconnues, audits });
    const litige = {
      id: litigeId, mission_id: missionId, soignant_id: soignantIds.user, etablissement_id: etabIds.etab,
      motif: 'Discussion de recette synthétique sans intervention fournisseur', statut: 'REVUE_ADMIN',
      cree_le: '2026-10-04T08:00:00Z', initie_par: 'SOIGNANT', accord_soignant: false, accord_etablissement: false,
      payload_modifications: null, modifications_executees: false, type_litige: 'HEURES',
      missions: { id: missionId, intitule: titre, debut_le: '2026-10-04T08:00:00Z', fin_le: '2026-10-04T12:00:00Z', etablissement_id: etabIds.etab },
      soignants: { id: soignantIds.user, prenom: 'Camille', nom: 'Simulation', profession: 'IDE' },
      etablissements: { id: etabIds.etab, nom: 'Établissement fictif local' },
    };
    overrides.set('fn_get_my_role', { role, etablissement_id: role === 'ADMIN_ETABLISSEMENT' ? etabIds.etab : null });
    overrides.set('fn_admin_mes_acces', { acces_total: true, groupes: [] });
    overrides.set('fn_etablissements_safe', [litige.etablissements]);
    await page.addInitScript(({ userId, role }) => {
      sessionStorage.setItem('sb-127-auth-token', JSON.stringify({
        user: { id: userId, email: 'message-local@example.invalid', aud: 'authenticated', role: 'authenticated',
          email_confirmed_at: '2026-10-04T08:00:00Z', app_metadata: { role }, user_metadata: {} },
        access_token: 'fixture-auth', refresh_token: 'fixture-refresh', token_type: 'bearer',
        expires_in: 3600, expires_at: Math.floor(Date.now() / 1000) + 3600,
      }));
    }, { userId: id, role });
    await page.route('**/*', async route => {
      const req = route.request(), url = new URL(req.url()), nom = url.pathname.split('/').at(-1)!;
      const repondre = (json: unknown) => route.fulfill({ json, headers: { 'access-control-allow-origin': '*', 'access-control-allow-headers': '*', 'access-control-allow-methods': 'GET,POST,HEAD,OPTIONS' } });
      const refuser = () => { refus.push(`${req.method()} ${url.origin}${url.pathname}`); return route.abort(); };
      if (url.hostname === 'fonts.googleapis.com') return route.fulfill({ contentType: 'text/css', body: '' });
      if (url.hostname === 'js.stripe.com') return route.fulfill({ contentType: 'application/javascript', body: 'window.Stripe = function(){ return {}; };' });
      if (!['127.0.0.1', 'localhost'].includes(url.hostname)) return refuser();
      if (/\/(functions|storage)\/v1\//.test(url.pathname)) return refuser();
      if (req.method() === 'OPTIONS' && /\/(auth|rest)\/v1\//.test(url.pathname)) return route.fulfill({ status: 204, body: '', headers: { 'access-control-allow-origin': '*', 'access-control-allow-headers': '*', 'access-control-allow-methods': 'GET,POST,HEAD,OPTIONS' } });
      if (url.pathname.startsWith('/auth/v1/') && !(req.method() === 'GET' && nom === 'user')) return refuser();
      if (!url.pathname.startsWith('/rest/v1/')) return route.fallback();
      if (url.pathname.startsWith('/rest/v1/rpc/')) {
        if (req.method() !== 'POST') return refuser();
        if (nom === 'fn_ajouter_message_litige') {
          expect(req.headers().authorization).toBe('Bearer fixture-auth');
          const contenu = `Message fictif ${envois.length + 1} — ${role}, aucun destinataire réel.`;
          const attendu = { p_litige_id: litigeId, p_contenu: contenu };
          expect(req.postDataJSON()).toEqual(attendu);
          expect(envois.length).toBeLessThan(2);
          envois.push(attendu);
          messages.push({ id: `72000000-0000-4000-8000-00000000000${envois.length}`, litige_id: litigeId,
            auteur_id: id, type_auteur: role === 'ADMIN_PLATEFORME' ? 'ADMIN' : role === 'SOIGNANT' ? 'SOIGNANT' : 'ETABLISSEMENT',
            contenu, cree_le: `2026-10-04T08:0${envois.length}:00Z` });
          return repondre({ success: true });
        }
        if (auditsInertes.has(nom)) { audits.push(nom); return repondre(null); }
        if (!lecturesRpc.has(nom)) return refuser();
        if (nom === 'fn_litiges_etablissement') {
          expect(role).toBe('ADMIN_ETABLISSEMENT');
          expect(req.postDataJSON()).toEqual({ p_etablissement_id: etabIds.etab });
          compteurs.listes++;
          return repondre([{ ...litige, litige_id: litige.id, mission_intitule: titre,
            mission_debut: litige.missions.debut_le, soignant_nom: 'Camille Simulation', soignant_profession: 'IDE',
            nb_messages: messages.length, dernier_message: messages.at(-1)?.contenu ?? null }]);
        }
        return route.fallback();
      }
      if (!['GET', 'HEAD'].includes(req.method())) return refuser();
      if (nom === 'messages_litige') {
        expect(req.method()).toBe('GET');
        expect(url.searchParams.get('litige_id')).toBe(`eq.${litigeId}`);
        expect(url.searchParams.get('select')).toBe('*');
        expect(url.searchParams.get('order')).toBe('cree_le.asc');
        compteurs.messages++;
        return repondre(messages);
      }
      if (nom === 'litiges') {
        expect(role).not.toBe('ADMIN_ETABLISSEMENT');
        if (role === 'SOIGNANT') expect(url.searchParams.get('soignant_id')).toBe(`eq.${id}`);
        compteurs.listes++;
        return repondre([litige]);
      }
      return route.fallback();
    });
    const chemin = role === 'ADMIN_PLATEFORME' ? '/admin/litiges' : role === 'SOIGNANT' ? '/soignant/litiges' : '/etablissement/litiges';
    const dossier = page.locator(role === 'ADMIN_PLATEFORME' ? `[data-litige-id="${litigeId}"]` : `#litige-${litigeId}`);
    const champ = dossier.getByPlaceholder('Votre message (min. 10 caractères)...', { exact: true });
    async function ouvrir() {
      if (role === 'ADMIN_PLATEFORME') {
        await activer(page.getByRole('button', { name: /^Tous 1$/ }));
        await activer(dossier.locator('button[aria-expanded]'));
      } else if (role === 'ADMIN_ETABLISSEMENT') {
        await activer(dossier.getByRole('button', { name: '▼ Voir le litige', exact: true }));
      } else {
        await activer(dossier.getByText(titre, { exact: true }));
      }
      await expect(champ).toBeVisible();
      await stabiliser();
    }
    await page.goto(chemin);
    await ouvrir();
    await expect(dossier.getByText('Aucun message pour le moment', { exact: true })).toBeVisible();
    await expect(champ).toHaveValue('');
    await expect(dossier.getByRole('button', { name: 'Envoyer', exact: true })).toBeDisabled();
    for (const numero of [1, 2]) {
      const contenu = `Message fictif ${numero} — ${role}, aucun destinataire réel.`;
      const avant = { ...compteurs };
      await champ.fill(`  ${contenu}  `);
      await activer(dossier.getByRole('button', { name: 'Envoyer', exact: true }));
      await expect.poll(() => envois.length).toBe(numero);
      await expect.poll(() => compteurs.messages).toBeGreaterThan(avant.messages);
      await expect.poll(() => compteurs.listes).toBeGreaterThan(avant.listes);
      // Les remontages historiques E/admin peuvent relire le fil plusieurs fois.
      await stabiliser();
      await expect(champ).toHaveValue('');
      await expect(dossier.getByRole('button', { name: 'Envoyer', exact: true })).toBeDisabled();
      const messageFil = dossier.locator('p.text-foreground').filter({ hasText: contenu });
      await expect(messageFil).toHaveCount(1);
      await expect(messageFil).toHaveText(contenu);
      await expect(messageFil).toBeVisible();
      // Aucun scroll de test après l'envoi : le résultat doit rester à l'écran.
      await expect(messageFil).toBeInViewport();
      await expect(dossier.getByText('Aucun message pour le moment', { exact: true })).toHaveCount(0);
      await info.attach(`message-${numero}`, { body: await dossier.ariaSnapshot(), contentType: 'text/plain' });
      await page.screenshot({ path: info.outputPath(`message-${numero}.png`), scale: 'css' });
    }
    await stabiliser();
    await page.reload();
    await ouvrir();
    await expect(champ).toHaveValue('');
    for (const envoi of envois) await expect(dossier.locator('p.text-foreground').filter({ hasText: envoi.p_contenu })).toHaveText(envoi.p_contenu);
    expect(envois).toHaveLength(2);
    await info.attach('apres-reload', { body: await dossier.ariaSnapshot(), contentType: 'text/plain' });
    await page.screenshot({ path: info.outputPath('apres-reload.png'), scale: 'css' });
    expect(refus).toEqual([]); expect(inconnues).toEqual([]); expect(erreursPage).toEqual([]); expect(erreursConsole).toEqual([]);
  });
}
