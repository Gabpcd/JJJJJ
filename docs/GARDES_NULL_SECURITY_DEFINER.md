# Gardes NULL des fonctions SECURITY DEFINER (B9)

> Statut : **PR B9 en attente du go explicite de Gabrielle** (SECURITY DEFINER,
> autorisation, escrow, facturation). Migration
> `supabase/migrations/20261103013434_gardes_null_security_definer.sql`.

## 1. Le défaut

`mon_etablissement_id()` renvoie `NULL` pour tout appelant sans établissement
actif : soignant, membre révoqué (`membres_etablissement.actif = false`), service
sans identité. `est_admin_etablissement()` renvoie `NULL` quand
`fn_role_etablissement_courant(NULL)` ne trouve aucun rôle (défini ainsi depuis
`20260712230000_p0_securite_auth_rls.sql`, la version précédente était sous
`COALESCE(..., false)`).

En logique ternaire SQL, une garde de refus écrite

```sql
IF x.etablissement_id != mon_etablissement_id() AND NOT est_admin() THEN refus
IF NOT (est_admin() OR x.etablissement_id = mon_etablissement_id()) THEN refus
IF NOT est_admin_etablissement() AND NOT est_admin() THEN refus
```

vaut `NULL` pour ces appelants. PL/pgSQL ne prend pas la branche `IF NULL` et la
fonction continue. Comme elles sont `SECURITY DEFINER`, la RLS ne s'applique pas,
et `fn_enforce_etablissement_rbac_trigger` laisse aussi passer un appelant sans
rôle d'établissement (`fn_role_etablissement_courant(NULL) IS NULL → RETURN NEW`).

## 2. Correctif livré (21 fonctions)

Une seule différence par fonction, partie de la définition LIVE (md5 relu le
2026-11-03, identique au dump) : la comparaison passe sous `COALESCE(..., false)`.
Un `NULL` vaut « pas d'accès ». Les appelants dont la comparaison valait déjà
`true` ou `false` gardent exactement le même résultat. Messages, ACL,
volatilité et `search_path` sont inchangés (`CREATE OR REPLACE`, aucun GRANT).

| Fonction | Gravité | Avant (appelant sans établissement) | Après |
|---|---|---|---|
| `fn_valider_alerte_presence` | critique | le soignant valide sa propre présence ; `dec_proteger_presence_soignant` et `fn_protect_presence_integrity` ne revertent pas (même NULL) → `trg_escrow_release_on_validation` | `Accès refusé` |
| `fn_generer_facture` | critique | facture de commission créée sur la mission d'un tiers | `Accès refusé` |
| `fn_codes_pointage_mission` | haute | lecture (et génération) des codes statiques CP5b | `Accès interdit` |
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
| `fn_declarer_honoraires_retrocession` | moyenne (conditionnelle) | sur une mission RETROCESSION héritée : `total_brut`/`net_a_payer` fixés par le soignant | `Non autorisé` |
| `fn_etat_pointage_mission` | moyenne | statut et segments d'une mission non assignée/d'un tiers | `Accès interdit` |
| `fn_etablissement_pour_mission` | faible | fiche d'un établissement sans mission ouverte ni assignation | `Accès refusé` |
| `fn_creer_reclamation_score` | faible | réclamation sur un événement de score d'établissement (UUID requis) : bloque celle de l'établissement, notifie l'admin | `NON_AUTORISE` |
| `fn_definir_retrocession_mission` | faible | aujourd'hui bloqué par `trg_00_bloquer_retrocession_prelaunch` ; ouvert dès la levée du verrou | `Non autorisé` |
| `fn_annuler_serie` | défense en profondeur | garde franchie mais `UPDATE … WHERE etablissement_id = mon_etablissement_id()` → 0 ligne | `Accès refusé` |
| `fn_assigner_mission_admin` | défense en profondeur | garde franchie, la seconde (`IS DISTINCT FROM`) refuse | `Non autorisé` |

`fn_creer_reclamation_score`, `fn_declarer_honoraires_retrocession` et
`fn_definir_retrocession_mission` ne figuraient pas dans le constat initial : la
garde statique les a relevés.

## 3. Cas laissés en l'état, et pourquoi

Ces cas sont listés dans `REVUES` de `tests/node/gardes-null-security-definer.node.mjs`.
Toute nouvelle occurrence échoue, et une entrée devenue sans objet aussi.

| Fonction | Raison |
|---|---|
| `fn_declarer_fin_retroactive` | Même défaut, corrigé par la PR B9 `fix/scanner-code-sans-code-suivant` (migration `20261102205212`, `COALESCE` à l'usage de `v_caller_is_etab_admin`). La redéfinir ici depuis le LIVE réintroduirait `nouveau_code`/`nouveau_hmac` si cette migration passait après. |
| `dec_valider_paiement_facture` | Trigger `factures` : la RLS UPDATE est réservée à `est_admin()`. Le NULL est porteur pour le contexte système (webhook, cron sans `auth.uid()`) qui passe la facture `PAYEE`. |
| `fn_ouvrir_litige_rate_limited` (surcharge 4 arguments) | NULL seulement si la mission n'a pas de soignant assigné. La lecture `factures_honoraires … soignant_id = NULL` ne trouve alors rien et refuse. |
| `fn_suivi_remboursements_connect_facture` | `v_finance := v_admin OR (… = mon_etablissement_id() AND fn_a_permission_etablissement(…) IS TRUE)` : sans établissement, le second terme vaut `false`, et `NULL AND false = false`. |
| `fn_*_internal_20260801` (3) | Non SECURITY DEFINER, `EXECUTE` révoqué de PUBLIC. Appelées uniquement par leurs enveloppes, dont la garde utilise déjà `IS DISTINCT FROM`. |
| `dec_proteger_mission_soignant`, `dec_proteger_presence_soignant`, `fn_protect_mission_financials`, `fn_protect_presence_integrity`, `fn_protect_contrat_integrity` | Volet 2 ci-dessous. |

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

* **CP5b** (`fn_pointer_arrivee`/`fn_pointer_depart`) : lever une exception si
  `p_code_arrivee`/`p_code_depart` est non NULL (« un gap connu reste
  verrouillé »). Aucun appelant front ne les passe ; faire un `git grep`, iOS
  compris, avant.
* **Colonnes de codes** : `code_arrivee`, `code_depart`, `code_pointage_actif`
  et `code_pointage_hmac` sont lisibles par le soignant assigné en PostgREST
  (GRANT SELECT de table et `pol_mission_select`). Il faut un `REVOKE SELECT` de
  table et des GRANT colonne par colonne (voir B1-ter,
  `docs/POINTAGE_CODE_ROTATIF_VISIBILITE.md`).
* **RPC sans appelant front** : `fn_generer_facture`,
  `fn_valider_alerte_presence` et `fn_deposer_chorus` ne sont appelées ni par le
  web ni par iOS. On peut faire un `REVOKE EXECUTE … FROM authenticated` et mettre
  à jour `supabase/SECURITY_DEFINER_MANIFEST.json`.
* **`fn_generer_facture`** : refuser une mission déjà facturée
  (`commission_facturee OR facture_id IS NOT NULL`).
* **Codes de secours** : dans `fn_generer_code_secours_mission`, poser
  `type_acteur` selon l'appelant (`ADMIN_PLATEFORME` si `est_admin()`). Dans
  `fn_valider_code_secours`, refuser un code dont `cree_par` est le soignant
  lui-même.
* **QR** : dans `fn_valider_scan_qr`, signaler un jeton dont `cree_par` n'est ni
  membre de l'établissement ni le compte système.
* **RBAC** : `fn_enforce_etablissement_rbac_trigger` devrait refuser un INSERT
  sur `missions` par un compte authentifié sans rôle d'établissement.
  L'alignement fin des gardes sur `fn_a_permission_etablissement` (`pointage`,
  `missions`, `lecture_contrats`, `paiement`) est un changement de sémantique
  RBAC, à décider séparément.

## 6. Vérifications

* Garde statique : `node --test tests/node/gardes-null-security-definer.node.mjs`
  (dump, migrations à partir de `20261103013434`, différence unique par corps
  LIVE, branchement CI).
* Recette SQL : `tests/security/gardes-null-security-definer.test.sql`, exécutée
  sur staging par `validate-pr`, sous ROLLBACK. Elle couvre 85 refus et
  48 appelants légitimes, et vérifie l'absence d'effet.
* Post-déploiement, en lecture seule :

```sql
-- Corps, inventaire et ACL (21 lignes attendues, toutes à true / false / true).
SELECT v.signature, md5(p.prosrc) = v.md5 AS corps_ok, i.definition_md5 = v.md5 AS inventaire_ok,
       has_function_privilege('anon', p.oid, 'EXECUTE') AS anon,
       has_function_privilege('authenticated', p.oid, 'EXECUTE') AS authenticated
FROM (VALUES ('fn_valider_alerte_presence(uuid)', '1ff0c4c48ccd906f161e1a9174034505')
             /* … les 20 autres couples du manifeste de la migration … */) AS v(signature, md5)
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
