# Annulation candidature soignant (Sprint 3.5 + Sprint 5.5 PR 1)

> Workflow d'annulation d'une candidature **après acceptation** par l'établissement.
> Avant acceptation, le soignant peut retirer librement sa candidature (pas couvert par ce doc).

## Principe

Une fois la candidature **ACCEPTEE**, la mission devient `ASSIGNEE` côté DB. Le soignant a alors une **fenêtre de rétractation de 30 minutes** pour annuler sans aucun impact sur son score. Au-delà, une **grille de pénalité** s'applique selon le délai restant avant le début de mission.

### Principes directeurs

- ✅ Aucune pénalité financière soignant (interdit en CDD, géré via litige en libéral)
- ✅ Aucune suspension automatique du compte
- ✅ Pénalités score contestables via la page score Sprint 3.5
- ✅ Transparence totale : conséquences affichées AVANT confirmation

## Grille de pénalité Sprint 3.5

Calculée par le helper IMMUTABLE `fn_calculer_penalite_annulation_soignant(p_acceptee_a, p_debut_mission, p_est_asap)` :

| Délai depuis acceptation | Délai jusqu'à mission | Cas | Points |
|---|---|---|---|
| **< 30 min** | n/a | Fenêtre rétractation | **0** (libre) |
| ≥ 30 min | > 24h avant mission | Anticipation suffisante | 0 |
| ≥ 30 min | 12h-24h avant | Annulation 12-24h | **-5** |
| ≥ 30 min | 1h-12h avant | Annulation 1-12h | **-10** |
| ≥ 30 min (ASAP) | < 2h avant | ASAP annulée tardive | **-25** |
| ≥ 30 min | ≤ 1h ou commencée | No-show | **-30 + signalement admin** |

Tous ces événements sont contestables via `fn_creer_reclamation_score` (Sprint 3.5).

## Flux UI

### Composant `AnnulationCandidatureTimer` (`src/components/soignant/AnnulationCandidatureTimer.tsx`)

Affiché dans la section "ASSIGNEE" de `DetailMissionSoignant.tsx`. Refresh toutes les 10 secondes.

- **Fenêtre 30 min** : carte verte "Vous pouvez annuler sans impact (X min restantes)".
- **Hors fenêtre** : carte adaptée (warning/orange/destructive) avec le bucket de pénalité + description.

### Composant `ModaleAnnulationCandidature` (`src/components/soignant/ModaleAnnulationCandidature.tsx`)

Modale plein écran ouverte au clic "Annuler ma participation".

1. **Récap mission** (intitulé, étab, dates).
2. **`AnnulationCandidatureTimer` intégré** : conséquences en temps réel.
3. **Motif structuré** (dropdown 6 valeurs) :
   - `URGENCE_PERSONNELLE`, `URGENCE_MEDICALE`, `DEUIL`, `PROBLEME_TRANSPORT`, `CHANGEMENT_AVIS`, `AUTRE`
4. **Texte libre** obligatoire (min 20 chars).
5. **Justificatif optionnel** PDF/image (max 5 MB) → bucket `justificatifs` path `annulations-candidature/{candidature_id}/{timestamp}_{filename}`.
6. **Coche obligatoire** "J'ai compris les conséquences".
7. Appel `fn_annuler_candidature_soignant(candidature_id, motif_categorie, texte_libre, justificatif_storage_path)`.

## RPCs backend (Sprint 3.5)

### `fn_calculer_penalite_annulation_soignant`
- IMMUTABLE pure function
- Retourne `{ libre: boolean, points: int, motif: text, signalement_admin?: boolean }`

### `fn_annuler_candidature_soignant`
- SECURITY DEFINER
- Validations : auth.uid(), motif dans enum, texte_libre ≥ 20 chars, candidature appartient au soignant, candidature ACCEPTEE
- Calcule pénalité via helper IMMUTABLE
- Crée `evenement_score_soignant` si points < 0 (contestable=true par défaut)
- Si no-show → signalement admin (alerte_systeme)
- Update candidature → `ANNULEE_SOIGNANT`
- Update mission → `OUVERTE` (re-disponible)
- Notification push + email à l'étab
- Audit `CANDIDATURE_ANNULEE_SOIGNANT`

### `fn_dans_fenetre_retractation(candidature_id)`
- STABLE helper retournant `boolean`
- `NOW() - acceptee_a < INTERVAL '30 minutes'`

## Codes erreur retournés

| Code | Cas |
|---|---|
| `NON_AUTHENTIFIE` | Pas de session active |
| `NON_AUTORISE` | Candidature ne lui appartient pas |
| `MOTIF_INVALIDE` | Motif hors enum |
| `TEXTE_REQUIS` | Texte libre < 20 chars |
| `CANDIDATURE_INTROUVABLE` | UUID introuvable |
| `STATUT_INVALIDE` | Candidature pas ACCEPTEE |

Mapping FR géré côté UI (`ModaleAnnulationCandidature` : `codeErreurFr`).

## Tests Playwright (`e2e/flows/annulation-candidature-soignant.spec.ts`)

10 tests DB-level couvrant :
- Helper : 5 buckets calculés correctement
- RPC : motif invalide, candidature introuvable
- E2E seed : fenêtre rétractation, `fn_dans_fenetre_retractation`

Tests UI exclus (timer + modale testés sur preview Vercel).
