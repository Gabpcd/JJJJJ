# Tolérance pointage GPS étab (Sprint 4.5 PR 8 + Sprint 5.5 PR 8)

> Configuration de la distance maximale autorisée entre le soignant et l'établissement pour qu'un pointage GPS soit validé.

## Champ DB

`etablissements.tolerance_pointage_m` (integer, CHECK `[30, 1000]`, DEFAULT `100`).

- Backend défini Sprint 4.5 PR 8 (migration `20260514100000_pr8s45_tolerance_adaptive.sql`).
- UI étab livrée Sprint 5.5 PR 8 (avant : feature invisible, valeur figée DEFAULT 100).

## Usage runtime

- **Pointage GPS** (`fn_pointer_arrivee` / `fn_pointer_depart`) : vérifie distance ≤ tolérance, sinon refus avec code `HORS_PERIMETRE`.
- **Scanner QR** (`fn_valider_scan_qr`) : utilise la valeur pour déclencher alerte `QR_SCAN_GPS_ELOIGNE` si écart > 1 km, mais valide tout de même (QR = preuve physique prioritaire).
- **Téléportation cron** : utilise la tolérance comme paramètre de calcul de plausibilité.

## RPC dédiée (Sprint 5.5 PR 8)

`fn_modifier_tolerance_pointage_etab(p_tolerance_pointage_m integer) RETURNS jsonb`

- Validation range `[30, 1000]` → code `HORS_RANGE` sinon
- Sécurité : `auth.uid()` + `mon_etablissement_id()`
- Audit `MODIFICATION_PROFIL` avec ancienne/nouvelle valeur
- Retour `{ success, tolerance_pointage_m, horodatage }`

### Codes erreur

| Code | Cas |
|---|---|
| `NON_AUTHENTIFIE` | Pas de session |
| `NON_AUTORISE` | Pas d'établissement associé |
| `VALEUR_REQUISE` | NULL |
| `HORS_RANGE` | < 30 ou > 1000 |

## UI

`src/components/etablissement/TolerancePointageGps.tsx`, intégrée dans `Parametres.tsx` tab "config" (en tête).

### Features
- Slider range 30-1000 step 10
- Saisie numérique alternative (input number)
- Affichage grande valeur courante en mètres
- Info-bulle pédagogique :
  - **100 m** zone urbaine
  - **200 m** zone rurale
  - **500 m+** grands campus
- Conseil dynamique selon la valeur courante
- Boutons Réinitialiser + Enregistrer (désactivés si pas dirty)
- Codes erreur mappés FR

### Workflow
1. Au montage : `fn_mon_etablissement_complet` retourne `tolerance_pointage_m`.
2. Edition slider/input → state local `valeur`.
3. Sauvegarde → `fn_modifier_tolerance_pointage_etab(p_tolerance_pointage_m)`.
4. Notification succès + reset `valeurInitiale`.

## Pourquoi pas étendre `fn_modifier_mon_etablissement` ?

`fn_modifier_mon_etablissement` accepte 18 paramètres optionnels. Ajouter un 19e nécessiterait soit :
1. `CREATE OR REPLACE` impossible (changement de signature)
2. `DROP + CREATE` risqué (perte des grants, dépendances)
3. Surcharge avec signature différente (encombre namespace)

La RPC dédiée `fn_modifier_tolerance_pointage_etab` respecte le principe single-responsibility et reste indépendante des autres modifications profil.

## Audit Sprint 5.5

- **PR 8** (#141) — Fix P0-4 audit Sprint 5.
