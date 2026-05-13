# Page admin alertes anti-triche pointage (Sprint 5.7)

> Fix **P0-11** audit Sprint 5. Expose les alertes Sprint 4.5 (téléportation, mock GPS, cohérence temporelle, QR éloigné) côté admin avec décision structurée. **Aucune action automatique sur compte** — l'admin tranche manuellement.

## Architecture

Réutilise les détections Sprint 4.5 existantes :
- `alertes_systeme` (`TELEPORTATION_DETECTED`, `POINTAGE_INCOHERENT`)
- `presences.arrivee_mock_detected` / `depart_mock_detected`
- `journaux_audit` action `POINTAGE` evenement `QR_SCAN_GPS_ELOIGNE`

## Routes

- `/admin/alertes-pointage` — page principale (KPIs + filtres + liste + traitement)
- Bandeau récap dans `/admin` (dashboard) — composant `<BandeauAlertesAntiTricheAdmin>`

## RPCs

### `fn_admin_resume_alertes_pointage()`

5 KPIs sur 7 derniers jours :

```json
{
  "success": true,
  "kpis": {
    "teleportations_7j": 3,
    "mock_gps_7j": 1,
    "coherence_7j": 5,
    "qr_gps_eloigne_7j": 2,
    "total_ouvertes": 7
  }
}
```

### `fn_admin_lister_alertes_pointage(p_type_filtre?, p_statut_filtre?, p_limit, p_offset)`

Liste paginée des alertes :

- **Type** : `TELEPORTATION_DETECTED` / `POINTAGE_INCOHERENT` / NULL (toutes)
- **Statut** : `OUVERTE` (resolu_le IS NULL) / `RESOLUE` (resolu_le IS NOT NULL) / NULL (toutes)
- 50/page par défaut

### `fn_admin_traiter_alerte_pointage(p_alerte_id, p_decision, p_motif?)`

4 décisions disponibles :

| Décision | Effet |
|---|---|
| `LEGITIME` | Faux positif — aucune sanction, alerte close |
| `FRAUDE_AVERTISSEMENT` | Note + email d'avertissement au soignant |
| `FRAUDE_SUSPENSION_PROPOSEE` | Crée une task admin pour suspension manuelle (PAS automatique) |
| `IGNORER` | Faible importance, alerte close sans action |

Codes erreur : `NON_AUTORISE`, `DECISION_INVALIDE`, `ALERTE_INTROUVABLE`.

Audit trail dans `journaux_audit` avec `evenement='ALERTE_POINTAGE_TRAITEE'`, decision + motif + type_alerte + traite_par + traite_le.

## Frontend

### `AdminAlertesPointage.tsx`

**5 KPI cards** colorées (toutes cliquables → filtres) :
- 🔴 Téléportations (rouge) — détectées par cron `*/15 min`
- 🟠 Mock GPS (orange) — heuristiques `accuracy=0`, vitesse aberrante
- 🟠 Cohérence (orange) — incidents temporels 7 codes
- 🔵 QR > 1km (info) — scan QR loin de l'étab
- 🔴 Total ouvertes (rouge si > 5) — alertes non encore traitées

**Filtres** : type alerte + statut OUVERTE/RESOLUE.

**Liste** : sévérité (badge), message, source, timestamp, statut (badge OUVERTE/RESOLUE).
- **Collapsible détails techniques** : JSON pretty-printed (`details` jsonb)
- **Pagination** : 50/page

### `ModaleTraiterAlerte`

- 4 **radio buttons** (LEGITIME / FRAUDE_AVERTISSEMENT / FRAUDE_SUSPENSION_PROPOSEE / IGNORER)
- Motif obligatoire min 10 chars (sauf LEGITIME et IGNORER, optionnel)
- Bouton "Confirmer décision" → appel `fn_admin_traiter_alerte_pointage`

### `BandeauAlertesAntiTricheAdmin`

Affiché en tête du dashboard admin (`/admin`) :
- Récap visuel des 4 types d'alertes 7j
- Badge **ATTENTION** + couleur destructive si `total_ouvertes > 5`
- Sinon couleur warning
- Caché si aucune alerte 7j
- Click → redirection `/admin/alertes-pointage`

## Workflow

```
Détection automatique (Sprint 4.5 crons)
  ↓
INSERT alertes_systeme ou presences.*_mock_detected
  ↓
Admin connecté voit le bandeau sur dashboard
  ↓
Admin clique → /admin/alertes-pointage
  ↓
Filtre statut=OUVERTE
  ↓
Pour chaque alerte : examiner details techniques (jsonb)
  ↓
Click "Traiter" → ModaleTraiterAlerte
  ↓
Choix décision + motif → fn_admin_traiter_alerte_pointage
  ↓
Alerte close (resolu_le = now) + journaux_audit
  ↓
Si FRAUDE_SUSPENSION_PROPOSEE : task admin créée pour suspension manuelle
```

## Garde-fous

- **AUCUNE suspension automatique** : `FRAUDE_SUSPENSION_PROPOSEE` crée juste une task admin
- **AUCUNE pénalité financière soignant** : seuls scoring + avertissement possibles
- **Motif obligatoire** pour décisions de fraude (audit légal)
- **Audit trail complet** : décision + motif + acteur + timestamp + alerte d'origine
- **Faux positifs** : décision `LEGITIME` clarifie le traitement
- **est_admin() check** sur toutes les RPCs

## Cas d'usage

1. Téléportation Paris→Marseille en 30 min entre 2 pointages → vérifier explication soignant → décider
2. Mock GPS détecté (accuracy=0 + coords rondes) → enquêter device → avertissement si confirmé
3. Cohérence : pointage entrée 02h, sortie 23h le même jour → POINTAGE_INCOHERENT → demander correction
4. QR > 1km : soignant scan QR à la maison → discuter avec étab → souvent légitime (clinique mobile)

## Différences avec Sprint 3.5 réclamations

| Sprint | Sprint 3.5 Réclamations | Sprint 5.7 Alertes pointage |
|---|---|---|
| Source | Contestation soignant d'une pénalité | Détection automatique fraude |
| Initiateur | Soignant | Système (crons) |
| Décisions | MAINTENIR / REDUIRE / ANNULER | LEGITIME / FRAUDE_AVERTISSEMENT / FRAUDE_SUSPENSION_PROPOSEE / IGNORER |
| Impact | Modification event scoring | Suspension manuelle (jamais auto) |
