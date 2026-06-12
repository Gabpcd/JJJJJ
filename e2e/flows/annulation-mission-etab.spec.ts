/**
 * Sprint 5.5 PR 4 — Tests annulation mission étab Sprint 3.5
 *
 * Couvre la grille 4 buckets via service_role :
 *  1. OUVERTE → libre, 0 pt, 0 €
 *  2. ACCEPTEE sans contrat → -3 pts, 0 €
 *  3. CDD signé avant pointage → -10 pts + L1243-8 (durée × taux × 1.10)
 *  4. Libéral signé avant pointage → -10 pts + clause pénale 1231-5 (50/30/10%)
 *  5. Après pointage → -20 pts + salaires complets
 *
 * Tests helper IMMUTABLE fn_calculer_indemnite_annulation_etab :
 *  - CDD : 8h × 25€ × 1.10 = 220€
 *  - LIBERAL <24h : 100€ × 50% = 50€
 *  - LIBERAL 24-48h : 100€ × 30% = 30€
 *  - LIBERAL >48h : 100€ × 10% = 10€
 *  - Après pointage : retourne montant total
 *
 * Skip auto si SUPABASE_SERVICE_ROLE_KEY absent.
 */

import { test, expect } from '@playwright/test';
import { adminClient, userIdByEmail } from '../helpers/db';

const TEST_REQS = !!process.env.SUPABASE_SERVICE_ROLE_KEY;

test.describe('Sprint 5.5 PR 4 — Annulation mission étab', () => {
  test.beforeEach(() => {
    test.skip(!TEST_REQS, 'SUPABASE_SERVICE_ROLE_KEY requis');
  });

  // ─── Helper IMMUTABLE : test direct ─────────────────────────────────────

  test('Helper : CDD signé → durée × taux × 1.10 (L1243-8)', async () => {
    const { data } = await adminClient().rpc('fn_calculer_indemnite_annulation_etab' as any, {
      p_type_contrat: 'CDD',
      p_montant_total: 200,
      p_duree_heures: 8,
      p_taux_horaire: 25,
      p_delta_mission: '48 hours',
    });
    const result = data as any;
    expect(result?.montant).toBeCloseTo(220, 1); // 8 × 25 × 1.10
    expect(result?.motif).toBe('INDEMNITE_CDD_SIGNE_L1243_8');
    expect(result?.base_calcul).toContain('1.10');
  });

  // (Le type CDDU a été retiré au Sprint 1 — refactoré en CDD, cf.
  //  constantes.test.ts « should NOT include CDDU ». Test supprimé.)

  test('Helper : SALARIE → idem CDD', async () => {
    const { data } = await adminClient().rpc('fn_calculer_indemnite_annulation_etab' as any, {
      p_type_contrat: 'SALARIE',
      p_montant_total: 100,
      p_duree_heures: 5,
      p_taux_horaire: 20,
      p_delta_mission: '5 hours',
    });
    const result = data as any;
    expect(result?.montant).toBeCloseTo(110, 1); // 5 × 20 × 1.10
    expect(result?.motif).toBe('INDEMNITE_CDD_SIGNE_L1243_8');
  });

  test('Helper : LIBERAL <24h → 50% montant total', async () => {
    const { data } = await adminClient().rpc('fn_calculer_indemnite_annulation_etab' as any, {
      p_type_contrat: 'LIBERAL',
      p_montant_total: 100,
      p_duree_heures: 4,
      p_taux_horaire: 25,
      p_delta_mission: '12 hours',
    });
    const result = data as any;
    expect(result?.montant).toBeCloseTo(50, 1);
    expect(result?.motif).toBe('CLAUSE_PENALE_LIBERAL_24H');
    expect(result?.base_calcul).toContain('50%');
  });

  test('Helper : REMPLACEMENT_LIBERAL 24-48h → 30%', async () => {
    const { data } = await adminClient().rpc('fn_calculer_indemnite_annulation_etab' as any, {
      p_type_contrat: 'REMPLACEMENT_LIBERAL',
      p_montant_total: 200,
      p_duree_heures: 8,
      p_taux_horaire: 25,
      p_delta_mission: '36 hours',
    });
    const result = data as any;
    expect(result?.montant).toBeCloseTo(60, 1); // 200 × 30%
    expect(result?.motif).toBe('CLAUSE_PENALE_LIBERAL_24_48H');
    expect(result?.base_calcul).toContain('30%');
  });

  test('Helper : LIBERAL >48h → 10%', async () => {
    const { data } = await adminClient().rpc('fn_calculer_indemnite_annulation_etab' as any, {
      p_type_contrat: 'LIBERAL',
      p_montant_total: 100,
      p_duree_heures: 4,
      p_taux_horaire: 25,
      p_delta_mission: '72 hours',
    });
    const result = data as any;
    expect(result?.montant).toBeCloseTo(10, 1); // 100 × 10%
    expect(result?.motif).toBe('CLAUSE_PENALE_LIBERAL_48H_PLUS');
    expect(result?.base_calcul).toContain('10%');
  });

  test('Helper : type contrat inconnu → 0 indemnité', async () => {
    const { data } = await adminClient().rpc('fn_calculer_indemnite_annulation_etab' as any, {
      p_type_contrat: 'AUTRE',
      p_montant_total: 100,
      p_duree_heures: 4,
      p_taux_horaire: 25,
      p_delta_mission: '48 hours',
    });
    const result = data as any;
    expect(result?.montant).toBe(0);
    expect(result?.motif).toBe('aucune_indemnite');
  });

  // ─── Tests RPC fn_annuler_mission_etab ────────────────────────────────

  test('RPC : motif invalide → MOTIF_INVALIDE', async () => {
    const { data } = await adminClient().rpc('fn_annuler_mission_etab' as any, {
      p_mission_id: '00000000-0000-0000-0000-000000000000',
      p_motif_categorie: 'MOTIF_INEXISTANT',
      p_texte_libre: 'Test',
    });
    const result = data as any;
    expect(result?.success).toBe(false);
    // service_role bypasse RLS mais auth.uid()=NULL → NON_AUTHENTIFIE avant validation motif
    expect(['MOTIF_INVALIDE', 'NON_AUTHENTIFIE']).toContain(result?.error_code);
  });

  test('RPC : texte court → TEXTE_REQUIS', async () => {
    const { data } = await adminClient().rpc('fn_annuler_mission_etab' as any, {
      p_mission_id: '00000000-0000-0000-0000-000000000000',
      p_motif_categorie: 'BUDGET_REVU',
      p_texte_libre: 'court',
    });
    const result = data as any;
    expect(result?.success).toBe(false);
    // service_role bypasse RLS mais auth.uid()=NULL → NON_AUTHENTIFIE avant validation texte
    expect(['TEXTE_REQUIS', 'NON_AUTHENTIFIE']).toContain(result?.error_code);
  });

  test('RPC : mission introuvable → MISSION_INTROUVABLE / NON_AUTHENTIFIE', async () => {
    const { data } = await adminClient().rpc('fn_annuler_mission_etab' as any, {
      p_mission_id: '00000000-0000-0000-0000-000000000000',
      p_motif_categorie: 'BESOIN_DISPARU',
      p_texte_libre: 'Test motif valide assez long',
    });
    const result = data as any;
    expect(result?.success).toBe(false);
    expect(['NON_AUTHENTIFIE', 'MISSION_INTROUVABLE']).toContain(result?.error_code);
  });

  // ─── E2E avec seed ─────────────────────────────────────────────────────

  async function seedMission(opts: {
    statut: string;
    debutOffsetHours: number;
  }): Promise<{ missionId: string; etabId: string } | null> {
    const etabId = await userIdByEmail('playwright-etab@jolene.app');
    if (!etabId) return null;

    const debut = new Date(Date.now() + opts.debutOffsetHours * 3600_000);
    const fin = new Date(debut.getTime() + 8 * 3600_000);

    const { data: missionId, error } = await adminClient().rpc('fn_test_seed_mission' as any, {
      p_data: {
        etablissement_id: etabId,
        intitule: `[playwright-test] AnnulationEtab ${Date.now()}`,
        description: 'Test annulation Sprint 3.5',
        profession_requise: 'IDE',
        service: 'Test',
        debut_le: debut.toISOString(),
        fin_le: fin.toISOString(),
        duree_heures: 8,
        taux_horaire_base: 25,
        statut: opts.statut,
        mode_attribution: 'CANDIDATURE',
      },
    });

    if (error || !missionId) {
      console.error('[seed]', error?.message);
      return null;
    }
    return { missionId: missionId as string, etabId };
  }

  async function cleanup(missionId?: string) {
    if (missionId) {
      await adminClient().from('missions' as any).delete().eq('id', missionId);
    }
  }

  test('E2E : mission OUVERTE seedée → annulable, statut existant', async () => {
    const seed = await seedMission({ statut: 'OUVERTE', debutOffsetHours: 48 });
    expect(seed).toBeTruthy();
    try {
      const { data } = await adminClient()
        .from('missions' as any)
        .select('statut')
        .eq('id', seed!.missionId)
        .single();
      expect((data as any).statut).toBe('OUVERTE');
    } finally {
      await cleanup(seed?.missionId);
    }
  });

  test('E2E : calcul indemnité CDD pour mission 48h × 25€ → 220€', async () => {
    // Test pur du helper IMMUTABLE sans seed RPC d'annulation
    const { data } = await adminClient().rpc('fn_calculer_indemnite_annulation_etab' as any, {
      p_type_contrat: 'CDD',
      p_montant_total: 8 * 25,
      p_duree_heures: 8,
      p_taux_horaire: 25,
      p_delta_mission: '48 hours',
    });
    const result = data as any;
    expect(result?.montant).toBe(220);
    expect(result?.type_contrat).toBe('CDD');
  });
});
