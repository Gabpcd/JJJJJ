# CP5a — Refonte triggers et taux configurables

> Date : 2026-04-16
> Statut : AUDIT — validation partie par partie avant implémentation

---

## Partie 1 : Nouvelles colonnes

### 1.1 Colonnes ajoutées sur `etablissements`

Deux colonnes pour les bornes horaires de nuit configurables (D4). Les taux de majoration existent déjà.

| Colonne | Type | Default | CHECK | Raison |
|---|---|---|---|---|
| `heure_debut_nuit` | time | `'21:00'` | `BETWEEN '19:00' AND '23:59'` | Art. L3122-2 : « tout travail entre 21h et 6h ». Conventions collectives permettent 19h–23h59. Type `time` pour supporter 21h30, 22h30 etc. |
| `heure_fin_nuit` | time | `'06:00'` | `BETWEEN '04:00' AND '08:00'` | Idem, fin de nuit 4h–8h selon convention. |

**Colonnes existantes — ajout de planchers légaux (D7) :**

| Colonne existante | Default actuel | CHECK à ajouter | Justification légale |
|---|---|---|---|
| `taux_majoration_nuit_pourcent` | 25.00 | `>= 25` | Plancher prudent au-dessus des minima CCN FHP n°2264 art. 82.1/82.2 pour couvrir FEHAP, CCU, Croix-Rouge, FPH. Ticket tech-debt T1 : validation avocat santé pré-lancement. |
| `taux_majoration_dimanche_pourcent` | 50.00 | `>= 25` | Idem — plancher prudent. CCN FHP art. 82.1 impose 20% min, relevé à 25% par précaution. |
| `taux_majoration_ferie_pourcent` | 100.00 | `>= 50` | CCN FHP art. 82.2 : 50% min hors 1er mai. Art. L3133-6 : 100% pour le 1er mai. Ticket tech-debt T1. |

**Pas de colonne ajoutée pour les taux de majoration eux-mêmes** — ils existent déjà :
- `taux_majoration_nuit_pourcent` (default 25)
- `taux_majoration_dimanche_pourcent` (default 50)
- `taux_majoration_ferie_pourcent` (default 100)
- `taux_commission_negocie` (default 15)
- `rist_taux_base_horaire` (default 25)

### 1.2 Colonnes snapshot ajoutées sur `missions`

Huit colonnes `*_fige` + un timestamp (D6). Toutes nullable, `NULL` = « pas encore figé » (mission OUVERTE).

| Colonne | Type | Source (copiée au gel) | Rôle |
|---|---|---|---|
| `taux_horaire_base_fige` | numeric | `missions.taux_horaire_base` | Taux horaire figé à l'assignation |
| `taux_majoration_nuit_fige` | numeric | `etablissements.taux_majoration_nuit_pourcent` | % majoration nuit figé |
| `taux_majoration_dimanche_fige` | numeric | `etablissements.taux_majoration_dimanche_pourcent` | % majoration dimanche figé |
| `taux_majoration_ferie_fige` | numeric | `etablissements.taux_majoration_ferie_pourcent` | % majoration férié figé |
| `heure_debut_nuit_fige` | time | `etablissements.heure_debut_nuit` | Borne début nuit figée |
| `heure_fin_nuit_fige` | time | `etablissements.heure_fin_nuit` | Borne fin nuit figée |
| `taux_commission_fige` | numeric | `etablissements.taux_commission_negocie` | % commission figé |
| `fige_le` | timestamptz | `now()` | Horodatage du gel |

**Sémantique COALESCE dans les triggers calculateurs :**
```
taux_effectif = COALESCE(_fige, valeur_etab, default_legal)
```
Tant que `_fige IS NULL`, les triggers utilisent les valeurs live de l'établissement (comportement actuel inchangé pour les missions OUVERTE).

### 1.2b Cycle de vie `taux_commission` et `taux_horaire_base` vs `*_fige`

**`taux_horaire_base`** (colonne existante sur `missions`) :
- Éditable uniquement tant que `fige_le IS NULL` (mission OUVERTE). Renseignée par l'étab à la création de la mission.
- `taux_horaire_base_fige` : snapshot de `taux_horaire_base` au moment de la transition OUVERTE → ASSIGNEE.
- **Après gel (`fige_le IS NOT NULL`) : `taux_horaire_base` est immutable.** Toute tentative de modification est bloquée par le trigger de gel (Partie 2). Exception : bypass admin tracé via session vars `jolene.admin_override_gel` + `jolene.admin_override_reason` avec audit dans `invoice_audit_log`.
- **Pas de deprecation** de `taux_horaire_base`. Elle reste utilisée en affichage, dans les RPCs, dans le frontend. `_fige` est interne aux triggers financiers.

**Règle d'immutabilité post-gel** (implémentée dans le trigger de gel, Partie 2) :
```sql
-- Bloque toute modification de taux_horaire_base après gel
IF NEW.taux_horaire_base IS DISTINCT FROM OLD.taux_horaire_base
   AND OLD.fige_le IS NOT NULL THEN
  -- Bypass admin tracé
  IF current_setting('jolene.admin_override_gel', true) = NEW.id::text
     AND COALESCE(current_setting('jolene.admin_override_reason', true), '') != '' THEN
    INSERT INTO invoice_audit_log (invoice_id, action, performed_by, payload_before)
    SELECT fh.id, 'TAUX_HORAIRE_MODIFIED_POST_GEL', auth.uid(),
      jsonb_build_object(
        'reason', current_setting('jolene.admin_override_reason', true),
        'mission_id', NEW.id,
        'old_taux', OLD.taux_horaire_base,
        'new_taux', NEW.taux_horaire_base
      )
    FROM factures_honoraires fh
    WHERE fh.mission_id = NEW.id AND fh.statut NOT IN ('BROUILLON', 'ANNULEE')
    LIMIT 1;
    -- Si pas de facture, log dans une table d'audit directe
    IF NOT FOUND THEN
      INSERT INTO invoice_audit_log (action, performed_by, payload_before)
      VALUES ('TAUX_HORAIRE_MODIFIED_POST_GEL', auth.uid(),
        jsonb_build_object(
          'reason', current_setting('jolene.admin_override_reason', true),
          'mission_id', NEW.id,
          'old_taux', OLD.taux_horaire_base,
          'new_taux', NEW.taux_horaire_base
        ));
    END IF;
  ELSE
    RAISE EXCEPTION 'Modification de taux_horaire_base interdite après gel (fige_le=%). Pour corriger : annuler la mission et en créer une nouvelle, ou utiliser le bypass admin tracé (jolene.admin_override_gel + jolene.admin_override_reason).',
      OLD.fige_le USING ERRCODE = 'check_violation';
  END IF;
END IF;
```

**`taux_commission`** (colonne existante sur `missions`, default 15) :
- Initialisée par `fn_calculer_financier_mission` depuis `etablissements.taux_commission_negocie`.
- `taux_commission_fige` : snapshot au gel via `COALESCE(missions.taux_commission, etab.taux_commission_negocie, 15)`. Après gel, c'est `_fige` qui est lu par le calculateur financier.
- **Pas de deprecation** de `taux_commission`. Elle continue d'exister comme valeur "live" et reste utile pour l'affichage et les RPCs.
- **État actuel en base** (vérifié 2026-04-16) : 0 missions avec `taux_commission IS NULL`, 133 à 15%, 135 à un taux différent. Le COALESCE dans le backfill ne changera rien en pratique, mais reste en sécurité pour les futurs INSERT sans trigger.

**Lecture par `fn_calculer_financier_mission` :**

| Phase mission | `taux_horaire_base` lu depuis | Taux majorations lus depuis | Commission lue depuis |
|---|---|---|---|
| OUVERTE (`_fige IS NULL`) | `missions.taux_horaire_base` | `etablissements.taux_majoration_*_pourcent` | `COALESCE(missions.taux_commission, etab.taux_commission_negocie, 15)` |
| ASSIGNEE+ (`_fige NOT NULL`) | `missions.taux_horaire_base_fige` | `missions.taux_majoration_*_fige` | `missions.taux_commission_fige` |

**Backfill des 268 missions existantes** : `taux_commission_fige` est backfillé via `COALESCE(missions.taux_commission, etab.taux_commission_negocie, 15)` — cascade identique à la lecture OUVERTE pour cohérence. `taux_horaire_base_fige` depuis `missions.taux_horaire_base` (pas de COALESCE nécessaire, colonne NOT NULL).

### 1.3 Impact sur les protecteurs existants

Les 8 colonnes `*_fige` doivent être ajoutées aux listes de freeze dans :

| Protecteur | Contexte sync (`sync_in_progress=true`) | Contexte non-admin |
|---|---|---|
| `dec_proteger_mission_soignant` | Freeze `*_fige` à OLD (le sync ne les touche pas) | Freeze `*_fige` à OLD |
| `fn_protect_mission_financials` | Freeze `*_fige` à OLD | Freeze `*_fige` à OLD |

**Raison** : seul le trigger de gel (Partie 2) doit écrire les `*_fige`. Tout autre contexte (sync, soignant, même etab-admin hors transition de statut) doit les laisser intacts.

### 1.4 Migration des 268 missions existantes

| Statut | Nb missions | Action `*_fige` |
|---|---|---|
| `OUVERTE` | Variable | `NULL` (pas encore assignée — correct) |
| `ASSIGNEE`, `EN_COURS` | Variable | Backfill depuis l'établissement actuel |
| `TERMINEE` | Variable | Backfill depuis l'établissement actuel |
| `ANNULEE_*`, `ABSENCE`, `LITIGE` | Variable | Backfill depuis l'établissement actuel |

**Requête de backfill :**
```sql
UPDATE missions m SET
  taux_horaire_base_fige = m.taux_horaire_base,
  taux_majoration_nuit_fige = e.taux_majoration_nuit_pourcent,
  taux_majoration_dimanche_fige = e.taux_majoration_dimanche_pourcent,
  taux_majoration_ferie_fige = e.taux_majoration_ferie_pourcent,
  heure_debut_nuit_fige = COALESCE(e.heure_debut_nuit, '21:00'::time),
  heure_fin_nuit_fige = COALESCE(e.heure_fin_nuit, '06:00'::time),
  taux_commission_fige = COALESCE(m.taux_commission, e.taux_commission_negocie, 15),
  fige_le = NULL  -- gel rétroactif CP5a, date réelle de transition OUVERTE→ASSIGNEE inconnue
FROM etablissements e
WHERE e.id = m.etablissement_id
  AND m.statut != 'OUVERTE';
```

**`fige_le = NULL` pour les missions backfillées** : `modifie_le` reflète la dernière modification (pas la transition OUVERTE → ASSIGNEE). Plutôt que d'inventer une date fausse, on laisse `NULL` pour distinguer clairement les gels rétroactifs (CP5a) des gels traçables (post-CP5a, `fige_le = now()` au moment exact de la transition).

**Vérification pré-backfill : cohérence avec les factures existantes :**

Avant exécution du backfill, lancer cette vérification pour détecter toute divergence entre les taux backfillés et les montants déjà facturés :

```sql
-- Dry-run : détecter les missions TERMINEE facturées où le backfill
-- créerait une incohérence avec la facture émise
SELECT
  m.id AS mission_id,
  fh.numero AS facture_numero,
  m.total_brut AS total_brut_actuel,
  fh.montant_ht AS montant_ht_facture,
  m.taux_horaire_base AS taux_horaire_mission,
  e.taux_majoration_nuit_pourcent AS taux_nuit_etab_actuel,
  e.taux_majoration_dimanche_pourcent AS taux_dim_etab_actuel,
  e.taux_majoration_ferie_pourcent AS taux_fer_etab_actuel,
  e.taux_commission_negocie AS taux_comm_etab_actuel,
  m.taux_commission AS taux_comm_mission_actuel
FROM missions m
JOIN etablissements e ON e.id = m.etablissement_id
JOIN factures_honoraires fh ON fh.mission_id = m.id
  AND fh.statut NOT IN ('BROUILLON', 'ANNULEE')
WHERE m.statut = 'TERMINEE';
```

Si divergence détectée → rapport soumis pour validation avant exécution.
En pratique : 0 divergence attendue (taux étab jamais modifiés depuis création des comptes test).

**Risque du backfill** : les taux de l'établissement ont pu changer entre l'assignation et maintenant. Pour les 251 missions seeded, ce risque est nul (données test, bientôt purgées par CP6). Pour les 17 missions organiques, les taux étab n'ont jamais été modifiés depuis la création du compte → backfill exact.

**Pattern** : `DISABLE TRIGGER USER` + backfill + `ENABLE TRIGGER USER` (playbook standard, cf. `/docs/bulk-updates-playbook.md`).

### 1.5 SQL proposé (DDL)

```sql
-- ── etablissements : bornes nuit configurables ──
-- Type time pour supporter les demi-heures (21h30, 22h30 etc.)
ALTER TABLE public.etablissements
  ADD COLUMN IF NOT EXISTS heure_debut_nuit time DEFAULT '21:00',
  ADD COLUMN IF NOT EXISTS heure_fin_nuit time DEFAULT '06:00';

ALTER TABLE public.etablissements
  ADD CONSTRAINT chk_heure_debut_nuit CHECK (heure_debut_nuit BETWEEN '19:00' AND '23:59'),
  ADD CONSTRAINT chk_heure_fin_nuit CHECK (heure_fin_nuit BETWEEN '04:00' AND '08:00');

-- ── etablissements : planchers légaux sur taux existants ──
-- Planchers calibrés au-dessus des minima CCN FHP n°2264 art. 82.1/82.2
-- pour couvrir également FEHAP, CCU, Croix-Rouge, FPH sans validation
-- juridique formelle à ce stade. Ticket tech-debt T1 : validation
-- avocat santé avant lancement public.
ALTER TABLE public.etablissements
  ADD CONSTRAINT chk_taux_maj_nuit_min CHECK (taux_majoration_nuit_pourcent >= 25),   -- Prudent > CCN FHP
  ADD CONSTRAINT chk_taux_maj_dim_min CHECK (taux_majoration_dimanche_pourcent >= 25), -- Prudent > CCN FHP art. 82.1 (20%)
  ADD CONSTRAINT chk_taux_maj_fer_min CHECK (taux_majoration_ferie_pourcent >= 50);    -- CCN FHP art. 82.2

-- ── missions : colonnes snapshot ──
ALTER TABLE public.missions
  ADD COLUMN IF NOT EXISTS taux_horaire_base_fige numeric,
  ADD COLUMN IF NOT EXISTS taux_majoration_nuit_fige numeric,
  ADD COLUMN IF NOT EXISTS taux_majoration_dimanche_fige numeric,
  ADD COLUMN IF NOT EXISTS taux_majoration_ferie_fige numeric,
  ADD COLUMN IF NOT EXISTS heure_debut_nuit_fige time,
  ADD COLUMN IF NOT EXISTS heure_fin_nuit_fige time,
  ADD COLUMN IF NOT EXISTS taux_commission_fige numeric,
  ADD COLUMN IF NOT EXISTS fige_le timestamptz;
```

---

## Partie 2 : Trigger de gel `fn_geler_mission_a_assignation`

### 2.1 Matrice des transitions de statut

**Machine d'états existante** (source : `fn_valider_transition_statut_mission`) :

```
OUVERTE → ASSIGNEE                    (assignation soignant)
OUVERTE → ANNULEE_PAR_ETABLISSEMENT   (étab annule avant assignation)
ASSIGNEE → EN_COURS                   (mission démarre)
ASSIGNEE → OUVERTE                    (soignant se désiste)
ASSIGNEE → ANNULEE_PAR_ETABLISSEMENT
ASSIGNEE → ANNULEE_PAR_SOIGNANT
ASSIGNEE → ABSENCE                    (no-show)
EN_COURS → TERMINEE
EN_COURS → ABSENCE
EN_COURS → LITIGE
EN_COURS → ANNULEE_PAR_ETABLISSEMENT
LITIGE → TERMINEE                     (litige résolu)
LITIGE → ANNULEE_PAR_ETABLISSEMENT
```

Note : un admin peut forcer TOUTE transition (`est_admin()` bypass dans `fn_valider_transition_statut_mission`).

**Action du trigger de gel par transition :**

| Avant | Après | Action `*_fige` | Raison |
|---|---|---|---|
| `OUVERTE` | `ASSIGNEE` | **GEL** : remplir les 8 `_fige` + `fige_le = now()` | Première assignation = formation du contrat |
| `OUVERTE` | `ANNULEE_PAR_ETABLISSEMENT` | Rien (`_fige` restent `NULL`) | Jamais assignée, pas de contrat |
| `ASSIGNEE` | `EN_COURS` | Rien (déjà gelé) | Contrat en cours d'exécution |
| `ASSIGNEE` | `OUVERTE` | **DEGEL** : `_fige = NULL`, `fige_le = NULL` | Soignant se désiste, contrat rompu, mission rouverte |
| `ASSIGNEE` | `ANNULEE_PAR_ETABLISSEMENT` | **CONSERVER** les `_fige` | Audit trail : quel contrat a été annulé |
| `ASSIGNEE` | `ANNULEE_PAR_SOIGNANT` | **CONSERVER** les `_fige` | Idem |
| `ASSIGNEE` | `ABSENCE` | **CONSERVER** les `_fige` | Idem — le no-show s'est produit sous ces conditions |
| `EN_COURS` | `TERMINEE` | Rien (déjà gelé) | Fin normale |
| `EN_COURS` | `ABSENCE` | **CONSERVER** | — |
| `EN_COURS` | `LITIGE` | Rien (déjà gelé) | — |
| `EN_COURS` | `ANNULEE_PAR_ETABLISSEMENT` | **CONSERVER** | — |
| `LITIGE` | `TERMINEE` | Rien (déjà gelé) | Litige résolu |
| `LITIGE` | `ANNULEE_PAR_ETABLISSEMENT` | **CONSERVER** | — |

**Résumé** : 3 actions possibles :
- **GEL** : uniquement `OUVERTE → ASSIGNEE`
- **DEGEL** : uniquement `ASSIGNEE → OUVERTE` (soignant se désiste)
- **CONSERVER** : toutes les transitions depuis un état gelé vers un état terminal/annulé

Pas de transition directe `OUVERTE → EN_COURS` dans la machine d'états → le gel se fait toujours via `ASSIGNEE`.

### 2.2 Comportement sur ré-attribution (Q1)

**Scénario** : Mission M assignée à soignant A (gel). A se désiste (ASSIGNEE → OUVERTE). M réassignée à soignant B (OUVERTE → ASSIGNEE).

**Analyse des 3 options :**

| Option | Comportement | Avantage | Inconvénient |
|---|---|---|---|
| **A — Garder** | `_fige` restent aux valeurs du gel initial (soignant A). B hérite des taux de A. | Simple (pas de degel). | B voit des taux potentiellement obsolètes. Si l'étab a changé ses taux entre A et B, le contrat de B est basé sur des conditions périmées. Confusion UX. |
| **B — Re-snapshotter** | `_fige` écrasés au nouveau gel sans passer par NULL. `fige_le` mis à jour. | Taux à jour pour B. | Perte de traçabilité : on ne sait plus quels taux étaient proposés à A. Pas de distinction entre premier gel et re-gel. |
| **C — NULL puis re-gel** | `ASSIGNEE → OUVERTE` : `_fige = NULL`. `OUVERTE → ASSIGNEE` : nouveau gel complet. | Chaque assignation = transaction complète. B obtient les taux actuels. Traçabilité via `fige_le` (date du nouveau gel). Distinction claire gel rétroactif (`fige_le = NULL`) / premier gel / re-gel. | Deux actions trigger au lieu d'une (degel + gel). Légèrement plus complexe. |

**Recommandation : Option C.**

Arguments :
1. **Cohérence produit** : le soignant B n'a pas négocié avec les conditions de A. Chaque acceptation de mission est un nouvel engagement.
2. **Traçabilité** : `fige_le` du nouveau gel = date réelle de la nouvelle assignation. Pas de confusion avec l'ancien gel.
3. **Simplicité conceptuelle** : un état OUVERTE a toujours `_fige = NULL`. Un état post-ASSIGNEE a toujours `_fige NOT NULL` (sauf les backfillés CP5a avec `fige_le = NULL`).
4. **Impact performances** : négligeable — le degel est un simple `SET _fige = NULL` sur 8 colonnes + 1 timestamp. Le re-gel est le même coût que le premier gel.

**Perte de traçabilité du gel de A** : si nécessaire pour des audits futurs, on pourrait logger le degel dans l'audit log (`GEL_RESET`, payload = ancien snapshot). Mais pour V1, pas nécessaire — les conditions de A n'ont jamais donné lieu à facturation (la mission n'a jamais été TERMINEE sous A).

### 2.3 Champs bloqués après gel (Q3)

**Principe** : après gel (`fige_le IS NOT NULL`), les champs qui constituent le « contrat visible du soignant » sont immutables. Les champs mécaniques (calculés par triggers) restent libres.

**Champs contractuels — BLOQUÉS après gel :**

| Champ | Justification |
|---|---|
| `taux_horaire_base` | Le taux horaire est la base du contrat financier. |
| `intitule` | Le titre de la mission, vu par le soignant lors de l'acceptation. Coquilles → bypass admin tracé. |
| `profession_requise` | La profession requise ne peut pas changer après qu'un soignant de cette profession a accepté. |
| `taux_horaire_base_fige` | Snapshot — immutable par définition. |
| `taux_majoration_nuit_fige` | Idem. |
| `taux_majoration_dimanche_fige` | Idem. |
| `taux_majoration_ferie_fige` | Idem. |
| `heure_debut_nuit_fige` | Idem. |
| `heure_fin_nuit_fige` | Idem. |
| `taux_commission_fige` | Idem. |
| `fige_le` | Idem — horodatage du gel, jamais modifiable. |

**Message d'erreur paramétré** (identique pour tous les champs bloqués) :
```sql
RAISE EXCEPTION 'Modification du champ "%" interdite après assignation (gel du %). Pour corriger une coquille, contactez le support Jolene pour un override admin tracé. Pour modifier le contenu substantiel, annuler la mission et en créer une nouvelle.',
  v_champ_modifie, OLD.fige_le
  USING ERRCODE = 'check_violation';
```

**Champs retirés de la liste bloquée (décisions Gabrielle) :**

| Champ | Raison du retrait | Ticket tech-debt |
|---|---|---|
| `description` | Reçoit des ajouts utiles post-assignation (infos logistiques, corrections typo). Bloquer = friction inutile. | T3 (P3) : audit trail modifications description post-gel |
| `service` | Les étabs santé réaffectent légitimement un soignant d'un service à un autre le jour même (réorg interne, absence collègue). Usage réel du terrain. | T4 (P3) : notifier le soignant par email si service modifié post-gel |

**Champs mécaniques — NON BLOQUÉS (protégés par d'autres triggers) :**

| Champ | Protégé par | Raison |
|---|---|---|
| `total_brut`, `net_a_payer`, `net_estime` | `fn_calculer_financier_mission` (recalcule) + `dec_proteger_mission_soignant` (freeze CP3) | Calculés par triggers, pas éditables directement. |
| `montant_majoration_*`, `montant_ifm`, `montant_icp` | Idem | Idem. |
| `montant_commission_*`, `taux_commission` | Idem | `taux_commission` reste live, `_fige` prend le relais dans les calculs. |
| `heures_nuit`, `heures_dimanche`, `heures_ferie` | `fn_trg_auto_heures_majorees` (recalcule) | Calculés depuis les créneaux. |
| `duree_heures`, `debut_le`, `fin_le`, `nb_creneaux` | `fn_sync_mission_creneaux` (sync) | Maintenus par le sync trigger. |
| `soignant_assigne_id` | Flow assignation/désistement | Doit changer lors d'une ré-attribution. |
| `statut` | `fn_valider_transition_statut_mission` | Géré par la machine d'états. |
| `description` | — (non bloqué, ticket T3) | Ajouts logistiques post-assignation légitimes. |
| `service` | — (non bloqué, ticket T4) | Réaffectation service légitime. |
| `est_urgente`, `niveau_urgence` | — | L'étab peut légitimement modifier l'urgence post-assignation (ex: situation qui s'aggrave). |
| `mode_attribution`, `type_contrat_recherche` | — | Administratif, pas contractuel vis-à-vis du soignant. |
| `commission_facturee` | Flow facturation | Flag mécanique. |
| `taux_ifm`, `taux_icp` | Légaux (10% fixe) | Taux légaux, pas négociables. |
| `etablissement_id` | `dec_proteger_mission_soignant` | Déjà protégé (freeze to OLD). Pas de duplication dans le trigger de gel. |
| `rist_plafond_applique`, `taux_rist_plafonne` | `fn_calculer_financier_mission` | Calculés. |

**Total : 11 champs bloqués** (3 contractuels + 8 `_fige` / `fige_le`).

### 2.7 Risques identifiés (préliminaire — complété en Message C)

**P4 — `est_urgente` changeant post-gel :**

Vérifié : `fn_trg_sms_mission_urgente` (trigger `trg_sms_mission_urgente`, AFTER INSERT OR UPDATE) n'envoie un SMS que si `NEW.statut = 'OUVERTE' AND NEW.est_urgente = TRUE`. Donc un changement `est_urgente = FALSE → TRUE` sur une mission ASSIGNEE ne déclenche PAS le SMS pool. **Pas de risque de notification parasite.**

Cependant, aucun trigger ne notifie le soignant assigné quand `est_urgente` change post-assignation. Ce n'est pas bloquant pour CP5a (le soignant voit le badge urgence dans l'app), mais à surveiller si un flow de notification soignant est ajouté plus tard.

**P5 — Transitions admin forcées :**

Un admin peut forcer toute transition via `est_admin()` bypass dans `fn_valider_transition_statut_mission`. Le trigger de gel doit se comporter normalement dans tous les cas :
- Admin force `ASSIGNEE → OUVERTE` : DEGEL normal (NULL des `_fige`). Pas de traitement spécial.
- Admin force une transition "anormale" (ex: `TERMINEE → OUVERTE`) : le trigger détecte `NEW.statut = 'OUVERTE'` → le degel s'applique si `OLD.fige_le IS NOT NULL`. Comportement cohérent.
- Admin force `OUVERTE → EN_COURS` (bypass machine d'états) : pas de gel car la condition est `OLD.statut = 'OUVERTE' AND NEW.statut = 'ASSIGNEE'` — la mission EN_COURS n'aurait pas de `_fige`. **Risque mineur** : une mission EN_COURS sans gel. Mitigation : le calculateur financier utilise les valeurs etab live (`_fige IS NULL` → fallback). Ticket tech-debt si ce scénario admin se produit.

Tests spécifiques requis (section 2.6, Message C) :
- Test : admin force `ASSIGNEE → OUVERTE` → `_fige` remis à NULL
- Test : admin force `TERMINEE → OUVERTE` → `_fige` remis à NULL (si étaient non-NULL)
- Test : admin force `OUVERTE → EN_COURS` (bypass ASSIGNEE) → mission fonctionne sans gel (fallback etab)

---

*Sections 2.4–2.6 (code SQL, bypass admin, tests) en attente — livraison Messages B et C.*
