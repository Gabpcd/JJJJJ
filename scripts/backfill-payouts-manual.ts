#!/usr/bin/env npx tsx
/**
 * backfill-payouts-manual.ts — Escrow 7b-D PR 1 (amendement A7)
 *
 * Bascule les comptes Stripe Connect Express existants en
 * `settings.payouts.schedule.interval = "manual"`, en DRAINANT d'abord le
 * legacy : un compte qui a encore des fonds issus de l'ancien flux (transfers
 * partis en payout automatique pas encore versés) est soldé par un payout
 * manuel AVANT la bascule — sinon ces fonds resteraient bloqués sur le solde
 * connecté jusqu'à la livraison du release escrow (PR 5).
 *
 * Ordre par compte (loggé « soldé → basculé ») :
 *   1. skip si déjà `manual` (idempotent, re-run sûr)
 *   2. balance connectée : si `pending` > 0 → NE PAS basculer (re-run plus tard,
 *      les fonds en settlement ne sont pas payables) ; si `available` > 0 →
 *      payouts.create du montant disponible (drain)
 *   3. accounts.update → schedule manual
 *
 * Usage :
 *   STRIPE_SECRET_KEY=sk_... SUPABASE_URL=https://xxx.supabase.co \
 *   SUPABASE_SERVICE_ROLE_KEY=... npx tsx scripts/backfill-payouts-manual.ts
 *
 * Dry-run par défaut : n'écrit RIEN (ni payout ni update) — affiche ce qui
 * serait fait. Ajouter --apply pour exécuter réellement.
 */

const STRIPE_KEY = process.env.STRIPE_SECRET_KEY;
const SUPABASE_URL = process.env.SUPABASE_URL;
const SERVICE_ROLE = process.env.SUPABASE_SERVICE_ROLE_KEY;
const APPLY = process.argv.includes("--apply");

if (!STRIPE_KEY || !SUPABASE_URL || !SERVICE_ROLE) {
  console.error(
    "Variables requises : STRIPE_SECRET_KEY, SUPABASE_URL, SUPABASE_SERVICE_ROLE_KEY"
  );
  process.exit(1);
}

const STRIPE_API = "https://api.stripe.com/v1";

async function stripeGet(path: string, account?: string): Promise<any> {
  const res = await fetch(`${STRIPE_API}${path}`, {
    headers: {
      Authorization: `Bearer ${STRIPE_KEY}`,
      ...(account ? { "Stripe-Account": account } : {}),
    },
  });
  const json = await res.json();
  if (!res.ok) throw new Error(`GET ${path}: ${json.error?.message || res.status}`);
  return json;
}

async function stripePost(
  path: string,
  form: Record<string, string>,
  account?: string
): Promise<any> {
  const res = await fetch(`${STRIPE_API}${path}`, {
    method: "POST",
    headers: {
      Authorization: `Bearer ${STRIPE_KEY}`,
      "Content-Type": "application/x-www-form-urlencoded",
      ...(account ? { "Stripe-Account": account } : {}),
    },
    body: new URLSearchParams(form).toString(),
  });
  const json = await res.json();
  if (!res.ok) throw new Error(`POST ${path}: ${json.error?.message || res.status}`);
  return json;
}

async function main() {
  console.log(
    `backfill-payouts-manual — mode ${APPLY ? "APPLY (écritures réelles)" : "DRY-RUN (aucune écriture ; --apply pour exécuter)"}`
  );

  // Comptes Connect connus côté Jolene (source : table d'onboarding).
  const rows: Array<{
    soignant_id: string;
    stripe_account_id: string;
    statut: string;
  }> = await fetch(
    `${SUPABASE_URL}/rest/v1/stripe_connect_onboarding?select=soignant_id,stripe_account_id,statut&stripe_account_id=not.is.null`,
    {
      headers: {
        apikey: SERVICE_ROLE!,
        Authorization: `Bearer ${SERVICE_ROLE}`,
      },
    }
  ).then(async (r) => {
    if (!r.ok) throw new Error(`PostgREST stripe_connect_onboarding: ${r.status}`);
    return r.json();
  });

  console.log(`${rows.length} compte(s) Connect à examiner\n`);

  let basculés = 0,
    déjàManual = 0,
    drainés = 0,
    reportés = 0,
    erreurs = 0;

  for (const row of rows) {
    const acct = row.stripe_account_id;
    const prefix = `[${acct} · soignant ${row.soignant_id.slice(0, 8)} · ${row.statut}]`;
    try {
      // 1. Déjà manual ? (idempotent)
      const account = await stripeGet(`/accounts/${acct}`);
      const interval = account.settings?.payouts?.schedule?.interval;
      if (interval === "manual") {
        console.log(`${prefix} déjà manual — skip`);
        déjàManual++;
        continue;
      }

      // 2. Drain legacy : balance du compte connecté
      const balance = await stripeGet(`/balance`, acct);
      const availEur = (balance.available || []).find((b: any) => b.currency === "eur");
      const pendEur = (balance.pending || []).find((b: any) => b.currency === "eur");
      const availableCents = availEur?.amount ?? 0;
      const pendingCents = pendEur?.amount ?? 0;

      if (pendingCents > 0) {
        // Des fonds en settlement ne sont pas encore payables : basculer
        // maintenant les bloquerait à leur arrivée. On re-run le script quand
        // ils seront `available`.
        console.log(
          `${prefix} ⏸ REPORTÉ — ${(pendingCents / 100).toFixed(2)} € pending (settlement en cours), re-run quand available`
        );
        reportés++;
        continue;
      }

      if (availableCents > 0) {
        if (APPLY) {
          const payout = await stripePost(
            `/payouts`,
            {
              amount: String(availableCents),
              currency: "eur",
              "metadata[raison]": "BACKFILL_DRAIN_LEGACY_7BD",
            },
            acct
          );
          console.log(
            `${prefix} soldé — payout ${payout.id} de ${(availableCents / 100).toFixed(2)} € (drain legacy)`
          );
        } else {
          console.log(
            `${prefix} soldé (dry-run) — payout de ${(availableCents / 100).toFixed(2)} € serait créé`
          );
        }
        drainés++;
      }

      // 3. Bascule en manual
      if (APPLY) {
        await stripePost(`/accounts/${acct}`, {
          "settings[payouts][schedule][interval]": "manual",
        });
      }
      console.log(`${prefix} → basculé manual${APPLY ? "" : " (dry-run)"}`);
      basculés++;
    } catch (err) {
      console.error(`${prefix} ❌ ERREUR : ${(err as Error).message}`);
      erreurs++;
    }
  }

  console.log(
    `\nRésumé : ${basculés} basculé(s), ${déjàManual} déjà manual, ${drainés} drainé(s), ${reportés} reporté(s) (pending), ${erreurs} erreur(s)`
  );
  if (reportés > 0) {
    console.log("⚠ Des comptes ont des fonds en settlement : re-lancer le script plus tard.");
  }
  if (erreurs > 0) process.exit(2);
}

main().catch((err) => {
  console.error("Échec :", err);
  process.exit(1);
});
