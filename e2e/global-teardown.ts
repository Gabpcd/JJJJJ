import { createClient } from '@supabase/supabase-js';
import { nettoyerSessionsPlaywright } from './helpers/nettoyage-sessions-playwright';

/** Libère les sessions Auth techniques créées par le run qui vient de finir. */
export default async function globalTeardown() {
  const url = process.env.SUPABASE_URL || process.env.E2E_SUPABASE_URL;
  const serviceKey = process.env.SUPABASE_SERVICE_ROLE_KEY;
  if (!url || !serviceKey) return;

  const admin = createClient(url, serviceKey, { auth: { persistSession: false } });
  await nettoyerSessionsPlaywright(admin, '0 seconds');
}
