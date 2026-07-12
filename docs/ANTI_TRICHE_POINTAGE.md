# Anti-triche pointage (Sprint 4.5)

> Architecture défensive multi-couches contre la fraude au pointage.
> Décision Gabrielle : **aucune photo selfie**, **aucune suspension automatique**, **aucune pénalité financière soignant**.

## Vue d'ensemble — hiérarchie des méthodes

L'app propose 3 méthodes de pointage, présentées par ordre de fiabilité :

1. **Scan QR** (recommandé, 1 tap) — preuve physique de présence à l'établissement
2. **GPS** — fallback si QR HS, contrôlé par la `tolerance_gps_metres` configurée
3. **Code numérique secours** — 6 chiffres communiqués par l'établissement, pour les cas extrêmes (réseau soignant HS, caméra HS)

À côté, des contrôles passifs et asynchrones :

- Détection mock GPS (faux GPS)
- Détection téléportation (>200 km/h entre 2 pointages d'un même soignant)
- Cohérence temporelle (arrivée avant fin, départ après arrivée, etc.)

**Tous les incidents génèrent des alertes `alertes_systeme` SANS action automatique.** L'administration Jolene tranche manuellement.

## Couche 1 — QR code (PR 4-7)

### Génération (étab)
- RPC `fn_generer_qr_mission(mission_id, type)` : génère un token `gen_random_uuid()::text || '_' || gen_random_bytes(8)` (hex 16 caractères).
- Désactive automatiquement les tokens précédents (un seul QR actif par mission).
- Auto-généré au passage `SIGNE_COMPLET` du contrat (trigger `trg_dec_auto_generer_qr_mission`).
- Types : `ARRIVEE`, `DEPART`, `UNIVERSEL` (le RPC choisit la méthode selon le contexte).

### Affichage
- Composant `<QRPointageEtab />` : QR 240×240 SVG, plein écran, impression A4 (popup pré-formatée).
- Stats nb_scans en temps réel.

### Scan (soignant)
- Composant `<ScannerQRPointageSoignant />` :
  - Routing `isNative()` : `@capacitor/barcode-scanner` (natif) vs `html5-qrcode` (web)
  - Acquisition GPS ponctuelle et non bloquante au scan (timeout 5s)
  - Appel `fn_valider_scan_qr(token, lat?, lng?, precision?, terminal_id?)`
  - 10 codes erreur mappés FR :
    - `QR_INVALIDE` / `QR_EXPIRE` / `QR_MISSION_AUTRE`
    - `HEURE_TROP_TOT` / `HEURE_TROP_TARD`
    - `DEJA_POINTE` / `DEPART_SANS_ARRIVEE` / `DEPART_TROP_RAPIDE`
    - `NON_AUTHENTIFIE` / `NON_AUTORISE`
  - Fallback `onFallbackCode` vers le code secours en cas d'échec
- Validation back : audit `QR_SCAN_GPS_ELOIGNE` si distance > 1 km

### Queue offline
- `qr-offline-queue.ts` : stockage `localStorage` + listeners `online` / Capacitor Network
- Retry × 3 par scan, retire à `OK` ou `QR_EXPIRE`
- Indicateur visuel `<IndicateurFileOffline />` dans `CartePointage`

## Couche 2 — GPS (existant + Sprint 3 + PR 8)

### Tolérance adaptive (PR 8)
- CHECK constraint `tolerance_gps_metres` range `[30, 1000]` (vs `[50, 5000]` initial)
- DEFAULT 100 m (vs 500)
- Configurable par étab via `/etablissement/parametres`

### Détection mock GPS (PR 2 + lib)
- `src/lib/mock-detection.ts` : retourne `niveau: 'AUCUN' | 'SUSPECT' | 'FORT'`
- Heuristiques cumulables :
  - `accuracy === 0` (trop parfait pour un vrai GPS)
  - lat/lng parfaitement rondes (`.000000`)
  - vitesse > 200 m/s en mode piéton
  - position identique pendant >1 min en marche
- `detecterJailbreakIos()` : check Cydia

Si `FORT` détecté : flag `presences.arrivee_mock_detected` / `depart_mock_detected` → audit admin (`POINTAGE_MOCK_GPS_SUSPECT`).

### Détection téléportation (PR 2)
- `fn_vitesse_entre_pointages(lat1, lng1, t1, lat2, lng2, t2)` IMMUTABLE — Haversine km/h
- `fn_detecter_teleportations()` cron `*/15 min` :
  - Compare les pointages d'un même soignant
  - Si vitesse > 200 km/h → `alertes_systeme` severite CRITICAL
  - Marque `presences.alerte_teleportation = true`

## Couche 3 — Code numérique secours (PR 9)

### Génération étab
- RPC `fn_generer_code_secours_mission(mission_id, type)` retourne le code **en clair UNE SEULE FOIS** (puis hash `bcrypt` via `crypt(code, gen_salt('bf'))` en DB).
- Désactive les codes précédents.
- TTL : 15 min par défaut.

### Saisie soignant
- Composant `<SaisieCodeSecours />` : 6 cases input chiffres, auto-focus enchaîné, paste support, backspace recule.
- Appel `fn_valider_code_secours(mission_id, code, lat?, lng?, precision?, terminal_id?)`.
- 6 codes erreur structurés.

### Sécurité
- Code stocké uniquement en hash bcrypt. **Aucun log en clair.**
- `nb_essais` incrémenté à chaque tentative ratée (audit).
- Échec silencieux côté caller (pas de leak par timing).

## Couche retirée avant publication — ping GPS continu

Le plugin natif, le wrapper et l'interface de consentement au suivi continu ont
été supprimés : aucune partie du client ne démarrait ou n'arrêtait réellement
ce suivi. Les tables/RPC historiques éventuels ne constituent pas une collecte
active. La preuve de présence repose sur QR, position ponctuelle au pointage,
code de secours et contrôles de cohérence.

## Couche 5 — Cohérence temporelle (PR 11)

### `fn_evaluer_coherence_pointage` (IMMUTABLE)
Helper pure function qui retourne un `jsonb[]` d'incidents :

| Code | Sévérité | Condition |
|---|---|---|
| `ARRIVEE_TROP_PRECOCE` | WARNING | arrivée > 1h avant début |
| `ARRIVEE_APRES_FIN` | CRITICAL | arrivée après fin |
| `DEPART_AVANT_ARRIVEE` | CRITICAL | départ < arrivée |
| `DEPART_TRES_ANTICIPE` | WARNING | départ > 4h avant fin |
| `DEPART_TRES_TARDIF` | WARNING | départ > 4h après fin |
| `DUREE_NULLE` | CRITICAL | durée nette ≤ 0 |
| `DUREE_EXCESSIVE` | WARNING | durée nette > 24h |
| `DEPART_MANQUANT` | CRITICAL | arrivée + pas de départ + fin > 6h |

### Worker
- `fn_verifier_pointages_incoherents` SECURITY DEFINER, traite presences avec mission terminée (>1h) ou arrivée orpheline (>6h après fin).
- Crée `alertes_systeme` (sévérité max des incidents).
- Marque `presences.coherence_verifiee_le` + `presences.coherence_incidents` (anti-doublon).
- Cron `jolene_verifier_pointages_incoherents` `*/30 min`.

## Couche 6 — UI hiérarchisée (PR 12)

`<CartePointage />` présente :

1. **Bouton principal** large `SCANNER LE QR (recommandé)` (1 tap)
2. **Grille secondaire** 50/50 : GPS + Code secours
3. **Indicateur file offline** quand `qr-offline-queue` non vide
4. Modals plein écran pour scanner / saisie code

États : `futur` / `trop_tot` / `pret` / `en_mission` / `termine`. Pause masque les boutons de pointage.

## Tests (PR 13)

12 tests E2E DB-level dans `e2e/flows/anti-triche-pointage.spec.ts` :
QR génération/scan, codes erreur, téléportation, hash bcrypt, ping GPS, cohérence temporelle, tolérance CHECK, worker.

**Tests UI exclus** : le scanner QR natif et le GPS réel ne sont pas testables
par Playwright headless. Test manuel sur appareils réels.

## Tableau récapitulatif des migrations

| PR | Migration | Effet |
|---|---|---|
| PR 1 | `20260513270000` (fix) | Index partiel sans NOW() |
| PR 2 | `20260514080000` | Téléportation cron + cols mock_detected |
| PR 4 | `20260514090000` | QR codes mission backend |
| PR 8 | `20260514100000` | Tolerance GPS adaptive [30, 1000] |
| PR 9 | `20260514110000` | Code numérique secours bcrypt |
| PR 10 | `20260514120000` | Ping GPS background opt-in |
| PR 11 | `20260514130000` | Cohérence temporelle + cron |

## Cron jobs actifs

| Cron | Schedule | Fonction |
|---|---|---|
| `jolene_alerte_teleportation` | `*/15 min` | Détection téléportation |
| `jolene_purger_pings_gps` | `0 3 * * *` | Purge pings >30j RGPD |
| `jolene_verifier_pointages_incoherents` | `*/30 min` | Cohérence temporelle |

## Décisions architecturales

- **Aucune photo selfie** : friction utilisateur et RGPD lourd ; QR + GPS ponctuel suffisent.
- **Aucune suspension automatique** : toute action sur compte passe par admin manuel.
- **Aucune pénalité financière soignant** : conforme prudhommes.
- **Indemnités légales étab** auto-calculées (cf. `ANNULATION_MISSION.md`).
- **Fallback gracieux** : si caméra HS → code secours ; si réseau HS → queue offline ; si GPS HS → QR.
