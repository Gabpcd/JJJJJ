# Contrats RPC de l'espace établissement (lot 5, tranche T0)

Document de référence des RPC que l'espace établissement du client Swift consommera au lot 5
(`docs/mobile-swift/LOT5_PLAN.md` §2.4-§2.5, §3 T0) : quatorze RPC propres à l'établissement, suivies en
`a_venir` lot 5 dans `RPC_SUIVIES_ETABLISSEMENT` de `scripts/mobile/check-rpc-contracts.mjs`, et sept RPC déjà
suivies par un lot soignant que l'établissement consomme aussi (`RPC_PARTAGEES_ETABLISSEMENT`, champ
`aussi_etablissement` du JSON). Pour chaque RPC : la signature SQL exacte de `supabase/schema/public.sql`
(dump de production re-baseliné le 01/11/2026), la classe du manifeste `supabase/SECURITY_DEFINER_MANIFEST.json`,
le GRANT, la signature de `src/integrations/supabase/types.ts`, la forme de réponse, les exceptions interceptées
et la relecture exigée après mutation.

Le fichier machine est `ios-native/rpc-contracts.json`, régénéré et comparé par
`node scripts/mobile/check-rpc-contracts.mjs` dans le job « Cœur — golden et contrats » de
`.github/workflows/ios-swift-ci.yml`. Pour les RPC de l'établissement, il porte en plus la **liste blanche des
exceptions** (`exceptions` : SQLSTATE, message, fonction et trigger d'origine) : une modification serveur d'un
message ou d'un SQLSTATE rougit le contrat avant que l'interception Swift ne se trompe. Le présent document est
gardé par `tests/node/contrats-etablissement-ios.node.mjs` (une fiche par RPC, exceptions verbatim, clés du
tableau de bord, matrice des permissions, matrice de parité), exécuté par l'étape « Garde de livraison mobile »
du check requis « Typecheck + build » (`.github/workflows/validate-pr.yml`). La procédure de re-baseline du schéma
est celle de `CONTRATS_RPC_SOIGNANT.md` (PR humaine, `--update`, fiche ajustée).

**Dédoublonnage.** Une RPC de l'établissement déjà suivie par un lot antérieur garde son entrée et son lot :
`fn_creer_notation_mission` (ajoutée par le T0 du lot 2) et `fn_obtenir_conversation` (T0 du lot 4) passent alors
en « partagées » sans doublon, quel que soit l'ordre des fusions (`check-rpc-contracts.mjs`, boucle d'ajout).

Règles de l'espace établissement (`LOT5_PLAN.md` §2.2-§2.8) :

- **Périmètre serveur.** Toutes les RPC du lot agissent sur `mon_etablissement_id()` (correction 3), jamais sur un
  identifiant passé ; le périmètre natif est l'établissement confirmé par `fn_mes_permissions_etab(NULL)` (D2).
  Le repli legacy `user.id` est un candidat comparé, jamais une valeur de filtre.
- **Permissions fail-closed.** Clé absente = `false` ; le serveur reste l'autorité (§2.7). Un refus `42501` de
  droit n'est **pas** « session expirée » : il est intercepté avant `SupabaseErrorMapping` (correction 5, D12),
  puis les permissions sont relues une fois.
- **Aucun montant.** Aucun champ monétaire, Stripe ou bancaire n'est décodé (D15) ; aucune note n'est lue (D8).
- **Relecture.** Chaque mutation est relue avant d'afficher un succès ; un délai client (15 s,
  `SessionController.resolutionTimeout`) ne prouve pas que le serveur n'a pas agi : relecture, jamais de renvoi.
- **Textes.** Les refus serveur s'affichent verbatim ; aucun texte juridique n'est écrit en Swift hors de
  `JoleneCore/Legal/TextesWeb.swift` (garde `scripts/mobile/check-litteraux-juridiques.mjs`, §2.9).

## Synthèse

| RPC | Statut natif | Lot (tranche) | Classe manifeste | GRANT | types.ts | Exceptions interceptées |
|---|---|---|---|---|---|---|
| `fn_mes_permissions_etab` | à venir | 5 (T1, T2) | MIXTE_TENANT_ADMIN | authenticated, service_role | déclarée | aucune |
| `fn_mon_etablissement_complet` | à venir | 5 (T1, T2, T12) | RPC_UTILISATEUR_AUTH_INTERNE | authenticated, service_role | déclarée | aucune |
| `fn_stats_dashboard_etablissement` | à venir | 5 (T4) | RPC_UTILISATEUR_AUTH_INTERNE | authenticated, service_role | déclarée | aucune |
| `fn_soignant_pour_etablissement` | à venir | 5 (T5) | MIXTE_TENANT_ADMIN | authenticated, service_role | déclarée | aucune |
| `fn_lire_candidatures_mission_habilitee` | à venir | 5 (T6) | hors manifeste — classement manuel RPC_UTILISATEUR_AUTH_INTERNE | authenticated | déclarée | `42501` |
| `fn_traiter_candidature_planning_v1` | à venir | 5 (T6) | hors manifeste — classement manuel RPC_UTILISATEUR_AUTH_INTERNE | authenticated, service_role | absente | `P0001` ×3 |
| `fn_contrat_signe_pour_pointage` | à venir | 5 (T7) | hors manifeste — classement manuel RPC_UTILISATEUR_AUTH_INTERNE | authenticated | absente | `42501` |
| `fn_valider_presence` | à venir | 5 (T8, B9) | RPC_UTILISATEUR_AUTH_INTERNE | authenticated, service_role | déclarée | `42501`, `23503`, `P0001` ×4 |
| `fn_valider_presences_lot` | à venir | 5 (T8, B9) | RPC_UTILISATEUR_AUTH_INTERNE | authenticated, service_role | déclarée | `42501`, `23503`, `P0001` ×4 |
| `fn_contester_presence` | à venir | 5 (T8, B9) | RPC_UTILISATEUR_AUTH_INTERNE | authenticated, service_role | déclarée | `42501` |
| `fn_creer_notation_mission` | à venir | 5 (T8, best-effort) — partagée si le lot 2 la suit | MIXTE_TENANT_ADMIN | authenticated, service_role | déclarée | `P0001` |
| `fn_declarer_fin_retroactive` | à venir | 5 (T8, B9) | MIXTE_TENANT_ADMIN | authenticated, service_role | déclarée | `P0002` ×2, `42501`, `23514` |
| `fn_creer_mission_multi_jours_v4` | à venir | 5 (T9) | hors manifeste — classement manuel RPC_UTILISATEUR_AUTH_INTERNE | authenticated, service_role | déclarée | `28000` |
| `fn_obtenir_conversation` | à venir | 5 (T11, port du lot 4) — partagée si le lot 4 la suit | MIXTE_TENANT_ADMIN | authenticated | déclarée | `28000`, `22023`, `42501` |
| `fn_get_my_role` | consommée lot 0 — aussi établissement | 0 (lot 5 T2) | MIXTE_TENANT_ADMIN | authenticated, service_role | déclarée | — (fiche soignant) |
| `fn_audit_connexion` | à venir — aussi établissement | 1 (lot 5 T2) | RPC_UTILISATEUR_AUTH_INTERNE | authenticated, service_role | déclarée | — (fiche soignant) |
| `fn_ecrire_audit_safe` | à venir — aussi établissement | 1 (lot 5 T4) | MIXTE_TENANT_ADMIN | authenticated, service_role | déclarée | — (fiche soignant) |
| `fn_param_bool` | à venir — aussi établissement | 1 (lot 5 T2) | RPC_UTILISATEUR_AUTH_INTERNE | authenticated, service_role | absente | — (fiche soignant) |
| `fn_etat_pointage_mission` | à venir — aussi établissement | 2 (lot 5 T7, T8) | MIXTE_TENANT_ADMIN | authenticated, service_role | absente | — (fiche soignant) |
| `fn_envoyer_otp_signature` | à venir — aussi établissement | 2 (lot 5 T10) | RPC_UTILISATEUR_AUTH_INTERNE | authenticated, service_role | déclarée | — (fiche soignant) |
| `fn_signer_contrat_otp` | à venir — aussi établissement | 2 (lot 5 T10) | RPC_UTILISATEUR_AUTH_INTERNE | authenticated, service_role | déclarée | — (fiche soignant) |

## Permissions établissement (§2.7)

Les 11 clés servies par `fn_mes_permissions_etab` (l.42290-42302) sont celles de `PERMISSIONS_VIDES` dans
`src/hooks/useEtabPermissions.ts` (l.21-33) ; les 5 rôles sont ceux du CHECK `membres_etablissement_role_check`.
La matrice ci-dessous est lue dans le `CASE` de `fn_a_permission_etablissement` (l.4905-4934) et comparée à ce
`CASE` par la garde : elle documente les fixtures démo (`demo-etab-permissions.json`, générées par T1 depuis le
même `CASE`) et les preuves par rôle. **Aucune de ces correspondances n'est écrite en Swift** : le natif lit les
booléens servis. `ADMIN_PLATEFORME` (`est_admin()`, `role` = `COALESCE(v_role, 'ADMIN_PLATEFORME')` l.42287) est un
rôle inconnu de l'espace établissement natif → écran de renvoi. Les clés `docs/EQUIPE_ETAB.md` (`validation_pointage`,
`lecture_finances`) n'existent pas (correction 14).

| Rôle | `gerer_equipe` | `supprimer_compte` | `profil_etab` | `paiement` | `lecture_paiement` | `missions` | `candidatures` | `contrats` | `pointage` | `rh` | `lecture` |
|---|---|---|---|---|---|---|---|---|---|---|---|
| `PROPRIETAIRE` | oui | oui | oui | oui | oui | oui | oui | oui | oui | oui | oui |
| `ADMIN_GROUPE` | non | non | oui | oui | oui | oui | oui | oui | oui | oui | oui |
| `RH` | non | non | non | non | non | oui | oui | oui | oui | oui | oui |
| `POINTAGE_ONLY` | non | non | non | non | non | non | non | non | oui | non | oui |
| `LECTURE_SEULE` | non | non | non | non | oui | non | non | non | non | non | oui |

Surfaces natives (§2.7) : `lecture` → Accueil, Missions, Présences, Messagerie ; `missions` → bouton Publier ;
`candidatures` → section candidatures ; `contrats` → contrats et OTP ; `pointage` → code rotatif, QR, valider,
lot, contester, clôturer ; `lecture_paiement` ∨ `paiement` → compteur « factures à régulariser » sans montant ;
`gerer_equipe` → lien web Équipe ; suppression du compte → lien web pour tout membre (D17).

## Listes blanches d'exceptions (§2.5, D12)

Extraction (`extraireExceptions`) : le corps de la RPC, puis les fonctions qu'elle appelle et les fonctions de
trigger qu'elle atteint, **nommées par RPC** dans `EXCEPTIONS_ETABLISSEMENT` (aucune exploration automatique) ;
formes `RAISE EXCEPTION '…'[, args] USING ERRCODE = …` et `RAISE EXCEPTION USING ERRCODE = …, MESSAGE = '…'` ;
sans `ERRCODE`, SQLSTATE `P0001` ; noms de condition traduits (`no_data_found` → `P0002`,
`insufficient_privilege` → `42501`, `check_violation` → `23514`). Un `%` formaté depuis `TG_ARGV[n]` est
instancié par l'argument littéral du trigger (`'pointage'` pour `trg_p0_rbac_presences`) ; tout autre `%` est un
**joker non vide** côté Swift. Fail-closed : message entièrement dynamique, condition inconnue, `%%`, chaîne
`E''`, trigger ou fonction absents → le script échoue au lieu de produire une liste fausse.

Traitement natif (T1, `RPC/RPCInterception.swift`) : `.accesRefuse` (42501 de la liste) → message serveur, ou
message neutre « Votre rôle dans cet établissement ne permet pas cette action. » pour le trigger RBAC, puis relecture
des permissions ; `.refusMetier` (P0001/P0002/23503/23514 de la liste) → verbatim ; `.nonAuthentifie` (28000) →
`.unauthorized`. Un 42501 hors liste garde le comportement du lot 0 ; `[CODE DU TRAVAIL]` reste intercepté (lot 1).

## fn_mes_permissions_etab

- **Statut natif** : à venir (lot 5, T1 port `EtabSessionPort.permissions`, T2 résolution de l'espace).
- **Usage** : source du périmètre (D2) — appel `p_etablissement_id: NULL`, corps exact `{"p_etablissement_id":null}` ;
  relu à l'ouverture, à la revalidation 30 min et après tout refus `accesRefuse`.
- **Signature SQL** (`supabase/schema/public.sql` l.42265) :

```sql
CREATE OR REPLACE FUNCTION "public"."fn_mes_permissions_etab"("p_etablissement_id" "uuid" DEFAULT NULL::"uuid") RETURNS "jsonb"
    LANGUAGE "plpgsql" STABLE SECURITY DEFINER
    SET "search_path" TO 'pg_catalog', 'public', 'auth'
```

- **Classe d'authentification (manifeste)** : `MIXTE_TENANT_ADMIN` pour `fn_mes_permissions_etab(uuid)`.
- **GRANT** : `REVOKE ALL … FROM PUBLIC` puis `authenticated`, `service_role` (l.83490-83492).
- **Signature TypeScript** : `Args: { p_etablissement_id?: string }` ; `Returns: Json`.
- **Forme de réponse** (HTTP 200, jamais d'exception) : compte inactif → `{success:false, role:null, permissions:{}}`
  (l.42274) → `.signedOut` ; aucun établissement → `{success:true, role:null, etablissement_id:null, permissions:{}}`
  (l.42277) ; membre révoqué (rôle nul, non admin) → même forme (l.42282) → `.blocked(ETAB_SANS_ACCES)` ; sinon
  `{success:true, role, etablissement_id, permissions{11 clés}}` (l.42285-42302), `role` ∈ 5 rôles ou
  `ADMIN_PLATEFORME`. Décodage : clé absente = `false`, rôle inconnu = bloqué, `etablissement_id` ≠ candidat →
  `.blocked(ETAB_SCOPE_DIVERGENT)`.
- **Exceptions** : aucune levée par le corps (liste blanche vide).
- **Relecture** : lecture seule ; une relecture qui change `etablissement_id` → divergence (epoch + 1) ; qui ne
  change que rôle/permissions → snapshot remplacé à epoch constant (§2.2).

## fn_mon_etablissement_complet

- **Statut natif** : à venir (lot 5, T1 `EtabSessionPort.profil`, T2 snapshot, T12 compte).
- **Usage** : profil de l'établissement courant (`mon_etablissement_id()`), sous-ensemble décodé seulement.
- **Signature SQL** (`supabase/schema/public.sql` l.44594) :

```sql
CREATE OR REPLACE FUNCTION "public"."fn_mon_etablissement_complet"() RETURNS "jsonb"
    LANGUAGE "plpgsql" SECURITY DEFINER
    SET "search_path" TO 'pg_catalog', 'public'
```

- **Classe d'authentification (manifeste)** : `RPC_UTILISATEUR_AUTH_INTERNE` pour `fn_mon_etablissement_complet()`.
- **GRANT** : `REVOKE ALL … FROM PUBLIC` puis `authenticated`, `service_role` (l.83735-83737).
- **Signature TypeScript** : `Args: never` ; `Returns: Json`.
- **Forme de réponse** : objet ligne `row_to_json` (l.44606-44645) ; `{error:'Etablissement introuvable'}` (l.44603,
  l.44647) → `leverSiErreur`. **Sous-ensemble décodé** (§2.2) : `id`, `nom`, `logo_url`, `type`,
  `peut_publier_missions`, `statut_verification`, `bloque_auto_le`, `contrat_service_signe`, `est_secteur_public`.
  **Jamais décodé** (correction 4, D15, D8) : `stripe_customer_id`, `stripe_account_id`, `iban_last4`, `rib_s3_key`,
  `siret`, `finess`, `taux_commission_negocie`, `taux_commission_effectif`, `paliers_commission`, `groupes_sante`,
  `bloque_auto_raisons` (montants dus), `note_moyenne`, `nb_evaluations` ; un test T1 échoue si le modèle les expose.
- **Exceptions** : aucune levée par le corps (liste blanche vide).
- **Relecture** : lecture seule.

## fn_stats_dashboard_etablissement

- **Statut natif** : à venir (lot 5, T4 Accueil, actions prioritaires).
- **Usage** : compteurs de l'Accueil, sans graphique ni montant (D15).
- **Signature SQL** (`supabase/schema/public.sql` l.57610) :

```sql
CREATE OR REPLACE FUNCTION "public"."fn_stats_dashboard_etablissement"() RETURNS "jsonb"
    LANGUAGE "plpgsql" SECURITY DEFINER
    SET "search_path" TO 'public'
```

- **Classe d'authentification (manifeste)** : `RPC_UTILISATEUR_AUTH_INTERNE` pour `fn_stats_dashboard_etablissement()`.
- **GRANT** : `REVOKE ALL … FROM PUBLIC` puis `authenticated`, `service_role` (l.84904-84906).
- **Signature TypeScript** : `Args: never` ; `Returns: Json`.
- **Forme de réponse** : `{error:'Établissement introuvable'}` (l.57627) ; sinon un objet de **18 clés**
  (l.57660-57702) : `a_deja_publie`, `total_missions`, `missions_ouvertes`, `missions_assignees`,
  `missions_en_cours`, `missions_terminees`, `missions_terminees_ce_mois`, `soignants_ce_mois`,
  `commissions_cumulees`, `commissions_impayees`, `nb_factures_impayees`, `pool_urgence_count`, `messages_non_lus`,
  `missions_a_payer`, `litiges_ouverts`, `candidatures_en_attente`, `candidatures_recentes`,
  `missions_assignees_detail`. Décodées par T4 (tolérantes, NULL toléré) : `candidatures_en_attente`,
  `missions_assignees_detail[]` (`mission_id`, `intitule`, `debut_le`, `fin_le`, `soignant_nom` de la mission
  assignée), `messages_non_lus`, `litiges_ouverts`, `nb_factures_impayees` (compteur seul, sous `lecture_paiement` ∨
  `paiement`), `pool_urgence_count`, `a_deja_publie`. **Jamais décodées** : `commissions_cumulees`,
  `commissions_impayees` (montants) et `candidatures_recentes` (noms complets servis à POINTAGE_ONLY, correction 4) ;
  « présences à valider » et « évaluations » n'ont pas de clé (correction 20).
- **Exceptions** : aucune levée par le corps (liste blanche vide).
- **Relecture** : lecture seule ; rechargée si le dernier chargement date de plus de 60 s (parité `staleTime` web).

## fn_soignant_pour_etablissement

- **Statut natif** : à venir (lot 5, T5 détail mission, soignant assigné).
- **Usage** : profil d'un soignant vu par l'établissement courant, noms à l'initiale hors relation contractuelle.
- **Signature SQL** (`supabase/schema/public.sql` l.57155) :

```sql
CREATE OR REPLACE FUNCTION "public"."fn_soignant_pour_etablissement"("p_soignant_id" "uuid") RETURNS "jsonb"
    LANGUAGE "plpgsql" SECURITY DEFINER
    SET "search_path" TO 'public'
```

- **Classe d'authentification (manifeste)** : `MIXTE_TENANT_ADMIN` pour `fn_soignant_pour_etablissement(uuid)`.
- **GRANT** : `REVOKE ALL … FROM PUBLIC` puis `authenticated`, `service_role` (l.84844-84846).
- **Signature TypeScript** : `Args: { p_soignant_id: string }` ; `Returns: Json`.
- **Forme de réponse** : `{error:'Accès refusé'}` (l.57165) → `leverSiErreur` ; `null` SQL quand le soignant est
  supprimé (`supprime_le IS NULL`, l.57212) → « Soignant indisponible », jamais un profil vide ; sinon objet
  (l.57183-57211) : `nom` complet seulement avec relation contractuelle, sinon initiale + `nom_anonymise:true` ;
  `telephone` seulement pour une mission du jour ou du lendemain (l.57194). **Jamais décodés** : `note_moyenne`,
  `nb_evaluations` (D8), `type_exercice` (le régime affiché vient de la mission, garde `test:guards` 7), `internat`
  (statuts d'internat non portés, D10).
- **Exceptions** : aucune levée par le corps (liste blanche vide).
- **Relecture** : lecture seule.

## fn_lire_candidatures_mission_habilitee

- **Statut natif** : à venir (lot 5, T6).
- **Usage** : lecture habilitée des candidatures d'une mission (un appel, cohorte TEST filtrée, adhésion
  vérifiée, noms à l'initiale) ; écart assumé et plus strict que le web monté (`DetailMission.tsx` →
  `ListeCandidatures` en PostgREST, correction 15), consigné dans `PARITE_ETABLISSEMENT.md`.
- **Signature SQL** (`supabase/schema/public.sql` l.39524) :

```sql
CREATE OR REPLACE FUNCTION "public"."fn_lire_candidatures_mission_habilitee"("p_mission_id" "uuid") RETURNS "jsonb"
    LANGUAGE "plpgsql" STABLE SECURITY DEFINER
    SET "search_path" TO ''
```

- **Classe d'authentification (manifeste)** : hors manifeste — classement manuel `RPC_UTILISATEUR_AUTH_INTERNE`
  (comme la décision 6 du lot 1 ; contrôle `auth.uid()`, compte actif, e-mail confirmé, rôle et permission
  `candidatures` dans le corps) ; manifeste non régénéré.
- **GRANT** : `REVOKE ALL … FROM PUBLIC` puis `authenticated` seul (l.83214-83215).
- **Signature TypeScript** : `Args: { p_mission_id: string }` ; `Returns: Json`.
- **Forme de réponse** : `{mission{id, intitule, etablissement_id, etablissement_nom, statut, mode_attribution,
  nb_creneaux, profession_requise, specialite_medicale_requise, accepte_internes}, creneaux[{id, mission_id, debut,
  fin, est_pause, type_creneau}], candidatures[{id, soignant_id, message, statut, cree_le, soignant{…,
  nom_anonymise:true}}]}` (l.39556-39581) ; créneaux PREVISIONNEL hors pause triés `debut, id` (ordre de
  l'empreinte de T6) ; candidats hors cohorte de test de l'établissement filtrés en silence (l.39581).
  `type_contrat_recherche` n'y figure pas : lu par T5 (D25). `mission.id` ≠ demandé → `.contract`.
- **Exceptions** :
  - `42501` « Mission indisponible ou accès refusé » (`fn_lire_candidatures_mission_habilitee`, l.39533, l.39542,
    l.39553 : non authentifié, e-mail non confirmé, mission illisible, pas de permission `candidatures`, adhésion
    absente) → `accesRefuse(message serveur)` + relecture des permissions.
- **Relecture** : lecture seule ; relue avant le récapitulatif, avant l'envoi (empreinte) et après l'issue.

## fn_traiter_candidature_planning_v1

- **Statut natif** : à venir (lot 5, T6 ; hors B9 sous condition D25).
- **Usage** : acceptation (missions `SALARIE` hors `MEDECIN` seulement, refus local avant réseau sinon, D25) et
  refus d'une candidature. Acceptation : `p_decision 'ACCEPTEE'`, `p_creneaux_confirmes` = **chaînes `debut`/`fin`
  relues telles quelles** (D26), `p_motif` NULL. Refus : `p_decision 'REFUSEE'`, `p_creneaux_confirmes` NULL,
  `p_motif 'Refusé par l''établissement'` (web).
- **Signature SQL** (`supabase/schema/public.sql` l.61869) :

```sql
CREATE OR REPLACE FUNCTION "public"."fn_traiter_candidature_planning_v1"("p_candidature_id" "uuid", "p_decision" "text", "p_creneaux_confirmes" "jsonb" DEFAULT NULL::"jsonb", "p_motif" "text" DEFAULT NULL::"text") RETURNS "jsonb"
    LANGUAGE "plpgsql" SECURITY DEFINER
    SET "search_path" TO 'pg_catalog', 'public'
```

- **Classe d'authentification (manifeste)** : hors manifeste — classement manuel `RPC_UTILISATEUR_AUTH_INTERNE`
  (délègue à `fn_traiter_candidature_planning_v1_internal_20260810` l.61972 puis `fn_traiter_candidature` l.61705,
  contrôles `auth.uid()` et établissement dans les délégués) ; manifeste non régénéré.
- **GRANT** : `REVOKE ALL … FROM PUBLIC` puis `service_role`, `authenticated` (l.85149-85151).
- **Signature TypeScript** : absente de `types.ts` (le contrat est tenu par `public.sql`).
- **Forme de réponse** (HTTP 200, discriminée par clés, `RPCResponse` du lot 1) :
  - succès : `{success:true, choix_applique?, contrat_id?}` (acceptation, via `fn_finaliser_attribution_mission`) ;
    `{success:true}` (refus, l.61782) ;
  - cadre étudiant AS (`est_etudiant ∧ scolarite_verifiee ∧ scolarite_profession_autorisee = 'AS'`, l.61898-61900) :
    `{success:false, code, error}` avec `CADRE_ETUDIANT_PROFESSION_INVALIDE`, `CADRE_ETUDIANT_SALARIAT_REQUIS`,
    `CADRE_ETUDIANT_STRUCTURE_INELIGIBLE` → refus verbatim, et `CADRE_ETUDIANT_A_CONFIRMER` → `.cadreEtudiant`,
    renvoi web (jamais `CADRE_ETUDIANT_AS_CONFIRME` envoyé en natif, D10, correction 19) ;
  - planning : `{success:false, code:'PLANNING_A_RECONFIRMER', error}` (l.62046) et
    `{success:false, code:'PLANNING_MODIFIE_RECONFIRMER', error}` (l.62093) → `.planningAReconfirmer`, jamais renvoyé
    automatiquement ;
  - délégué interne : `{success:false, error}` « Non authentifié. », « Décision invalide. », « Candidature
    introuvable. », « Mission introuvable ou accès refusé. » (l.61988-62021) ;
  - `fn_traiter_candidature` **sans clé `success`** : `{error}` « Décision invalide », « Candidature introuvable »,
    « Mission introuvable », « Non autorisé », « Cette candidature a déjà été traitée. » (l.61718-61757) → verbatim ;
    `{error, documents_requis_pour, …}` ; `{choix_requis:true, error, options}` → `.refusee` verbatim (le web l'affiche
    tel quel).
- **Exceptions** :
  - `P0001` « Notification d'acceptation impossible : % » (`fn_traiter_candidature`, l.61834) → message générique
    (préfixe connu, suite non garantie) ;
  - `P0001` « Cette mission ne peut pas être attribuée : l'établissement doit d'abord configurer un mode de paiement
    (Paramètres → Facturation). » (`fn_trg_gate_assignation_paiement` via `trg_gate_assignation_paiement`, l.63314) →
    `.paiementNonConfigure` verbatim + Safari `/etablissement/facturation` ;
  - `P0001` « Cette mission ne peut pas être attribuée : le mandat SEPA de l'établissement n'est pas encore posé (IBAN
    à ajouter dans Paramètres → Facturation). » (même trigger, l.63317) → idem ;
  - `[CODE DU TRAVAIL]` (triggers atteints par `UPDATE missions`) : interception du lot 1, verbatim.
- **Relecture** : relire `fn_lire_candidatures_mission_habilitee` : candidature `ACCEPTEE` **et** mission
  `ASSIGNEE` (acceptation), candidature `REFUSEE` (refus) ; sinon « non confirmé », jamais succès.
- **Écart D26 consigné** : l'établissement renvoie les chaînes relues (écho exact, microsecondes et décalage
  conservés : le serveur compare des instants `::timestamptz`, l.62061-62090), alors que le soignant du lot 1 passe
  par `CreneauxConfirmes.pourAction` (ré-émission UTC sans fraction). Type commun `CreneauConfirme` (voie `lus`).

## fn_contrat_signe_pour_pointage

- **Statut natif** : à venir (lot 5, T7 code rotatif).
- **Usage** : savoir si le contrat de la mission est `SIGNE_COMPLET` sans accès au contrat (POINTAGE_ONLY) ; relu
  toutes les 60 s par l'écran de pointage.
- **Signature SQL** (`supabase/schema/public.sql` l.25865) :

```sql
CREATE OR REPLACE FUNCTION "public"."fn_contrat_signe_pour_pointage"("p_mission_id" "uuid") RETURNS boolean
    LANGUAGE "plpgsql" STABLE SECURITY DEFINER
    SET "search_path" TO ''
```

- **Classe d'authentification (manifeste)** : hors manifeste — classement manuel `RPC_UTILISATEUR_AUTH_INTERNE`
  (contrôles `auth.uid()`, compte actif, `lecture_pointage` et `pointage` dans le corps) ; manifeste non régénéré.
- **GRANT** : `REVOKE ALL … FROM PUBLIC` puis `authenticated` seul (l.82180-82181).
- **Signature TypeScript** : absente de `types.ts`.
- **Forme de réponse** : `boolean` (contrat `SIGNE_COMPLET` entre les mêmes parties que la mission, l.25893-25899).
- **Exceptions** :
  - `42501` « Lecture du pointage non autorisée. » (`fn_contrat_signe_pour_pointage`, l.25874, l.25880, l.25887) →
    interceptée en `false` + bandeau « code masqué » ; un segment ouvert garde le code de départ seulement avec
    `pointage` (§2.5).
- **Relecture** : lecture seule.

## fn_valider_presence

- **Statut natif** : à venir (lot 5, T8 — **B9 paiements/escrow** : la validation déclenche
  `trg_escrow_release_on_validation`, correction 6).
- **Usage** : validation unitaire après note 1-5 (D6) et relecture des créneaux.
- **Signature SQL** (`supabase/schema/public.sql` l.65364) :

```sql
CREATE OR REPLACE FUNCTION "public"."fn_valider_presence"("p_presence_id" "uuid") RETURNS "jsonb"
    LANGUAGE "plpgsql" SECURITY DEFINER
    SET "search_path" TO 'public'
```

- **Classe d'authentification (manifeste)** : `RPC_UTILISATEUR_AUTH_INTERNE` pour `fn_valider_presence(uuid)`.
- **GRANT** : `REVOKE ALL … FROM PUBLIC` puis `authenticated`, `service_role` (l.85505-85507).
- **Signature TypeScript** : `Args: { p_presence_id: string }` ; `Returns: Json`.
- **Forme de réponse** : `{success:true}` (l.65419) ; `{success:false, error}` « Non autorisé » (l.65374),
  « Présence introuvable » (l.65384), « Déjà validée » (l.65388 → relecture puis état validé). L'audit
  `PRESENCE_VALIDATION` et la notification `PRESENCE_VALIDEE` sont écrits par le serveur : jamais doublés.
- **Exceptions** :
  - `42501` « Permission etablissement pointage requise » (`fn_enforce_etablissement_rbac_trigger` via
    `trg_p0_rbac_presences`, argument `'pointage'`, l.32239) → message neutre + relecture des permissions ;
  - `23503` « Mission introuvable pour cette présence. » (`dec_bloquer_validation_presence_avant_fin_planning` via
    `trg_bloquer_validation_presence_avant_fin_planning`, forme `USING MESSAGE`) → verbatim ;
  - `P0001` « La présence ne peut être validée avant la fin du dernier créneau planifié. » (même trigger) → verbatim ;
  - `P0001` « Le planning détaillé doit être terminé avant validation de la présence. » (même trigger) → verbatim ;
  - `P0001` « Un pointage est encore ouvert pour cette mission. » (même trigger) → verbatim ;
  - `P0001` « Aucun pointage terminé ne permet de valider cette présence. » (même trigger) → verbatim.
- **Relecture** : relire la présence : `valide_par_etablissement == true` et `valide_le` non nul (valeur serveur,
  jamais posée localement) ; puis `fn_creer_notation_mission` best-effort.

## fn_valider_presences_lot

- **Statut natif** : à venir (lot 5, T8 — **B9**).
- **Usage** : validation en lot des présences éligibles relues.
- **Signature SQL** (`supabase/schema/public.sql` l.65459) :

```sql
CREATE OR REPLACE FUNCTION "public"."fn_valider_presences_lot"("p_ids" "uuid"[]) RETURNS "jsonb"
    LANGUAGE "plpgsql" SECURITY DEFINER
    SET "search_path" TO 'public'
```

- **Classe d'authentification (manifeste)** : `RPC_UTILISATEUR_AUTH_INTERNE` pour `fn_valider_presences_lot(uuid[])`.
- **GRANT** : `REVOKE ALL … FROM PUBLIC` puis `authenticated`, `service_role` (l.85516-85518).
- **Signature TypeScript** : `Args: { p_ids: string[] }` ; `Returns: Json`.
- **Forme de réponse** : `{success:true, nb_validees}` (l.65537) — seules les présences non validées avec
  `perimetre_gps_valide` et sans téléportation sont validées (l.65486-65487) ; `{success:false, error:'Non autorisé'}`
  (l.65473, permission `pointage` contrôlée dans le corps).
- **Exceptions** :
  - `42501` « Permission etablissement pointage requise » (`fn_enforce_etablissement_rbac_trigger` via
    `trg_p0_rbac_presences`) ;
  - `23503` « Mission introuvable pour cette présence. » et `P0001` « La présence ne peut être validée avant la fin du
    dernier créneau planifié. », « Le planning détaillé doit être terminé avant validation de la présence. », « Un
    pointage est encore ouvert pour cette mission. », « Aucun pointage terminé ne permet de valider cette présence. »
    (`dec_bloquer_validation_presence_avant_fin_planning` via `trg_bloquer_validation_presence_avant_fin_planning`) :
    une seule ligne en faute annule tout le lot (une instruction `UPDATE`).
- **Relecture** : relire chaque id et compter ; afficher « N validées sur M sélectionnées » avec les valeurs relues,
  `nb_validees` serveur seulement.

## fn_contester_presence

- **Statut natif** : à venir (lot 5, T8 — **B9** : `motif_litige` bloque la libération d'escrow, l.63177).
- **Usage** : contestation d'une présence « à valider » (non validée et validable), motif ≥ 3 caractères.
- **Signature SQL** (`supabase/schema/public.sql` l.25802) :

```sql
CREATE OR REPLACE FUNCTION "public"."fn_contester_presence"("p_presence_id" "uuid", "p_motif" "text") RETURNS "jsonb"
    LANGUAGE "plpgsql" SECURITY DEFINER
    SET "search_path" TO 'public'
```

- **Classe d'authentification (manifeste)** : `RPC_UTILISATEUR_AUTH_INTERNE` pour `fn_contester_presence(uuid,text)`.
- **GRANT** : `REVOKE ALL … FROM PUBLIC` puis `authenticated`, `service_role` (l.82174-82176).
- **Signature TypeScript** : `Args: { p_motif: string; p_presence_id: string }` ; `Returns: Json`.
- **Forme de réponse** : `{success:true}` (l.25857) ; `{success:false, error}` « Non autorisé » (l.25815), « Le motif
  est obligatoire (3 caractères min.) » (l.25819), « Présence introuvable » (l.25829). Aucun refus d'une présence déjà
  validée côté serveur (candidat B5b) : le natif ne propose la contestation que pour une présence à valider.
- **Exceptions** :
  - `42501` « Permission etablissement pointage requise » (`fn_enforce_etablissement_rbac_trigger` via
    `trg_p0_rbac_presences`) → message neutre + relecture des permissions.
- **Relecture** : relire `motif_litige` de la présence.

## fn_creer_notation_mission

- **Statut natif** : à venir (lot 5, T8, best-effort après validation relue ; si le T0 du lot 2 la suit, entrée du
  lot 2 et annotation `aussi_etablissement`).
- **Usage** : note 1-5 de l'établissement (`p_sens 'ETAB_VERS_SOIGNANT'`, quatre critères = la note, comme
  `NotationRapide.tsx`) ; écriture seulement, aucune lecture de `notations_missions` (D8).
- **Signature SQL** (`supabase/schema/public.sql` l.27282) :

```sql
CREATE OR REPLACE FUNCTION "public"."fn_creer_notation_mission"("p_mission_id" "uuid", "p_sens" "text", "p_critere_1" integer, "p_critere_2" integer, "p_critere_3" integer, "p_critere_4" integer, "p_commentaire" "text" DEFAULT NULL::"text") RETURNS "jsonb"
    LANGUAGE "plpgsql" SECURITY DEFINER
    SET "search_path" TO 'public', 'extensions'
```

- **Classe d'authentification (manifeste)** : `MIXTE_TENANT_ADMIN` pour
  `fn_creer_notation_mission(uuid,text,integer,integer,integer,integer,text)`.
- **GRANT** : `REVOKE ALL … FROM PUBLIC` puis `authenticated`, `service_role` (l.82268-82270).
- **Signature TypeScript** : `Args: { p_commentaire?: string; p_critere_1: number; p_critere_2: number; p_critere_3:
  number; p_critere_4: number; p_mission_id: string; p_sens: string }` ; `Returns: Json`.
- **Forme de réponse** : `{success:true, id, tardive}` (l.27442) ; `{success:false, error}` (l.27300-27375) ; « Mission
  déjà notée pour ce sens » (l.27399) = succès (parité web).
- **Exceptions** :
  - `P0001` « La notation n’a pas pu être enregistrée. Veuillez réessayer. » (`fn_creer_notation_mission`, audit en
    échec, l.27425, l.27439) → verbatim, jamais bloquant : la validation déjà relue n'est pas défaite.
- **Relecture** : aucune (best-effort, ordre du web : validation relue puis note).

## fn_declarer_fin_retroactive

- **Statut natif** : à venir (lot 5, T8 — **B9**).
- **Usage** : clôture rétroactive du segment ouvert, `p_raison` = texte du web, heure choisie dans
  [début du segment ouvert, maintenant] (D28 : le serveur n'interdit pas une heure future).
- **Signature SQL** (`supabase/schema/public.sql` l.28664) :

```sql
CREATE OR REPLACE FUNCTION "public"."fn_declarer_fin_retroactive"("p_mission_id" "uuid", "p_heure_fin" timestamp with time zone, "p_raison" "text" DEFAULT 'Oubli de scan'::"text") RETURNS "jsonb"
    LANGUAGE "plpgsql" SECURITY DEFINER
    SET "search_path" TO 'public'
```

- **Classe d'authentification (manifeste)** : `MIXTE_TENANT_ADMIN` pour
  `fn_declarer_fin_retroactive(uuid,timestamp with time zone,text)`.
- **GRANT** : `REVOKE ALL … FROM PUBLIC` puis `authenticated`, `service_role` (l.82349-82351).
- **Signature TypeScript** : `Args: { p_heure_fin: string; p_mission_id: string; p_raison?: string }` ; `Returns: Json`.
- **Forme de réponse** : succès = objet **sans clé `success`** `{creneau_effectif_id, debut_creneau, fin_declaree,
  horodatage_arrondi, validation_etab_requise, nouveau_code, nouveau_hmac, prochain_type_scan, numero_scan}`
  (l.28805) → `requiredString("creneau_effectif_id")` (correction 17). `nouveau_code` et `nouveau_hmac` (nouveau code
  de pointage) ne sont **jamais décodés, journalisés ni affichés** : le code est relu par `fn_etat_pointage_mission`
  sous permission `pointage`.
- **Exceptions** :
  - `P0002` « Mission % introuvable ou dans un statut incompatible. » (`fn_declarer_fin_retroactive`, l.28687) →
    verbatim, `%` joker (identifiant de mission) ;
  - `42501` « Vous n'êtes pas autorisé(e) à déclarer une fin rétroactive sur cette mission. » (l.28696) →
    `accesRefuse` verbatim ;
  - `P0002` « Aucun créneau effectif ouvert à fermer pour cette mission. » (l.28709) → verbatim ;
  - `23514` « L'heure de fin (%) doit être postérieure au début du créneau (%). » (l.28713) → verbatim, deux jokers.
- **Relecture** : `fn_etat_pointage_mission.segment_ouvert == false`.

## fn_creer_mission_multi_jours_v4

- **Statut natif** : à venir (lot 5, T9 publication simple ou urgente, salariée, taux horaire, D8).
- **Usage** : 16 paramètres exacts (T9) : `p_type_contrat_recherche 'SALARIE'`, `p_mode_remuneration 'TAUX_HORAIRE'`,
  `p_retrocession_pct` NULL, `p_nature_tva_prestation` NULL, `p_specialite_medicale_requise` NULL,
  `p_accepte_internes false`, profession hors `MEDECIN`, `p_creneaux = [{debut,fin}]` ISO `Z`.
- **Signature SQL** (`supabase/schema/public.sql` l.27251) :

```sql
CREATE OR REPLACE FUNCTION "public"."fn_creer_mission_multi_jours_v4"("p_intitule" "text", "p_description" "text", "p_profession_requise" "public"."type_profession", "p_service" "text", "p_taux_horaire_base" numeric, "p_est_urgente" boolean, "p_niveau_urgence" integer, "p_mode_attribution" "text", "p_specialite_medicale_requise" "text", "p_accepte_non_specialises" boolean, "p_creneaux" "jsonb", "p_type_contrat_recherche" "text", "p_mode_remuneration" "text", "p_retrocession_pct" numeric, "p_nature_tva_prestation" "text", "p_accepte_internes" boolean) RETURNS "jsonb"
    LANGUAGE "plpgsql" SECURITY DEFINER
    SET "search_path" TO ''
```

- **Classe d'authentification (manifeste)** : hors manifeste — classement manuel `RPC_UTILISATEUR_AUTH_INTERNE`
  (`auth.uid()` et compte actif contrôlés l.27257-27259, puis `_v3` → `_v2` → `fn_creer_mission_multi_jours`) ;
  manifeste non régénéré.
- **GRANT** : `REVOKE ALL … FROM PUBLIC` puis `authenticated`, `service_role` (l.82262-82264).
- **Signature TypeScript** : 16 arguments (`p_accepte_internes: boolean`, `p_creneaux: Json`,
  `p_type_contrat_recherche: string`…) ; `Returns: Json`.
- **Forme de réponse** : `{success:true, mission_id, nb_creneaux, total_heures, type_contrat_recherche,
  mode_remuneration, nature_tva_prestation, statut_validation_tva, accepte_internes}` ; `{success:false, error}`
  (intitulé, profession, taux, planning de `fn_valider_creneaux_mission_json` dont `PLAFOND_48H_HEBDO`, passé ;
  choix internes l.27260-27265 ; nature TVA de `_v3` l.27182-27194) → verbatim ;
  `{success:false, code:'CREATION_MISSION_INDISPONIBLE', error}` (toute exception avalée par `_v2`, l.27155-27164,
  et la base, l.27050-27058) → verbatim ; **`{error: CODE, message}`** de `fn_blocage_publication_etab` (l.20685-20746)
  relayé tel quel (l.26892) → `message` prioritaire, `.blocageEtablissement` + renvoi web (activer/facturation) pour
  les codes `ETABLISSEMENT_NON_VERIFIE` (« Votre établissement doit être vérifié avant de publier des missions. »),
  `VERIFICATION_INCOMPLETE` (« Les contrôles SIRET, FINESS, identité et habilitation du représentant doivent être
  validés. »), `CONTRAT_SERVICE_REQUIS` (« Le contrat de service Jolene doit être signé avant de publier des
  missions. »), `PUBLICATION_SUSPENDUE` (« Publication suspendue en raison d obligations de paiement à
  régulariser. ») et `FACTURES_IMPAYEES` (« Vous avez des factures impayées à régulariser. »).
- **Exceptions** :
  - `28000` « Non authentifié » (`fn_creer_mission_multi_jours_v4`, l.27258) → `.unauthorized`.
- **Relecture** : relire `missions` (id, statut `OUVERTE`, `nb_creneaux`, `debut_le`, `fin_le`,
  `type_contrat_recherche == SALARIE`) et `mission_creneaux` PREVISIONNEL : multiset `(debut, fin)` égal à l'envoi ;
  sinon erreur, jamais succès (le trigger libéral peut muter `TOUS → SALARIE` en silence, correction 7).

## fn_obtenir_conversation

- **Statut natif** : à venir (lot 5, T11 « Envoyer un message » depuis le détail mission, par le port messagerie du
  lot 4 — aucun port partiel, D18 ; si le T0 du lot 4 la suit, entrée du lot 4 et annotation `aussi_etablissement`).
- **Usage** : get-or-create de la conversation liée à la mission.
- **Signature SQL** (`supabase/schema/public.sql` l.45620) :

```sql
CREATE OR REPLACE FUNCTION "public"."fn_obtenir_conversation"("p_autre_id" "uuid", "p_mission_id" "uuid" DEFAULT NULL::"uuid") RETURNS "uuid"
```

- **Classe d'authentification (manifeste)** : `MIXTE_TENANT_ADMIN` pour `fn_obtenir_conversation(uuid,uuid)`.
- **GRANT** : `REVOKE ALL … FROM PUBLIC` puis `authenticated` seul (l.83840-83841).
- **Signature TypeScript** : `Args: { p_autre_id: string; p_mission_id?: string }` ; `Returns: string`.
- **Forme de réponse** : `uuid` de la conversation (l.45803).
- **Exceptions** :
  - `28000` « Non authentifié » (`fn_obtenir_conversation`) → `.unauthorized` ;
  - `22023` « Interlocuteur invalide » → refus verbatim ;
  - `42501` « Conversation non autorisée » → issue « conversation indisponible », jamais « session expirée ».
- **Relecture** : ouverture du fil par le port du lot 4 (messages relus).

## fn_get_my_role

- **Fiche principale** : `CONTRATS_RPC_SOIGNANT.md` (lot 0).
- **Usage établissement** (T2) : rôle `ADMIN_ETABLISSEMENT` (comptes membres) ou alias signé `ETABLISSEMENT`
  (legacy) ; `etablissement_id` servi = candidat, confirmé par `fn_mes_permissions_etab` (correction 2). Le repli
  legacy `etablissementId = user.id` n'est jamais une valeur de filtre.

## fn_audit_connexion

- **Fiche principale** : `CONTRATS_RPC_SOIGNANT.md` (lot 1).
- **Usage établissement** (T2) : `CONNEXION` / `DECONNEXION` conservés comme le web (type d'acteur `mon_role()` côté
  serveur, §2.2) ; seul `fn_maj_activite_soignant` est sauté pour un établissement (correction 12, D19).

## fn_ecrire_audit_safe

- **Fiche principale** : `CONTRATS_RPC_SOIGNANT.md` (lot 1).
- **Usage établissement** (T4, D19) : `DONNEES_PERSO_CONSULTATION` à l'ouverture de l'Accueil comme le web
  (`p_type_acteur 'ADMIN_ETABLISSEMENT'`, `p_type_ressource 'etablissement'`, `p_id_ressource = user.id`,
  `p_details {page}`), best-effort, par un port dédié (`EtabAuditPort`) ; aucun doublon des audits déjà écrits par le
  serveur (`PRESENCE_VALIDATION`, `PRESENCE_CONTESTATION`, `PRESENCE_VALIDATION_LOT`).

## fn_param_bool

- **Fiche principale** : `CONTRATS_RPC_SOIGNANT.md` (lot 1, décision 15).
- **Usage établissement** (T2) : drapeaux `ios_natif_etab_{accueil,missions,publier,presences,pointage,messages,compte}_actif`
  (B5a, D14), lus après `.readyEtablissement`, défaut fail-open ; aucun GRANT `anon`.

## fn_etat_pointage_mission

- **Fiche principale** : `CONTRATS_RPC_SOIGNANT.md` (lot 2).
- **Usage établissement** (T7 polling 5 s écran visible et scène active, D23 ; T8 relecture `segment_ouvert`) :
  `code_pointage_actif` est servi à **tout** membre (`v_is_etab`, l.35165, l.35188, correction 4) : il n'est affiché
  que si `permissions.pointage` ; `{error:'Mission introuvable'|'Accès interdit'}` → erreur. B5b (B9) propose de
  le restreindre côté serveur.

## fn_envoyer_otp_signature

- **Fiche principale** : `CONTRATS_RPC_SOIGNANT.md` (lot 2).
- **Usage établissement** (T10) : envoi de l'OTP au `telephone_contact` de l'établissement (pas au téléphone du
  membre), empreinte relue par le triple contrôle d'original du lot 2 ; permission `contrats`.

## fn_signer_contrat_otp

- **Fiche principale** : `CONTRATS_RPC_SOIGNANT.md` (lot 2).
- **Usage établissement** (T10) : signature OTP de l'établissement, refus `{success:false, error_code, error}`
  verbatim ; succès relu (`signature_etablissement_le` non nul). Signature manuscrite non portée (renvoi web).

## Jamais appelées par l’espace établissement natif

Aucune gateway de l'espace établissement ne les appelle ; la garde des littéraux `"fn_…"` du Swift
(`tests/node/check-rpc-contracts.node.mjs`) refuse déjà toute RPC non suivie, et la garde
`check-litteraux-juridiques.mjs` refuse les noms de la matrice et des évaluations.

- `fn_mode_exercice` : le natif publie `SALARIE` / `TAUX_HORAIRE` seulement (D8) ; aucune règle de mode d'exercice
  (`matrice_modes_exercice`, `liberalEstSelectionnable`) n'est portée (§2.9).
- `fn_generer_qr_mission` : non exposée par le web (seul appelant `QRPointageEtab.tsx`, monté nulle part,
  correction 1) ; le QR natif encode `code_pointage_actif` (D4). Elle reste suivie par le lot 2 côté soignant.
- `fn_generer_code_secours_mission` : non exposée par le web (correction 1).
- `fn_annuler_mission_etablissement` : modification et annulation de mission = renvoi web (§1.2).
- `fn_ouvrir_litige_rate_limited` : litiges = renvoi web côté établissement (§1.2) ; la RPC reste suivie par les lots
  soignant (2/4) pour l'espace soignant.
- Lectures `notations_missions`, `evaluations`, `evaluations_publiees` : visibilité différée centralisée (D8,
  CLAUDE.md) ; l'établissement **écrit** une note (`fn_creer_notation_mission`) et n'en lit jamais.
- `fn_alerte_cddu_repetitif` (alerte de requalification « 150 jours », D27), `fn_terminer_mission` (facture générée),
  `fn_marquer_source_mission` (duplication) : surfaces web non portées au lot 5.

## Hors périmètre de ce document

Les tables lues en PostgREST par l'établissement (`missions` sans colonne monétaire, `mission_creneaux`, `presences`
sans coordonnées GPS, `contrats_mission` sous RLS `lecture_contrats`) ont leurs requêtes exactes dans les tests de
gateway des tranches T4, T5, T8 et T10 ; la messagerie (`fn_lister_conversations_messagerie`,
`fn_marquer_messages_lus`, Realtime `messages_chat`) dans les fiches du lot 4.
