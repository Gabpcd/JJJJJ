# Notation bidirectionnelle — Soignant ↔ Établissement

Date : 2026-05-03 (Refonte.B + Refonte.E.2)

## 1. Concept

Avant Refonte.B : une seule direction (étab note soignant via ancienne table `evaluations`).

Après Refonte.B : **bidirectionnel symétrique**. Les deux parties d'une mission peuvent se noter mutuellement après mission `TERMINEE`.

- `ETAB_VERS_SOIGNANT` : 4 critères (ponctualité, professionnalisme, qualité du travail, communication)
- `SOIGNANT_VERS_ETAB` : 4 critères (accueil, encadrement, clarté de la mission, paiement)

Stockés dans une table unique `notations_missions` avec une colonne `sens` (enum `sens_notation`).

## 2. Schéma

### Table `notations_missions`

| Colonne | Type | Description |
|---|---|---|
| `id` | UUID | PK |
| `mission_id` | UUID FK | Mission notée |
| `notateur_id` | UUID | Auteur (soignant ou étab) |
| `note_id` | UUID | Cible (étab ou soignant) |
| `sens` | enum `sens_notation` | `ETAB_VERS_SOIGNANT` / `SOIGNANT_VERS_ETAB` |
| `critere_1`, `critere_2`, `critere_3`, `critere_4` | int 1-5 | Notes par critère |
| `commentaire` | text (max 2000) | Optionnel |
| `signale` | bool | Signalement par cible (modération) |
| `masque` | bool | Masquage par admin |
| `masque_par` / `masque_le` | UUID / timestamp | Audit modération |
| `notateur_anonymise` | bool | RGPD : true si compte notateur supprimé |
| `cree_le` / `mis_a_jour_le` | timestamp | |

### Contraintes

- `UNIQUE (mission_id, sens)` : une seule notation par sens et par mission
- `CHECK (critere_1..4 BETWEEN 1 AND 5)`
- Trigger `trg_recalcul_score_v2_notations` recalcule les scores des deux parties après INSERT/UPDATE

## 3. RPCs

### `fn_creer_notation_mission(p_mission_id, p_sens, p_critere_1..4, p_commentaire?)`

- Auth : utilisateur authentifié, doit être partie de la mission
- Vérifie sens cohérent avec rôle (soignant assigné = SOIGNANT_VERS_ETAB, etab = ETAB_VERS_SOIGNANT)
- Vérifie mission `TERMINEE`
- Insertion → trigger recalcul automatique
- Audit `NOTATION_DONNEE` + `NOTATION_RECUE`

### `fn_modifier_notation_mission(p_notation_id, p_critere_1..4, p_commentaire?)`

- **Fenêtre 7 jours** depuis `cree_le`. Au-delà : retourne `{success: false, error: "Notation non modifiable après 7 jours"}`.
- Modification → recalcul auto via trigger UPDATE.

### `fn_compter_missions_sans_notation()` — SOIGNANT et ETAB

Retourne le nombre de missions `TERMINEE` éligibles à notation par cet utilisateur (pas encore notées). Utilisé par `BannerEncourageNotation` pour afficher un bandeau si ≥3 missions non notées.

### `fn_lister_notations_recues(p_user_id?)`

Liste paginée des notations reçues, avec anonymisation (prénom + initiale uniquement, sauf admin).

## 4. UI — Composants

| Composant | Rôle | Usage |
|---|---|---|
| `ModalNoterMission.tsx` | Modal réutilisable 4 critères StarRating + commentaire 2000 chars | Soignant ET étab (sens dynamique) |
| `BoutonNoterMission.tsx` | Wrapper bouton "Noter cette mission" avec auto-cache "déjà noté" | Carte mission, page détail |
| `NotationsRecues.tsx` | Liste anonymisée des notations reçues | `/soignant/score`, `/etablissement/score` |
| `BannerEncourageNotation.tsx` | Bandeau seuil 3 missions non notées, dismiss localStorage 7j | Dashboard soignant + étab |

## 5. Email J+1 (Refonte.D.3 + Refonte.E.2)

Cron quotidien `email-cron-daily` appelle `fn_envoyer_rappels_notation_j1()` :
- Sélectionne missions `TERMINEE` `fin_le > 24h ago` ET pas encore notées par chaque sens
- Insert dans `notifications_notation_j1` (idempotence via UNIQUE `(mission_id, sens)`)
- Déclenche `pg_net.http_post` vers `send-email` avec types `RAPPEL_NOTATION_ETAB` et `RAPPEL_NOTATION_SOIGNANT`
- Audit `RAPPEL_NOTATION_J1_ENVOYE`

Les templates sont dans `supabase/functions/send-email/index.ts`.

## 6. Modération commentaires

### Signalement (par la cible)

- Endpoint UI : bouton "Signaler" sur les notations reçues affichées
- RPC `fn_signaler_notation(p_notation_id, p_motif)` → `signale = true` + audit `NOTATION_SIGNALE`

### Masquage admin

- Page admin (à brancher dans AdminModeration ou dédiée future)
- RPC `fn_admin_masquer_notation(p_notation_id, p_raison)` → `masque = true`, `masque_par`, `masque_le` set + audit `NOTATION_MASQUEE`
- Notations masquées sortent du calcul score v2 (filtre `WHERE masque = false` dans `fn_calculer_score_fiabilite_v2`)

## 7. RGPD

### Anonymisation à la suppression compte

Lors de la suppression RGPD d'un compte (soignant ou étab), les notations dont l'utilisateur est le **notateur** ne sont pas supprimées (elles font partie de l'historique scoring de la cible). À la place :
- `notateur_id` set à `NULL`
- `notateur_anonymise = true`
- Le commentaire éventuel est conservé (déjà anonyme côté UI : "Soignant anonyme" / "Établissement anonyme")

Les notations dont l'utilisateur est le **noté** restent visibles côté notateur, mais l'identité du noté est anonymisée.

### Export RGPD

`fn_exporter_mes_donnees()` v8 inclut :
- `notations_donnees` : toutes les notations dont je suis `notateur_id`
- `notations_recues` : toutes les notations dont je suis `note_id` ET `masque = false`

## 8. Notes tech-debt

| Item | Priorité | Cible |
|---|---|---|
| **Page admin modération notations** : RPCs prêtes, page UI à créer (équivalent `AdminModeration` filtre notations signalées) | P2 | Q3 2026 |
| **Migration evaluations → notations_missions** : table `evaluations` legacy conservée pour historique. À archiver/supprimer dans 6 mois si plus d'usage. | P3 | Novembre 2026 |
| **Notation côté admin (intervention)** : pour l'instant l'admin ne peut que masquer. Pas de RPC pour modifier le contenu. À évaluer selon usage. | — | — |
