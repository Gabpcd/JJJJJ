# Statuts `factures_honoraires` — référentiel et rendu visuel

Ce document recense les valeurs possibles de la colonne `factures_honoraires.statut`
et décrit le comportement visuel associé dans le PDF généré par `generate-invoice`.

## Valeurs autorisées (CHECK constraint)

| Statut        | Sens métier                                                                  | Source           |
| ------------- | ---------------------------------------------------------------------------- | ---------------- |
| `BROUILLON`   | Facture en préparation (non émise, modifiable librement).                    | État par défaut   |
| `EMISE`       | Facture émise, envoyée au client. Verrouillée par immutabilité (trigger).    | `generate-invoice` |
| `PAYEE`       | Facture réglée (webhook Stripe ou confirmation admin).                       | Webhook paiement  |
| `ANNULEE`     | Facture annulée (litige résolu en faveur d'annulation totale).               | `fn_admin_resoudre_litige` cas `ANNULER_REEMETTRE` ou `AVOIR` |
| `FACTORISEE`  | Facture cédée à un affactureur (pas encore payée par le débiteur final).     | RPC affacturage   |
| `EN_RETARD`   | Échéance dépassée, relance en cours.                                         | Cron relances     |
| `REMPLACEE`   | Facture remplacée par une nouvelle (chaînage via `facture_precedente_id`).   | CP-LITIGES-7a FIX 6 (référentiel), consommation RPC à venir |

Migration de référence : `supabase/migrations/20260417130705_fix6_statut_remplacee.sql`.

## Rendu visuel dans le PDF (CP-LITIGES-7a FIX 7)

Toutes les factures PDF sont régénérées via l'endpoint `generate-invoice` en
mode REGEN (flag `pdf_a_regenerer=TRUE` + appel direct depuis
`fn_admin_resoudre_litige` via pg_net, cf. FIX 18). Les statuts suivants
déclenchent un **tampon diagonal** sur la première page :

### `ANNULEE`

- **Texte principal** : `ANNULEE` (100 pt, gras)
- **Couleur** : rouge (`rgb(0.86, 0.15, 0.15)`)
- **Opacité** : 35 %
- **Rotation** : +30° (diagonale bas-gauche → haut-droite)
- **Position** : centrée sur la première page (ancrage `(90, 320)` sur A4 595×842)

### `REMPLACEE`

- **Texte principal** : `REMPLACEE` (100 pt, gras)
- **Sous-titre** : `par facture <numero>` (22 pt, gras, ancrage `(170, 280)`)
  — le numéro est obtenu via reverse lookup
  `WHERE facture_precedente_id = id AND ORDER BY cree_le DESC LIMIT 1`.
  Absent si la facture successeur n'est pas (encore) émise.
- **Couleur** : orange (`rgb(0.95, 0.55, 0.05)`)
- **Opacité** : 35 % (principal), 45 % (sous-titre)
- **Rotation** : +30°

### Mention légale

- `REMPLACEE` ajoute également, dans le corps de la facture, une mention
  textuelle : `Facture rectificative remplacee par <numero> (art. L441-9 C. com.).`
  Cette mention est posée en orange sous le bloc d'en-tête (après le méta
  numéro/dates).
- Pas de mention légale ajoutée pour `ANNULEE` : le tampon est suffisant
  (pas de remplacement, pas de rectification).

### Statuts qui ne déclenchent pas de tampon

`BROUILLON`, `EMISE`, `PAYEE`, `FACTORISEE`, `EN_RETARD` : PDF rendu normal,
sans tampon. La mention `BROUILLON` n'est jamais exposée côté client
(flow interne uniquement).

## Tests visuels

Procédure de smoke-test manuel : `docs/tests-annulation/README.md`.

## Historique

- **CP-LITIGES-6** : support AVOIR (type_document, facture_precedente_id, mention art. L441-10).
- **CP-LITIGES-7a FIX 6** : ajout statut `REMPLACEE` au CHECK.
- **CP-LITIGES-7a FIX 7** : tampons ANNULEE / REMPLACEE + mention L441-9 (ce doc).
- **CP-LITIGES-7a FIX 18** : regen PDF déclenchée immédiatement via pg_net.
