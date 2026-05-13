# Pointage GPS — Architecture & sécurité

> Sprint 3 PR 3 — hardening production-grade. Audit Sprint 3 a corrigé
> l'absence de calcul Haversine côté serveur et l'absence de validation
> auto à J+72h.

## Flow utilisateur

```
1. Soignant ouvre /soignant/missions/:id (mission ASSIGNEE ou EN_COURS)
2. Composant CartePointage.tsx + BoutonPointage.tsx affichent
   "📍 Pointer mon arrivée"
3. Au clic :
   a. ConsentementGPS.tsx demande l'autorisation RGPD (1ère fois uniquement)
   b. navigator.geolocation.getCurrentPosition() — Web Geolocation API
      (Capacitor Geolocation natif en backlog Sprint 4)
   c. Options : { enableHighAccuracy: true, timeout: 10000, maximumAge: 0 }
4. Appel RPC fn_pointer_arrivee(mission_id, lat, lng, precision, terminal_id, modele)
   → Backend calcule distance Haversine vers etablissements.adresse_lat/lng
   → Si distance ≤ etablissements.tolerance_pointage_m (default 500m) → OK
   → Sinon : refus avec error_code=HORS_PERIMETRE + distance + tolerance
5. Si refus GPS / hors périmètre / pas de signal :
   → Soignant tape le code 6 chiffres affiché par l'étab dans
     SaisieCodePointage.tsx → fn_pointer_arrivee(..., p_code_arrivee='123456')
   → Backend bypass distance, vérifie code == missions.code_arrivee
```

## RPCs serveur

### `fn_pointer_arrivee(mission_id, lat, lng, precision, terminal_id, modele, code)`
- Si `code` fourni → bypass GPS, prioritaire (mode dégradé batiment)
- Sinon : `lat`/`lng` requis, calcul Haversine vs `etablissements.adresse_lat/lng`
- Refus si distance > `etablissements.tolerance_pointage_m`
- Storage : `presences.distance_etablissement_m`, `presences.perimetre_gps_valide`,
  `presences.methode_pointage_arrivee` (GPS ou CODE)
- Marque la mission `EN_COURS`

### `fn_pointer_depart(presence_id, lat, lng, precision, terminal_id, modele, code)`
- Symétrique avec `fn_pointer_arrivee`
- Met à jour `pointage_depart_le` + `methode_pointage_depart` + colonnes départ

### `fn_haversine_distance_m(lat1, lng1, lat2, lng2)`
- Helper utilitaire IMMUTABLE — distance entre 2 points GPS en mètres
- Algorithme : formule de Haversine, rayon Terre 6 371 km
- Retourne `numeric` (mètres entiers)
- Testé : Paris ↔ Lyon ≈ 392 km, Paris ↔ Paris+50m ≈ 50m

## Codes d'erreur retournés

| `error_code` | Cause | Action UI |
|---|---|---|
| `CODE_INCORRECT` | Code de secours saisi ≠ `missions.code_arrivee/depart` | "Vérifiez avec l'étab" |
| `GPS_MANQUANT` | lat/lng NULL et pas de code | "Activez le GPS ou demandez le code à l'étab" |
| `HORS_PERIMETRE` | distance > tolerance | Affiche distance + tolerance, propose code |

Réponse `HORS_PERIMETRE` :
```json
{
  "success": false,
  "error_code": "HORS_PERIMETRE",
  "error": "Vous êtes à 750m de l'établissement (tolérance 500m). Utilisez le code fourni par l'établissement.",
  "distance_m": 750,
  "tolerance_m": 500
}
```

## Tolérance configurable

`etablissements.tolerance_pointage_m` (default **500m**, range 50–5000m).
Admin peut ajuster pour les étabs avec :
- GPS bruité (sous-sols, bâtiments massifs) → augmenter à 1000m
- Petits cabinets avec position GPS précise → diminuer à 100m

## Validation automatique J+72h

`fn_valider_presences_72h_auto()` exécutée par **pg_cron** toutes les 6h :

```sql
SELECT cron.schedule('jolene_valider_presences_72h', '15 */6 * * *',
  $$SELECT public.fn_valider_presences_72h_auto()$$);
```

Critères :
- `pointage_depart_le < NOW() - INTERVAL '72 hours'`
- `valide_par_etablissement = false`
- `motif_litige IS NULL`
- `valide_auto_72h_le IS NULL`

Met à jour :
- `valide_par_etablissement = true`
- `valide_le = NOW()` (si pas déjà set)
- `valide_auto_72h_le = NOW()` (tracking)

Audit dans `journaux_audit` avec `evenement = 'PRESENCES_VALIDEES_AUTO_72H'`
+ count.

## Mode offline

Si le soignant pointe sans connexion (zone blanche hôpital) :
1. Frontend stocke le pointage en localStorage (`stockerPointageHorsLigne` dans
   `src/lib/horsLigne.ts`)
2. Au retour réseau (event `online`), un sync worker (Sprint 4) renverra
   les pointages en file à `fn_pointer_arrivee` avec l'horodatage original
3. Backlog : auto-sync via service worker

## Capacitor mobile (Sprint 4 roadmap)

Aujourd'hui le pointage utilise `navigator.geolocation` (Web API) qui marche
dans le wrapper Capacitor. Future amélioration : utiliser `@capacitor/geolocation`
en natif :
- Permissions iOS/Android plus claires
- Précision GPS améliorée (background)
- Plugin Permissions runtime mieux géré

Permissions déjà déclarées :
- `ios/App/App/Info.plist` : `NSLocationWhenInUseUsageDescription`
- `android/app/src/main/AndroidManifest.xml` : `ACCESS_FINE_LOCATION`, `ACCESS_COARSE_LOCATION`

## Litige & contestation

Si l'étab conteste les heures pointées dans les 72h :
1. UPDATE presences SET motif_litige = '...'
2. Litige enregistré (table `litiges`)
3. fn_valider_presences_72h_auto skip cette présence (motif_litige IS NOT NULL)
4. Workflow litige standard prend le relais (mediation, admin, etc.)

## Tests E2E

`e2e/flows/pointage-gps.spec.ts` (à activer Sprint 4 avec mock GPS).
Couvre :
- Pointage GPS valide (distance < tolerance) → OK
- Pointage GPS hors zone → HORS_PERIMETRE, propose code
- Code de secours valide → OK
- Code de secours invalide → CODE_INCORRECT
- Pointage offline → queue
- Validation auto J+72h (test cron manuel via `SELECT fn_valider_presences_72h_auto()`)

## Forensic

Chaque pointage capture :
- `arrivee_lat/lng`, `depart_lat/lng` (coordonnées brutes)
- `arrivee_precision_gps_m`, `depart_precision_gps_m`
- `arrivee_id_terminal`, `depart_id_terminal` (device fingerprint)
- `arrivee_modele_terminal`, `depart_modele_terminal` (User-Agent simplifié)
- `arrivee_ip`, `depart_ip`
- `distance_etablissement_m`, `perimetre_gps_valide`
- `methode_pointage_arrivee`/`depart` (GPS ou CODE)
- `alerte_teleportation` (flag si vitesse > 200 km/h entre 2 pointages — Sprint 4)
