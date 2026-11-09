# Gardes NULL des fonctions SECURITY DEFINER (B9)

> Statut : **PR B9 en attente du go explicite de Gabrielle** (SECURITY DEFINER,
> autorisation, escrow, facturation). Migrations
> `supabase/migrations/20261109010957_gardes_null_security_definer.sql`
> (renommée le 09/11 : ex-`20261103013434`, antérieure aux migrations du 08/11)
> et `supabase/migrations/20261109020404_verrou_double_facturation_generer_facture.sql`
> (verrou du gap « double facturation », §5 ; décision prise par Claude sur
> délégation explicite de Gabrielle du 08/11/2026).
> **Ordre de merge imposé** (§7) : les quatre branches B9 du 02/11 sont mergées ;
> dans la file sérielle, ce lot passe après #1123 puis #1124.

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

Une seule différence par fonction, partie de la définition LIVE (relue en lecture
seule le 03/11, puis le 09/11 après les merges du 08/11 #1114, #1117, #1118, #1119
et #1120 : `md5(prosrc)`, `md5(pg_get_functiondef)`, arguments, résultat,
`proconfig`, ACL et inventaire identiques, aucune des 20 fonctions redéfinie
entre-temps). Le texte exact de `pg_get_functiondef` est versionné dans
`tests/security/fixtures/gardes-null-security-definer-live.sql`. La comparaison
passe sous `COALESCE(..., false)`.
Un `NULL` vaut « pas d'accès ». Les appelants dont la comparaison valait déjà
`true` ou `false` gardent exactement le même résultat. Messages, ACL,
volatilité et `search_path` sont inchangés (`CREATE OR REPLACE`, aucun GRANT).

**Une exception voulue pour l'admin plateforme.** Partout ailleurs, l'admin
passe par `est_admin()`. La branche établissement de `fn_creer_reclamation_score`
n'a pas de `est_admin()` : l'admin, sans établissement, y passait par le `NULL`
et y est désormais refusé (`NON_AUTORISE`). C'est voulu : une réclamation de
score d'établissement se dépose depuis l'établissement, l'admin la **traite**
(décision prise par Claude sur délégation explicite de Gabrielle du
08/11/2026). Recette SQL : ADM dans les refus du cas 21.

**`fn_etablissement_pour_mission` : resserrement conservé.** Un soignant partie
à un contrat dont la mission a été réattribuée ne voit plus la fiche de
l'établissement (« — »). Le contrat porte déjà l'identité de l'établissement,
et une mission réattribuée ne doit plus exposer la fiche (décision prise par
Claude sur délégation explicite de Gabrielle du 08/11/2026). Autoriser
`contrats_mission.soignant_id = auth.uid()` changerait le prédicat : hors de ce
lot.

| Fonction | Gravité | Avant (appelant sans établissement) | Après |
|---|---|---|---|
| `fn_valider_alerte_presence` | critique | le soignant valide sa propre présence ; `dec_proteger_presence_soignant` et `fn_protect_presence_integrity` ne revertent pas (même NULL) → `trg_escrow_release_on_validation` | `Accès refusé` |
| `fn_generer_facture` | critique | facture de commission créée sur la mission d'un tiers | `Accès refusé` ; puis **EXECUTE retiré à authenticated et anon** (migration `20261109020404`, §5) : 42501 |
| `fn_generer_code_secours_mission` | haute | le soignant se génère un code de secours puis pointe | `NON_AUTORISE` |
| `fn_generer_qr_mission` (+ `fn_regenerer_qr_mission`) | haute | le soignant se génère un QR de pointage | `NON_AUTORISE` |
| `fn_soignants_urgence` | haute | noms, scores et **téléphones** du pool urgence | 0 ligne |
| `fn_generer_donnees_dpae` | haute | données DPAE d'un contrat (NIR, date et lieu de naissance, établissement) | `Non autorisé` |
| `fn_presences_detail_mission` | haute | présences (heures réelles, retards, validité du périmètre GPS) de la mission d'un autre soignant ; sur une mission **sans soignant assigné**, aussi pour un membre d'un **autre établissement** (les deux comparaisons valaient NULL) | `Accès refusé` |
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
désormais refusé comme tout appelant sans établissement (recette SQL : acteur
SYS refusé sur ces quinze fonctions ; il garde la fiche d'un établissement qui a
une mission OUVERTE, comme tout compte). Les cinq autres
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
| `fn_declarer_fin_retroactive` (`v_caller_is_etab_admin`, `v_caller_is_soignant`) | `OR COALESCE(v_caller_is_etab_admin, false)` et `NOT (COALESCE(v_caller_is_soignant, false)` (migration `20261102205212`) | Même défaut, corrigé par la PR B9 #1117 `fix/scanner-code-sans-code-suivant` (COALESCE à l'usage), **mergée le 08/11** ; les deux preuves figurent dans le corps LIVE relu le 09/11. La redéfinir ici réintroduirait `nouveau_code`/`nouveau_hmac`. |
| `fn_etat_pointage_mission` (`v_is_etab`, `v_is_soignant`) | `IF NOT COALESCE(v_is_etab, false) AND NOT COALESCE(v_is_soignant, false) THEN` (migration `20261102210943`) | Même défaut, corrigé par la PR B9 B5b #1119 `fix/visibilite-etablissement-par-permission` (COALESCE à l'usage, code réservé à la permission `pointage`), **mergée le 08/11** ; preuve présente dans le corps LIVE relu le 09/11. |
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
pour CP5b : il est documenté, pas rendu impossible. La double facturation est
verrouillée par cette PR, la fin rétroactive depuis le 08/11.

* **CP5b, pointage par codes statiques (gravité haute, fraude)** :
  `fn_pointer_arrivee`/`fn_pointer_depart` acceptent `p_code_arrivee`/`p_code_depart`
  et sautent alors le contrôle GPS. Le soignant assigné lit ces codes en
  PostgREST : il peut pointer hors de l'établissement. Verrou proposé (B1-ter) :
  lever une exception explicite si un code est passé, avec référence à
  `docs/POINTAGE_CODE_ROTATIF_VISIBILITE.md`, après un `git grep` des appelants
  (web, iOS, mobile-native : aucun ne les passe à ce jour), puis `REVOKE SELECT`
  de table et GRANT colonne par colonne sur `code_arrivee`, `code_depart`,
  `code_pointage_actif`, `code_pointage_hmac`.
* **CP5b sera verrouillé après #1124, dans une PR B9 séparée** : #1124 redéfinit
  `fn_pointer_arrivee` ; le verrou repartira de son corps LIVE post-#1124
  (garde-fou 9.0 n°2).
* ~~Double facturation `fn_generer_facture` puis prélèvement SEPA
  automatique~~ : **verrouillé dans cette PR** (migration distincte
  `20261109020404_verrou_double_facturation_generer_facture.sql`). Décision prise
  par Claude sur délégation explicite de Gabrielle du 08/11/2026.
  * Gap : la RPC ne refuse que `factures.mission_id = p_mission_id`, alors que
    la facturation courante rattache les missions autrement ; une mission déjà
    facturée pouvait recevoir une seconde facture de commission, prélevée par
    `sepa-auto-charge`.
  * Appelants vérifiés le 09/11 : aucun dans `src/` (seul le type généré
    `src/integrations/supabase/types.ts`), `supabase/functions/`, `ios-native/`,
    `mobile-native/`, `scripts/` ; en production (lecture seule) 0 job
    `cron.job`, 0 fonction `pg_proc` qui l'appelle, 0 appel dans
    `pg_stat_statements` depuis sa remise à zéro du 11/08/2026.
  * Verrou retenu, faute d'appelant client vivant : `REVOKE EXECUTE … FROM
    PUBLIC, anon, authenticated`. Tout appel client reçoit 42501 ; service_role
    garde EXECUTE ; corps, propriétaire et `search_path` inchangés. Inventaire
    SECURITY DEFINER : `MIXTE_TENANT_ADMIN` → `SERVICE_ONLY_REVOQUE`. Le
    préflight vérifie les ACL LIVE, le corps corrigé par `20261109010957` et
    l'absence d'appelant interne ou cron ; le postflight vérifie le retrait.
  * Gardes du verrou : recette SQL (A, ADM, S en authenticated et un anon :
    42501), banc PostgreSQL 17 isolé (42501 et rejeu refusé), garde statique
    (aucun appelant client dans le dépôt, dump aligné).
  * `supabase/SECURITY_DEFINER_MANIFEST.json` n'est pas modifié : c'est
    l'instantané figé du 29/07 (vérifié contre `20260729121443`), comme pour les
    PR B9 précédentes.
* ~~`fn_declarer_fin_retroactive`~~ : fermé par #1117, mergée et déployée le
  08/11 (preuve relue dans le corps LIVE le 09/11, §3).

### Autres suites

* **RPC sans appelant front** : `fn_valider_alerte_presence` et
  `fn_deposer_chorus` ne sont appelées ni par le web ni par iOS. On peut faire un
  `REVOKE EXECUTE … FROM authenticated` sur le modèle de `20261109020404`
  (`fn_generer_facture` est déjà verrouillée).
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
  (13 tests) : scanner et ses choix, dump, ordre de merge, migrations à partir
  de `20261109010957`, horodatages postérieurs au registre distant et à #1124,
  **aucune chaîne hexadécimale ≥ 32** dans les fichiers du lot, différence
  unique par corps LIVE comparée texte à texte à la fixture
  `pg_get_functiondef`, dump aligné, manifeste du préflight, seconde migration
  (REVOKE exact, gardes, inventaire, dump), aucun appelant client de
  `fn_generer_facture`, bancs PostgreSQL 17 et leur câblage CI, matrice de la
  recette SQL, et **aucun `CASE` nu dans une condition `IF`** des fichiers SQL
  du lot (son `THEN` clôturerait le `IF` : défaut réel trouvé dans la recette
  SQL du 03/11 et corrigé le 09/11).
* Migrations : préflight et postflight **calculés** (aucune empreinte écrite en
  dur, GitGuardian refuse les chaînes hexadécimales ou base64 de 32 caractères
  et plus).
  * `20261109010957` : le préflight capture chaque corps LIVE, exige la garde
    LIVE une seule fois et l'absence de sa correction (rejeu refusé :
    `GARDES_NULL_PREFLIGHT_SOURCE_DRIFT`) et une empreinte d'inventaire égale au
    `md5` du corps LIVE. Le postflight exige
    `md5(replace(nouveau corps, garde corrigée, garde LIVE)) = md5(corps LIVE)`,
    des attributs et ACL inchangés, puis aligne l'inventaire sur le nouveau
    corps. Toute dérive annule la migration entière (`GARDES_NULL_POSTFLIGHT_*`).
  * `20261109020404` (verrou double facturation, §5) : préflight sur le corps
    corrigé, les ACL LIVE, l'inventaire et l'absence d'appelant interne ou cron ;
    postflight sur le retrait d'EXECUTE (ni PUBLIC, ni anon, ni authenticated,
    service_role conservé) et l'inventaire `SERVICE_ONLY_REVOQUE`. Un rejeu
    échoue (`VERROU_FACTURE_PREFLIGHT_ACL_DRIFT`).
* Recette SQL : `tests/security/gardes-null-security-definer.test.sql`, exécutée
  sur staging par `validate-pr` (job `sql-transaction`, même transaction que les
  deux migrations, sous ROLLBACK). **103 refus et 52 appelants légitimes**, puis
  4 refus 42501 du verrou facture, et l'absence d'effet des refus.
  * Acteurs : S, T, R (sans établissement), B (autre établissement), A
    (propriétaire), ADM et **SYS** (contexte système : `auth.uid()` NULL, rôle
    `service_role` des claims), refusé sur les quinze fonctions du §2.
  * `fn_presences_detail_mission` : mission assignée (cas 11) et **mission sans
    soignant assigné** (cas 24, refus S, T, R, B, SYS ; A et ADM passent). Le
    cas 24 est le seul qui exerce la seconde comparaison : il est rouge sur le
    corps LIVE et sur les deux corps à demi corrigés (preuve ci-dessous).
  * Passants : **réponse positive attendue** pour chaque cas, une seule forme
    par cas : réponse exacte, objet contenu, contrôle métier exact levé après la
    garde (SQLSTATE et message lus dans le code LIVE : validation de présence
    avant fin de planning, code de secours avant affectation) ou réponse égale à
    celle de la suite métier appelée directement dans le même contexte annulé
    (`fn_assigner_mission_admin` → `fn_finaliser_attribution_mission`). Plus
    aucune exception quelconque n'est comptée comme un passage.
  * Pool urgence : un soignant fixture éligible (même cohorte test, documents
    vérifiés) rend le pool non vide ; A et ADM obtiennent exactement ce soignant
    (téléphone compris) et une diffusion, les refusés 0.
  * **Exécutable seulement en CI** (base staging nécessaire, aucun PostgreSQL
    local) : jamais exécutée hors CI à ce jour.
* Bancs PostgreSQL 17 isolés (job `paiements-concurrence` de `validate-pr`) :
  `tests/security/gardes-null-security-definer-isolated.test.sql` et
  `…-rejeu.test.sql`, sur le banc B5b réutilisé
  (`fixtures/visibilite-etablissement-permission-banc.sql` : helpers d'identité
  LIVE, acteurs) complété par `fixtures/gardes-null-security-definer-banc.sql`
  (les 20 corps LIVE, ACL et inventaire de production). Ils exécutent **les
  vraies migrations** :
  * matrice de `fn_presences_detail_mission` sur 7 acteurs × 2 missions × 4
    phases (LIVE, deux variantes à demi corrigées, après migration) : chaque
    variante à demi corrigée laisse encore fuir la mission non assignée, seule
    la migration complète la refuse ;
  * 20 corps : seule la garde a changé, inventaire suivi, ACL inchangées sauf
    `fn_generer_facture` (42501 pour authenticated et anon) ;
  * rejeu refusé (`GARDES_NULL_PREFLIGHT_SOURCE_DRIFT`), corps LIVE dérivé hors
    garde refusé au postflight (`GARDES_NULL_POSTFLIGHT_CORPS_OU_ATTRIBUTS`),
    rejeu du verrou refusé (`VERROU_FACTURE_PREFLIGHT_ACL_DRIFT`).
  * **Exécutables seulement en CI** (aucun PostgreSQL local). Syntaxe validée
    localement par le parseur PostgreSQL 17 (pglast/libpg_query).
* Preuve locale du cas 24 (09/11, PostgreSQL 17.6 de production, `SELECT` pur
  sans lecture de table ni écriture) : la garde évaluée avec les valeurs de la
  mission sans soignant assigné laisse passer S, T, R, B et SYS sur le corps
  LIVE, S, T, R, B et SYS sur la variante 1 (seule la comparaison
  d'établissement corrigée), S, T, R et SYS sur la variante 2 (seule la
  comparaison `auth.uid()` corrigée), et ne refuse les cinq que sur le corps
  corrigé. La garde statique échoue aussi sur un corps de migration à demi
  corrigé (deux tests rouges).
* Post-déploiement, en lecture seule :

```sql
-- Corps, inventaire et ACL (20 lignes attendues : corps_ok, inventaire_ok à true ;
-- anon à false ; authenticated à true sauf fn_generer_facture). Empreintes calculées.
SELECT v.signature,
       pg_catalog.strpos(p.prosrc, v.garde_corrigee) > 0 AS corps_ok,
       i.definition_md5 = pg_catalog.md5(p.prosrc) AS inventaire_ok,
       has_function_privilege('anon', p.oid, 'EXECUTE') AS anon,
       has_function_privilege('authenticated', p.oid, 'EXECUTE') AS authenticated
FROM (VALUES ('fn_valider_alerte_presence(uuid)',
              'IF NOT COALESCE(v_presence.etablissement_id = v_etab_id, false) AND NOT est_admin() THEN')
             /* … les 19 autres couples (signature, garde corrigée) du manifeste de la migration … */
     ) AS v(signature, garde_corrigee)
JOIN pg_proc p ON p.oid = to_regprocedure('public.' || v.signature)
JOIN private.security_definer_inventory i ON i.signature = v.signature;

-- Registre (statements peuplés) des deux migrations.
SELECT version, name, cardinality(statements) > 0 AS statements_ok
FROM supabase_migrations.schema_migrations WHERE version IN ('20261109010957', '20261109020404');

-- Audit a posteriori : codes de secours, QR et numéros DPAE émis par un compte
-- ni membre de l'établissement, ni propriétaire historique, ni admin. Les codes
-- et QR portent leur mission dans details->>'mission_id' ; le numéro DPAE est
-- rattaché par son contrat (id_ressource). Les événements dont la mission a
-- disparu sont comptés à part (NON_RESOLU), et signalés si l'acteur est un
-- soignant : sans mission, l'audit ne prouve rien.
WITH ev AS (
  SELECT ja.cree_le, ja.acteur_id, ja.details->>'evenement' AS evenement,
         CASE WHEN ja.details->>'evenement' = 'DPAE_NUMERO_ENREGISTRE'
              THEN (SELECT cm.mission_id FROM contrats_mission cm WHERE cm.id = ja.id_ressource)
              ELSE NULLIF(ja.details->>'mission_id', '')::uuid END AS mission_id
    FROM journaux_audit ja
   WHERE ja.details->>'evenement' IN ('CODE_SECOURS_GENERE', 'QR_GENERE', 'DPAE_NUMERO_ENREGISTRE')
), classes AS (
  SELECT ev.*, m.etablissement_id,
         CASE
           WHEN m.id IS NULL AND EXISTS (SELECT 1 FROM soignants s WHERE s.id = ev.acteur_id)
             THEN 'NON_RESOLU_ACTEUR_SOIGNANT'
           WHEN m.id IS NULL THEN 'NON_RESOLU'
           WHEN ev.acteur_id IS NOT DISTINCT FROM m.etablissement_id
             OR EXISTS (SELECT 1 FROM membres_etablissement me
                         WHERE me.user_id = ev.acteur_id AND me.etablissement_id = m.etablissement_id)
             OR EXISTS (SELECT 1 FROM equipe_admin ea WHERE ea.user_id = ev.acteur_id) THEN 'LEGITIME'
           ELSE 'SUSPECT'
         END AS classe
    FROM ev LEFT JOIN missions m ON m.id = ev.mission_id
)
SELECT evenement, classe, count(*) AS n, count(DISTINCT acteur_id) AS acteurs
FROM classes GROUP BY 1, 2 ORDER BY 1, 2;
-- Puis le détail : SELECT * FROM classes WHERE classe IN ('SUSPECT', 'NON_RESOLU_ACTEUR_SOIGNANT').
```

Relevé du 09/11 (production, lecture seule) : 1 597 `CODE_SECOURS_GENERE` et
3 146 `QR_GENERE`, tous `NON_RESOLU` (missions de test supprimées), émis par
2 comptes ; 0 `NON_RESOLU_ACTEUR_SOIGNANT`, 0 `SUSPECT`, 0 `DPAE_NUMERO_ENREGISTRE`.

`fn_valider_alerte_presence` n'écrit pas d'audit : une auto-validation passée ne
se reconnaît pas a posteriori.

## 7. Ordre de merge

Branches B9 du 02/11 dont la migration précède celle de ce lot, **toutes mergées
sur main le 08/11** (fusion `origin/main` du 09/11 dans cette branche, sans
rebase) :

| Ordre | Branche | Migration | Lien avec ce lot |
|---|---|---|---|
| 1 | `fix/score-matching-inconnu-null` (#1114) | `20261102204820` | aucune fonction commune (`fn_obtenir_missions_swipe`) |
| 2 | `fix/scanner-code-sans-code-suivant` (#1117) | `20261102205212` | porte le correctif de `fn_declarer_fin_retroactive` : **verrou** (entrée REVUES conditionnée, tenue) |
| 3 | `fix/contestation-paiement-soignant` (#1118) | `20261102205808` | aucune fonction commune (`fn_contester_paiement_soignant`) |
| 4 | `fix/visibilite-etablissement-par-permission` (B5b, #1119) | `20261102210943` | porte le correctif de `fn_etat_pointage_mission` : **verrou** (entrée REVUES conditionnée, tenue) |

File de merge sériel restante :

| Ordre | PR | Migration | Lien avec ce lot |
|---|---|---|---|
| 5 | #1123 `fix/dpae-contrats-cddu-vacation` | — (front seul) | aucun fichier commun |
| 6 | #1124 `fix/dpae-serveur-cddu-vacation` | `20261108223500` | redéfinit `fn_mes_dpae`, `fn_rappel_dpae_quotidien`, `fn_pointer_arrivee`, `fn_annuler_candidature_soignant`, `dec_email_contrat_signe_complet` : **aucune des 20 fonctions** de ce lot (vérifié sur son fichier du 09/11), aucun corps commun |
| 7 | `fix/gardes-null-security-definer` (ce lot) | `20261109010957`, `20261109020404` | en dernier |

Ce lot a été renommé de `20261103013434` en `20261109010957` : la migration de
#1124 (`20261108223500`) lui serait sinon postérieure, et `supabase db push`
refuserait l'ordre (CLAUDE.md, migrations règle 2). La garde statique exige
désormais un horodatage postérieur à `20261108223500` et à la dernière version du
registre de production (`20261102210943` au 09/11).

Après le merge de #1124, fusionner main dans cette branche (sans rebase) et
**porter le compte à 66 à la main** : simulation faite, git fusionne seul le
commentaire « les 65 suites » et `assert.equal(…, 65)`, puisque les deux côtés
font 64 → 65. Seuls les `assert.match` entrent en conflit. Le test paiements
échouerait alors (66 suites pour 65 attendues) : rien de silencieux, mais le
commentaire resterait faux.

1. `.github/workflows/validate-pr.yml` : `SQL_TESTS` passe à **66** suites (main
   64 + #1124 + ce lot) ; garder `tests/security/dpae-contrats-cddu-vacation.test.sql`
   et `tests/security/gardes-null-security-definer.test.sql`, la contestation
   restant **en fin de liste** (exigence de son test node), et corriger le
   commentaire en « les 66 suites » ;
2. `tests/node/paiements-staging-installed.node.mjs` : compte, titre du test et
   `assert.equal` à 66, garder les `assert.match` des deux suites ;
3. `supabase/schema/public.sql` : fonctions disjointes, fusion attendue sans
   conflit ;
4. l'étape PostgreSQL 17 isolée de ce lot est insérée avant celle du scanner,
   celle de #1124 après : pas de conflit attendu ;
5. puis rejouer `node --test tests/node/gardes-null-security-definer.node.mjs`
   (entièrement vert) et relire les corps LIVE des 20 fonctions : le préflight
   refuse toute divergence.

Si ce lot devait malgré tout passer avant #1124, rien ne casse côté SQL
(fonctions disjointes) ; seule la migration de #1124 deviendrait antérieure à la
dernière version distante et devrait être renommée après `20261109020404`
(CLAUDE.md, migrations règle 2).

Les deux migrations de ce lot (`20261109010957` puis `20261109020404`) partent
ensemble : le préflight du verrou exige le corps corrigé par la première.

## 8. Recette frontend

**Niveau : simulation avec réponses simulées** (`e2e/recette-complete-gardes-null.spec.ts`,
configuration `e2e/playwright.recette-complete.config.ts`, build
`VITE_SUPABASE_URL=http://127.0.0.1:8890`, `RECETTE_START_SERVER=1 CI=true`). Les
écrans sont ceux que les routes montent réellement (App.tsx) ; l'API est
interceptée par le harnais strict (tout appel inconnu = 501 et échec). Les
réponses « avant » reproduisent ce que la fonction LIVE non corrigée renvoyait à
l'appelant, les réponses « après » le refus de la fonction corrigée
(fixture LIVE §2). **Ni la garde SQL, ni la RLS, ni le staging ne sont exercés
ici** : la preuve SQL est la recette du §6 (CI). Aucune intégration réelle,
aucun appareil physique.

Exécution du 09/11 : **35/35** (7 cas × iphone, android, ipad-portrait,
ipad-paysage, ordinateur), aucune erreur de page, aucun appel inconnu ni
externe. Chaque cas : assertions sur le texte exact, corps des RPC appelées,
reprise après rechargement, dump ARIA (`test-results/recette-complete/gardes-null/<projet>/`).

| Cas | Rôle | Fonction | Résultat attendu et vérifié |
|---|---|---|---|
| Contrat d'une mission réattribuée | soignant | `fn_etablissement_pour_mission` | refus ; « SIRET : — Adresse : — Téléphone : — », ni nom ni SIRET de l'établissement |
| Présences d'une mission republiée (OUVERTE) | soignant tiers | `fn_presences_detail_mission` | avant : « Distance GPS 37m », « Méthode GPS » de l'ancien soignant ; après : synthèse sans aucune donnée de pointage d'un tiers |
| Présences de sa mission | soignant assigné | `fn_presences_detail_mission` | accès conservé (« Méthode CODE_ROTATIF ») |
| Présences de sa mission | établissement propriétaire | `fn_presences_detail_mission` | accès conservé (soignant, « Distance GPS 37m ») |
| Boost et protection remplacement | établissement propriétaire | `fn_booster_mission`, `fn_activer_garantie_mission` | « Mission boostée — 3 soignants… », « Protection remplacement activée ✓ », état repris après rechargement |
| DPAE | établissement propriétaire | `fn_generer_donnees_dpae`, `fn_enregistrer_numero_dpae` | données préparées, « DPAE déclarée » + numéro, repris après rechargement |
| DPAE, membre révoqué en cours de session | ex-membre (JWT établissement encore ouvert) | `fn_generer_donnees_dpae` | avant : données du salarié (date de naissance) affichées ; après : alerte « Non autorisé », aucune donnée, aucun numéro, même refus après rechargement |

Sans surface montée, donc sans recette UI possible (preuve SQL seulement) :
`QRPointageEtab` et `CodesPointageMission` ne sont importés par aucune route
(`fn_generer_qr_mission`, `fn_generer_code_secours_mission`,
`fn_codes_pointage_mission`) ; `fn_valider_alerte_presence`, `fn_deposer_chorus`,
`fn_generer_facture`, `fn_diffuser_pool_urgence`, `fn_annuler_serie`,
`fn_assigner_mission_admin`, `fn_definir_retrocession_mission` et
`fn_regenerer_qr_mission` n'ont aucun appelant web. Montées mais non rejouées
dans cette recette (appelants légitimes inchangés, refus couverts par la recette
SQL) : `fn_soignants_urgence` (pool urgence de la fiche mission),
`fn_rebooker_soignant` (tableau de bord), `fn_declarer_honoraires_retrocession`
(missions en rétrocession héritées ; la création en rétrocession est verrouillée avant lancement) et
`fn_creer_reclamation_score` (branche établissement).
