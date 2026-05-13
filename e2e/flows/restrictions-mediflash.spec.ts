/**
 * Flow C — Restrictions matrice profession × type_etab (Sprint 2 PR 6).
 *
 * Le trigger dec_valider_compatibilite_mission_liberal bloque côté DB
 * les missions libérales sur des paires incompatibles (ex: IDE LIBERAL
 * en CLINIQUE).
 *
 * Tests :
 *  - Mission IDE LIBERAL en CLINIQUE → blocage (le formulaire UI ou
 *    le INSERT RPC retourne erreur)
 *  - Mission MEDECIN LIBERAL en CABINET_MEDICAL → OK
 *  - Mission IDE CDD en CLINIQUE → OK (CDD non concerné)
 *
 * Skip par défaut car nécessite admin client + seed étab.
 * Activer via PLAYWRIGHT_SEED_MEDIFLASH=1.
 */
import { test, expect } from '@playwright/test';
import { adminClient } from '../helpers/db';

const SEED_READY = process.env.PLAYWRIGHT_SEED_MEDIFLASH === '1';

test.describe('Restrictions Mediflash (matrice prof × type_etab)', () => {
  test.beforeEach(() => {
    test.skip(!SEED_READY, 'Seed Mediflash E2E à compléter — flow validé manuellement Sprint 1 PR 2');
  });

  test('IDE LIBERAL en CLINIQUE → trigger refuse INSERT', async () => {
    const etabId = process.env.PLAYWRIGHT_ETAB_CLINIQUE_ID;
    test.skip(!etabId, 'PLAYWRIGHT_ETAB_CLINIQUE_ID non défini');

    const client = adminClient();
    const { error } = await client.from('missions' as any).insert({
      intitule: '[playwright-test] IDE LIBERAL CLINIQUE — refus attendu',
      etablissement_id: etabId,
      profession: 'IDE',
      type_contrat: 'REMPLACEMENT_LIBERAL',
      statut: 'BROUILLON',
      debut_le: new Date(Date.now() + 86400000).toISOString(),
      fin_le: new Date(Date.now() + 172800000).toISOString(),
      duree_heures: 8,
      taux_horaire_base: 35,
    } as any);

    expect(error, 'INSERT IDE LIBERAL en CLINIQUE doit être refusé par le trigger').toBeTruthy();
    expect(error?.message || '').toMatch(/(incompatible|libéral|compatibilité)/i);
  });

  test('MEDECIN LIBERAL en CABINET_MEDICAL → INSERT accepté', async () => {
    const etabId = process.env.PLAYWRIGHT_ETAB_CABINET_ID;
    test.skip(!etabId, 'PLAYWRIGHT_ETAB_CABINET_ID non défini');

    const client = adminClient();
    const { data, error } = await client.from('missions' as any).insert({
      intitule: '[playwright-test] MEDECIN LIBERAL CABINET — OK attendu',
      etablissement_id: etabId,
      profession: 'MEDECIN',
      type_contrat: 'REMPLACEMENT_LIBERAL',
      statut: 'BROUILLON',
      debut_le: new Date(Date.now() + 86400000).toISOString(),
      fin_le: new Date(Date.now() + 172800000).toISOString(),
      duree_heures: 6,
      taux_horaire_base: 80,
    } as any).select().single();

    expect(error).toBeNull();
    expect((data as any)?.id).toBeTruthy();

    // Cleanup
    if ((data as any)?.id) {
      await client.from('missions' as any).delete().eq('id', (data as any).id);
    }
  });

  test('IDE CDD en CLINIQUE → INSERT accepté (CDD non concerné par matrice libéral)', async () => {
    const etabId = process.env.PLAYWRIGHT_ETAB_CLINIQUE_ID;
    test.skip(!etabId, 'PLAYWRIGHT_ETAB_CLINIQUE_ID non défini');

    const client = adminClient();
    const { data, error } = await client.from('missions' as any).insert({
      intitule: '[playwright-test] IDE CDD CLINIQUE — OK attendu',
      etablissement_id: etabId,
      profession: 'IDE',
      type_contrat: 'CDD',
      statut: 'BROUILLON',
      debut_le: new Date(Date.now() + 86400000).toISOString(),
      fin_le: new Date(Date.now() + 172800000).toISOString(),
      duree_heures: 8,
      taux_horaire_base: 25,
    } as any).select().single();

    expect(error).toBeNull();
    expect((data as any)?.id).toBeTruthy();

    if ((data as any)?.id) {
      await client.from('missions' as any).delete().eq('id', (data as any).id);
    }
  });
});
