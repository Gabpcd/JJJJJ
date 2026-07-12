/**
 * Global setup Playwright — pré-nettoyage de l'état de test.
 *
 * Pourquoi AVANT le run et pas seulement en afterEach : quand un job CI est
 * annulé ou tué en plein vol (matrices superflues annulées, timeout…), les
 * afterEach ne s'exécutent jamais et laissent des missions de test orphelines
 * en prod. Une mission EN_COURS orpheline assignée au soignant test bloque
 * ensuite TOUTES les acceptations des runs suivants (chevauchement / repos
 * 11 h / plafond 48 h) — incident du 12/06/2026, run 27429495070.
 *
 * Chaque run démarre donc sur un état propre, quelle que soit la façon dont
 * le run précédent est mort. Sans clé service_role (run local sans env), le
 * setup se contente d'un avertissement : les tests qui en dépendent géreront.
 */
import { createClient } from '@supabase/supabase-js';

const PREFIXES = ['[playwright-test]%', '[pw-test%'];

/** Tables enfants de missions en FK NO ACTION — ordre de purge obligatoire. */
const ENFANTS_MISSION = [
  'conformite_travail',
  'cotisations_sociales',
  'bulletins_paie',
  'contrats_travail_missions',
  'contrats_mission',
  'rappels_contrat_travail',
  'scans_pointage',
  'presences',
  'codes_secours_mission',
  'qr_codes_mission',
  'messages_mission',
  'conversations',
  'swipes',
  'matching_scores',
  'candidatures',
];

export default async function globalSetup() {
  const url = process.env.SUPABASE_URL || process.env.E2E_SUPABASE_URL;
  const serviceKey = process.env.SUPABASE_SERVICE_ROLE_KEY;
  if (!url || !serviceKey) {
    console.warn('[global-setup] SUPABASE_URL/SERVICE_ROLE_KEY absents — pré-nettoyage sauté.');
    return;
  }

  const admin = createClient(url, serviceKey, { auth: { persistSession: false } });

  // 1. Missions de test orphelines (tous préfixes confondus)
  const orFiltre = PREFIXES.map((p) => `intitule.like.${p}`).join(',');
  const { data: missions, error } = await admin
    .from('missions')
    .select('id')
    .or(orFiltre)
    .limit(500);
  if (error) {
    console.warn('[global-setup] lecture missions impossible :', error.message);
    return;
  }
  const ids = (missions ?? []).map((m: { id: string }) => m.id);
  if (ids.length > 0) {
    // messages_chat est enfant de conversations (FK conversation_id, pas de
    // mission_id direct). Il DOIT être purgé avant conversations, sinon le DELETE
    // conversations échoue (FK) et bloque en cascade la suppression des missions
    // → missions orphelines EN_COURS qui rebloquent les runs suivants (chevauchement).
    const { data: convs } = await admin.from('conversations').select('id').in('mission_id', ids);
    const convIds = (convs ?? []).map((c: { id: string }) => c.id);
    if (convIds.length > 0) {
      const { error: eMc } = await admin.from('messages_chat').delete().in('conversation_id', convIds);
      if (eMc && !/relation .* does not exist/.test(eMc.message)) {
        console.warn('[global-setup] purge messages_chat :', eMc.message);
      }
    }
    for (const table of ENFANTS_MISSION) {
      const { error: e } = await admin.from(table).delete().in('mission_id', ids);
      if (e && !/relation .* does not exist/.test(e.message)) {
        console.warn(`[global-setup] purge ${table} :`, e.message);
      }
    }
    const { error: eM } = await admin.from('missions').delete().in('id', ids);
    if (eM) console.warn('[global-setup] purge missions :', eM.message);
    else console.log(`[global-setup] ${ids.length} mission(s) de test orpheline(s) purgée(s).`);
  }

  // 2. Factures résiduelles du compte TECHNIQUE Playwright. Ce compte est
  //    distinct des comptes de démonstration/review : toutes ses données sont
  //    exclusivement créées par la CI. Une facture EMISE laissée par un run
  //    ancien déclenche légitimement le gel J+15 et fait ensuite échouer toutes
  //    les créations de missions du run suivant. On annule donc uniquement les
  //    factures impayées de ce compte technique, sans toucher aux données démo.
  const { data: etablissementTestIdBrut, error: etablissementError } = await admin.rpc(
    'fn_admin_get_user_id_by_email',
    { p_email: 'playwright-etab@jolene.app' },
  );
  const etablissementTestId = etablissementTestIdBrut as string | null;
  if (etablissementError || !etablissementTestId) {
    throw new Error(
      `[global-setup] compte établissement Playwright introuvable : ${etablissementError?.message || 'aucune ligne'}`,
    );
  }

  const { data: facturesAnnulees, error: facturesError } = await admin
    .from('factures')
    .update({ statut: 'ANNULEE' })
    .eq('etablissement_id', etablissementTestId)
    .eq('statut', 'EMISE')
    .select('id');
  if (facturesError) {
    throw new Error(`[global-setup] neutralisation des factures Playwright impossible : ${facturesError.message}`);
  }
  if ((facturesAnnulees ?? []).length > 0) {
    console.log(`[global-setup] ${(facturesAnnulees ?? []).length} facture(s) technique(s) Playwright annulée(s).`);
  }

  // 3. État volatile du soignant test (quota super-likes du jour, swipes badges
  //    résiduels) — repart de zéro pour les tests de matching.
  const { data: soignant } = await admin
    .from('soignants')
    .select('id')
    .eq('email', 'playwright-soignant@jolene.app')
    .maybeSingle();
  if (soignant?.id) {
    await admin.from('super_swipes_quota').delete().eq('soignant_id', soignant.id);
    await admin.from('swipes').delete().eq('soignant_id', soignant.id);
    await admin.from('badges_soignant').delete().eq('soignant_id', soignant.id);
    await admin.from('streaks_soignant' as never).delete().eq('soignant_id', soignant.id);
  }

  console.log('[global-setup] état de test prêt.');
}
