# Évaluation reverse étab → soignant (Sprint 5.7)

> Fix **P0-8** audit Sprint 5. Permet à l'établissement de noter le soignant après une mission TERMINEE (sens inverse de Sprint 3.5). Le soignant peut signaler une notation abusive pour modération admin.

## Architecture

Réutilise l'infrastructure Sprint 3.5 (`notations_missions`) avec la valeur d'enum `ETAB_VERS_SOIGNANT` du champ `sens`.

### Critères (4 × 5 étoiles)

| Critère | Description |
|---|---|
| `note_ponctualite` | Respect des horaires de pointage |
| `note_technique` | Qualité technique du soin |
| `note_relationnel` | Relationnel équipe + patients |
| `note_conformite` | Respect des protocoles établissement |

**Note globale** = moyenne des 4 critères, calculée côté UI et stockée côté DB.

## RPCs

| RPC | Auth | Description |
|---|---|---|
| `fn_lister_missions_a_noter_etab()` | étab connecté | Missions TERMINEE 60j sans notation ETAB_VERS_SOIGNANT |
| `fn_creer_notation_mission(mission_id, sens, notes, commentaire)` | étab | Insère notation + propage score soignant via trigger |
| `fn_signaler_notation(notation_id, motif)` | soignant | Signale notation pour modération admin (Sprint 3.5) |
| `fn_admin_masquer_notation(notation_id, motif)` | admin | Masque notation jugée abusive (Sprint 3.5) |

## Frontend

- `/etablissement/evaluations-a-faire` — liste des missions à évaluer + bouton "Noter"
- `<ModaleEvaluerSoignant>` — modale 4 critères + commentaire 500 chars max
- `<NotationsRecues audience="soignant">` — vue soignant des notations reçues
- Bouton "🚩 Signaler cette évaluation" + `<ModaleSignaler>` (motif min 10 chars)

## Workflow

```
Mission TERMINEE
  ↓
Étab voit "Mission à évaluer" sur /etablissement/evaluations-a-faire
  ↓
Étab clique → ModaleEvaluerSoignant ouverte
  ↓
4 critères + commentaire → fn_creer_notation_mission
  ↓
Trigger DB met à jour le score soignant (Sprint 3.5 logique réutilisée)
  ↓
Notification push + email envoyée au soignant
  ↓
Soignant voit notation reçue dans /soignant/profil (onglet notations)
  ↓
Si abusive : bouton "Signaler" → fn_signaler_notation
  ↓
Admin modère via /admin/notations-signalees (Sprint 3.5)
```

## Délai

Mission TERMINEE depuis maximum **60 jours** : au-delà, retirée de la liste à évaluer (pas de notation possible). Évite les évaluations rancunières tardives.

## Garde-fous

- **Une seule notation** par mission par sens (UNIQUE constraint `mission_id + sens`)
- **Auteur = créateur étab** identifié par `auth.uid()` (membre_etablissement actif)
- **Commentaire optionnel** mais limité à 500 caractères
- **Notes 1-5** (CHECK constraint)
- **Audit trail** complet via `journaux_audit`

## Différences avec sens SOIGNANT_VERS_ETAB

| Aspect | Soignant → étab (Sprint 3.5) | Étab → soignant (Sprint 5.7) |
|---|---|---|
| 4 critères | Sécurité, équipement, équipe, organisation | Ponctualité, technique, relationnel, conformité |
| Vue auteur | `/soignant/notations-faites` | `/etablissement/evaluations-a-faire` |
| Vue cible | `/etablissement/notations-recues` | `/soignant/profil` (onglet notations) |
| Signalement | Étab signale soignant | Soignant signale étab |
| Impact score | Score étab (Sprint 3.5) | Score soignant (Sprint 3.5) |
