/**
 * chorus-pro-deposit — Dépôt facture commission Jolene sur Chorus Pro
 *
 * Flux :
 * 1. Frontend étab clique "Déposer sur Chorus Pro" sur une facture commission
 * 2. Cette edge function :
 *    - Fetch facture + chorus_pro_config + etab (via RLS via le JWT user)
 *    - Génère Factur-X XML à la volée (générateur partagé)
 *    - OAuth2 PISTE → token
 *    - POST /cpro/factures/v1/deposer/flux avec XML base64
 *    - Update factures.chorus_pro_* avec résultat
 *
 * Action 'statut' : consulte l'API Chorus Pro pour le statut actuel.
 *
 * Mode simulation si PISTE_CLIENT_ID absent.
 *
 * Env vars : voir _shared/piste-client.ts
 */

import { createClient } from 'npm:@supabase/supabase-js@2';
import { getPisteConfig, getAccessToken, deposerFlux, consulterFacture } from '../_shared/piste-client.ts';
import { generateCiiXml } from '../_shared/facturx-builder.ts';
import { verifyUserOrServiceRole } from '../_shared/admin-auth.ts';
import { resolveOperationalTestAccount } from '../_shared/test-account.ts';

function getCorsOrigin(req: Request): string {
  const origin = req.headers.get('origin') || '';
  if (origin === 'https://jolene.app' || origin === 'https://www.jolene.app' || origin === 'http://localhost:5173' || origin === 'http://localhost:8080') return origin;
  return 'https://jolene.app';
}
function corsHeaders(req: Request) {
  return {
    'Access-Control-Allow-Origin': getCorsOrigin(req),
    'Access-Control-Allow-Headers': 'authorization, x-client-info, apikey, content-type, x-supabase-client-platform, x-supabase-client-platform-version, x-supabase-client-runtime, x-supabase-client-runtime-version',
  };
}
function jsonResponse(req: Request, body: unknown, status = 200) {
  return new Response(JSON.stringify(body), {
    status,
    headers: { ...corsHeaders(req), 'Content-Type': 'application/json' },
  });
}

// Jolene identité émetteur commission (constantes, pourraient venir d'une config admin)
const JOLENE_SELLER = {
  name: 'Jolene SAS',
  siret: Deno.env.get('JOLENE_SIRET') ?? '',
  address: Deno.env.get('JOLENE_ADDRESS') ?? '',
  city: Deno.env.get('JOLENE_CITY') ?? '',
  postalCode: Deno.env.get('JOLENE_POSTAL_CODE') ?? '',
  email: Deno.env.get('JOLENE_EMAIL') ?? 'facturation@jolene.app',
};

Deno.serve(async (req) => {
  if (req.method === 'OPTIONS') return new Response(null, { headers: corsHeaders(req) });

  try {
    const authHeader = req.headers.get('Authorization');
    if (!authHeader?.startsWith('Bearer ')) return jsonResponse(req, { error: 'Non autorise' }, 401);

    const supabaseAdmin = createClient(
      Deno.env.get('SUPABASE_URL')!,
      Deno.env.get('SUPABASE_SERVICE_ROLE_KEY')!,
      { auth: { persistSession: false } },
    );
    const auth = await verifyUserOrServiceRole(req);
    if (!auth.ok) return jsonResponse(req, { error: auth.error }, auth.status);
    const { facture_id, action } = await req.json();
    if (!facture_id || !action) return jsonResponse(req, { error: 'facture_id et action requis' }, 400);

    const { data: facture, error: factError } = await supabaseAdmin
      .from('factures')
      .select('id, numero_facture, montant_ht, montant_ttc, montant_tva, taux_tva, statut, chorus_pro_statut, chorus_pro_id, est_secteur_public, etablissement_id, date_emission, date_echeance')
      .eq('id', facture_id).single();
    if (factError || !facture) return jsonResponse(req, { error: 'Facture introuvable' }, 404);
    if (!facture.est_secteur_public) {
      return jsonResponse(req, { error: 'Chorus Pro est reserve aux etablissements publics' }, 400);
    }
    if (!auth.isServiceRole) {
      const supabaseUser = createClient(
        Deno.env.get('SUPABASE_URL')!,
        Deno.env.get('SUPABASE_ANON_KEY')!,
        { global: { headers: { Authorization: authHeader } } },
      );
      const { data: allowed, error: permissionError } = await supabaseUser.rpc(
        'fn_a_permission_etablissement',
        { p_permission: 'paiement', p_etablissement_id: facture.etablissement_id },
      );
      if (permissionError || allowed !== true) {
        return jsonResponse(req, { error: 'Acces interdit' }, 403);
      }
    }

    // `etablissement_id` vient de la facture canonique. La classification est
    // obligatoire avant tout changement de statut et avant tout appel PISTE,
    // pour les actions dépôt comme consultation.
    const classification = await resolveOperationalTestAccount(
      supabaseAdmin,
      facture.etablissement_id,
    );
    if (!classification.ok) {
      return jsonResponse(req, { error: 'Classification du compte indisponible' }, 503);
    }
    if (classification.isTest) {
      return jsonResponse(req, {
        success: true,
        test_skipped: true,
        message: 'Chorus Pro neutralisé pour les données de test.',
      }, 200);
    }

    const { data: chorusConfig } = await supabaseAdmin
      .from('chorus_pro_config').select('*').eq('etablissement_id', facture.etablissement_id).eq('actif', true).maybeSingle();
    const { data: etab } = await supabaseAdmin
      .from('etablissements').select('siret, nom, adresse_rue, adresse_code_postal, adresse_ville').eq('id', facture.etablissement_id).single();

    const pisteConfig = getPisteConfig();
    const isSimulation = !pisteConfig;

    /* ── ACTION: DEPOSER ── */
    if (action === 'deposer') {
      if (!['A_DEPOSER', 'REJETEE'].includes(facture.chorus_pro_statut ?? 'A_DEPOSER')) {
        return jsonResponse(req, { error: `Impossible de deposer : statut actuel ${facture.chorus_pro_statut}` }, 400);
      }

      if (isSimulation) {
        const now = new Date().toISOString();
        const fluxId = `SIM-${Date.now()}`;
        await supabaseAdmin.from('factures').update({
          chorus_pro_statut: 'DEPOSEE',
          chorus_pro_deposee_le: now,
          chorus_pro_date_depot: now,
          chorus_pro_numero_flux: fluxId,
        }).eq('id', facture_id);
        return jsonResponse(req, {
          success: true, simulation: true,
          message: 'Mode simulation : facture marquee comme deposee. Configurez PISTE_CLIENT_ID et PISTE_CLIENT_SECRET pour le mode reel (API PISTE).',
          statut: 'DEPOSEE', numero_flux: fluxId,
        });
      }

      if (!chorusConfig) return jsonResponse(req, { error: 'Configuration Chorus Pro manquante. Allez dans Parametres -> Chorus Pro.' }, 400);
      if (!etab?.siret) return jsonResponse(req, { error: 'SIRET etablissement non renseigne.' }, 400);
      if (!JOLENE_SELLER.siret) return jsonResponse(req, { error: 'JOLENE_SIRET non configure dans les secrets.' }, 500);

      console.log(`[chorus-pro] Depot facture ${facture.numero_facture} (${pisteConfig.isSandbox ? 'SANDBOX' : 'PROD'})`);

      // Génération Factur-X XML à la volée
      const xml = generateCiiXml({
        invoiceNumber: facture.numero_facture,
        issueDate: (facture.date_emission ?? new Date().toISOString()).slice(0, 10),
        dueDate: (facture.date_echeance ?? facture.date_emission ?? new Date().toISOString()).toString().slice(0, 10),
        sellerName: JOLENE_SELLER.name,
        sellerSiret: JOLENE_SELLER.siret,
        sellerAddress: JOLENE_SELLER.address,
        sellerCity: JOLENE_SELLER.city,
        sellerPostalCode: JOLENE_SELLER.postalCode,
        sellerEmail: JOLENE_SELLER.email,
        buyerName: etab.nom ?? '',
        buyerSiret: etab.siret,
        buyerAddress: etab.adresse_rue ?? '',
        buyerCity: etab.adresse_ville ?? '',
        buyerPostalCode: etab.adresse_code_postal ?? '',
        serviceCode: chorusConfig.code_service ?? '',
        description: `Commission Jolene — facture ${facture.numero_facture}`,
        amountHt: Number(facture.montant_ht) || Number(facture.montant_ttc) || 0,
        amountTva: Number(facture.montant_tva) || 0,
        amountTtc: Number(facture.montant_ttc) || 0,
        vatRate: Number(facture.taux_tva) || 20,
        vatExempt: false,
      });

      // Base64 encode (UTF-8 safe)
      const xmlBase64 = btoa(unescape(encodeURIComponent(xml)));

      const accessToken = await getAccessToken(pisteConfig);
      const result = await deposerFlux(pisteConfig, accessToken, {
        fichierBase64: xmlBase64,
        nomFichier: `${facture.numero_facture}.xml`,
        syntaxeFlux: 'IN_DP_E2_CII_FACTURX',
      });

      if (!result.ok) {
        console.error('[chorus-pro] PISTE deposit error:', result.status, result.raw.slice(0, 300));
        return jsonResponse(req, {
          error: `Chorus Pro API erreur ${result.status}: ${result.data?.libelleErreur || result.data?.message || 'voir logs'}`,
          piste_status: result.status,
        }, 502);
      }

      const now = new Date().toISOString();
      await supabaseAdmin.from('factures').update({
        chorus_pro_statut: 'DEPOSEE',
        chorus_pro_deposee_le: now,
        chorus_pro_date_depot: now,
        chorus_pro_numero_flux: result.identifiantFluxDepot ?? null,
        chorus_pro_id: result.data?.identifiantFactureCPP?.toString() ?? null,
      }).eq('id', facture_id);

      console.log(`[chorus-pro] Facture ${facture.numero_facture} deposee - flux ${result.identifiantFluxDepot}`);

      return jsonResponse(req, {
        success: true, simulation: false, sandbox: pisteConfig.isSandbox,
        message: pisteConfig.isSandbox ? 'Facture deposee sur Chorus Pro (bac a sable)' : 'Facture deposee sur Chorus Pro',
        statut: 'DEPOSEE',
        numero_flux: result.identifiantFluxDepot,
        identifiant_cpp: result.data?.identifiantFactureCPP,
      });
    }

    /* ── ACTION: STATUT ── */
    if (action === 'statut') {
      if (isSimulation) {
        return jsonResponse(req, {
          success: true, simulation: true,
          message: 'Mode simulation : statut lu depuis la base de donnees.',
          statut: facture.chorus_pro_statut ?? 'A_DEPOSER',
          numero_facture: facture.numero_facture,
        });
      }
      if (!facture.chorus_pro_id) {
        return jsonResponse(req, {
          success: true, simulation: false,
          statut: facture.chorus_pro_statut ?? 'A_DEPOSER',
          numero_facture: facture.numero_facture,
          message: 'Pas d\'identifiant Chorus Pro - facture non encore deposee.',
        });
      }
      const accessToken = await getAccessToken(pisteConfig);
      const statusResult = await consulterFacture(pisteConfig, accessToken, facture.chorus_pro_id);

      const statutMapping: Record<string, string> = {
        DEPOSEE: 'DEPOSEE', A_RECYCLER: 'REJETEE', REJETEE: 'REJETEE',
        MISE_A_DISPOSITION: 'RECUE', PRISE_EN_COMPTE: 'RECUE',
        MANDATEE: 'MANDATEE', MISE_EN_PAIEMENT: 'PAYEE', COMPTABILISEE: 'PAYEE',
      };
      const nouveauStatut = statutMapping[statusResult.statutFacture ?? ''] || facture.chorus_pro_statut || 'DEPOSEE';

      if (nouveauStatut !== facture.chorus_pro_statut) {
        const updateData: any = { chorus_pro_statut: nouveauStatut };
        if (nouveauStatut === 'MANDATEE' || nouveauStatut === 'PAYEE') {
          updateData.chorus_pro_date_acceptation = statusResult.dateStatut || new Date().toISOString();
        }
        await supabaseAdmin.from('factures').update(updateData).eq('id', facture_id);
      }

      return jsonResponse(req, {
        success: true, simulation: false, sandbox: pisteConfig.isSandbox,
        statut: nouveauStatut,
        statut_chorus: statusResult.statutFacture,
        motif_refus: statusResult.motifRefus,
        numero_facture: facture.numero_facture,
      });
    }

    return jsonResponse(req, { error: `Action inconnue: ${action}` }, 400);
  } catch (err) {
    console.error('chorus-pro-deposit error:', err);
    return jsonResponse(req, { error: err instanceof Error ? err.message : 'Erreur interne' }, 500);
  }
});
