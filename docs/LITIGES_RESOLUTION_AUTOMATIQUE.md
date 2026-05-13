# Litiges — résolution automatique des accords

> Sprint 3.5 PR 1-3. Quand deux parties se mettent d'accord sur une
> modification (horaires, montant, annulation, compensation), Jolene
> propage automatiquement la modification aux données aval : presences,
> factures, paiements Stripe, déclaration Chorus, DPAE URSSAF.

## Vue d'ensemble

```
1. Soignant ou étab ouvre un litige (table litiges)
2. Conversation dans FilDiscussionLitige
3. Une partie propose un accord via FormulaireAccord :
   - Type (HORAIRES, MONTANT, ANNULATION, COMPENSATION, MIXTE, ACCORD_SIMPLE)
   - Modifications structurées (datetime, montant, %, motif)
   - Justification
4. fn_cloturer_litige_avec_payload :
   - Stocke payload sur litiges.payload_modifications
   - Marque l'accord de l'appelant (accord_soignant ou _etablissement)
5. Autre partie voit la proposition en encart visuel
6. Autre partie clique "Accepter" → re-appelle la même RPC
7. Double accord détecté → CLOTURE + fn_executer_modifications_litige
8. Exécution atomique des sub-routines DB :
   - fn_modifier_horaires_presence
   - fn_annuler_mission_complete
   - fn_appliquer_compensation_partielle
9. Side-effects enqueués dans externalisation_actions :
   - STRIPE_REFUND_PARTIEL / TOTAL
   - CHORUS_RECYCLER_FACTURE
   - DPAE_ANNULATION (URSSAF 48h)
   - AVOIR_PDF_GENERATION
10. Cron worker (Sprint 4) traite les side-effects async
```

## Types de modifications

### `MODIFICATION_HORAIRES`
Champs :
- `pointage_arrivee_le` (datetime)
- `pointage_depart_le` (datetime)

Effets :
- `presences` mis à jour (`pointage_arrivee_le`, `pointage_depart_le`, `duree_brute_min`, `duree_nette_min`)
- Avoir partiel + nouvelle facture (queue)

### `MODIFICATION_MONTANT`
Champs :
- `montant_total_corrige` (numeric)

Effets :
- Avoir partiel + nouvelle facture avec nouveau montant

### `ANNULATION_TOTALE`
Champs :
- `motif_annulation` (text)

Effets :
- `missions.statut = ANNULEE_LITIGE`
- `presences.heures_ajustees_litige = 0`
- Stripe TOTAL refund
- Chorus Pro `recyclerFacture` (motif ANNULATION)
- DPAE annulation URSSAF si CDD signé
- Avoir total

### `COMPENSATION_PARTIELLE`
Champs :
- `pourcentage_compensation` (1-100)

Effets :
- `presences.heures_ajustees_litige` = heures originales × (1 - %/100)
- Stripe refund partiel = % du paiement
- Avoir partiel

### `MIXTE`
Combine `MODIFICATION_HORAIRES` + `MODIFICATION_MONTANT`.

### `ACCORD_SANS_MODIFICATION`
Aucune donnée aval modifiée. Marque `litiges.statut = RESOLU` + audit.
Utile quand les parties s'expliquent mais aucune correction chiffrée
n'est nécessaire (ex : excuses, malentendu).

## Table `externalisation_actions`

Queue async des side-effects qui ne tiennent pas dans une transaction PG :

| Colonne | Description |
|---|---|
| `type_action` | STRIPE_REFUND_*, CHORUS_RECYCLER_FACTURE, DPAE_ANNULATION, EMAIL_NOTIF, PUSH_NOTIF, AVOIR_PDF_GENERATION |
| `payload` | JSON spécifique à l'action (montants, IDs, motif) |
| `source` | LITIGE_EXEC / ANNULATION_MISSION / AUTRE |
| `source_id` | UUID du litige ou de la mission source |
| `statut` | PENDING / PROCESSING / DONE / ERROR |
| `tentatives` | Compteur de retry |
| `derniere_erreur` | Stack trace si erreur |

**Cron worker** (à implémenter Sprint 4) :
- Pagination 50/run, retry 3 fois avec backoff exponentiel (1s, 5s, 30s)
- Edge function `process-externalisation-actions`
- Traite par batch de type pour batcher les appels Stripe / Chorus

## Atomicité

Toute la résolution DB est dans une transaction Postgres :
- `litiges.modifications_executees` ← true au succès
- Sub-routines `fn_modifier_horaires_presence` etc. réussissent OU rollback
- Side-effects externes (Stripe, Chorus, DPAE, PDF) sont **enqueués** :
  ils ne bloquent pas la résolution DB.
- Si un side-effect échoue côté worker → `externalisation_actions.statut = ERROR`,
  alerte admin pour traitement manuel.

## Idempotence

`fn_executer_modifications_litige` est idempotent :
- Skip si `litiges.modifications_executees = true`
- Retourne `already_executed: true` avec la date d'exécution originale

Ce qui permet de rejouer en cas de doute sans risque de double facturation.

## UI `FormulaireAccord`

Composant `src/components/litige/FormulaireAccord.tsx` :
- Affiche le formulaire de création si pas de proposition existante
- Affiche l'encart "Proposition reçue" si l'autre partie a déjà proposé
- Bouton "Accepter l'accord" → re-appelle `fn_cloturer_litige_avec_payload`
  avec le même payload → déclenche `RESOLU` + exec
- Bouton "Contre-proposer" → l'utilisateur ouvre un nouveau formulaire
  avec un payload différent (l'ancien est écrasé)

## Notifications

Le worker `externalisation_actions` envoie via `send-email` et `send-push` :
- `LITIGE_RESOLU` aux 2 parties à la clôture
- `LITIGE_MODIFICATIONS_EXECUTEES` aux 2 parties après exec
- `AVOIR_GENERE` à l'étab si avoir émis
- `REVERSEMENT_AJUSTE` au soignant si paiement modifié

## Sécurité

- `fn_cloturer_litige_avec_payload` vérifie que l'appelant est partie au litige
- RLS sur `externalisation_actions` : SELECT admin uniquement
- Aucune modification ne peut être exécutée sans **double accord** (sauf
  médiation admin avec `litiges.statut = RESOLU_ADMIN`)
- Audit trail complet dans `journaux_audit` action='SYSTEM' avec
  `evenement = LITIGE_MODIFICATIONS_EXECUTEES`
