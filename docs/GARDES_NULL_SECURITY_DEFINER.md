# Gardes NULL des fonctions SECURITY DEFINER (B9)

> Statut : **PR B9 en attente du go explicite de Gabrielle** (SECURITY DEFINER,
> autorisation, escrow, facturation). Migration
> `supabase/migrations/20261103013434_gardes_null_security_definer.sql`.
> **Ordre de merge imposé** : ce lot passe après les quatre branches B9 du 02/11
> (§7). La garde statique le refuse tant que scanner et B5b ne sont pas mergés.

## 1. Le défaut

`mon_etablissement_id()` renvoie `NULL` pour tout appelant sans établissement
actif : soignant, membre révoqué (`membres_etablissement.actif = false`), service
sans identité. `est_admin_etablissement()` renvoie `NULL` quand
`fn_role_etablissement_courant(NULL)` ne trouve aucun rôle (défini ainsi depuis
`20260712230000_p0_securite_auth_rls.sql`, la version précédente était sous
`COALESCE(..., false)`). Une colonne nullable comparée à `auth.uid()`
(`soignant_assigne_id` d'une mission non assignée) vaut aussi `NULL`.

En logique ternaire SQL, une garde de refus écrite

```sql
IF x.etablissement_id != mon_etablissement_id() AND NOT est_admin() THEN refus
IF NOT (est_admin() OR x.etablissement_id = mon_etablissement_id()) THEN refus
IF NOT x.etablissement_id = mon_etablissement_id() THEN refus  -- NOT lie moins fort que =
IF NOT est_admin_etablissement() AND NOT est_admin() THEN refus
IF x.soignant_assigne_id != auth.uid() THEN refus
```

vaut `NULL` pour ces appelants. PL/pgSQL ne prend pas la branche `IF NULL` et la
fonction continue. Comme elles sont `SECURITY DEFINER`, la RLS ne s'applique pas,
et `fn_enforce_etablissement_rbac_trigger` laisse aussi passer un appelant sans
rôle d'établissement (`fn_role_etablissement_courant(NULL) IS NULL → RETURN NEW`).

## 2. Correctif livré (20 fonctions)

Une seule différence par fonction, partie de la définition LIVE (md5 relu le
2026-11-03, identique au dump) : la comparaison passe sous `COALESCE(..., false)`.
Un `NULL` vaut « pas d'accès ». Les appelants dont la comparaison valait déjà
`true` ou `false` gardent exactement le même résultat. Messages, ACL,
volatilité et `search_path` sont inchangés (`CREATE OR REPLACE`, aucun GRANT).

| Fonction | Gravité | Avant (appelant sans établissement) | Après |
|---|---|---|---|
| `fn_valider_alerte_presence` | critique | le soignant valide sa propre présence ; `dec_proteger_presence_soignant` et `fn_protect_presence_integrity` ne revertent pas (même NULL) → `trg_escrow_release_on_validation` | `Accès refusé` |
| `fn_generer_facture` | critique | facture de commission créée sur la mission d'un tiers | `Accès refusé` |
| `fn_generer_code_secours_mission` | haute | le soignant se génère un code de secours puis pointe | `NON_AUTORISE` |
| `fn_generer_qr_mission` (+ `fn_regenerer_qr_mission`) | haute | le soignant se génère un QR de pointage | `NON_AUTORISE` |
| `fn_soignants_urgence` | haute | noms, scores et **téléphones** du pool urgence | 0 ligne |
| `fn_generer_donnees_dpae` | haute | données DPAE d'un contrat (NIR, date et lieu de naissance, établissement) | `Non autorisé` |
| `fn_presences_detail_mission` | haute | présences (heures réelles, retards, validité du périmètre GPS) de la mission d'un autre soignant | `Accès refusé` |
| `fn_enregistrer_numero_dpae` | moyenne | faux numéro DPAE + email « DPAE déclarée » | `Non autorisé` |
| `fn_rebooker_soignant` | moyenne | mission REBOOK créée pour l'établissement d'un tiers | `Non autorisé` |
| `fn_booster_mission` | moyenne | boost (option facturée) + notifications | `Non autorisé` |
| `fn_activer_garantie_mission` | moyenne | bascule de la garantie de remplacement | `Non autorisé` |
| `fn_deposer_chorus` | moyenne | facture marquée DÉPOSÉE chez Chorus | `Accès refusé` |
| `fn_diffuser_pool_urgence` | moyenne | diffusion du pool urgence d'un tiers | 0 |
| `fn_codes_pointage_mission` | faible | lecture des codes statiques d'une mission quelconque (UUID requis). Le soignant assigné lit déjà `code_arrivee`/`code_depart` en PostgREST (GRANT SELECT de table et `pol_mission_select`) et la branche de génération est morte (`dec_codes_pointage` les pose à l'INSERT) : le vrai trou est CP5b (§5) | `Accès interdit` |
| `fn_declarer_honoraires_retrocession` | faible (conditionnelle) | sur une mission RETROCESSION TERMINEE héritée : `montant_honoraires_bruts` et le justificatif sont posés une seule fois (la vraie déclaration du cabinet est ensuite refusée, « Honoraires déjà déclarés ») et le soignant reçoit « Relevé d'honoraires à confirmer ». `total_brut`, `net_a_payer` et la commission sont réécrits par `dec_mission_z_finance` et `dec_mission_zz_commission` | `Non autorisé` |
| `fn_etablissement_pour_mission` | faible | fiche d'un établissement sans mission ouverte ni assignation | `Accès refusé` |
| `fn_creer_reclamation_score` | faible | réclamation sur un événement de score d'établissement (UUID requis) : bloque celle de l'établissement, notifie l'admin | `NON_AUTORISE` |
| `fn_definir_retrocession_mission` | faible | aujourd'hui bloqué par `trg_00_bloquer_retrocession_prelaunch` ; ouvert dès la levée du verrou | `Non autorisé` |
| `fn_annuler_serie` | défense en profondeur | garde franchie mais `UPDATE … WHERE etablissement_id = mon_etablissement_id()` → 0 ligne | `Accès refusé` |
| `fn_assigner_mission_admin` | défense en profondeur | garde franchie, la seconde (`IS DISTINCT FROM`) refuse | `Non autorisé` |

`fn_creer_reclamation_score`, `fn_declarer_honoraires_retrocession` et
`fn_definir_retrocession_mission` ne figuraient pas dans le constat initial : la
garde statique les a relevés.

`fn_etat_pointage_mission` a quitté ce lot (21 → 20 fonctions) : la PR B9 B5b
`fix/visibilite-etablissement-par-permission` la redéfinit depuis le même LIVE
avec la garde NULL-safe (§3, §7). Pour le soignant, `est_etab` y reste `null` :
`mobile-native/PRESENCE-SCENARIO-PREPARATION.md` (l.108) et
`mobile-native/src/workflows/presence/supabaseGateway.ts` restent exacts.

### Contexte système (service_role, crons)

Quinze fonctions du lot n'ont pas de garde `auth.uid() IS NULL` préalable :
`fn_valider_alerte_presence`, `fn_codes_pointage_mission`, `fn_soignants_urgence`,
`fn_rebooker_soignant`, `fn_booster_mission`, `fn_presences_detail_mission`,
`fn_activer_garantie_mission`, `fn_deposer_chorus`, `fn_generer_facture`,
`fn_diffuser_pool_urgence`, `fn_etablissement_pour_mission`, `fn_annuler_serie`,
`fn_assigner_mission_admin`, `fn_declarer_honoraires_retrocession`,
`fn_definir_retrocession_mission`. `est_admin()` exige un `auth.uid()` : un appel
sans identité (service_role, cron, script) passait par le `NULL` et il est
désormais refusé comme tout appelant sans établissement. Les cinq autres
(`fn_generer_code_secours_mission`, `fn_generer_qr_mission`,
`fn_generer_donnees_dpae`, `fn_enregistrer_numero_dpae`,
`fn_creer_reclamation_score`) refusaient déjà ce contexte (`NON_AUTHENTIFIE`).

Appelants système recherchés, aucun trouvé : `cron.job` LIVE (lecture seule du
03/11, 0 commande), `pg_proc` (seuls `fn_regenerer_qr_mission` →
`fn_generer_qr_mission` et `fn_creer_mission_multi_jours_v2` →
`fn_definir_retrocession_mission`, tous deux sous le JWT de l'utilisateur),
`supabase/functions/`, `ios-native/`, `mobile-native/`, `scripts/`. Pas de
régression attendue ; un futur appelant système devra passer par une fonction
interne dédiée, pas par ces RPC.

## 3. Cas laissés en l'état, et pourquoi

Ces cas sont listés dans `REVUES` de `tests/node/gardes-null-security-definer.node.mjs`.
Toute nouvelle occurrence échoue, et une entrée devenue sans objet aussi. Une
entrée **conditionnée** (colonne « Preuve exigée ») n'est acceptée que si la
preuve figure dans la définition versionnée la plus récente de la fonction : sa
migration de correctif si elle est dans le dépôt, sinon le dump. Tant que la PR
B9 qui la porte n'est pas mergée et cette branche rebasée, le test « ordre de
merge » échoue : main ne peut pas afficher une raison « corrigée » fausse.

| Fonction | Preuve exigée | Raison |
|---|---|---|
| `fn_declarer_fin_retroactive` (`v_caller_is_etab_admin`, `v_caller_is_soignant`) | `OR COALESCE(v_caller_is_etab_admin, false)` et `NOT (COALESCE(v_caller_is_soignant, false)` (migration `20261102205212`) | Même défaut, corrigé par la PR B9 `fix/scanner-code-sans-code-suivant` (COALESCE à l'usage). La redéfinir ici depuis le LIVE réintroduirait `nouveau_code`/`nouveau_hmac` si cette migration passait après. **Exploitable en LIVE** (md5 `845c6a3f…` relu le 03/11) tant que cette PR n'est pas mergée. |
| `fn_etat_pointage_mission` (`v_is_etab`, `v_is_soignant`) | `IF NOT COALESCE(v_is_etab, false) AND NOT COALESCE(v_is_soignant, false) THEN` (migration `20261102210943`) | Même défaut, corrigé par la PR B9 B5b `fix/visibilite-etablissement-par-permission` (COALESCE à l'usage, code réservé à la permission `pointage`), partie du même LIVE (md5 `3fe46580…`). La garder ici faisait échouer la seconde PR mergée. |
| `fn_creer_reclamation_score` (`v_proprio_id != v_uid`) | — | Branche SOIGNANT : `v_uid` testé `IS NULL` en tête, `v_proprio_id` lu dans `evenements_score_soignant.soignant_id` (NOT NULL) après le test `v_event.id IS NULL` : jamais NULL. |
| `dec_valider_paiement_facture` | — | Trigger `factures` : la RLS UPDATE est réservée à `est_admin()`. Le NULL est porteur pour le contexte système (webhook, cron sans `auth.uid()`) qui passe la facture `PAYEE`. |
| `fn_ouvrir_litige_rate_limited` (surcharge 4 arguments ; garde et `v_initie_par`) | — | NULL seulement si la mission n'a pas de soignant assigné. La lecture `factures_honoraires … soignant_id = NULL` ne trouve alors rien et refuse ; le `CASE` de `v_initie_par`, calculé après la garde, retombe sur « ETABLISSEMENT », seule branche qui a pu passer. |
| `fn_suivi_remboursements_connect_facture` | — | `v_finance := v_admin OR (… = mon_etablissement_id() AND fn_a_permission_etablissement(…) IS TRUE)` : sans établissement, le second terme vaut `false`, et `NULL AND false = false`. |
| `dec_proteger_mission_soignant`, `dec_proteger_presence_soignant`, `fn_protect_mission_financials`, `fn_protect_presence_integrity`, `fn_protect_contrat_integrity` | — | Volet 2 ci-dessous. |

**Hors `REVUES`, parce que non scannés** : quatre fonctions
`*_internal_20260801` portent la forme NULL (`fn_declarer_paiement_soignant_…`,
`fn_generer_facture_mensuelle_…`, `fn_modifier_reference_paiement_…`, et
`fn_detail_facture_…` où un test `v_etab_id IS NULL AND NOT est_admin()`
préalable la neutralise). Elles ne sont pas SECURITY DEFINER (la garde ne scanne
que celles-là), `EXECUTE` est révoqué de PUBLIC, et leurs enveloppes
(`fn_declarer_paiement_soignant_v2`, `fn_generer_facture_mensuelle`,
`fn_modifier_reference_paiement`, `fn_detail_facture`) appliquent déjà
`IS DISTINCT FROM mon_etablissement_id()`.

### Portée du scanner — choix conservateur

* **Règle `mon_etablissement_id`** : comparaison `!=`/`<>`, comparaison sous un
  `NOT` (parenthésé ou non : `NOT x = mon_etablissement_id()`), affectation d'une
  comparaison ; une variable qui reçoit exactement `mon_etablissement_id()` est
  suivie, sauf si elle est testée `IS [NOT] NULL`.
* **Règle `auth.uid`** : même formes avec `auth.uid()` (ou une variable qui le
  reçoit). Seul un test `IS [NOT] NULL` de l'autre opérande exempte. Elle
  s'applique à toutes les migrations à partir de celle-ci et, dans le dump, aux
  fonctions de ce lot et de `REVUES` : une régression de `fn_presences_detail_mission`
  ou des entrées revues échoue. Le reste du dump (34 occurrences dans 31
  fonctions SECURITY DEFINER au 03/11, surtout des colonnes NOT NULL ou le
  contexte système) n'est pas instruit ici : §5.
* **Règle `NOT est_admin_etablissement()`** : inchangée.
* **Pas de suivi du flot de données** : `ok := … = mon_etablissement_id()` est
  signalé même si chaque lecture de `ok` est ensuite sous `COALESCE` (forme sûre
  « COALESCE à l'usage » de B5b et de la PR scanner). Ces cas passent par `REVUES`
  avec une preuve exigée. Le test unitaire du scanner fige ce choix.

## 4. Volet 2 — `est_admin_etablissement()` et les cinq triggers (non livré)

Le correctif de la cause racine tient en une ligne :

```sql
CREATE OR REPLACE FUNCTION public.est_admin_etablissement() RETURNS boolean
LANGUAGE sql STABLE SECURITY DEFINER SET search_path TO 'pg_catalog', 'public', 'auth' AS $$
  SELECT COALESCE(public.fn_role_etablissement_courant(NULL) IN ('PROPRIETAIRE', 'ADMIN_GROUPE', 'RH'), false);
$$;
```

Ses usages positifs (IF, WHERE, USING) ne changent pas. Mais cinq triggers le
nient (`NOT est_admin_etablissement()`) et **ne revertent plus rien depuis le
12/07** pour les soignants (RPC) ni pour le contexte système. Les réactiver
change le comportement de quatre mois de code écrit sans eux. D'après la lecture
du dump (non exécutée), on obtient au moins :

* `fn_annuler_mission_soignant` (désistement) et `fn_annuler_candidature_soignant`
  font `UPDATE missions SET statut = 'OUVERTE', soignant_assigne_id = NULL` sous
  le JWT du soignant. `dec_proteger_mission_soignant` ne prévoit aucun contexte de
  contournement pour ces chemins et reverterait `soignant_assigne_id` : on aurait
  une mission OUVERTE toujours assignée.
* `dec_proteger_mission_soignant` n'exempte pas `auth.uid() IS NULL`. Les
  écritures des crons et de service_role sur `soignant_assigne_id`, `debut_le`,
  `fin_le` et les champs financiers seraient revertées. Cela contrevient à la règle
  CLAUDE.md « tout trigger anti-tamper … DOIT exempter le contexte système ».
* `dec_mission_z_finance` (`dec_calculer_finance_mission`) s'exécute **avant**
  `dec_proteger_mission_soignant` et `trg_protect_mission_financials` (ordre
  alphabétique). Toute écriture sur `missions` faite dans le contexte du soignant
  (par exemple `dec_resynchroniser_compteurs_presence` après son pointage) verrait
  le recalcul financier reverté.

Côté PostgREST direct, rien n'est exploitable : `pol_mission_update`,
`pol_pres_update` et `pol_contrat_update` refusent l'UPDATE au soignant. Ces
triggers ne protègent le soignant que contre une RPC SECURITY DEFINER fautive,
et les gardes corrigées ici ferment toutes celles qui sont connues.

**CLAUDE.md périmé (proposition à Gabrielle, non modifié ici)** : « Patterns
backend (10/07/2026) » point 2 décrit `dec_proteger_mission_soignant` comme
actif pour tout caller non-admin, service_role compris. Depuis
`20260712230000` (est_admin_etablissement() sans COALESCE), il ne revert plus rien
pour un appelant sans rôle d'établissement : soignant sous RPC, service_role,
cron. `fn_test_update_mission` reste le chemin des tests, mais l'UPDATE direct ne
serait plus un no-op silencieux. Formulation proposée : « `dec_proteger_mission_soignant`
ne revert aujourd'hui que pour un membre d'établissement non administrateur ;
il est inerte pour les soignants, service_role et les crons depuis
`20260712230000` (voir docs/GARDES_NULL_SECURITY_DEFINER.md §4). Passer quand
même par `fn_test_update_mission`. »

Proposition, à instruire dans une PR B9 dédiée :

1. Le helper sous `COALESCE(…, false)`.
2. Dans `dec_proteger_mission_soignant`, ajouter `auth.uid() IS NOT NULL AND` en
   tête de la condition (règle des crons), plus un contexte de contournement
   explicite pour le désistement et l'annulation de candidature.
3. Rejouer la recette pointage (code, QR, fin rétroactive), désistement,
   facturation et `test:guards`, et prouver que `heures_reelles` et `net_a_payer`
   sont conservés.
4. Ajouter un test-garde : sous le JWT d'un soignant, `est_admin_etablissement()`
   vaut `false` et non `NULL`.
5. Retirer les cinq entrées de `REVUES` (la garde statique l'exigera).

## 5. Suites proposées (hors de cette PR)

### Gaps connus non verrouillés — PR B9 dédiées à ouvrir en priorité

Le principe CLAUDE.md « un gap connu reste verrouillé » n'est **pas** satisfait
pour ces trois cas : ils sont documentés, pas rendus impossibles.

* **CP5b, pointage par codes statiques (gravité haute, fraude)** :
  `fn_pointer_arrivee`/`fn_pointer_depart` acceptent `p_code_arrivee`/`p_code_depart`
  et sautent alors le contrôle GPS. Le soignant assigné lit ces codes en
  PostgREST : il peut pointer hors de l'établissement. Verrou proposé (B1-ter) :
  lever une exception explicite si un code est passé, avec référence à
  `docs/POINTAGE_CODE_ROTATIF_VISIBILITE.md`, après un `git grep` des appelants
  (web, iOS, mobile-native : aucun ne les passe à ce jour), puis `REVOKE SELECT`
  de table et GRANT colonne par colonne sur `code_arrivee`, `code_depart`,
  `code_pointage_actif`, `code_pointage_hmac`.
* **Double facturation `fn_generer_facture` puis prélèvement SEPA automatique** :
  la RPC ne refuse que `factures.mission_id = p_mission_id`, alors que la
  facturation courante rattache les missions autrement. Une mission déjà
  facturée peut recevoir une seconde facture de commission, prélevée par
  `sepa-auto-charge`. Verrou proposé : refuser `commission_facturee OR
  facture_id IS NOT NULL` avec un message explicite, ou `REVOKE EXECUTE … FROM
  authenticated` (aucun appelant web ni iOS) et mise à jour de
  `supabase/SECURITY_DEFINER_MANIFEST.json`.
* **`fn_declarer_fin_retroactive`** : exploitable en LIVE tant que
  `fix/scanner-code-sans-code-suivant` n'est pas mergée (§3).

### Autres suites

* **RPC sans appelant front** : `fn_generer_facture`,
  `fn_valider_alerte_presence` et `fn_deposer_chorus` ne sont appelées ni par le
  web ni par iOS. On peut faire un `REVOKE EXECUTE … FROM authenticated` et mettre
  à jour `supabase/SECURITY_DEFINER_MANIFEST.json`.
* **Codes de secours** : dans `fn_generer_code_secours_mission`, poser
  `type_acteur` selon l'appelant (`ADMIN_PLATEFORME` si `est_admin()`). Dans
  `fn_valider_code_secours`, refuser un code dont `cree_par` est le soignant
  lui-même.
* **QR** : dans `fn_valider_scan_qr`, signaler un jeton dont `cree_par` n'est ni
  membre de l'établissement ni le compte système.
* **Inventaire `auth.uid()` du dump** (règle hors périmètre, §3) : instruire les
  comparaisons d'une colonne nullable, d'abord `soignant_assigne_id != auth.uid()`
  (`fn_pointer_arrivee`, `fn_annuler_mission_soignant`, `fn_evaluer_etablissement`,
  `fn_enregistrer_pings_gps`, `fn_valider_code_secours`, `fn_scanner_code_pointage`).
  Probablement non exploitables (statut ASSIGNEE/EN_COURS exigé ensuite,
  `trg_coherence_statut_soignant`), à confirmer avant d'étendre la règle au dump.
* **RBAC** : `fn_enforce_etablissement_rbac_trigger` devrait refuser un INSERT
  sur `missions` par un compte authentifié sans rôle d'établissement.
  L'alignement fin des gardes sur `fn_a_permission_etablissement` (`pointage`,
  `missions`, `lecture_contrats`, `paiement`) est un changement de sémantique
  RBAC, à décider séparément.

## 6. Vérifications

* Garde statique : `node --test tests/node/gardes-null-security-definer.node.mjs`
  (scanner et ses choix, dump, ordre de merge, migrations à partir de
  `20261103013434`, différence unique par corps LIVE, branchement CI). Le test
  « ordre de merge » est **rouge par construction** tant que scanner et B5b ne
  sont pas mergés et cette branche rebasée.
* Recette SQL : `tests/security/gardes-null-security-definer.test.sql`, exécutée
  sur staging par `validate-pr`, sous ROLLBACK. Elle couvre 82 refus et
  49 appelants légitimes et vérifie l'absence d'effet. Pool urgence : un soignant
  fixture éligible (même cohorte test, documents vérifiés) rend le pool non vide
  et les autres soignants éligibles sont exclus le temps du test ; A et ADM
  obtiennent exactement ce soignant (téléphone compris) et une diffusion, S, T, R
  et B 0. `fn_deposer_chorus` est exercée sur une facture fixture EMISE.
  **Jamais exécutée à ce jour** : elle le sera à l'ouverture de la PR.
* Post-déploiement, en lecture seule :

```sql
-- Corps, inventaire et ACL (20 lignes attendues, toutes à true / true / false / true :
-- corps_ok, inventaire_ok, anon, authenticated).
SELECT v.signature, md5(p.prosrc) = v.md5 AS corps_ok, i.definition_md5 = v.md5 AS inventaire_ok,
       has_function_privilege('anon', p.oid, 'EXECUTE') AS anon,
       has_function_privilege('authenticated', p.oid, 'EXECUTE') AS authenticated
FROM (VALUES ('fn_valider_alerte_presence(uuid)', '1ff0c4c48ccd906f161e1a9174034505')
             /* … les 19 autres couples du manifeste de la migration … */) AS v(signature, md5)
JOIN pg_proc p ON p.oid = to_regprocedure('public.' || v.signature)
JOIN private.security_definer_inventory i ON i.signature = v.signature;

-- Registre (statements peuplés).
SELECT version, name, cardinality(statements) > 0 AS statements_ok
FROM supabase_migrations.schema_migrations WHERE version = '20261103013434';

-- Audit a posteriori : codes de secours, QR et numéros DPAE émis par un compte
-- ni membre de l'établissement, ni propriétaire historique, ni admin.
SELECT ja.cree_le, ja.acteur_id, ja.details->>'evenement' AS evenement, m.id AS mission_id
FROM journaux_audit ja
LEFT JOIN codes_secours_mission cs ON ja.details->>'evenement' = 'CODE_SECOURS_GENERE' AND cs.id = ja.id_ressource
LEFT JOIN qr_codes_mission q ON ja.details->>'evenement' = 'QR_GENERE' AND q.id = ja.id_ressource
LEFT JOIN contrats_mission cm ON ja.details->>'evenement' = 'DPAE_NUMERO_ENREGISTRE' AND cm.id = ja.id_ressource
JOIN missions m ON m.id = COALESCE(cs.mission_id, q.mission_id, cm.mission_id)
WHERE ja.details->>'evenement' IN ('CODE_SECOURS_GENERE', 'QR_GENERE', 'DPAE_NUMERO_ENREGISTRE')
  AND ja.acteur_id IS DISTINCT FROM m.etablissement_id
  AND NOT EXISTS (SELECT 1 FROM membres_etablissement me
                  WHERE me.user_id = ja.acteur_id AND me.etablissement_id = m.etablissement_id)
  AND NOT EXISTS (SELECT 1 FROM equipe_admin ea WHERE ea.user_id = ja.acteur_id);
```

`fn_valider_alerte_presence` n'écrit pas d'audit : une auto-validation passée ne
se reconnaît pas a posteriori.

## 7. Ordre de merge

Branches B9 du 02/11 dont la migration précède `20261103013434` :

| Ordre | Branche | Migration | Lien avec ce lot |
|---|---|---|---|
| 1 | `fix/score-matching-inconnu-null` | `20261102204820` | aucune fonction commune (`fn_obtenir_missions_swipe`) |
| 2 | `fix/scanner-code-sans-code-suivant` | `20261102205212` | porte le correctif de `fn_declarer_fin_retroactive` : **verrou** (entrée REVUES conditionnée) |
| 3 | `fix/contestation-paiement-soignant` | `20261102205808` | aucune fonction commune (`fn_contester_paiement_soignant`) |
| 4 | `fix/visibilite-etablissement-par-permission` (B5b) | `20261102210943` | porte le correctif de `fn_etat_pointage_mission` : **verrou** (entrée REVUES conditionnée) |
| 5 | `fix/gardes-null-security-definer` (ce lot) | `20261103013434` | en dernier |

Les quatre premières s'ordonnent entre elles selon leurs propres contraintes ;
aucune ne redéfinit l'une des 20 fonctions de ce lot (vérifié sur leurs fichiers
du 03/11). La protection stricte de main impose de les merger une par une ;
avant le merge de ce lot :

1. rebaser cette branche sur main (conflits attendus seulement dans
   `.github/workflows/validate-pr.yml` et `supabase/schema/public.sql`,
   fonctions disjointes : garder les deux côtés) ;
2. `node --test tests/node/gardes-null-security-definer.node.mjs` doit être
   entièrement vert, test « ordre de merge » compris ;
3. relire les md5 LIVE des 20 fonctions (le contrôle « avant » de la migration
   refuse toute divergence) ;
4. `validate-pr` rejoue la recette SQL sur staging.

Si ce lot devait malgré tout passer avant l'une des quatre : la garde statique le
refuse pour scanner et B5b ; pour score-matching et contestation, renommer leur
migration après `20261103013434` (CLAUDE.md, migrations règle 2, même si
`deploy-supabase` accepte `--include-all`) et la repartir de son LIVE.

## 8. Recette frontend

Voir la section dédiée ci-dessous, complétée par la recette simulée.
