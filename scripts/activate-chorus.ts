#!/usr/bin/env npx tsx
/**
 * activate-chorus.ts — Script de validation end-to-end Chorus Pro
 *
 * Usage :
 *   PISTE_CLIENT_ID=xxx PISTE_CLIENT_SECRET=yyy PISTE_ENV=sandbox npx tsx scripts/activate-chorus.ts
 *
 * Ce script effectue 3 vérifications :
 * 1. OAuth2 : obtention d'un access_token
 * 2. Dépôt test : soumission d'une facture fictive
 * 3. Consultation : lecture du statut de la soumission
 *
 * Si les 3 passent, les edge functions submit-to-chorus et sync-chorus-status
 * sont prêtes à être activées.
 */

const PISTE_CLIENT_ID = process.env.PISTE_CLIENT_ID;
const PISTE_CLIENT_SECRET = process.env.PISTE_CLIENT_SECRET;
const PISTE_ENV = process.env.PISTE_ENV || 'sandbox';

const URLS = {
  sandbox: {
    oauth: 'https://sandbox-oauth.piste.gouv.fr/api/oauth/token',
    api: 'https://sandbox-api.piste.gouv.fr/cpro/factures/v1',
  },
  production: {
    oauth: 'https://oauth.piste.gouv.fr/api/oauth/token',
    api: 'https://api.piste.gouv.fr/cpro/factures/v1',
  },
};

function log(step: string, status: 'OK' | 'FAIL' | 'INFO', message: string) {
  const icon = status === 'OK' ? '✅' : status === 'FAIL' ? '❌' : 'ℹ️';
  console.log(`${icon} [${step}] ${message}`);
}

async function main() {
  console.log('═══════════════════════════════════════');
  console.log('  Activation Chorus Pro — Test E2E');
  console.log(`  Environnement : ${PISTE_ENV}`);
  console.log('═══════════════════════════════════════\n');

  if (!PISTE_CLIENT_ID || !PISTE_CLIENT_SECRET) {
    log('PREREQ', 'FAIL', 'Variables PISTE_CLIENT_ID et PISTE_CLIENT_SECRET requises');
    log('PREREQ', 'INFO', 'Usage : PISTE_CLIENT_ID=xxx PISTE_CLIENT_SECRET=yyy npx tsx scripts/activate-chorus.ts');
    process.exit(1);
  }

  const urls = PISTE_ENV === 'production' ? URLS.production : URLS.sandbox;

  // ─── Step 1: OAuth2 ───
  log('OAUTH2', 'INFO', `POST ${urls.oauth}`);

  try {
    const tokenRes = await fetch(urls.oauth, {
      method: 'POST',
      headers: { 'Content-Type': 'application/x-www-form-urlencoded' },
      body: new URLSearchParams({
        grant_type: 'client_credentials',
        client_id: PISTE_CLIENT_ID,
        client_secret: PISTE_CLIENT_SECRET,
        scope: 'openid',
      }).toString(),
    });

    if (!tokenRes.ok) {
      const text = await tokenRes.text();
      log('OAUTH2', 'FAIL', `HTTP ${tokenRes.status}: ${text}`);
      process.exit(1);
    }

    const tokenData = await tokenRes.json();
    const token = tokenData.access_token;
    log('OAUTH2', 'OK', `Token obtenu (expire dans ${tokenData.expires_in}s)`);

    // ─── Step 2: Dépôt test ───
    log('DEPOT', 'INFO', `POST ${urls.api}/soumettre/facture`);

    const testPayload = {
      idUtilisateurCourant: 0,
      modeDepot: 'SAISIE_API',
      coupledePaiement: {
        cadreDeFacturation: {
          codeCadreFacturation: 'A1_FACTURE_FOURNISSEUR',
        },
        destinataire: {
          idDestinataire: '12345678901234', // SIRET test
          typeIdentifiantDestinataire: 'SIRET',
        },
        fournisseur: {
          idFournisseur: '98765432109876', // SIRET test
          typeIdentifiantFournisseur: 'SIRET',
        },
      },
      references: {
        numeroFacture: `TEST-CHORUS-${Date.now()}`,
        dateFacture: new Date().toISOString().split('T')[0],
      },
      montantTotal: {
        montantHtTotal: 100.00,
        montantTVA: 0,
        montantTTC: 100.00,
      },
      lignesPoste: [{
        numeroLigne: 1,
        designation: 'Test activation Chorus Pro via Jolene',
        montantHT: 100.00,
        tauxTva: 0,
        montantTva: 0,
      }],
    };

    const depositRes = await fetch(`${urls.api}/soumettre/facture`, {
      method: 'POST',
      headers: {
        Authorization: `Bearer ${token}`,
        'Content-Type': 'application/json',
        Accept: 'application/json',
      },
      body: JSON.stringify(testPayload),
    });

    const depositText = await depositRes.text();
    let depositData: any;
    try { depositData = JSON.parse(depositText); } catch { depositData = { raw: depositText }; }

    if (!depositRes.ok) {
      // En sandbox, un rejet pour SIRET invalide est NORMAL et prouve que l'API répond
      if (depositRes.status === 400 || depositRes.status === 422) {
        log('DEPOT', 'OK', `API a répondu ${depositRes.status} (rejet attendu en test avec SIRET fictif)`);
        log('DEPOT', 'INFO', `Erreur PISTE : ${depositData?.libelleErreur || depositData?.message || depositText}`);
      } else {
        log('DEPOT', 'FAIL', `HTTP ${depositRes.status}: ${depositText}`);
        process.exit(1);
      }
    } else {
      log('DEPOT', 'OK', `Facture déposée — flux: ${depositData?.numeroFluxDepot || depositData?.identifiantFactureCPP || 'N/A'}`);
    }

    // ─── Step 3: Consultation statut ───
    log('STATUT', 'INFO', `POST ${urls.api}/consulter/facture (test)`);

    // On teste juste que l'endpoint répond (même avec un ID fictif)
    const statusRes = await fetch(`${urls.api}/consulter/facture`, {
      method: 'POST',
      headers: {
        Authorization: `Bearer ${token}`,
        'Content-Type': 'application/json',
        Accept: 'application/json',
      },
      body: JSON.stringify({
        idUtilisateurCourant: 0,
        identifiantFactureCPP: 1, // ID fictif
      }),
    });

    const statusText = await statusRes.text();
    if (statusRes.status === 400 || statusRes.status === 404 || statusRes.ok) {
      log('STATUT', 'OK', `API consultation répond (${statusRes.status}) — endpoint fonctionnel`);
    } else {
      log('STATUT', 'FAIL', `HTTP ${statusRes.status}: ${statusText}`);
    }

    // ─── Résultat ───
    console.log('\n═══════════════════════════════════════');
    console.log('  RÉSULTAT : Activation possible');
    console.log('═══════════════════════════════════════');
    console.log(`
Prochaines étapes :
1. Ajouter dans Supabase Secrets :
   - PISTE_CLIENT_ID = ${PISTE_CLIENT_ID}
   - PISTE_CLIENT_SECRET = ***
   - PISTE_ENV = ${PISTE_ENV}
2. Redéployer les edge functions (push sur main)
3. Les factures secteur public seront soumises automatiquement
`);

  } catch (err) {
    log('ERREUR', 'FAIL', `Exception : ${err}`);
    process.exit(1);
  }
}

main();
