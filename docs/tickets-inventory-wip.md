# Inventaire exhaustif tickets — Sub-PR 2 sexies

**Date** : 2026-04-20
**Snapshot base** : commit `f6e8d279` (tech-debt.md restauré, 428 lignes)
**Branche** : `claude/fix-merge-conflicts-2Y4ph`
**Sources couvertes** : A (héritage) + B (Audit 1 Crons) + C (Audit 2 Objets fantômes) + D (Audit 3 Templates email)
**Sources à venir** : E (Audit 4 Paiement salarié), F (Audit 5 Scoring), G (Audit 6 Statut REMPLACEE), H (Audit 7 Stripe Connect), I (Migrations), J (Smoke tests), K (Audit 8 RLS — placeholder)

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
| A20  | T12 Câblage stripe_payment_intent_id sur factures_honoraires           | P1       | OUVERT   | Héritage                        | 8         | SP-stripe-connect-prod-ready      |
| A21  | T13 Edge function process-stripe-refunds à finaliser                   | P1       | OUVERT   | Héritage                        | 12        | SP-stripe-connect-prod-ready      |
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

---

## Comptage automatique

**Total tickets** : 47

| Catégorie       | Nombre | IDs                                                                     |
|-----------------|--------|-------------------------------------------------------------------------|
| P0 OUVERTS      | 6      | B1, B2, B3a, D1, D2, D3                                                 |
| P0 RÉSOLUS      | 2      | A24, A25                                                                |
| P1 OUVERTS      | 12     | A5, A7, A8, A16, A20, A21, D4, D5, D6, D7, D11, D12                     |
| P1 EN COURS     | 1      | B4                                                                      |
| P1 RÉSOLUS      | 3      | A4, A23, A26                                                            |
| P2 OUVERTS      | 16     | A1, A2, A3, A6, A9, A10, A11, A12, A14, A15, A19, B3b, C1, D8, D9, D10  |
| P2 RÉSOLUS      | 2      | A22, B5                                                                 |
| DIFFÉRÉS        | 5      | A13, A17, A18, C2, C3                                                   |

**Validation somme** : 6 + 2 + 12 + 1 + 3 + 16 + 2 + 5 = **47** ✓

**Scope total OUVERTS + EN COURS** (hors RÉSOLUS, hors DIFFÉRÉS) :
- P0 OUVERTS (6 tickets) : B1=10 + B2=6 + B3a=0.5 + D1=3 + D2=2 + D3=4 = **25.5 h**
- P1 OUVERTS + EN COURS (13 tickets) : A5=12 + A7=16 + A8=4 + A16=24 + A20=8 + A21=12 + B4=0.5 + D4=3 + D5=2 + D6=2 + D7=2 + D11=2 + D12=8 = **95.5 h**
- P2 OUVERTS (16 tickets) : A1=4 + A2=1 + A3=0.5 + A6=2 + A9=4 + A10=3 + A11=3 + A12=1 + A14=6 + A15=2 + A19=16 + B3b=0.25 + C1=2 + D8=4 + D9=3 + D10=2 = **53.75 h**
- **Total actionnable immédiatement : 174.75 h** (≈ 4.5 semaines ingénieur)

Les DIFFÉRÉS (5 tickets : A13=2 + A17=8 + A18=2 + C2=4 + C3=6 = **22 h**) sont hors périmètre sprint courant.
