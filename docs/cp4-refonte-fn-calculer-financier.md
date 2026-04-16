# CP4 — Refonte fn_calculer_financier_mission

> Date : 2026-04-16
> Statut : AUDIT — en attente de validation avant implémentation

## 1. Code actuel (lignes 24-27)

```sql
-- Step 1: Calculate duration if not set
v_duree := COALESCE(NEW.duree_heures,
  EXTRACT(EPOCH FROM (NEW.fin_le - NEW.debut_le)) / 3600.0);
NEW.duree_heures := v_duree;
```

**Problème** : `COALESCE` utilise `debut_le - fin_le` (span global) en fallback. Quand le sync trigger envoie `duree_heures = NULL` (cas all-pauses), le fallback recalcule 12h (span) au lieu de 0h (somme non-pauses).

## 2. Code proposé (remplacement des lignes 24-27)

```sql
-- Step 1: Calculate duration from mission_creneaux (source de vérité)
SELECT COALESCE(
  SUM(EXTRACT(EPOCH FROM (fin - debut)) / 3600.0), 0
) INTO v_duree
FROM mission_creneaux
WHERE mission_id = NEW.id AND NOT est_pause;

-- Fallback: si aucun créneau existe (missions sans créneau, ex: 3 ANNULEE >24h)
IF v_duree = 0 AND NOT EXISTS (SELECT 1 FROM mission_creneaux WHERE mission_id = NEW.id) THEN
  v_duree := COALESCE(NEW.duree_heures,
    EXTRACT(EPOCH FROM (NEW.fin_le - NEW.debut_le)) / 3600.0);
END IF;

NEW.duree_heures := v_duree;
```

**Différences** :
- Source de vérité : `mission_creneaux` au lieu de `debut_le/fin_le`
- Le fallback ne s'applique QUE si la mission n'a aucun créneau (pas si elle a des créneaux tous en pause)
- Cas "all pauses" : v_duree = 0 → `total_brut = 0`, `net_a_payer = 0`, `commission = 0`

**Le reste de la fonction (lignes 29-83) ne change pas.**

## 3. Constraint à modifier

`chk_duree_positive` : `duree_heures > 0 OR IS NULL` → doit devenir `duree_heures >= 0 OR IS NULL` pour accepter `duree_heures = 0` (cas all-pauses légitime).

## 4. Triggers affectés par le changement

Le trigger `trg_calculer_financier` fire sur `UPDATE OF taux_horaire_base, duree_heures, debut_le, fin_le, heures_nuit, heures_dimanche, heures_ferie, taux_ifm, taux_icp`. Le changement CP4 ne modifie pas les conditions de déclenchement — seul le calcul interne de `v_duree` change.

### Triggers qui lisent `duree_heures` depuis `missions` (19 fonctions)

Aucune ne nécessite de modification — elles lisent la valeur dénormalisée dans `missions.duree_heures`, qui sera correcte après CP4.

| Fonction | Usage de duree_heures | Impact CP4 |
|---|---|---|
| `dec_verifier_plafond_48h` | Somme pour vérification 48h/semaine | Valeur plus précise (pauses exclues) |
| `dec_maj_compteurs_soignant` | Incrémente compteur heures | Valeur correcte |
| `dec_incrementer_heures_plateforme` | Incrémente heures_plateforme soignant | Valeur correcte |
| `fn_dashboard_soignant_complet` | Affichage dashboard | Valeur correcte |
| `fn_mes_missions_soignant` | Affichage liste missions | Valeur correcte |
| `fn_planning_*` | Affichage planning | Valeur correcte |
| `fn_analytics_etablissement` | Statistiques | Valeur correcte |
| `fn_admin_*` (4 fonctions) | Dashboards admin | Valeur correcte |
| Autres (8 fonctions) | Lecture seule | Valeur correcte |

### Interaction avec le sync trigger

Le sync trigger (`fn_sync_mission_creneaux`) fait `UPDATE missions SET duree_heures = X`. Le trigger financier se déclenche car `duree_heures` est dans le column filter. Le financier recalcule `v_duree` depuis `mission_creneaux` (même source que le sync). Résultat : la valeur est identique. Pas de boucle, pas de conflit.

**MAIS** : pendant le sync, `jolene.sync_in_progress = true` et les triggers de protection (`dec_proteger_mission_soignant`) freezent les financials à OLD. Donc même si le financier recalcule, les valeurs sont revertées. Ce qui signifie : **le recalcul financier lors du sync est un no-op** (il calcule mais ses résultats sont écrasés par les protecteurs).

Le recalcul financier RÉEL se fait uniquement quand l'UPDATE vient d'une source AUTRE que le sync (ex: modification du taux horaire, changement de statut).

## 5. Scénarios de validation

| Scénario | Avant CP4 | Après CP4 | Delta |
|---|---|---|---|
| **A. Mono-créneau 8h** (sans pause) | duree=8, brut=200 | duree=8, brut=200 | **Identique** |
| **B. Bi-créneau avec pause** (5h+5h, pause 2h) | duree=12 (span), brut=300 | duree=10 (sum), brut=250 | **Corrigé** |
| **C. All-pauses** (2 créneaux pauses) | duree=12 (fallback span), brut=300 | duree=0, brut=0 | **Corrigé** |
| **D. 0 créneau** (3 missions ANNULEE) | duree=span (existant) | duree=span (fallback) | **Identique** |
| **E. 265 missions migrées** (mono-créneau) | duree=X | duree=X (SUM = span) | **Identique** |

**Note sur le scénario E** : les 265 missions migrées ont exactement 1 créneau avec debut=debut_le et fin=fin_le. Donc SUM(créneau) = span = valeur actuelle. 0 changement attendu.

## 6. Risques

1. **Performance** : la requête `SELECT SUM(...) FROM mission_creneaux WHERE mission_id = NEW.id` ajoute 1 subquery par trigger execution. Avec l'index `idx_mc_mission`, c'est un index scan sur 1-6 rows. Coût négligeable (<1ms).

2. **Constraint `chk_duree_positive`** : doit être modifiée AVANT le déploiement de la fonction (sinon `duree_heures = 0` échoue sur les cas all-pauses).

3. **Snapshot recommandé** : oui, pour les 265 missions migrées. Pas de risque théorique (scénario E = 0 delta), mais le post-mortem CP3 nous a appris qu'il vaut mieux vérifier.

## 7. Décision technique : sync 2-phase

Le sync trigger `fn_sync_mission_creneaux` a été modifié pour fonctionner en 2 phases :

**Pourquoi** : le sync doit mettre à jour `debut_le`, `fin_le`, `nb_creneaux` ET `duree_heures`. Mais la mise à jour de `duree_heures` doit déclencher `fn_calculer_financier_mission` pour que les valeurs financières soient recalculées avec la bonne durée. Si tout est dans une seule UPDATE avec `sync_in_progress=true`, les protecteurs gèlent les financials → le recalcul ne persiste pas.

**Phase 1** (sync_in_progress=true) :
- UPDATE `debut_le`, `fin_le`, `nb_creneaux`
- Les protecteurs (`dec_proteger_mission_soignant`, `fn_protect_mission_financials`) gèlent les 21 champs financiers à OLD
- `fn_calculer_financier` recalcule mais ses résultats sont écrasés par les protecteurs

**Phase 2** (sync_in_progress=false) :
- UPDATE `duree_heures` uniquement
- `fn_calculer_financier` se redéclenche (duree_heures est dans son column filter)
- Les protecteurs ne gèlent PAS (guard inactive) — MAIS en contexte service_role/MCP, `est_admin()=false` et `est_admin_etablissement()=false` → les protecteurs GÈLENT quand même (c'est un UPDATE sans contexte auth)
- En contexte authenticated (ex: etab user insère un créneau via le front), `est_admin_etablissement()=true` → les protecteurs ne gèlent PAS → les financials sont recalculés correctement

**Garantie de sécurité** :
- La Phase 2 n'est jamais déclenchée directement par du code utilisateur — elle est interne à `fn_sync_mission_creneaux`
- Le test régression CP3 passe toujours (Phase 1 gèle les financials)
- Pour les missions facturées, `trg_protect_creneaux_facture` bloque en amont

**Conséquence** : en contexte service_role (MCP, admin-invoke), les financials ne sont PAS recalculés par Phase 2 (les protecteurs gèlent). C'est acceptable : les opérations admin qui modifient les créneaux via service_role doivent ensuite forcer un recalcul explicite si nécessaire.

## 8. Écarts pré-existants missions vs factures

Les valeurs `missions.net_a_payer` et `factures_honoraires.montant_ht` divergent déjà (écarts de 3€ à 68€ sur les missions test). La facture est le document de vérité financière — la mission est un estimatif qui peut dériver.

**Règle** : ne JAMAIS recalculer financièrement une mission déjà facturée via un bulk update. Le trigger `trg_protect_creneaux_facture` empêche la modification des créneaux sur les missions facturées. Toute correction post-facture passe par le flow annulation-refacturation avec audit trail.

## 9. Résultat du déploiement

- 265 missions migrées : `duree_diff = 0` (aucun changement de durée)
- Pas de mass recalcul nécessaire (SUM mono-créneau = span = identique)
- Tests A-E verts
- Régression CP3 verte
