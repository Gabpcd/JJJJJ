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

---

## 3. Bug B — `serie_id` et missions récurrentes

### 3.1 État de `serie_id`

La colonne `serie_id` (uuid, nullable) existe sur la table `missions` en prod. **Aucune des 268 missions n'a un `serie_id` non NULL** (0 sur 268).

Historique :
- La colonne semble provenir du schéma initial Lovable
- Un trigger `dec_limite_serie` a été créé puis **droppé** dans la migration `20260316215405` avec le commentaire "Fix broken trigger referencing non-existent serie_id column" — incohérence historique
- La RPC `fn_annuler_serie` existe dans les types TS mais aucune migration SQL ne la définit
- `fn_creer_mission` a un paramètre `p_serie_id` dans la signature TS, mais **le corps SQL ne l'utilise pas**

### 3.2 Comment les séries fonctionnent aujourd'hui

Le mécanisme actuel de séries est **100% client-side** :

1. `FormulaireRecurrence.tsx` génère un tableau de `CreneauFlex[]` (un par jour)
2. `FormulaireMission.tsx` injecte un tag `[SERIE_ID:SERIE_${Date.now()}_${random}]` dans le champ `description` de chaque mission
3. `DetailSerieSoignant.tsx` retrouve les missions d'une série via `ilike('description', '%[SERIE_ID:…]%')`
4. `fn_creer_serie` (RPC) crée N missions indépendantes en batch

**Chaque mission d'une série est un row indépendant** avec son propre `debut_le`/`fin_le`. La colonne `serie_id` n'est jamais peuplée. Le groupement se fait par pattern matching dans `description`.

### 3.3 Le vrai Bug B : impossibilité de modéliser les pauses intra-journée

Le problème n'est pas les séries (missions récurrentes sur plusieurs jours) — celles-ci fonctionnent en créant une mission par jour.

**Le Bug B est l'absence de multi-créneaux au sein d'une même mission-jour.**

Exemple concret :
- Mission "IDE — Nuit urgences week-end"
- Travail réel : 19h–00h + 01h–07h (pause de 1h pour repas)
- Modèle actuel : `debut_le = 19:00, fin_le = 07:00, duree_heures = 12.0`
- Réalité : 11h travaillées, 1h de pause
- **Erreur de facturation : +1h facturée à tort** → impact sur `total_brut`, `net_a_payer`, `IFM`, `ICP`, commission

Exemple jour classique :
- Mission "IDE — Clinique Test"
- Travail réel : 7h–12h + 14h–19h (pause déjeuner 2h)
- Modèle actuel : `debut_le = 07:00, fin_le = 19:00, duree_heures = 12.0`
- Réalité : 10h travaillées
- **Erreur de facturation : +2h facturées à tort**

### 3.4 Impact financier estimé du Bug B

Sur 213 missions TERMINEE, si on estime qu'environ 50% ont une pause non déclarée d'1h en moyenne :
- ~106 missions × 1h × taux moyen ~25€/h = **~2 650 € de surfacturation brute**
- Avec IFM+ICP (20%) : **~3 180 €**
- Commission Jolene (15% de total_brut) : **~400 € de surcommission**

Ce ne sont que des estimations, mais le risque juridique est réel (voir §4).

### 3.5 Table `shifts` — alternative avortée

La table `shifts` (jour + heure_debut + heure_fin) aurait pu servir de système multi-créneaux, mais :
- 0 lignes en prod
- Pas d'intégration avec le formulaire de création de mission
- `shift_affectations` a un `mission_id` FK mais n'est pas peuplé
- Le système de shifts est un module planning indépendant, pas un sous-système de la mission

**Conclusion** : `shifts` n'est pas la bonne base pour les multi-créneaux. Il faut une table dédiée `mission_creneaux` (voir §5).

---

## 4. Contraintes légales — Pauses et déclaration horaire

### 4.1 Code du travail — Temps de pause obligatoire

**Article L.3121-16** : Au-delà de 6h de travail effectif continu, le salarié bénéficie d'un temps de pause d'au moins 20 minutes. Pour les intérimaires, cette obligation s'applique via l'article L.1251-21 (conditions de travail identiques aux salariés de l'entreprise utilisatrice).

**Conséquence pour Jolene** : toute mission de 6h+ sans pause déclarée est juridiquement suspecte. Or, 97.7% des missions en prod font > 6h (avg 9.4h). Le modèle actuel ne permet pas de déclarer les pauses — donc **aucune mission ne déclare de pause**, même celles qui en ont une dans la réalité.

### 4.2 Convention collective et spécificités santé

Les conventions collectives hospitalières (FHP, FEHAP, Croix-Rouge, fonction publique hospitalière) imposent des temps de pause spécifiques :
- **Jour** : 20 min minimum après 6h, souvent 30 min–1h en pratique (pause déjeuner)
- **Nuit** : 20 min minimum, souvent intégrée au poste (pas toujours déductible)
- **12h (garde)** : 2 × 20 min minimum, souvent 1h cumulée

La distinction pause déductible / non déductible dépend de la convention de l'établissement. Certaines pauses (repas sur place, astreinte passive) sont considérées comme du temps de travail effectif.

### 4.3 Factur-X et Chorus Pro

**Factur-X (EN16931)** : La facture doit indiquer la quantité et l'unité (heures) de la prestation. Si la facture indique 12h mais que la réalité est 10h + 2h pause, c'est une **fausse déclaration** susceptible de requalification en fraude fiscale (article 1741 CGI).

**Chorus Pro** : Pour les établissements publics (EHPAD publics, CH, CHU), la facture soumise à Chorus Pro est un document comptable officiel. L'écart entre heures déclarées et heures effectives peut entraîner un rejet au contrôle de la Cour des comptes.

### 4.4 Impact sur la facture d'honoraires (soignant libéral)

Le soignant libéral émet une facture d'honoraires basée sur `net_a_payer`. Si ce montant est gonflé par des heures de pause incluses :
- Le soignant déclare un CA supérieur à la réalité → charges sociales URSSAF majorées
- L'établissement paie plus que le service rendu → litige potentiel
- Jolene touche une commission sur un montant erroné

### 4.5 Recommandation

Le modèle cible DOIT permettre :
1. **Déclarer les créneaux effectifs** (ex: 7h–12h + 14h–19h) → la pause de 12h–14h est implicite
2. **Calculer `duree_heures` comme la somme des créneaux** (10h, pas 12h)
3. **Optionnellement** : distinguer pause déductible vs non déductible (pour les gardes de nuit)

La solution la plus simple et la plus conforme est le **multi-créneaux par mission** : la somme des `(fin − debut)` de chaque créneau donne le temps de travail effectif.

---

## 5. Proposition de modèle cible — `mission_creneaux`

### 5.1 Nouvelle table `mission_creneaux`

```sql
CREATE TABLE public.mission_creneaux (
  id          uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  mission_id  uuid NOT NULL REFERENCES missions(id) ON DELETE CASCADE,
  debut       timestamptz NOT NULL,
  fin         timestamptz NOT NULL,
  est_pause   boolean NOT NULL DEFAULT false,
  -- est_pause = true → créneau de pause comptée (garde de nuit)
  -- est_pause = false → créneau de travail effectif
  ordre       smallint NOT NULL DEFAULT 1,
  cree_le     timestamptz NOT NULL DEFAULT now(),

  CONSTRAINT ck_creneau_coherent CHECK (fin > debut),
  CONSTRAINT ck_creneau_max_24h CHECK (EXTRACT(EPOCH FROM (fin - debut)) <= 86400),
  UNIQUE (mission_id, ordre)
);

CREATE INDEX idx_mc_mission ON mission_creneaux(mission_id);
```

### 5.2 Invariants

- **Au moins 1 créneau** par mission (enforced par trigger ou RPC, pas par CHECK)
- Les créneaux d'une même mission ne se chevauchent pas
- `missions.debut_le` = `MIN(debut)` des créneaux, `missions.fin_le` = `MAX(fin)` des créneaux (dénormalisé pour compatibilité)
- `missions.duree_heures` = somme des `(fin − debut)` des créneaux WHERE `est_pause = false`

### 5.3 Modification du trigger financier

Le trigger `fn_calculer_financier_mission` change à l'étape 1 :

```sql
-- AVANT (actuel)
v_duree := COALESCE(NEW.duree_heures,
  EXTRACT(EPOCH FROM (NEW.fin_le - NEW.debut_le)) / 3600.0);

-- APRÈS (multi-créneaux)
SELECT COALESCE(SUM(EXTRACT(EPOCH FROM (fin - debut)) / 3600.0), 0)
INTO v_duree
FROM mission_creneaux
WHERE mission_id = NEW.id AND est_pause = false;
-- Fallback si 0 créneaux (migration en cours) :
IF v_duree = 0 THEN
  v_duree := EXTRACT(EPOCH FROM (NEW.fin_le - NEW.debut_le)) / 3600.0;
END IF;
NEW.duree_heures := v_duree;
```

Le reste du trigger (RIST, majorations, IFM, ICP, commission) ne change pas — tout dépend de `v_duree`.

### 5.4 Colonnes conservées sur `missions` (rétrocompatibilité)

| Colonne | Comportement |
|---|---|
| `debut_le` | Dénormalisé = `MIN(mc.debut)` — mis à jour par trigger sur `mission_creneaux` |
| `fin_le` | Dénormalisé = `MAX(mc.fin)` — mis à jour par trigger sur `mission_creneaux` |
| `duree_heures` | Recalculé = somme créneaux effectifs |

Ces colonnes restent pour que les 73 fichiers frontend qui lisent `debut_le`/`fin_le`/`duree_heures` **continuent de fonctionner sans modification**. Seuls les fichiers d'écriture (FormulaireMission) et d'affichage détaillé (DetailMission) doivent être adaptés.

### 5.5 Création simplifiée (mission mono-créneau)

Pour la majorité des missions (un seul créneau), le workflow reste identique :
1. L'établissement saisit debut + fin dans le formulaire
2. La RPC `fn_creer_mission` crée la mission + 1 row dans `mission_creneaux`
3. Le trigger de sync met à jour `missions.debut_le`/`fin_le`/`duree_heures`

Pour les missions multi-créneaux :
1. L'établissement saisit N créneaux dans un formulaire étendu
2. La RPC crée la mission + N rows dans `mission_creneaux`
3. Les pauses sont implicites (gaps entre créneaux)

### 5.6 `serie_id` — Nettoyage

Recommandation : **conserver `serie_id`** mais le rendre fonctionnel :
- `fn_creer_serie` doit écrire le `serie_id` en DB (pas seulement dans `description`)
- Supprimer le pattern `[SERIE_ID:...]` dans `description`
- Ajouter un index `idx_missions_serie ON missions(serie_id) WHERE serie_id IS NOT NULL`

---

## 6. Plan de migration des 268 missions existantes

### 6.1 Stratégie : migration rétroactive mono-créneau

Chaque mission existante (268 rows) devient une mission avec **1 créneau** dans `mission_creneaux`. C'est factuellement correct : le modèle actuel ne permettait pas de déclarer les pauses, donc toutes les missions historiques sont stockées comme un bloc continu. On ne réécrit pas l'histoire.

### 6.2 Script de migration

```sql
-- Étape 1 : Créer la table mission_creneaux
-- (voir §5.1)

-- Étape 2 : Peupler avec 1 créneau par mission existante
INSERT INTO mission_creneaux (mission_id, debut, fin, est_pause, ordre)
SELECT id, debut_le, fin_le, false, 1
FROM missions
WHERE debut_le IS NOT NULL AND fin_le IS NOT NULL;
-- Résultat attendu : 268 rows insérés

-- Étape 3 : Trigger de sync mission_creneaux → missions
CREATE OR REPLACE FUNCTION fn_sync_mission_creneaux()
RETURNS TRIGGER LANGUAGE plpgsql SECURITY DEFINER AS $$
BEGIN
  UPDATE missions SET
    debut_le = (SELECT MIN(debut) FROM mission_creneaux WHERE mission_id = COALESCE(NEW.mission_id, OLD.mission_id) AND NOT est_pause),
    fin_le   = (SELECT MAX(fin)   FROM mission_creneaux WHERE mission_id = COALESCE(NEW.mission_id, OLD.mission_id) AND NOT est_pause),
    duree_heures = (SELECT SUM(EXTRACT(EPOCH FROM (fin - debut)) / 3600.0) FROM mission_creneaux WHERE mission_id = COALESCE(NEW.mission_id, OLD.mission_id) AND NOT est_pause)
  WHERE id = COALESCE(NEW.mission_id, OLD.mission_id);
  RETURN NEW;
END;
$$;

CREATE TRIGGER trg_sync_creneaux
  AFTER INSERT OR UPDATE OR DELETE ON mission_creneaux
  FOR EACH ROW EXECUTE FUNCTION fn_sync_mission_creneaux();

-- Étape 4 : RLS sur mission_creneaux
ALTER TABLE mission_creneaux ENABLE ROW LEVEL SECURITY;
CREATE POLICY mc_select_own ON mission_creneaux FOR SELECT USING (
  EXISTS (SELECT 1 FROM missions m WHERE m.id = mission_id
    AND (m.etablissement_id = mon_etablissement_id()
      OR m.soignant_assigne_id = mon_soignant_id()
      OR est_admin()))
);
CREATE POLICY mc_insert_etab ON mission_creneaux FOR INSERT WITH CHECK (
  EXISTS (SELECT 1 FROM missions m WHERE m.id = mission_id
    AND m.etablissement_id = mon_etablissement_id())
);
-- UPDATE/DELETE : service_role uniquement (pas de modification directe par le client)
```

### 6.3 Ordre d'exécution

1. **Sub-PR 1** (data model) : CREATE TABLE + migration + trigger sync + RLS + GRANTs
2. **Sub-PR 2** (formulaire) : Adapter `FormulaireMission.tsx` pour saisir N créneaux
3. **Sub-PR 3** (downstream) : Adapter `fn_calculer_financier_mission`, `generate-invoice`, `calendar-feed/sync`, `api-v1`
4. **Sub-PR 4** (affichage) : Adapter `DetailMission`, `DetailMissionSoignant`, `ExportPaie`

### 6.4 Rétrocompatibilité pendant la migration

Pendant la phase transitoire (Sub-PR 1 déployé, Sub-PR 2 pas encore) :
- Le formulaire continue de créer des missions mono-créneau
- La RPC `fn_creer_mission` est modifiée pour aussi insérer 1 row dans `mission_creneaux`
- Le trigger financier utilise le fallback `fin_le − debut_le` si 0 créneaux
- **Aucune régression** : les 73 fichiers frontend lisent toujours `missions.debut_le`/`fin_le`/`duree_heures`

---

## 7. Impact estimé sur le code

### 7.1 Fichiers à modifier obligatoirement

| Fichier | Type de changement | Effort |
|---|---|---|
| **Migration SQL** | CREATE TABLE + INSERT + triggers + RLS | Moyen |
| `fn_calculer_financier_mission` | Step 1 : lire `mission_creneaux` au lieu de `fin_le − debut_le` | Faible |
| `fn_creer_mission` (RPC) | Ajouter INSERT into `mission_creneaux` après INSERT mission | Faible |
| `fn_creer_serie` (RPC) | Idem pour chaque mission de la série | Faible |
| `FormulaireMission.tsx` | Ajouter UI multi-créneaux (optionnel, un ou N) | **Élevé** |
| `FormulaireRecurrence.tsx` | Adapter pour supporter multi-créneaux par jour | Moyen |
| `generate-invoice/index.ts` | Description ligne facture : itérer sur créneaux | Moyen |
| `calendar-feed/index.ts` | Générer 1 event iCal par créneau (ou 1 event avec breaks) | Faible |
| `calendar-sync/index.ts` | Idem | Faible |
| `api-v1/index.ts` | POST /missions : accepter array de créneaux | Moyen |
| `types.ts` (Supabase) | Régénérer (`supabase gen types`) | Auto |

### 7.2 Fichiers impactés mais sans modification nécessaire (rétrocompatibilité)

Les 60+ fichiers frontend qui lisent `missions.debut_le`/`fin_le`/`duree_heures` **ne changent pas** grâce à la dénormalisation. Les valeurs restent à jour via le trigger de sync.

### 7.3 Fichiers à adapter pour affichage amélioré (optionnel, post-migration)

| Fichier | Amélioration |
|---|---|
| `DetailMission.tsx` | Afficher la liste des créneaux au lieu d'un seul horaire |
| `DetailMissionSoignant.tsx` | Idem |
| `DetailPresencesMission.tsx` | Pointage par créneau |
| `ExportPaie.tsx` | Détailler les créneaux dans le CSV |
| `ContratMission.tsx` | Lister les créneaux dans le contrat |
| `NoteHonoraires.tsx` | Détailler les créneaux sur la note d'honoraires |

### 7.4 Triggers à auditer (impact potentiel)

| Trigger | Impact | Raison |
|---|---|---|
| `dec_refuser_chevauchement_soignant` | **Moyen** | Doit vérifier les chevauchements créneau par créneau, pas mission par mission |
| `dec_verifier_plafond_48h` | **Moyen** | Doit sommer les créneaux effectifs, pas les spans |
| `dec_verifier_repos_11h` | **Moyen** | Le repos 11h se calcule entre le dernier créneau d'une mission et le premier de la suivante |
| `fn_trg_auto_heures_majorees` | **Élevé** | Doit détecter les heures nuit/dimanche/férié par créneau |
| `dec_generer_codes_pointage` | **Faible** | 1 code par mission suffit (pas par créneau) |
| Autres triggers | **Aucun** | Ne touchent pas au timing |

### 7.5 Résumé quantitatif

| Catégorie | Nombre |
|---|---|
| Fichiers à modifier (obligatoire) | ~11 |
| Triggers à adapter | 4–5 |
| Fichiers rétrocompatibles (0 changement) | ~60 |
| Fichiers à améliorer (optionnel) | ~6 |
| Tables impactées | 1 créée, 1 modifiée (missions) |

---

## 8. Décisions à arbitrer par Gabrielle

### D1 — Périmètre de la pause

**Option A** : Les pauses sont implicites (gaps entre créneaux). Pas de flag `est_pause`.
- Pro : Simple, pas d'ambiguïté
- Con : Impossible de distinguer pause payée (garde de nuit) vs non payée

**Option B** : Le flag `est_pause` permet de déclarer des créneaux de pause comptabilisée.
- Pro : Conforme aux conventions collectives hospitalières (pause nuit intégrée)
- Con : Complexité formulaire + triggers

**Recommandation** : Option B, mais `est_pause = false` par défaut. Le formulaire ne montre le toggle "pause comptée" que pour les missions de nuit (21h–7h).

### D2 — Nombre max de créneaux par mission

- **2** : couvre 95% des cas (matin + après-midi)
- **4** : couvre les gardes fragmentées (rare)
- **Illimité** : flexible mais risque d'abus

**Recommandation** : MAX 4, avec CHECK constraint.

### D3 — Migration des 42 missions multi-jour

42 missions ont `debut_le.date ≠ fin_le.date`. Certaines sont des gardes (19h → 7h le lendemain, normal). 3 missions > 24h sont toutes ANNULEE.

**Question** : Faut-il les éclater en multi-créneaux automatiquement (ex: 19h–7h → 1 créneau de nuit), ou les laisser en mono-créneau ?

**Recommandation** : Les laisser en mono-créneau (état historique fidèle). Seules les nouvelles missions bénéficieront du multi-créneaux.

### D4 — Timing de la refonte vs finalisation PDF facture

La facture d'honoraires (generate-invoice) utilise `debut_le`/`fin_le`/`duree_heures` dans la description de ligne. Deux stratégies :

**Option A** : Refonte modèle AVANT template PDF v2.1
- Pro : Le PDF affichera directement les créneaux
- Con : Retarde la livraison de la facturation

**Option B** : Template PDF v2.1 MAINTENANT avec le modèle actuel, puis adapter quand multi-créneaux arrive
- Pro : Facturation opérationnelle plus vite
- Con : Double travail sur le template

**Recommandation** : Option A (c'est la décision déjà prise par Gabrielle le 2026-04-16).

### D5 — Sort de `serie_id`

**Option A** : Rendre `serie_id` fonctionnel (écrire en DB, indexer, supprimer le hack `[SERIE_ID:...]` dans description)
**Option B** : Supprimer `serie_id`, garder le système actuel par tag dans description

**Recommandation** : Option A — c'est propre, et le coût de migration est quasi nul (colonne existe déjà, juste la peupler).

### D6 — Sort de la table `shifts`

**Option A** : Conserver `shifts`/`shift_affectations` comme système planning indépendant
**Option B** : Supprimer (0 données, 0 usage)

**Recommandation** : Conserver mais ne pas y toucher. C'est un module planning futur distinct du multi-créneaux mission.

### D7 — Rétroactivité sur les missions TERMINEE

Faut-il demander aux établissements de corriger les pauses sur les 213 missions terminées ?

**Recommandation** : Non. Les missions terminées restent en l'état (mono-créneau). Le multi-créneaux ne s'applique qu'aux nouvelles missions. Les factures déjà émises ne sont pas rétroactivement modifiées — c'est le principe de l'annuité comptable.

---

> **Prochaine étape** : Gabrielle valide les 7 décisions ci-dessus, puis on découpe en Sub-PRs.
