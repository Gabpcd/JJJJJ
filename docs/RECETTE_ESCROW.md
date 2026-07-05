# Recette escrow 7b-D — rapport d'exécution (Lot 10 §3)

> 05/07/2026 — exécutée sur **branche Supabase neuve `recette-escrow-v3`**
> (ref `wnepopwygokbhlqghydb`), reconstruite intégralement depuis le registre
> squashé (parité prod prouvée : 149 tables, 719 fonctions — md5 identique).
> Remplace le rapport du 04/07 (recette alors bloquée par le squash, résolu).

## Verdict §6.2 : legs SQL 100 % PASS — **PAS de flip** tant que les legs Stripe ne sont pas verts

- **Machine à états escrow : 14/14 assertions SQL PASS** (détail ci-dessous).
- **2 bugs prod bloquants découverts et corrigés** (migration
  `20260705210000_fix_audit_safe_et_refunds_queue_escrow.sql`, cette PR).
- **Legs Stripe** (PI SEPA réel, settlement webhook, payout, exécution refund,
  dispute event, A10.8 attente fonds) : **non exécutés** — le sandbox ne peut
  pas joindre api.stripe.com (proxy). Chemin préparé : workflow CI avec clé
  test lue depuis le vault de la branche. → règle §6.2 : **flag reste à 0**.

## Bugs prod découverts par la recette

### BUG 1 — `fn_ecrire_audit_safe` : 74 points d'audit silencieusement morts (P1)
L'INSERT visait des colonnes inexistantes (`cle_s3, ip, navigateur` au lieu de
`cle_s3_ressource, ip_acteur, navigateur_acteur`). Échec 100 % des appels,
avalé par `EXCEPTION WHEN OTHERS`. **Preuve prod** : sur 24 410 audits,
`BULLETIN_PAIE_EMIS = 0`, `NOTATION_DONNEE = 0`, `MEDIATION_* = 0` — actions
émises quotidiennement. Impact : CONTRAT_SIGNE, LITIGE_ADMIN_TRANCHE,
COMPTE_SUSPENDU, FRAUDE, tous les audits ESCROW_*… Fix : colonnes corrigées
(déf live, seule la liste de colonnes change). Validé sur branche : le trigger
escrow écrit désormais son audit.

### BUG 2 — `stripe_refunds_queue` : remboursement escrow impossible
`fn_escrow_rembourser` insère `avoir_id=NULL, facture_origine_id=NULL` (un
refund escrow n'a ni avoir ni facture), colonnes **NOT NULL** → A5/A6 ne
pouvait **jamais** réussir (pattern Sprint 17 : contrainte désynchronisée d'un
chemin jamais exécuté). Fix : NOT NULL relâchés + CHECK d'intégrité
`avoir_id IS NOT NULL OR paiement_escrow_id IS NOT NULL`.

## Résultats détaillés (spec docs/ESCROW_7BD_RECETTE.md, scénarios 2→8)

| # | Scénario | Assertion | Résultat |
|---|---|---|---|
| 2.1 | Confirmation → INITIE | trigger sur OUVERTE→ASSIGNEE, LIBERAL only | ✅ PASS |
| 2.1 | 1ʳᵉ mission étab | `VIREMENT_INSTANTANE` + `premiere=true`, débit immédiat | ✅ PASS |
| 2.1 | Marge ≥ 8 j | `SEPA`, débit à **J-7 exactement** du début | ✅ PASS |
| 2.1 | Marge courte | `VIREMENT_INSTANTANE` non-première | ✅ PASS |
| 2.1 | Audit `ESCROW_INITIE` | écrit par le trigger | ✅ PASS (post-fix BUG 1) |
| 2.2–2.3 | Destination charge + settlement | PI Stripe réel + webhook | 🔶 CI Stripe |
| 2.4 | Validation présences → queue | 0 avant ; `EN_ATTENTE` après chaque validation | ✅ PASS |
| 2.5 | Release payout | payout manuel réel | 🔶 CI Stripe |
| 3 | Refund AVANT release, total | `reverse_transfer=true, fee=100 % (4320cts), absorbe=false` | ✅ PASS (post-fix BUG 2) |
| 3 | Variante partielle (½) | `fee = prorata exact (2160cts)`, montant queue = hono+fee | ✅ PASS |
| 4 | A10.9 refund APRÈS release | `absorbe_plateforme=true, reverse_transfer=false` | ✅ PASS (décision) / exécution 🔶 CI |
| 5 | A10.8 validation avant fonds | attente fonds `available` (edge escrow-release) | 🔶 CI Stripe |
| 6 | Échec débit | `ECHOUE` + relance **J+3**, gel, compteur→0, audit GELE | ✅ PASS |
| 6.2 | Badge ⚡ retiré | `fn_etablissements_safe → paiement_rapide=false` gelé | ✅ PASS |
| 6.3 | Dégel admin | éligible à nouveau + audit `ESCROW_ETAB_DEGELE` | ✅ PASS |
| 7 | Dispute | statut `DISPUTE`, **pas de relance auto**, gel | ✅ PASS (décision) / event réel 🔶 CI |
| 8 | Plafond A2 base | 2 000 € ; refus au-dessus ; exposition+montant comptés | ✅ PASS |
| 8 | Plafond mordu au trigger | mission 3 750 € → **0 escrow**, régime standard | ✅ PASS |
| 8 | Étab gelé au trigger | confirmation pendant gel → 0 escrow (A2) | ✅ PASS (observé via M7) |
| 8.2 | Confiance ≥ 3 missions | plafond → 5 000 € | ✅ PASS |
| — | Invariant montants | ∀ lignes `total = commission + honoraires` | ✅ PASS |
| — | Invariant exposition | `fn_escrow_exposition_courante ≡ Σ ACTIF` ; fenêtre +8 sem ; REGLE au refund | ✅ PASS |
| — | Réconciliation pipeline (9.1) | KPI « À valider » ≡ liste destination | ✅ PASS |
| — | Files crons | `fn_escrow_debits_a_echeance` / `fn_escrow_releases_a_traiter` listent juste | ✅ PASS |

## Notes d'environnement (prérequis rejouables)

- Branche = schéma seul : seeder `auth.users` **incl. l'acteur SYSTÈME
  `00000000-…-0000`** (sinon FK audit), flag
  `feature_paiement_rapide_actif=1` dans `parametres_systeme`, étab
  `SEPA_DEBIT` + `stripe_sepa_payment_method_id`, soignante LIBERAL.
- `fn_test_seed_mission`/`fn_test_update_mission` exigent
  `request.jwt.claim.role='service_role'` ; les protections mission exigent un
  acteur `est_admin()` (user `raw_app_meta_data.role=ADMIN_PLATEFORME`).
- Extensions : préambule baseline couvre 8/9 ; `pg_cron` non requis par la
  recette (crons invoqués directement) — installable en 1 ligne (prouvé).
- Gate 7b-B multi-présences : `UNIQUE(mission_id, soignant_id)` rend le cas
  « autre présence bloquante » structurellement impossible — le EXISTS du
  trigger est un garde-fou.

## Reste à faire pour le GO flip (§6.2 : 100 % PASS, zéro MANUEL)

1. **Legs Stripe en CI** (runner GitHub = internet libre) : clé `sk_test` déposée
   dans le **vault de la branche v3** (jamais commitée/loggée), lue par le
   workflow via Management API ; secrets edge de la branche basculés en test ;
   endpoint webhook test enregistré vers la branche. Scénarios : 2.2/2.3/2.5,
   4-exécution, 5 (A10.8), 7-event.
   ⚠️ Ne JAMAIS invoquer les edge functions Stripe de la branche avant d'avoir
   posé la clé test (héritage possible de la clé live prod).
2. Merger cette PR (fixes prod) — préalable à toute exécution réelle.
3. Puis PR de flip (§9 spec) : flag=1 + copie PageStripeConnect + KPI
   `fn_mes_revenus_connect` — inchangé.

La branche `recette-escrow-v3` est **conservée** (≈0,013 $/h) pour les legs
Stripe ; la détruire après (`delete_branch`).
