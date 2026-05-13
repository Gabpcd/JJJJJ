# Évaluation post-mission soignant (Sprint 6)

> Fix **P1-2** audit Sprint 5. Affichage du bouton "Noter la mission" et du wizard d'ouverture de litige directement depuis l'historique soignant.

## Composants livrés

- **`BoutonNoterMission`** (existant Sprint 3.5) intégré dans `HistoriqueMissions.tsx` sur chaque carte mission TERMINEE avec `sens='SOIGNANT_VERS_ETAB'`. Auto-masqué si déjà noté.
- **`WizardOuvertureLitige`** (nouveau Sprint 6 PR 2) — wizard 3 étapes pour signaler un problème depuis l'historique.

## Workflow

```
Mission TERMINEE
  ↓
HistoriqueMissions affiche carte avec 2 actions :
  • Bouton "⭐ Noter l'établissement" (variant secondary)
  • Bouton "Signaler un problème" (warning)
  ↓
Click "Noter" → ModalNoterMission Sprint 3.5
   4 critères 1-5 étoiles + commentaire optionnel + note publique/privée
   → fn_creer_notation_mission(sens='SOIGNANT_VERS_ETAB', ...)
   → propagation score étab via trigger
  ↓
Click "Signaler" → WizardOuvertureLitige (modale 3 étapes)
   Étape 1 : type litige (PAIEMENT/CONDITIONS/COMPORTEMENT/AUTRE)
   Étape 2 : détail factuel (min 20 chars, max 2000)
   Étape 3 : récap + confirmation
   → fn_ouvrir_litige_rate_limited(p_mission_id, p_motif='[TYPE] détail')
   → notif étab + admin Jolene + ouverture fil discussion
```

## Types litige

Le wizard structure le motif en 4 catégories :

| Code | Description |
|---|---|
| `PAIEMENT` | Montant erroné, retard, heures non comptées… |
| `CONDITIONS` | Horaires non respectés, poste différent, matériel manquant… |
| `COMPORTEMENT` | Conflit, irrespect, comportement inapproprié… |
| `AUTRE` | Autre problème lié à la mission |

Le motif final est préfixé : `[CONDITIONS] Le poste promis n'était pas celui prévu…`

## Garde-fous

- Rate limit côté backend (`fn_ouvrir_litige_rate_limited` 3 ouvertures / 24h).
- Pas de litige multiple sur même mission (UNIQUE constraint).
- Pas de pénalité automatique : tout litige est négocié via fil discussion + médiation admin si pas d'accord 72h.
- Champ "Signaler" caché si litige déjà ouvert sur la mission.
