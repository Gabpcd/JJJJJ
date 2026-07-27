import type { SupabaseClient } from '@supabase/supabase-js';

const EMAIL_ETABLISSEMENT_PLAYWRIGHT = 'playwright-etab@jolene.app';
const SIRET_ETABLISSEMENT_PLAYWRIGHT = '90000000000001';

/**
 * Garantit la présence du compte établissement technique partagé par la CI.
 *
 * Un compte fixe peut disparaître après un run interrompu ou une manipulation
 * de recette. Le setup doit alors le recréer avant le moindre test, sans
 * toucher aux comptes de démonstration ni aux données réelles.
 */
export async function garantirEtablissementPlaywright(
  admin: SupabaseClient,
): Promise<string> {
  const password = process.env.PLAYWRIGHT_TEST_PASSWORD;
  if (!password) {
    throw new Error(
      '[compte-etablissement-playwright] PLAYWRIGHT_TEST_PASSWORD absent',
    );
  }

  const { data: userIdBrut, error: userIdError } = await admin.rpc(
    'fn_admin_get_user_id_by_email',
    { p_email: EMAIL_ETABLISSEMENT_PLAYWRIGHT },
  );
  if (userIdError) {
    throw new Error(
      `[compte-etablissement-playwright] recherche Auth impossible : ${userIdError.message}`,
    );
  }

  let userId = typeof userIdBrut === 'string' ? userIdBrut : null;
  if (!userId) {
    const { data: creation, error: creationError } =
      await admin.auth.admin.createUser({
        email: EMAIL_ETABLISSEMENT_PLAYWRIGHT,
        password,
        email_confirm: true,
        app_metadata: {
          role: 'ADMIN_ETABLISSEMENT',
          is_test_playwright: true,
        },
        user_metadata: {
          role: 'ADMIN_ETABLISSEMENT',
          nom: 'TestEtabPlaywright',
        },
      });
    if (creationError || !creation.user) {
      throw new Error(
        `[compte-etablissement-playwright] création Auth impossible : ${creationError?.message || 'utilisateur absent'}`,
      );
    }
    userId = creation.user.id;
    console.log(
      '[compte-etablissement-playwright] compte Auth technique recréé.',
    );
  } else {
    const { error: synchronisationAuthError } =
      await admin.auth.admin.updateUserById(userId, {
        password,
        email_confirm: true,
        app_metadata: {
          role: 'ADMIN_ETABLISSEMENT',
          is_test_playwright: true,
        },
        user_metadata: {
          role: 'ADMIN_ETABLISSEMENT',
          nom: 'TestEtabPlaywright',
        },
      });
    if (synchronisationAuthError) {
      throw new Error(
        `[compte-etablissement-playwright] synchronisation Auth impossible : ${synchronisationAuthError.message}`,
      );
    }
  }

  const maintenant = new Date().toISOString();
  const { error: etablissementError } = await admin
    .from('etablissements')
    .upsert(
      {
        id: userId,
        nom: 'Clinique Playwright Test',
        siret: SIRET_ETABLISSEMENT_PLAYWRIGHT,
        type: 'CLINIQUE_PRIVEE',
        adresse_rue: '1 rue de Test',
        adresse_ville: 'Paris',
        adresse_code_postal: '75002',
        adresse_departement: '75',
        adresse_lat: 48.8666,
        adresse_lng: 2.3322,
        email_contact: EMAIL_ETABLISSEMENT_PLAYWRIGHT,
        telephone_contact: '+33100000001',
        contrat_service_signe: true,
        contrat_service_signe_le: maintenant,
        rib_s3_key: 'playwright-test/seed/rib-fictif.pdf',
        siret_verifie: true,
        siret_verifie_le: maintenant,
        statut_verification: 'VERIFIE',
        peut_publier_missions: true,
        representant_identite_verifiee: true,
        representant_identite_verifiee_le: maintenant,
        rattachement_methode: 'ADMIN',
        rattachement_verifie: true,
        rattachement_verifie_le: maintenant,
        email_contact_verifie: true,
        email_contact_verifie_le: maintenant,
        onboarding_termine_le: maintenant,
        est_compte_test: true,
        supprime_le: null,
      },
      { onConflict: 'id' },
    );
  if (etablissementError) {
    throw new Error(
      `[compte-etablissement-playwright] profil établissement impossible : ${etablissementError.message}`,
    );
  }

  const { error: membreError } = await admin
    .from('membres_etablissement')
    .upsert(
      {
        etablissement_id: userId,
        user_id: userId,
        role: 'PROPRIETAIRE',
        actif: true,
        accepte_le: maintenant,
      },
      { onConflict: 'etablissement_id,user_id' },
    );
  if (membreError) {
    throw new Error(
      `[compte-etablissement-playwright] propriétaire impossible : ${membreError.message}`,
    );
  }

  return userId;
}
