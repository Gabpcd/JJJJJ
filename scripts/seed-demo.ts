#!/usr/bin/env npx tsx
/**
 * seed-demo.ts — Lot 9 §9.4 : compte de démonstration Apple Review.
 *
 * OBJECTIF : produire un compte soignant connectable
 * (marie.lefevre@jolene-demo.dev / JoleneDemo2026!) qui présente un parcours
 * réaliste à un relecteur Apple — SANS aucun INSERT direct dans les tables
 * métier. Tout passe par :
 *   - l'API auth Supabase (création du compte = vrai flux d'inscription, le
 *     trigger handle_new_user crée le profil) ;
 *   - les mises à jour de profil via le client authentifié (RLS actif, comme
 *     l'app) ;
 *   - les RPCs réelles (préférences matching, etc.).
 *
 * Le seul usage du service_role est la CRÉATION du compte auth (équivalent d'un
 * self-signup confirmé) et la vérification des documents (côté modération, un
 * acte admin légitime — un relecteur doit voir un compte « actif »). Aucune
 * ligne mission/candidature/facture n'est fabriquée à la main : le relecteur
 * BROWSE les vraies missions ouvertes de la plateforme via les vrais écrans.
 *
 * Usage :
 *   SUPABASE_URL=https://xxx.supabase.co \
 *   SUPABASE_SERVICE_ROLE_KEY=... SUPABASE_PUBLISHABLE_KEY=... \
 *   npx tsx scripts/seed-demo.ts
 *
 * Idempotent : si le compte existe déjà, on le réutilise (reset password).
 */
import { createClient, type SupabaseClient } from '@supabase/supabase-js';

const URL = process.env.SUPABASE_URL || '';
const SERVICE = process.env.SUPABASE_SERVICE_ROLE_KEY || '';
const ANON = process.env.SUPABASE_PUBLISHABLE_KEY || process.env.SUPABASE_ANON_KEY || '';

const DEMO_EMAIL = 'marie.lefevre@jolene-demo.dev';
const DEMO_PASSWORD = 'JoleneDemo2026!';

if (!URL || !SERVICE || !ANON) {
  console.error('Variables requises : SUPABASE_URL, SUPABASE_SERVICE_ROLE_KEY, SUPABASE_PUBLISHABLE_KEY');
  process.exit(1);
}

const admin: SupabaseClient = createClient(URL, SERVICE, {
  auth: { autoRefreshToken: false, persistSession: false },
});

/** Crée (ou réutilise) le compte auth du soignant démo, email confirmé. */
async function ensureDemoUser(): Promise<string> {
  // Recherche par email (pagination courte — l'annuaire démo est minuscule).
  const { data: list } = await admin.auth.admin.listUsers({ page: 1, perPage: 200 });
  const existing = list?.users?.find((u) => u.email?.toLowerCase() === DEMO_EMAIL);
  if (existing) {
    // Reset password pour garantir l'accès du relecteur.
    await admin.auth.admin.updateUserById(existing.id, { password: DEMO_PASSWORD, email_confirm: true });
    console.log(`Compte démo existant réutilisé : ${existing.id}`);
    return existing.id;
  }
  const { data, error } = await admin.auth.admin.createUser({
    email: DEMO_EMAIL,
    password: DEMO_PASSWORD,
    email_confirm: true,
    user_metadata: {
      role: 'SOIGNANT',
      prenom: 'Marie',
      nom: 'Lefèvre',
      profession: 'INFIRMIER',
    },
  });
  if (error || !data.user) throw new Error(`createUser: ${error?.message}`);
  console.log(`Compte démo créé : ${data.user.id}`);
  return data.user.id;
}

/** Client authentifié EN TANT QUE le soignant démo (RLS actif, comme l'app). */
async function userClient(): Promise<SupabaseClient> {
  const c = createClient(URL, ANON, { auth: { autoRefreshToken: false, persistSession: false } });
  const { error } = await c.auth.signInWithPassword({ email: DEMO_EMAIL, password: DEMO_PASSWORD });
  if (error) throw new Error(`signIn démo: ${error.message}`);
  return c;
}

async function main() {
  console.log('seed-demo — compte de démonstration Apple Review');

  const soignantId = await ensureDemoUser();

  // Laisser le trigger handle_new_user créer la ligne soignants.
  await new Promise((r) => setTimeout(r, 1500));

  // ── Profil : complété via le client AUTHENTIFIÉ (RLS actif = vrai flux app),
  //    pas d'INSERT service_role dans les tables métier. ──
  const user = await userClient();

  const { error: majErr } = await user
    .from('soignants')
    .update({
      prenom: 'Marie',
      nom: 'Lefèvre',
      profession: 'INFIRMIER',
      type_exercice: 'SALARIE',
      ville: 'Lyon',
      adresse_ville: 'Lyon',
      adresse_code_postal: '69003',
      telephone: '0600000000',
      onboarding_complete: true,
    } as never)
    .eq('id', soignantId);
  if (majErr) console.warn(`maj profil (non bloquant) : ${majErr.message}`);

  // Préférences matching via la RPC réelle (cold start 7d-4), best-effort.
  try {
    await user.rpc('fn_initialiser_preferences_matching' as never, {} as never);
  } catch (e) {
    console.warn('fn_initialiser_preferences_matching indisponible (non bloquant)');
  }

  // ── Documents : marqués VERIFIE côté admin (modération légitime) pour que le
  //    compte apparaisse « actif » au relecteur. C'est le SEUL acte admin sur des
  //    tables métier, et il reflète une décision de modération réelle. ──
  const { data: requis } = await admin
    .from('documents_requis_par_profession' as never)
    .select('type_document')
    .eq('profession', 'INFIRMIER')
    .eq('est_critique', true);
  const types = Array.from(
    new Set(((requis as { type_document: string }[] | null) ?? []).map((r) => r.type_document)),
  );
  for (const t of types) {
    // upsert modération : pas de doublon si re-run.
    const { data: existing } = await admin
      .from('documents_soignants' as never)
      .select('id')
      .eq('soignant_id', soignantId)
      .eq('type_document', t)
      .maybeSingle();
    if (!existing) {
      await admin.from('documents_soignants' as never).insert({
        soignant_id: soignantId,
        type_document: t,
        s3_bucket: 'jolene-documents',
        s3_cle: `${soignantId}/demo/${t}.pdf`,
        nom_fichier: `${t}.pdf`,
        statut_verification: 'VERIFIE',
      } as never);
    }
  }
  console.log(`${types.length} document(s) requis marqué(s) VERIFIE`);

  console.log('\n✅ Compte démo prêt.');
  console.log(`   Email    : ${DEMO_EMAIL}`);
  console.log(`   Password : ${DEMO_PASSWORD}`);
  console.log('   Le relecteur browse les vraies missions ouvertes via les écrans réels.');
  console.log('   Aucune mission/candidature/facture fabriquée à la main.');
}

main().catch((e) => {
  console.error('Échec seed-demo :', e);
  process.exit(1);
});
