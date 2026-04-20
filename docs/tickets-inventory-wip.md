# Inventaire exhaustif tickets — Sub-PR 2 sexies

**Date** : 2026-04-20
**Snapshot base** : commit `f6e8d279` (tech-debt.md restauré, 428 lignes)
**Branche** : `claude/fix-merge-conflicts-2Y4ph`
**Sources couvertes** : A (héritage) + B (Audit 1 Crons) + C (Audit 2 Objets fantômes) + D (Audit 3 Templates email) + E (Audit 4 Paiement salarié) + F (Audit 5 Scoring soignant)
**Sources à venir** : G (Audit 6 Statut REMPLACEE), H (Audit 7 Stripe Connect), I (Migrations), J (Smoke tests), K (Audit 8 RLS — placeholder)

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
| E1   | Harmoniser 2 logiques blocage divergentes (trigger 30j vs RPC 60j) → chemin unique | P0 | OUVERT | Audit 4 : Paiement salarié    | 6         | SP-C-paiement-salarie-refonte     |
| E2   | Créer 3 templates email manquants (RAPPEL_PAIEMENT_J7 + PAIEMENT_RETARD_J30 + PUBLICATION_SUSPENDUE) | P0 | OUVERT | Audit 4 : Paiement salarié | 8 | SP-C-paiement-salarie-refonte     |
| E3   | Pont pg_net → send-email (RPC écrit notif in-app uniquement, aucun email) | P0 | OUVERT | Audit 4 : Paiement salarié      | 6         | SP-C-paiement-salarie-refonte     |
| E4   | Déduplication notif par `type` dédié (aujourd'hui titre LIKE '%retard%' fragile) | P0 | OUVERT | Audit 4 : Paiement salarié   | 3         | SP-C-paiement-salarie-refonte     |
| E5   | Statut EXPIRE + transition automatique après échéance                  | P1       | OUVERT   | Audit 4 : Paiement salarié      | 8         | SP-C-paiement-salarie-refonte     |
| E6   | Exploiter colonne `relance_2_le` (dead column, jamais écrite)          | P1       | OUVERT   | Audit 4 : Paiement salarié      | 3         | SP-C-paiement-salarie-refonte     |
| E7   | Unfreeze automatique quand étab régularise (aujourd'hui bloqué à vie)  | P1       | OUVERT   | Audit 4 : Paiement salarié      | 6         | SP-C-paiement-salarie-refonte     |
| E8   | Basculer source de vérité sur `echeance_le` (aujourd'hui fin_le + INTERVAL) | P2   | OUVERT   | Audit 4 : Paiement salarié      | 4         | SP-C-paiement-salarie-refonte     |
| E9   | Ajouter colonnes `bloque_le`, `raison_blocage`, historique blocages    | P2       | OUVERT   | Audit 4 : Paiement salarié      | 6         | SP-C-paiement-salarie-refonte     |
| E10  | Aligner seuils J+7/J+30/expiration (prod J+30/J+15/J+60 vs annoncés)   | P0       | OUVERT   | Audit 4 : Paiement salarié      | 4         | SP-C-paiement-salarie-refonte     |
| E11  | Implémenter reminder J+7 (zéro code actuel)                            | P0       | OUVERT   | Audit 4 : Paiement salarié      | 6         | SP-C-paiement-salarie-refonte     |
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

---

## Comptage automatique

**Total tickets** : 73

| Catégorie       | Nombre | IDs                                                                     |
|-----------------|--------|-------------------------------------------------------------------------|
| P0 OUVERTS      | 18     | B1, B2, B3a, D1, D2, D3, E1, E2, E3, E4, E10, E11, F1, F2, F3, F4, F13, F15 |
| P0 RÉSOLUS      | 2      | A24, A25                                                                |
| P1 OUVERTS      | 21     | A5, A7, A8, A16, A20, A21, D4, D5, D6, D7, D11, D12, E5, E6, E7, F5, F6, F7, F8, F9, F14 |
| P1 EN COURS     | 1      | B4                                                                      |
| P1 RÉSOLUS      | 3      | A4, A23, A26                                                            |
| P2 OUVERTS      | 21     | A1, A2, A3, A6, A9, A10, A11, A12, A14, A15, A19, B3b, C1, D8, D9, D10, E8, E9, F10, F11, F12 |
| P2 RÉSOLUS      | 2      | A22, B5                                                                 |
| DIFFÉRÉS        | 5      | A13, A17, A18, C2, C3                                                   |

**Validation somme** : 18 + 2 + 21 + 1 + 3 + 21 + 2 + 5 = **73** ✓

**Scope total OUVERTS + EN COURS** (hors RÉSOLUS, hors DIFFÉRÉS) :
- P0 OUVERTS (18 tickets) : 58.5 + F1=6 + F2=8 + F3=3 + F4=6 + F13=24 + F15=4 = **109.5 h**
- P1 OUVERTS + EN COURS (22 tickets) : 112.5 + F5=6 + F6=3 + F7=3 + F8=4 + F9=3 + F14=12 = **143.5 h**
- P2 OUVERTS (21 tickets) : 63.75 + F10=4 + F11=2 + F12=6 = **75.75 h**
- **Total actionnable immédiatement : 328.75 h** (≈ 8.5 semaines ingénieur)

Les DIFFÉRÉS (5 tickets : A13=2 + A17=8 + A18=2 + C2=4 + C3=6 = **22 h**) sont hors périmètre sprint courant.

### Scope par Sub-PR (en construction)

| Sub-PR                                   | Tickets                                                   | Scope (h) |
|------------------------------------------|-----------------------------------------------------------|-----------|
| SP-C-paiement-salarie-refonte (Source E) | E1, E2, E3, E4, E5, E6, E7, E8, E9, E10, E11              | **60 h**  |
| SP-E-scoring-refonte (Source F)          | F1, F2, F3, F4, F5, F6, F7, F8, F9, F10, F11, F12, F13, F14, F15 | **94 h**  |
