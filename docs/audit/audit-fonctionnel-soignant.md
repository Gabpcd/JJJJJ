# Audit fonctionnel hybride — Phase 1 : soignant

> **Méthodo** : lecture de code + tests SQL via MCP Supabase, sans navigateur.
> **Date** : 2026-04-27 · **Branche** : `audit/phase-1`

## Sommaire

- [Récap matrice](#recap-matrice)
- [IDE / IBODE / IADE](#ide-ibode-iade)
- [SAGE_FEMME](#sage_femme)
- [KINE](#kine)
- [MEDECIN](#medecin)
- [PHARMACIEN / PREPARATEUR_PHARMA](#pharmacien--preparateur_pharma)
- [MANIPULATEUR_RADIO](#manipulateur_radio)
- [AS / AES](#as--aes)
- [DIETETICIEN / ERGOTHERAPEUTE / PSYCHOMOTRICIEN](#dieteticien--ergotherapeute--psychomotricien)
- [ORTHOPHONISTE](#orthophoniste)
- [Findings](#findings)

## Recap matrice

| Profession | RPPS | LIBERAL | Catégorie installation libéral |
|---|---|---|---|
| IDE / IBODE / IADE | obligatoire | autorisé | AVEC_HEURES_IDE (3200h) |
| SAGE_FEMME | obligatoire | autorisé | SANS_HEURES_CPAM |
| KINE | obligatoire | autorisé | AVEC_HEURES_KINE (2240h) |
| MEDECIN | obligatoire | autorisé | SANS_HEURES_CPAM |
| PHARMACIEN / PREPARATEUR_PHARMA | obligatoire | NON | NON_ELIGIBLE |
| MANIPULATEUR_RADIO | obligatoire | NON | NON_ELIGIBLE |
| AS / AES | absent | NON | NON_ELIGIBLE |
| DIETETICIEN / ERGO / PSYCHOMOTRICIEN | obligatoire | autorisé | SANS_HEURES_CIPAV |
| ORTHOPHONISTE | obligatoire | autorisé | SANS_HEURES_CPAM |

Constantes vérifiées dans `src/lib/constantes.ts` et `regles_exercice_profession`.

## IDE / IBODE / IADE

**Inscription** ✅ — RPPS demandé, LIBERAL/VACATION dispo.
**Dashboard** ✅ — KPI 3200h correct, "Passer en libéral" affiché à 25% (R2.5 fix).
**Profil** ✅ — RPPS inline disponible, ADELI absent.
**Documents** ✅ — RCP conditionnel sur LIBERAL/MIXTE.
**Recherche** ✅ — filtre profession appliqué.
**Passer en libéral** ✅ — catégorie AVEC_HEURES_IDE.

⚠️ **Note** : `useTypesExerciceAutorises` charge `regles_exercice_profession` via RPC. Avant R3.3, retournait 401 anonyme sur inscription — fix livré.

## SAGE_FEMME

✅ Tous flows OK. Pas de seuil heures (catégorie SANS_HEURES_CPAM). RPPS obligatoire.

## KINE

✅ Inscription/Dashboard/Documents/Recherche OK.
🐛 **P2** — `SectionProfilPrincipal.tsx:382` affiche en dur "Passage en libéral disponible à 3 200h" même pour KINE (seuil réel : 2240h selon `getRegleInstallation('KINE').heures_requises`). Texte trompeur.

## MEDECIN

✅ Inscription/Dashboard/Profil OK. Champ spécialité (`SelectSpecialiteMedicale`) shown.
🐛 **P1** — Spécialité médicale stockée mais jamais matchée par `fn_postuler_mission`. Voir audit étab synthèse, scénario 5 reproductible.

## PHARMACIEN / PREPARATEUR_PHARMA

✅ Inscription : LIBERAL/VACATION cachés (NON_LIBERAL filter).
✅ Dashboard : "Passer en libéral" caché (estEligibleLiberal=false).
✅ Profil : type_exercice forcé SALARIE (regles_exercice_profession).
✅ Passer en libéral : redirect vers tableau-de-bord (R2.5).

## MANIPULATEUR_RADIO

✅ Tous flows OK. Comportement identique à PHARMACIEN (NON_LIBERAL).

## AS / AES

✅ Inscription : champ RPPS absent, encart explicite "diplôme + CNI vérifiés à la première mission" (R3.5 fix).
✅ Dashboard : pas de section libéral.
✅ Profil : carte "Identification professionnelle" avec lien direct vers `/soignant/mes-documents` (R3.5).
✅ Helper completion : 8 items au lieu de 9 (item RPPS exclu, R3.5).
✅ Documents : pas de RPPS_ADELI requis.

## DIETETICIEN / ERGOTHERAPEUTE / PSYCHOMOTRICIEN

✅ Tous flows OK. Catégorie SANS_HEURES_CIPAV (libéral autorisé sans seuil heures).

## ORTHOPHONISTE

✅ Tous flows OK. Catégorie SANS_HEURES_CPAM (CPAM, pas de seuil).

## Findings

### Bugs détectés (par sévérité)

**P1 (critique)** — concerne tous médecins :
- Specialty match absent dans `fn_postuler_mission` (cf. synthèse).

**P2 (mineur)** :
- KINE : texte "3 200h" hard-codé dans `SectionProfilPrincipal.tsx:382`.

### Edge cases / patterns suspects

1. **Item RPPS marqué `obligatoire: false` dans le helper** alors qu'aucune candidature n'est possible sans RPPS pour 13 professions. Le bandeau colore en warning au lieu de destructive. Pas bloquant car la complétion 100% reste atteignable et l'erreur RPPS est levée à la candidature, mais l'UX laisse penser que le profil est complet sans RPPS.

2. **Profession NULL** : si soignant n'a pas vérifié RPPS, `profession=null` filtre toutes les missions côté serveur (RechercheMissions.tsx:143). Géré par BandeauProfilIncomplet, mais conditionnellement.

### Bugs déjà connus (référencés)

- ADELI obsolète (R3.5 — nettoyé)
- Triplon completion (R3.2 — corrigé)
- 406 .single() (R3.3 — corrigé)
- Action audit "PROFIL_MODIFICATION" enum (R3.3 — corrigé)
