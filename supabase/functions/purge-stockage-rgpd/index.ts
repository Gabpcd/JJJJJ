/**
 * Purge RGPD des fichiers Storage des comptes soignants supprimés (migration 20261128140100, docs/CONFORMITE.md §6).
 *
 * Appelée toutes les heures par le cron jolene_rgpd_purge_stockage (private.fn_lancer_purge_stockage_rgpd, pg_net,
 * en-tête x-jolene-cron-secret). La base possède la file et ne confirme un fichier que s'il a disparu de
 * storage.objects ; cette fonction n'efface que par l'API Storage. Aucun chemin n'est journalisé ni renvoyé.
 */

import { createClient } from 'npm:@supabase/supabase-js@2.99.2';
import {
  cronAuthErrorResponse,
  cronAuthProbeResponse,
  isCronAuthProbe,
  verifyCronServiceAuth,
} from '../_shared/cron-service-auth.ts';
import { type ClientPurge, purgerStockageRgpd } from '../_shared/rgpd-purge-stockage.ts';

const json = (corps: unknown, status = 200) => new Response(JSON.stringify(corps), {
  status,
  headers: { 'Content-Type': 'application/json', 'Cache-Control': 'no-store' },
});

Deno.serve(async (req) => {
  if (req.method !== 'POST') return json({ error: 'Méthode non autorisée' }, 405);

  const url = Deno.env.get('SUPABASE_URL') || '';
  const cle = Deno.env.get('SUPABASE_SERVICE_ROLE_KEY') || '';
  if (!url || !cle) return json({ error: 'Configuration serveur incomplète' }, 500);
  const admin = createClient(url, cle, { auth: { persistSession: false } });

  const auth = await verifyCronServiceAuth(req, admin);
  if (!auth.ok) return cronAuthErrorResponse(auth);
  if (isCronAuthProbe(req)) return cronAuthProbeResponse(auth);

  try {
    const bilan = await purgerStockageRgpd(admin as unknown as ClientPurge);
    // 503 si un fichier reste : la réponse pg_net le montre ; la file et l'alerte à 24 h restent la garantie.
    return json(bilan, bilan.en_echec > 0 ? 503 : 200);
  } catch (erreur) {
    const code = erreur instanceof Error ? erreur.message.slice(0, 80) : 'ERREUR';
    console.error('[purge-stockage-rgpd] purge interrompue', code);
    return json({ error: 'Purge interrompue', code }, 503);
  }
});
