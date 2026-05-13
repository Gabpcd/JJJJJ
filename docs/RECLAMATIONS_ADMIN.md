# Réclamations admin — workflow contestation score

> Sprint 3.5 PR 7-8. Tout événement de score `contestable=true` peut être
> contesté par l'utilisateur. Un admin Jolene tranche : MAINTENIR /
> REDUIRE / ANNULER. La décision est propagée automatiquement et le
> score recalculé en temps réel.

## Workflow complet

```
1. User reçoit une pénalité de score (annulation, note basse, etc.)
2. User voit l'événement dans son profil score (CarteScore)
3. User clique "Contester" sur l'event (bouton visible si contestable)
4. ModaleReclamationScore s'ouvre :
   - Sélection motif (URGENCE_MEDICALE, DEUIL, FORCE_MAJEURE,
     ERREUR_JOLENE, CONTEXTE_PARTICULIER, AUTRE)
   - Texte libre min 20 chars
   - Upload justificatif optionnel (PDF/image, max 5 MB) → bucket
     'justificatifs'
5. fn_creer_reclamation_score :
   - Validations : motif, texte, propriété event, contestable
   - INSERT reclamations_score (statut=PENDING)
   - UPDATE event.reclamation_id pour lier
   - Notif admin via externalisation_actions
6. Admin voit la réclamation dans /admin/reclamations-score
7. Admin clique "Traiter" → modale décision :
   - MAINTENIR (réclamation rejetée)
   - REDUIRE avec points_corriges < 0 (ex: -5 au lieu de -10)
   - ANNULER (event neutralisé, 0 pt)
   - Motif admin obligatoire (min 10 chars, visible par user)
8. fn_admin_traiter_reclamation :
   - UPDATE reclamations_score : statut=TREATED + decision + motif_admin
   - Propagation auto sur l'event :
     decision_admin + points_corriges + motif_admin
   - Recalcul auto score via fn_calculer_score_soignant/_etab
   - Notif user email + push avec décision + motif
9. User voit son score recalculé en temps réel
10. User voit la décision dans son onglet "Mes réclamations"
```

## RPCs

### `fn_creer_reclamation_score(event_id, event_type, motif_categorie, texte_libre, justificatif_path)`
- Auth : propriétaire de l'event
- Validations : event existe, contestable, pas déjà traité, pas déjà
  réclamation PENDING en cours
- Crée `reclamations_score` + lie via `event.reclamation_id`
- Notification admin auto

### `fn_mes_reclamations(statut?)`
Retourne les réclamations de l'utilisateur courant, filtre statut
optionnel (PENDING/TREATED/CANCELLED).

### `fn_admin_traiter_reclamation(reclamation_id, decision, points_corriges, motif_admin)`
- Auth admin requis
- Validations : decision IN (MAINTENIR, REDUIRE, ANNULER), motif min 10
  chars, points_corriges < 0 si REDUIRE
- Propage la décision sur l'event + recalcul score
- Notification user via externalisation_actions

### `fn_admin_lister_reclamations(statut, limit)`
Liste enrichie avec données de l'event lié (type, points, motif,
cree_le). Filtre statut. Inclut `jours_attente` calculé pour highlight
des réclamations > 7 jours.

## Tables

### `reclamations_score`
Polymorphe via discriminant `evenement_type` + CHECK XOR :
- Si SOIGNANT : `evenement_soignant_id` rempli, `evenement_etab_id` NULL
- Si ETAB : `evenement_etab_id` rempli, `evenement_soignant_id` NULL

Champs clés :
- `contesteur_id` : user qui réclame
- `motif_categorie` : URGENCE_MEDICALE / DEUIL / FORCE_MAJEURE / ERREUR_JOLENE / CONTEXTE_PARTICULIER / AUTRE
- `texte_libre` : explication (min 20 chars)
- `justificatif_storage_path` : path bucket 'justificatifs' (optionnel)
- `statut` : PENDING / TREATED / CANCELLED
- `decision_admin` : MAINTENIR / REDUIRE / ANNULER (NULL tant que PENDING)
- `motif_admin` : justification de la décision (visible par user)
- `traitee_par_admin_id` + `traitee_le`

### Liens avec `evenements_score_*`
Quand admin tranche, ces colonnes sont mises à jour sur l'event :
- `decision_admin` : copie de la décision
- `points_corriges` : nouveau total si REDUIRE
- `motif_admin` : copie du motif
- `traite_par_admin_id` + `traite_le`

## UI utilisateur

### `ModaleReclamationScore.tsx`
Modale plein écran avec :
- Pré-affichage de l'event contesté (type, points, motif)
- Select motif catégorie (5 options labellisées avec emojis)
- Textarea texte libre + compteur caractères
- Upload justificatif (PDF/image, max 5 MB, Storage bucket `justificatifs`)
- Encart pédagogique : examinée par admin
- Bouton "Envoyer" → `fn_creer_reclamation_score`

Intégration dans `CarteScore` (à câbler côté pages score) :
- Bouton "Contester" affiché si `event.contestable = true`
- Disabled si réclamation déjà PENDING

## UI admin

### Page `/admin/reclamations-score`
- Tabs PENDING / TREATED / TOUS
- Liste triée par cree_le ASC (les plus anciennes en haut)
- Badge "Xj d'attente" :
  - Amber si < 7 jours
  - Destructive (rouge) si > 7 jours
- Détail event + motif catégorie + texte + justificatif (lien storage)
- Bouton "Traiter" → modale décision

### Modale décision
- Radio MAINTENIR / REDUIRE / ANNULER
- Si REDUIRE : champ points_corriges (validation < 0, défaut = max(-5, original/2))
- Textarea motif admin (min 10 chars, visible par user)
- Encart : "propagation auto + recalcul score + notif user"
- Bouton "Appliquer la décision" → `fn_admin_traiter_reclamation`

## Sécurité

- RLS strict sur `reclamations_score` : SELECT propriétaire + admin
- INSERT/UPDATE/DELETE bloqué directement → uniquement via RPCs
- Auth check dans chaque RPC (`est_admin()` ou owner)
- Justificatifs Storage : bucket `justificatifs` privé, signed URL admin only

## Audit

Chaque opération laisse trace :
- `RECLAMATION_SCORE_CREEE` (user)
- `RECLAMATION_SCORE_TRAITEE` (admin) avec decision + motif + nouveau_score

## Délais opérationnels

- **Cible** : traitement admin < 48h
- **Alerte** : visible côté admin si > 7 jours (badge rouge)
- **Cron** : recommandé d'ajouter cron weekly pour alerter Sentry sur
  réclamations PENDING > 14 jours (Sprint 4)
