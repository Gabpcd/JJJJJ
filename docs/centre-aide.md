# Centre d'aide Jolene — `/aide`

Date : 29 avril 2026

## Vue d'ensemble

Le centre d'aide est accessible publiquement sur `/aide` (ou `/faq`, `/help`).
23 articles disponibles à ce jour, organisés par audience et catégorie.

- **Recherche full-text** : index GIN PostgreSQL avec `to_tsvector('french')` et `websearch_to_tsquery` (tolérant aux fautes).
- **Filtre par audience** : SOIGNANT (10), ETABLISSEMENT (8), COMMUN (5 — toujours inclus quel que soit le filtre).
- **Bouton aide global** : icône `?` flottante bottom-right présente sur toutes les pages `LayoutApp` (sauf `/aide`).
- **Lien footer** : « ❓ Centre d'aide » dans `FooterLegal`.

## Architecture

### Schema DB
- Table `articles_aide` (id, slug UNIQUE, titre, contenu Markdown, audience CHECK, categorie, ordre_affichage, publie, cree_le, mis_a_jour_le).
- Index GIN full-text français.
- RLS : SELECT public anon+authenticated WHERE publie=true. Admin tout.
- Trigger `mis_a_jour_le` automatique.

### RPC
- `fn_rechercher_aide(p_query?, p_audience?)` → JSONB `{articles[], count}`.
  - Ranking via `ts_rank` si query fournie.
  - Filtre audience : COMMUN toujours inclus en plus de l'audience demandée.

### Frontend
- `src/pages/PageAide.tsx` — page liste, recherche débounced 250ms, sync URL.
- `src/pages/PageAideArticle.tsx` — article unique avec `renderMarkdown` (h1-h3, listes, liens, code, hr).
- `src/components/BoutonAideGlobal.tsx` — bouton flottant.

## Liste complète des 23 articles

### Soignant (10)

| Slug | Catégorie | Sujet |
|---|---|---|
| `inscription-soignant-liberal-salarie-mixte` | Inscription | LIBERAL/SALARIE/MIXTE |
| `comment-verifier-mon-rpps` | Inscription | RPPS, hiérarchie pro, dépannage |
| `signer-mandat-facturation` | Mandat | Mandat v1.2, art. 289 I-2 CGI, re-signature |
| `comment-candidater-mission` | Missions | Filtres, candidature, annulation |
| `comment-fonctionne-pointage` | Pointage | Code 6 chiffres, GPS, créneaux multiples |
| `comprendre-ma-facture-honoraires` | Facturation | Hebdo vs finale, numérotation, Factur-X |
| `comprendre-mon-bulletin-paie` | Bulletin paie | R3243-1, IFM, ICP, cotisations |
| `defacto-paiement-j2` | Facturation | Opt-in global, frais 1-3 %, désactivation |
| `comment-ouvrir-litige` | Litiges | 4 catégories, fenêtres F1/F2/F3, gel facture |
| `mes-droits-rgpd-soignant` | RGPD | 6 droits, export 21 clés, conservation 10 ans |

### Établissement (8)

| Slug | Catégorie | Sujet |
|---|---|---|
| `etab-comment-m-inscrire` | Inscription | Phase 1 (compte) + Phase 2 (contrat + RIB) |
| `etab-contrat-service-jolene` | Inscription | Contrat v1.0, signature canvas, hash SHA-256 |
| `etab-pourquoi-deposer-rib` | Inscription | Storage privé, signed URLs, pas de débit auto |
| `etab-pourquoi-uploader-contrat-travail` | Missions | Art. 5.2, requalification URSSAF, CDDU |
| `etab-publier-premiere-mission` | Missions | LIBERAL vs SALARIE, créneaux, majorations |
| `etab-comprendre-commission-jolene` | Facturation | 15 % par défaut, cascade, figement assignation |
| `etab-resoudre-litige` | Litiges | Fenêtres F2/F3, gel scope, médiation admin |
| `etab-gerer-absence-soignant` | Pointage | 4 cas A/B/C/D, fn_resoudre_absence_mission |

### Commun (5)

| Slug | Catégorie | Sujet |
|---|---|---|
| `mes-droits-rgpd` | RGPD | Droits RGPD globaux, plainte CNIL |
| `comment-jolene-assure-securite` | RGPD | RLS 87 tables, audit append-only, PITR, Captcha |
| `cgu-jolene` | Légal | Résumé CGU + lien `/legal/cgu` |
| `contacter-support` | Légal | Canaux + délai 48h ouvrées |
| `pourquoi-je-recois-emails-bienvenue` | Inscription et profil | Série J0/J1/J3/J7 + opt-out via `/parametres/notifications` |

## Comment ajouter un nouvel article

1. INSERT direct (admin) :
```sql
INSERT INTO public.articles_aide (slug, titre, audience, categorie, ordre_affichage, contenu, publie)
VALUES ('mon-slug', 'Mon titre', 'SOIGNANT', 'Catégorie', 50, $$# Contenu Markdown
...$$, true);
```

2. Backoffice admin (P3 future) — page `/admin/articles-aide` à créer si besoin éditeur visuel.

## Conventions

- **Slug** : kebab-case, URL-friendly, unique, en français
- **Audience** : SOIGNANT, ETABLISSEMENT, COMMUN
- **Catégories utilisées** :
  - Inscription et profil
  - Missions
  - Mandat de facturation
  - Bulletin de paie
  - Pointage et présence
  - Facturation et paiement
  - Litiges
  - RGPD et données personnelles
  - Légal
- **Ordre d'affichage** : 10 = premier dans la catégorie, 100 = défaut, plus c'est bas plus c'est haut
- **Markdown** : h2/h3 (h1 réservé au titre auto), listes - et 1., liens [texte](url), `code`, **gras**, `---` séparateur

## Tests SQL (PASS)

| Test | Attendu | Obtenu |
|---|---|---|
| Total publiés | 23 | 23 ✓ |
| nb SOIGNANT | 10 | 10 ✓ |
| nb ETABLISSEMENT | 8 | 8 ✓ |
| nb COMMUN | 5 | 5 ✓ |
| Audience SOIGNANT (incl COMMUN) | 15 | 15 ✓ |
| Audience ETABLISSEMENT (incl COMMUN) | 13 | 13 ✓ |
| Recherche "RPPS" | ≥1 | 7 ✓ |
| Recherche "Defacto" | ≥1 | 4 ✓ |
| Recherche "URSSAF" | ≥1 | 5 ✓ |
| Recherche "litige" | ≥2 | 13 ✓ |
| Recherche "absence" | ≥1 | 2 ✓ |
| Recherche "RGPD" | ≥2 | 8 ✓ |
