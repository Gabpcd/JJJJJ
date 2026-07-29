#!/usr/bin/env node

/**
 * Vérification non destructive des identifiants administrateurs.
 *
 * Les secrets restent exclusivement dans l'environnement. Ce script ne crée,
 * ne met à jour et ne réinitialise aucun utilisateur ; il tente seulement une
 * connexion par mot de passe pour chaque Auth user ADMIN_PLATEFORME.
 */
import { createClient } from '@supabase/supabase-js';

const url = process.env.SUPABASE_URL || '';
const publishableKey = process.env.SUPABASE_PUBLISHABLE_KEY
  || process.env.SUPABASE_ANON_KEY
  || '';
const serviceRoleKey = process.env.SUPABASE_SERVICE_ROLE_KEY || '';
const canonicalPassword = process.env.JOLENE_ADMIN_CANONICAL_PASSWORD || '';

if (!url || !publishableKey || !serviceRoleKey || !canonicalPassword) {
  console.error(
    'Variables requises : SUPABASE_URL, SUPABASE_PUBLISHABLE_KEY, '
      + 'SUPABASE_SERVICE_ROLE_KEY, JOLENE_ADMIN_CANONICAL_PASSWORD.',
  );
  process.exit(2);
}

const directoryClient = createClient(url, serviceRoleKey, {
  auth: { autoRefreshToken: false, persistSession: false },
});

async function listPlatformAdmins() {
  const admins = [];
  const perPage = 200;
  for (let page = 1; ; page += 1) {
    const { data, error } = await directoryClient.auth.admin.listUsers({
      page,
      perPage,
    });
    if (error) throw new Error(`Lecture annuaire Auth impossible : ${error.message}`);

    const users = data?.users ?? [];
    admins.push(...users.filter(
      (user) => user.app_metadata?.role === 'ADMIN_PLATEFORME' && user.email,
    ));
    if (users.length < perPage) break;
  }
  return admins;
}

async function verifyPassword(email) {
  const client = createClient(url, publishableKey, {
    auth: { autoRefreshToken: false, persistSession: false },
  });
  const { data, error } = await client.auth.signInWithPassword({
    email,
    password: canonicalPassword,
  });
  if (error || !data.user) {
    return { ok: false, error: error?.message || 'session absente' };
  }
  await client.auth.signOut({ scope: 'local' });
  return { ok: true };
}

async function main() {
  const admins = await listPlatformAdmins();
  if (admins.length === 0) {
    throw new Error('Aucun compte ADMIN_PLATEFORME trouvé.');
  }

  let failed = 0;
  for (const admin of admins) {
    const email = admin.email.toLowerCase();
    const result = await verifyPassword(email);
    if (result.ok) {
      console.log(`OK   ${email}`);
    } else {
      failed += 1;
      console.error(`FAIL ${email} — ${result.error}`);
    }
  }

  if (failed > 0) {
    throw new Error(`${failed} compte(s) administrateur(s) refusent le mot de passe canonique.`);
  }
  console.log(`${admins.length} compte(s) administrateur(s) vérifié(s).`);
}

main().catch((error) => {
  console.error(error instanceof Error ? error.message : 'Vérification impossible.');
  process.exit(1);
});
