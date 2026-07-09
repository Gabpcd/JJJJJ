# Lot 11 — Investigation : chip « Libéral » sur une mission CDD (Facturation)

> Constat d'audit (09/07) : dans Facturation établissement, une mission en CDD
> affiche un chip « Libéral ». **Cause racine identifiée — correction au Lot 14.**

## Cause racine

Dans `src/pages/FacturationEtablissement.tsx`, la section « missions non payées »
rend **deux chips à sources différentes** :

1. **Chip régime (le fautif)** : `<TypeExerciceBadge type={m.soignant_type_exercice} />`
   — la donnée est le **type d'exercice du PROFIL soignant** (`SALARIE` /
   `LIBERAL` / `MIXTE`), pas le contrat de la mission.
2. **Chip contrat (la vérité mission)** : `Contrat {isSalarie ? 'salarié (CDD)' : 'libéral'}`
   — dérivé de `m.type_contrat_applique`, le champ qui fait foi.

Un soignant au profil `type_exercice = LIBERAL` qui réalise une mission en CDD
(`type_contrat_applique = SALARIE`) affiche donc « Libéral » + « Contrat
salarié (CDD) » côte à côte : le doublon régime-du-profil vs contrat-de-la-mission.

## Décision (à exécuter au Lot 14, avec la bifurcation stricte D4)

- Le chip affiché sur une ligne de facturation doit refléter **le régime de la
  mission** (`type_contrat_applique`), jamais le profil du soignant.
- Correction à la source : remplacer la source du `TypeExerciceBadge` (ou le
  supprimer au profit du seul chip contrat), + test de non-régression.
- Si le pattern « profil vs contrat » est confirmé ailleurs (Publier l'a aussi
  eu : « Type de profil recherché » corrigé au Lot 11), ajouter la ligne aux
  patterns du CLAUDE.md : *« régime affiché = type_contrat_applique de la
  mission, jamais type_exercice du profil »*.

## Pourquoi pas corrigé au Lot 11

Le Lot 11 est une passe UX sans toucher aux flux ; la donnée `soignant_type_exercice`
alimente peut-être d'autres usages (filtre, tri) dans la même page — la
correction se fait au Lot 14 avec le test dédié, comme prévu par la feuille de
route.
