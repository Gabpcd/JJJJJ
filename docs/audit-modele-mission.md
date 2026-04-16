# Audit exhaustif — Modèle de données `missions`

> Date : 2026-04-16
> Auteur : Claude (assisté par Gabrielle Picard)
> Objectif : Documenter l'état actuel du modèle mission avant refonte multi-créneaux

---

## Table des matières

1. [Modèle actuel — Schéma de la table `missions`](#1-modèle-actuel)
2. [Cartographie des usages (frontend, edge functions, triggers, RPCs)](#2-cartographie-des-usages)
3. [Bug B — Analyse `serie_id` et missions récurrentes](#3-bug-b)
4. [Contraintes légales — Pauses et déclaration horaire en intérim santé](#4-contraintes-légales)
5. [Proposition de modèle cible — `mission_creneaux`](#5-modèle-cible)
6. [Plan de migration des 268 missions existantes](#6-plan-de-migration)
7. [Impact estimé sur le code](#7-impact-estimé)
8. [Décisions à arbitrer par Gabrielle](#8-décisions)

---

## 1. Modèle actuel

### 1.1 Colonnes de la table `missions` (52 colonnes en prod)

| Colonne | Type | Nullable | Rôle |
|---|---|---|---|
| `id` | uuid | NOT NULL | PK, `uuid_generate_v4()` |
| `etablissement_id` | uuid | NOT NULL | FK → etablissements |
| `intitule` | text | NOT NULL | Titre affiché |
| `description` | text | NULL | Détail libre |
| `profession_requise` | enum `type_profession` | NOT NULL | IDE, AS, etc. |
| `service` | text | NULL | Service hospitalier |
| **`debut_le`** | **timestamptz** | **NOT NULL** | **Début unique du créneau** |
| **`fin_le`** | **timestamptz** | **NOT NULL** | **Fin unique du créneau** |
| **`duree_heures`** | **numeric** | NULL | **Calculé par trigger = (fin_le − debut_le) en heures** |
| `taux_horaire_base` | numeric | NOT NULL | Taux horaire soignant (€/h) |
| `taux_rist_plafonne` | numeric | NULL | Taux après plafond RIST |
| `rist_plafond_applique` | boolean | NULL | Flag RIST |
| `heures_nuit` | numeric | NULL | Heures de nuit déclarées |
| `heures_dimanche` | numeric | NULL | Heures dimanche déclarées |
| `heures_ferie` | numeric | NULL | Heures férié déclarées |
| `montant_majoration_nuit` | numeric | NULL | Calculé par trigger |
| `montant_majoration_dimanche` | numeric | NULL | Calculé par trigger |
| `montant_majoration_ferie` | numeric | NULL | Calculé par trigger |
| `taux_ifm` | numeric | NULL | Default 0.10 (10%) |
| `taux_icp` | numeric | NULL | Default 0.10 (10%) |
| `montant_ifm` | numeric | NULL | Calculé par trigger |
| `montant_icp` | numeric | NULL | Calculé par trigger |
| `total_brut` | numeric | NULL | Calculé : base + majorations |
| `net_a_payer` | numeric | NULL | Calculé : brut + IFM + ICP |
| `net_estime` | numeric | NULL | Calculé : net × 0.78 |
| `taux_commission` | numeric | NULL | Default 15% |
| `montant_commission_ht` | numeric | NULL | Calculé par trigger |
| `montant_commission_tva` | numeric | NULL | Calculé par trigger (20%) |
| `montant_commission_ttc` | numeric | NULL | Calculé par trigger |
| `commission_facturee` | boolean | NULL | Default false |
| `est_urgente` | boolean | NULL | Flag urgence |
| `niveau_urgence` | integer | NULL | 0-3 |
| `statut` | enum `statut_mission` | NULL | Default OUVERTE |
| `soignant_assigne_id` | uuid | NULL | FK → soignants |
| `facture_id` | uuid | NULL | Lien facture commission |
| `type_paiement_soignant` | text | NULL | BULLETIN_PAIE / HONORAIRES |
| `numero_note_honoraires` | text | NULL | Numéro note d'honoraires |
| `mode_paiement_soignant` | text | NULL | DIRECT / STRIPE_CONNECT |
| `stripe_payment_intent_id` | text | NULL | Stripe PI commission |
| `stripe_transfer_id` | text | NULL | Stripe Transfer soignant |
| `mode_attribution` | text | NULL | PREMIER_ARRIVE / CANDIDATURE |
| `type_contrat_recherche` | text | NOT NULL | TOUS / SALARIE / LIBERAL |
| `choix_contrat_soignant` | text | NULL | Choix contrat du soignant |
| `code_arrivee` | text | NULL | Code pointage arrivée |
| `code_depart` | text | NULL | Code pointage départ |
| `yousign_id_procedure` | text | NULL | ID procédure Yousign |
| `yousign_statut` | text | NULL | Default AUCUN |
| `serie_id` | uuid | NULL | Groupement série (JAMAIS utilisé — voir §3) |
| `annulee_le` | timestamptz | NULL | Date annulation |
| `annulee_par` | uuid | NULL | Qui a annulé |
| `motif_annulation` | text | NULL | Raison annulation |
| `terminee_le` | timestamptz | NULL | Date fin effective |
| `cree_le` | timestamptz | NULL | Default now() |
| `modifie_le` | timestamptz | NULL | Default now() |

### 1.2 Problème structurel

**Une mission = un seul créneau horaire continu** (`debut_le` → `fin_le`).

Pas de colonne `nombre_heures_pause`. Le `duree_heures` est calculé comme le span brut `(fin_le − debut_le)`. Si un soignant travaille 7h–12h + 14h–19h (10h effectives, 2h de pause), le modèle stocke `debut_le=07:00, fin_le=19:00, duree_heures=12.0` — **2h fantômes facturées**.

### 1.3 Trigger financier principal — `fn_calculer_financier_mission`

Déclenché `BEFORE INSERT OR UPDATE OF taux_horaire_base, duree_heures, debut_le, fin_le, heures_nuit, heures_dimanche, heures_ferie, taux_ifm, taux_icp`.

Logique séquentielle :
1. `duree_heures = COALESCE(duree_heures, EXTRACT(EPOCH FROM (fin_le − debut_le)) / 3600)`
2. Plafond RIST → `taux_effectif`
3. `brut_base = taux_effectif × duree_heures`
4. Majorations nuit/dimanche/férié
5. `total_brut = base + majorations`
6. `IFM = total_brut × taux_ifm` (10%), `ICP = total_brut × taux_icp` (10%)
7. `net_a_payer = total_brut + IFM + ICP`
8. `net_estime = net_a_payer × 0.78`
9. Commission : `montant_commission_ht = total_brut × taux_commission / 100`, TVA 20%

**Point critique** : le step 1 utilise `fin_le − debut_le` sans soustraire aucune pause. Tout le calcul financier en aval hérite de cette erreur.

### 1.4 Volumétrie en prod (2026-04-16)

| Métrique | Valeur |
|---|---|
| Total missions | 268 |
| TERMINEE | 213 |
| OUVERTE | 2 |
| ASSIGNEE | 1 |
| ANNULEE (toutes variantes) | 43 |
| Avec `serie_id` non NULL | **0** |
| Durée moyenne | 9.4h |
| Durée min / max | 4h / 144h |
| Missions > 24h | 3 (toutes ANNULEE) |
| Missions multi-jour (debut_le.date ≠ fin_le.date) | 42 |

### 1.5 Tables liées (FK → missions)

23 tables référencent `missions.id` :
`candidatures`, `contrats_mission`, `presences`, `evaluations`, `conversations`, `messages_mission`, `litiges`, `reclamations`, `reclamations_scoring`, `paiements_mission`, `paiements_soignant`, `cotisations_sociales`, `factures`, `factures_honoraires`, `factor_advances`, `stripe_transfers`, `assurances_mission`, `partages_rib`, `conformite_travail`, `calendar_events_sync`, `shift_affectations`

### 1.6 Table `shifts` (système planning parallèle)

| Colonne | Type |
|---|---|
| id | uuid |
| etablissement_id | uuid |
| equipe_id | uuid |
| intitule | text |
| service | text |
| jour | date |
| heure_debut | time |
| heure_fin | time |
| profession_requise | text |
| nb_postes | integer |
| nb_pourvus | integer |
| recurrence | text |
| notes | text |

**0 lignes en prod.** Lié à `shift_affectations` (shift_id, soignant_id, mission_id) — également 0 lignes. Système de planning par équipes prévu mais jamais utilisé.

### 1.7 Triggers sur `missions` (30 triggers uniques, ~56 event bindings)

**Financiers (BEFORE):**
- `trg_calculer_financier` → `fn_calculer_financier_mission()`
- `dec_mission_z_finance` → `dec_calculer_finance_mission()`
- `dec_mission_commission` → `dec_calculer_commission()`
- `dec_net_estime` → `dec_calculer_net_estime()`
- `trg_auto_heures_majorees` → `fn_trg_auto_heures_majorees()`
- `trg_auto_commission_facturee` → `fn_trg_auto_commission_facturee()`
- `trg_protect_mission_financials` → `fn_protect_mission_financials()`

**Validation (BEFORE):**
- `dec_chevauchement` → `dec_refuser_chevauchement_soignant()`
- `dec_mission_plafond_48h` → `dec_verifier_plafond_48h()`
- `dec_mission_repos_11h` → `dec_verifier_repos_11h()`
- `dec_mission_passee` → `dec_refuser_mission_passee()`
- `dec_anti_double` → `dec_anti_double_assignation()`
- `dec_bloquer_modif_acceptee` → `dec_bloquer_modif_apres_acceptation()`
- `dec_eligibilite_liberal` → `dec_verifier_eligibilite_liberal()`
- `dec_facture_impayee` → `dec_bloquer_si_facture_impayee()`
- `dec_profession_etab` → `dec_verifier_profession_etablissement()`
- `dec_docs_fin_mission` → `dec_verifier_docs_jusqua_fin()`
- `dec_proteger_mission_soignant` → `dec_proteger_mission_soignant()`
- `dec_mission_plafond_rist` → `dec_appliquer_plafond_rist()`
- `trg_valider_transition_statut` → `fn_valider_transition_statut_mission()`
- `trg_coherence_statut_soignant` → `fn_trg_coherence_statut_soignant()`
- `dec_type_contrat_compat` / `trg_valider_type_contrat_mission` → contrat checks
- `trg_verifier_docs_avant_debut` → `dec_verifier_docs_avant_debut()`

**Business logic (AFTER):**
- `dec_annuler_contrat` → `dec_annuler_contrat_si_mission_annulee()`
- `dec_bonus_urgence` → `dec_bonus_urgence()`
- `dec_heures_plateforme` → `dec_incrementer_heures_plateforme()`
- `dec_maj_compteurs` → `dec_maj_compteurs_soignant()`
- `dec_mission_liberee` → `dec_alerte_mission_liberee()`
- `dec_mission_maj_fiabilite` → `dec_mettre_a_jour_fiabilite()`
- `dec_premiere_mission` → `dec_premiere_mission()`
- `dec_penalite_annulation` → `dec_penalite_annulation_tardive()`
- `dec_type_paiement_mission` → `dec_definir_type_paiement()`
- `dec_notif_mission` → `dec_notifier_changement_mission()`
- `dec_codes_pointage` → `dec_generer_codes_pointage()`
- `trg_auto_facture_honoraires` → `fn_trg_auto_facture_honoraires()`
- `trg_auto_cotisations` → `dec_auto_calculer_cotisations()`
- `trg_auto_proposition_pool_urgence` → `fn_trg_auto_proposition_pool_urgence()`
- `trg_conversation_assignation` → `dec_creer_conversation_assignation()`
- `trg_email_mission_terminee` → `fn_trg_email_mission_terminee()`
- `trg_rappel_evaluation` → `dec_rappel_evaluation()`
- `trg_sms_annulation_tardive` → `fn_trg_sms_annulation_tardive()`
- `trg_sms_mission_urgente` → `fn_trg_sms_mission_urgente()`

---

## 2. Cartographie des usages

### 2.1 Edge Functions (Supabase)

| Fonction | Accès missions | Champs timing | Champs financiers | Usage |
|---|---|---|---|---|
| `generate-invoice` | READ | `debut_le`, `fin_le`, `duree_heures` | `net_a_payer`, `total_brut`, `montant_commission_ht` | Génération PDF/XML facture honoraires |
| `stripe-connect-pay-mission` | READ | — | `montant_commission_ttc`, `net_a_payer` | Stripe Checkout (commission + honoraires) |
| `create-mission-payment` | READ | — | `montant_commission_ttc` | Stripe PaymentIntent commission |
| `stripe-webhook` | WRITE | — | Écrit `commission_facturee`, `mode_paiement_soignant` | Callback post-paiement |
| `calendar-feed` | READ | `debut_le`, `fin_le` | `taux_horaire_base` | Génération iCal (.ics) |
| `calendar-sync` | READ | `debut_le`, `fin_le` | `taux_horaire_base` | Sync calendrier externe |
| `api-v1` | READ+WRITE | `debut_le`, `fin_le` | `taux_horaire_base` | API REST partenaires |
| `factor-request-advance` | READ | — | — | Lit `intitule` uniquement |
| `send-email` | READ (count) | — | — | Vérification d'autorisation |
| `email-cron` | Indirect (RPC) | `heure_debut` via RPC | — | Rappels J-1 |

**Impact refonte** : `generate-invoice` est le plus critique — il construit la description de la ligne facture à partir de `debut_le`/`fin_le`/`duree_heures`. Avec multi-créneaux, cette description devra itérer sur N créneaux.

### 2.2 Frontend — Fichiers WRITE (création/modification de missions)

| Fichier | Mode | Champs écrits |
|---|---|---|
| `components/FormulaireMission.tsx` | WRITE (RPC `fn_creer_mission`) | `debut_le`, `fin_le`, `taux_horaire_base` |
| `components/FormulaireRecurrence.tsx` | WRITE (génère `CreneauFlex[]` → 1 mission par créneau) | `debut`/`fin` par créneau → `debut_le`/`fin_le` |
| `pages/ModifierMission.tsx` | WRITE (RPC `fn_modifier_mission_etablissement`) | `intitule`, `description`, `service` uniquement (timing NON modifiable) |

**Note** : en mode récurrence, `FormulaireRecurrence` génère un tableau de `CreneauFlex` (debut, fin, dureeHeures) — mais chaque créneau crée **une mission distincte**. Il n'y a pas de multi-créneaux au sein d'une même mission.

### 2.3 Frontend — Fichiers READ (73 fichiers touchent les champs timing/financiers)

**Pages avec décomposition financière complète** (lisent tous les champs financiers) :
- `pages/DetailMission.tsx` — Vue étab, tous champs + majorations
- `pages/DetailMissionSoignant.tsx` — Vue soignant, tous champs + IFM/ICP
- `pages/DetailPresencesMission.tsx` — Fiche présence détaillée
- `pages/ExportPaie.tsx` — Export CSV paie (Standard/Silae/Sage)

**Pages avec résumé financier** (net_a_payer, total_brut, taux_horaire) :
- `pages/MesGains.tsx`, `pages/HistoriqueMissions.tsx`, `pages/AttestationHeures.tsx`
- `pages/ChargesSociales.tsx`, `pages/ContratMission.tsx`
- `pages/ListeMissions.tsx`, `pages/MissionsSoignant.tsx`, `pages/RechercheMissions.tsx`
- `pages/MesFacturesHonoraires.tsx`, `pages/FacturationEtablissement.tsx`
- `pages/DashboardEtablissement.tsx`, `pages/ObligationsFinancieres.tsx`
- `components/BandeauPaiementDeclare.tsx`, `components/DecompositionFinanciere.tsx`

**Pages timing uniquement** (debut_le, fin_le, duree_heures) :
- `pages/PresencesSoignant.tsx`, `pages/PresencesEtablissement.tsx`
- `pages/Parcours3200h.tsx`, `pages/PoolUrgenceEtablissement.tsx`
- `pages/LitigesEtablissement.tsx`, `pages/LitigesSoignant.tsx`
- `components/CalendrierMensuel.tsx`, `components/PlanningHebdomadaire.tsx`
- `components/CompteurHebdomadaire.tsx`, `components/BlocConformite.tsx`

**Pages admin** :
- `admin/AdminMissions.tsx` — `debut_le`, `fin_le`, `duree_heures`, `taux_horaire_base`, `net_estime`
- `admin/AdminFinances.tsx` — `total_brut`, `montant_commission_ht/ttc`
- `admin/AdminFacturation.tsx`, `admin/AdminImpayees.tsx` — Tous champs financiers
- `admin/AdminDashboard.tsx` — `montant_commission_ht/tva`, `commission_facturee`
- `admin/AdminCalendrier.tsx` — `debut_le`, `fin_le`
- `admin/AdminDetailUtilisateur.tsx` — `debut_le`, `fin_le`, `taux_horaire_base`, `duree_heures`, `net_a_payer`
- `admin/AdminGroupes.tsx` — `montant_commission_ht/ttc`

### 2.4 RPCs et fonctions DB touchant le timing

| RPC | Champs timing | Usage |
|---|---|---|
| `fn_creer_mission` | `p_debut_le`, `p_fin_le` | Création mission unique |
| `fn_creer_serie` | Array de `{debut, fin}` | Création série (1 mission par créneau) |
| `fn_modifier_mission_etablissement` | — (timing non modifiable) | Modification post-création |
| `fn_calculer_financier_mission` | `debut_le`, `fin_le` → `duree_heures` | Trigger calcul |
| `dec_refuser_chevauchement_soignant` | `debut_le`, `fin_le` | Validation anti-chevauchement |
| `dec_verifier_plafond_48h` | `debut_le`, `fin_le`, `duree_heures` | Plafond hebdo 48h |
| `dec_verifier_repos_11h` | `debut_le`, `fin_le` | Repos inter-mission 11h |
| `fn_trg_auto_heures_majorees` | `debut_le`, `fin_le` | Auto-détection heures nuit/dimanche/férié |
| `fn_email_rappels_j1` | `debut_le` → `heure_debut` | Email rappel J-1 |
