# Audit fonctionnel hybride — Phase 1 : établissement + cross-matching

> **Méthodo** : lecture de code + tests SQL via MCP Supabase, sans navigateur.
> **Date** : 2026-04-27 · **Branche** : `audit/phase-1`

## Sommaire

- [HOPITAL_PUBLIC](#hopital_public)
- [CLINIQUE_PRIVEE](#clinique_privee)
- [EHPAD](#ehpad)
- [PHARMACIE_OFFICINE](#pharmacie_officine)
- [Cross-matching scénarios reproductibles](#cross-matching-scenarios-reproductibles)

## HOPITAL_PUBLIC

**Inscription** ✅ — formulaire SIRET (14) + FINESS (9) + auto-vérification INSEE.
**Dashboard** ✅ — KPI missions, candidatures, factures impayées, blocage auto si retards.
**Publication mission** ✅ — `fn_creer_mission` valide `peut_publier_missions`, `statut_verification`, `contrat_valide`, `bloque_auto_le`, factures en retard, RIST plafond pour secteur public.
**Acceptation candidature** ✅ — `fn_traiter_candidature` vérifie profession, exclusions, type_contrat, documents J-7, plafond 48h/sem SALARIE.
**Facturation/Paiement** ✅ — taux_horaire × duree_heures + cron auto-transitions.
**Litiges** ⚠️ — composant `FilDiscussionLitige` existe, déclenchement présumé via migration SQL.
**Paramètres** ✅ — onglets Profil/Groupe/Contrats/Config/Exclusions.

## CLINIQUE_PRIVEE

Identique à HOPITAL_PUBLIC sauf RIST plafond inactif (secteur privé).

## EHPAD

Identique à HOPITAL_PUBLIC sauf pas de FINESS sectoriel.
✅ **Test SQL** : EHPAD peut publier mission MEDECIN (`fn_creer_mission` retourne `success: true`). C'est une décision métier, pas un bug — un EHPAD peut effectivement avoir besoin d'un médecin coordonnateur ad hoc.

## PHARMACIE_OFFICINE

✅ **Inscription** : "N° Licence" au lieu de FINESS.
✅ **Filtre métier** double-niveau :
- **Frontend** (`FormulaireMission.tsx:413`) : `filtresProfessions={etablissementType === 'PHARMACIE_OFFICINE' ? ['PHARMACIEN', 'PREPARATEUR_PHARMA'] : undefined}`.
- **Backend** confirmé par test SQL : `fn_creer_mission` rejette `IDE` si appelée par pharmacie avec :
  ```
  {"error":"Une pharmacie d'officine ne peut publier que des missions pour pharmacien ou préparateur.","success":false}
  ```

✅ **Aucun bypass possible** — la défense en profondeur fonctionne.

## Cross-matching scénarios reproductibles

Tests exécutés en SQL via comptes audit (`audit-{prof}@jolene-test.dev`) avec missions test (`AUDIT TEST mission ...`).

### Scénario 1 : IDE → mission IDE
**Attendu** : match. **Obtenu** : `Cette mission requiert un(e) IDE` non levé ; bloque sur RCP manquante (compte audit). ✅ Comportement profession correct.

### Scénario 2 : IBODE → mission IDE (hiérarchie)
**Attendu métier** : IBODE pourrait candidater (IBODE = IDE+) avec `accepte_non_specialises=false` à débattre.
**Obtenu SQL** : `{"error":"Cette mission requiert un(e) IDE."}`
🐛 **P1 — Hiérarchie professionnelle ignorée**. `fn_postuler_mission` fait un match strict `v_soignant.profession != v_mission.profession_requise`.

### Scénario 3 : IDE → mission IBODE avec accepte_non_specialises=true
**Attendu métier** : match (le flag souplesse devrait élargir).
**Obtenu SQL** : `{"error":"Cette mission requiert un(e) IBODE."}`
🐛 **P1 — Flag `accepte_non_specialises` IGNORÉ par fn_postuler_mission**. La colonne est stockée mais jamais lue. Le métier n'est tout simplement pas implémenté côté candidature.

### Scénario 4 : IDE → mission IBODE accepte_non_specialises=false
**Attendu** : refus. **Obtenu** : refus. ✅ (par effet de bord du strict match, même résultat que #3).

### Scénario 5 : MEDECIN sans spécialité → mission MEDECIN cardio (SM48)
**Attendu métier** : refus si `accepte_non_specialises=false`, ou souplesse si `=true`.
**Obtenu SQL** : passe la validation profession (avant blocage RCP).
🐛 **P1 — Match spécialité absent**. `mission.specialite_medicale_requise` n'est jamais comparée à `soignant.specialite_medicale` dans `fn_postuler_mission`. Un médecin généraliste peut candidater à mission cardio si tous les autres garde-fous passent.

### Scénario 6 : PHARMACIE → mission IDE
**Attendu** : refus.
**Obtenu SQL** :
```
{"error":"Une pharmacie d'officine ne peut publier que des missions pour pharmacien ou préparateur.","success":false}
```
✅ Backend bloque correctement (corrige la prédiction de l'agent d'audit qui supposait UI-only).

### Scénario 7 : Soignant mineur → candidature
**Setup** : tentative `UPDATE soignants SET date_naissance = today - 17 years` bloquée par trigger `dec_age_minimum` BEFORE INSERT/UPDATE.
✅ Garde âge à la racine — un mineur ne peut jamais avoir de row dans `soignants`, donc ne peut pas candidater. La prédiction de l'agent (« pas de check âge ») est inexacte : le check est en amont, au niveau de la création/modif du profil.

### Scénario 8 : Soignant exclu → candidature mission de l'étab qui exclut
**Setup** : `INSERT INTO exclusions (exclu_par=etab, exclu_id=soignant, type_exclu_par='ETABLISSEMENT')`.
**Obtenu SQL** :
```
{"error":"Accès refusé."}
```
✅ Backend bloque correctement via `fn_est_exclu` dans `fn_postuler_mission`.

### Bonus : 3 overloads de `fn_creer_mission`

🐛 **P2 (technique)** — `fn_creer_mission` existe en 3 versions (10, 11, 12 args). Le frontend appelle systématiquement la signature 12-args (named params), donc pas d'ambiguïté en pratique. Mais nettoyage SQL recommandé pour éviter futures collisions PostgREST.
