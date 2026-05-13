# Score de fiabilité — soignant et étab

> Sprint 3.5 PR 6. Score sur 100 calculé selon 3 composantes
> consolidées et intégrant les événements impactants des 12 derniers mois
> (avec correction si réclamation admin).

## Formule soignant `fn_calculer_score_soignant`

```
Score total = note_moyenne (max 40) + comportement (max 40) + ancienneté (max 20)
```

### Composante 1 : note moyenne (40 pts max)
- Moyenne des notes reçues par le soignant (table `notations`)
- Filtres : 12 derniers mois, `masquee_par_admin IS NOT TRUE`
- Formule : `note_moyenne × 8` (note sur 5)
- Si aucune note : 28 pts par défaut (équivalent 3.5/5)

### Composante 2 : comportement contractuel (40 pts max)
- Base : 40 pts
- Soustraire la somme des points des `evenements_score_soignant` :
  - `decision_admin = ANNULER` → 0 pt (event neutralisé)
  - `decision_admin = REDUIRE` → `points_corriges` utilisé
  - Sinon → `points` original
- Sur les **12 derniers mois** uniquement
- Plancher 0, plafond 40

### Composante 3 : ancienneté (20 pts max)
- 1 pt par mois d'inscription Jolene (max 20)
- `mois = (NOW() - soignants.cree_le) / 30.44 jours`

## Formule étab `fn_calculer_score_etab`

```
Score total = note_moyenne (max 40) + comportement (max 40) + délai_paiement (max 20)
```

### Composante 1 : note moyenne reçue des soignants (40 pts max)
Identique à la composante soignant mais sur les notations
`cible_type = ETABLISSEMENT`.

### Composante 2 : comportement (40 pts max)
Identique au soignant mais sur `evenements_score_etab`.

### Composante 3 : délai de paiement moyen (20 pts max)
Sur les factures payées des 12 derniers mois :
```
delai_jours = AVG(date_paiement - date_emission)
```

| Délai moyen | Points |
|---|---|
| ≤ 7 jours | 20 |
| 7-15 jours | 15 |
| 15-30 jours | 10 |
| > 30 jours | 5 |
| Aucune donnée | 15 (défaut neutre) |

## Helpers UI

### `fn_mon_score()`
Raccourci auto-détection soignant/étab pour la `CarteScore`.
Retourne :
```json
{
  "success": true,
  "score_total": 87,
  "composantes": {
    "note_moyenne_pts": 36,
    "note_moyenne_valeur": 4.5,
    "note_count": 12,
    "comportement_pts": 35,
    "comportement_penalites": -5,
    "comportement_bonus": 0,
    "anciennete_pts": 16,
    "anciennete_mois": 16
  }
}
```

### `fn_mes_evenements_score(limit)`
Liste des événements récents pour l'historique :
```json
{
  "success": true,
  "type": "SOIGNANT",
  "events": [
    {
      "id": "...",
      "type_evenement": "ANNULATION_1_12H",
      "points": -10,
      "points_corriges": null,
      "motif": "URGENCE_PERSONNELLE : ...",
      "contestable": true,
      "decision_admin": null,
      "cree_le": "...",
      "mission_id": "..."
    }
  ]
}
```

Le flag `contestable` est calculé : `event.contestable AND decision_admin IS NULL AND reclamation_id IS NULL`.

## Réclamations

Chaque événement avec `contestable=true` peut être contesté par
l'utilisateur via `fn_creer_reclamation_score` (PR 7 Sprint 3.5).
L'admin tranche via `fn_admin_traiter_reclamation` (PR 8) :
- `MAINTENIR` : pas de changement
- `REDUIRE` : `points_corriges` < 0 appliqué
- `ANNULER` : event neutralisé (compte 0 dans le calcul)

Le score est **recalculé automatiquement** à chaque décision admin.

## Événements possibles

### Soignant (`evenements_score_soignant.type_evenement`)
- `ANNULATION_12_24H` (-5)
- `ANNULATION_1_12H` (-10)
- `ASAP_ANNULEE_APRES_FENETRE` (-25)
- `NO_SHOW` (-30) + signalement admin
- `LITIGE_TORT_RECONNU` (variable)
- `NOTE_BASSE_RECUE` (informatif)
- `EVALUATION_NEGATIVE` (informatif)
- `BONUS_AMBASSADEUR` (+ pts)
- `BONUS_FIDELITE` (+ pts)
- `AUTRE`

### Étab (`evenements_score_etab.type_evenement`)
- `ANNULATION_AVANT_CONTRAT` (-3)
- `ANNULATION_CDD_SIGNE` (-10) + indemnité légale
- `ANNULATION_LIBERAL_SIGNE` (-10) + clause pénale
- `ANNULATION_APRES_POINTAGE` (-20) + montant complet dû
- `PAIEMENT_RETARD` (variable)
- `LITIGE_TORT_RECONNU`
- `NOTE_BASSE_RECUE`
- `AUTRE`

## Audit & traçabilité

Toute décision admin laisse trace dans `journaux_audit` :
- `action = ADMIN_ACTION` ou `SYSTEM`
- `evenement = RECLAMATION_SCORE_TRAITEE`
- `details` : decision, points_corriges, motif_admin, event_id, nouveau_score
