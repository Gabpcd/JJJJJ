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

## Triggers modifiés en CP2

| Trigger | Modification | Raison |
|---|---|---|
| `dec_bloquer_modif_apres_acceptation` | Skip si `jolene.sync_in_progress = 'true'` | Permettre au sync de mettre à jour `debut_le`/`fin_le` sans être bloqué |

## Triggers OK sans modification

| Trigger | Raison |
|---|---|
| `trg_calculer_financier` | Recalcule correctement avec les nouvelles valeurs dénormalisées |
| `dec_notifier_changement_mission` | Ne fire que sur changement de `statut` |
| `fn_trg_auto_facture_honoraires` | Ne fire que sur `statut → TERMINEE` |
| `fn_trg_email_mission_terminee` | Idem |
| `fn_trg_sms_*` | Idem |
| `dec_incrementer_heures_plateforme` | Idem |
| Tous les triggers `{statut}` column-filtered | Le sync ne change pas `statut` |
