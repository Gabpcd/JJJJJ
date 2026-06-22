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

## ⚠️ Ce qui était DÉJÀ construit (ne pas refaire)

Audit du backend (2026-06-22) : le système ② était quasi complet. Seuls le
branchement frontend et l'init du code manquaient. **Déjà en place** :

- `fn_scanner_code_pointage` — scan rotatif complet (codes régénérés, OUVERTURE/
  FERMETURE, pauses, créneaux EFFECTIF, anti-rejeu 2 min, GPS, validation flag).
- **Paie/facturation sur EFFECTIF** : `fn_calculer_montant_periode` calcule les
  heures via `GREATEST(somme PREVISIONNEL, somme EFFECTIF)`. `fn_lister_missions_a_facturer`,
  `fn_detail_facture`, `dec_calculer_finance_mission` s'appuient dessus.
  → **La paie lit déjà les segments EFFECTIF. Rien à refaire ici.**
- `fn_declarer_fin_retroactive` — fallback de saisie rétroactive (« pas de téléphone »).
- `fn_sync_mission_creneaux` — synchro créneaux.

## Plan par étapes (PRs) — état réel

- **PR 1** ✅ *(mergée + déployée)* — fondation : init `code_pointage_actif` au
  trigger + backfill. Additif, zéro régression.
- **PR 2/3** ✅ *(mergée + déployée, #664)* — branchement frontend de la boucle :
  RPC `fn_etat_pointage_mission` + `AffichageCodeRotatifEtab` (code rotatif temps
  réel par polling 5 s + QR + segments) + `PointageRotatifSoignant` (saisie/scan
  → `fn_scanner_code_pointage`). Remplace `CartePointage` dans les onglets actifs.
- **PR 4** ~~paie~~ — **DÉJÀ FAIT** (cf. ci-dessus). Reste seulement à *vérifier*
  end-to-end qu'un cycle scan → EFFECTIF → facture sort le bon montant.
- **PR 3-bis (vrai trou restant)** — *validation étab des scans* : aucune fonction
  ne pose `scans_pointage.valide_par_etab` aujourd'hui. À ajouter pour les scans
  `validation_etab_requise = true` (anomalies : en avance / >24h). **Non bloquant
  pour la paie** (qui lit EFFECTIF quelle que soit la validation) — c'est de
  l'anti-fraude/litige. + brancher l'UI du fallback `fn_declarer_fin_retroactive`.
- **PR 5** — *nettoyage* : retrait du système ① (`presences` / `fn_pointer_*` /
  `CartePointage` / `fn_valider_scan_qr` / `fn_codes_pointage_mission`) et du legacy
  série (`serie_id` / `extraireSerieId`), une fois ② vérifié de bout en bout.

## Notes de prudence
- Cœur **paie + légal** : on ne retire ① qu'en dernier (PR 5), une fois ② vérifié.
- Pré-lancement (0 mission multi-jours, 0 présence en prod) → moment idéal pour
  converger sans migration de données lourde.
