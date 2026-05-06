# Tests E16 — Choix contrat salarié/libéral pour soignant MIXTE × mission TOUS

Scope : bug critique URSSAF E16 (RÉSOLU). 5 RPCs backend + 3 composants frontend corrigés.

## Pré-requis communs

- Migrations appliquées (vérifier via MCP `list_migrations`) :
  - `20260420160000_e16_a_postuler_check`
  - `20260420161000_e16_b_traiter_candidature`
  - `20260420162000_e16_c_assigner_admin`
  - `20260420163000_e16_d_repondre_proposition`
  - `20260420164000_e16_e_proposer_mission_soignant`
- Frontend déployé (commits `cb626d16`, `ba0dc537` sur main)
- Comptes de test :
  - Soignant MIXTE (`type_exercice='MIXTE'`) avec RCP valide + documents OK
  - Soignant SALARIE pur (`type_exercice='SALARIE'`)
  - Soignant LIBERAL pur (`type_exercice='LIBERAL'`)
  - Étab de test avec `mon_etablissement_id()` valide

## Scénario 1 — Candidature nominale MIXTE × TOUS choix SALARIE

**Pré-conditions** :
- Mission OUVERTE, `mode_attribution='CANDIDATURE'`, `type_contrat_recherche='TOUS'`
- Soignant MIXTE connecté, éligible (docs, RCP, profession)

**Étapes** :
1. Naviguer `/soignant/missions/{mission_id}`
2. Saisir un message puis cliquer "Postuler"
3. `ChoixContratDialog` s'ouvre avec 2 options : Salarié (CDDU), Libéral (note d'honoraires)
4. Sélectionner **Salarié** puis cliquer "Confirmer"

**Résultat attendu** :
- Toast "Candidature envoyée !"
- État mission/candidature mis à jour côté UI

**Vérification DB** :
```sql
SELECT id, statut, type_contrat_choisi
FROM candidatures
WHERE mission_id = '{mission_id}' AND soignant_id = '{soignant_id}';
-- Attendu : statut='EN_ATTENTE', type_contrat_choisi='SALARIE'
```

## Scénario 2 — Candidature MIXTE × TOUS choix LIBERAL

**Étapes** : identique au scénario 1 mais sélectionner **Libéral**.

**Vérification DB** :
```sql
-- Attendu : type_contrat_choisi='LIBERAL'
```

## Scénario 3 — Étab traite candidature MIXTE × TOUS (non-orpheline)

**Pré-conditions** :
- Candidature EN_ATTENTE issue du scénario 1 ou 2 (`type_contrat_choisi` non-NULL)
- Étab connecté (propriétaire de la mission)

**Étapes** :
1. Naviguer `/etablissement/missions/{mission_id}` (ou vue équivalente)
2. Ouvrir `ListeCandidatures`, cliquer "Accepter" sur la candidature

**Résultat attendu** :
- Toast "Candidature acceptée !"
- Mission passe à `ASSIGNEE`
- Notification CANDIDATURE_ACCEPTEE envoyée au soignant

**Vérification DB** :
```sql
SELECT
  statut, type_contrat_applique, choix_contrat_soignant,
  type_paiement_soignant, mode_paiement_soignant
FROM missions
WHERE id = '{mission_id}';
```

Cohérence attendue :

| candidature.type_contrat_choisi | type_contrat_applique | type_paiement_soignant | mode_paiement_soignant |
|---|---|---|---|
| SALARIE | SALARIE | BULLETIN_PAIE | DIRECT |
| LIBERAL | LIBERAL | NOTE_HONORAIRES | STRIPE_CONNECT |

```sql
-- Vérif contrats_mission créé avec bon type_contrat
SELECT type_contrat, statut FROM contrats_mission WHERE mission_id='{mission_id}';
-- SALARIE → 'CDDU', LIBERAL → 'REMPLACEMENT_LIBERAL', statut='EN_ATTENTE_SIGNATURES'
```

## Scénario 4 — Étab traite candidature orpheline (antérieure E16)

**Pré-conditions** :
Insertion manuelle en DB d'une candidature orpheline pour test :
```sql
INSERT INTO candidatures (id, mission_id, soignant_id, statut, type_contrat_choisi)
VALUES (gen_random_uuid(), '{mission_TOUS_id}', '{soignant_MIXTE_id}', 'EN_ATTENTE', NULL);
```

**Étapes** :
1. Étab ouvre ListeCandidatures
2. Clique "Accepter" sur la candidature orpheline

**Résultat attendu** :
- Réponse RPC : `{ error: 'E16_CANDIDATURE_ORPHELINE', message: '...', candidature_id: '...' }`
- Toast erreur côté étab (message backend affiché tel quel ou générique)
- La candidature **n'est pas** acceptée
- Mission reste OUVERTE

**Vérification DB** :
```sql
SELECT statut FROM candidatures WHERE id='{candidature_id}';
-- Attendu : statut='EN_ATTENTE' (inchangé)
SELECT statut FROM missions WHERE id='{mission_id}';
-- Attendu : 'OUVERTE'
```

## Scénario 5 — Acceptation directe mode PREMIER_ARRIVE

**Pré-conditions** :
- Mission OUVERTE, `mode_attribution='PREMIER_ARRIVE'`, `type_contrat_recherche='TOUS'`
- Soignant MIXTE connecté

**Étapes** :
1. `/soignant/missions/{mission_id}`
2. Clic "Prendre la mission"
3. `ChoixContratDialog` s'ouvre
4. Sélectionner un choix (SALARIE ou LIBERAL) → Confirmer

**Résultat attendu** :
- Animation succès
- Redirect `/contrat/{contrat_id}` après 2s
- Mission ASSIGNEE

**Vérification DB** :
```sql
SELECT
  statut, soignant_assigne_id, type_contrat_applique,
  choix_contrat_soignant, type_paiement_soignant, mode_paiement_soignant
FROM missions WHERE id='{mission_id}';
```
Cohérence idem tableau scénario 3.

## Scénario 6 — Proposition étab urgence MIXTE × TOUS

**Pré-conditions** :
- Mission OUVERTE avec `type_contrat_recherche='TOUS'` et `est_urgente=true`
- Soignant MIXTE dans le pool urgence (`disponible_urgence=true`, `score_fiabilite>=50`, docs OK)

**Étapes étab** :
1. Sur page mission étab, bouton "Rechercher un remplaçant d'urgence"
2. Clic "Proposer" sur le soignant MIXTE
3. Au premier clic, backend retourne `{ choix_requis: TRUE, options: [...] }`
4. **`ChoixContratDialog` s'ouvre côté étab**
5. Sélectionner un choix (ex. SALARIE) → Confirmer

**Résultat attendu étab** :
- Toast "Mission proposée au soignant !"
- Carte soignant disparaît de la liste des proposables

**Vérification DB** :
```sql
SELECT statut, type_contrat_choisi, proposee_par
FROM candidatures
WHERE mission_id='{mission_id}' AND soignant_id='{soignant_id}';
-- Attendu : statut='PROPOSEE', type_contrat_choisi='SALARIE' (ou le choix), proposee_par=auth.uid() étab
```

**Étapes soignant (suite)** :
1. Soignant reçoit la notification + carte dans son dashboard
2. Clic "Accepter" sur `CarteProposition`
3. Backend appelle `fn_repondre_proposition` avec le `type_contrat_choisi` persisté
4. Pas de nouveau dialog côté soignant (choix déjà persisté)
5. Mission passe à ASSIGNEE avec les 4 champs cohérents

## Scénario 7 — Proposition orpheline refusée (antérieure E16)

**Pré-conditions** :
```sql
-- Simuler proposition orpheline
INSERT INTO candidatures (id, mission_id, soignant_id, statut, proposee_par, type_contrat_choisi, cree_le)
VALUES (gen_random_uuid(), '{mission_TOUS_id}', '{soignant_MIXTE_id}', 'PROPOSEE', '{etab_uid}', NULL, NOW());
```

**Étapes** :
1. Soignant MIXTE voit la carte proposition sur son dashboard
2. Clic "Accepter"

**Résultat attendu** :
- Toast **neutre** (pas rouge) : "Proposition obsolète — postulez directement depuis la mission dans votre espace"
- Carte disparaît (`onTraitee` appelé)
- Pas de crash, pas de re-tentative

**Vérification DB** :
```sql
SELECT statut FROM candidatures WHERE id='{candidature_id}';
-- Attendu : 'PROPOSEE' (inchangé, expirera naturellement)
SELECT statut FROM missions WHERE id='{mission_id}';
-- Attendu : 'OUVERTE'
```

## Scénario 8 — Série MIXTE × TOUS

**Pré-conditions** :
- Série contenant au moins 2 missions ouvertes, dont au moins une `type_contrat_recherche='TOUS'`
- Soignant MIXTE

**Étapes** :
1. Soignant ouvre `/soignant/serie/{serie_id}`
2. Sélectionne plusieurs missions dont la TOUS
3. Clic "Accepter la sélection"

**Résultat attendu** :
- Missions non-TOUS acceptées normalement (`reussies++`)
- Mission TOUS → toast "**Choix de contrat requis**" avec description contextualisée (intitulé + CTA "ouvrez son détail")
- `echouees++` pour la mission TOUS
- Bilan final : N réussies + 1 échouée
- Soignant peut ensuite accepter la mission TOUS individuellement via `DetailMissionSoignant` (avec dialog choix)

## Scénario 9 — Non-régression cas non-concerné

Vérifier qu'aucun dialog ne s'ouvre inutilement :

**9.1** — Soignant SALARIE pur postule sur mission SALARIE :
- Clic "Postuler" → pas de dialog
- Candidature créée avec `type_contrat_choisi='SALARIE'` (calcul déterministe)

**9.2** — Soignant LIBERAL pur postule sur mission LIBERAL :
- Pas de dialog
- `type_contrat_choisi='LIBERAL'`

**9.3** — Soignant MIXTE sur mission SALARIE (force-type) :
- Pas de dialog (mission force SALARIE)
- `type_contrat_choisi='SALARIE'`

**9.4** — Soignant MIXTE sur mission LIBERAL :
- Pas de dialog
- `type_contrat_choisi='LIBERAL'`

**9.5** — Soignant SALARIE sur mission TOUS :
- Pas de dialog (soignant n'a qu'un type)
- `type_contrat_choisi='SALARIE'` (déduit `v_soignant.type_exercice`)

**9.6** — Soignant LIBERAL sur mission TOUS :
- Pas de dialog
- `type_contrat_choisi='LIBERAL'`

Vérification DB commune :
```sql
SELECT type_contrat_choisi, COUNT(*)
FROM candidatures
WHERE cree_le > NOW() - INTERVAL '1 day'
GROUP BY type_contrat_choisi;
-- Attendu : 0 candidatures avec type_contrat_choisi IS NULL post-correctif
```

## Vérifications post-prod

```sql
-- Toutes nouvelles candidatures persistent un choix non-NULL
SELECT
  COUNT(*) FILTER (WHERE type_contrat_choisi IS NULL) AS nulls,
  COUNT(*) FILTER (WHERE type_contrat_choisi IN ('SALARIE','LIBERAL')) AS valides
FROM candidatures
WHERE cree_le > '2026-04-20 16:00:00';
-- Attendu : nulls=0, valides=N

-- Missions ASSIGNEE récentes : cohérence 4 champs
SELECT
  id, type_contrat_applique, choix_contrat_soignant,
  type_paiement_soignant, mode_paiement_soignant
FROM missions
WHERE statut='ASSIGNEE' AND modifie_le > '2026-04-20 16:00:00';
-- Chaque ligne : les 4 champs non-NULL et cohérents
```

## Rappel périmètre clos E16

- **E16 RÉSOLU** : 5 RPCs backend + 3 composants frontend
- **Migrations backend** : 5 (1A/1B/1C/1D/1E)
- **22 missions prod figées SALARIE** laissées en l'état (Option A)
- **Tickets P2 futurs** : UI-E16-1 (dialog unique série), UI-E16-2 (UI admin assignation)
