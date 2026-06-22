# Diagnostic & cible — système de pointage (multi-jours, codes rotatifs, paie)

> Pourquoi « ça devait être implémenté depuis longtemps » mais ça ne marche pas.

## TL;DR

Trois mécanismes de pointage se sont empilés. Le **frontend est branché sur le
plus simple et le plus ancien**, alors que le **système sophistiqué que tu décris
(codes rotatifs, pauses, multi-jours, alimente la paie) existe en entier côté
backend mais est dormant** (jamais branché, code de départ jamais initialisé).

## Création de mission : déjà « 1 annonce = N jours »

Une nouvelle mission est **toujours créée comme UNE seule mission** via
`fn_creer_mission_multi_jours` → N lignes dans `mission_creneaux`
(`type_creneau = 'PREVISIONNEL'`). Pas « une mission par jour ».
Les anciens modèles (`fn_creer_serie`, colonne `serie_id`, regroupement par
`extraireSerieId(description)`) sont du **legacy** à nettoyer.

## Les 3 systèmes de pointage

| # | Système | Fonctions clés | Tables | Frontend | Modèle |
|---|---|---|---|---|---|
| ① | **Ancien simple** | `fn_pointer_arrivee`, `fn_pointer_depart`, `fn_pointer_*_pause`, `fn_valider_scan_qr` (QR via `qr_codes_mission`), `fn_codes_pointage_mission` (codes statiques) | `presences` | ✅ **branché** (PresencesSoignant, ScannerQRPointageSoignant, QRPointageEtab, CodesPointageMission, SyncHorsLigne) | 1 arrivée + 1 départ (+ 1 pause) **par mission**. Codes `missions.code_arrivee`/`code_depart` fixes. |
| ② | **Rotatif (cible)** | `fn_scanner_code_pointage` | `scans_pointage`, créneaux `EFFECTIF` | ❌ **rien ne l'appelle** | Code `missions.code_pointage_actif` qui **se régénère à chaque scan** (+ HMAC). Alterne `OUVERTURE`/`FERMETURE` → N segments/jour (gère les pauses). Chaque segment = un créneau `EFFECTIF` horodaté/arrondi au ¼h → **base de la paie**. Anti-rejeu 2 min, validation étab si hors plage. |

### Le bug bloquant de ①
`fn_pointer_arrivee` refuse tout 2ᵉ pointage sur la même mission
(*« Vous avez déjà pointé votre arrivée »*) et `presences` n'a **pas de
`creneau_id`** → sur une mission multi-jours, le soignant est bloqué dès le jour 2.

### Pourquoi ② est dormant
- Le **frontend ne l'appelle nulle part**.
- `code_pointage_actif` (le code que `fn_scanner_code_pointage` matche) n'était
  **jamais initialisé** (le trigger `dec_generer_codes_pointage` ne posait que les
  codes de ①). → **corrigé en PR 1.**

## Cible

Basculer **tout le pointage sur le système ②** et brancher la paie sur les
créneaux `EFFECTIF`, puis retirer ①.

## Plan par étapes (PRs)

- **PR 1 (cette PR)** — *fondation* : initialiser `code_pointage_actif` à la
  création (trigger) + backfill missions actives. Additif, zéro régression.
- **PR 2** — *soignant* : écran de pointage appelle `fn_scanner_code_pointage`
  (un seul bouton « Pointer » qui alterne ouverture/fermeture selon
  `prochain_type_scan`), gère le code rotatif renvoyé, affiche « segment en cours ».
- **PR 3** — *établissement* : affichage du **code rotatif courant**
  (`code_pointage_actif`) avec rafraîchissement temps réel (Realtime) + QR ;
  liste des scans/segments par jour ; validation des scans `validation_etab_requise`.
- **PR 4** — *paie* : calcul des heures depuis les créneaux `EFFECTIF`
  (somme des segments) au lieu de `presences.arrivee/depart`.
- **PR 5** — *nettoyage* : retrait du système ① (fonctions + appels frontend) et
  du legacy série (`serie_id` / `extraireSerieId`). Migration des écrans présences.

## Notes de prudence
- Cœur **paie + légal** : on avance par PRs réversibles, on ne retire ① qu'en
  dernier (PR 5), une fois ② validé de bout en bout.
- Pré-lancement (0 mission multi-jours, 0 présence en prod) → moment idéal pour
  converger sans migration de données lourde.
