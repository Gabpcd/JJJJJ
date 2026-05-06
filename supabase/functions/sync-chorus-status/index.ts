/**
 * sync-chorus-status — Synchronisation périodique statuts Chorus Pro
 *
 * Cron horaire (ou 2h) qui interroge l'API PISTE pour chaque soumission
 * pending/submitted en base, met à jour le statut local et émet les
 * notifications appropriées selon le nouveau statut.
 *
 * Utilise /cpro/factures/v1/consulter/flux (pas /consulter/facture) car
 * chorus_submissions.piste_request_id stocke le numeroFluxDepot retourné
 * par deposer/flux.
 *
 * Auth : service_role uniquement (invocation cron).
 *
 * Env vars : voir _shared/piste-client.ts
 */

import { createClient } from 'npm:@supabase/supabase-js@2';
import { getPisteConfig, getAccessToken, consulterFlux, consulterCRDetaille } from '../_shared/piste-client.ts';

function json(body: unknown, status = 200) {
  return new Response(JSON.stringify(body), {
    status,
    headers: { 'Content-Type': 'application/json' },
  });
}

/** Auth service_role résiliente : accepte legacy JWT (avec role=service_role)
 *  OU nouveau secret asymétrique sb_secret_… (depuis env ou vault). */
let _vaultSecret: string | null = null;
async function getVaultSecret(sb: any): Promise<string> {
  if (_vaultSecret) return _vaultSecret;
  const env = Deno.env.get('SUPABASE_SECRET_KEY') || Deno.env.get('SB_SECRET_KEY') || '';
  if (env) { _vaultSecret = env; return env; }
  try {
    const { data } = await sb.rpc('fn_lire_secret_cron');
    if (data) { _vaultSecret = data; return data; }
  } catch { /* ignore */ }
  return '';
}

async function verifyServiceRole(authHeader: string | null, sb: any): Promise<{ ok: boolean; error?: string }> {
  if (!authHeader?.startsWith('Bearer ')) return { ok: false, error: 'Authorization Bearer manquant' };
  const token = authHeader.slice(7).trim();

  // Cas 1 : nouveau secret asymétrique (sb_secret_…) — match exact env/vault
  const legacyKey = Deno.env.get('SUPABASE_SERVICE_ROLE_KEY') || '';
  if (legacyKey && token === legacyKey) return { ok: true };
  const vault = await getVaultSecret(sb);
  if (vault && token === vault) return { ok: true };

  // Cas 2 : JWT classique avec role=service_role
  const parts = token.split('.');
  if (parts.length === 3) {
    try {
      const b64 = parts[1].replace(/-/g, '+').replace(/_/g, '/');
      const padded = b64 + '='.repeat((4 - b64.length % 4) % 4);
      const payload = JSON.parse(atob(padded));
      if (payload?.role === 'service_role') return { ok: true };
      return { ok: false, error: `Role '${payload?.role}' non autorisé` };
    } catch (e) {
      return { ok: false, error: `JWT decode error: ${e instanceof Error ? e.message : String(e)}` };
    }
  }
  return { ok: false, error: 'JWT format invalide' };
}

/** Mapping statut Chorus Pro → statut interne chorus_submissions */
function mapChorusStatus(chorusStatut: string | undefined): 'submitted' | 'accepted' | 'rejected' | 'pending' {
  if (!chorusStatut) return 'submitted';
  const map: Record<string, 'submitted' | 'accepted' | 'rejected' | 'pending'> = {
    DEPOSEE: 'submitted',
    A_RECYCLER: 'rejected',
    REJETEE: 'rejected',
    REFUSEE: 'rejected',
    MISE_A_DISPOSITION: 'submitted',
    PRISE_EN_COMPTE: 'submitted',
    MANDATEE: 'accepted',
    MISE_EN_PAIEMENT: 'accepted',
    COMPTABILISEE: 'accepted',
  };
  return map[chorusStatut] ?? 'submitted';
}

/**
 * Émet les notifications appropriées selon le nouveau statut Chorus.
 * Anti-spam : 1 notif par type+ressource par 24h max.
 */
async function emitNotificationsForStatus(
  supabase: any,
  fh: { id: string; soignant_id: string; etablissement_id: string; numero_facture?: string },
  chorusStatut: string,
  motifRefus?: string | null,
): Promise<number> {
  const notifs: { type: string; dest_id: string; dest_type: 'SOIGNANT' | 'ETABLISSEMENT' | 'ADMIN'; titre: string; corps: string; lien: string }[] = [];
  const ref = fh.numero_facture ? `#${fh.numero_facture}` : '';

  switch (chorusStatut) {
    case 'DEPOSEE':
      notifs.push({
        type: 'CHORUS_DEPOSEE',
        dest_id: fh.soignant_id,
        dest_type: 'SOIGNANT',
        titre: 'Facture déposée sur Chorus Pro',
        corps: `Votre facture ${ref} a été déposée à Chorus Pro. En attente de mise à disposition par l'établissement.`,
        lien: '/soignant/mes-factures',
      });
      break;

    case 'MISE_A_DISPOSITION':
    case 'PRISE_EN_COMPTE':
      notifs.push({
        type: 'CHORUS_MISE_A_DISPOSITION',
        dest_id: fh.etablissement_id,
        dest_type: 'ETABLISSEMENT',
        titre: 'Facture disponible sur Chorus Pro',
        corps: `Une facture ${ref} est mise à disposition dans votre espace Chorus Pro. Pensez à valider son traitement.`,
        lien: '/etablissement/facturation',
      });
      break;

    case 'MANDATEE':
    case 'MISE_EN_PAIEMENT':
      notifs.push({
        type: 'CHORUS_PAIEMENT_EN_COURS',
        dest_id: fh.soignant_id,
        dest_type: 'SOIGNANT',
        titre: 'Paiement en circuit',
        corps: `Votre facture ${ref} a été mise en paiement par l'établissement via Chorus Pro.`,
        lien: '/soignant/mes-factures',
      });
      break;

    case 'COMPTABILISEE':
      notifs.push({
        type: 'CHORUS_PAIEMENT_COMPTABILISE',
        dest_id: fh.soignant_id,
        dest_type: 'SOIGNANT',
        titre: 'Paiement comptabilisé',
        corps: `Votre facture ${ref} a été comptabilisée par la DGFiP. Le paiement a été effectué.`,
        lien: '/soignant/mes-factures',
      });
      notifs.push({
        type: 'CHORUS_PAIEMENT_COMPTABILISE',
        dest_id: fh.etablissement_id,
        dest_type: 'ETABLISSEMENT',
        titre: 'Paiement comptabilisé',
        corps: `Le paiement de la facture ${ref} a été comptabilisé par la DGFiP.`,
        lien: '/etablissement/facturation',
      });
      break;

    case 'REJETEE':
    case 'A_RECYCLER':
    case 'REFUSEE': {
      const motif = motifRefus ? ` Motif : ${motifRefus}` : '';
      notifs.push({
        type: 'CHORUS_REJETEE',
        dest_id: fh.soignant_id,
        dest_type: 'SOIGNANT',
        titre: '⚠️ Facture rejetée par Chorus Pro',
        corps: `Votre facture ${ref} a été rejetée par Chorus Pro.${motif} Contactez le support.`,
        lien: '/soignant/mes-factures',
      });
      // Admins : tous les admins SaaS
      const { data: admins } = await supabase
        .from('profiles')
        .select('id')
        .eq('type_utilisateur', 'ADMIN_SAAS');
      for (const admin of (admins ?? [])) {
        notifs.push({
          type: 'CHORUS_REJETEE',
          dest_id: admin.id,
          dest_type: 'ADMIN',
          titre: '⚠️ Facture rejetée Chorus Pro',
          corps: `Facture ${ref} (soignant ${fh.soignant_id.slice(0, 8)}) rejetée.${motif}`,
          lien: '/admin/chorus-submissions',
        });
      }
      break;
    }
  }

  let inserted = 0;
  for (const n of notifs) {
    // Anti-spam : éviter doublon même type + même ressource dans les 24h
    const { data: existing } = await supabase
      .from('notifications')
      .select('id')
      .eq('type', n.type)
      .eq('id_ressource', fh.id)
      .eq('type_ressource', 'facture_honoraire')
      .eq('destinataire_id', n.dest_id)
      .gte('cree_le', new Date(Date.now() - 24 * 3600 * 1000).toISOString())
      .limit(1);

    if (existing && existing.length > 0) continue;

    const { error } = await supabase.from('notifications').insert({
      destinataire_id: n.dest_id,
      type_destinataire: n.dest_type,
      type: n.type,
      titre: n.titre,
      corps: n.corps,
      lien: n.lien,
      type_ressource: 'facture_honoraire',
      id_ressource: fh.id,
    });
    if (!error) inserted++;
    else console.warn('[sync-chorus-status] notif insert error:', error.message);
  }
  return inserted;
}

Deno.serve(async (req) => {
  if (req.method === 'OPTIONS') return new Response(null, { status: 204 });

  const start = Date.now();

  const supabase = createClient(
    Deno.env.get('SUPABASE_URL')!,
    Deno.env.get('SUPABASE_SERVICE_ROLE_KEY')!,
    { auth: { persistSession: false } },
  );

  // Auth (après création du client pour que la vérif puisse lire vault si besoin)
  const auth = await verifyServiceRole(req.headers.get('Authorization'), supabase);
  if (!auth.ok) return json({ error: `Non autorisé : ${auth.error}` }, 401);

  const pisteConfig = getPisteConfig();
  if (!pisteConfig) {
    console.log('[sync-chorus-status] PISTE credentials absents → simulation mode');
    return json({ success: true, mode: 'simulation', synced: 0, reason: 'PISTE credentials not configured' });
  }

  // Fetch submissions à sync
  const { data: submissions, error: fetchErr } = await supabase
    .from('chorus_submissions')
    .select('id, invoice_id, piste_request_id, status, response_raw')
    .in('status', ['pending', 'submitted'])
    .not('piste_request_id', 'is', null)
    .or('last_checked_at.is.null,last_checked_at.lt.' + new Date(Date.now() - 3600 * 1000).toISOString())
    .order('last_checked_at', { ascending: true, nullsFirst: true })
    .limit(50);

  if (fetchErr) {
    console.error('[sync-chorus-status] fetch error:', fetchErr.message);
    return json({ error: `Fetch submissions : ${fetchErr.message}` }, 500);
  }

  if (!submissions || submissions.length === 0) {
    return json({ success: true, synced: 0, message: 'No pending submissions to sync', duration_ms: Date.now() - start });
  }

  // Access token
  let accessToken: string;
  try {
    accessToken = await getAccessToken(pisteConfig);
  } catch (err) {
    console.error('[sync-chorus-status] OAuth error:', err);
    return json({ error: `PISTE OAuth failed : ${err instanceof Error ? err.message : String(err)}` }, 502);
  }

  let updates = 0;
  let errors = 0;
  let notifsEmitted = 0;

  for (const sub of submissions) {
    try {
      const result = await consulterFlux(pisteConfig, accessToken, sub.piste_request_id!);

      if (!result.ok) {
        console.warn(`[sync-chorus-status] PISTE consulter/flux ${sub.piste_request_id} → ${result.status}`);
        await supabase.from('chorus_submissions').update({
          last_checked_at: new Date().toISOString(),
          error_message: `Chorus consultation failed: ${result.status}`,
        }).eq('id', sub.id);
        errors++;
        continue;
      }

      // Parser liste factures (un flux = généralement 1 facture)
      const listeFactures = result.data?.listeFactures ?? result.data?.factures ?? [];
      const factureData = Array.isArray(listeFactures) ? listeFactures[0] : null;
      const chorusStatut = factureData?.statutCourantCode ?? factureData?.statutFacture ?? result.data?.statutFacture;
      const motifRefus = factureData?.motifRefus ?? result.data?.motifRefus ?? null;
      const identifiantFactureCPP = factureData?.identifiantFactureCPP ?? factureData?.identifiantCPP ?? null;

      const newStatus = mapChorusStatus(chorusStatut);
      const hasChanged = sub.status !== newStatus;

      // Update chorus_submissions (toujours last_checked_at ; status si changé)
      const updateData: any = {
        last_checked_at: new Date().toISOString(),
        response_raw: result.data,
      };
      if (hasChanged) updateData.status = newStatus;
      if (['rejected'].includes(newStatus)) {
        let detailMsg = motifRefus ? String(motifRefus) : '';
        try {
          const cr = await consulterCRDetaille(config, token, sub.piste_request_id!);
          if (cr.ok) {
            const dpErrors = (cr.erreurs ?? []).map((e: any) => e.libelleErreurDP ?? e.libelle ?? JSON.stringify(e)).join(' | ');
            const techErrors = (cr.erreursTechniques ?? []).map((e: any) => e.libelleErreur ?? e.libelle ?? JSON.stringify(e)).join(' | ');
            if (dpErrors) detailMsg += (detailMsg ? ' — ' : '') + `DP: ${dpErrors}`;
            if (techErrors) detailMsg += (detailMsg ? ' — ' : '') + `Tech: ${techErrors}`;
          }
        } catch { /* CR detail non bloquant */ }
        if (detailMsg) updateData.error_message = detailMsg.slice(0, 2000);
      }

      await supabase.from('chorus_submissions').update(updateData).eq('id', sub.id);

      if (hasChanged) {
        updates++;

        // Propager sur factures_honoraires + notif
        const { data: fh } = await supabase
          .from('factures_honoraires')
          .select('id, soignant_id, etablissement_id, numero_facture')
          .eq('chorus_submission_id', sub.id)
          .maybeSingle();

        if (fh) {
          await supabase.from('factures_honoraires').update({
            chorus_submission_status: newStatus,
            chorus_last_sync_at: new Date().toISOString(),
          }).eq('id', fh.id);

          if (chorusStatut) {
            const n = await emitNotificationsForStatus(supabase, fh, chorusStatut, motifRefus);
            notifsEmitted += n;
          }
        }
      }
    } catch (err) {
      console.error(`[sync-chorus-status] submission ${sub.id} error:`, err);
      await supabase.from('chorus_submissions').update({
        last_checked_at: new Date().toISOString(),
      }).eq('id', sub.id);
      errors++;
    }
  }

  const duration_ms = Date.now() - start;
  console.log(`[sync-chorus-status] done: synced=${submissions.length}, updates=${updates}, errors=${errors}, notifs=${notifsEmitted}, duration=${duration_ms}ms`);

  return json({
    success: true,
    sandbox: pisteConfig.isSandbox,
    synced: submissions.length,
    updates,
    errors,
    notifs_emitted: notifsEmitted,
    duration_ms,
  });
});
