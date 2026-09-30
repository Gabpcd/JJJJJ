/**
 * Évaluation reverse : vérifications API sans mutation sur la base partagée.
 * La preuve métier (acteurs authentifiés, création, RLS et double aveugle)
 * est dans tests/security/notation-reverse-transactionnelle.test.sql, annulée.
 * Aucune erreur SQL ou fixture absente ne peut transformer un échec en skip.
 */
import { test, expect } from '@playwright/test';
import { adminClient } from '../helpers/db';

const TEST_REQS = Boolean(process.env.SUPABASE_SERVICE_ROLE_KEY);
const ABSENT_ID = '00000000-0000-0000-0000-000000000000';

test.describe('Évaluation reverse — API partagée en lecture seule', () => {
  test.beforeEach(() => {
    test.skip(!TEST_REQS, 'SUPABASE_SERVICE_ROLE_KEY requis pour les contrôles API');
  });

  test('la liste refuse explicitement une requête sans utilisateur', async () => {
    const { data, error } = await adminClient().rpc('fn_lister_missions_a_noter_etab');
    expect(error).toBeNull();
    expect(data).toEqual({ success: false, error_code: 'NON_AUTHENTIFIE' });
  });

  test('les colonnes de notation existent sans lire de notation personnelle', async () => {
    const { data, error } = await adminClient()
      .from('notations_missions')
      .select('id,mission_id,notateur_id,note_id,sens,critere_1,critere_2,critere_3,critere_4,publie_le')
      .eq('id', ABSENT_ID);
    expect(error).toBeNull();
    expect(data).toEqual([]);
  });

  test('le signalement refuse sans utilisateur avant toute lecture ou écriture', async () => {
    const { data, error } = await adminClient().rpc('fn_signaler_notation', {
      p_notation_id: ABSENT_ID,
      p_motif: 'Contrôle de refus sans identité',
    });
    expect(error).toBeNull();
    expect(data).toEqual({ success: false, error: 'Non authentifié' });
  });
});
