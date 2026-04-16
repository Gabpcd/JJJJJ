# Post-mortem CP3 — Incident recalcul financier lors de la migration

> Date : 2026-04-16
> Sévérité : P1 (données financières modifiées, détecté et corrigé avant impact utilisateur)
> Durée de l'incident : ~5 minutes (entre exécution et détection)

## 1. Timeline factuelle

| Étape | Action | Résultat |
|---|---|---|
| T+0 | `SELECT set_config('jolene.sync_in_progress', 'true', false)` | Bypass activé (session-level) |
| T+1 | `INSERT INTO mission_creneaux ... SELECT id, debut_le, fin_le ...` | 265 créneaux insérés. Le sync trigger `fn_sync_mission_creneaux` ne fire pas (guard active). OK. |
| T+2 | `UPDATE missions SET nb_creneaux = 1 WHERE ...` (bypass TOUJOURS actif) | **INCIDENT** : les 24 BEFORE UPDATE triggers sur missions se déclenchent. Les 3 triggers avec `sync_in_progress` guard (bloquer, proteger, protect) sont bypassés. Les triggers financiers sans guard (`dec_calculer_commission`, `dec_mission_z_finance`, `dec_net_estime`) recalculent les montants. Normalement, `dec_proteger_mission_soignant` aurait revert les valeurs à OLD — mais il est bypassé. Résultat : 231 missions avec `total_brut` modifié, 242 avec `commission_ht` modifiée. |
| T+3 | Vérification post-migration détecte les diffs | Anomalie identifiée immédiatement |
| T+4 | Tentative de restore via UPDATE + sync bypass | Même problème — la restore elle-même déclenche le même cascade |
| T+5 | Restore via `ALTER TABLE missions DISABLE TRIGGER USER` + UPDATE | Succès. Toutes les valeurs financières restaurées identiques au snapshot. |
| T+6 | nb_creneaux et description cleanup refaits avec `DISABLE TRIGGER USER` | Migration complétée proprement. 0 diff financier. |

## 2. Analyse cause racine

### Pourquoi le bypass a laissé passer les recalculs financiers

Le bypass `jolene.sync_in_progress` a été conçu au CP2 pour résoudre un problème précis : permettre au trigger de sync de mettre à jour `debut_le`/`fin_le`/`duree_heures` sur missions sans être bloqué par 3 triggers de protection.

**Erreur d'analyse** : au CP2, nous avons ajouté le bypass dans ces 3 triggers :
1. `dec_bloquer_modif_apres_acceptation` — RAISE EXCEPTION
2. `dec_proteger_mission_soignant` — revert `NEW.x := OLD.x`
3. `fn_protect_mission_financials` — revert `NEW.x := OLD.x`

Nous avons bypassé la **totalité** de chaque fonction (RETURN NEW immédiat), pas juste les lignes qui bloquent les champs timing. Conséquence : quand le bypass est actif, `dec_proteger_mission_soignant` ne protège plus **aucun** champ — ni timing, ni financier.

### Le mécanisme normal (sans bypass)

En fonctionnement normal, quand un UPDATE touche missions :
1. `dec_calculer_commission` recalcule `montant_commission_ht/tva/ttc`
2. `dec_mission_z_finance` recalcule `total_brut`
3. `dec_calculer_net_estime` recalcule `net_estime`
4. **Puis** `dec_proteger_mission_soignant` arrive et fait `NEW.montant_commission_ht := OLD.montant_commission_ht` — il **revert tout** si le caller n'est pas admin/etab

C'est ce revert qui empêche les recalculs de persister en temps normal. Avec le bypass, le revert saute → les recalculs persistent.

### Pourquoi les recalculs donnent des valeurs différentes

Les triggers `dec_calculer_commission` et `dec_mission_z_finance` lisent les taux actuels dans la table `etablissements` (ex: `taux_commission_negocie`). Si ces taux ont changé depuis la création des missions, les recalculs produisent des valeurs différentes. C'est le cas ici : les établissements de test ont probablement eu leurs taux modifiés au cours du développement.

### Pourquoi l'inventaire CP2 n'a pas identifié ce risque

L'inventaire CP2 classait les triggers en 5 catégories. Les triggers financiers étaient en catégorie 3 ("cascading calc — souhaitable"). L'analyse disait : "le recalcul est OK car fn_calculer_financier utilise les bonnes valeurs dénormalisées".

**L'erreur** : cette analyse ne considérait que le cas du **sync trigger** (UPDATE déclenché par INSERT créneau via le trigger de sync). Elle ne considérait pas le cas d'un **UPDATE direct** sur missions (ex: `SET nb_creneaux = 1`) avec le bypass actif. Dans le cas du sync, le bypass empêche les bloqueurs mais les protecteurs font quand même leur travail car l'UPDATE vient du trigger de sync qui s'exécute dans le contexte de l'utilisateur original. Dans le cas d'un UPDATE direct via service_role, `auth.uid()` est NULL → les protecteurs traitent le caller comme "ni admin ni etab" → ils auraient revert si le bypass n'avait pas été actif.

## 3. Triggers financiers — Impact global du bypass

### Tableau exhaustif des 24 BEFORE UPDATE triggers sur missions

| Trigger | Écrit financials ? | Écrit duree ? | Guard sync ? | Impact si bypass actif | Risque |
|---|---|---|---|---|---|
| `dec_bloquer_modif_acceptee` | Non | Non | **OUI** | Skip RAISE EXCEPTION timing | **Souhaité** |
| `dec_proteger_mission_soignant` | **OUI** (revert) | **OUI** (revert) | **OUI** | **Skip revert de TOUS les champs** | **DANGEREUX** — laisse passer les recalculs financiers |
| `fn_protect_mission_financials` | **OUI** (revert) | **OUI** (revert) | **OUI** | **Skip revert de TOUS les champs** | **DANGEREUX** — même effet |
| `dec_calculer_commission` | **OUI** (écrit) | Non | Non | Recalcule commission | Dangereux si protecteurs bypassés |
| `dec_mission_z_finance` | **OUI** (écrit) | Non | Non | Recalcule total_brut | Dangereux si protecteurs bypassés |
| `dec_calculer_net_estime` | **OUI** (écrit) | Non | Non | Recalcule net_estime | Dangereux si protecteurs bypassés |
| `fn_calculer_financier_mission` | **OUI** (écrit) | **OUI** (écrit) | Non | Recalcule tout (COALESCE) | OK si duree_heures non-NULL |
| `fn_trg_auto_heures_majorees` | Non (heures_*) | Non | Non | Recalcule majorations | OK |
| `dec_appliquer_plafond_rist` | Non (rist_*) | Non | Non | Applique plafond RIST | OK |
| `fn_trg_auto_commission_facturee` | Non | Non | Non | Flag commission | OK |
| `dec_anti_double_assignation` | Non | Non | Non | Validation | OK |
| `dec_refuser_chevauchement_soignant` | Non | Non | Non | Validation | OK |
| `dec_verifier_plafond_48h` | Non | OUI (lit) | Non | Validation 48h | OK |
| `dec_verifier_repos_11h` | Non | Non | Non | Validation 11h | OK |
| `dec_verifier_docs_jusqua_fin` | Non | Non | Non | Validation docs | OK |
| `dec_eligibilite_liberal` | Non | Non | Non | Validation | OK |
| `dec_penalite_annulation` | Non | Non | Non | Logique métier | OK |
| `dec_alerte_mission_liberee` | Non | Non | Non | Notification | OK |
| `dec_definir_type_paiement` | Non | Non | Non | Logique métier | OK |
| `dec_type_contrat_compat` | Non | Non | Non | Validation | OK |
| `fn_coherence_statut_soignant` | Non | Non | Non | Validation | OK |
| `trg_valider_transition_statut` | Non | Non | Non | Validation statut | OK (column filter) |
| `trg_valider_type_contrat_mission` | Non | Non | Non | Validation | OK (column filter) |
| `trg_verifier_docs_avant_debut` | Non | Non | Non | Validation | OK (column filter) |

### Résumé du risque

Les **6 triggers qui écrivent des champs financiers** sont :
- 3 **protecteurs** (revert NEW := OLD) — bypassés par le guard
- 3 **calculateurs** (écrivent de nouvelles valeurs) — pas de guard

En fonctionnement normal : calculateurs écrivent → protecteurs revertent → résultat net = pas de changement.
Avec bypass : calculateurs écrivent → protecteurs bypassés → résultat = **recalcul persisté**.

Le bypass transforme un système "write + revert = no-op" en "write + skip revert = **modification involontaire**".

## 4. Risques en prod future

### Scénario A : Établissement corrige l'horaire d'une mission en cours

**Flow** : UPDATE créneau → sync trigger → UPDATE missions SET debut_le, fin_le, duree_heures

**Comportement actuel** :
1. `fn_sync_mission_creneaux` active `jolene.sync_in_progress = true`
2. UPDATE missions → tous les BEFORE triggers se déclenchent
3. `dec_bloquer_modif_acceptee` : **bypassé** (sync guard) — OK, c'est voulu
4. `dec_calculer_commission` : recalcule commission → nouvelle valeur dans NEW
5. `dec_proteger_mission_soignant` : **bypassé** (sync guard) — **la nouvelle commission persiste**
6. `fn_calculer_financier_mission` : recalcule avec le nouveau duree_heures — **OK, c'est voulu**

**Risque** : si les taux de commission de l'établissement ont changé, le changement d'horaire provoque aussi un recalcul de commission. C'est un **effet de bord non intentionnel** d'un changement de créneau.

**Sévérité** : MOYENNE — en prod, les taux changent rarement. Mais le risque existe.

### Scénario B : Admin ajoute un créneau sur mission TERMINEE facturée

**Flow** : INSERT créneau → sync → UPDATE missions

**Comportement actuel** :
1. Sync met à jour `debut_le`, `fin_le`, `duree_heures`
2. `fn_calculer_financier_mission` recalcule `total_brut`, `net_a_payer` (basé sur nouveau `duree_heures`)
3. Les **nouvelles valeurs financières persistent** sur la mission
4. La facture (`factures_honoraires`) reste intacte (trigger d'immutabilité la protège)
5. **Divergence** : `missions.net_a_payer` ≠ `factures_honoraires.montant_ht`

**Risque** : ÉLEVÉ — incohérence données mission/facture. Si quelqu'un génère une nouvelle facture basée sur la mission, elle aura un montant différent de l'originale.

**Mitigation manquante** : il n'y a AUCUN trigger sur `mission_creneaux` qui bloque l'INSERT/UPDATE si la mission a une facture émise (non-BROUILLON). C'est un trou dans les protections.

### Scénario C : INSERT créneau sur mission avec facture immutable

**Comportement actuel** : Aucun blocage. L'INSERT passe, le sync met à jour la mission, les financials divergent de la facture. Identique au scénario B.

**Comportement souhaité** : BLOCAGE — si `factures_honoraires` existe en statut non-ANNULEE pour cette mission, interdire toute modification de créneaux.

## 5. Corrections structurelles proposées

### Option retenue : C — Bypass ciblé + protection facture

**Principe** : le bypass `jolene.sync_in_progress` ne doit affecter QUE les lignes qui bloquent les champs timing, pas les protections financières.

#### 5.1 Refonte des 3 triggers avec sync guard

Au lieu de `RETURN NEW` immédiat quand le guard est actif, on ne skip que les protections timing :

```sql
-- dec_proteger_mission_soignant — version corrigée
IF current_setting('jolene.sync_in_progress', true) = 'true' THEN
    -- Pendant le sync : on PROTÈGE toujours les financials
    -- mais on AUTORISE debut_le/fin_le/duree_heures/nb_creneaux
    IF NOT est_admin() AND NOT est_admin_etablissement() THEN
        NEW.taux_horaire_base := OLD.taux_horaire_base;
        NEW.total_brut := OLD.total_brut;
        NEW.net_a_payer := OLD.net_a_payer;
        -- ... tous les champs financiers := OLD ...
        -- MAIS PAS debut_le, fin_le, duree_heures, nb_creneaux
    END IF;
    RETURN NEW;
END IF;
```

Même pattern pour `fn_protect_mission_financials` et `dec_bloquer_modif_apres_acceptation` (ne skip que la vérification timing, pas le reste).

#### 5.2 Nouveau trigger : bloquer modifications créneaux si facture émise

```sql
CREATE TRIGGER trg_protect_creneaux_facture
  BEFORE INSERT OR UPDATE OR DELETE ON mission_creneaux
  FOR EACH ROW EXECUTE FUNCTION fn_protect_creneaux_si_facture();
```

Logique : si `factures_honoraires` existe pour cette mission avec `statut NOT IN ('BROUILLON', 'ANNULEE')`, bloquer sauf admin.

#### 5.3 Pattern pour bulk updates

Voir section 6.

### Options rejetées

**A — Bypass granulaire par trigger** : trop verbeux, 3 variables de session au lieu d'1. Risque d'oubli.

**B — Session variable avec allowlist** : plus propre que A mais over-engineered. Le vrai problème est que le bypass est un RETURN NEW au lieu d'un skip ciblé.

## 6. Pattern pour bulk updates — `/docs/bulk-updates-playbook.md`

### Quand utiliser `DISABLE TRIGGER USER`

- **Migrations de données** : INSERT/UPDATE en masse sur `missions` (ex: CP3, futur CP data fixes)
- **Restauration de snapshot** : revert de données après incident
- **Recalcul batch** : mise à jour de colonnes dénormalisées sur N rows

### Quand NE PAS utiliser

- **Opérations unitaires** : l'UPDATE d'une seule mission doit passer par les triggers (validation, protection, calcul)
- **Opérations initiées par l'utilisateur** : le frontend ne doit jamais contourner les triggers
- **Service functions (edge functions)** : doivent respecter les validations

### Comment

```sql
-- Toujours dans un bloc avec ENABLE en fin
ALTER TABLE missions DISABLE TRIGGER USER;

-- ... bulk operations ...

ALTER TABLE missions ENABLE TRIGGER USER;
```

**Règles** :
1. Le `DISABLE` et `ENABLE` doivent être dans la **même** migration/script
2. Logger le nombre de rows affectées
3. Avoir un snapshot de la table AVANT l'opération
4. Vérifier la non-régression financière APRÈS l'opération (diff vs snapshot)
5. Ne JAMAIS laisser les triggers désactivés en fin de migration (vérifier avec `SELECT tgenabled FROM pg_trigger`)

### Où documenter

Chaque usage de `DISABLE TRIGGER USER` doit être documenté dans le header de la migration SQL avec :
- Raison
- Colonnes modifiées
- Triggers impactés
- Vérification post-opération
