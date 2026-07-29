/**
 * weekly-invoicing-cron — Facturation hebdomadaire libérale automatique
 *
 * Déclenchée quotidiennement à 6h Europe/Paris par pg_cron.
 * Appelle fn_lister_missions_a_facturer() pour obtenir la liste des missions
 * à facturer (finales + hebdo), puis invoque generate-invoice pour chacune
 * avec les périodes appropriées. 3 retries max par mission en cas d'échec.
 *
 * AUTH : secret d'automatisation dédié Vault (verify_jwt = false), puis appel
 * interne à generate-invoice avec service_role_reason=cron_auto_generation.
 *
 * Idempotence : la contrainte unique partielle sur factures_honoraires
 * (mission_id, annee_iso, numero_semaine_iso, type_document) WHERE
 * est_facture_finale_mission = false empêche les doublons hebdo.
 * La vérification anti-doublon dans generate-invoice bloque aussi
 * les finales en double. Le cron peut donc tourner 2x sans risque.
 */

import { createClient } from 'npm:@supabase/supabase-js@2';
import {
  cronAuthErrorResponse,
  cronAuthProbeResponse,
  isCronAuthProbe,
  verifyCronServiceAuth,
} from '../_shared/cron-service-auth.ts';

const MAX_RETRIES = 3;
const RETRY_DELAY_MS = 2000;

function sleep(ms: number) { return new Promise(r => setTimeout(r, ms)); }

Deno.serve(async (req: Request) => {
  const corsHeaders = {
    'Access-Control-Allow-Origin': '*',
    'Access-Control-Allow-Headers': 'authorization, x-client-info, apikey, content-type',
    'Content-Type': 'application/json',
  };
  if (req.method === 'OPTIONS') return new Response('ok', { headers: corsHeaders });

  try {
    const supabaseUrl = Deno.env.get('SUPABASE_URL')!;
    const serviceRoleKey = Deno.env.get('SUPABASE_SERVICE_ROLE_KEY')!;
    const supabase = createClient(supabaseUrl, serviceRoleKey, { auth: { persistSession: false } });

    const auth = await verifyCronServiceAuth(req, supabase);
    if (!auth.ok) return cronAuthErrorResponse(auth, corsHeaders);
    if (isCronAuthProbe(req)) return cronAuthProbeResponse(auth);

    // 1. Obtenir la liste des missions à facturer
    const { data: liste, error: listeErr } = await supabase.rpc('fn_lister_missions_a_facturer');
    if (listeErr) {
      console.error('[weekly-invoicing-cron] Erreur liste:', listeErr);
      return new Response(JSON.stringify({ error: listeErr.message }), { status: 500, headers: corsHeaders });
    }

    const finales: any[] = (liste as any)?.finales || [];
    const hebdo: any[] = (liste as any)?.hebdo || [];
    const all = [...finales, ...hebdo];

    console.log(`[weekly-invoicing-cron] ${all.length} missions à facturer (${finales.length} finales, ${hebdo.length} hebdo)`);

    if (all.length === 0) {
      return new Response(JSON.stringify({ success: true, total: 0, message: 'Rien à facturer' }), { headers: corsHeaders });
    }

    // 2. Itérer et invoquer generate-invoice pour chaque entrée
    const results: any[] = [];
    for (const entry of all) {
      let lastError: string | null = null;
      let success = false;

      const { data: missionReelle, error: missionReelleError } =
        await supabase.rpc('fn_mission_est_reelle_pour_service', {
          p_mission_id: entry.mission_id,
        });
      if (missionReelleError) {
        results.push({
          mission_id: entry.mission_id,
          mode: entry.mode,
          success: false,
          skipped: false,
          error: `test_account_filter_unavailable: ${missionReelleError.message}`,
        });
        continue;
      }
      if (missionReelle !== true) {
        results.push({
          mission_id: entry.mission_id,
          mode: entry.mode,
          success: false,
          skipped: true,
          reason: 'test_account',
        });
        continue;
      }

      for (let attempt = 1; attempt <= MAX_RETRIES; attempt++) {
        try {
          const invoiceBody: any = {
            mission_id: entry.mission_id,
            service_role_reason: 'cron_auto_generation',
          };

          // Mode hebdo : ajouter les params période
          if (entry.mode === 'HEBDO') {
            invoiceBody.periode_debut = entry.periode_debut;
            invoiceBody.periode_fin = entry.periode_fin;
            invoiceBody.numero_semaine_iso = entry.numero_semaine_iso;
            invoiceBody.annee_iso = entry.annee_iso;
            invoiceBody.est_facture_finale_mission = false;
          } else if (entry.mode === 'FINALE' && entry.strategie_facturation === 'HEBDO_ET_FINALE') {
            // Facture finale partielle d'une mission HEBDO_ET_FINALE
            invoiceBody.periode_debut = entry.periode_debut;
            invoiceBody.periode_fin = entry.periode_fin;
            invoiceBody.est_facture_finale_mission = true;
          }
          // Mode FINALE + FINALE_UNIQUE : pas de période (comportement existant)

          const { data, error } = await supabase.functions.invoke('generate-invoice', {
            body: invoiceBody,
          });

          if (error) throw new Error(error.message || 'invoke error');
          if (data?.error) {
            // 409 = doublon déjà existant (idempotence OK)
            if (data.error.includes('existe déjà')) {
              console.log(`[weekly-invoicing-cron] Doublon OK (idempotent): mission=${entry.mission_id} mode=${entry.mode}`);
              success = true;
              break;
            }
            throw new Error(data.error);
          }
          if (data?.success !== true || !data?.facture_id) {
            throw new Error('generate-invoice a retourné une réponse de succès invalide');
          }

          console.log(`[weekly-invoicing-cron] OK: mission=${entry.mission_id} mode=${entry.mode} facture=${data?.numero_facture}`);
          success = true;
          break;

        } catch (err: any) {
          lastError = err?.message || String(err);
          console.warn(`[weekly-invoicing-cron] Attempt ${attempt}/${MAX_RETRIES} failed: mission=${entry.mission_id} mode=${entry.mode} — ${lastError}`);
          if (attempt < MAX_RETRIES) await sleep(RETRY_DELAY_MS * attempt);
        }
      }

      results.push({
        mission_id: entry.mission_id,
        mode: entry.mode,
        periode_debut: entry.periode_debut,
        periode_fin: entry.periode_fin,
        success,
        error: success ? null : lastError,
        retries: success ? 0 : MAX_RETRIES,
      });

      // Alerte admin si échec définitif après 3 retries
      if (!success) {
        const { error: auditError } = await supabase.from('journaux_audit').insert({
          acteur_id: null,
          type_acteur: 'SYSTEME',
          action: 'ADMIN_ACTION',
          type_ressource: 'mission',
          id_ressource: entry.mission_id,
          details: {
            event: 'WEEKLY_INVOICING_FAIL_DEFINITIF',
            mode: entry.mode,
            periode_debut: entry.periode_debut,
            periode_fin: entry.periode_fin,
            error: lastError,
            retries: MAX_RETRIES,
          },
        });
        if (auditError) {
          console.error('[weekly-invoicing-cron] Audit error:', auditError);
        }
      }
    }

    const failed = results.filter(r => !r.success && !r.skipped).length;
    const summary = {
      success: failed === 0,
      total: all.length,
      ok: results.filter(r => r.success).length,
      skipped: results.filter(r => r.skipped).length,
      failed,
      details: results,
    };

    console.log(
      `[weekly-invoicing-cron] Terminé: ${summary.ok}/${summary.total} OK, ` +
      `${summary.skipped} test ignorée(s), ${summary.failed} échec(s)`,
    );
    return new Response(JSON.stringify(summary), {
      status: summary.success ? 200 : 500,
      headers: corsHeaders,
    });

  } catch (err) {
    console.error('[weekly-invoicing-cron] Fatal error:', err);
    return new Response(JSON.stringify({ error: err instanceof Error ? err.message : 'Erreur interne' }), { status: 500, headers: corsHeaders });
  }
});
