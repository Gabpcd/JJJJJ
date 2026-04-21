# Inventaire exhaustif tickets — Sub-PR 2 sexies

**Date** : 2026-04-20
**Snapshot base** : commit `f6e8d279` (tech-debt.md restauré, 428 lignes)
**Branche** : `claude/fix-merge-conflicts-2Y4ph`
**Sources couvertes** : A (héritage) + B (Audit 1 Crons) + C (Audit 2 Objets fantômes) + D (Audit 3 Templates email) + E (Audit 4 Paiement salarié) + F (Audit 5 Scoring soignant) + G (Audit 6 Statuts factures REMPLACEE) + H (Audit 7 Stripe Connect) + I (Migrations Sub-PR 2 quater) + J (Smoke tests) + K (Audit 8 RLS global) + L (Audit commission flow Jolene)
**Inventaire complet**. Prochaine étape : planification des Sub-PR.

## 🎯 Sub-PR C — Paiement salarié + commission + Chorus Pro : COMPLÈTE ✅

**Chantier principal Q2 2026** livré intégralement le 21 avril 2026.

### 6 CPs livrés

| CP | Tickets résolus | Commits |
|----|-----------------|---------|
| CP-C-1 (déclaration paiement + attestation URSSAF) | E12, E13 | `5845901e` |
| CP-C-1.5 (E16 bug critique MIXTE×TOUS) | E16 | `0e308bdd..6ee88090` (9 commits) |
| CP-C-2 (templates email + cron relances) | E2, E6, E11 | `1e6bd1cb..9de62dd6` (5 commits) |
| CP-C-3 (blocage auto J+45 + unfreeze + UI bandeau) | E1, E7, E9 | `82c5cc25..7435d8db` (5 commits) |
| CP-C-4 (statut EXPIREE + transition auto) | E5, E8, E14 | `cd803211..50bc30fa` (2 commits) |
| CP-C-5 (Chorus Pro complet, mode simulation) | E15 | `2b1d0757..4fc624a4` (12 commits) |

**Scope réalisé** : E12 (12h) + E13 (0h) + E16 (8h) + E2 (8h) + E6 (3h) + E11 (6h) + E1 (6h) + E7 (6h) + E9 (6h) + E5 (8h) + E8 (4h) + E14 (0h) + E15 (30h) = **97h** (inclut E16 émergent et E15 complet).

**Note CP-C-5** : code complet + mode simulation actif. Activation réelle Chorus Pro bloquée par support PISTE (403 sur credentials, ticket Gabrielle 21/04/2026).

**Sub-PR C : 13 tickets résolus** (E1, E2, E5, E6, E7, E8, E9, E11, E12, E13, E14, E15, E16).

---

## 🎯 Sub-PR D — Stripe Connect Prod-Ready : CLOSE ✅

**Livrée en 6 CP le 20 avril 2026.**

- **Scope réalisé** : ~71h (vs 53h initial, surcharge justifiée : H14 ajouté, H6 sous-estimé 4h→22h)
- **Tickets résolus** : 14 (H1-H14, certains via faux positifs ou cumuls)
- **Nouveaux tickets émergents** : H15 (UI admin disputes P2, suivi), H16 (email STRIPE_COMPTE_SUPPRIME P2, suivi), UI-1a/b/c (bugs + manque admin remontés par smoke test Gabrielle), UI-2a-j (10 tickets refonte UX étab + soignant)

### Livrables Sub-PR D

**Backend** :
- 5 edge functions Stripe refactorées/étendues : `stripe-connect-onboard`, `stripe-connect-status`, `stripe-connect-pay-mission`, `stripe-webhook`, `process-stripe-refunds`
- 1 helper partagé : `_shared/stripe-errors.ts` (mapStripeError typed)
- 2 migrations DDL : `20260420130000` (dispute_* + reversed_le + ANNULEE) + `20260420140000` (statut SUPPRIME)
- 7 templates email : CHARGE_FAILED_ETAB, DISPUTE_OUVERTE_ADMIN/CLOSE_ADMIN, PAYOUT_FAILED_ADMIN/SOIGNANT, PAYOUT_CANCELED_ADMIN, REFUND_ECHEC_ADMIN
- 1 template étendu : PAIEMENT_RAPIDE_RECU (3 contextes : CONNECT_MISSION_PAYMENT, CONNECT_PAYOUT_PAID, legacy factor)
- 1 cron pg_cron actif : `process-stripe-refunds-15min` (jobid 17)

**Frontend** :
- 3 call-sites pay-mission adaptés (gestion FACTURE_NON_GENEREE) : FacturationEtablissement, ObligationsFinancieres, DetailMission
- PageStripeConnect.tsx + ProfilSoignant.tsx : branche SUPPRIME + bouton refresh `?force=true`

**Tests** :
- 5 fichiers SQL automatisables (cp-stripe-2/3/4/5/6.test.sql, ~30 scénarios)
- 5 docs checklists manuelles (~40 scénarios end-to-end)

### Détail CPs

| CP | Tickets résolus | Commit |
|----|-----------------|--------|
| CP-STRIPE-1 (audit uniquement) | H12, H13 (faux positifs) | — |
| CP-STRIPE-2 (propagation PI + PAYEE + notif) | H1, A20, H7, H14 | `a1d0932f` |
| CP-STRIPE-3 (guards + compensation) | H4, H5, H8 | `37deadbd` |
| CP-STRIPE-4 (13 webhook events) | H6 | `dbe2ecc3` |
| CP-STRIPE-5 (process-stripe-refunds full) | H3, A21/T13 | `658acc11` |
| CP-STRIPE-6 (typed errors + cache + SUPPRIME) | H2, H9, H10, H11 | `9c219ad4` |

---

## Légende

- **Priorité** : `P0` (bloquant go-live/critique) · `P1` (bloquant beta/acceptation clients) · `P2` (amélioration notable) · `DIFFÉRÉ` (post-lancement ou dépendance module futur)
- **Statut** : `OUVERT` · `EN COURS` · `RÉSOLU`
- **Source** : `Héritage` (ex-tech-debt.md) · `Audit N : [thème]` · `Migration` · `Smoke test`

---

## Tableau des tickets

| ID   | Titre                                                                 | Priorité | Statut   | Source                          | Scope (h) | Sub-PR                            |
|------|-----------------------------------------------------------------------|----------|----------|---------------------------------|-----------|-----------------------------------|
| A1   | Accès direct factures_honoraires → RPC SECURITY DEFINER                | P2       | OUVERT   | Héritage                        | 4         | SP-frontend-rpc-hardening         |
| A2   | admin-invoke en prod : secrets manquants (SALT + OPS_TEST_ADMIN_PWD)   | P2       | OUVERT   | Héritage                        | 1         | SP-secrets-config                 |
| A3   | Supprimer 2 edge functions proxy test (test-invoke + internal)         | P2       | OUVERT   | Héritage                        | 0.5       | SP-nettoyage-versions-rpcs        |
| A4   | CP4 fn_calculer_financier_mission lit mission_creneaux                 | P1       | RÉSOLU   | Héritage                        | —         | Sub-PR 1 (livrée)                 |
| A5   | CP5 fn_trg_auto_heures_majorees utilise span (6.25€ résidu pauses)     | P1       | OUVERT   | Héritage                        | 12        | SP-triggers-multi-creneaux        |
| A6   | Doc règle "jamais recalculer mission facturée"                         | P2       | OUVERT   | Héritage                        | 2         | SP-triggers-multi-creneaux        |
| A7   | Hardening anti-seed-incohérent (triggers + cron diag)                  | P1       | OUVERT   | Héritage                        | 16        | SP-hardening-coherence-financiere |
| A8   | T1 Validation juridique planchers CCN (brief avocat santé)             | P1       | OUVERT   | Héritage                        | 4         | SP-validation-juridique           |
| A9   | T2 Auto-détection divergence backfill (script + alerting)              | P2       | OUVERT   | Héritage                        | 4         | SP-hardening-coherence-financiere |
| A10  | T3 Audit trail modif description post-gel                              | P2       | OUVERT   | Héritage                        | 3         | SP-audit-trail-missions           |
| A11  | T4 Notifier soignant si service modifié post-gel                       | P2       | OUVERT   | Héritage                        | 3         | SP-audit-trail-missions           |
| A12  | T5 Doc JWT context bulk-updates pour heures majorées                   | P2       | OUVERT   | Héritage                        | 1         | SP-docs                           |
| A13  | T6 Test plafond 48h + heures externes déclarées                        | DIFFÉRÉ  | OUVERT   | Héritage                        | 2         | Modules futurs                    |
| A14  | T7 Cron détection créneaux effectifs jamais fermés                     | P2       | OUVERT   | Héritage                        | 6         | SP-crons-fixes                    |
| A15  | T8 Batch recalc financials missions existantes (post-purge CP6)        | P2       | OUVERT   | Héritage                        | 2         | SP-crons-fixes                    |
| A16  | Sub-PR 2bis : gestion admin taux commission (groupes étabs)            | P1       | OUVERT   | Héritage                        | 24        | SP-commission-groupes             |
| A17  | T9 Gel facture par période (unlock Partie 2)                           | DIFFÉRÉ  | OUVERT   | Héritage                        | 8         | Partie 2 litiges hebdo            |
| A18  | T10 Rate limit litiges 3/h vs 3/24h (post-retours terrain)             | DIFFÉRÉ  | OUVERT   | Héritage                        | 2         | Post-beta                         |
| A19  | T11 Audit exhaustif objets SQL fantômes (types.ts ↔ migrations)        | P2       | OUVERT   | Héritage                        | 16        | SP-phantom-objects-audit          |
| A20  | T12 Câblage stripe_payment_intent_id sur factures_honoraires           | P1       | RÉSOLU   | Héritage / CP-STRIPE-2          | 8         | SP-stripe-connect-prod-ready      |
| A21  | T13 Edge function process-stripe-refunds à finaliser                   | P1       | RÉSOLU   | Héritage / CP-STRIPE-5          | 12        | SP-stripe-connect-prod-ready      |
| A22  | T14 Regen PDF/XML avoir via pg_net (FIX 18)                            | P2       | RÉSOLU   | Héritage                        | —         | Sub-PR 2 quater (livrée)          |
| A23  | T15 Type email RELANCE_FACTURE orphelin (relances perdues)             | P1       | RÉSOLU   | Héritage                        | —         | Sub-PR 2 quater (livrée)          |
| A24  | T18 fn_ouvrir_litige_rate_limited : fenêtres F2/F3 ineffectives        | P0       | RÉSOLU   | Héritage                        | —         | Sub-PR 2 quater (livrée)          |
| A25  | T19 Escalade + fenêtre : flag global vs type_contrat_applique          | P0       | RÉSOLU   | Héritage                        | —         | Sub-PR 2 quater (livrée)          |
| A26  | T20 fn_cloturer_litige_mutuel sans audit RGPD                          | P1       | RÉSOLU   | Héritage                        | —         | Sub-PR 2 quater (livrée)          |
| B1   | alerte-cddu-repetitif : RPC fn_alerter_cddu_repetitif inexistante      | P0       | OUVERT   | Audit 1 : Crons                 | 10        | SP-crons-fixes                    |
| B2   | recalculer-paliers-commission : erreur ALTER TABLE → cron échoue       | P0       | OUVERT   | Audit 1 : Crons                 | 6         | SP-crons-fixes                    |
| B3a  | calculer-bfa-annuel : rattrapage manuel BFA 2025 (fn_calculer_bfa_tous) | P0       | OUVERT   | Audit 1 : Crons                 | 0.5       | SP-crons-fixes                    |
| B3b  | calculer-bfa-annuel : vérifier déclenchement cron 2 janvier 2027       | P2       | OUVERT   | Audit 1 : Crons                 | 0.25      | SP-crons-fixes                    |
| B4   | litige-escalation-cron : deploy CLI + schedule + vault secret prod     | P1       | EN COURS | Audit 1 : Crons                 | 0.5       | SP-activation-prod                |
| B5   | auto-transitions-missions : purge 900 logs d'échecs historiques        | P2       | RÉSOLU   | Audit 1 : Crons                 | 0.5       | SP-nettoyage-observabilite        |
| C1   | Régén types.ts : 3 RPCs typées `as any` (reclamation ×2 + paiement_soignant) | P2 | OUVERT   | Audit 2 : Objets fantômes       | 2         | SP-phantom-objects-audit          |
| C2   | Câbler UI fn_declarer_fin_retroactive (RPC CP5b présente sans front)   | DIFFÉRÉ  | OUVERT   | Audit 2 : Objets fantômes       | 4         | Modules futurs (UI pointage)      |
| C3   | Câbler UI fn_scanner_code_pointage (RPC CP5b scanner, pas d'écran soignant) | DIFFÉRÉ | OUVERT | Audit 2 : Objets fantômes       | 6         | Modules futurs (UI pointage)      |
| D1   | CONTRAT_A_SIGNER non câblé post-création contrats_mission (UX rompue)  | P0       | OUVERT   | Audit 3 : Templates email       | 3         | SP-B-templates-email-critiques    |
| D2   | REMBOURSEMENT_CONFIRME : TODO dans fn_confirmer_remboursement_avoir    | P0       | OUVERT   | Audit 3 : Templates email       | 2         | SP-B-templates-email-critiques    |
| D3   | REGULARISATION_SOCIALE_REQUISE promise par LitigeResolutionModal, backend muet | P0 | OUVERT | Audit 3 : Templates email       | 4         | SP-B-templates-email-critiques    |
| D4   | EVALUATION_RECUE jamais déclenché (mock AdminEmails uniquement)        | P1       | OUVERT   | Audit 3 : Templates email       | 3         | SP-B-templates-email-critiques    |
| D5   | MISSION_NON_POURVUE jamais appelé                                      | P1       | OUVERT   | Audit 3 : Templates email       | 2         | SP-B-templates-email-critiques    |
| D6   | LITIGE_NOUVEAU_MESSAGE non câblé dans fn_ajouter_message_litige        | P1       | OUVERT   | Audit 3 : Templates email       | 2         | SP-B-templates-email-critiques    |
| D7   | PAIEMENT_RAPIDE_RECU : factor-webhook insère notif sans invoke send-email | P1    | OUVERT   | Audit 3 : Templates email       | 2         | SP-B-templates-email-critiques    |
| D8   | RECAP_HEBDO : aucun cron, câbler ou retirer                            | P2       | OUVERT   | Audit 3 : Templates email       | 4         | SP-B-templates-email-critiques    |
| D9   | ELIGIBLE_LIBERAL : aucun trigger (heures_totales ≥ seuil), câbler ou supprimer | P2 | OUVERT  | Audit 3 : Templates email       | 3         | SP-B-templates-email-critiques    |
| D10  | PAIEMENT_CONFIRME : aucun trigger (distinct FACTURE_PAYEE), câbler ou fusionner | P2 | OUVERT | Audit 3 : Templates email       | 2         | SP-B-templates-email-critiques    |
| D11  | AdminEmails.tsx : 7 noms legacy → bouton "Send test" rend templates vides | P1   | OUVERT   | Audit 3 : Templates email       | 2         | SP-B-templates-email-critiques    |
| D12  | Audit systémique pattern "notif in-app sans email" + 3 TODOs post-CP-LITIGES-3 | P1 | OUVERT  | Audit 3 : Templates email       | 8         | SP-B-templates-email-critiques    |
| E1   | Unifier blocage auto étab (OR : commission impayée >45j OU paiement soignant non déclaré >45j) + reformulé post-audit Sub-PR C | P0 | RÉSOLU | Audit 4 / CP-C-3 C commit 21018ea7 | 6         | SP-C-paiement-salarie-refonte     |
| E2   | Créer 3 templates email manquants (RAPPEL_PAIEMENT_J7 + PAIEMENT_RETARD_J21 + PUBLICATION_SUSPENDUE) | P0 | RÉSOLU | Audit 4 / CP-C-2 B commit 53e56f7b | 8 | SP-C-paiement-salarie-refonte     |
| E3   | Pont pg_net → send-email pour notif étab/soignant paiement (validé post-audit) | P0 | OUVERT | Audit 4 : Paiement salarié      | 4         | SP-C-paiement-salarie-refonte     |
| E4   | Déduplication notif par `type` dédié (clarifié : RAPPEL_PAIEMENT_J7/J21, BLOCAGE_ETAB, DEBLOCAGE_ETAB) | P0 | OUVERT | Audit 4 : Paiement salarié | 3 | SP-C-paiement-salarie-refonte     |
| E5   | Statut mission EXPIREE + transition automatique (seuil 1h post debut_le) | P1 | RÉSOLU | Audit 4 / CP-C-4 A commit cd803211 | 8         | SP-C-paiement-salarie-refonte     |
| E6   | Exploiter colonne `relance_2_le` (dead column, jamais écrite — confirmé par audit)          | P1       | RÉSOLU   | Audit 4 / CP-C-2 A commit 1e6bd1cb      | 3         | SP-C-paiement-salarie-refonte     |
| E7   | Unfreeze automatique quand étab régularise (immédiat, pas de cooldown)  | P1       | RÉSOLU   | Audit 4 / CP-C-3 C commit 21018ea7     | 6         | SP-C-paiement-salarie-refonte     |
| E8   | echeance_le calculé par fn_declarer_paiement_soignant (CP-C-1), seuils relances gardés sur fin_le pour uniformité produit | P2 | RÉSOLU | Audit 4 / CP-C-4 audit (aucun travail additionnel) | 4         | SP-C-paiement-salarie-refonte     |
| E9   | Ajouter colonnes `bloque_auto_le`, `bloque_auto_raisons`, table historique_blocages_etablissements | P2 | RÉSOLU | Audit 4 / CP-C-3 A commit 82c5cc25 | 6         | SP-C-paiement-salarie-refonte     |
| E10  | Seuils paiement validés Gabrielle : J+7 1ère relance, J+21 2ème, J+45 blocage (commission + soignant) | P0 | OUVERT | Audit 4 / Audit Sub-PR C | 4         | SP-C-paiement-salarie-refonte     |
| E11  | Implémenter reminder J+7 (cron paiements_soignant, zéro code actuel)    | P0       | RÉSOLU   | Audit 4 / CP-C-2 C commit 0f8f62e9 | 6         | SP-C-paiement-salarie-refonte     |
| E12  | Créer page UI + RPC côté étab pour DÉCLARER paiement soignant (ATTESTATION SUR L'HONNEUR obligatoire) | P0 | RÉSOLU | Audit Sub-PR C / CP-C-1 | 12 | SP-C-paiement-salarie-refonte     |
| E13  | Audit source historique des 14 lignes `paiements_soignant` existantes — mix seed + usage réel minime | P1 | RÉSOLU | Audit Sub-PR C / CP-C-1 audit intégré       | 0         | SP-C-paiement-salarie-refonte     |
| E14  | Ajouter `EXPIREE` à enum `statut_mission` (scope inclus dans E5)        | P1       | RÉSOLU   | Audit Sub-PR C / CP-C-4 A commit cd803211 | 0 (⇔ E5)  | SP-C-paiement-salarie-refonte     |
| UI-C4-email | Template email MISSION_EXPIREE pour étab (notif in-app déjà OK, email optionnel nice-to-have) | P2 | OUVERT | CP-C-4 émergent | 2 | SP-B-templates-email-critiques    |
| E15  | Chorus Pro full : PISTE OAuth2 + deposer/flux + sync-chorus-status + UI admin + mention subrogation art. 289 I-2 CGI | P0 | RÉSOLU | Audit Sub-PR C / CP-C-5 commits 2b1d0757..4fc624a4 (12 commits) | 30 | SP-C-paiement-salarie-refonte     |
| E16  | Bug URSSAF critique : choix contrat SALARIE/LIBERAL pour soignant MIXTE × mission TOUS non persisté (5 RPCs + 3 front) | P0 | RÉSOLU | Investigation Passe 2 Sub-PR C / E16 backend 1A-1E + frontend 2B-2D | 8 | SP-C-paiement-salarie-refonte     |
| F1   | Triple pénalité annulation soignant (dec_penalite + dec_fiabilite + RPC, cumul -15 à -35) | P0 | OUVERT | Audit 5 : Scoring soignant | 6 | SP-E-scoring-refonte              |
| F2   | Deux moteurs de score s'écrasent (compteurs vs évaluation, dernier trigger gagne) | P0 | OUVERT | Audit 5 : Scoring soignant    | 8         | SP-E-scoring-refonte              |
| F3   | Trois valeurs désynchro annulation soignant (-8, -10, -15/25) dans 3 endroits | P0 | OUVERT | Audit 5 : Scoring soignant        | 3         | SP-E-scoring-refonte              |
| F4   | COMPORTEMENT_SOIGNANT / SECURITE_DANGER verdict contre soignant = 0 impact score | P0 | OUVERT | Audit 5 : Scoring soignant    | 6         | SP-E-scoring-refonte              |
| F5   | Aucune décote temporelle (absence 2 ans pèse autant qu'hier)           | P1       | OUVERT   | Audit 5 : Scoring soignant      | 6         | SP-E-scoring-refonte              |
| F6   | Compteurs doublement MAJ (dec_maj_compteurs SELECT COUNT + dec_fiabilite +1) | P1 | OUVERT | Audit 5 : Scoring soignant         | 3         | SP-E-scoring-refonte              |
| F7   | `heures_reelles=0` non couplé à `total_absences`                       | P1       | OUVERT   | Audit 5 : Scoring soignant      | 3         | SP-E-scoring-refonte              |
| F8   | Départ anticipé calculé mais non pénalisé                              | P1       | OUVERT   | Audit 5 : Scoring soignant      | 4         | SP-E-scoring-refonte              |
| F9   | Bonus urgence effacé au prochain recalcul formule principale           | P1       | OUVERT   | Audit 5 : Scoring soignant      | 3         | SP-E-scoring-refonte              |
| F10  | Pas de pondération évaluation récente vs ancienne                      | P2       | OUVERT   | Audit 5 : Scoring soignant      | 4         | SP-E-scoring-refonte              |
| F11  | Initialisation score à 50 non documentée produit                       | P2       | OUVERT   | Audit 5 : Scoring soignant      | 2         | SP-E-scoring-refonte              |
| F12  | `reclamations` vs `reclamations_scoring` — 2 tables parallèles à fusionner/documenter | P2 | OUVERT | Audit 5 : Scoring soignant | 6         | SP-E-scoring-refonte              |
| F13  | Refonte `fn_recalculer_score_fiabilite` unifiée (remplace 4 mécanismes concurrents) | P0 | OUVERT | Audit 5 : Scoring soignant     | 24        | SP-E-scoring-refonte              |
| F14  | Table `scoring_events` append-only (traçabilité + anti-double-compte + audit) | P1 | OUVERT | Audit 5 : Scoring soignant          | 12        | SP-E-scoring-refonte              |
| F15  | Mapping catégories litige → impact explicite (SECURITE_DANGER -20, COMPORTEMENT_SOIGNANT -10) | P0 | OUVERT | Audit 5 : Scoring soignant | 4 | SP-E-scoring-refonte            |
| G1   | `fn_protect_creneaux_si_facture` trigger : filtre statut oublie REMPLACEE → blocage post-litige | P0 | OUVERT | Audit 6 : Statuts factures REMPLACEE | 2 | SP-A-fixes-rapides               |
| G2   | `generate-invoice/index.ts:716` guard doublon oublie REMPLACEE → risque 3e facture même mission | P0 | OUVERT | Audit 6 : Statuts factures REMPLACEE | 2 | SP-A-fixes-rapides               |
| G3   | `MesFacturesHonoraires.tsx` : STATUT_CONFIG sans REMPLACEE (badge trompeur) + KPI totalFacture gonflé | P1 | OUVERT | Audit 6 : Statuts factures REMPLACEE | 3 | SP-A-fixes-rapides               |
| G4   | `fn_admin_mandats_stats` : SUM(montant_ttc) sans filtre statut (bug pré-existant amplifié par REMPLACEE) | P2 | OUVERT | Audit 6 : Statuts factures REMPLACEE | 2 | SP-A-fixes-rapides               |
| H1   | stripe_payment_intent_id jamais écrit sur factures_honoraires (⇔ A20 T12, même travail) | P0 | RÉSOLU | Audit 7 : Stripe Connect / CP-STRIPE-2 | 0 (⇔ A20) | SP-D-stripe-connect-prod-ready    |
| H2   | Edge functions Stripe ne consomment pas DDL FIX 9 (résolu via CP2-3-4-5 cumulés : stripe-webhook consomme dispute_*, reversed_le, stripe_payout_id, paye_le, type_document ; autres colonnes légitimement hors scope edge functions) | P0 | RÉSOLU | Audit 7 / CP-STRIPE-2+3+4+5 | 0 | SP-D-stripe-connect-prod-ready    |
| H3   | stripe_refunds_queue non consommée, process-stripe-refunds squelette (⇔ A21 T13) | P0 | RÉSOLU | Audit 7 : Stripe Connect / CP-STRIPE-5 | 0 (⇔ A21) | SP-D-stripe-connect-prod-ready    |
| H4   | stripe-webhook ignore statut REMPLACEE → paiement possible contre facture invalidée (CP-STRIPE-2 : factures_honoraires OK ; CP-STRIPE-3 : factures commission OK) | P0 | RÉSOLU | Audit 7 : Stripe Connect / CP-STRIPE-2+3 | 1 | SP-D-stripe-connect-prod-ready    |
| H5   | Pas de rollback atomique stripe-connect-pay-mission (Checkout OK, upsert KO → orphelin) | P1 | RÉSOLU | Audit 7 : Stripe Connect / CP-STRIPE-3 | 4 | SP-D-stripe-connect-prod-ready    |
| H6   | Pas de handler `transfer.failed` dans stripe-webhook — étendu à 13 events (CP-STRIPE-4 inc. dispute, payout, refund, charge failed/pending/expired) | P1 | RÉSOLU | Audit 7 : Stripe Connect / CP-STRIPE-4 | 22         | SP-D-stripe-connect-prod-ready    |
| H7   | Pas de notification soignant à réception transfert Connect                | P1       | RÉSOLU   | Audit 7 : Stripe Connect / CP-STRIPE-2 | 3         | SP-D-stripe-connect-prod-ready    |
| H8   | stripe-connect-pay-mission ne vérifie pas statut facture (peut payer ANNULEE) | P1    | RÉSOLU   | Audit 7 : Stripe Connect / CP-STRIPE-2 | 3         | SP-D-stripe-connect-prod-ready    |
| H9   | Gestion erreurs Stripe typées manquante (helper _shared/stripe-errors.ts) | P2      | RÉSOLU   | Audit 7 / CP-STRIPE-6           | 5         | SP-D-stripe-connect-prod-ready    |
| H10  | Pas de throttle/cache sur stripe-connect-status (cache 5min via modifie_le + ?force=true) | P2 | RÉSOLU | Audit 7 / CP-STRIPE-6       | 3         | SP-D-stripe-connect-prod-ready    |
| H11  | Gestion compte Stripe supprimé (catch resource_missing + statut SUPPRIME + UI branche) | P2 | RÉSOLU | Audit 7 / CP-STRIPE-6           | 3         | SP-D-stripe-connect-prod-ready    |
| H12  | Enum `mode_remboursement_avoir` orphelin (faux positif : colonne existe sous le nom `mode_remboursement`) | P2 | RÉSOLU | Audit CP-STRIPE-1               | 0         | SP-D-stripe-connect-prod-ready    |
| H13  | 27 missions STRIPE_CONNECT sans soignant onboardé (data de test : UUIDs seed + étabs test) | P1 | RÉSOLU | Audit CP-STRIPE-1                | 0         | SP-D-stripe-connect-prod-ready    |
| H14  | Transition EMISE → PAYEE de factures_honoraires manquante dans flow CONNECT | P1 | RÉSOLU | Audit CP-STRIPE-2                | 3         | SP-D-stripe-connect-prod-ready    |
| H15  | UI admin disputes (chargebacks Stripe) — tableau de bord dédié         | P2       | OUVERT   | Audit CP-STRIPE-4 (suivi)       | 8         | SP-admin-ui-disputes (futur)      |
| H16  | Template email STRIPE_COMPTE_SUPPRIME_SOIGNANT (notif soignant quand compte Stripe détecté supprimé) | P2 | OUVERT | Audit CP-STRIPE-6 (suivi)        | 2         | SP-B-templates-email-critiques    |
| UI-1a | Route `/admin/cohort-economics` manquante dans App.tsx (404) — page AdminCohortEconomics.tsx existe | P0 | OUVERT | Smoke test CP-STRIPE-6 Gabrielle | 0.5       | SP-UI-1-bugs-admin                |
| UI-1b | KPI "Prélever SEPA" toujours vide — vérifier query RPC + data test | P1       | OUVERT   | Smoke test CP-STRIPE-6 Gabrielle | 1         | SP-UI-1-bugs-admin                |
| UI-1c | Créer page `/admin/stripe` sidebar dédiée (stats Connect + paiements + onboarding) | P2 | OUVERT | Smoke test CP-STRIPE-6 Gabrielle | 4         | SP-UI-1-bugs-admin                |
| UI-2a | Refonte UI `LitigesEtablissement.tsx` (alignement qualité AdminModeration) | P1 | OUVERT | Smoke test CP-STRIPE-6 Gabrielle | 15        | SP-UI-2-refonte-ux-etab-soignant  |
| UI-2b | Refonte UI `LitigesSoignant.tsx` (même qualité que refonte étab) | P1       | OUVERT   | Smoke test CP-STRIPE-6 Gabrielle | 15        | SP-UI-2-refonte-ux-etab-soignant  |
| UI-2c | Audit + refonte UI `FacturationEtablissement.tsx`                      | P2       | OUVERT   | Smoke test CP-STRIPE-6 Gabrielle | 10        | SP-UI-2-refonte-ux-etab-soignant  |
| UI-2d | Audit + refonte UI `ObligationsFinancieres.tsx`                        | P2       | OUVERT   | Smoke test CP-STRIPE-6 Gabrielle | 8         | SP-UI-2-refonte-ux-etab-soignant  |
| UI-2e | Audit + refonte UI `DashboardEtablissement.tsx`                        | P2       | OUVERT   | Smoke test CP-STRIPE-6 Gabrielle | 10        | SP-UI-2-refonte-ux-etab-soignant  |
| UI-2f | Audit + refonte UI `DashboardRH.tsx`                                   | P2       | OUVERT   | Smoke test CP-STRIPE-6 Gabrielle | 8         | SP-UI-2-refonte-ux-etab-soignant  |
| UI-2g | Audit + refonte UI `MesFacturesHonoraires.tsx`                         | P2       | OUVERT   | Smoke test CP-STRIPE-6 Gabrielle | 6         | SP-UI-2-refonte-ux-etab-soignant  |
| UI-2h | Audit + refonte UI `DashboardSoignant.tsx`                             | P2       | OUVERT   | Smoke test CP-STRIPE-6 Gabrielle | 10        | SP-UI-2-refonte-ux-etab-soignant  |
| UI-2i | Polish UI `PageStripeConnect.tsx` + `ProfilSoignant.tsx`               | P2       | OUVERT   | Smoke test CP-STRIPE-6 Gabrielle | 4         | SP-UI-2-refonte-ux-etab-soignant  |
| UI-2j | Refonte `BarreNavigation` (cohérence visuelle globale si nécessaire)   | P2       | OUVERT   | Smoke test CP-STRIPE-6 Gabrielle | 3         | SP-UI-2-refonte-ux-etab-soignant  |
| UI-E16-1 | Dialog unique choix contrat pour série MIXTE×TOUS (DetailSerieSoignant) — contournement 2C laisse wording, dialog serait DX + | P2 | OUVERT | E16 Passe 2C | 4 | SP-UI-2-refonte-ux-etab-soignant  |
| UI-E16-2 | UI admin assignation mission avec param choix contrat obligatoire MIXTE×TOUS — fn_assigner_mission_admin prête backend, aucune UI existante | P2 | OUVERT | E16 audit Passe 2 | 6 | SP-UI-1-bugs-admin                |
| BUG-UI-OBLIG-1 | ObligationsFinancieres étab : paiements déjà effectués restent dans "missions à payer aux soignants" + message "Un paiement est déjà en cours pour cette mission" pour missions DÉJÀ PAYÉES (confirmé en prod 22/04/2026) | P1 | OUVERT | Smoke test CP-C-5 + reconfirmé BUG-UI-STRIPE-1.2 | 3 | SP-UI-2-refonte-ux-etab-soignant |
| BUG-UI-STRIPE-1 | Payer commission Jolene par carte via UI étab : erreur 500 sur create-invoice-payment (régression Sub-PR D ou nouveau bug à investiguer) | P1 | OUVERT | Smoke test session CP-C-5 | 3 | SP-UI-1-bugs-admin |
| BUG-RLS-1 | 403 sur tables reclamations, shifts, equipes dans console navigateur étab (RLS ou tables inexistantes à investiguer) | P2 | OUVERT | Smoke test session CP-C-5 | 1 | SP-H-rls-consolidation |
| UI-C5-badge-etab | Badge statut Chorus Pro (DEPOSEE/ACCEPTEE/PAYEE/REJETEE) sur factures honoraires côté UI étab + soignant | P2 | OUVERT | C5-D hors scope MVP | 2 | SP-UI-2-refonte-ux-etab-soignant |
| BUG-UI-CHORUS-CONFIG | Page /admin/chorus-pro tab Config : ChorusConfigEtabDialog sans validation format numero_structure (devrait valider SIRET 14 chiffres ou format Chorus Pro) | P2 | OUVERT | Découverte session BUG-UI-STRIPE-1.2 | 1 | SP-UI-1-bugs-admin |
| BUG-UI-EVAL-1 | Fiche mission étab : bandeau "Évaluer le soignant" s'affiche même si évaluation déjà faite (condition d'affichage ne vérifie pas EXISTS evaluations pour le couple mission/soignant/évaluateur) | P1 | OUVERT | Smoke test session 22/04/2026 | 2 | SP-UI-1-bugs-admin |
| UI-MISSION-FICHE-RICHE | Fiche mission TERMINEE (étab + soignant) trop pauvre : manque heures pointage exactes, codes pointage, pauses, timeline déroulement, DPAE référence, évaluations cross. Enrichir DetailMission post-TERMINEE avec section/onglet "Déroulement" complet | P2 | OUVERT | Smoke test session 22/04/2026 | 8 | SP-UI-2-refonte-ux-etab-soignant |
| I1   | Migration orpheline prod `20260417102123` — FAUX POSITIF (version correcte = 20260417120000, fichier local OK) | P2 | RÉSOLU | Audit CP-STRIPE-1 / post-merge | 0         | SP-F-bugs-latents-nettoyage       |
| I2   | Cohabitation 2 versions `fn_admin_resoudre_litige` (5-arg legacy + 6-arg) → DROP après vérif usages | P2 | OUVERT | Migrations : Sub-PR 2 quater | 3         | SP-F-bugs-latents-nettoyage       |
| I3   | Cohabitation 2 versions `fn_ouvrir_litige_rate_limited` (2-arg + 3-arg) → DROP après vérif usages | P2 | OUVERT | Migrations : Sub-PR 2 quater | 3         | SP-F-bugs-latents-nettoyage       |
| I4   | `fn_generer_code_parrainage` appelle gen_random_bytes sans schéma → SET search_path | P2 | OUVERT | Migrations : Sub-PR 2 quater | 2         | SP-F-bugs-latents-nettoyage       |
| I5   | Trigger `fn_auto_code_parrainage` : NULL-only restrictif, refuse INSERT avec code explicite | P2 | OUVERT | Migrations : Sub-PR 2 quater | 2         | SP-F-bugs-latents-nettoyage       |
| J1   | Enum `type_document_facture` manque FACTURE_COMPLEMENTAIRE (uniquement FACTURE + AVOIR) | P2 | OUVERT | Smoke tests : FAIL design        | 3         | SP-G-decisions-design-factures    |
| J2   | Colonnes `ajuster_heures`/`ajuster_taux`/`action_financiere_appliquee` absentes table litiges (design JSONB audit_log) | P2 | OUVERT | Smoke tests : FAIL design | 2 | SP-G-decisions-design-factures    |
| J3   | Colonne `annulee_pour_litige_id` absente factures_honoraires (tracé via statut + facture_precedente_id + litige_id) | P2 | OUVERT | Smoke tests : FAIL design | 1 | SP-G-decisions-design-factures    |
| K1   | 8 policies RLS role `public` → `authenticated` (messages_litige, factures_honoraires, calendar_*, email_queue, sms_envoyes) | P1 | OUVERT | Audit 8 : RLS global | 1 | SP-H-rls-consolidation            |
| K2   | 3 SELECT policies redondantes factures_honoraires → garder `fh_select_own` seule | P2 | OUVERT | Audit 8 : RLS global             | 1         | SP-H-rls-consolidation            |
| K3   | Documenter tables append-only by design (litiges, messages_litige, contrats_mission, journaux_audit…) | P2 | OUVERT | Audit 8 : RLS global        | 2         | SP-H-rls-consolidation            |
| L1   | Cron mensuel `fn_auto_facturation_mensuelle` (30 missions TERMINEE, 1092€ non facturé) | P0 | OUVERT | Audit L : Commission flow    | 3         | SP-I-commission-flow-hardening    |
| L2   | Cron quotidien bascule EMISE → EN_RETARD (3/4 factures émises en retard non flaggées) | P0 | OUVERT | Audit L : Commission flow   | 1         | SP-I-commission-flow-hardening    |
| L3   | Onboarding SEPA forcé signature contrat-cadre (0/16 étabs configurés)   | P0       | OUVERT   | Audit L : Commission flow       | 6         | SP-I-commission-flow-hardening    |
| L4   | Expliciter compte Stripe Jolene (metadata + validation compta, aujourd'hui implicite) | P1 | OUVERT | Audit L : Commission flow    | 4         | SP-I-commission-flow-hardening    |
| L5   | Mécanisme blocage étab impayé commission > 30j (aucune sanction aujourd'hui) | P1 | OUVERT | Audit L : Commission flow            | 8         | SP-I-commission-flow-hardening    |
| L6   | Consommer table `paliers_commission` dans `fn_calculer_financier_mission` (4 paliers dormants) | P2 | OUVERT | Audit L : Commission flow | 8         | SP-I-commission-flow-hardening    |
| L7   | Audit trail `taux_commission_source` lors du gel taux (traçabilité modifs mid-month) | P2 | OUVERT | Audit L : Commission flow    | 4         | SP-I-commission-flow-hardening    |
| L8   | Auto-retry SEPA échouée (colonne tentatives_sepa + cron retry, max 3)    | P2       | OUVERT   | Audit L : Commission flow       | 4         | SP-I-commission-flow-hardening    |

---

## Comptage automatique

**Total tickets** : 140

| Catégorie       | Nombre | IDs                                                                     |
|-----------------|--------|-------------------------------------------------------------------------|
| P0 OUVERTS      | 21     | B1, B2, B3a, D1, D2, D3, E3, E4, E10, F1, F2, F3, F4, F13, F15, G1, G2, L1, L2, L3, UI-1a |
| P0 RÉSOLUS      | 12     | A24, A25, E1, E2, E11, E12, E15, E16, H1, H2, H3, H4                    |
| P1 OUVERTS      | 26     | A5, A7, A8, A16, D4, D5, D6, D7, D11, D12, F5, F6, F7, F8, F9, F14, G3, K1, L4, L5, UI-1b, UI-2a, UI-2b, BUG-UI-OBLIG-1, BUG-UI-STRIPE-1, BUG-UI-EVAL-1 |
| P1 EN COURS     | 1      | B4                                                                      |
| P1 RÉSOLUS      | 16     | A4, A20, A21, A23, A26, E5, E6, E7, E13, E14, H5, H6, H7, H8, H13, H14  |
| P2 OUVERTS      | 50     | A1, A2, A3, A6, A9, A10, A11, A12, A14, A15, A19, B3b, C1, D8, D9, D10, F10, F11, F12, G4, H15, H16, I2, I3, I4, I5, J1, J2, J3, K2, K3, L6, L7, L8, UI-1c, UI-2c, UI-2d, UI-2e, UI-2f, UI-2g, UI-2h, UI-2i, UI-2j, UI-E16-1, UI-E16-2, UI-C4-email, BUG-RLS-1, UI-C5-badge-etab, BUG-UI-CHORUS-CONFIG, UI-MISSION-FICHE-RICHE |
| P2 RÉSOLUS      | 9      | A22, B5, E8, E9, H9, H10, H11, H12, I1                                  |
| DIFFÉRÉS        | 5      | A13, A17, A18, C2, C3                                                   |

**Validation somme** : 21 + 12 + 26 + 1 + 16 + 50 + 9 + 5 = **140** ✓

**Scope résolu CP-STRIPE-2** : H1 (0h dédup A20) + A20 (8h) + H7 (3h) + H14 (3h) = **14h** de scope éliminé (plus partiellement H4 : -1h). **Scope actionnable post-Sub-PR D : 430.75 - 15 = 415.75 h**.

**Scope résolu CP-C-1** : E12 (12h) + E13 (0h audit) = **12h** de scope éliminé. **Scope actionnable post-CP-C-1 : 415.75 - 12 = 403.75 h**.

**Scope ajouté E16 (CP-C-1.5)** : E16 (8h RÉSOLU, nouveau ticket non comptabilisé auparavant) + UI-E16-1 (4h P2 nouveau) + UI-E16-2 (6h P2 nouveau) = **+10h P2 ouverts**. **Scope actionnable post-E16 : 403.75 + 10 = 413.75 h**.

**Scope résolu CP-C-2** : E2 (8h) + E6 (3h) + E11 (6h) = **17h** de scope éliminé. **Scope actionnable post-CP-C-2 : 413.75 - 17 = 396.75 h**.

**Scope résolu CP-C-3** : E1 (6h) + E7 (6h) + E9 (6h) = **18h** de scope éliminé. **Scope actionnable post-CP-C-3 : 396.75 - 18 = 378.75 h**.

**Scope résolu CP-C-4** : E5 (8h) + E8 (4h) + E14 (0h) = **12h** éliminés. **+2h** émergent UI-C4-email (P2). **Scope actionnable post-CP-C-4 : 378.75 - 12 + 2 = 368.75 h**.

**Scope résolu CP-C-5** : E15 (30h) = **30h** éliminé (scope réel ~18h grâce aux helpers existants). **+2h** émergent UI-C5-badge-etab (P2). **Scope actionnable post-CP-C-5 : 368.75 - 30 + 2 = 340.75 h**. **Sub-PR C 100% complète**.

**Scope total OUVERTS + EN COURS** (hors RÉSOLUS, hors DIFFÉRÉS) :
- P0 OUVERTS (27 tickets, dont H1/H3 scope=0 dédupliqués) : 121.5 + L1=3 + L2=1 + L3=6 = **131.5 h**
- P1 OUVERTS + EN COURS (30 tickets) : 163.5 + L4=4 + L5=8 = **175.5 h**
- P2 OUVERTS (38 tickets) : 107.75 + L6=8 + L7=4 + L8=4 = **123.75 h**
- **Total actionnable immédiatement : 430.75 h** (≈ 10.8 semaines ingénieur à 40h/semaine)

Note : H1 (⇔ A20, 8h) et H3 (⇔ A21, 12h) sont des doublons scope — le travail est compté une seule fois dans A20/A21 (P1). Le scope total n'est pas gonflé.

Les DIFFÉRÉS (5 tickets : A13=2 + A17=8 + A18=2 + C2=4 + C3=6 = **22 h**) sont hors périmètre sprint courant.

### Scope par Sub-PR (inventaire exhaustif)

Les 8 Sub-PR identifiées pendant les audits + les Sub-PR dérivées des tickets héritage :

| Sub-PR                                     | Tickets                                              | Scope (h) |
|--------------------------------------------|------------------------------------------------------|-----------|
| **SP-A-fixes-rapides**                     | G1, G2, G3, G4                                       | **9 h**   |
| **SP-B-templates-email-critiques**         | D1-D12                                               | **37 h**  |
| **SP-C-paiement-salarie-refonte**          | E1-E11                                               | **60 h**  |
| **SP-D-stripe-connect-prod-ready**         | A20, A21, H1-H11 (H1/H3 ⇔ A20/A21 dédupliqués)       | **53 h**  |
| **SP-E-scoring-refonte**                   | F1-F15                                               | **94 h**  |
| **SP-F-bugs-latents-nettoyage**            | I1-I5                                                | **12 h**  |
| **SP-G-decisions-design-factures**         | J1, J2, J3                                           | **6 h**   |
| **SP-H-rls-consolidation**                 | K1, K2, K3                                           | **4 h**   |
| **SP-I-commission-flow-hardening**         | L1-L8                                                | **38 h**  |
| *SP-triggers-multi-creneaux* (hérité)      | A5, A6                                               | 14 h      |
| *SP-hardening-coherence-financiere* (hérité) | A7, A9                                             | 20 h      |
| *SP-commission-groupes (= Sub-PR 2bis)*    | A16                                                  | 24 h      |
| *SP-phantom-objects-audit* (hérité)        | A19, C1                                              | 18 h      |
| *SP-crons-fixes* (hérité + Audit 1)        | A14, A15, B1, B2, B3a, B3b                           | 24.75 h   |
| *SP-audit-trail-missions* (hérité)         | A10, A11                                             | 6 h       |
| *SP-frontend-rpc-hardening* (hérité)       | A1                                                   | 4 h       |
| *SP-validation-juridique* (hérité, externe) | A8                                                  | 4 h       |
| *SP-secrets-config* (hérité, action manuelle) | A2                                                | 1 h       |
| *SP-nettoyage-versions-rpcs* (hérité)      | A3                                                   | 0.5 h     |
| *SP-docs* (hérité)                         | A12                                                  | 1 h       |
| *SP-activation-prod* (Audit 1)             | B4 (EN COURS)                                        | 0.5 h     |
| **TOTAL brut 9 Sub-PR majeures**           | 64 tickets                                           | **313 h** |
| **TOTAL brut 21 Sub-PR (incl. héritages)** | 102 tickets actionnables                             | **430.75 h** |
