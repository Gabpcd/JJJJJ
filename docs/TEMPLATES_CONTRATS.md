# Templates de contrats — guide développeur

> Sprint 1 PR 5 + Sprint 2 PR 5 : 14 templates en DB (CDD master + 13 libéraux).

## Inventaire

| Slug `type_contrat` | Sprint | Cas d'usage |
|---|---|---|
| `CDD` | S1 | Tous les contrats salariés (18 professions via `{{profession}}`) |
| `REMPLACEMENT_LIBERAL` | S1 | Libéral générique (fallback) |
| `LIBERAL_MEDECIN_CABINET` | S1 | Médecin libéral en cabinet médical |
| `LIBERAL_DENTISTE_CABINET` | S1 | Dentiste en cabinet dentaire |
| `LIBERAL_IDE_CABINET` | S1 | IDEL en cabinet d'infirmiers libéraux |
| `LIBERAL_SAGE_FEMME_CABINET` | S1 | Sage-femme libérale en cabinet |
| `LIBERAL_KINE_CABINET` | S1 | Kiné libéral en cabinet de kiné |
| `LIBERAL_MEDECIN_CLINIQUE` | S2 | Médecin libéral en clinique privée |
| `LIBERAL_MEDECIN_EHPAD` | S2 | Médecin coordonnateur en EHPAD |
| `LIBERAL_SAGE_FEMME_CLINIQUE` | S2 | Sage-femme libérale en clinique |
| `LIBERAL_KINE_CLINIQUE` | S2 | Kiné libéral en clinique SSR |
| `LIBERAL_ORTHOPHONISTE_CABINET` | S2 | Orthophoniste en cabinet |
| `LIBERAL_ERGOTHERAPEUTE_CABINET` | S2 | Ergothérapeute en cabinet/HAD |
| `LIBERAL_PSYCHOMOTRICIEN_CABINET` | S2 | Psychomotricien en cabinet |

## Format de stockage

Table `templates_contrat` :

```sql
id              uuid PK
type_contrat    text         -- slug ci-dessus
nom             text         -- libellé humain
version         int          -- v1, v2, ...
est_actif       boolean      -- on garde l'historique
contenu_html    text         -- HTML avec variables {{xxx}}
variables       jsonb        -- ["etablissement_nom", ...]
```

Le rendu utilise `replace(/\{\{\s*([^}]+?)\s*\}\}/g, ...)` (cf. edge function
`generate-contrat-mission-pdf` + `ContratMission.tsx` fallback).

## Variables disponibles

### Établissement
- `etablissement_nom`, `etablissement_siret`, `etablissement_finess`
- `etablissement_adresse`, `etablissement_ville`
- `etablissement_email`, `etablissement_telephone`

### Soignant
- `soignant_prenom`, `soignant_nom`, `soignant_date_naissance`
- `soignant_adresse`
- `soignant_rpps`, `soignant_siret`
- `soignant_profession`

### Mission
- `intitule_mission`, `mission_service`
- `debut_le`, `fin_le`, `duree_heures`
- `taux_horaire` (formaté €)
- `profession` (slug lisible)

### Contrat
- `numero_contrat`, `type_contrat`
- `date_signature` (au moment du rendu PDF figé)

### CDD-spécifique
- `motif_cdd` (default "remplacement / surcroît temporaire")
- `convention_collective` (default selon étab)
- `periode_essai_jours` (default 1)
- `caisse_retraite` (default AGIRC-ARRCO)
- `regime_prevoyance`

## Résolution du template

L'edge function `generate-contrat-mission-pdf` (PR 3 S2) utilise la RPC
`fn_resolve_template_contrat(type_contrat, profession, type_etab)` pour
choisir le slug exact :

1. Si `type_contrat` libéral + profession + type_etab → tente `LIBERAL_<PROF>_<TYPE_ETAB>`
2. Si trouvé → match `specifique`
3. Sinon → fallback `REMPLACEMENT_LIBERAL` master (ou `CDD` master)
4. Match `master_fallback`

## Ajouter un nouveau template

```sql
INSERT INTO public.templates_contrat (type_contrat, nom, version, est_actif, contenu_html, variables)
VALUES (
  'LIBERAL_ORTHOPTISTE_CABINET',
  'Prestation libérale — Orthoptiste en cabinet',
  1, true,
  $html$<h1>...{{etablissement_nom}}...</h1>$html$,
  '["etablissement_nom",...]'::jsonb
);
```

Bonnes pratiques :
- Toujours inclure la **mention obligatoire Jolene plateforme technique** en début
- Référencer les **articles ordinaux** propres à la profession (R.4127-65, R.4321-129, etc.)
- Préciser la **caisse de retraite** propre (CARMF, CARPIMKO, CARCDSF, CIPAV)
- Footer "**Modèle Jolene v1 — pour question juridique, consultez votre conseil**"
- Marquer `est_actif = true` ; la version précédente est conservée pour audit

## CDD master vs CDD par profession

**Décision Sprint 1 Q5** : pas de templates CDD par profession. Le CDD master
utilise les variables `{{profession}}`, `{{convention_collective}}`,
`{{caisse_retraite}}` et couvre les 18 professions salariées via substitution
au moment du rendu (cf. `buildVariables()` dans `generate-contrat-mission-pdf`).

Cela évite la duplication de 18 fois 95% du même texte légal. Si une profession
nécessite une clause CDD spécifique (ex: clause de non-concurrence pour
pharmaciens), créer un slug `CDD_<PROFESSION>` et `fn_resolve_template_contrat`
le préférera automatiquement au master.
