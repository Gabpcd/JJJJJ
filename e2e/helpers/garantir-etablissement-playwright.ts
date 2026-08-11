import type { SupabaseClient } from '@supabase/supabase-js';

const EMAIL_ETABLISSEMENT_PLAYWRIGHT = 'playwright-etab@jolene.app';
const SIRET_ETABLISSEMENT_PLAYWRIGHT = '90000000000001';

type ErreurAuth = {
  name?: string;
  message?: string;
  status?: number;
  code?: string;
};

const PAUSES_REESSAI_AUTH_MS = [2_000, 5_000] as const;

function diagnosticErreurAuth(error: ErreurAuth): string {
  return JSON.stringify({
    name: error.name || error.constructor?.name || 'ErreurAuthInconnue',
    message: error.message || String(error),
    status: error.status,
    code: error.code,
  });
}

function estErreurAuthTransitoire(error: ErreurAuth): boolean {
  const statut = Number(error.status || 0);
  const message = [error.name, error.message, error.code]
    .filter(Boolean)
    .join(' ')
    .toLowerCase();

  return (
    statut === 0
    || statut === 408
    || statut === 429
    || statut >= 500
    || /^\s*\{\}\s*$/.test(error.message || '')
    || /timeout|timed out|deadline|network|fetch|econn|socket|temporar/.test(message)
  );
}

export async function synchroniserAuthEtablissementPlaywright(
  admin: SupabaseClient,
  userId: string,
  password: string,
  attendre: (ms: number) => Promise<void> = (ms) =>
    new Promise((resolve) => setTimeout(resolve, ms)),
): Promise<void> {
  for (let tentative = 1; tentative <= PAUSES_REESSAI_AUTH_MS.length + 1; tentative += 1) {
    const { error } = await admin.auth.admin.updateUserById(userId, {
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

    if (!error) return;

    const diagnostic = diagnosticErreurAuth(error);
    const pause = PAUSES_REESSAI_AUTH_MS[tentative - 1];
    if (!pause || !estErreurAuthTransitoire(error)) {
      throw new Error(
        `[compte-etablissement-playwright] synchronisation Auth impossible : ${diagnostic}`,
      );
    }

    console.warn(
      `[compte-etablissement-playwright] Auth temporairement indisponible (tentative ${tentative}/3) : ${diagnostic}`,
    );
    await attendre(pause);
  }
}

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
    await synchroniserAuthEtablissementPlaywright(admin, userId, password);
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

  // Le trigger d'insertion choisit normalement SEPA pour une clinique privée.
  // La fixture CI doit au contraire rester en facturation mensuelle : elle
  // franchit le garde-fou d'assignation sans mandat réel et laisse les tests
  // escrow créer eux-mêmes leur état financier de façon déterministe.
  const { error: paiementError } = await admin
    .from('etablissements')
    .update({
      mode_paiement_commission: 'FACTURE_MENSUELLE',
      stripe_customer_id: null,
      stripe_sepa_payment_method_id: null,
    })
    .eq('id', userId)
    .eq('est_compte_test', true);
  if (paiementError) {
    throw new Error(
      `[compte-etablissement-playwright] mode de paiement technique impossible : ${paiementError.message}`,
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
