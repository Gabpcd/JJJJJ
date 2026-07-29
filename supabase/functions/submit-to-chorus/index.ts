/**
 * submit-to-chorus — Dépôt facture d'honoraires soignant sur Chorus Pro
 *
 * Appelée automatiquement par generate-invoice après génération PDF + XML
 * Factur-X, pour les factures destinées aux établissements secteur public.
 *
 * Flux :
 * 1. Fetch facture_honoraire + soignant + etab + chorus_pro_config
 * 2. Valide etab secteur public + config Chorus active + pdf_s3_key
 * 3. Télécharge PDF Factur-X depuis bucket jolene-documents
 * 4. Encode base64
 * 5. INSERT chorus_submissions préliminaire (status=SUBMITTING)
 * 6. OAuth2 PISTE + deposer/flux avec mode DEPOT_PDF_FACTURX
 * 7. UPDATE chorus_submissions (SUBMITTED / ERROR) + factures_honoraires.chorus_submission_id
 *
 * Mode simulation : si PISTE_CLIENT_ID absent, INSERT placeholder
 * PENDING_CREDENTIALS et retourne success=false avec détail clair.
 *
 * Env vars : voir _shared/piste-client.ts
 */

import { createClient } from 'npm:@supabase/supabase-js@2';
import { getPisteConfig, getAccessToken, deposerFlux } from '../_shared/piste-client.ts';
import { corsHeaders, preflightResponse } from '../_shared/cors.ts';
import { verifyAdminOrServiceRole } from '../_shared/admin-auth.ts';
import { resolveOperationalTestAccount } from '../_shared/test-account.ts';

function json(req: Request, body: unknown, status = 200) {
  return new Response(JSON.stringify(body), {
    status,
    headers: corsHeaders(req),
  });
}

/** Convert ArrayBuffer → base64 (safe for large PDFs, chunked) */
function arrayBufferToBase64(buffer: ArrayBuffer): string {
  const bytes = new Uint8Array(buffer);
  const chunkSize = 8192;
  let binary = '';
  for (let i = 0; i < bytes.length; i += chunkSize) {
    binary += String.fromCharCode(...bytes.subarray(i, Math.min(i + chunkSize, bytes.length)));
  }
  return btoa(binary);
}

Deno.serve(async (req) => {
  if (req.method === 'OPTIONS') return preflightResponse(req);

  // Auth admin OU service_role (appelée en interne par generate-invoice et
  // par admin-invoke, manuellement par les admins depuis /admin/chorus-pro).
  const auth = await verifyAdminOrServiceRole(req);
  if (!auth.ok) return json(req, { error: auth.error }, auth.status);

  const supabaseAdmin = createClient(
    Deno.env.get('SUPABASE_URL')!,
    Deno.env.get('SUPABASE_SERVICE_ROLE_KEY')!,
    { auth: { persistSession: false } },
  );

  let submissionId: string | null = null;

  try {
    const { facture_honoraire_id, type_document } = await req.json();
    if (!facture_honoraire_id) return json(req, { error: 'facture_honoraire_id requis' }, 400);

    // ─── Fetch facture + joins ───
    const { data: fh, error: fhErr } = await supabaseAdmin
      .from('factures_honoraires')
      .select(`
        id, numero_facture, montant_ttc, soignant_id, etablissement_id,
        pdf_s3_key, facturx_xml_url, type_document, chorus_avoir_reference_invoice,
        chorus_submission_id, chorus_submission_status
      `)
      .eq('id', facture_honoraire_id)
      .single();

    if (fhErr || !fh) return json(req, { error: 'Facture honoraire introuvable', detail: fhErr?.message }, 404);

    // La facture canonique lie les deux parties. Cette garde précède toute
    // écriture chorus_submissions, lecture Storage et requête OAuth/PISTE.
    for (const accountId of [fh.soignant_id, fh.etablissement_id]) {
      const classification = await resolveOperationalTestAccount(
        supabaseAdmin,
        accountId,
      );
      if (!classification.ok) {
        return json(req, { error: 'Classification du compte indisponible' }, 503);
      }
      if (classification.isTest) {
        return json(req, {
          accepted: true,
          test_skipped: true,
          message: 'Dépôt Chorus neutralisé pour les données de test.',
        }, 200);
      }
    }

    // Idempotence : ne pas re-soumettre si déjà en cours
    if (fh.chorus_submission_id && ['submitted', 'accepted'].includes(fh.chorus_submission_status ?? '')) {
      return json(req, {
        accepted: true,
        skipped: true,
        reason: `Facture déjà soumise (statut=${fh.chorus_submission_status})`,
        submission_id: fh.chorus_submission_id,
      }, 200);
    }

    const docType: 'FACTURE' | 'AVOIR' = (type_document ?? fh.type_document) === 'AVOIR' ? 'AVOIR' : 'FACTURE';
    const avoirReferenceInvoice = docType === 'AVOIR' ? fh.chorus_avoir_reference_invoice : null;

    // Fetch etab + chorus_pro_config
    const { data: etab } = await supabaseAdmin
      .from('etablissements')
      .select('id, nom, siret, est_secteur_public')
      .eq('id', fh.etablissement_id)
      .single();

    if (!etab?.est_secteur_public) {
      return json(req, {
        error: 'Etablissement non secteur public, Chorus Pro non applicable',
        etablissement_id: fh.etablissement_id,
      }, 400);
    }

    const { data: cpConfig } = await supabaseAdmin
      .from('chorus_pro_config')
      .select('numero_structure, code_service, identifiant_cpro, actif')
      .eq('etablissement_id', fh.etablissement_id)
      .eq('actif', true)
      .maybeSingle();

    if (!cpConfig) {
      return json(req, {
        error: 'Config Chorus Pro inactive ou absente pour cet établissement',
        etablissement_id: fh.etablissement_id,
      }, 400);
    }

    if (!fh.pdf_s3_key) {
      return json(req, {
        error: 'PDF Factur-X manquant (pdf_s3_key null) — régénérer la facture via generate-invoice',
      }, 400);
    }

    // ─── Mode simulation si credentials PISTE absents ───
    const pisteConfig = getPisteConfig();
    if (!pisteConfig) {
      console.log(`[submit-to-chorus] PISTE credentials pending — ${docType} submission deferred (id=${facture_honoraire_id})`);

      const { data: sim, error: simErr } = await supabaseAdmin
        .from('chorus_submissions')
        .insert({
          invoice_id: facture_honoraire_id,
          submission_type: 'DEPOT_PDF_API',
          type_document: docType,
          avoir_reference_invoice: avoirReferenceInvoice,
          status: 'pending_credentials',
          error_message: 'PISTE credentials not configured — submission deferred',
        })
        .select('id')
        .single();

      if (simErr) return json(req, { error: simErr.message }, 500);

      await supabaseAdmin.from('factures_honoraires').update({
        chorus_submission_id: sim!.id,
        chorus_submission_status: 'pending_credentials',
      }).eq('id', facture_honoraire_id);

      return json(req, {
        accepted: true,
        simulation: true,
        status: 'pending_credentials',
        submission_id: sim!.id,
        type_document: docType,
        message: `Soumission Chorus Pro (${docType}) différée — credentials PISTE en attente.`,
      }, 202);
    }

    // ─── Download PDF Factur-X depuis storage ───
    const { data: pdfBlob, error: dlErr } = await supabaseAdmin.storage
      .from('jolene-documents')
      .download(fh.pdf_s3_key);

    if (dlErr || !pdfBlob) {
      return json(req, {
        error: `Impossible de télécharger PDF : ${dlErr?.message ?? 'blob null'}`,
        pdf_s3_key: fh.pdf_s3_key,
      }, 500);
    }

    const pdfBase64 = arrayBufferToBase64(await pdfBlob.arrayBuffer());
    console.log(`[submit-to-chorus] PDF encodé : ${pdfBase64.length} chars base64 (facture ${fh.numero_facture})`);

    // ─── INSERT chorus_submissions préliminaire ───
    const { data: sub, error: subErr } = await supabaseAdmin
      .from('chorus_submissions')
      .insert({
        invoice_id: facture_honoraire_id,
        submission_type: 'DEPOT_PDF_API',
        type_document: docType,
        avoir_reference_invoice: avoirReferenceInvoice,
        status: 'pending',
        submitted_at: new Date().toISOString(),
      })
      .select('id')
      .single();

    if (subErr) return json(req, { error: `INSERT chorus_submissions : ${subErr.message}` }, 500);
    submissionId = sub!.id;

    // ─── Appel PISTE deposer/flux (DEPOT_PDF_FACTURX) ───
    console.log(`[submit-to-chorus] Dépôt ${docType} ${fh.numero_facture} (${pisteConfig.isSandbox ? 'SANDBOX' : 'PROD'})`);
    const accessToken = await getAccessToken(pisteConfig);
    const result = await deposerFlux(pisteConfig, accessToken, {
      fichierBase64: pdfBase64,
      nomFichier: `${fh.numero_facture}.pdf`,
      syntaxeFlux: 'IN_DP_E2_CII_FACTURX',
    });

    if (result.ok) {
      await supabaseAdmin.from('chorus_submissions').update({
        status: 'submitted',
        piste_request_id: result.identifiantFluxDepot ?? result.pisteRequestId ?? null,
        response_raw: result.data,
        last_checked_at: new Date().toISOString(),
      }).eq('id', submissionId);

      await supabaseAdmin.from('factures_honoraires').update({
        chorus_submission_id: submissionId,
        chorus_submission_status: 'submitted',
        chorus_last_sync_at: new Date().toISOString(),
      }).eq('id', facture_honoraire_id);

      console.log(`[submit-to-chorus] OK — flux ${result.identifiantFluxDepot} pour ${fh.numero_facture}`);

      return json(req, {
        success: true,
        simulation: false,
        sandbox: pisteConfig.isSandbox,
        submission_id: submissionId,
        piste_request_id: result.identifiantFluxDepot,
        type_document: docType,
        message: pisteConfig.isSandbox
          ? `${docType} déposée sur Chorus Pro (bac à sable)`
          : `${docType} déposée sur Chorus Pro`,
      }, 200);
    }

    // ─── Erreur API PISTE ───
    console.error('[submit-to-chorus] PISTE error:', result.status, result.raw.slice(0, 300));
    const errMsg = result.data?.libelleErreur
      || result.data?.message
      || result.data?.error_description
      || result.raw.slice(0, 500);

    await supabaseAdmin.from('chorus_submissions').update({
      status: 'error',
      error_code: String(result.status),
      error_message: errMsg.slice(0, 1000),
      response_raw: result.data,
      last_checked_at: new Date().toISOString(),
    }).eq('id', submissionId);

    await supabaseAdmin.from('factures_honoraires').update({
      chorus_submission_id: submissionId,
      chorus_submission_status: 'error',
    }).eq('id', facture_honoraire_id);

    return json(req, {
      success: false,
      error: `Chorus Pro API erreur ${result.status}: ${errMsg}`,
      submission_id: submissionId,
      piste_status: result.status,
    }, 502);

  } catch (err) {
    const errMsg = err instanceof Error ? err.message : String(err);
    console.error('submit-to-chorus error:', errMsg);

    // Si submission déjà créée, la marquer en erreur
    if (submissionId) {
      await supabaseAdmin.from('chorus_submissions').update({
        status: 'error',
        error_message: errMsg.slice(0, 1000),
      }).eq('id', submissionId);
    }

    return json(req, { error: errMsg, submission_id: submissionId }, 500);
  }
});
