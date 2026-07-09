# PLAYBOOK — Escrow / Paiement rapide ⚡ (obligatoire avant tout chantier paiement)

> **Lire et exécuter AVANT de toucher au moindre fichier escrow / Stripe / SEPA.**
> Le rail est ouvert en prod (flag `feature_paiement_rapide_actif = 1`). Une
> erreur ici touche de l'argent réel. Réf. circuit : `docs/flux-monetaire-escrow.md`.

## 0. Invariants NON négociables

1. **Clés Stripe** : jamais commit / log / bundle client / clé **live**. La recette
   tourne en **test mode** (`balance.livemode` doit être `false`, sinon REFUS).
2. **La recette ne tourne JAMAIS sur prod** : garde `PROD_REF = flripxtsyegjshnhzjkz`
   dans `scripts/recette-escrow-stripe.ts` — elle s'exécute sur une **branche
   Supabase éphémère** (`create_branch`), détruite après.
3. **DDL uniquement via CI `deploy-supabase`** (merge d'une migration), jamais
   `apply_migration`/`execute_sql` MCP hors hotfix incident (règle 9.0 CLAUDE.md).
   Exception testing : DDL sur une **branche** Supabase = OK.
4. **Redéfinition depuis le LIVE** : toute réécriture de fonction/trigger part de la
   définition **prod live** (`pg_get_functiondef`), jamais d'un fichier repo obsolète.
5. **`honoraires_cents` figé à la confirmation**, jamais recalculé (plancher #11).
6. **Circuit v15** : destination charge, **`on_behalf_of` retiré**, Jolene merchant
   of record. Les honoraires **ne stationnent jamais** sur un compte Jolene (ils
   *transitent* le settlement) — wording exact, cf. flux-monetaire-escrow.md.

## 1. Rejouer la recette (legs Stripe réels, test mode)

- **CI** : workflow `recette-escrow-stripe.yml` (dispatch). 14 legs attendus PASS,
  invariant solde plateforme vérifié à chaque étape. Tout FAIL = STOP + rapport.
- La recette parque ses résidus (missions ASSIGNEE, escrows INITIE) au lieu de les
  supprimer, et **désactive les tripwires** (`alertes_tripwire_actives = 0`, Setup 0)
  pour ne pas spammer `notify-support`.

## 2. Vérifier la visibilité revenus (E2E, contre prod partagée)

```bash
npm run test:escrow
```
- Spec `e2e/flows/escrow-revenus-soignant.spec.ts` : états
  (`fn_mes_paiements_escrow`), part soignant seule (255 €, jamais 298,20 €),
  no-double-compte (`fn_mes_revenus_connect`), verrous.
- **La DB E2E = prod partagée** : nonce unique par run + purge résidus + deltas.
  Les seeds utilisent des PI factices `pi_pwtest_*` (exclus des tripwires).
- Les tests **verrous** (remboursement partiel pré-release, docs santé) sont
  **capability-guardés** : `test.skip` tant que les migrations `170000/180000` ne
  sont pas en prod (elles s'appliquent au merge), assertion réelle post-deploy.

## 3. Surveillance premier euro réel (tripwires)

- Migration `20260709190000` : alerte `notify-support` à la **première** occurrence
  réelle de mandat SEPA posé / Connect complété / PaymentIntent créé. Auto-limité
  (`NOT EXISTS`), gaté par `fn_param_num('alertes_tripwire_actives', 1)`.
- Après le tout premier vrai paiement : vérifier l'alerte reçue + le circuit Stripe
  (destination charge, application fee, payout manuel).

## 4. Garde-fous « gap verrouillé » (CLAUDE.md)

Un gap documenté (ex. remboursement partiel pré-release, SPEC §9.4) doit être
**impossible à déclencher en silence** : rejet explicite + message renvoyant à la
doc + **un test par verrou**. Ne jamais laisser un chemin non couvert « passer ».

## 5. Non-régression — les 3 bugs recette à ne jamais réintroduire

1. **Mandat SEPA créancier = Jolene** → `on_behalf_of` doit rester ABSENT du
   PaymentIntent (la recette S2.2 asserte son absence).
2. **Enqueue au débit** : le passage `→ DEBITE` doit enfiler la release
   (`fn_trg_escrow_enqueue_on_debite`, migration `20260709130000`).
3. **Audit escrow** : écriture directe en table côté edge (helper `auditEscrow`),
   PAS via `fn_ecrire_audit_safe` (bug binding uuid PostgREST 14.5).
