# Visibilité du code de pointage rotatif — instruction « B1-ter » (B9, en attente de Gabrielle)

> Préparé le 2026-11-02 avec la PR B1 (`fix/scanner-code-sans-code-suivant`,
> migration `20261102205212_scanner_code_sans_code_suivant.sql`). Faits relus dans
> le dépôt et, en **lecture seule**, en production (définitions, privilèges,
> politiques, registre des migrations). **Rien n'est implémenté ici** : la
> fermeture touche aux GRANT de `missions` (catégorie B9 « RLS / auth / GRANT »),
> elle attend le go explicite de Gabrielle. Les numéros de ligne renvoient à
> `supabase/schema/public.sql` au commit de B1.

## 1. Constat : B1 ne ferme que l'étage RPC

B1 retire `nouveau_code` et `nouveau_hmac` des réponses de
`fn_scanner_code_pointage` et de `fn_declarer_fin_retroactive`. Le code courant
reste pourtant lisible par le soignant assigné **sans aucune RPC** :

| Étage | Fait | Effet |
|---|---|---|
| GRANT | `GRANT SELECT,INSERT,DELETE,UPDATE ON TABLE "public"."missions" TO "authenticated"` (l.86265). Production, 02/11 : `has_column_privilege('authenticated', 'public.missions', 'code_pointage_actif', 'SELECT')` = `true`, idem `code_pointage_hmac` ; 107 colonnes sur 107 en SELECT. | toutes les colonnes sont lisibles par tout compte connecté que la RLS laisse passer |
| RLS | `pol_mission_select` (l.79367) : `est_admin()` OU membre de l'établissement avec `lecture_missions` OU **`soignant_assigne_id = auth.uid()`** OU soignant sur mission `OUVERTE` non exclue. | le soignant assigné voit sa ligne `missions` |
| RPC | `fn_etat_pointage_mission` (l.35151) : `'code_pointage_actif', CASE WHEN v_is_etab THEN … ELSE NULL END` (l.35194). | seul filtre existant, à un seul étage |

Conséquence : `GET /rest/v1/missions?id=eq.<id>&select=code_pointage_actif` avec le
JWT du soignant assigné renvoie le code courant à tout moment ; il peut ensuite
appeler `fn_scanner_code_pointage` sans être devant l'écran de l'établissement.
C'est exactement le cas que le principe « filtre de visibilité centralisé » de
`CLAUDE.md` interdit : la visibilité du code est décidée à l'étage RPC seulement,
pas aux étages GRANT et RLS.

Le code d'une mission `OUVERTE` (posé à l'insertion par `dec_generer_codes_pointage`,
l.1971-1990, trigger `BEFORE INSERT` l.75364) est aussi lisible par les soignants
éligibles (4e branche de la politique), mais il est **régénéré à l'assignation**
(`fn_geler_mission_a_assignation`, l.37218, nouveau code l.37278) et le scanner ne
cherche que les missions `ASSIGNEE` / `EN_COURS` : ce code-là est mort. Le résidu
réel est donc le soignant assigné.

## 2. Audit des lecteurs (quatre étages, 02/11/2026)

- **Fonctions SQL (production)** dont le corps nomme `code_pointage_actif` ou
  `code_pointage_hmac` : `dec_generer_codes_pointage`, `fn_enforce_etablissement_rbac_trigger`
  et `fn_geler_mission_a_assignation` (triggers, sans EXECUTE pour `authenticated`) ;
  `fn_etat_pointage_mission` (filtre établissement) ; `fn_scanner_code_pointage` et
  `fn_declarer_fin_retroactive` (plus aucun renvoi après B1). Aucune fonction du
  schéma `public` ne renvoie le type `missions`. Aucune fonction `SECURITY INVOKER`
  ne lit `missions.*` ni les colonnes du code. Les fonctions `SECURITY DEFINER`
  qui sérialisent des lignes de missions (`fn_dashboard_soignant_complet`,
  `fn_missions_decouverte_inscription`, relues) projettent des colonnes explicites,
  sans le code.
- **GRANT / RLS** : voir §1 ; aucune vue sur `missions` ; `missions` hors de toute
  publication Realtime.
- **Clients** : 81 lectures `from('missions')` dans `src/` et `ios-native/` (hors
  tests). Une seule n'a pas de projection explicite : `src/pages/ModifierMission.tsx`
  l.25, `select('*')` (écran établissement). Aucune mutation de `missions` ne
  demande la ligne en retour, aucun embarqué `missions(*)`. `ios-native`
  (`MissionQuery.missionSelect`) projette des colonnes explicites. Seul lecteur du
  code côté web : `AffichageCodeRotatifEtab.tsx`, par `fn_etat_pointage_mission`.
- **Edge functions** : `generate-contrat-mission-pdf` lit `missions` en `select('*')`
  avec le client `service_role` (l.233), non concerné par un GRANT à `authenticated`.
  `e2e/`, `tests/`, `scripts/` : aucun `select('*')` sur `missions` avec un JWT
  utilisateur.

## 3. Proposition B1-ter (non implémentée)

En PostgreSQL, un `REVOKE SELECT (colonne)` n'enlève rien à un SELECT accordé sur
la table entière. La fermeture se fait donc en deux temps, dans une PR B9 séparée,
mergée **après** B1 :

1. **Préalable applicatif** (même PR ou PR web juste avant) : remplacer le
   `select('*')` de `ModifierMission.tsx` l.25 par la projection explicite dont
   `FormulaireMission` a besoin, et ajouter une garde (test Node ou vitest) qui
   interdit `from('missions').select('*')` et `missions(*)` dans `src/` et
   `ios-native/`. Sans cela, l'écran de modification d'une mission échouerait en
   `42501 permission denied for table missions`, que le mapping iOS du lot 0
   traduirait en « session expirée ».
2. **Migration B9** : `REVOKE SELECT ON TABLE public.missions FROM authenticated`,
   puis `GRANT SELECT (<toutes les colonnes sauf code_pointage_actif et
   code_pointage_hmac>) ON public.missions TO authenticated`, la liste étant
   **calculée à l'exécution** depuis `information_schema.columns` (aucune liste en
   dur). INSERT, UPDATE et DELETE inchangés. Gardes avant (SELECT de table présent,
   107 colonnes) et après (`has_column_privilege` faux pour les deux colonnes, vrai
   pour toutes les autres ; `fn_etat_pointage_mission` renvoie toujours le code à
   l'établissement ; `service_role` inchangé). À décider dans la même PR : y
   inclure `code_arrivee` et `code_depart` (système ①, voir §4).
3. **Garde durable** : un test (banc PG17 ou drift-check) qui échoue si une colonne
   de `missions` hors liste interdite n'est pas lisible par `authenticated` (une
   colonne ajoutée plus tard ne recevrait sinon aucun SELECT), ou si l'une des
   colonnes interdites le redevient.
4. **Preuves** : banc PG17 (`select=*` refusé en `42501` pour `authenticated`,
   projection explicite acceptée, code relu par l'établissement), vitest de
   `ModifierMission`, recette de l'écran de modification d'une mission côté
   établissement (consigne du 28/09/2026), dump `public.sql` re-snapshoté.

## 4. Constats voisins (hors B1-ter, à arbitrer)

- **Corrigé dans B1** : la garde d'autorisation de `fn_declarer_fin_retroactive`
  valait `NULL` pour un compte authentifié sans lien avec la mission (logique
  ternaire : `est_admin_etablissement()` et `mon_etablissement_id()` renvoient
  `NULL`), et un `IF NULL` ne lève pas. Les commits de ce verrou sont détachables
  de la seule suppression des clés.
- **Non corrigé** : `fn_etat_pointage_mission` a la même forme
  (`v_is_etab := est_admin() OR v_mission.etablissement_id = mon_etablissement_id()`,
  l.35171 ; `IF NOT v_is_etab AND NOT v_is_soignant`, l.35174). Pour un compte
  authentifié sans lien avec la mission, la condition vaut `NULL` : l'appel n'est
  pas refusé et renvoie statut, intitulé, prochain type de scan, nombre de scans et
  segments effectifs (le code reste `NULL`). Fuite d'information mineure ; même
  correctif (`COALESCE`) en PR B9 séparée.
- **Système ①** (`fn_pointer_arrivee` l.47427, `fn_pointer_depart` l.47569,
  EXECUTE accordé à `authenticated` en production) : le code n'est contrôlé que
  s'il est fourni (`IF p_code_arrivee IS NOT NULL`, l.47455 ; `IF p_code_depart IS
  NOT NULL`, l.47584), et `code_arrivee` / `code_depart` sont lisibles comme
  `code_pointage_actif`. Aucun écran monté ne l'appelle (lot 2, correction 1) ;
  `docs/POINTAGE_DIAGNOSTIC.md` prévoit son retrait (« PR 5 »).

## 5. Décision demandée à Gabrielle

1. Go B1 (suppression des clés **et** verrou d'autorisation de la fin
   rétroactive), ou go sur la seule suppression des clés.
2. Go pour préparer B1-ter selon §3, avec ou sans `code_arrivee` / `code_depart`.
3. Go pour la PR B9 du verrou ternaire de `fn_etat_pointage_mission`.
