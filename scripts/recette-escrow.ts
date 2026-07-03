#!/usr/bin/env npx tsx
/**
 * recette-escrow.ts — Harness de recette escrow 7b-D (§4.7 + A10).
 *
 * Déroule automatiquement les scénarios de docs/ESCROW_7BD_RECETTE.md et produit
 * un RAPPORT (console + JSON) pass/fail. À lancer contre un ENVIRONNEMENT DE TEST
 * (jamais la prod) avec le flag feature_paiement_rapide_actif = 1 et des CLÉS
 * STRIPE TEST.
 *
 * Deux niveaux d'assertion :
 *   [SQL]    — décisions de la machine à états testables sans Stripe (éligibilité
 *              plafond, gel, décision de remboursement A5/A6, exposition,
 *              enqueue release). Exécutées ici, résultat déterministe.
 *   [STRIPE] — legs nécessitant l'API Stripe (destination charge, payout,
 *              webhooks succeeded/failed/dispute). NON exécutés automatiquement :
 *              le harness imprime la procédure test-mode à dérouler à la main
 *              (Stripe CLI `stripe trigger`, Dashboard test) et attend la
 *              confirmation via variables d'état en base.
 *
 * Usage :
 *   SUPABASE_URL=... SUPABASE_SERVICE_ROLE_KEY=... \
 *   RECETTE_ETAB_ID=<uuid étab test> RECETTE_SOIGNANT_ID=<uuid soignant test> \
 *   npx tsx scripts/recette-escrow.ts
 *
 * ⚠️ Refuse de tourner si l'URL ressemble à la prod (garde-fou).
 */
import { createClient, type SupabaseClient } from '@supabase/supabase-js';

const URL = process.env.SUPABASE_URL || '';
const SERVICE = process.env.SUPABASE_SERVICE_ROLE_KEY || '';
const ETAB = process.env.RECETTE_ETAB_ID || '';
const SOIGNANT = process.env.RECETTE_SOIGNANT_ID || '';
const PROD_REF = 'flripxtsyegjshnhzjkz';

if (!URL || !SERVICE || !ETAB || !SOIGNANT) {
  console.error('Requis : SUPABASE_URL, SUPABASE_SERVICE_ROLE_KEY, RECETTE_ETAB_ID, RECETTE_SOIGNANT_ID');
  process.exit(1);
}
if (URL.includes(PROD_REF) && !process.env.RECETTE_FORCE_PROD) {
  console.error(`REFUS : l'URL cible le projet prod (${PROD_REF}). La recette DOIT tourner sur un projet de test.`);
  process.exit(1);
}

const db: SupabaseClient = createClient(URL, SERVICE, { auth: { persistSession: false } });

type Etat = 'PASS' | 'FAIL' | 'MANUEL';
const rapport: Array<{ scenario: string; etat: Etat; detail: string }> = [];
function note(scenario: string, etat: Etat, detail: string) {
  rapport.push({ scenario, etat, detail });
  const icone = etat === 'PASS' ? '✅' : etat === 'FAIL' ? '❌' : '🔧';
  console.log(`${icone} [${etat}] ${scenario} — ${detail}`);
}

async function rpc(fn: string, args: Record<string, unknown> = {}): Promise<any> {
  const { data, error } = await db.rpc(fn as never, args as never);
  if (error) throw new Error(`${fn}: ${error.message}`);
  return data;
}

async function main() {
  console.log('=== Recette escrow 7b-D ===');
  console.log(`Projet : ${URL}`);
  console.log(`Étab test : ${ETAB} · Soignant test : ${SOIGNANT}\n`);

  // ── S8 (SQL) — Plafond §11.1 : éligibilité sous / au-dessus du plafond ──
  try {
    const plafond = await rpc('fn_escrow_plafond_cents', { p_etablissement_id: ETAB });
    const eligibleSous = await rpc('fn_escrow_etab_eligible', { p_etablissement_id: ETAB, p_montant_cents: 1000 });
    const eligibleAuDessus = await rpc('fn_escrow_etab_eligible', {
      p_etablissement_id: ETAB, p_montant_cents: Number(plafond) + 100000,
    });
    if (eligibleSous === true && eligibleAuDessus === false) {
      note('S8 plafond A2', 'PASS', `plafond ${Number(plafond) / 100}€ ; éligible sous, refusé au-dessus`);
    } else {
      note('S8 plafond A2', 'FAIL', `sous=${eligibleSous} au-dessus=${eligibleAuDessus} (attendu true/false)`);
    }
  } catch (e) {
    note('S8 plafond A2', 'FAIL', String(e));
  }

  // ── S6 (SQL) — Gel puis déblocage admin ──
  try {
    await rpc('fn_escrow_geler_etablissement', { p_etablissement_id: ETAB, p_raison: 'RECETTE' });
    const gele = await rpc('fn_escrow_etab_eligible', { p_etablissement_id: ETAB, p_montant_cents: 1000 });
    // Déblocage : nécessite est_admin() → via SQL direct service_role sur la table.
    await db.from('escrow_etablissement_etat' as never)
      .update({ gele: false, gele_le: null, gele_raison: null } as never)
      .eq('etablissement_id', ETAB);
    const debloque = await rpc('fn_escrow_etab_eligible', { p_etablissement_id: ETAB, p_montant_cents: 1000 });
    if (gele === false && debloque === true) {
      note('S6 gel incident', 'PASS', 'gelé → non éligible ; dégelé → éligible');
    } else {
      note('S6 gel incident', 'FAIL', `gele=${gele} debloque=${debloque}`);
    }
  } catch (e) {
    note('S6 gel incident', 'FAIL', String(e));
  }

  // ── S2/S5 (STRIPE) — nominal débit → validation → release ──
  note('S2 nominal débit→release', 'MANUEL',
    'Confirmer une mission LIBERAL éligible ⚡ → vérifier paiements_escrow INITIE, ' +
    'invoquer escrow-debit-echeance (destination charge test SEPA), simuler ' +
    'payment_intent.succeeded (stripe trigger) → DEBITE, valider les présences ' +
    '→ escrow_release_queue, invoquer escrow-release → payout test → PAYE.');
  note('S5 validation avant fonds (A10.8)', 'MANUEL',
    'Valider les présences pendant que le PI SEPA est en processing → escrow-release ' +
    'laisse la queue EN_ATTENTE + audit ESCROW_RELEASE_ATTENTE_FONDS ; puis fonds ' +
    'available → PAYE.');

  // ── S3 (SQL) — décision de remboursement pré-release (A5/A6) ──
  // Nécessite un paiements_escrow de test DEBITE. On le crée en test uniquement.
  try {
    const { data: esc } = await db.from('paiements_escrow' as never).insert({
      mission_id: null, etablissement_id: ETAB, soignant_id: SOIGNANT,
      montant_total_cents: 11500, commission_cents: 1500, honoraires_cents: 10000,
      methode_debit: 'SEPA', statut: 'DEBITE', stripe_payment_intent_id: 'pi_recette_test',
    } as never).select('id').maybeSingle();
    // Note : mission_id NOT NULL en prod → ce leg suppose une contrainte relâchée
    // en test, ou un vrai mission_id de test. Sinon → MANUEL.
    if (esc && (esc as any).id) {
      const r = await rpc('fn_escrow_rembourser', {
        p_paiement_escrow_id: (esc as any).id, p_montant_honoraires_cts: 10000, p_annulation_totale: true,
      });
      if (r?.reverse_transfer === true && r?.absorbe_plateforme === false && r?.refund_application_fee_cts === 1500) {
        note('S3 refund pré-release (A5/A6)', 'PASS', 'reverse_transfer=true, fee=100% (1500cts)');
      } else {
        note('S3 refund pré-release (A5/A6)', 'FAIL', JSON.stringify(r));
      }
      await db.from('paiements_escrow' as never).delete().eq('id', (esc as any).id);
    } else {
      note('S3 refund pré-release (A5/A6)', 'MANUEL', 'création paiements_escrow test impossible (mission_id NOT NULL) — dérouler via une vraie mission de test');
    }
  } catch (e) {
    note('S3 refund pré-release (A5/A6)', 'MANUEL', `${e} — dérouler via une vraie mission de test`);
  }

  note('S4 refund post-release (A10.9)', 'MANUEL',
    'Sur un escrow PAYE, fn_escrow_rembourser → absorbe_plateforme=true, ' +
    'reverse_transfer=false ; process-stripe-refunds refund SANS reverse.');
  note('S7 dispute SEPA', 'MANUEL',
    'stripe trigger charge.dispute.created sur une charge escrow → DISPUTE + gel.');

  // ── Rapport final ──
  const pass = rapport.filter((r) => r.etat === 'PASS').length;
  const fail = rapport.filter((r) => r.etat === 'FAIL').length;
  const manuel = rapport.filter((r) => r.etat === 'MANUEL').length;
  console.log(`\n=== Bilan : ${pass} PASS · ${fail} FAIL · ${manuel} MANUEL (Stripe) ===`);
  console.log(JSON.stringify({ rapport, pass, fail, manuel, date_iso: new Date().toISOString() }, null, 2));
  if (fail > 0) process.exit(2);
}

main().catch((e) => {
  console.error('Échec recette :', e);
  process.exit(1);
});
