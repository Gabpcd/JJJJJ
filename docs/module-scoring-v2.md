# Module Scoring v2 — Soignants & Établissements

Date : 2026-05-03 (Refonte.A → Refonte.E)

## 1. Vue d'ensemble

Le scoring v2 remplace l'ancien score v1 (formule heuristique simple `50 + bonus - malus`). Objectifs :

- **Multi-composantes** : 6 dimensions de qualité, pondérées, tracées dans `scoring_breakdown`.
- **Symétrique** : étab note soignant ET soignant note étab.
- **Dépréciation 12 mois** : les missions/notations/litiges anciens sortent automatiquement.
- **Transparence** : chaque recalcul produit un breakdown JSON expliquant la composition (pour la page `/soignant/score`).
- **Niveaux qualitatifs** : Bronze / Argent / Or / Platine, visibles aux étabs côté candidatures et profil public.

Soignants et étabs ont chacun un score :
- **Soignant** : `soignants.score_fiabilite` (0-100), `soignants.niveau` (enum), `soignants.score_breakdown_id` (FK breakdown actif).
- **Établissement** : `etablissements.score_qualite_employeur`, `etablissements.niveau_qualite_employeur`. Calcul plus simple (50/30/20).

## 2. Algorithme soignant — `fn_calculer_score_fiabilite_v2(p_soignant_id, p_raison)`

### 2.1 Six composantes

| Composante | Poids initial | Source de données |
|---|---|---|
| `notation_etab_soignant_pct` | 35 % | Notations `ETAB_VERS_SOIGNANT`, pondérées récence linéaire |
| `presentisme_pct` | 20 % | Missions `TERMINEE` / (TERMINEE + ABSENCE + ANNULEE_PAR_SOIGNANT) sur 12m |
| `ponctualite_pct` | 15 % | (TODO P1 — composante actuellement inactive en prod, voir tech-debt) |
| `reactivite_pct` | 10 % | Délai moyen acceptation/refus candidatures (TODO P1 — actuellement inactive) |
| `anciennete_volume_pct` | 10 % | Quartiles : `<5 missions=25%`, `5-15=50%`, `15-30=75%`, `>30=100%` |
| `notation_soignant_etab_pct` | 10 % | Notations données `SOIGNANT_VERS_ETAB`, pondérées récence |

**Total poids actifs** : variable (les composantes sans données sont inactives → redistribution).

### 2.2 Formule pondérée récence (notations)

Pour chaque critère (1-5), pondéré par récence linéaire sur 365 jours :

```sql
SUM((critere_1+critere_2+critere_3+critere_4)/4 *
    GREATEST(0, 1 - age_jours/365)) /
NULLIF(SUM(GREATEST(0, 1 - age_jours/365)), 0)
```

Une notation d'il y a 1 mois pèse `1 - 30/365 ≈ 0.92`. Une notation d'il y a 11 mois pèse `1 - 330/365 ≈ 0.10`.

**Seuil minimum** : `< 3 notations` → composante désactivée (`pct = NULL`).

### 2.3 Redistribution des composantes inactives

Si une composante ne peut être calculée (ex. `< 3 notations`), son poids est redistribué proportionnellement sur les actives :

```
facteur = 100 / total_poids_actives
poids_actif_redistribué = poids_initial × facteur
```

Exemple : si `ponctualite` (15) et `reactivite` (10) sont inactives :
- `total_poids_actives = 35 + 20 + 10 + 10 = 75`
- `facteur = 100/75 = 1.333`
- `notation_etab_soignant_poids` final = `35 × 1.333 = 46.67`

Le breakdown stocke à la fois les composantes inactives (`composantes_inactives_json`) et le facteur de redistribution (`redistribution_json`).

### 2.4 Malus + bonus

| Type | Calcul | Cap |
|---|---|---|
| **Malus litiges** | `LEAST(2, COUNT(*)) × 10` litiges `RESOLU_ETABLISSEMENT` ou `RESOLU_FAVEUR_ETAB` 12m | -20 |
| **Malus absence sans prévenir** | `LEAST(1, COUNT(*)) × 30` missions `ABSENCE` + `absence_sans_prevenir=true` 6m | -30 |
| **Bonus super-actif** | `+5` si `> 50 missions terminées` 12m | +5 |

```sql
v_score := SUM(composante_pct × composante_poids) / 100
        + v_litiges_malus + v_absence_malus + v_bonus_super_actif
v_score := GREATEST(0, LEAST(100, v_score))
```

### 2.5 Période probatoire

- `soignants.en_periode_probatoire = true` si `total_missions_terminees < 3`.
- En probatoire : le score est calculé mais **affiché avec mention** "Probatoire" côté UI (BadgeNiveauV2) pour expliquer pourquoi le niveau est bas même avec de bonnes notes.
- À 3 missions terminées : sortie automatique de la probation.

## 3. Niveaux

| Niveau | Seuil | Sens |
|---|---|---|
| `BRONZE` | `< 50` | Score faible / probatoire |
| `ARGENT` | `≥ 50` | Score correct |
| `OR` | `≥ 70` | Bon score |
| `PLATINE` | `≥ 90` | Excellence |

Composant React : `BadgeNiveauV2` (`src/components/BadgeNiveauV2.tsx`).

## 4. Recalcul automatique

### 4.1 Triggers

| Trigger | Table | Évènement |
|---|---|---|
| `trg_recalcul_score_v2_notations` | `notations_missions` | INSERT/UPDATE notation → recalcul soignant + recalcul étab |
| `trg_recalcul_score_v2_missions` | `missions` | UPDATE statut → TERMINEE ou ABSENCE → recalcul soignant |
| `trg_recalcul_score_v2_litiges` | `litiges` | UPDATE statut → RESOLU_* → recalcul soignant + étab |
| `trg_compteur_absences_sans_prevenir` | `missions` | UPDATE absence_sans_prevenir → maintien compteur 6m + suspension auto si ≥3 |

Les triggers sont `EXCEPTION WHEN OTHERS THEN RETURN NEW` (best-effort) : un échec recalcul ne bloque jamais la transaction métier.

### 4.2 Cron quotidien

Edge function `email-cron-daily` appelle :
- `fn_basculer_litiges_revue_admin_timeout()` — médiation 7j → REVUE_ADMIN
- `fn_envoyer_rappels_notation_j1()` — emails J+1 post-mission

(Le score lui-même n'est PAS recalculé en cron : il l'est à chaque évènement métier.)

## 5. Score étab — `fn_calculer_score_etablissement(p_etab_id)`

Formule simplifiée (pas de période probatoire, pas de redistribution) :

| Composante | Poids |
|---|---|
| Note moyenne reçue (`SOIGNANT_VERS_ETAB`) | 50 % |
| % missions complétées (TERMINEE / total) | 30 % |
| Volume relatif (quartiles) | 20 % |

Niveaux : mêmes seuils Bronze/Argent/Or/Platine.

## 6. RPC publiques (lecture)

| RPC | Audience | Description |
|---|---|---|
| `fn_evolution_score_soignant(p_soignant_id, p_mois?)` | SOIGNANT (self) | Série temporelle pour graphique 6 mois |
| `fn_mon_breakdown_actuel()` | SOIGNANT | Breakdown JSON du score actuel |
| `fn_mon_score_etab()` | ETAB | Breakdown étab |
| `fn_score_etab_public(p_etab_id)` | SOIGNANT | Niveau étab visible côté candidat (pas le détail) |

## 7. RPC privées (mutations)

- `fn_calculer_score_fiabilite_v2(uuid, text)` — invoquée par triggers + cron + admin recompute
- `fn_calculer_score_etablissement(uuid)` — idem côté étab
- `fn_admin_recalculer_score_soignant(uuid, text)` — admin force recompute

## 8. RLS

| Table | Policy | Description |
|---|---|---|
| `scoring_breakdown` | `pol_scoring_bd_select` | `soignant_id = auth.uid()` OU `est_admin()` |
| `notations_missions` | RLS multiples | Notateur voit les siennes, noté voit celles non masquées |

## 9. Pages frontend

- `/soignant/score` (`PageScoreSoignant.tsx`) — Graphique évolution + breakdown détaillé + conseils
- `/etablissement/score` (`PageScoreEtablissement.tsx`) — Breakdown étab + bonnes pratiques
- `BadgeScoreEtabPublic` — visible côté candidat sur fiches missions
- `CardScoreQualiteEtab` — dashboard étab

## 10. Migration v1 → v2 (Refonte.A.3)

Migration bulk `evaluations` → `notations_missions` réalisée dans `20260429380200_refonte_a_3_trigger_recalcul_migration_evaluations.sql` :
- Pour chaque `evaluations` row : créé une `notations_missions` row équivalente avec `sens=ETAB_VERS_SOIGNANT` (l'ancien modèle ne notait que dans ce sens).
- Les 4 critères v2 ont été dérivés de la note unique v1 (toutes à la même valeur).

## 11. Notes tech-debt

| Item | Priorité | Cible |
|---|---|---|
| **Suppression score v1 inline** dans `dec_mettre_a_jour_fiabilite` (overwritten par v2) | P3 | Refonte.E.3 (livré) |
| **Composantes ponctualité + réactivité** : actuellement toujours inactives en prod (sources de données pas encore branchées) | P1 | Q3 2026 |
| **Epsilon floating-point seuil 70** : score `69.999...` (affiché 70.00) classé ARGENT au lieu de OR | P2 | À fixer dans `fn_determiner_niveau` ou arrondir avant comparaison |
| **Compteur dénormalisé `total_missions_terminees`** : `fn_calculer_score_fiabilite_v2` se fie à cette colonne (maintenue par trigger `dec_mettre_a_jour_fiabilite`). Si le trigger est bypassed, `en_periode_probatoire` est faux. Refactor possible : utiliser `COUNT(*)` direct dans v2. | P3 | Optionnel |
| **Suppression colonne `evaluations` legacy** : table conservée pour historique, à archiver/supprimer dans 6 mois si plus d'usage | P3 | Novembre 2026 |
| **Redistribution si TOUTES composantes inactives** : edge case (nouveau soignant sans aucune donnée) → score = 0. Comportement actuel acceptable (probatoire couvre ce cas). | — | — |

## 12. Tests E2E (Refonte.E.4)

19/19 PASS — voir migration `20260429430000_refonte_e_4_fix_litige_admin_tranche.sql` pour le bug prod-critique fixé en cours de tests.

Scénarios testés :
- S1-S10 : scoring + niveaux + composantes (probatoire, redistribution, fenêtre 12m)
- S11-S15 : litiges + RLS + UNIQUE
- S16-S19 : emails J+1 + accord mutuel + admin tranche
