import { test, expect } from '@playwright/test';
import { creerMissionSimulee, ids, now, type RoleRecette } from './helpers/recette-complete-mission';

// Navigation UI uniquement : Auth, contrats et autres réponses API sont fictifs.
// Aucune lecture de compte réel, signature, génération de document ou émission SMS.
for (const role of ['SOIGNANT', 'ADMIN_ETABLISSEMENT'] as RoleRecette[]) {
  test(`FILTRES CONTRATS — ${role} : conserver onglet, origine et filtre après rechargement`, async ({ context, page }, info) => {
    const { state, installer } = creerMissionSimulee();
    state.contratCree = true;
    state.mission.statut = 'ASSIGNEE';
    state.mission.soignant_assigne_id = ids.soignant;
    const contrats = [
      { ...state.contrat, numero_contrat: 'SIM-FILTRE-ATTENTE', statut: 'EN_ATTENTE_SIGNATURES',
        signature_soignant: false, signature_etablissement: false, cree_le: now },
      { ...state.contrat, id: '71000000-0000-4000-8000-000000000061', numero_contrat: 'SIM-FILTRE-SIGNE',
        statut: 'SIGNE_COMPLET', signature_soignant: true, signature_etablissement: true,
        cree_le: '2026-09-24T06:54:59.000Z' },
      { ...state.contrat, id: '71000000-0000-4000-8000-000000000062', numero_contrat: 'SIM-FILTRE-ANNULE',
        statut: 'ANNULE', signature_soignant: false, signature_etablissement: false,
        cree_le: '2026-09-24T06:54:58.000Z' },
    ].map(contrat => ({ ...contrat, missions: {
      intitule: 'Mission fictive — filtres contrats', debut_le: state.mission.debut_le, fin_le: state.mission.fin_le,
    } }));
    const contratsInitiaux = structuredClone(contrats);
    const lectures: { scope: string; ordre: string }[] = [];
    const refus: { methode: string; chemin: string; parametres: string[] }[] = [];
    const etapes: { filtre: string | null; query: string; numeros: readonly string[] }[] = [];
    await installer(context, role);
    await page.clock.setFixedTime(new Date(now));
    await context.route('https://fonts.googleapis.com/**', route => route.fulfill({ contentType: 'text/css', body: '' }));
    await context.route('**/rest/v1/contrats_mission*', async route => {
      const request = route.request(), url = new URL(request.url());
      if (!['127.0.0.1', 'localhost'].includes(url.hostname)) {
        state.external.push(url.origin);
        return route.abort('blockedbyclient');
      }
      const headers = { 'access-control-allow-origin': '*', 'access-control-allow-headers': '*' };
      if (request.method() === 'OPTIONS' && url.pathname === '/rest/v1/contrats_mission') {
        return route.fulfill({ json: {}, headers });
      }
      const scope = role === 'SOIGNANT' ? 'soignant_id' : 'etablissement_id';
      const uid = role === 'SOIGNANT' ? ids.soignant : ids.etablissement;
      const select = 'id,mission_id,numero_contrat,type_contrat,statut,soignant_id,etablissement_id,signature_soignant,signature_etablissement,cree_le,missions(intitule,debut_le,fin_le)';
      const attendus = new URLSearchParams({ select, [scope]: `eq.${uid}`, order: 'cree_le.desc' });
      const conforme = request.method() === 'GET' && url.pathname === '/rest/v1/contrats_mission'
        && [...url.searchParams].length === 3
        && [...attendus].every(([cle, valeur]) => url.searchParams.getAll(cle).length === 1 && url.searchParams.get(cle) === valeur);
      if (!conforme) {
        refus.push({ methode: request.method(), chemin: url.pathname, parametres: [...url.searchParams.keys()] });
        return route.fulfill({ status: 501, json: { message: 'Lecture contrats hors contrat de simulation' }, headers });
      }
      lectures.push({ scope, ordre: url.searchParams.get('order')! });
      // Le composant filtre localement : chaque lecture fournit les trois mêmes contrats.
      return route.fulfill({ json: contrats, headers });
    });

    const soignant = role === 'SOIGNANT';
    const pathname = soignant ? '/soignant/mes-documents' : '/etablissement/contrats';
    const initial = `${pathname}?${soignant ? 'tab=contrats&' : ''}origine=recette`;
    const zone = soignant ? page.getByRole('tabpanel', { name: 'Contrats', exact: true }) : page.getByRole('main');
    const numerosTous = contrats.map(contrat => contrat.numero_contrat);
    const numeroContrat = /^SIM-FILTRE-(?:ATTENTE|SIGNE|ANNULE)$/;
    const verifierEtat = async (statut: string | null, numeros: readonly string[]) => {
      await expect(page).toHaveURL(url => url.pathname === pathname
        && url.searchParams.getAll('origine').length === 1 && url.searchParams.get('origine') === 'recette'
        && (soignant ? url.searchParams.getAll('tab').length === 1 && url.searchParams.get('tab') === 'contrats' : !url.searchParams.has('tab'))
        && (statut === null ? !url.searchParams.has('statut') : url.searchParams.getAll('statut').length === 1 && url.searchParams.get('statut') === statut)
        && [...url.searchParams].length === (soignant ? 2 : 1) + (statut === null ? 0 : 1));
      if (soignant) {
        await expect(page.getByRole('tab', { name: 'Contrats', exact: true })).toHaveAttribute('aria-selected', 'true');
        await expect(page.getByRole('tab', { name: 'Justificatifs', exact: true })).toHaveAttribute('aria-selected', 'false');
        await expect(zone).toBeVisible();
      }
      await expect(zone.getByRole('heading', { name: soignant ? 'Mes contrats' : 'Contrats', exact: true })).toBeVisible();
      await expect(zone.getByText(numeroContrat)).toHaveText([...numeros]);
      for (const numero of numerosTous) {
        const resultat = zone.getByText(numero, { exact: true });
        if (numeros.includes(numero)) await expect(resultat).toBeVisible();
        else await expect(resultat).toHaveCount(0);
      }
      etapes.push({ filtre: statut, query: new URL(page.url()).search, numeros });
    };
    const filtres = [
      { bouton: 'En attente', statut: 'EN_ATTENTE_SIGNATURES', numeros: [numerosTous[0]] },
      { bouton: 'Signés', statut: 'SIGNE_COMPLET', numeros: [numerosTous[1]] },
      { bouton: 'Annulés', statut: 'ANNULE', numeros: [numerosTous[2]] },
      { bouton: 'Tous', statut: null, numeros: numerosTous },
    ];
    try {
      await page.goto(initial);
      await verifierEtat(null, numerosTous);
      await info.attach('contrats-tous-initial-aria', { body: await zone.ariaSnapshot(), contentType: 'text/plain' });
      for (const filtre of filtres) {
        await zone.getByRole('button', { name: filtre.bouton, exact: true }).click();
        await verifierEtat(filtre.statut, filtre.numeros);
        const avantReload = lectures.length;
        await page.reload();
        await verifierEtat(filtre.statut, filtre.numeros);
        expect(lectures.length).toBeGreaterThan(avantReload);
        await info.attach(`contrats-${filtre.bouton}-reload-aria`, { body: await zone.ariaSnapshot(), contentType: 'text/plain' });
      }
      expect(contrats).toEqual(contratsInitiaux);
      expect(refus).toEqual([]);
      expect(state.unknown).toEqual([]);
      expect(state.external).toEqual([]);
      expect(state.errors).toEqual([]);
      expect(state.signatures).toEqual([]);
      expect(state.sms).toEqual([]);
      expect(state.emails).toEqual([]);
    } finally {
      await info.attach('journal-synthetique-filtres-contrats', {
        body: JSON.stringify({ role, lectures, refus, etapes, errors: state.errors, unknown: state.unknown, external: state.external }),
        contentType: 'application/json',
      });
    }
  });
}
