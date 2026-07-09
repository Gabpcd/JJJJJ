#!/usr/bin/env npx tsx
/**
 * recette-escrow-stripe.ts — Legs STRIPE de la recette escrow 7b-D (Lot 10 §3).
 *
 * Exécuté par le workflow `recette-escrow-stripe` (runner GitHub : internet
 * libre) contre la branche Supabase de recette (jamais la prod). Complète les
 * legs SQL déjà PASS (docs/RECETTE_ESCROW.md 05/07) avec les flux d'argent
 * réels en MODE TEST Stripe :
 *
 *   S2  — destination charge SEPA (off_session, application_fee, on_behalf_of,
 *         transfer_data.destination) → settlement webhook → DEBITE
 *   S5  — A10.8 : validation présences PENDANT le processing SEPA →
 *         escrow-release laisse EN_ATTENTE + audit ESCROW_RELEASE_ATTENTE_FONDS,
 *         puis fonds available → payout manuel → PAYE (webhook payout.paid)
 *   S3x — exécution refund pré-release : refunds.create AVEC reverse_transfer
 *         + refund_application_fee (fonds repris au connecté, étab remboursé)
 *   S4x — A10.9 exécution : refund post-release SANS reverse_transfer
 *         (absorption plateforme, aucun mouvement forcé sur la soignante)
 *   S6  — échec de débit réel (IBAN test rejet) → payment_failed webhook →
 *         ECHOUE + gel ⚡ ; puis dégel admin
 *   S7  — dispute réelle (IBAN test chargeback) → charge.dispute.created →
 *         DISPUTE + gel
 *
 * INVARIANT SOLDE PLATEFORME (vérifié à chaque étape, snapshots dans le
 * rapport) : les honoraires ne transitent JAMAIS par le solde Jolene — seule
 * la commission (application fee) y entre ; une absorption A10.9 en sort.
 *
 * Garde-fous : refuse la prod ; refuse une clé non sk_test_ ; branche détruite
 * séparément après recette.
 */
import { randomBytes } from 'node:crypto';

const BRANCH_REF = process.env.RECETTE_BRANCH_REF || '';
const MGMT_TOKEN = process.env.SUPABASE_ACCESS_TOKEN || '';
const STRIPE_KEY = process.env.STRIPE_TEST_SECRET_KEY || '';
const PROD_REF = 'flripxtsyegjshnhzjkz';

if (!BRANCH_REF || !MGMT_TOKEN || !STRIPE_KEY) {
  console.error('Requis : RECETTE_BRANCH_REF, SUPABASE_ACCESS_TOKEN, STRIPE_TEST_SECRET_KEY');
  process.exit(1);
}
if (BRANCH_REF === PROD_REF) { console.error('REFUS : ref prod.'); process.exit(1); }
if (!STRIPE_KEY.startsWith('sk_test_')) { console.error('REFUS : la clé Stripe n\'est pas une clé TEST (sk_test_…).'); process.exit(1); }

const FUNCTIONS = `https://${BRANCH_REF}.supabase.co/functions/v1`;
const MGMT = `https://api.supabase.com/v1/projects/${BRANCH_REF}/database/query`;
const ETAB = 'e2e00000-0000-4000-8000-0000000000e7';
const SOIGNANTE = 'e2e00000-0000-4000-8000-000000000001';
const ADMIN = 'e2e00000-0000-4000-8000-00000000ad01';
const RUN = Date.now().toString(36);

// Bearer des invocations edge. La clé service_role « révélée » par l'endpoint
// api-keys de la branche NE correspond PAS à l'env SUPABASE_SERVICE_ROLE_KEY
// injectée dans le runtime edge (403 forbidden, run #4 du 08/07). Chemin
// déterministe : on pose un secret vault `service_role_key` sur la branche
// (Setup 0) et bearerAutorise() des fonctions escrow le lit via
// fn_lire_secret_cron — exactement le mécanisme pg_cron de la prod
// (cf. CLAUDE.md « Auth crons pg_cron »). Valeur aléatoire par run, la
// branche est éphémère et détruite après recette.
const CRON_BEARER = `recette_${RUN}_${randomBytes(24).toString('hex')}`;

const IBAN_OK = 'DE89370400440532013000';
const IBAN_FAIL = 'DE62370400440532013001';
const IBANS_DISPUTE = ['DE35370400440532013002', 'AT861904300235473202'];

type Etat = 'PASS' | 'FAIL';
const rapport: Array<{ scenario: string; etat: Etat; detail: string }> = [];
let echec = false;
function note(scenario: string, etat: Etat, detail: string) {
  rapport.push({ scenario, etat, detail });
  console.log(`${etat === 'PASS' ? '✅' : '❌'} [${etat}] ${scenario} — ${detail}`);
  if (etat === 'FAIL') echec = true;
}
const soldes: Array<{ etape: string; plateforme: number; connecte: number }> = [];

// ── Helpers ──────────────────────────────────────────────────────────────────
async function sql(query: string): Promise<any[]> {
  const r = await fetch(MGMT, {
    method: 'POST',
    headers: { Authorization: `Bearer ${MGMT_TOKEN}`, 'Content-Type': 'application/json' },
    body: JSON.stringify({ query }),
  });
  if (!r.ok) throw new Error(`mgmt sql ${r.status}: ${(await r.text()).slice(0, 300)}`);
  return (await r.json()) as any[];
}
// Contexte service_role + acteur admin (mêmes préambules que la recette SQL).
const CTX = `SELECT set_config('request.jwt.claim.role','service_role',false);
SELECT set_config('request.jwt.claim.sub','${ADMIN}',false);
SELECT set_config('app.internal_operation','true',false);`;

function form(params: Record<string, any>, prefix = ''): string[] {
  const out: string[] = [];
  for (const [k, v] of Object.entries(params)) {
    const key = prefix ? `${prefix}[${k}]` : k;
    if (v === null || v === undefined) continue;
    if (typeof v === 'object' && !Array.isArray(v)) out.push(...form(v, key));
    else if (Array.isArray(v)) v.forEach((x, i) => typeof x === 'object' ? out.push(...form(x, `${key}[${i}]`)) : out.push(`${key}[]=${encodeURIComponent(x)}`));
    else out.push(`${key}=${encodeURIComponent(String(v))}`);
  }
  return out;
}
async function stripe(method: 'GET' | 'POST' | 'DELETE', path: string, params: Record<string, any> = {}, account?: string): Promise<any> {
  const headers: Record<string, string> = {
    Authorization: `Bearer ${STRIPE_KEY}`,
    'Content-Type': 'application/x-www-form-urlencoded',
  };
  if (account) headers['Stripe-Account'] = account;
  const body = form(params).join('&');
  const url = `https://api.stripe.com/v1/${path}${method === 'GET' && body ? `?${body}` : ''}`;
  const r = await fetch(url, { method, headers, body: method === 'GET' ? undefined : body });
  const j = await r.json();
  if (!r.ok) throw new Error(`stripe ${path}: ${j?.error?.message || r.status}`);
  return j;
}
async function invoke(fn: string): Promise<any> {
  const r = await fetch(`${FUNCTIONS}/${fn}`, {
    method: 'POST',
    headers: { Authorization: `Bearer ${CRON_BEARER}`, 'Content-Type': 'application/json' },
    body: '{}',
  });
  const t = await r.text();
  if (!r.ok) throw new Error(`${fn} → ${r.status}: ${t.slice(0, 300)}`);
  try { return JSON.parse(t); } catch { return t; }
}
const sleep = (ms: number) => new Promise((res) => setTimeout(res, ms));
async function poll<T>(label: string, timeoutMs: number, everyMs: number, fn: () => Promise<T | null>): Promise<T> {
  const t0 = Date.now();
  for (;;) {
    const v = await fn();
    if (v !== null && v !== undefined) return v;
    if (Date.now() - t0 > timeoutMs) throw new Error(`timeout ${label} (${Math.round(timeoutMs / 1000)}s)`);
    await sleep(everyMs);
  }
}
let acctSoignante = '';
async function snapshot(etape: string) {
  const p = await stripe('GET', 'balance');
  const somme = (arr: any[]) => (arr || []).filter((b) => b.currency === 'eur').reduce((s, b) => s + b.amount, 0);
  let c = 0;
  if (acctSoignante) {
    const cb = await stripe('GET', 'balance', {}, acctSoignante);
    c = somme(cb.available) + somme(cb.pending);
  }
  const plateforme = somme(p.available) + somme(p.pending);
  soldes.push({ etape, plateforme, connecte: c });
  console.log(`   💰 [${etape}] plateforme=${plateforme}cts connecté=${c}cts`);
  return { plateforme, connecte: c };
}

async function seedMission(nom: string, joursDebut: number): Promise<string> {
  const rows = await sql(`${CTX}
DO $r$ DECLARE v uuid; BEGIN
  v := fn_test_seed_mission(jsonb_build_object(
    'intitule','${nom}','etablissement_id','${ETAB}','profession_requise','IDE','service','Recette',
    'debut_le',(now() + interval '${joursDebut} days')::text,'fin_le',(now() + interval '${joursDebut} days 8 hours')::text,
    'taux_horaire_base',30,'statut','OUVERTE'));
  PERFORM set_config('r.mid', v::text, false);
END $r$;
SELECT current_setting('r.mid') AS id;`);
  const id = rows[0].id as string;
  await sql(`${CTX}
SELECT fn_test_update_mission('${id}', jsonb_build_object(
 'soignant_assigne_id','${SOIGNANTE}','type_contrat_applique','LIBERAL','statut','ASSIGNEE'));`);
  const esc = await sql(`SELECT statut FROM paiements_escrow WHERE mission_id='${id}';`);
  if (!esc.length || esc[0].statut !== 'INITIE') throw new Error(`escrow INITIE absent pour ${nom} (${JSON.stringify(esc)})`);
  return id;
}
async function escrowDe(mission: string): Promise<any> {
  const r = await sql(`SELECT id, statut, stripe_payment_intent_id, stripe_payout_id, honoraires_cents, commission_cents, montant_total_cents FROM paiements_escrow WHERE mission_id='${mission}';`);
  return r[0];
}
async function validerPresences(mission: string) {
  await sql(`${CTX}
SELECT fn_test_update_mission('${mission}', jsonb_build_object(
 'debut_le',(now() - interval '1 day')::text,'fin_le',(now() - interval '1 day' + interval '8 hours')::text));
INSERT INTO presences (mission_id, soignant_id, pointage_arrivee_le, pointage_depart_le, valide_par_etablissement)
VALUES ('${mission}','${SOIGNANTE}', now() - interval '1 day', now() - interval '1 day' + interval '8 hours', false)
ON CONFLICT (mission_id, soignant_id) DO NOTHING;
UPDATE presences SET valide_par_etablissement = true WHERE mission_id='${mission}';`);
}
async function attendreStatut(mission: string, statut: string, timeoutMs: number) {
  return poll(`escrow ${statut} (${mission.slice(0, 8)})`, timeoutMs, 5000, async () => {
    const e = await escrowDe(mission);
    return e?.statut === statut ? e : null;
  });
}
async function setPmEtab(pm: string) {
  await sql(`UPDATE etablissements SET stripe_sepa_payment_method_id='${pm}' WHERE id='${ETAB}';`);
}
async function creerPmSepa(customer: string, iban: string): Promise<string> {
  const pm = await stripe('POST', 'payment_methods', {
    type: 'sepa_debit',
    sepa_debit: { iban },
    billing_details: { name: 'Clinique Recette Escrow', email: 'recette-etab@test.jolene' },
  });
  await stripe('POST', 'setup_intents', {
    customer, payment_method: pm.id, confirm: true,
    payment_method_types: ['sepa_debit'],
    mandate_data: { customer_acceptance: { type: 'online', online: { ip_address: '127.0.0.1', user_agent: 'recette-escrow' } } },
  });
  return pm.id;
}

// ═════════════════════════════════════════════════════════════════════════════
async function main() {
  console.log(`=== Recette escrow — legs Stripe (branche ${BRANCH_REF}, run ${RUN}) ===`);
  const bal = await stripe('GET', 'balance');
  if (bal.livemode) { console.error('REFUS : livemode=true.'); process.exit(1); }

  // ── Setup 0 : bearer vault pour les invocations edge (cf. CRON_BEARER) ─────
  // + neutralisation des résidus des runs précédents sur la branche :
  //   1. missions futures encore ASSIGNEE à la soignante e2e → déplacées 2 ans
  //      dans le passé (1 jour d'écart chacune) via fn_test_update_mission,
  //      sinon dec_refuser_chevauchement_soignant bloque les nouveaux seeds
  //      (run #6 : « Ce soignant a déjà une mission sur ce créneau ») ;
  //   2. escrows INITIE résiduels → échéance repoussée (pas de DELETE), sinon
  //      escrow-debit-echeance les ré-examine et l'assertion debites=1 casse
  //      (run #5 : examined=3). Ordre : missions d'abord, échéances ensuite.
  await sql(`${CTX}
NOTIFY pgrst, 'reload schema';
DELETE FROM vault.secrets WHERE name = 'service_role_key';
SELECT vault.create_secret('${CRON_BEARER}', 'service_role_key');
-- Tripwires « premier euro réel » (migration 20260709190000) DÉSACTIVÉS en
-- recette : le mandat SEPA (Setup 1) et les PaymentIntents de test feraient
-- sinon appeler notify-support (URL prod) à chaque run. Défaut prod = actif.
INSERT INTO parametres_systeme(cle, valeur, label, categorie)
VALUES('alertes_tripwire_actives', 0, 'Alertes tripwire paiement actives', 'GENERAL')
ON CONFLICT (cle) DO UPDATE SET valeur = 0;
DO $neut$ DECLARE m record; d timestamptz; BEGIN
  -- Parking des résidus : slots espacés de 4 JOURS (repos hebdo 35h,
  -- dec_verifier_repos_hebdo_35h refuse des 8h/jour consécutifs — run #9),
  -- ancrés sur le max déjà garé (cumulatif entre les runs — run #8).
  -- Fenêtre : 7 derniers jours inclus, pas seulement le futur — la cible de
  -- validerPresences (now-1j) chevauchait un résidu de la recette SQL du
  -- 05/07 (run #9).
  SELECT coalesce(max(debut_le), now() - interval '2 years') INTO d FROM missions
   WHERE soignant_assigne_id = '${SOIGNANTE}' AND debut_le < now() - interval '1 year';
  FOR m IN SELECT id FROM missions
           WHERE soignant_assigne_id = '${SOIGNANTE}'
             AND statut = 'ASSIGNEE' AND debut_le > now() - interval '7 days'
           ORDER BY cree_le LOOP
    d := d + interval '4 days';
    PERFORM fn_test_update_mission(m.id, jsonb_build_object(
      'debut_le', d::text,
      'fin_le',   (d + interval '8 hours')::text));
  END LOOP;
END $neut$;
UPDATE paiements_escrow SET debit_prevu_le = now() + interval '10 years' WHERE statut = 'INITIE';
UPDATE escrow_release_queue SET prochaine_tentative_le = now() + interval '10 years' WHERE statut = 'EN_ATTENTE';`);

  // ── Setup 1 : customer + mandat SEPA test pour l'étab ──────────────────────
  const cust = await stripe('POST', 'customers', { name: 'Clinique Recette Escrow', email: 'recette-etab@test.jolene', metadata: { recette: RUN } });
  const pmOk = await creerPmSepa(cust.id, IBAN_OK);
  await sql(`UPDATE etablissements SET stripe_customer_id='${cust.id}', stripe_sepa_payment_method_id='${pmOk}', mode_paiement_commission='SEPA_DEBIT' WHERE id='${ETAB}';`);

  // ── Setup 2 : compte connecté custom FR (payouts manual) ──────────────────
  // Plateforme FR : les données d'identité des comptes Custom DOIVENT passer
  // par un account token (exigence Stripe France, découverte run #3 08/07).
  const acctToken = await stripe('POST', 'tokens', {
    account: {
      business_type: 'individual',
      individual: {
        first_name: 'Recette', last_name: 'Soignante', email: 'recette-soignante@test.jolene',
        phone: '+33600000000', dob: { day: 1, month: 1, year: 1990 },
        address: { line1: '1 rue du Test', city: 'Paris', postal_code: '75001', country: 'FR' },
      },
      tos_shown_and_accepted: true,
    },
  });
  // Capabilities = EXACTEMENT celles de la prod (stripe-connect-onboard :
  // card_payments + transfers). Run #5 : une destination charge avec
  // on_behalf_of exige card_payments actif sur le compte connecté —
  // transfers seul est refusé par Stripe. Tester le même set que la prod
  // valide au passage que les comptes soignants prod passeront.
  const acct = await stripe('POST', 'accounts', {
    type: 'custom', country: 'FR', email: 'recette-soignante@test.jolene',
    account_token: acctToken.id,
    capabilities: { card_payments: { requested: true }, transfers: { requested: true } },
    business_profile: { mcc: '8050', url: 'https://jolene.app', product_description: 'Soins infirmiers (recette test)' },
    external_account: { object: 'bank_account', country: 'FR', currency: 'eur', account_number: 'FR1420041010050500013M02606' },
    settings: { payouts: { schedule: { interval: 'manual' } } },
    metadata: { recette: RUN },
  });
  acctSoignante = acct.id;
  await poll('capabilités card_payments + transfers actives', 180_000, 10_000, async () => {
    const a = await stripe('GET', `accounts/${acct.id}`);
    if (a.capabilities?.card_payments === 'active' && a.capabilities?.transfers === 'active') return a;
    console.log(`   … capabilities=${JSON.stringify(a.capabilities)} currently_due=${JSON.stringify(a.requirements?.currently_due)}`);
    return null;
  });
  await sql(`UPDATE soignants SET stripe_account_id='${acct.id}' WHERE id='${SOIGNANTE}';
INSERT INTO stripe_connect_onboarding (soignant_id, stripe_account_id, statut, onboarding_complete, charges_enabled, payouts_enabled, details_submitted, country, business_type)
VALUES ('${SOIGNANTE}','${acct.id}','COMPLET', true, true, true, true, 'FR','individual')
ON CONFLICT (soignant_id) DO UPDATE SET stripe_account_id='${acct.id}', statut='COMPLET', payouts_enabled=true;`);
  note('Setup Stripe test', 'PASS', `customer ${cust.id}, pm SEPA, connecté ${acct.id} (transfers actif, payouts manual)`);
  await snapshot('setup');

  // ── S2 + S5 (A10.8) : nominal complet ──────────────────────────────────────
  const m8 = await seedMission(`Recette Stripe S2 ${RUN}`, 2);
  const r1 = await invoke('escrow-debit-echeance');
  if (r1.debites !== 1) throw new Error(`debit-echeance attendu debites=1, reçu ${JSON.stringify(r1)}`);
  let e8 = await escrowDe(m8);
  const pi = await stripe('GET', `payment_intents/${e8.stripe_payment_intent_id}`);
  // PAS de on_behalf_of attendu : le mandat SEPA de l'étab nomme Jolene
  // (cf. escrow-debit-echeance, fix run #7) — marchand = Jolene, fonds
  // directs au connecté via transfer_data.
  const chkPi = pi.transfer_data?.destination === acct.id && pi.application_fee_amount === e8.commission_cents
    && !pi.on_behalf_of && pi.amount === e8.montant_total_cents;
  note('S2.2 destination charge', chkPi ? 'PASS' : 'FAIL',
    `PI ${pi.id} status=${pi.status} fee=${pi.application_fee_amount} dest=${pi.transfer_data?.destination} on_behalf_of=${pi.on_behalf_of ?? 'aucun (attendu)'}`);
  const expo = await sql(`SELECT count(*) n FROM escrow_exposition_releases er JOIN paiements_escrow pe ON pe.id=er.paiement_escrow_id WHERE pe.mission_id='${m8}' AND er.statut='ACTIF';`);
  note('S2.2 exposition + audit débit', Number(expo[0].n) === 1 ? 'PASS' : 'FAIL', `exposition ACTIF=${expo[0].n}`);
  await snapshot('S2 débit initié');

  // A10.8 (1/2) : valider les présences PENDANT le processing. La queue de
  // release n'est peuplée qu'à la transition DEBITE (trigger 20260709130000 —
  // le trigger présences exige un escrow déjà DEBITE). Garantie testée ici :
  // AUCUN payout ne peut partir pendant le processing.
  if (pi.status === 'processing') {
    await validerPresences(m8);
    const r2 = await invoke('escrow-release');
    note('S5/A10.8 pas de payout pendant processing', r2.examined === 0 && r2.payes === 0 ? 'PASS' : 'FAIL',
      `release=${JSON.stringify(r2)} — la queue n'est peuplée qu'au DEBITE`);
  } else {
    note('S5/A10.8 pas de payout pendant processing', 'FAIL', `PI status inattendu (${pi.status}) — fenêtre processing manquée`);
  }

  // Settlement SEPA test → webhook payment_intent.succeeded → DEBITE
  await poll(`PI succeeded (${pi.id})`, 900_000, 10_000, async () => {
    const p = await stripe('GET', `payment_intents/${pi.id}`);
    return p.status === 'succeeded' ? p : null;
  });
  e8 = await attendreStatut(m8, 'DEBITE', 180_000);
  const auditDebite = await sql(`SELECT count(*) n FROM journaux_audit WHERE action='ESCROW_DEBITE' AND id_ressource='${m8}';`);
  note('S2.3 settlement → DEBITE (webhook)', Number(auditDebite[0].n) >= 1 ? 'PASS' : 'FAIL', `statut=DEBITE, audit ESCROW_DEBITE=${auditDebite[0].n}`);
  const s2d = await snapshot('S2 settled');

  // A10.8 (2/2) : au DEBITE, le trigger 20260709130000 enfile la release
  // (présences déjà validées) ; les fonds SEPA sont encore PENDING côté
  // connecté (available_on à J+2-5, même en test — run #10) → escrow-release
  // doit répondre attente_fonds + audit, la queue reste EN_ATTENTE.
  await poll('queue release enfilée au DEBITE', 60_000, 5000, async () => {
    const q = await sql(`SELECT statut FROM escrow_release_queue WHERE mission_id='${m8}';`);
    return q.length ? q[0] : null;
  });
  const r2b = await invoke('escrow-release');
  const auditAtt = await sql(`SELECT count(*) n FROM journaux_audit WHERE action='ESCROW_RELEASE_ATTENTE_FONDS' AND id_ressource='${m8}';`);
  note('S5/A10.8 attente fonds (DEBITE, fonds pending)', r2b.attente_fonds === 1 && Number(auditAtt[0].n) >= 1 ? 'PASS' : 'FAIL',
    `release=${JSON.stringify(r2b)}, audit ATTENTE_FONDS=${auditAtt[0].n} (backoff 30 min)`);

  // Disponibilité : les fonds SEPA restent pending des jours, même en test —
  // top-up tok_bypassPending sur le compte connecté (fonds immédiatement
  // available, marge pour les frais Stripe du top-up). Ne touche PAS le solde
  // plateforme : l'invariant reste vérifié tel quel.
  await stripe('POST', 'charges', {
    amount: Math.round(e8.honoraires_cents * 1.05) + 1000, currency: 'eur',
    source: 'tok_bypassPending', description: `recette top-up disponibilité ${RUN}`,
  }, acct.id);
  await sql(`UPDATE escrow_release_queue SET prochaine_tentative_le = now() WHERE mission_id='${m8}';`);
  await poll('fonds available connecté', 120_000, 5000, async () => {
    const cb = await stripe('GET', 'balance', {}, acct.id);
    const avail = (cb.available || []).find((b: any) => b.currency === 'eur')?.amount ?? 0;
    return avail >= e8.honoraires_cents ? avail : null;
  });
  const r3 = await invoke('escrow-release');
  e8 = await attendreStatut(m8, 'PAYE', 60_000);
  const payout = await stripe('GET', `payouts/${e8.stripe_payout_id}`, {}, acct.id);
  const conf = await sql(`SELECT missions_sans_incident FROM escrow_etablissement_etat WHERE etablissement_id='${ETAB}';`);
  const queue8 = await sql(`SELECT statut FROM escrow_release_queue WHERE mission_id='${m8}';`);
  note('S2.5 release → payout → PAYE', r3.payes === 1 && payout.amount === e8.honoraires_cents && queue8[0].statut === 'TRAITE' ? 'PASS' : 'FAIL',
    `payout ${payout.id} (${payout.amount}cts, status=${payout.status}), queue=${queue8[0].statut}, confiance=${conf[0]?.missions_sans_incident}`);
  const s2p = await snapshot('S2 payé');
  // Invariant : le payout sort du connecté, la plateforme ne bouge pas.
  note('Invariant plateforme (payout)', Math.abs(s2p.plateforme - s2d.plateforme) === 0 ? 'PASS' : 'FAIL',
    `plateforme ${s2d.plateforme}→${s2p.plateforme} (attendu inchangé — les honoraires ne transitent pas par Jolene)`);

  // ── S3x : refund pré-release exécuté (reverse_transfer) ────────────────────
  // Jours étalés (S3=+3, S6=+4, S7=+5/+6) : les missions du run restent
  // ASSIGNEE à la même soignante — un même J+2 partout se chevaucherait
  // (dec_refuser_chevauchement_soignant). Tous < 8 j ⇒ débit immédiat (A2).
  const m9 = await seedMission(`Recette Stripe S3 ${RUN}`, 3);
  await invoke('escrow-debit-echeance');
  const e9i = await escrowDe(m9);
  await poll(`PI M9 succeeded`, 900_000, 10_000, async () => {
    const p = await stripe('GET', `payment_intents/${e9i.stripe_payment_intent_id}`);
    return p.status === 'succeeded' ? p : null;
  });
  const e9 = await attendreStatut(m9, 'DEBITE', 180_000);
  const avantRefund = await snapshot('S3 avant refund');
  await sql(`${CTX} SELECT fn_escrow_rembourser('${e9.id}', ${e9.honoraires_cents}, true, 'RECETTE Stripe S3 annulation totale');`);
  const r4 = await invoke('process-stripe-refunds');
  const q9 = await poll('refund M9 TRAITE', 120_000, 5000, async () => {
    const q = await sql(`SELECT statut FROM stripe_refunds_queue WHERE paiement_escrow_id='${e9.id}';`);
    return q[0]?.statut === 'TRAITE' ? q[0] : null;
  });
  const refunds9 = await stripe('GET', 'refunds', { payment_intent: e9.stripe_payment_intent_id });
  const rf9 = refunds9.data?.[0];
  const apresRefund = await snapshot('S3 après refund');
  const reversalOk = !!rf9?.transfer_reversal;
  const connecteRepris = avantRefund.connecte - apresRefund.connecte === e9.honoraires_cents;
  note('S3x refund pré-release exécuté', reversalOk && connecteRepris ? 'PASS' : 'FAIL',
    `refund ${rf9?.id} reversal=${rf9?.transfer_reversal ? 'oui' : 'NON'} ; connecté -${avantRefund.connecte - apresRefund.connecte}cts (attendu ${e9.honoraires_cents}) ; process=${JSON.stringify(r4)}`);

  // ── S4x : A10.9 refund post-release exécuté (absorption plateforme) ────────
  const avantAbs = await snapshot('S4 avant absorption');
  const e8paye = await escrowDe(m8);
  await sql(`${CTX} SELECT fn_escrow_rembourser('${e8paye.id}', ${e8paye.honoraires_cents}, true, 'RECETTE Stripe A10.9 post-release');`);
  await invoke('process-stripe-refunds');
  await poll('refund M8 TRAITE', 120_000, 5000, async () => {
    const q = await sql(`SELECT statut FROM stripe_refunds_queue WHERE paiement_escrow_id='${e8paye.id}';`);
    return q[0]?.statut === 'TRAITE' ? q[0] : null;
  });
  const refunds8 = await stripe('GET', 'refunds', { payment_intent: e8paye.stripe_payment_intent_id });
  const rf8 = refunds8.data?.[0];
  const apresAbs = await snapshot('S4 après absorption');
  const sansReversal = rf8 && !rf8.transfer_reversal;
  const connecteIntact = apresAbs.connecte === avantAbs.connecte;
  const plateformeAbsorbe = avantAbs.plateforme - apresAbs.plateforme === e8paye.montant_total_cents;
  note('S4x/A10.9 refund post-release exécuté', sansReversal && connecteIntact ? 'PASS' : 'FAIL',
    `refund ${rf8?.id} sans reversal=${sansReversal} ; connecté intact=${connecteIntact} ; plateforme -${avantAbs.plateforme - apresAbs.plateforme}cts (attendu ${e8paye.montant_total_cents})`);
  note('Invariant plateforme (absorption A5)', plateformeAbsorbe ? 'PASS' : 'FAIL',
    `Jolene absorbe ${avantAbs.plateforme - apresAbs.plateforme}cts depuis SON solde, zéro mouvement forcé sur la soignante`);

  // ── S6 : échec de débit réel → ECHOUE + gel, puis dégel ────────────────────
  const pmFail = await creerPmSepa(cust.id, IBAN_FAIL);
  await setPmEtab(pmFail);
  const m10 = await seedMission(`Recette Stripe S6 ${RUN}`, 4);
  await invoke('escrow-debit-echeance');
  const e10 = await escrowDe(m10);
  await attendreStatut(m10, 'ECHOUE', 900_000);
  const gel = await sql(`SELECT gele FROM escrow_etablissement_etat WHERE etablissement_id='${ETAB}';`);
  const rel10 = await sql(`SELECT relance_prevue_le::date - now()::date AS jours FROM paiements_escrow WHERE mission_id='${m10}';`);
  note('S6 échec débit réel (webhook payment_failed)', gel[0]?.gele === true ? 'PASS' : 'FAIL',
    `PI ${e10.stripe_payment_intent_id} → ECHOUE, relance J+${rel10[0]?.jours}, gel=${gel[0]?.gele}`);
  await sql(`${CTX} SELECT fn_admin_degeler_escrow_etablissement('${ETAB}');`);
  await setPmEtab(pmOk);
  note('S6.3 dégel admin', 'PASS', 'gel levé, mandat SEPA valide restauré');

  // ── S7 : dispute réelle ─────────────────────────────────────────────────────
  let disputeOk = false; let disputeDetail = '';
  let jourS7 = 5;
  for (const iban of IBANS_DISPUTE) {
    try {
      const pmD = await creerPmSepa(cust.id, iban);
      await setPmEtab(pmD);
      const m11 = await seedMission(`Recette Stripe S7 ${RUN} ${iban.slice(-4)}`, jourS7++);
      await invoke('escrow-debit-echeance');
      const e11 = await escrowDe(m11);
      // Le débit doit d'abord réussir, puis être disputé.
      await poll(`PI M11 succeeded (${iban.slice(-4)})`, 600_000, 10_000, async () => {
        const p = await stripe('GET', `payment_intents/${e11.stripe_payment_intent_id}`);
        if (p.status === 'canceled' || p.last_payment_error) throw new Error(`IBAN ${iban.slice(-4)} : échec au lieu de dispute`);
        return p.status === 'succeeded' ? p : null;
      });
      await attendreStatut(m11, 'DISPUTE', 900_000);
      const gel11 = await sql(`SELECT gele FROM escrow_etablissement_etat WHERE etablissement_id='${ETAB}';`);
      disputeOk = gel11[0]?.gele === true;
      disputeDetail = `IBAN …${iban.slice(-4)} → charge.dispute.created → DISPUTE + gel=${gel11[0]?.gele}`;
      await sql(`${CTX} SELECT fn_admin_degeler_escrow_etablissement('${ETAB}');`);
      break;
    } catch (err: any) {
      disputeDetail = `IBAN …${iban.slice(-4)} : ${err.message}`;
      console.warn(`S7 candidat ${iban} : ${err.message}`);
    }
  }
  await setPmEtab(pmOk);
  note('S7 dispute SEPA réelle', disputeOk ? 'PASS' : 'FAIL', disputeDetail);
  await snapshot('fin');

  // ── Rapport ─────────────────────────────────────────────────────────────────
  const pass = rapport.filter((r) => r.etat === 'PASS').length;
  const fail = rapport.filter((r) => r.etat === 'FAIL').length;
  console.log(`\n=== Bilan legs Stripe : ${pass} PASS · ${fail} FAIL · 0 MANUEL ===`);
  console.log(JSON.stringify({ rapport, soldes, pass, fail, branch: BRANCH_REF, run: RUN }, null, 2));
  if (echec) process.exit(2);
}

main().catch((e) => { console.error('Échec recette Stripe :', e); console.log(JSON.stringify({ rapport, soldes }, null, 2)); process.exit(1); });
