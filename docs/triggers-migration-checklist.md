# Checklist triggers — Migration multi-créneaux

> Date : 2026-04-16

## Triggers à refondre en CP5

Ces triggers comparent `missions.debut_le`/`fin_le` (span global) au lieu des créneaux individuels.
Avec le multi-créneaux, ils produisent des **faux positifs** (rejet de missions légitimes pendant les pauses).

### 1. `dec_refuser_chevauchement_soignant` (dec_chevauchement)

**Problème** : Compare `debut_le`/`fin_le` entre missions du même soignant. Si mission A = 7h–12h + 14h–19h (pause 12h–14h), le span est 7h–19h. Une mission B à 13h–14h serait rejetée alors que le soignant est en pause.

**Fix CP5** : Comparer créneau par créneau via `mission_creneaux` :
```sql
EXISTS (
  SELECT 1 FROM mission_creneaux mc_a
  JOIN mission_creneaux mc_b ON mc_a.mission_id != mc_b.mission_id
  WHERE mc_a.mission_id = NEW.id AND mc_b.mission_id = other.id
    AND NOT mc_a.est_pause AND NOT mc_b.est_pause
    AND mc_a.debut < mc_b.fin AND mc_a.fin > mc_b.debut
)
```

### 2. `dec_verifier_plafond_48h` (dec_mission_plafond_48h)

**Problème** : Utilise `duree_heures` (correct maintenant grâce au sync) mais vérifie le chevauchement des spans pour le calcul hebdo. Si deux missions avec pauses se chevauchent en span mais pas en créneaux effectifs, le plafond est surestimé.

**Fix CP5** : Sommer les `duree_heures` (qui sont déjà corrigés par le sync) plutôt que les spans. Le `duree_heures` est fiable après CP2.

### 3. `dec_verifier_repos_11h` (dec_mission_repos_11h)

**Problème** : Calcule le repos entre `fin_le` de mission N et `debut_le` de mission N+1. Mais `fin_le` = MAX(fin) de tous créneaux. Si la mission N a un dernier créneau effectif à 17h suivi d'une pause comptée 17h–19h, le repos réel commence à 17h (fin du travail), pas à 19h (fin de pause).

**Fix CP5** : Calculer le repos depuis `MAX(fin) WHERE NOT est_pause` de la mission N jusqu'au `MIN(debut) WHERE NOT est_pause` de la mission N+1.

### 4. `fn_trg_auto_heures_majorees` (trg_auto_heures_majorees)

**Problème** : Calcule les heures nuit/dimanche/férié à partir de `debut_le`/`fin_le` (span global). Avec multi-créneaux, le span inclut les pauses. Exemple : mission 21h–7h avec pause 1h–2h → le trigger compte 10h de nuit au lieu de 9h.

**Fix CP5** : Itérer sur chaque créneau `WHERE NOT est_pause` et calculer les majorations par créneau.

## Triggers protégés par `jolene.sync_in_progress`

Audit exhaustif (2026-04-16) — tous les triggers sur `missions` qui référencent `debut_le`/`fin_le`/`duree_heures` ont été analysés.

### Protégés (bypass sync) — 3 triggers

| Trigger | Pattern dangereux | Guard ajouté |
|---|---|---|
| `dec_bloquer_modif_apres_acceptation` | `RAISE EXCEPTION` si `debut_le`/`fin_le` changent après acceptation | `jolene.sync_in_progress` skip ✅ |
| `dec_proteger_mission_soignant` | `NEW.debut_le := OLD.debut_le` (revert) quand caller ≠ admin/etab | `jolene.sync_in_progress` skip ✅ |
| `fn_protect_mission_financials` | `NEW.debut_le := OLD.debut_le` (revert) quand caller = soignant assigné | `jolene.sync_in_progress` skip ✅ |

### Non protégés — validations légitimes (3 triggers)

Ces triggers RAISE EXCEPTION sur timing invalide. Ils NE doivent PAS être bypassés car leurs validations s'appliquent aussi au sync.

| Trigger | Condition de feu | Pourquoi pas de guard |
|---|---|---|
| `dec_verifier_docs_jusqua_fin` | Seulement sur transition `OUVERTE → ASSIGNEE` | Sync ne change pas `statut` → ne fire pas |
| `dec_verifier_plafond_48h` | Vérifie le plafond 48h/semaine | Validation légitime, DOIT bloquer si dépassement |
| `dec_verifier_repos_11h` | Vérifie repos 11h entre missions | Validation légitime, DOIT bloquer si repos insuffisant |

### Non protégés — calculs cascadés (2 triggers, OK)

| Trigger | Effet | Pourquoi OK |
|---|---|---|
| `fn_calculer_financier_mission` | Recalcule `duree_heures` via `COALESCE(NEW.duree_heures, span)` | Garde la valeur du sync si non-NULL, recalcule si NULL (cas "all pauses" → bug CP4) |
| `fn_trg_auto_heures_majorees` | Recalcule heures nuit/dimanche/férié | Calcul basé sur debut_le/fin_le — à refondre en CP5 pour utiliser créneaux |

### Non protégés — ne référencent timing qu'en lecture (9 triggers, OK)

| Trigger | Usage |
|---|---|
| `dec_alerte_mission_liberee` | Lit debut_le pour contexte notification |
| `dec_calculer_finance_mission` | Lit debut_le/fin_le pour calcul |
| `dec_incrementer_heures_plateforme` | Lit duree_heures (seulement sur → TERMINEE) |
| `dec_maj_compteurs_soignant` | Lit duree_heures |
| `dec_mettre_a_jour_fiabilite` | Lit debut_le |
| `dec_penalite_annulation_tardive` | Lit debut_le |
| `dec_refuser_chevauchement_soignant` | Lit debut_le/fin_le (faux positifs multi-créneaux → CP5) |
| `dec_refuser_mission_passee` | Lit debut_le |
| `fn_trg_sms_annulation_tardive` | Lit debut_le |

## Changement structurel irréversible — CP2

**Date** : 2026-04-16
**Action** : `ALTER TABLE missions ALTER COLUMN duree_heures DROP EXPRESSION IF EXISTS`
**Raison** : `duree_heures` était `GENERATED ALWAYS AS (EXTRACT(epoch FROM (fin_le - debut_le)) / 3600.0)`. Cette expression calculait le span brut sans soustraire les pauses. Converti en colonne régulière pour permettre au trigger `fn_sync_mission_creneaux` de la maintenir avec la somme des créneaux non-pause.
**Vérification** : les 268 missions existantes ont conservé leurs valeurs (0 NULL après conversion).
**Source de vérité** : désormais `fn_sync_mission_creneaux()` (sync trigger) + `fn_calculer_financier_mission()` (fallback COALESCE si NULL).

## CP3 — Migration data : COMPLETED (2026-04-16)

- 265 créneaux mono-créneau insérés (3 missions >24h skippées)
- 1 série reconstruite (SERIE_DEMO_001, 8 missions)
- Incident : bypass trop large → 231 missions avec financials recalculés → corrigé via snapshot restore
- Correction Option C : bypass ciblé (freeze 21 champs financiers, laisse passer 4 timing)
- Nouveau trigger `trg_protect_creneaux_facture` : bloque créneaux si facture émise
- Post-mortem complet : `/docs/postmortem-cp3.md`
- Snapshots droppés après validation

## CP5a — Gel financier + refonte 4 triggers : COMPLETED (2026-04-16)

**Step 1 — Colonnes snapshot + trigger de gel + backfill :**
- 2 colonnes `time` ajoutées sur `etablissements` (heure_debut_nuit, heure_fin_nuit)
- 3 CHECK planchers ajoutés (nuit ≥25%, dimanche ≥25%, férié ≥50%)
- 8 colonnes `_fige` + `fige_le` ajoutées sur `missions`
- `fn_geler_mission_a_assignation` : GEL (OUVERTE→ASSIGNEE), DEGEL (→OUVERTE), PROTECTION (11 champs)
- `trg_zz_geler_mission` : BEFORE UPDATE, position 25/25 (préfixe `zz_` = dernier)
- Protecteurs mis à jour : `_fige` ajoutés aux listes de freeze (dec_proteger + fn_protect)
- 266 missions backfillées (`fige_le = NULL` gel rétroactif), 2 OUVERTE laissées NULL
- Audit : `journaux_audit` (Option Z) avec actions DEGEL_APPLIED + OVERRIDE_CHAMP_POST_GEL

**Step 3 — Tests gel (7/7 PASS) :**
- A. GEL normal, B. DEGEL + audit, C. Protection sans bypass, D. Protection avec bypass admin
- E. Re-gel après désistement (Option C), F. Sync créneau transparent, G. 11 champs bloqués

**Step 4 — Refonte 4 triggers span → créneaux :**

| Trigger | Changement | Tests |
|---|---|---|
| `fn_trg_auto_heures_majorees` | Créneaux non-pause, night _fige configurable, TZ Europe/Paris, SECURITY DEFINER | 3 PASS (night, dimanche, pause) |
| `dec_refuser_chevauchement_soignant` | Inchangé (D1 : span bloque) | N/A |
| `dec_verifier_plafond_48h` | Créneaux non-pause, fix conformite_travail columns, fix RAISE format | 2 PASS (sanity + blocage 55h>48h) |
| `dec_verifier_repos_11h` | MAX/MIN créneaux non-pause, fix RAISE format | 2 PASS (blocage 0.4h<11h, format) |

**Bugs corrigés en passant :**
- `journaux_audit` CHECK constraint : ajout DEGEL_APPLIED + OVERRIDE_CHAMP_POST_GEL
- `type_acteur` : 'system'→'SYSTEME', 'admin'→'ADMIN_PLATEFORME'
- `dec_alerte_mission_liberee` : `niveau_urgence := 'CRITIQUE'` → `3` (colonne integer)
- `conformite_travail` columns : `type_violation`/`details` → `type_controle`/`resultat`/`details_violation`
- RAISE format PL/pgSQL : `%.1f` → `ROUND(v, 1)` (3 fonctions)

**Total : 14 tests, 14 PASS.**

## Triggers modifiés en CP2

| Trigger | Modification | Raison |
|---|---|---|
| `dec_bloquer_modif_apres_acceptation` | Skip si `jolene.sync_in_progress = 'true'` | Permettre au sync de mettre à jour `debut_le`/`fin_le` sans être bloqué |
| `dec_proteger_mission_soignant` | Skip si `jolene.sync_in_progress = 'true'` | Empêcher le revert `NEW.x := OLD.x` sur les champs timing/financiers |
| `fn_protect_mission_financials` | Skip si `jolene.sync_in_progress = 'true'` | Idem pour les soignants assignés |
