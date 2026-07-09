# Escrow 7b-D — Mapping §4.5 : les 7 trous × l'architecture destination charges

> 03/07/2026 — Lot 9 Piste B. Préalable à toute ligne de code du chantier escrow.
> Cartographie : 6 lectures parallèles du système de paiement existant (références
> fichier:ligne vérifiées sur le repo + les définitions live `db/baseline_prod_2026-07-04/`).
>
> **Verdict global : les 7 trous de `docs/AUDIT_PAIEMENTS_2_5.md` MAPPENT tous sur
> l'architecture retenue.** Aucun STOP §4.5. Deux corrections factuelles à l'audit
> (§3) et sept découvertes supplémentaires à traiter dans le chantier (§4).

## 1. Architecture cible (rappel des décisions §4.2–4.4 du Lot 9)

- **Modèle PSP Stripe Connect — destination charges** : la charge établissement porte
  `transfer_data[destination]` (compte connecté soignant) + `application_fee_amount`
  (commission 15 % capturée à la source). **⚠️ MàJ v15 : `on_behalf_of` RETIRÉ.** Le
  mandat SEPA désigne **Jolene** comme créancier (`_shared` : `mandate_data.customer_acceptance`) →
  Jolene est **merchant of record**, `on_behalf_of` (qui ferait du compte connecté le
  merchant/settlement) est incompatible et supprimé (cf. `escrow-debit-echeance` v15).
  **Invariant : les honoraires ne STATIONNENT jamais sur le solde plateforme** — ils
  transitent l'instant du settlement (mécanique destination charge) puis filent au
  solde du compte connecté du soignant ; seule l'application fee reste à Jolene. Cf.
  `docs/flux-monetaire-escrow.md` (distinction « ne stationne » vs « ne transite »).
- **Séquestre = payouts manuels** : comptes connectés en
  `settings.payouts.schedule.interval = "manual"`. Les fonds attendent sur le solde
  Connect du soignant (cantonnement Stripe) ; le « release » = `payouts.create` sur le
  compte connecté, déclenché par la validation des présences (1 tap étab ou auto-72h),
  virement reçu J+2/J+3.
- **Timing débit** : à la confirmation de mission — J-7 si le début est à plus de 7
  jours ; prélèvement SEPA si ≥ 6 jours ouvrés de marge, sinon paiement immédiat
  (carte / virement instantané).
- **Échecs** : `payment_intent.payment_failed` → relance J+3 + gel du badge ⚡ de
  l'étab ; dispute SEPA (R-transaction tardive) absorbée par Jolene, plafonnée
  (§11.1) + gel ⚡.
- **Remboursements** : `refunds.create` avec `reverse_transfer: true` (+
  `refund_application_fee` au prorata) — reprend les fonds du solde connecté tant que
  le payout n'est pas parti.

## 2. Mapping des 7 trous

### Trou 1 — « Débit exigé sur statut TERMINEE » → ✅ MAPPE

- **Existant** : `stripe-connect-pay-mission/index.ts:98-106` exige `statut ===
  "TERMINEE"` avant de créer le Checkout ; charge à capture immédiate, aucun
  `capture_method` (`:346-400`).
- **Mécanisme cible** : le débit part **à la confirmation** (assignation) — nouveau
  point d'entrée déclenché par la confirmation de mission + cron J-7 pour les missions
  confirmées loin en avance. Le PaymentIntent devient une destination charge
  (`transfer_data[destination]`, `application_fee_amount` ; **`on_behalf_of` retiré en
  v15**, cf. §1) débitée sur le mandat SEPA étab (`setup-sepa` existant) ou en carte si
  délai court.
- **Fichiers** : `stripe-connect-pay-mission` (refonte ou nouvelle fonction
  `escrow-debit-mission`), nouveau cron `escrow-debits-j7`, garde du statut mission
  (ASSIGNEE au lieu de TERMINEE) derrière le flag `feature_paiement_rapide_actif`.

### Trou 2 — « Pas de phase held, transfer immédiat » → ✅ MAPPE

- **Existant** : `stripe-webhook/index.ts:168-176` fait `stripe.transfers.create` dès
  `checkout.session.completed` ; comptes Express créés **sans**
  `settings.payouts.schedule` (`stripe-connect-onboard/index.ts:112-127`) → payout
  automatique Stripe ; `payouts.create` n'est **jamais** appelé (stub
  `dispatchStripePayout`, `process-externalisation-actions/index.ts:242-244`).
- **Mécanisme cible** : la phase « held » = fonds sur le solde connecté du soignant
  avec payouts manuels. Suppression du `transfers.create` du webhook (le split est
  porté par la charge elle-même) ; onboarding passe `payouts.schedule.interval =
  "manual"` ; **backfill `stripe.accounts.update`** des comptes Express existants ;
  release = implémentation réelle du payout (remplace le stub).
- **Fichiers** : `stripe-webhook` (branche CONNECT_MISSION_PAYMENT `:168-434`),
  `stripe-connect-onboard:112-127`, script backfill one-shot, edge function de release.

### Trou 3 — « Fonds soignant sur le balance Stripe Jolene (réglementaire) » → ✅ MAPPE

- **Existant** : modèle « separate charges & transfers » — la totalité
  (commission + honoraires, 2 line items `stripe-connect-pay-mission:352-369`) est
  chargée sur le solde plateforme, puis les honoraires repartent en transfer. Entre
  les deux (et sur échec `balance_insufficient`, cas documenté
  `stripe-webhook:441-444`), les honoraires stationnent chez Jolene.
- **Mécanisme cible** : c'est la décision §4.2 elle-même. En destination charge, les
  fonds vont **directement** au compte connecté (cantonnement Stripe, statut PSP de
  Stripe) ; Jolene ne touche que `application_fee_amount`. L'invariant est structurel,
  plus besoin de le surveiller applicativement.
- **Fichiers** : les mêmes que trous 1-2 (c'est le même refactor).

### Trou 4 — « Aucune gestion d'échec asynchrone SEPA ni relance » → ✅ MAPPE

- **Existant** : aucun handler `payment_intent.payment_failed` (confirmé — seuls
  `charge.failed:801` et `invoice.payment_failed:718` existent, ciblant la table
  `factures` commission) ; une facture EN_RETARD sort définitivement du cron SEPA
  (`sepa-auto-charge:57-61`) ; aucun handler `charge.dispute.funds_withdrawn/
  reinstated`.
- **Mécanisme cible** : machine à états du paiement mission escrow
  (AUTORISE → DEBITE → RELEASE / ECHOUE) + handlers `payment_intent.payment_failed`
  (→ relance J+3, gel ⚡ étab, mission repasse visible sans badge) et
  `charge.dispute.*` complets. Le timing §4.4 (débit J-7, SEPA ≥ 6 j ouvrés) fait que
  les R-transactions « techniques » (J+3/J+5) arrivent **avant** le release
  post-mission ; les disputes tardives (jusqu'à 8 semaines) sont absorbées par Jolene
  avec plafond §11.1 — décision produit déjà actée.
- **Fichiers** : `stripe-webhook` (nouveaux handlers), nouvelle table ou extension
  `paiements_mission` (machine à états), cron relance J+3.

### Trou 5 — « Aucun lien validation présences → release » → ✅ MAPPE

- **Existant** : le gate 7b-B (`20260702154526`) exprime déjà la condition exacte
  (« aucune présence à pointage complet non validée ni contestée ») mais elle est
  seulement **lue** par `fn_lister_missions_a_facturer` — aucun événement n'est émis
  quand elle bascule. L'état est écrit par exactement 4 fonctions
  (`fn_valider_presence`, `fn_valider_presences_lot`, `fn_valider_alerte_presence`,
  `fn_valider_presences_72h_auto` — cron 72h actif, jobid 26).
- **Mécanisme cible** : trigger `AFTER UPDATE OF valide_par_etablissement ON
  presences` qui recalcule la condition du gate au niveau mission (miroir exact du
  `NOT EXISTS` 7b-B) et enfile le release quand la dernière présence bloquante passe
  validée sans litige résiduel. Couvre uniformément les 4 chemins d'écriture. Le
  release s'articule avec le gel litige existant (`fn_trg_litige_gel_degel_facture`).
- **Fichiers** : nouvelle migration (trigger + queue de release), edge function de
  payout (consommateur), articulation avec `fn_trg_auto_facture_honoraires`.

### Trou 6 — « Réconciliation 1↔N + reverse_transfer manquant » → ✅ MAPPE

- **Existant** : `fn_auto_facturation_mensuelle` agrège 1 facture ↔ N missions
  (`factures.mission_id` existe mais reste NULL dans ce flux) ; `reverse_transfer` : 0
  occurrence dans le code — `process-stripe-refunds:149-159` fait un refund simple sur
  le PaymentIntent, prélevé sur le solde plateforme, **le transfer soignant reste
  intact** (perte plateforme systématique sur remboursement partiel).
- **Mécanisme cible** : la destination charge est **par mission** → l'adossement
  1 mission ↔ 1 PaymentIntent ↔ 1 facture unitaire (renseigner `factures.mission_id`)
  est structurel ; la commission part à la source (`application_fee_amount`), donc les
  missions escrow sortent de la facturation mensuelle agrégée (le flag
  `commission_facturee = true` posé au débit les exclut déjà du `GROUP BY`).
  Remboursements : `reverse_transfer: true` + `refund_application_fee` au prorata,
  **avant release** (fonds encore sur le solde connecté). Attention au montant : la
  queue actuelle enfile un écart **HT** (`fn_admin_resoudre_litige`,
  slice_03.sql:730) — le reversal doit viser la part soignant réellement transférée.
- **Fichiers** : `process-stripe-refunds:149` (+ idempotency key explicite sur le
  reversal), `fn_admin_resoudre_litige` (base de montant), `stripe-webhook`
  `charge.refunded:976` (réconcilier aussi le reversal).

### Trou 7 — « Cron fn_auto_facturation_mensuelle non branché » → ✅ MAPPE (et déjà partiellement résolu)

- **Correction factuelle** : le cron **est branché en prod** — jobid 2
  `auto-facturation-mensuelle`, `0 2 1 * *` (`cron_jobs.sql:19-21`). Le point de
  l'audit §2.5 est obsolète.
- **Ce qui reste** : le circuit mensuel agrégé subsiste pour les étabs hors escrow
  (flag ⚡ off) et le legacy. Sous escrow, la commission étant capturée à la source,
  ce cron n'a plus qu'un rôle résiduel — s'assurer qu'il exclut proprement les
  missions escrow (déjà le cas via `commission_facturee = false` dans son WHERE).

## 3. Corrections factuelles à l'audit §2.5

1. **Les relances existent** : `fn_alerter_paiements_retard` (cron quotidien 8h)
   relance les factures EMISE **et** EN_RETARD à J+7 (`relance_1_le`) et J+21
   (`relance_2_le`), et `fn_gerer_blocage_etabs` bloque la publication de missions
   (~45 j). Ce qui manque réellement : le **re-prélèvement** automatique après échec
   (une facture EN_RETARD ne repasse jamais dans `sepa-auto-charge`) et la transition
   automatique EMISE → EN_RETARD sur échéance dépassée (aucun cron ne la fait).
2. **Le cron mensuel est branché** (cf. trou 7).

## 4. Découvertes hors audit — à traiter dans le chantier

1. **Idempotence webhook branche Connect cassée** : `return` anticipé à
   `stripe-webhook:493` avant le marquage `traite_le:1432` → sur retry Stripe, la
   branche se ré-exécute et le code ne re-vérifie pas le statut TRANSFERE avant
   `transfers.create:168` — **risque latent de double transfert dès aujourd'hui**.
   À corriger indépendamment de l'escrow (hotfix candidat).
2. **Matching `payout.paid` global** : `stripe-webhook:1180` marque PAYE tous les
   `stripe_transfers` TRANSFERE à `stripe_payout_id` NULL, **tous soignants
   confondus**. Tolérable en payout automatique, faux avec des payouts manuels par
   compte — à réécrire (filtrer par `event.account`).
3. **Copie UI mensongère sous escrow** : `PageStripeConnect.tsx:256,259` promet
   « sans délai » / « virements automatiques après chaque mission » → à réécrire au
   flip du flag (règle transversale ② : aucune promesse non contrôlée).
4. **KPI revenus faussé** : `fn_mes_revenus_connect` compte TRANSFERE comme reçu ;
   sous escrow, TRANSFERE-pas-encore-payé n'est plus « reçu ».
5. **Mandat SEPA non tracé côté Jolene** : seuls `payment_method_id` + `iban_last4`
   sont stockés — pas de référence de mandat (RUM) ni date de signature. À enrichir
   pour la preuve de mandat (et exigé par le diff mandat §4.6).
6. **Deux circuits AVOIR à bénéficiaires opposés** : AUTO_STRIPE rembourse
   l'établissement (refund PI), VIREMENT_MANUEL/SWAN verse au **soignant**
   (`dispatchRemboursementAvoirSwan`), sélection par ancienneté 120 j. Sous escrow
   pré-release : reverse_transfer (reprend au soignant) + refund (rembourse l'étab)
   dans la même opération — clarifie le circuit au lieu de le compliquer.
7. **Expiration d'autorisation carte à 7 jours** : pour la branche « délai court =
   carte », préférer un débit immédiat (pas de hold `capture_method: manual` à J-7,
   qui expirerait) — le séquestre est porté par le solde connecté + payout manuel,
   pas par l'autorisation.

## 5. Séquencement d'implémentation proposé

| PR | Contenu | Risque |
|---|---|---|
| 0 (hotfix) | Idempotence branche Connect (`traite_le` avant return + re-check statut TRANSFERE) | Corrige un double-transfert latent en prod |
| 1 | Onboarding `payouts manual` + backfill comptes existants + fix matching `payout.paid` par compte | Sans effet visible (payout auto → manual ne change rien tant que rien n'est en séquestre… **sauf** pour les paiements legacy en cours — à séquencer avec la PR 3) |
| 2 | Machine à états paiement escrow (migration) + trigger release sur validation présences + queue | Backend pur, inactif sans flag |
| 3 | Destination charge à la confirmation (edge function débit + cron J-7 + SEPA/carte selon délai) + suppression transfers.create webhook + handlers payment_intent.payment_failed / dispute | Cœur du chantier, gaté flag ⚡ |
| 4 | Refunds reverse_transfer + base de montant part-soignant | Dépend PR 3 |
| 5 | Release payout réel (remplace stub) + emails/notifs + KPI revenus + copie UI | Dépend PR 1-3 |
| 6 | §4.6 diff CGU/mandat ✋ **validation Gabrielle avant merge** | Légal |
| 7 | §4.7 recette complète mode test Stripe (compte test, débit→validation→release→refund→dispute) | Avant tout flip du flag |

**Le flag `feature_paiement_rapide_actif` reste à 0 pendant tout le chantier.**
Le flip n'intervient qu'après recette §4.7 verte et validation du diff légal §4.6.

## 6. Amendements validés (03/07/2026 — GO Gabrielle)

Le mapping et le séquencement §5 sont approuvés avec les 10 amendements suivants,
à intégrer **avant** d'écrire le cœur du chantier (PR 2-3).

- **A1 — PR 0 GO immédiat** : hotfix idempotence livré (PR #785), discipline
  live-def respectée (pour une edge function, le repo est la source déployée par
  le CI à chaque merge).
- **A2 — Plafond d'exposition §11.1 (🔴, PR 2 ou 3)** : compteur par étab des fonds
  libérés encore remboursables (fenêtre glissante 8 semaines post-débit SEPA,
  incrément au release, décrément à expiration/règlement) ; enforcement dans le
  gating ⚡ : plafond 2 000 € (5 000 € après 3 missions sans incident), au-delà les
  nouvelles missions repassent en régime standard ; **1ʳᵉ mission de chaque étab =
  virement instantané** (intégré au gating 7c) ; gel du ⚡ au premier incident
  (dispute/échec), déblocage manuel admin.
- **A3 — Machine à états : DÉBITÉ ≠ DISPONIBLE** : états
  `INITIE → DEBITE (succeeded) → DISPONIBLE (balance available) → RELEASE_PLANIFIE
  → PAYE` + branches `ECHOUE / REMBOURSE / DISPUTE`. Le consumer de release vérifie
  **deux** conditions (présences validées ET fonds `available` sur le solde
  connecté — retry avec backoff sinon) ; le gating « settled avant J » lit
  `available_on` de la balance transaction, pas le statut du PaymentIntent.
- **A4 — Fallback court délai** : SEPA (≥ 6 j ouvrés) → virement instantané → à
  défaut **pas de badge ⚡, mission en régime standard** (publication normale). La
  carte n'est jamais un prérequis (décision produit : la RH ne met pas sa CB) ;
  reste une option si enregistrée. Débit carte immédiat confirmé (pas de hold J-7,
  cf. découverte 7).
- **A5 — Règle post-release (PR 4)** : avant release `reverse_transfer: true` ;
  **après release, tout remboursement étab est absorbé par Jolene** via l'avoir
  AUTO_STRIPE — jamais de reversal ni de solde négatif imposé à une soignante qui
  a travaillé, sauf fraude avérée (décision admin manuelle, tracée). L'exposition
  A2 est décrémentée en conséquence.
- **A6 — `refund_application_fee` (PR 4)** : annulation totale avant début de
  mission → commission remboursée à 100 % (`refund_application_fee: true`) ;
  réduction partielle → prorata sur la part non due. À encoder avec la correction
  de base de montant (part soignant réellement transférée, pas l'écart HT).
- **A7 — Backfill payouts manual (PR 1) : drainer le legacy d'abord** : inventorier
  les `stripe_transfers` TRANSFERE non payés ; les solder par payout manuel avant
  de basculer chaque compte. Le script loggue compte par compte « soldé → basculé ».
- **A8 — Relances régime standard (PR 3 ou 3 bis)** : ① cron de transition
  `EMISE → EN_RETARD` à échéance dépassée ; ② re-prélèvement automatique d'une
  facture EN_RETARD (réintégration dans `sepa-auto-charge` avec cap de tentatives).
- **A9 — PR 6 : texte légal verbatim** depuis `jolene-clauses-cgv-et-mandat.md`
  (sections B « Paiement rapide ⚡ » CGU soignante + C avenant mandat
  d'encaissement) fourni par Gabrielle. Diff toujours soumis à validation ✋ avant
  merge (règle ④), mais rédaction faite.
- **A10 — Recette PR 7 : +2 scénarios** : ⑧ validation des présences avant
  disponibilité des fonds (SEPA en settlement) → release en file, retry, payout au
  passage `available`, aucune erreur visible soignante ; ⑨ remboursement
  post-release → avoir absorbé plateforme, aucun mouvement côté soignante,
  exposition décrémentée.

Rappels inchangés : flag à 0 pendant tout le chantier (flip après recette
§4.7+A10 verte ET validation du diff légal) ; au flip, réécriture de la copie
`PageStripeConnect.tsx` (découverte 3) et du KPI `fn_mes_revenus_connect`
(découverte 4) **dans la même PR que le flip** ; enrichissement du mandat SEPA
(RUM + date de signature via l'objet `mandate` Stripe, découverte 5) requis.
