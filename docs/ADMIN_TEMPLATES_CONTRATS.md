# Page admin templates contrats (Sprint 5.7)

> Fix **P0-10** audit Sprint 5. Page admin permettant d'éditer + activer/désactiver les 14 templates de contrats Sprint 2 sans intervention DB directe.

## Templates Sprint 2

14 templates couvrant tous les cas de mission :

| Template | Type | Notes |
|---|---|---|
| **CDD master** | `CDD` | 18 professions via variable `{{profession}}` |
| **REMPLACEMENT_LIBERAL master** | `REMPLACEMENT_LIBERAL` | Tous types d'étab |
| 12 LIBERAL_* spécifiques | `LIBERAL_*` | Cas particuliers profession × type_etab |

Total : **14 templates actifs**.

## Routes

- `/admin/templates-contrats` — liste avec 3 KPI cards (Total / Actifs / Inactifs)
- `/admin/templates-contrats/:id` — éditeur HTML + sidebar variables

## RPCs

### `fn_admin_lister_templates_contrats()`

Retourne la liste avec stats par template :
- `id`, `nom`, `type_contrat`, `profession`, `type_etablissement`
- `version` (incrémentée auto à chaque modification)
- `est_actif` (boolean)
- `taille_contenu` (chars HTML)
- `cree_le`, `modifie_le`

### `fn_admin_detail_template_contrat(p_template_id)`

Retourne le contenu HTML complet + `variables` jsonb (déclaration des variables jinja-like attendues).

### `fn_admin_modifier_template_contrat(p_template_id, p_contenu, p_nom?, p_variables?)`

- Validation `length(contenu) >= 50` chars
- Incrémente `version = version + 1` automatiquement
- Met à jour `modifie_le = now()` + audit `journaux_audit`
- Codes erreur : `NON_AUTORISE`, `TEMPLATE_INTROUVABLE`, `CONTENU_TROP_COURT`

### `fn_admin_toggle_template_contrat(p_template_id)`

Inverse `est_actif`. Audit.

## Frontend

### `AdminTemplatesContrats.tsx`

- 3 KPI cards : Total / Actifs / Inactifs
- Table : nom, type, version, statut (badge), taille, modifié
- Actions par ligne : **Éditer** (lien) + **Activer/Désactiver** (toggle)
- Bandeau warning : *"La modification affecte uniquement les NOUVEAUX contrats. Les contrats déjà signés conservent leur template d'origine (immutables pour audit légal)."*

### `AdminEditerTemplateContrat.tsx`

Layout 2-colonnes :

**Gauche (éditeur)** :
- Textarea HTML monospace, 80% height
- Toggle **Éditer / Aperçu** (avec `dangerouslySetInnerHTML`)
- Validation min 50 chars
- Bouton "Enregistrer" → confirmation modale avec `v_ancien + 1` affiché

**Droite (sidebar variables)** :
- 16 variables jinja-like disponibles, cliquables pour insertion :
  - `{{soignant_prenom}}`, `{{soignant_nom}}`, `{{soignant_profession}}`, `{{rpps}}`
  - `{{etablissement_nom}}`, `{{etablissement_siret}}`, `{{etablissement_adresse}}`
  - `{{mission_intitule}}`, `{{mission_service}}`, `{{taux_horaire}}`
  - `{{date_debut}}`, `{{date_fin}}`, `{{duree_heures}}`
  - `{{montant_brut}}`, `{{date_signature}}`, `{{numero_contrat}}`
- Display des variables originales déclarées dans le template (jsonb `variables`)

## Garde-fous

- **Immutabilité signature** : un contrat signé garde son contenu d'origine en `contrat_mission.contenu_html` (snapshot). Les modifications de template n'affectent QUE les nouveaux contrats créés.
- **Versioning auto** : version incrémentée à chaque save, audit trail complet.
- **Validation min 50 chars** : empêche un wipe accidentel.
- **Confirmation modale** : avant chaque save, affiche `v_ancien → v_nouveau`.

## Cas d'usage

1. Mise à jour cadre légal (ex: nouvelle convention collective) → édition template + bump version
2. Désactivation temporaire d'un template buggé → toggle sans suppression
3. Ajout variable manquante → édition + audit trail

## Sécurité

- `est_admin()` check sur toutes les RPCs
- Aucun template ne peut être supprimé (immutabilité historique)
- `audit_trail` pour chaque modification et toggle
