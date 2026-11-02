# Contrats RPC du parcours soignant (lot 0, plan §11 jour 8 ; lot 1, T0)

Document de référence des vingt-sept RPC que le client Swift consomme ou consommera (seize au lot 0,
onze ajoutées par la tranche T0 du lot 1, `docs/mobile-swift/LOT1_PLAN.md` §3), plus deux fiches hors
RPC : l'edge function `delete-account` (suppression de compte, Apple 5.1.1) et l'interdiction de
`fn_etablissement_public` côté natif. Pour chaque RPC : la
signature SQL exacte extraite de `supabase/schema/public.sql` (dump de production re-baseliné par
`schema-snapshot.yml`), la classe d'authentification du manifeste `supabase/SECURITY_DEFINER_MANIFEST.json`
(capture production du 2026-07-29, 422 fonctions), le GRANT connu, la signature TypeScript de
`src/integrations/supabase/types.ts` et l'emplacement de l'exemple de réponse STAGING à enregistrer en semaine 2.

Le fichier machine correspondant est `ios-native/rpc-contracts.json`, régénéré et comparé par
`node scripts/mobile/check-rpc-contracts.mjs` dans le job « Cœur — golden et contrats » de
`.github/workflows/ios-swift-ci.yml`. Toute dérive de signature, de GRANT ou de classe fait échouer la CI ;
`--update` réécrit le JSON après relecture des gateways Swift. Le présent document est lui-même gardé par
`tests/node/check-rpc-contracts.node.mjs` (une fiche par RPC suivie, RPC interdites, formes de réponse
confrontées à `public.sql` et à l'edge `delete-account`), exécuté sur toute PR par l'étape « Garde de
livraison mobile » du check requis « Typecheck + build » de `.github/workflows/validate-pr.yml`.

**Re-baseline du schéma (procédure).** Parce que cette garde tourne dans un check requis, une PR
automatique `auto/schema-baseline` (`schema-snapshot.yml`) qui modifie l'une des vingt-sept RPC suivies
(signature, GRANT, ou corps dont une fiche cite les réponses) reste bloquée — c'est voulu, fail-closed — et
`drift-check.yml` reste rouge tant qu'elle n'est pas mergée. Ne jamais corriger sur `auto/schema-baseline` :
le `git push --force` du run suivant efface tout commit manuel. Procédure : une **PR humaine**, depuis une
branche dédiée, porte le dump (`supabase/schema/public.sql` de la PR automatique ou de l'artefact
`schema-public-sql`) ; après relecture de la définition live (`scripts/dump-live-def.sh`) et des gateways
Swift concernées, elle ajoute `node scripts/mobile/check-rpc-contracts.mjs --update` (nouveau
`ios-native/rpc-contracts.json`) et la fiche ajustée dans ce document ; CI verte et revue fraîche, merge,
puis fermeture de la PR automatique devenue sans objet (le run suivant de `schema-snapshot.yml` ne trouve
plus de diff).

**Autres sources lues par la garde.** Outre les vingt-sept RPC suivies, la garde lit : les corps de six fonctions non suivies (`fn_conflit_planning_soignant`, `fn_postuler_mission`, `fn_postuler_mission_rate_limited`, `fn_finaliser_attribution_mission`, `fn_resoudre_contrat_mission`, `fn_demander_confirmations_presence`) ; le web `src/pages/DetailMissionSoignant.tsx` (chaînes de présence, tests `data?.choix_requis`, classement « mission perdue ») et `src/lib/erreurs.ts` (`estBlocageCodeTravail`) ; l'edge `supabase/functions/delete-account/index.ts` et `supabase/functions/_shared/admin-auth.ts` ; tout littéral `"fn_…"` des fichiers `ios-native/**/*.swift`. Une PR web, edge ou de re-baseline qui modifie l'une de ces sources met la fiche concernée à jour **dans la même PR**.

Règles (plan §4.4) : montants, net estimé et règles juridiques sont des valeurs serveur jamais recalculées ;
chaque gateway relit l'objet après mutation ; les erreurs PostgREST PGRST202 et 300 à 303 sont des refus
définitifs ; aucune RPC `fn_admin_*` n'est embarquée.

Règles ajoutées au lot 1 (`LOT1_PLAN.md` §2.3-§2.4) : les réponses `jsonb` en HTTP 200 sont polymorphes —
`{error}` seul ; `{success:false, ok:false, error, code?}` (refus propres à `fn_confirmer_action_planning_v1`) ;
`{success:false, error_code, …}` (`fn_annuler_candidature_soignant`) ; réponses des délégués de la
candidature **sans clé `success`** : `{choix_requis:true, error, options}`, `{error, code, …}` (plafond
48 h) et `{error, documents_requis_pour, lien_documents}` ; `{success:true, …}` ; exception PostgREST. Elles
passent par un décodeur unique `RPCResponse` qui les discrimine **par clés, indépendamment de `success`**,
dans l'ordre du web (`LOT1_PLAN.md` §2.4 : `choix_requis` → `code` → `documents_requis_pour` avec `error` →
`success:true` → `error` seul → sinon `.contract`) ; un gateway qui ne teste que l'erreur PostgREST
afficherait un faux succès, d'où un test par RPC et par forme de réponse. Chaque appel est borné à
`SessionController.resolutionTimeout` (15 s) ; un timeout client sur une mutation ne prouve pas que le
serveur n'a pas agi : relecture obligatoire, jamais de renvoi automatique.

## Synthèse

| RPC | Statut natif | Lot | Classe manifeste | GRANT | types.ts |
|---|---|---|---|---|---|
| `fn_get_my_role` | consommée lot 0 | 0 | MIXTE_TENANT_ADMIN | authenticated, service_role | déclarée |
| `fn_etablissements_safe` | consommée lot 0 | 0 | MIXTE_TENANT_ADMIN | authenticated, service_role | déclarée |
| `fn_mon_profil_soignant_complet` | à venir | 3 (reclassée, lot 1 v2 n°4) | RPC_UTILISATEUR_AUTH_INTERNE | authenticated, service_role | déclarée |
| `fn_dashboard_soignant_complet` | consommée lot 1 (T3) | 1 (T3) | RPC_UTILISATEUR_AUTH_INTERNE | authenticated, service_role | déclarée |
| `fn_confirmer_action_planning_v1` | à venir | 1 (T6a) | hors manifeste — classée RPC_UTILISATEUR_AUTH_INTERNE (décision 6) | authenticated, service_role | absente |
| `fn_suggestions_missions_pour_soignant` | à venir | 4 (reclassée, revue B8 de T3 : non consommée par l'Accueil) | RPC_UTILISATEUR_AUTH_INTERNE | authenticated, service_role | déclarée |
| `fn_annuler_candidature_soignant` | à venir | 1 (T7) | RPC_UTILISATEUR_AUTH_INTERNE | authenticated, service_role | déclarée |
| `fn_annuler_mission_soignant` | à venir | 1 (T7) | RPC_UTILISATEUR_AUTH_INTERNE | authenticated, service_role | déclarée |
| `fn_repondre_proposition` | à venir | 1 (T6a, refus seulement) | RPC_UTILISATEUR_AUTH_INTERNE | authenticated, service_role | déclarée |
| `fn_toggle_favori_etablissement` | à venir | 1 (T4b, retrait seulement) | RPC_UTILISATEUR_AUTH_INTERNE | authenticated, service_role | déclarée |
| `fn_mes_favoris_etablissements` | à venir | 1 (T4b) | RPC_UTILISATEUR_AUTH_INTERNE | authenticated, service_role | déclarée |
| `fn_audit_connexion` | à venir | 1 (T1/T9) | RPC_UTILISATEUR_AUTH_INTERNE | authenticated, service_role | déclarée |
| `fn_maj_activite_soignant` | à venir | 1 (T1/T9) | RPC_UTILISATEUR_AUTH_INTERNE | authenticated, service_role | déclarée |
| `fn_ecrire_audit_safe` | à venir | 1 (T1/T6a) | MIXTE_TENANT_ADMIN | authenticated, service_role | déclarée |
| `fn_supprimer_compte_rate_limited` | à venir | 1 (T8, via edge `delete-account`) | RPC_UTILISATEUR_AUTH_INTERNE | authenticated, service_role | déclarée |
| `fn_param_bool` | à venir | 1 (T1/T9) | RPC_UTILISATEUR_AUTH_INTERNE | authenticated, service_role | absente |
| `fn_confirmer_presence_mission` | à venir | 1 (T6c) | RPC_UTILISATEUR_AUTH_INTERNE | authenticated, service_role | déclarée |
| `fn_pointer_arrivee` | à venir | 2 | RPC_UTILISATEUR_AUTH_INTERNE | authenticated, service_role | déclarée |
| `fn_pointer_depart` | à venir | 2 | RPC_UTILISATEUR_AUTH_INTERNE | authenticated, service_role | déclarée |
| `fn_scanner_code_pointage` | à venir | 2 | RPC_UTILISATEUR_AUTH_INTERNE | authenticated, service_role | déclarée |
| `fn_valider_scan_qr` | à venir | 2 | RPC_UTILISATEUR_AUTH_INTERNE | authenticated, service_role | déclarée |
| `fn_generer_qr_mission` | à venir | 2 | MIXTE_TENANT_ADMIN | authenticated, service_role | déclarée |
| `fn_etat_pointage_mission` | à venir | 2 | MIXTE_TENANT_ADMIN | authenticated, service_role | absente |
| `fn_envoyer_otp_signature` | à venir | 2 | RPC_UTILISATEUR_AUTH_INTERNE | authenticated, service_role | déclarée |
| `fn_signer_contrat_otp` | à venir | 2 | RPC_UTILISATEUR_AUTH_INTERNE | authenticated, service_role | déclarée |
| `fn_remplacer_document_soignant` | à venir | 2 | RPC_UTILISATEUR_AUTH_INTERNE | authenticated, service_role | absente |
| `fn_upsert_token_push` | à venir | 3 | RPC_UTILISATEUR_AUTH_INTERNE | authenticated, service_role | déclarée |

Quatre RPC sont absentes de `types.ts` (`fn_confirmer_action_planning_v1`, `fn_param_bool`,
`fn_etat_pointage_mission`, `fn_remplacer_document_soignant`) : leur contrat est tenu par `public.sql` seul
jusqu'à régénération des types (`supabase gen types`) ; le web les appelle déjà avec `as any`
(`src/hooks/useParamBool.ts` l.18). Une RPC est hors manifeste (`fn_confirmer_action_planning_v1`, créée
après la capture du 2026-07-29) : **classée manuellement `RPC_UTILISATEUR_AUTH_INTERNE`** par la décision 6
du lot 1 (`LOT1_PLAN.md` §7), sans régénération du manifeste — voir sa fiche. `ios-native/rpc-contracts.json`
garde `manifeste: null` pour elle : c'est le fait observé, le classement est documentaire.

Deux RPC sont exclues, pour des raisons différentes, et `verifierExclusions`
(`scripts/mobile/check-rpc-contracts.mjs`) fait échouer la CI si l'une d'elles y entre trop tôt :
**jamais** `fn_etablissement_public` (fiche « Interdite côté natif » en fin de document) ; **pas avant le
lot 4** `fn_retirer_candidature` (swipe), suivie au plus tôt avec `lot: 4` — ce que fait le T0 du lot 4
(section « Lot 4 — synthèse »). À part, `fn_mon_profil_soignant_complet`
reste suivie mais est reclassée lot 3 (voir sa fiche).

## fn_get_my_role

- **Statut natif** : consommée dès le lot 0.
- **Usage prévu** : Résolution du rôle après connexion et après restauration de session (`RolePort.currentRole`). Raccourci `app_metadata.role` confirmé par cette RPC (plan §4.3).
- **Signature SQL** (`supabase/schema/public.sql` l.38216) :

```sql
CREATE OR REPLACE FUNCTION "public"."fn_get_my_role"() RETURNS "jsonb"
    LANGUAGE "plpgsql" STABLE SECURITY DEFINER
    SET "search_path" TO 'pg_catalog', 'public', 'auth'
```

- **Classe d'authentification (manifeste)** : `MIXTE_TENANT_ADMIN` pour `fn_get_my_role()` — Mixte tenant / admin : la fonction distingue en interne soignant, établissement et admin ; appel avec le JWT utilisateur.
- **GRANT connu** : `REVOKE ALL … FROM PUBLIC` puis `GRANT ALL … TO "authenticated", "service_role"`.
- **Signature TypeScript** (`types.ts`, section `Functions`) : `Args: never` ; `Returns: Json`.
- **Exemple de réponse STAGING** : à enregistrer en semaine 2 (plan §11 jour 8), depuis le compte TEST de la cohorte, corps JSON anonymisé, sans jeton ni identifiant de compte réel.

## fn_etablissements_safe

- **Statut natif** : consommée dès le lot 0.
- **Usage prévu** : Projection sûre des établissements affichés sur les cartes mission (liste Explorer, détail). Appelée avec les `etablissement_id` des missions chargées, jamais pour tout le référentiel.
- **Signature SQL** (`supabase/schema/public.sql` l.35044) :

```sql
CREATE OR REPLACE FUNCTION "public"."fn_etablissements_safe"("p_ids" "uuid"[]) RETURNS TABLE("id" "uuid", "nom" "text", "adresse_rue" "text", "adresse_code_postal" "text", "adresse_ville" "text", "adresse_departement" "text", "adresse_lat" numeric, "adresse_lng" numeric, "type" "text", "finess" "text", "taux_majoration_nuit_pourcent" numeric, "taux_majoration_dimanche_pourcent" numeric, "taux_majoration_ferie_pourcent" numeric, "logo_url" "text", "couleur_theme" "text", "paiement_rapide" boolean, "jour_paie_habituel" smallint)
    LANGUAGE "plpgsql" SECURITY DEFINER
    SET "search_path" TO 'public'
```

- **Classe d'authentification (manifeste)** : `MIXTE_TENANT_ADMIN` pour `fn_etablissements_safe(uuid[])` — Mixte tenant / admin : la fonction distingue en interne soignant, établissement et admin ; appel avec le JWT utilisateur.
- **GRANT connu** : `REVOKE ALL … FROM PUBLIC` puis `GRANT ALL … TO "authenticated", "service_role"`.
- **Signature TypeScript** (`types.ts`, section `Functions`) : `Args: { p_ids: string[] }` ; `Returns: { adresse_code_postal: string; adresse_departement: string; adresse_lat: number; adresse_lng: number; adresse_rue: string; adresse_ville: string; couleur_theme: string; finess: string; id: string; logo_url: string; nom: string; taux_majoration_dimanche_pourcent: number; taux_majoration_ferie_pourcent: number; taux_majoration_nuit_pourcent: number; type: string }[]`.
- **Exemple de réponse STAGING** : à enregistrer en semaine 2 (plan §11 jour 8), depuis le compte TEST de la cohorte, corps JSON anonymisé, sans jeton ni identifiant de compte réel.

## fn_mon_profil_soignant_complet

- **Statut natif** : à venir (**lot 3**, reclassée par le blueprint du lot 1, correction v2 n°4).
- **Usage prévu** : Profil complet du soignant connecté (onglet Profil, lot 3). Le soft-gate de candidature
  `peut_candidater` du lot 1 n'en dépend pas : il lit `prenom, nom, date_naissance, telephone, rpps_verifie,
  profession` par SELECT direct sur `soignants` (`pol_soig_select`, `profileSelect` étendu, `LOT1_PLAN.md`
  §2.6). Cette RPC renvoie `numero_secu`, `siret_liberal`, `iban_last4`, `stripe_account_id`, `email` :
  aucune de ces clés n'est décodée ni journalisée avant le lot 3.
- **Signature SQL** (`supabase/schema/public.sql` l.44659) :

```sql
CREATE OR REPLACE FUNCTION "public"."fn_mon_profil_soignant_complet"() RETURNS "jsonb"
    LANGUAGE "plpgsql" SECURITY DEFINER
    SET "search_path" TO 'public'
```

- **Classe d'authentification (manifeste)** : `RPC_UTILISATEUR_AUTH_INTERNE` pour `fn_mon_profil_soignant_complet()` — RPC utilisateur : identité `auth.uid()` lue en interne, appel avec le JWT du soignant.
- **GRANT connu** : `REVOKE ALL … FROM PUBLIC` puis `GRANT ALL … TO "authenticated", "service_role"`.
- **Signature TypeScript** (`types.ts`, section `Functions`) : `Args: never` ; `Returns: Json`.
- **Exemple de réponse STAGING** : à enregistrer en semaine 2 (plan §11 jour 8), depuis le compte TEST de la cohorte, corps JSON anonymisé, sans jeton ni identifiant de compte réel.

## fn_dashboard_soignant_complet

- **Statut natif** : consommée (lot 1, T3) par `JoleneSupabase/Dashboard/SupabaseDashboardGateway.swift`
  (`DashboardPort`), modèle `JoleneCore/Accueil/AccueilModel.swift` borné à `resolutionTimeout` (15 s).
- **Usage** : onglet Accueil, valeurs serveur affichées telles quelles. Appel sans paramètre, JWT du soignant.
  Décodage tolérant (`JoleneCore/Models/Dashboard.swift`, `DashboardCorps`) : section NULL, absente ou qui
  n'est pas un tableau → vide ; ligne sans `id` (ou sans `intitule`) écartée seule ; corps qui n'est pas un
  objet → `.contract`. Clés lues : `profil.{prenom, profession, tous_documents_valides, type_exercice}`
  (état civil, téléphone et numéros RPPS/ADELI du corps jamais décodés ; jamais un contrôle d'accès),
  `mes_missions`, `missions_ouvertes`, `propositions` (+ `missions` jointe), `documents` (décodés, non
  affichés au lot 1), `heures_semaine` (décodé, non affiché : `BandeauAlerte48h` exclu, HARD STOP n°4),
  `gains_mois.nb_missions`, `missions_oubliees_count`, `notifs_non_lues`. `gains_mois.net_total` et
  `brut_total` ne sont **jamais** décodés (décision 10).
- **Formes de réponse** (HTTP 200) : `{"error": "Non authentifié"}` (l.27934) → `JoleneError(.unauthorized)`
  par `RPCResponse.leverSiErreur`, aucune lecture qui dépend de la RPC (la relecture des gains, partie en
  parallèle, est annulée et ignorée) ; tout autre `{error}` → `.unknown`, message verbatim ; `PGRST202` /
  300-303 → `.contract` sans renvoi ; succès = l'objet `jsonb_build_object` ci-dessus.
  Un test par forme : `SupabaseDashboardGatewayTests`, `DashboardDecodingTests`.
- **Lectures complémentaires** (rendu partiel sans erreur d'écran, comme le web l.104-215) : gains du mois
  relus comme le web (`missions?select=id,type_contrat_applique,type_contrat_recherche,total_brut,net_a_payer,net_estime&soignant_assigne_id=eq.<uid>&statut=eq.TERMINEE&fin_le=gte.<début du mois, Paris>`,
  sommés par nature selon `montantFinanceAfficheMission`, sans recalcul ; en échec : carte masquée), lancés
  **en parallèle de la RPC** comme le `Promise.all` du web ; puis, en parallèle après la RPC : fiches
  `missions` (`MissionQuery.missionSelect`, `id=in.(…)` : `nb_creneaux` pour `CompletudePlanning`) et créneaux
  PREVISIONNEL hors pause par `MissionSlotPager` (en échec : planning « Planning détaillé à confirmer ») ;
  noms par `fn_etablissements_safe` (en échec ou ligne absente : `etab_nom`, puis « Établissement »).
  Chaque lecture a un **sous-budget** (`SupabaseDashboardGateway.sousBudgetLecture`, 5 s), réduit à ce qu'il
  reste du délai de l'écran (15 s, marge 0,5 s) : au dépassement elle vaut « indisponible », si bien qu'une
  lecture lente (pager multi-pages, rejeu SDK d'un GET d'environ 7 s, CPU partagé) ne jette jamais une RPC
  réussie. Repli seulement sur une erreur de transport, de serveur ou de contrat (journalisée en DEBUG :
  nom de la lecture et catégorie, sans URL ni valeur) ; une session expirée (401 / `PGRST301` →
  `.unauthorized`) et l'annulation sont **propagées** : l'écran propose « Vérifier ma session », jamais un
  tableau partiel.
- **Écarts assumés avec le web** (aussi dans `PARITE_SOIGNANT.md`) : une fiche mission non relue (RLS,
  mission retirée) ne rend « à confirmer » que **sa** mission, quand le web met tout le planning « à
  confirmer » dès que `metas.length !== missionIds.length` (`DashboardSoignant.tsx` l.160-162) — les autres
  missions restent vérifiées par leur propre `nb_creneaux` et par le pager (compte exact) ; la carte des
  gains est masquée quand aucun montant relu n'est positif (le web afficherait « 💰 Ce mois :  sur N
  missions »). « sur N missions » compte les missions relues porteuses d'un montant (`gainsCeMois.nb` du
  web), jamais `gains_mois.nb_missions`, décodé mais non affiché (lecture de la décision 10 proposée à Gabrielle, `LOT1_PLAN.md` §7, en attente de son accord).
- **Signature SQL** (`supabase/schema/public.sql` l.27920) :

```sql
CREATE OR REPLACE FUNCTION "public"."fn_dashboard_soignant_complet"() RETURNS "jsonb"
    LANGUAGE "plpgsql" SECURITY DEFINER
    SET "search_path" TO 'public'
```

- **Classe d'authentification (manifeste)** : `RPC_UTILISATEUR_AUTH_INTERNE` pour `fn_dashboard_soignant_complet()` — RPC utilisateur : identité `auth.uid()` lue en interne, appel avec le JWT du soignant.
- **GRANT connu** : `REVOKE ALL … FROM PUBLIC` puis `GRANT ALL … TO "authenticated", "service_role"`.
- **Signature TypeScript** (`types.ts`, section `Functions`) : `Args: never` ; `Returns: Json`.
- **Exemple de réponse STAGING** : à enregistrer en semaine 2 (plan §11 jour 8), depuis le compte TEST de la cohorte, corps JSON anonymisé, sans jeton ni identifiant de compte réel.

## fn_confirmer_action_planning_v1

- **Statut natif** : à venir (lot 1, T6a).
- **Usage prévu** : Candidature (`POSTULER`, mode `CANDIDATURE`), acceptation directe (`ACCEPTER`, mode
  `PREMIER_ARRIVE`) et acceptation d'une proposition (`PROPOSITION`, `p_candidature_id` renseigné), avec
  `p_creneaux_confirmes` strictement égal au planning live (sérialisation ISO 8601 UTC `Z` sans fraction,
  `CreneauxConfirmes`, T2) et relecture après la réponse : `candidatures` (id retourné) pour POSTULER,
  `mission(id:)` (`ASSIGNEE`, `soignant_assigne_id == userId`) pour ACCEPTER/PROPOSITION. L'annulation
  **ne passe pas** par cette RPC (voir `fn_annuler_candidature_soignant` / `fn_annuler_mission_soignant`).
- **Formes de réponse** (HTTP 200) à décoder par `RPCResponse`, une forme = un test dans T6a. Valeurs JSON
  réelles (apostrophes simples, pas l'échappement `''` du littéral SQL), relues dans le corps l.24141-24318.
  - **Refus propres à cette RPC** : toujours `success:false, ok:false, error` ; les refus de planning portent
    en plus la clé `code` (jamais `error_code` : ni ce corps ni `fn_conflit_planning_soignant` ne la posent, le
    décodeur lit `code` et ne se rabat pas sur `error_code`).
    1. `{success:false, ok:false, error:'Accès réservé aux soignants authentifiés.'}` — l.24153-24157 :
       `auth.uid()` nul ou `est_soignant()` faux.
    2. `{success:false, ok:false, error:'Action de candidature invalide.'}` — l.24162-24168 : `p_action` hors
       `POSTULER, ACCEPTER, SWIPE_LIKE, URGENCE, PROPOSITION`.
    3. `{success:false, ok:false, error:"Cette mission n'est plus disponible."}` — l.24177-24181 : mission absente
       ou statut ≠ `OUVERTE`.
    4. `{success:false, ok:false, code:'PLANNING_A_RECONFIRMER', error:"Le planning confirmé n'est pas exploitable. Rechargez la mission avant de continuer."}`
       — l.24195-24200 : `fn_valider_creneaux_mission_json` refuse `p_creneaux_confirmes` → relire la mission et
       reconstruire `CreneauxConfirmes`, jamais renvoyer la même charge.
    5. `{success:false, ok:false, code:'PLANNING_MODIFIE_RECONFIRMER', error:'Le planning a changé depuis son affichage. Vérifiez à nouveau toutes les dates et tous les horaires.'}`
       — l.24237-24248 : nombre ou contenu des créneaux différent du planning live → relire et redemander,
       jamais renvoyer.
    6. Conflit avec une mission déjà confirmée — l.24256-24264 :
       `{success:false, ok:false, code: COALESCE(v_conflit->>'code', 'CONFLIT_PLANNING'), error: COALESCE(v_conflit->>'message', 'Ce planning entre en conflit avec une mission déjà confirmée.')}`.
       `code` vaut `'PLANNING_DETAILLE_INDISPONIBLE'` (l.24787), `'PLANNING_EXISTANT_INDISPONIBLE'` (l.24828),
       `'REPOS_11H'` (l.24923) ou, sans code dans `fn_conflit_planning_soignant` (chevauchement, l.24859),
       `'CONFLIT_PLANNING'`. Le message vient du serveur (tutoiement « Tu es déjà confirmé(e) sur … » pour le
       chevauchement) et s'affiche verbatim (HARD STOP n°4).
    7. `{success:false, ok:false, error:'Proposition introuvable.'}` — l.24295-24306 : `PROPOSITION` sans
       `p_candidature_id`, ou candidature qui n'est pas `PROPOSEE`, au soignant et pour cette mission.
  - **Réponses des délégués**, renvoyées telles quelles une fois les contrôles passés : `POSTULER` →
    `fn_postuler_mission_rate_limited` (l.48080) → `fn_postuler_mission` (l.47889) ; `ACCEPTER` →
    `fn_accepter_mission` (l.5120) → `fn_finaliser_attribution_mission` (l.36703) ; `PROPOSITION` →
    `fn_repondre_proposition(p_candidature_id, true)` (l.53577) → `fn_finaliser_attribution_mission`. Hors
    succès, **aucune ne porte de clé `success`** : le décodeur les discrimine par clés, dans l'ordre normatif
    du `LOT1_PLAN.md` §2.4 (`choix_requis` → `code` → `documents_requis_pour` avec `error` → `success:true` →
    `error` seul → sinon `.contract`).
    8. Succès POSTULER : `{success:true, candidature_id, choix_contrat, profession_requise, docs_a_completer, documents_requis_pour}`
       — l.48061-48068. `documents_requis_pour` y vaut le contrat retenu (`v_choix`) et `docs_a_completer`
       signale des documents encore à valider : sans `error`, ce n'est **pas** un refus. Relecture `candidatures`.
    9. Succès ACCEPTER : `{success:true, contrat_id, contrat_numero, choix_applique, profession_requise, type_paiement, mode_paiement}`
       — l.36902-36910 ; PROPOSITION : la même réponse + `message:'Proposition acceptée'` (l.53670). Relecture
       `mission(id:)`.
    10. Choix de contrat, sans clé `success` (`v_resolution - 'ok'`, l.47970 et l.36753 ; réponse de
        `fn_resoudre_contrat_mission` l.54551-54565) :
        `{choix_requis:true, error:'Choisissez votre mode de contrat.', options:[{value:'SALARIE', label:'Salarié (CDD / bulletin de paie)'}, {value:'LIBERAL', label:"Libéral (note d'honoraires)"}]}`
        → sheet de choix de contrat, action rejouée avec `p_choix_contrat` (le rate-limit a déjà compté l'appel).
    11. Documents manquants, sans clé `success` → `.refusee(documentsRequisPour:)`, renvoi web vers les
        documents au lot 1 : POSTULER libéral
        `{error:'Les documents requis pour candidater en libéral sont manquants ou expirés.', documents_requis_pour:'LIBERAL', lien_documents:'/soignant/mes-documents'}`
        (l.47991-47996) ; ACCEPTER / PROPOSITION
        `{error:'Les documents requis pour une mission <salarie|liberal> ne sont pas encore validés.', documents_requis_pour:<contrat retenu>, lien_documents:'/soignant/mes-documents'}`
        (l.36758-36763, `lower(v_choix)` dans le message).
    12. Plafond hebdomadaire (ACCEPTER / PROPOSITION), sans clé `success` → `.refusee(code:, message verbatim)`
        (HARD STOP n°4) :
        `{error:'Planning hebdomadaire incomplet : impossible de vérifier le plafond de 48 h.', code:'PLANNING_HEBDOMADAIRE_INDISPONIBLE', creneaux_valides, creneaux_attendus}`
        (l.36788-36793) ;
        `{error:'Dépassement du plafond de 48 h pour la semaine du <JJ/MM/AAAA> (… h déjà planifiées + … h pour cette mission + … h ailleurs).', code:'PLAFOND_48H_HEBDO', semaine_du, heures_existantes, heures_mission, heures_externes, total}`
        (l.36812-36824).
    13. `{error}` seul → `JoleneError` (`.unauthorized` pour « Non authentifié », sinon `.unknown`, message
        verbatim) : rate-limit `{error:'Trop de candidatures en peu de temps. Réessayez plus tard.'}` renvoyé en
        **HTTP 200**, pas en 429 (l.48092 ; 20 candidatures/h, consommé même en `choix_requis`) ;
        `'Vous avez déjà postulé à cette mission'` (l.47982) ; profession incompatible ; exclusion
        (`'Accès refusé.'`, `'Accès refusé pour cette mission.'`) ; `"Cette mission n'est plus disponible"` et
        `'Cette mission nécessite une candidature'` (`fn_accepter_mission`) ; `"Cette mission vient d'être attribuée."`
        (l.36851) ; refus de `fn_resoudre_contrat_mission` hors `choix_requis` ; refus de `fn_repondre_proposition`
        (`'Cette proposition a expiré'`, `'Cette proposition n’est plus en attente'`, …).
    14. Exceptions PostgREST, lues sur `PostgrestError.message` **avant** `SupabaseErrorMapping.map` (qui ne
        garde pas le message) : `[CODE DU TRAVAIL] …` (triggers `dec_verifier_plafond_48h`, `dec_verifier_repos_11h`,
        `dec_verifier_moyenne_44h_12_semaines`, `dec_verifier_repos_hebdo_35h`, levés par l'`UPDATE missions` de
        `fn_finaliser_attribution_mission`) → `.refusee(code: 'CODE_DU_TRAVAIL', message verbatim)` (HARD STOP n°4 :
        aucun texte juridique reformulé ni avalé) ; `0 rows` / `déjà prise` → issue « mission déjà attribuée »
        avec relecture, sans message technique (modale « mission perdue » du web, l.804-810) ; toute autre
        exception → `SupabaseErrorMapping`.
- **Classement manuel (décision 6, `LOT1_PLAN.md` §7)** : `RPC_UTILISATEUR_AUTH_INTERNE` — SECURITY DEFINER,
  `search_path` vide, GRANT `authenticated`, identité lue via `auth.uid()` dans le corps (l.24141-24318 du dump) ;
  manifeste non régénéré, `rpc-contracts.json` garde `manifeste: null`.
- **Signature SQL** (`supabase/schema/public.sql` l.24141) :

```sql
CREATE OR REPLACE FUNCTION "public"."fn_confirmer_action_planning_v1"("p_mission_id" "uuid", "p_action" "text", "p_creneaux_confirmes" "jsonb", "p_message" "text" DEFAULT NULL::"text", "p_choix_contrat" "text" DEFAULT NULL::"text", "p_candidature_id" "uuid" DEFAULT NULL::"uuid") RETURNS "jsonb"
    LANGUAGE "plpgsql" SECURITY DEFINER
    SET "search_path" TO ''
```

- **Classe d'authentification (manifeste)** : **hors manifeste** — classée manuellement `RPC_UTILISATEUR_AUTH_INTERNE` (décision 6).
- **GRANT connu** : `REVOKE ALL … FROM PUBLIC` puis `GRANT ALL … TO "authenticated", "service_role"`.
- **Signature TypeScript** (`types.ts`, section `Functions`) : absente (types.ts en retard sur le schéma).
- **Exemple de réponse STAGING** : à enregistrer en semaine 2 (plan §11 jour 8), depuis le compte TEST de la cohorte, corps JSON anonymisé, sans jeton ni identifiant de compte réel.

## fn_suggestions_missions_pour_soignant

- **Statut natif** : à venir (lot 4) — reclassée par la revue B8 de T3 (02/11/2026), qui ne la consomme pas.
- **Motif du reclassement** : le composant web `src/components/dashboard/SuggestionsMissions.tsx` (seul
  appelant, `p_limit: 3`) n'est monté par **aucune** page, `DashboardSoignant` compris : la parité de
  l'Accueil ne l'exige pas, et « Missions pour vous » vient de `missions_ouvertes` de
  `fn_dashboard_soignant_complet`. Elle suit le matching du lot 4 (swipe, scoring) ; si le web ne la monte
  toujours pas à la clôture du lot 4, elle sort de `RPC_SUIVIES` (décision consignée dans la PR).
- **Usage prévu** : suggestions de missions, scoring serveur, jamais recalculé côté client.
- **Signature SQL** (`supabase/schema/public.sql` l.59643) :

```sql
CREATE OR REPLACE FUNCTION "public"."fn_suggestions_missions_pour_soignant"("p_limit" integer DEFAULT 5) RETURNS "jsonb"
    LANGUAGE "plpgsql" STABLE SECURITY DEFINER
    SET "search_path" TO 'public', 'extensions'
```

- **Classe d'authentification (manifeste)** : `RPC_UTILISATEUR_AUTH_INTERNE` pour `fn_suggestions_missions_pour_soignant(integer)` — RPC utilisateur : identité `auth.uid()` lue en interne, appel avec le JWT du soignant.
- **GRANT connu** : `REVOKE ALL … FROM PUBLIC` puis `GRANT ALL … TO "authenticated", "service_role"`.
- **Signature TypeScript** (`types.ts`, section `Functions`) : `Args: { p_limit?: number }` ; `Returns: Json`.
- **Exemple de réponse STAGING** : à enregistrer en semaine 2 (plan §11 jour 8), depuis le compte TEST de la cohorte, corps JSON anonymisé, sans jeton ni identifiant de compte réel.

## fn_pointer_arrivee

- **Statut natif** : à venir (lot 2).
- **Usage prévu** : Pointage d'arrivée (GPS, terminal, code de secours) ; reçu durable écrit avant l'appel.
- **Signature SQL** (`supabase/schema/public.sql` l.47421) :

```sql
CREATE OR REPLACE FUNCTION "public"."fn_pointer_arrivee"("p_mission_id" "uuid", "p_lat" numeric DEFAULT NULL::numeric, "p_lng" numeric DEFAULT NULL::numeric, "p_precision" numeric DEFAULT NULL::numeric, "p_terminal_id" "text" DEFAULT NULL::"text", "p_modele" "text" DEFAULT NULL::"text", "p_code_arrivee" "text" DEFAULT NULL::"text") RETURNS "jsonb"
    LANGUAGE "plpgsql" SECURITY DEFINER
    SET "search_path" TO 'public'
```

- **Classe d'authentification (manifeste)** : `RPC_UTILISATEUR_AUTH_INTERNE` pour `fn_pointer_arrivee(uuid,numeric,numeric,numeric,text,text,text)` — RPC utilisateur : identité `auth.uid()` lue en interne, appel avec le JWT du soignant.
- **GRANT connu** : `REVOKE ALL … FROM PUBLIC` puis `GRANT ALL … TO "authenticated", "service_role"`.
- **Signature TypeScript** (`types.ts`, section `Functions`) : `Args: { p_code_arrivee?: string; p_lat?: number; p_lng?: number; p_mission_id: string; p_modele?: string; p_precision?: number; p_terminal_id?: string }` ; `Returns: Json`.
- **Exemple de réponse STAGING** : à enregistrer en semaine 2 (plan §11 jour 8), depuis le compte TEST de la cohorte, corps JSON anonymisé, sans jeton ni identifiant de compte réel.

## fn_pointer_depart

- **Statut natif** : à venir (lot 2).
- **Usage prévu** : Pointage de départ sur une présence ouverte ; reçu durable écrit avant l'appel.
- **Signature SQL** (`supabase/schema/public.sql` l.47563) :

```sql
CREATE OR REPLACE FUNCTION "public"."fn_pointer_depart"("p_presence_id" "uuid", "p_lat" numeric DEFAULT NULL::numeric, "p_lng" numeric DEFAULT NULL::numeric, "p_precision" numeric DEFAULT NULL::numeric, "p_terminal_id" "text" DEFAULT NULL::"text", "p_modele" "text" DEFAULT NULL::"text", "p_code_depart" "text" DEFAULT NULL::"text") RETURNS "jsonb"
    LANGUAGE "plpgsql" SECURITY DEFINER
    SET "search_path" TO 'public'
```

- **Classe d'authentification (manifeste)** : `RPC_UTILISATEUR_AUTH_INTERNE` pour `fn_pointer_depart(uuid,numeric,numeric,numeric,text,text,text)` — RPC utilisateur : identité `auth.uid()` lue en interne, appel avec le JWT du soignant.
- **GRANT connu** : `REVOKE ALL … FROM PUBLIC` puis `GRANT ALL … TO "authenticated", "service_role"`.
- **Signature TypeScript** (`types.ts`, section `Functions`) : `Args: { p_code_depart?: string; p_lat?: number; p_lng?: number; p_modele?: string; p_precision?: number; p_presence_id: string; p_terminal_id?: string }` ; `Returns: Json`.
- **Exemple de réponse STAGING** : à enregistrer en semaine 2 (plan §11 jour 8), depuis le compte TEST de la cohorte, corps JSON anonymisé, sans jeton ni identifiant de compte réel.

## fn_scanner_code_pointage

- **Statut natif** : à venir (lot 2).
- **Usage prévu** : Code rotatif affiché par l'établissement ; `p_metadata` porte terminal et précision GPS.
- **Signature SQL** (`supabase/schema/public.sql` l.55622) :

```sql
CREATE OR REPLACE FUNCTION "public"."fn_scanner_code_pointage"("p_code" "text", "p_metadata" "jsonb" DEFAULT NULL::"jsonb") RETURNS "jsonb"
    LANGUAGE "plpgsql" SECURITY DEFINER
    SET "search_path" TO 'public'
```

- **Classe d'authentification (manifeste)** : `RPC_UTILISATEUR_AUTH_INTERNE` pour `fn_scanner_code_pointage(text,jsonb)` — RPC utilisateur : identité `auth.uid()` lue en interne, appel avec le JWT du soignant.
- **GRANT connu** : `REVOKE ALL … FROM PUBLIC` puis `GRANT ALL … TO "authenticated", "service_role"`.
- **Signature TypeScript** (`types.ts`, section `Functions`) : `Args: { p_code: string; p_metadata?: Json }` ; `Returns: Json`.
- **Exemple de réponse STAGING** : à enregistrer en semaine 2 (plan §11 jour 8), depuis le compte TEST de la cohorte, corps JSON anonymisé, sans jeton ni identifiant de compte réel.

## fn_valider_scan_qr

- **Statut natif** : à venir (lot 2).
- **Usage prévu** : QR généré par `fn_generer_qr_mission` ; file hors-ligne à sémantique identique à `src/lib/qr-offline-queue.ts`.
- **Signature SQL** (`supabase/schema/public.sql` l.65545) :

```sql
CREATE OR REPLACE FUNCTION "public"."fn_valider_scan_qr"("p_token" "text", "p_lat" numeric DEFAULT NULL::numeric, "p_lng" numeric DEFAULT NULL::numeric, "p_precision" numeric DEFAULT NULL::numeric, "p_terminal_id" "text" DEFAULT NULL::"text") RETURNS "jsonb"
    LANGUAGE "plpgsql" SECURITY DEFINER
    SET "search_path" TO 'public'
```

- **Classe d'authentification (manifeste)** : `RPC_UTILISATEUR_AUTH_INTERNE` pour `fn_valider_scan_qr(text,numeric,numeric,numeric,text)` — RPC utilisateur : identité `auth.uid()` lue en interne, appel avec le JWT du soignant.
- **GRANT connu** : `REVOKE ALL … FROM PUBLIC` puis `GRANT ALL … TO "authenticated", "service_role"`.
- **Signature TypeScript** (`types.ts`, section `Functions`) : `Args: { p_lat?: number; p_lng?: number; p_precision?: number; p_terminal_id?: string; p_token: string }` ; `Returns: Json`.
- **Exemple de réponse STAGING** : à enregistrer en semaine 2 (plan §11 jour 8), depuis le compte TEST de la cohorte, corps JSON anonymisé, sans jeton ni identifiant de compte réel.

## fn_generer_qr_mission

- **Statut natif** : à venir (lot 2).
- **Usage prévu** : Génération du QR côté établissement (lot 5) ; listée ici car le soignant en consomme le token.
- **Signature SQL** (`supabase/schema/public.sql` l.37981) :

```sql
CREATE OR REPLACE FUNCTION "public"."fn_generer_qr_mission"("p_mission_id" "uuid", "p_type" "text" DEFAULT 'UNIVERSEL'::"text") RETURNS "jsonb"
    LANGUAGE "plpgsql" SECURITY DEFINER
    SET "search_path" TO 'public'
```

- **Classe d'authentification (manifeste)** : `MIXTE_TENANT_ADMIN` pour `fn_generer_qr_mission(uuid,text)` — Mixte tenant / admin : la fonction distingue en interne soignant, établissement et admin ; appel avec le JWT utilisateur.
- **GRANT connu** : `REVOKE ALL … FROM PUBLIC` puis `GRANT ALL … TO "authenticated", "service_role"`.
- **Signature TypeScript** (`types.ts`, section `Functions`) : `Args: { p_mission_id: string; p_type?: string }` ; `Returns: Json`.
- **Exemple de réponse STAGING** : à enregistrer en semaine 2 (plan §11 jour 8), depuis le compte TEST de la cohorte, corps JSON anonymisé, sans jeton ni identifiant de compte réel.

## fn_etat_pointage_mission

- **Statut natif** : à venir (lot 2).
- **Usage prévu** : Relecture de l'état de pointage après chaque mutation (règle « aucun succès fabriqué »).
- **Signature SQL** (`supabase/schema/public.sql` l.35145) :

```sql
CREATE OR REPLACE FUNCTION "public"."fn_etat_pointage_mission"("p_mission_id" "uuid") RETURNS "jsonb"
    LANGUAGE "plpgsql" STABLE SECURITY DEFINER
    SET "search_path" TO 'public'
```

- **Classe d'authentification (manifeste)** : `MIXTE_TENANT_ADMIN` pour `fn_etat_pointage_mission(uuid)` — Mixte tenant / admin : la fonction distingue en interne soignant, établissement et admin ; appel avec le JWT utilisateur.
- **GRANT connu** : `REVOKE ALL … FROM PUBLIC` puis `GRANT ALL … TO "authenticated", "service_role"`.
- **Signature TypeScript** (`types.ts`, section `Functions`) : absente (types.ts en retard sur le schéma).
- **Exemple de réponse STAGING** : à enregistrer en semaine 2 (plan §11 jour 8), depuis le compte TEST de la cohorte, corps JSON anonymisé, sans jeton ni identifiant de compte réel.

## fn_envoyer_otp_signature

- **Statut natif** : à venir (lot 2).
- **Usage prévu** : Envoi du code OTP SMS avant signature de contrat.
- **Signature SQL** (`supabase/schema/public.sql` l.33098) :

```sql
CREATE OR REPLACE FUNCTION "public"."fn_envoyer_otp_signature"("p_contrat_id" "uuid") RETURNS "jsonb"
    LANGUAGE "plpgsql" SECURITY DEFINER
    SET "search_path" TO 'public', 'extensions'
```

- **Classe d'authentification (manifeste)** : `RPC_UTILISATEUR_AUTH_INTERNE` pour `fn_envoyer_otp_signature(uuid)` — RPC utilisateur : identité `auth.uid()` lue en interne, appel avec le JWT du soignant.
- **GRANT connu** : `REVOKE ALL … FROM PUBLIC` puis `GRANT ALL … TO "authenticated", "service_role"`.
- **Signature TypeScript** (`types.ts`, section `Functions`) : `Args: { p_contrat_id: string }` ; `Returns: Json`.
- **Exemple de réponse STAGING** : à enregistrer en semaine 2 (plan §11 jour 8), depuis le compte TEST de la cohorte, corps JSON anonymisé, sans jeton ni identifiant de compte réel.

## fn_signer_contrat_otp

- **Statut natif** : à venir (lot 2).
- **Usage prévu** : Signature du contrat avec le code OTP et le hash du document affiché.
- **Signature SQL** (`supabase/schema/public.sql` l.56473) :

```sql
CREATE OR REPLACE FUNCTION "public"."fn_signer_contrat_otp"("p_contrat_id" "uuid", "p_otp_code" "text", "p_hash_document" "text" DEFAULT NULL::"text", "p_signature_image" "text" DEFAULT NULL::"text") RETURNS "jsonb"
    LANGUAGE "plpgsql" SECURITY DEFINER
    SET "search_path" TO 'public', 'extensions'
```

- **Classe d'authentification (manifeste)** : `RPC_UTILISATEUR_AUTH_INTERNE` pour `fn_signer_contrat_otp(uuid,text,text,text)` — RPC utilisateur : identité `auth.uid()` lue en interne, appel avec le JWT du soignant.
- **GRANT connu** : `REVOKE ALL … FROM PUBLIC` puis `GRANT ALL … TO "authenticated", "service_role"`.
- **Signature TypeScript** (`types.ts`, section `Functions`) : `Args: { p_contrat_id: string; p_hash_document?: string; p_otp_code: string; p_signature_image?: string }` ; `Returns: Json`.
- **Exemple de réponse STAGING** : à enregistrer en semaine 2 (plan §11 jour 8), depuis le compte TEST de la cohorte, corps JSON anonymisé, sans jeton ni identifiant de compte réel.

## fn_remplacer_document_soignant

- **Statut natif** : à venir (lot 2).
- **Usage prévu** : Enregistrement d'un document après upload Storage sous `auth.uid()/` ; déclenche `verify-document` une seule fois.
- **Signature SQL** (`supabase/schema/public.sql` l.53079) :

```sql
CREATE OR REPLACE FUNCTION "public"."fn_remplacer_document_soignant"("p_type_document" "text", "p_libelle" "text", "p_s3_cle" "text", "p_nom_fichier" "text", "p_type_mime" "text", "p_taille_octets" bigint) RETURNS "jsonb"
    LANGUAGE "plpgsql" SECURITY DEFINER
    SET "search_path" TO 'pg_catalog', 'public'
```

- **Classe d'authentification (manifeste)** : `RPC_UTILISATEUR_AUTH_INTERNE` pour `fn_remplacer_document_soignant(text,text,text,text,text,bigint)` — RPC utilisateur : identité `auth.uid()` lue en interne, appel avec le JWT du soignant.
- **GRANT connu** : `REVOKE ALL … FROM PUBLIC` puis `GRANT ALL … TO "authenticated", "service_role"`.
- **Signature TypeScript** (`types.ts`, section `Functions`) : absente (types.ts en retard sur le schéma).
- **Exemple de réponse STAGING** : à enregistrer en semaine 2 (plan §11 jour 8), depuis le compte TEST de la cohorte, corps JSON anonymisé, sans jeton ni identifiant de compte réel.

## fn_upsert_token_push

- **Statut natif** : à venir (lot 3).
- **Usage prévu** : Enregistrement du token APNs (`p_plateforme = IOS`) à chaque session et au retour au premier plan.
- **Signature SQL** (`supabase/schema/public.sql` l.64628) :

```sql
CREATE OR REPLACE FUNCTION "public"."fn_upsert_token_push"("p_token" "text", "p_plateforme" "text" DEFAULT 'WEB'::"text") RETURNS "void"
    LANGUAGE "plpgsql" SECURITY DEFINER
    SET "search_path" TO 'pg_catalog', 'public'
```

- **Classe d'authentification (manifeste)** : `RPC_UTILISATEUR_AUTH_INTERNE` pour `fn_upsert_token_push(text,text)` — RPC utilisateur : identité `auth.uid()` lue en interne, appel avec le JWT du soignant.
- **GRANT connu** : `REVOKE ALL … FROM PUBLIC` puis `GRANT ALL … TO "authenticated", "service_role"`.
- **Signature TypeScript** (`types.ts`, section `Functions`) : `Args: { p_plateforme?: string; p_token: string }` ; `Returns: undefined`.
- **Exemple de réponse STAGING** : à enregistrer en semaine 2 (plan §11 jour 8), depuis le compte TEST de la cohorte, corps JSON anonymisé, sans jeton ni identifiant de compte réel.

## fn_annuler_candidature_soignant

- **Statut natif** : à venir (lot 1, T7).
- **Usage prévu** : Annulation d'une candidature `ACCEPTEE` ou `EN_ATTENTE` avec motif, texte libre et
  justificatif optionnel (bucket Storage `justificatifs`, chemin `<uid>/annulations-candidature/<candidatureId>/<ts>_<nom>`,
  précédé d'un reçu Keychain `prepared → started → …`, PRINCIPES §4). Relecture : candidature (`ANNULEE`)
  puis mission. Web : `src/components/soignant/ModaleAnnulationCandidature.tsx`.
- **Signature SQL** (`supabase/schema/public.sql` l.17541) :

```sql
CREATE OR REPLACE FUNCTION "public"."fn_annuler_candidature_soignant"("p_candidature_id" "uuid", "p_motif_categorie" "text", "p_texte_libre" "text", "p_justificatif_storage_path" "text" DEFAULT NULL::"text") RETURNS "jsonb"
    LANGUAGE "plpgsql" SECURITY DEFINER
    SET "search_path" TO 'public'
```

- **Classe d'authentification (manifeste)** : `RPC_UTILISATEUR_AUTH_INTERNE` pour `fn_annuler_candidature_soignant(uuid,text,text,text)` — identité `auth.uid()` lue en interne, appel avec le JWT du soignant.
- **GRANT connu** : `REVOKE ALL … FROM PUBLIC` puis `GRANT ALL … TO "authenticated", "service_role"`.
- **Signature TypeScript** (`types.ts`, section `Functions`) : `Args: { p_candidature_id: string; p_justificatif_storage_path?: string; p_motif_categorie: string; p_texte_libre: string }` ; `Returns: Json`.
- **Contrat de réponse (HTTP 200)** : motifs admis `URGENCE_PERSONNELLE`, `URGENCE_MEDICALE`, `DEUIL`,
  `PROBLEME_TRANSPORT`, `CHANGEMENT_AVIS`, `AUTRE` (sinon `{success:false, error_code:'MOTIF_INVALIDE'}`) ;
  texte ≥ 10 caractères côté serveur (`TEXTE_REQUIS`), **≥ 20 côté app** (parité web, décision 4) ;
  `NON_AUTHENTIFIE`, `CANDIDATURE_INTROUVABLE`, `NON_AUTORISE`, `STATUT_INVALIDE`, `MISSION_INTROUVABLE`.
  Succès `EN_ATTENTE` → `{success:true, libre:true, points:0, message}` ; succès `ACCEPTEE` →
  `{success:true, points, libre, contestable?, …}` calculés par `fn_calculer_penalite_annulation_soignant(acceptee_a, debut_le, est_asap)`.
  **Aucun barème côté client** : `points`/`libre`/`contestable` sont affichés tels quels (écart web/serveur
  -25/-15/-8 vs -8 et `est_urgente` vs `est_asap` consigné hors lot, décision 4). Wording pénalité/rétractation
  verbatim web ou validation Gabrielle (HARD STOP n°4).
- **Exemple de réponse STAGING** : à enregistrer en T11, depuis le compte de la cohorte D3, corps JSON anonymisé.

## fn_annuler_mission_soignant

- **Statut natif** : à venir (lot 1, T7).
- **Usage prévu** : Annulation d'une mission `ASSIGNEE` au soignant **sans ligne `candidatures`** (attribution
  directe) ; motif texte optionnel. Relecture `mission(id:)` (statut `OUVERTE`, `soignant_assigne_id` nul).
  Web : `DetailMissionSoignant.tsx` l.890-918 (suivi d'un `fn_ecrire_audit_safe` `MISSION_ANNULATION`
  côté client ; la RPC écrit déjà `MISSION_ANNULEE_PAR_SOIGNANT` — l'app reproduit l'appel client pour la parité).
- **Signature SQL** (`supabase/schema/public.sql` l.18355) :

```sql
CREATE OR REPLACE FUNCTION "public"."fn_annuler_mission_soignant"("p_mission_id" "uuid", "p_motif" "text" DEFAULT NULL::"text") RETURNS "jsonb"
    LANGUAGE "plpgsql" SECURITY DEFINER
    SET "search_path" TO 'public'
```

- **Classe d'authentification (manifeste)** : `RPC_UTILISATEUR_AUTH_INTERNE` pour `fn_annuler_mission_soignant(uuid,text)`.
- **GRANT connu** : `REVOKE ALL … FROM PUBLIC` puis `GRANT ALL … TO "authenticated", "service_role"`.
- **Signature TypeScript** : `Args: { p_mission_id: string; p_motif?: string }` ; `Returns: Json`.
- **Contrat de réponse (HTTP 200)** : `{error:'Mission introuvable'}`, `{error:'Cette mission ne vous est pas assignée'}`,
  `{error:'Annulation impossible dans cet état. Si la mission est en cours, ouvrez un litige.'}` (statut ≠ `ASSIGNEE`) ;
  succès `{success:true, annulation_tardive:boolean, penalite_score: -8 | 0}` (tardive = `debut_le - now() < 24 h`).
  Effets serveur : mission remise `OUVERTE`, notification étab `SYSTEM`, audit `MISSION_ANNULEE_PAR_SOIGNANT`,
  recalcul score si `est_urgente`. Messages `{error}` affichés verbatim.
- **Exemple de réponse STAGING** : à enregistrer en T11, corps JSON anonymisé.

## fn_repondre_proposition

- **Statut natif** : à venir (lot 1, T6a — **refus uniquement**).
- **Usage prévu** : Refus d'une proposition `PROPOSEE` depuis l'Accueil (`p_accepter = false`). L'acceptation
  passe par `fn_confirmer_action_planning_v1` (`PROPOSITION`, comme le web `CarteProposition.tsx` l.268-279) ;
  `p_accepter = true` n'est pas appelé par l'app au lot 1. Relecture : candidature (`REFUSEE`).
- **Signature SQL** (`supabase/schema/public.sql` l.53577) :

```sql
CREATE OR REPLACE FUNCTION "public"."fn_repondre_proposition"("p_candidature_id" "uuid", "p_accepter" boolean) RETURNS "jsonb"
    LANGUAGE "plpgsql" SECURITY DEFINER
    SET "search_path" TO 'public'
```

- **Classe d'authentification (manifeste)** : `RPC_UTILISATEUR_AUTH_INTERNE` pour `fn_repondre_proposition(uuid,boolean)` ; exige `candidatures.soignant_id = auth.uid()`.
- **GRANT connu** : `REVOKE ALL … FROM PUBLIC` puis `GRANT ALL … TO "authenticated", "service_role"`.
- **Signature TypeScript** : `Args: { p_accepter: boolean; p_candidature_id: string }` ; `Returns: Json`.
- **Contrat de réponse (HTTP 200)** : `{error:'Candidature introuvable'}`, `{error:'Accès refusé'}`,
  `{error:'Cette proposition n’est plus en attente'}`, `{error:'Cette proposition a expiré'}` (créée il y a plus de
  2 h : la RPC pose `EXPIREE` elle-même) ; refus → `{success:true, message:'Proposition refusée'}` ;
  acceptation (non utilisée) → résultat de `fn_finaliser_attribution_mission` + `message:'Proposition acceptée'`.
- **Exemple de réponse STAGING** : à enregistrer en T11 (PROPOSEE créée par `fn_proposer_mission_soignant` avec le JWT étab de la fixture D3, moins de 2 h avant).

## fn_toggle_favori_etablissement

- **Statut natif** : à venir (lot 1, T4b — **retrait uniquement**, `p_actif = false`).
- **Usage prévu** : Retrait d'un établissement favori depuis `/soignant/mes-favoris`. L'ajout (`p_actif = true`)
  n'est exposé nulle part sur le web (`BoutonFavoriEtab` non monté) et n'est pas porté (décision 8).
  Relecture : `fn_mes_favoris_etablissements`. Les favoris **mission** passent par PostgREST direct sur
  `missions_sauvegardees` (RLS `soignant_id = auth.uid()`), pas par une RPC.
- **Signature SQL** (`supabase/schema/public.sql` l.61480) :

```sql
CREATE OR REPLACE FUNCTION "public"."fn_toggle_favori_etablissement"("p_etablissement_id" "uuid", "p_actif" boolean) RETURNS "jsonb"
    LANGUAGE "plpgsql" SECURITY DEFINER
    SET "search_path" TO 'public', 'extensions'
```

- **Classe d'authentification (manifeste)** : `RPC_UTILISATEUR_AUTH_INTERNE` pour `fn_toggle_favori_etablissement(uuid,boolean)`.
- **GRANT connu** : `REVOKE ALL … FROM PUBLIC` puis `GRANT ALL … TO "authenticated", "service_role"`.
- **Signature TypeScript** : `Args: { p_actif: boolean; p_etablissement_id: string }` ; `Returns: Json`.
- **Contrat de réponse (HTTP 200)** : `{success:false, error:'Non authentifié'}`, `{success:false, error:'Établissement introuvable'}` ;
  succès `{success:true, actif:boolean}` ; audit serveur `FAVORI_AJOUTE` / `FAVORI_RETIRE` via `fn_ecrire_audit_safe`.
- **Exemple de réponse STAGING** : à enregistrer en T11.

## fn_mes_favoris_etablissements

- **Statut natif** : à venir (lot 1, T4b).
- **Usage prévu** : Liste des établissements favoris (écran Favoris, onglet Établissements) ; lecture seule,
  `STABLE`. Chaque élément porte `nb_missions_ouvertes` (valeur serveur, affichée telle quelle) et un bouton
  « Voir missions ouvertes » → Explorer filtré `etablissementId`.
- **Signature SQL** (`supabase/schema/public.sql` l.41835) :

```sql
CREATE OR REPLACE FUNCTION "public"."fn_mes_favoris_etablissements"() RETURNS "jsonb"
    LANGUAGE "plpgsql" STABLE SECURITY DEFINER
    SET "search_path" TO 'public', 'extensions'
```

- **Classe d'authentification (manifeste)** : `RPC_UTILISATEUR_AUTH_INTERNE` pour `fn_mes_favoris_etablissements()`.
- **GRANT connu** : `REVOKE ALL … FROM PUBLIC` puis `GRANT ALL … TO "authenticated", "service_role"`.
- **Signature TypeScript** : `Args: never` ; `Returns: Json`.
- **Contrat de réponse (HTTP 200)** : `{error:'Non authentifié'}` **ou** un tableau (pas d'objet enveloppe) :
  `[{etablissement_id, nom, ville, logo_url, type_etablissement, nb_missions_ouvertes, cree_le}]` trié par
  `cree_le DESC`, `[]` si aucun favori. Le décodeur doit accepter les deux formes (objet d'erreur / tableau).
  Note : la RPC fait un **JOIN interne** sur `etablissements` (l.41859), sans filtre de cohorte TEST ni de
  `supprime_le` : un favori dont l'établissement n'existe plus est absent du tableau (jamais présent avec
  un `nom` nul). Le nom affiché reste celui de `fn_etablissements_safe` quand la ligne existe (règle « nom
  d'établissement », `LOT1_PLAN.md` §2.6).
- **Exemple de réponse STAGING** : à enregistrer en T11.

## fn_audit_connexion

- **Statut natif** : à venir (lot 1, T1 gateway, T9 câblage ; décision 5).
- **Usage prévu** : `p_action = 'CONNEXION'` après un `signIn` explicite réussi (jamais après une restauration de
  session), `'DECONNEXION'` avant `SessionController.signOut()` — comme `src/contexts/AuthContext.tsx`
  l.186-210. Best-effort, borné, non bloquant : un échec n'empêche ni `.ready` ni la déconnexion.
  IP et User-Agent sont capturés côté serveur depuis `request.headers` ; l'app n'envoie rien d'autre.
- **Signature SQL** (`supabase/schema/public.sql` l.19699) :

```sql
CREATE OR REPLACE FUNCTION "public"."fn_audit_connexion"("p_action" "text") RETURNS "jsonb"
    LANGUAGE "plpgsql" SECURITY DEFINER
    SET "search_path" TO 'public'
```

- **Classe d'authentification (manifeste)** : `RPC_UTILISATEUR_AUTH_INTERNE` pour `fn_audit_connexion(text)`.
- **GRANT connu** : `REVOKE ALL … FROM PUBLIC` puis `GRANT ALL … TO "authenticated", "service_role"`.
- **Signature TypeScript** : `Args: { p_action: string }` ; `Returns: Json`.
- **Contrat de réponse (HTTP 200)** : `{error:'Action non autorisée'}` si `p_action ∉ {CONNEXION, DECONNEXION}` ;
  `{success:true}` ; `{success:false}` quand l'INSERT dans `journaux_audit` échoue (exception avalée : jamais
  une erreur utilisateur, journalisée en DEBUG seulement). Ligne écrite : `type_ressource = 'session'`,
  `details = {horodatage, method:'email_password'}`, `type_acteur = COALESCE(mon_role(), 'SOIGNANT')`.
- **Preuve STAGING** : `journaux_audit` relu avec assertion **relative** (`n_avant + 1`, table immuable) sur
  `action = 'CONNEXION'` pour l'acteur du run (critère lot 1 amendé, `docs/PLAN_APP_NATIVE_SWIFT.md` §5).

## fn_maj_activite_soignant

- **Statut natif** : à venir (lot 1, T1 gateway, T9 câblage ; décision 5).
- **Usage prévu** : `soignants.derniere_activite_le = NOW()` après un `signIn` réussi d'un compte `SOIGNANT`
  (`AuthContext.tsx` l.195-199). Best-effort, borné, non bloquant.
- **Signature SQL** (`supabase/schema/public.sql` l.41026) :

```sql
CREATE OR REPLACE FUNCTION "public"."fn_maj_activite_soignant"() RETURNS "jsonb"
    LANGUAGE "plpgsql" SECURITY DEFINER
    SET "search_path" TO 'public'
```

- **Classe d'authentification (manifeste)** : `RPC_UTILISATEUR_AUTH_INTERNE` pour `fn_maj_activite_soignant()`.
- **GRANT connu** : `REVOKE ALL … FROM PUBLIC` puis `GRANT ALL … TO "authenticated", "service_role"`.
- **Signature TypeScript** : `Args: never` ; `Returns: Json`.
- **Contrat de réponse (HTTP 200)** : toujours `{success:true}` (UPDATE sans garde : 0 ligne touchée pour un
  compte sans profil `soignants`, sans erreur). Aucune relecture.

## fn_ecrire_audit_safe

- **Statut natif** : à venir (lot 1, T1 gateway, T6a câblage ; décision 5).
- **Usage prévu** : `MISSION_ASSIGNATION` après `ACCEPTER` / `PROPOSITION` réussis et relus (parité web
  `DetailMissionSoignant.tsx` l.824-836 : `p_type_ressource = 'mission'`, `p_id_ressource = missionId`,
  `p_details = {intitule, etablissement, debut, fin}`) ; `MISSION_ANNULATION` après `fn_annuler_mission_soignant`
  (l.903-914). **Pas de ligne sur POSTULER** (décision 5). Paramètres app : `p_acteur_id = user.id`,
  `p_type_acteur = 'SOIGNANT'`, `p_cle_s3 = nil`, `p_ip = nil`, `p_navigateur = 'jolene-ios/2.0.0'`.
  `p_id_ressource` **jamais nul** (binding uuid cassé PostgREST, `CLAUDE.md` « audit escrow »).
- **Signature SQL** (`supabase/schema/public.sql` l.31802) :

```sql
CREATE OR REPLACE FUNCTION "public"."fn_ecrire_audit_safe"("p_acteur_id" "uuid", "p_type_acteur" "text", "p_action" "text", "p_type_ressource" "text", "p_id_ressource" "uuid", "p_cle_s3" "text" DEFAULT NULL::"text", "p_details" "jsonb" DEFAULT NULL::"jsonb", "p_ip" "inet" DEFAULT NULL::"inet", "p_navigateur" "text" DEFAULT NULL::"text") RETURNS "jsonb"
    LANGUAGE "plpgsql" SECURITY DEFINER
    SET "search_path" TO 'public'
```

- **Classe d'authentification (manifeste)** : `MIXTE_TENANT_ADMIN` pour `fn_ecrire_audit_safe(uuid,text,text,text,uuid,text,jsonb,inet,text)` — pour un appelant non admin / non service_role, `p_acteur_id` est **écrasé par `auth.uid()`** (anti-impersonation). Sans JWT utilisateur (`auth.uid()` nul), le `RAISE EXCEPTION 'Non authentifié' USING ERRCODE = '28000'` (l.31815) est intercepté par le `EXCEPTION WHEN OTHERS` de la fonction (l.31831-31832) : réponse HTTP 200 `{success:false, error:'Non authentifié'}`, **aucune** erreur PostgREST (voir « Contrat de réponse »).
- **GRANT connu** : `REVOKE ALL … FROM PUBLIC` puis `GRANT ALL … TO "authenticated", "service_role"`.
- **Signature TypeScript** : `Args: { p_acteur_id: string; p_action: string; p_cle_s3?: string; p_details?: Json; p_id_ressource: string; p_ip?: unknown; p_navigateur?: string; p_type_acteur: string; p_type_ressource: string }` ; `Returns: Json`.
- **Contrat de réponse (HTTP 200)** : `{success:true, id}` ou `{success:false, error: SQLERRM}` (toute exception
  avalée : `{success:false, error:'Non authentifié'}` sans JWT utilisateur, et un `p_action` hors
  `journaux_audit_action_check` ou un `p_type_acteur` hors `journaux_audit_type_acteur_check` renvoie
  `success:false` sans erreur PostgREST). `MISSION_ASSIGNATION`,
  `MISSION_ANNULATION`, `SOIGNANT` figurent dans les CHECK du dump (l.70243-70244). Best-effort : jamais une
  erreur utilisateur.
- **Preuve STAGING** : assertion relative `n_avant + 1` sur `action = 'MISSION_ASSIGNATION'` après la
  proposition acceptée de T11.

## fn_supprimer_compte_rate_limited

- **Statut natif** : à venir (lot 1, T8) — **jamais appelée directement par l'app** : elle est invoquée par
  l'edge function `delete-account` avec le JWT utilisateur (fiche « Edge `delete-account` »). Listée sous
  contrat parce que ses réponses `{error}` remontent verbatim dans le 409 de l'edge. L'edge est câblée en T8
  (`SupabaseAccountGateway`) ; la RPC reste `a_venir` dans `RPC_SUIVIES`, le statut `consommee` étant réservé
  aux RPC qu'une gateway Swift appelle elle-même (aucun littéral de cette RPC dans `ios-native/`).
- **Usage prévu** : Anonymisation du profil soignant (`fn_supprimer_mon_compte`), 1 appel / 24 h
  (`fn_verifier_rate_limit(uid, 'supprimer_compte', 1, 86400)`), idempotente si déjà anonymisé.
- **Signature SQL** (`supabase/schema/public.sql` l.59974) :

```sql
CREATE OR REPLACE FUNCTION "public"."fn_supprimer_compte_rate_limited"() RETURNS "jsonb"
    LANGUAGE "plpgsql" SECURITY DEFINER
    SET "search_path" TO ''
```

- **Classe d'authentification (manifeste)** : `RPC_UTILISATEUR_AUTH_INTERNE` pour `fn_supprimer_compte_rate_limited()`.
- **GRANT connu** : `REVOKE ALL … FROM PUBLIC` puis `GRANT ALL … TO "authenticated", "service_role"`.
- **Signature TypeScript** : `Args: never` ; `Returns: Json`.
- **Contrat de réponse (HTTP 200)** : `{error:'Non authentifié'}` ; `{success:true, deja_anonymise:true}` ;
  `{error:'Demande de suppression déjà en cours.'}` (rate-limit) ; sinon le jsonb de `fn_supprimer_mon_compte`
  (`{success:true, …}` ou `{error}`).
- **Preuve STAGING** : `soignants.nom = 'Supprimé'` relu en SQL sur le compte jetable de la fixture D3 (B9
  « données », go explicite de Gabrielle au dispatch de T11, décision 13).

## fn_param_bool

- **Statut natif** : à venir (lot 1, T1 gateway, T9 câblage ; décision 15 et `DECISIONS_LOT0.md` n°9).
- **Usage prévu** : Drapeaux `ios_natif_{accueil,explorer,missions,revenus,profil}_actif` lus **après `.ready`**
  et à la reprise (> 30 min) ; `p_defaut = true` ; toute erreur (réseau, 42501, timeout) → `true`
  (**fail-open**, inversion assumée de la convention web `useParamBool.ts` l.8-9 fail-closed) ; `false` →
  `RenvoiWebScreen` sur l'onglet concerné. Les 5 lignes `parametres_systeme` n'existent dans aucune
  migration : sans la PR backend B0, la RPC renvoie `p_defaut` (kill switch inopérant, documenté dans
  `PORTE_LOT1.md`).
- **Signature SQL** (`supabase/schema/public.sql` l.47037) :

```sql
CREATE OR REPLACE FUNCTION "public"."fn_param_bool"("p_cle" "text", "p_defaut" boolean) RETURNS boolean
    LANGUAGE "sql" STABLE SECURITY DEFINER
    SET "search_path" TO 'public'
```

- **Classe d'authentification (manifeste)** : `RPC_UTILISATEUR_AUTH_INTERNE` pour `fn_param_bool(text,boolean)`.
- **GRANT connu** : `REVOKE ALL … FROM PUBLIC` puis `GRANT ALL … TO "authenticated", "service_role"` — **pas de
  GRANT `anon`** (décision 15) : appel impossible avant session.
- **Signature TypeScript** : absente (types.ts en retard sur le schéma ; le web appelle avec `as any`).
- **Contrat de réponse (HTTP 200)** : un booléen nu (`true`/`false`), jamais un objet : `valeur <> 0` si la clé
  existe, sinon `p_defaut`. Aucun `{error}` possible.

## fn_confirmer_presence_mission

- **Statut natif** : à venir (lot 1, T6c ; décision 16).
- **Usage prévu** : Bloc « Confirme ta présence » d'une mission `ASSIGNEE` au soignant dont le début est à
  moins de 48 h (`PresenceRules.blocDu(mission:, now:)`, seuil 48 h en dur comme le web
  `DetailMissionSoignant.tsx` l.1414-1417, alors que le cron lit `confirmation_j1_max_h` = 36 h : écart
  consigné hors lot). Cible du push `RAPPEL_MISSION` (`/soignant/missions/{id}`, `?relance=1` ignoré).
  Relecture obligatoire `mission(id:)` → `presence_confirmee_le` non nul ; **jamais de date posée localement**.
- **Signature SQL** (`supabase/schema/public.sql` l.24608) :

```sql
CREATE OR REPLACE FUNCTION "public"."fn_confirmer_presence_mission"("p_mission_id" "uuid") RETURNS "jsonb"
    LANGUAGE "plpgsql" SECURITY DEFINER
    SET "search_path" TO 'public'
```

- **Classe d'authentification (manifeste)** : `RPC_UTILISATEUR_AUTH_INTERNE` pour `fn_confirmer_presence_mission(uuid)` ; filtre `soignant_assigne_id = auth.uid()` dans le SELECT.
- **GRANT connu** : `REVOKE ALL … FROM PUBLIC` puis `GRANT ALL … TO "authenticated", "service_role"`.
- **Signature TypeScript** : `Args: { p_mission_id: string }` ; `Returns: Json`.
- **Contrat de réponse (HTTP 200)** : `{error:'Mission introuvable'}` (inexistante ou non assignée au
  soignant) ; `{error:"Cette mission n'est plus active."}` (statut ∉ `ASSIGNEE, EN_COURS`) ; `{success:true}`.
  Valeurs JSON réelles, à copier telles quelles dans les vecteurs Swift : le littéral SQL de la l.24617 double
  l'apostrophe (échappement SQL `''`), ce doublement n'existe pas dans la réponse.
  **Aucune idempotence ni fenêtre serveur** : chaque appel réécrit `presence_confirmee_le = NOW()` et insère
  une notification étab `SYSTEM` « Présence confirmée ✓ » → bouton désactivé pendant l'appel, masqué après
  relecture ; bloc limité à `ASSIGNEE` côté app (la RPC accepte aussi `EN_COURS`).
- **Preuve STAGING** : `missions.presence_confirmee_le` relu + `notifications` étab `SYSTEM` « Présence
  confirmée ✓ » relue (T11).
- **Chaînes d'écran** (reprises à l'identique du web, `DetailMissionSoignant.tsx` l.1419-1438 ; cibles des
  assertions XCUITest et de la recette) : bouton « ✓ Je confirme ma présence » ; confirmation après relecture
  « Présence confirmée — l'établissement est prévenu. ✓ » (toast web) ; état confirmé
  « ✓ Présence confirmée — l'établissement est prévenu » ; refus : `error` serveur verbatim, sinon
  « Confirmation impossible. ». Titre et description du bloc, tutoyés sur le web, passent au vouvoiement
  (décision 9, `LOT1_PLAN.md` §3 T6c).
- **Titre du push** (pas un texte d'écran) : « Ta mission demain — Je serai là ✓ » est le titre du push
  serveur `RAPPEL_MISSION` (`fn_demander_confirmations_presence` l.29924/29934) ; aucune assertion d'écran ne le cherche.

## Edge `delete-account` (suppression de compte, Apple 5.1.1)

- **Statut natif** : câblée (lot 1, T8) — `JoleneSupabase/Compte/SupabaseAccountGateway.swift`
  (`SupabaseAccountGatewayTests` : une réponse ci-dessous = un test), démo `DemoAccountGateway`, écran
  `Jolene/Screens/Compte/SuppressionCompteScreen.swift` (`DemoCompteTests`, 3 formats) ; preuve STAGING en T11.
  Pas une RPC : `supabase/functions/delete-account/index.ts`, appelée par `client.functions.invoke("delete-account")`,
  comme le web `SectionConfidentialite.tsx` l.86 (`supabase.functions.invoke('delete-account', { body: {} })`).
  Vérifié au build de T8 dans supabase-swift 2.55.5 : tout statut hors 2xx lève
  `FunctionsError.httpError(code:data:)` avec le corps intact (lu pour `error` / `error_code`), l'en-tête
  `x-relay-error: true` lève `FunctionsError.relayError` (refus, même sur un 200), et `client.functions` passe
  par `fetchWithAuth`, qui pose le Bearer de `auth.session` (sans session : aucun `Authorization`, la clé
  `sb_publishable_` n'étant pas un JWT). La gateway lit la session elle-même, refuse avant tout appel si elle
  est absente ou n'appartient pas au compte affiché (`context.userId`), et envoie son jeton explicitement.
- **Transport** : `POST`, corps `{}`, en-tête `Authorization: Bearer <access_token utilisateur>` (jamais la
  clé service_role : la fonction refuse le service_role en 403 « Suppression self-service uniquement »).
  `supabase/config.toml` l.148-149 : `verify_jwt = false` — la vérification du JWT est faite **dans** la fonction
  (`verifyUserOrServiceRole`), pas par l'API Gateway ; le mode `--use-api` du déploiement ne lit pas ce
  fichier (`CLAUDE.md` « verify_jwt »), donc l'app ne suppose rien de la Gateway et traite un 401 comme
  un refus quelle qu'en soit l'origine.
- **Codes HTTP et corps** — liste exhaustive des réponses de `supabase/functions/delete-account/index.ts` et
  de `verifyUserOrServiceRole` (`supabase/functions/_shared/admin-auth.ts` l.106-169), dont `index.ts` l.23
  relaie le statut et le message (`{ error: auth.error }, auth.status`). Messages verbatim, sans accents quand
  la source n'en a pas ; la garde `tests/node/check-rpc-contracts.node.mjs` relit les deux fichiers et échoue
  si un statut ou un message manque ici. Base des tests de T8 (une réponse = un test).
  - **200** `{success:true, auth_deleted:true, anonymisation:{success:true, deja_anonymise?:boolean, profil_incomplet?:boolean}}` (`index.ts` l.253-257) → seul succès admis ; **aucune relecture possible** (refresh tokens révoqués, utilisateur Auth soft-deleted) : purge locale (`signOut(scope: .local)` tolérant) → `SessionController.signOut()` → écran « Compte supprimé » **avant** l'événement SDK (sinon « Votre session a expiré »). Ordre livré en T8, sans course : avis « Compte supprimé » (`AvisFinDeCompte`) → `SessionController.signOutLocally()` retire l'identité (epoch avancé, `.signedOut(nil)`) **puis** purge par `AuthPort.signOutLocally()` (bornée à 15 s, tolérante) : le `.signedOut` que le SDK émet pendant la purge arrive sans identité active et est ignoré ; préférences locales du compte (clés `UserDefaults` dont un segment est le `userId`) purgées.
  - **401** `{error:'Authorization Bearer manquant'}` (`admin-auth.ts` l.111, en-tête absent ou vide) ; `{error:'Token invalide ou expiré'}` (l.145, `auth.getUser` refuse le jeton).
  - **403** `{error:'Compte desactive'}` (`admin-auth.ts` l.150 : utilisateur Auth `deleted_at` posé ; l.155 : `banned_until` dans le futur ou illisible — cas d'un second appel après une suppression réussie ou après `AUTH_DELETE_PENDING`) ; `{error:'Suppression self-service uniquement'}` (`index.ts` l.25, service_role ou JWT sans utilisateur) ; `{error:'Un compte administrateur doit etre retire par un autre administrateur'}` (l.28, rôle `ADMIN` / `ADMIN_PLATEFORME`).
  - **405** `{error:'Methode non autorisee'}` (`index.ts` l.19, toute méthode autre que `POST` ; `OPTIONS` = préflight CORS, jamais émis par l'app).
  - **409** `{error:'Votre compte nécessite une vérification manuelle avant suppression.', error_code:'ACCOUNT_PROFILE_CONFLICT'}` (l.85-88, profils soignant et établissement simultanés) ; `{error:"Transferez d'abord le role de proprietaire a un autre membre.", error_code:'DERNIER_PROPRIETAIRE'}` (l.108-111) ; `{error:"Transferez d'abord la propriete du groupe de sante.", error_code:'DERNIER_PROPRIETAIRE_GROUPE'}` (l.124-127) ; `{error:<message PostgREST>}` quand `fn_supprimer_compte_rate_limited` lève une erreur (l.137) ; `{…<jsonb RPC>, success:false, error:<error RPC> || 'Anonymisation non confirmée'}` quand la RPC répond `{error}` ou sans `success === true` (l.139-140, dont `'Demande de suppression déjà en cours.'`). Mêmes formes l.144-147 pour `fn_supprimer_compte_etablissement_rate_limited` (compte établissement, sans objet pour un soignant).
  - **429** `{error:'Demande deja en cours'}` (`index.ts` l.30-31 : 3 appels / 60 s par `userId:ip`, compteur en mémoire de l'instance).
  - **500** `{error:'Configuration serveur incomplète (SUPABASE_URL/ANON_KEY)'}` (`admin-auth.ts` l.139) ; `{error:'Configuration serveur incomplete'}` (`index.ts` l.38) ; `{error:'Retrait des equipes impossible'}` (l.181) ; `{error:'Retrait des groupes impossible'}` (l.196) ; `{error:'Erreur interne'}` (l.260, toute exception, y compris dans `verifyUserOrServiceRole`).
  - **503** `{error:'Verification du compte impossible'}` (`index.ts` l.71, lecture des profils impossible) ; `{error:'Verification des responsabilites impossible'}` (l.105, comptage des propriétaires d'établissement) ; `{error:'Verification des responsabilites groupe impossible'}` (l.122, comptage des propriétaires de groupe) ; `{success:false, auth_deleted:false, error:'Anonymisation du profil non confirmée ; suppression Auth non effectuée.', error_code:'ANONYMISATION_NON_CONFIRMEE'}` (l.166-171) ; `{error:'Compte bloque et anonymise; suppression Auth en cours de finalisation', error_code:'AUTH_DELETE_PENDING'}` (l.247-250) — ces deux derniers cas laissent un compte **banni ou anonymisé** : l'app force aussi la déconnexion locale (`LOT1_PLAN.md` §3 T8). Les trois premiers 503 n'ont rien modifié : refus affiché, aucune nouvelle tentative automatique.
  - Hors fonction : une erreur de la plateforme (passerelle, délai) peut renvoyer un autre statut ou un corps non JSON ; la règle ci-dessous s'applique (refus, message générique si aucun `error` lisible).
- **Règle app** : tout code ≠ 200, ou 200 sans `success === true`, est un refus affiché avec le message
  serveur verbatim (`DeleteAccountOutcome.refused(message, code)`) ; aucune nouvelle tentative automatique.
  Texte RGPD de l'écran de confirmation verbatim web (`SectionConfidentialite.tsx` l.155-156, l.171-172,
  tutoiement) tant que Gabrielle n'a pas validé un wording vouvoyé (HARD STOP n°4) ; égalité mot pour mot
  gardée par `CompteSuppressionVerbatimTests` (lecture de la source web, `swift test` macOS). Titre de la
  confirmation sans le pictogramme « 🗑️ » du web. Délai dépassé (15 s) ou réseau coupé : « La suppression de
  votre compte n'a pas pu être confirmée… » (le serveur a pu agir ; nouvelle tentative manuelle seulement, à
  laquelle l'edge répond `Compte desactive` si la suppression a eu lieu). Seuls les `error_code`
  `AUTH_DELETE_PENDING` et `ANONYMISATION_NON_CONFIRMEE` forcent la déconnexion locale (écran de fin, message
  serveur verbatim) ; un 403 `Compte desactive` reste un refus affiché, session locale conservée jusqu'au
  rafraîchissement refusé par le SDK (point ouvert, non tranché au lot 1).
- **Preuve STAGING** : compte jetable créé par la fixture du run uniquement (garde équivalente à
  `createDeletionSafetyGate`), `soignants.nom = 'Supprimé'` relu en SQL ; B9 « données » → go explicite (décision 13).

## Interdite côté natif : `fn_etablissement_public`

- **Statut natif** : **jamais** (non suivie dans `RPC_SUIVIES`, aucun gateway ne doit l'appeler).
- **Pourquoi** : `fn_etablissement_public(p_etablissement_id uuid)` (`public.sql` l.34969-35000) renvoie le
  profil public d'un établissement **sauf** si `supprime_le IS NOT NULL` ou si `est_compte_test = true`
  (`AND e.est_compte_test IS FALSE`, l.34993-34995). Tout établissement de recette STAGING est un compte
  TEST (cohorte fail-closed, `trg_forcer_compte_test_prelaunch`) : la RPC renvoie `NULL` pour 100 % d'entre
  eux, et une assertion STAGING sur le nom échouerait ou, pire, passerait sur le repli « Établissement ».
  Le web l'appelle encore (`DetailMissionSoignant.tsx` l.428, `as any`) : écart assumé, non reproduit.
- **Source unique du nom d'établissement côté natif** : `fn_etablissements_safe` (fiche ci-dessus ;
  `MissionQuery.etablissementsRPC`, `SupabaseMissionsGateway.etablissements(ids:)`), qui applique la
  cohorte et ne renvoie la ligne que si la mission est assignée au soignant ou OUVERTE. Repli d'affichage
  « Établissement » conservé, mais toute assertion STAGING porte sur l'**égalité** avec le nom de fixture.
  `fn_dashboard_soignant_complet.mes_missions.etab_nom` (LEFT JOIN sans filtre cohorte, l.27970 : nom nul si
  l'établissement manque) et `fn_mes_favoris_etablissements.nom` (JOIN interne sans filtre cohorte ni
  `supprime_le`, l.41859 : un favori dont l'établissement n'existe plus disparaît de la liste au lieu d'y
  figurer avec un nom nul) ne servent que si la ligne safe manque ; une divergence est un bug de fixture.
- **Garde** : `tests/node/check-rpc-contracts.node.mjs` échoue si `fn_etablissement_public` entre dans
  `RPC_SUIVIES` ; ce test tourne sur toute PR (étape « Garde de livraison mobile » de
  `.github/workflows/validate-pr.yml`, sans filtre de chemins). Un `git grep fn_etablissement_public ios-native/`
  doit rester vide.

## Lot 4 — synthèse

Ajoutée par la tranche T0 du lot 4 (`docs/mobile-swift/LOT4_PLAN.md` §3 T0, décisions
`docs/mobile-swift/DECISIONS_LOT4.md`) : quarante-deux RPC consommées par le lot 4, soit **quarante et une
RPC** propres au lot 4, suivies en `a_venir`, `lot: 4`, dans l'ordre des tranches (T3a swipe, T4 filtres,
T5 disponibilités, T6 parrainage, T8 litiges et réclamations, T9 score et évaluations, T7a/T7b messagerie,
T10 bulletins, T11 pool urgence et exclusions), et une RPC partagée avec le lot 2,
`fn_ouvrir_litige_rate_limited` (`RPC_PARTAGEES_LOT4`, précision 10 des décisions) : une seule entrée dans
`RPC_SUIVIES`, celle du T0 du lot 2 (`lot: 2`) quand il est fusionné, `a_venir`, `lot: 4` à défaut ; une
seule fiche, dont la sous-section « Usage du lot 4 » porte l'usage `AUTRE`. Le décompte de l'en-tête
(vingt-sept RPC) couvre les lots 0 et 1 ; ces quarante-deux s'y ajoutent. Écart assumé à la règle
« statut passé en `consommee` par la PR qui câble la gateway » : les statuts du lot 4 passent en `consommee`
**en une fois par T15** (onze tranches parallèles ne modifient jamais le même tableau). Fiches propres au lot :
« lecture des exceptions », actions `SWIPE_LIKE` / `URGENCE`, edges `messagerie-validate` et
`copies-bulletins`, Realtime, double-aveugle et surcharges du litige, en fin de section.

Une entrée de plus porte `lot: 4` sans appartenir à ces quarante-deux : `fn_suggestions_missions_pour_soignant`,
reclassée du lot 1 vers le lot 4 par la revue B8 du T3 du lot 1 (son seul appelant web,
`SuggestionsMissions.tsx`, n'est monté par aucune page ; fiche et ligne dans la synthèse du lot 1), après
l'écriture du T0 du lot 4. `LOT4_PLAN.md` ne la cite dans aucune tranche : elle reste `a_venir`, `lot: 4`,
hors du tableau ci-dessous, et son sort (consommée ou retirée de `RPC_SUIVIES`) est statué en T15
(`DECISIONS_LOT4.md`, précision 11).

Toutes les RPC du lot 4 sont `SECURITY DEFINER` et accordées à `authenticated` ; dix ne le sont pas à
`service_role` (`fn_lister_conversations_messagerie`, `fn_interlocuteurs_conversations`,
`fn_marquer_messages_lus`, `fn_messages_non_lus`, `fn_typing_start`, `fn_typing_stop`, `fn_update_presence`,
`fn_obtenir_conversation`, `fn_lister_copies_bulletins`, `fn_signaler_copie_bulletin`), sans effet pour
l'app qui appelle avec le JWT du soignant. Dix ont `types: null` dans `ios-native/rpc-contracts.json`
(contrat tenu par `public.sql` seul, précédent du lot 1) : neuf absentes de `types.ts`
(`fn_retirer_candidature`, `fn_initialiser_preferences_matching`, `fn_definir_disponibilite`,
`fn_lister_conversations_messagerie`, `fn_est_bloque`, `fn_bloquer_utilisateur`, `fn_debloquer_utilisateur`,
`fn_lister_copies_bulletins`, `fn_signaler_copie_bulletin`) et `fn_ouvrir_litige_rate_limited`, déclarée
l.10147 en union de surcharges que `extractTypesSignature` ne lit pas. Deux sont hors manifeste
(`fn_lister_copies_bulletins`, `fn_signaler_copie_bulletin`) : **classement manuel
`RPC_UTILISATEUR_AUTH_INTERNE`** sur le modèle de la décision 6 du lot 1, manifeste non régénéré, `manifeste:
null` gardé dans le JSON (fait observé) ; la surcharge à 4 arguments de `fn_ouvrir_litige_rate_limited` est
hors manifeste mais jamais appelée.

**Sources lues par la garde (lot 4).** `tests/node/check-rpc-contracts.node.mjs` confronte chaque fiche
ci-dessous au corps SQL de sa RPC (toute réponse littérale `'error'`, `'message'`, JSON `{"error"}`,
`RAISE EXCEPTION`, `MESSAGE=`, tout `error_code` et tout SQLSTATE doit y être cité, valeurs JSON réelles,
apostrophes non doublées), ainsi que : le corps de `fn_accepter_mission_urgence` et le branchement de
`fn_confirmer_action_planning_v1` ; `fn_acces_copie_bulletin` ; `supabase/functions/messagerie-validate/index.ts`,
`supabase/functions/_shared/anti-leak.ts`, `supabase/functions/copies-bulletins/handler.ts`,
`supabase/config.toml` ; la migration `20260729143000_reinstaller_dependances_auth_storage_apres_bootstrap.sql`
(publication Realtime) ; les GRANT de `evaluations_publiees` ; `tests/non-regression/guards.sh` (garde-fous 18
et 19). Une PR web, edge, de migration ou de re-baseline qui modifie l'une de ces sources met la fiche
concernée à jour **dans la même PR**.

| RPC | Statut natif | Lot | Classe manifeste | GRANT | types.ts |
|---|---|---|---|---|---|
| `fn_obtenir_missions_swipe` | à venir | 4 (T3a) | RPC_UTILISATEUR_AUTH_INTERNE | authenticated, service_role | déclarée |
| `fn_enregistrer_swipe` | à venir | 4 (T3a) | RPC_UTILISATEUR_AUTH_INTERNE | authenticated, service_role | déclarée |
| `fn_retirer_candidature` | à venir | 4 (T3a) | RPC_UTILISATEUR_AUTH_INTERNE | authenticated, service_role | absente |
| `fn_initialiser_preferences_matching` | à venir | 4 (T3a) | RPC_UTILISATEUR_AUTH_INTERNE | authenticated, service_role | absente |
| `fn_lister_mes_filtres_sauvegardes` | à venir | 4 (T4) | RPC_UTILISATEUR_AUTH_INTERNE | authenticated, service_role | déclarée |
| `fn_creer_filtre_sauvegarde` | à venir | 4 (T4) | RPC_UTILISATEUR_AUTH_INTERNE | authenticated, service_role | déclarée |
| `fn_modifier_filtre_sauvegarde` | à venir | 4 (T4) | RPC_UTILISATEUR_AUTH_INTERNE | authenticated, service_role | déclarée |
| `fn_supprimer_filtre_sauvegarde` | à venir | 4 (T4) | RPC_UTILISATEUR_AUTH_INTERNE | authenticated, service_role | déclarée |
| `fn_definir_disponibilite` | à venir | 4 (T5) | RPC_UTILISATEUR_AUTH_INTERNE | authenticated, service_role | absente |
| `fn_obtenir_mes_parrainages` | à venir | 4 (T6) | RPC_UTILISATEUR_AUTH_INTERNE | authenticated, service_role | déclarée |
| `fn_appliquer_parrainage` | à venir | 4 (T6) | RPC_UTILISATEUR_AUTH_INTERNE | authenticated, service_role | déclarée |
| `fn_ouvrir_litige_rate_limited` | à venir | partagée : lot 2 (T5b) si son T0 est fusionné, sinon 4 ; usage lot 4 (T8) | RPC_UTILISATEUR_AUTH_INTERNE (2 et 3 arguments ; la 4 arguments est hors manifeste) | authenticated, service_role | union de surcharges (lue `null`) |
| `fn_ajouter_message_litige` | à venir | 4 (T8) | MIXTE_TENANT_ADMIN | authenticated, service_role | déclarée |
| `fn_soumettre_reclamation` | à venir | 4 (T8) | RPC_UTILISATEUR_AUTH_INTERNE | authenticated, service_role | déclarée |
| `fn_mon_breakdown_actuel` | à venir | 4 (T9) | RPC_UTILISATEUR_AUTH_INTERNE | authenticated, service_role | déclarée |
| `fn_mes_evenements_score` | à venir | 4 (T9) | RPC_UTILISATEUR_AUTH_INTERNE | authenticated, service_role | déclarée |
| `fn_evolution_score_soignant` | à venir | 4 (T9) | RPC_UTILISATEUR_AUTH_INTERNE | authenticated, service_role | déclarée |
| `fn_lister_notations_recues` | à venir | 4 (T9) | RPC_UTILISATEUR_AUTH_INTERNE | authenticated, service_role | déclarée |
| `fn_creer_reclamation_score` | à venir | 4 (T9) | RPC_UTILISATEUR_AUTH_INTERNE | authenticated, service_role | déclarée |
| `fn_mes_notations_recues_avec_stats` | à venir | 4 (T9) | RPC_UTILISATEUR_AUTH_INTERNE | authenticated, service_role | déclarée |
| `fn_signaler_notation` | à venir | 4 (T9) | RPC_UTILISATEUR_AUTH_INTERNE | authenticated, service_role | déclarée |
| `fn_lister_conversations_messagerie` | à venir | 4 (T7a) | MIXTE_TENANT_ADMIN | authenticated | absente |
| `fn_interlocuteurs_conversations` | à venir | 4 (T7a) | RPC_UTILISATEUR_AUTH_INTERNE | authenticated | déclarée |
| `fn_marquer_messages_lus` | à venir | 4 (T7a) | MIXTE_TENANT_ADMIN | authenticated | déclarée |
| `fn_messages_non_lus` | à venir | 4 (T7b) | RPC_UTILISATEUR_AUTH_INTERNE | authenticated | déclarée |
| `fn_typing_start` | à venir | 4 (T7a) | RPC_UTILISATEUR_AUTH_INTERNE | authenticated | déclarée |
| `fn_typing_stop` | à venir | 4 (T7a) | RPC_UTILISATEUR_AUTH_INTERNE | authenticated | déclarée |
| `fn_update_presence` | à venir | 4 (T7a) | RPC_UTILISATEUR_AUTH_INTERNE | authenticated | déclarée |
| `fn_est_bloque` | à venir | 4 (T7b) | RPC_UTILISATEUR_AUTH_INTERNE | authenticated, service_role | absente |
| `fn_bloquer_utilisateur` | à venir | 4 (T7b) | RPC_UTILISATEUR_AUTH_INTERNE | authenticated, service_role | absente |
| `fn_debloquer_utilisateur` | à venir | 4 (T7b) | RPC_UTILISATEUR_AUTH_INTERNE | authenticated, service_role | absente |
| `fn_signaler_utilisateur` | à venir | 4 (T7b) | MIXTE_TENANT_ADMIN | authenticated, service_role | déclarée |
| `fn_user_id_pour_etablissement` | à venir | 4 (T7b) | MIXTE_TENANT_ADMIN | authenticated, service_role | déclarée |
| `fn_obtenir_conversation` | à venir | 4 (T7b) | MIXTE_TENANT_ADMIN | authenticated | déclarée |
| `fn_lister_copies_bulletins` | à venir | 4 (T10) | hors manifeste — classée RPC_UTILISATEUR_AUTH_INTERNE (classement manuel) | authenticated | absente |
| `fn_signaler_copie_bulletin` | à venir | 4 (T10) | hors manifeste — classée RPC_UTILISATEUR_AUTH_INTERNE (classement manuel) | authenticated | absente |
| `fn_pool_urgence_missions_pour_soignant` | à venir | 4 (T11) | RPC_UTILISATEUR_AUTH_INTERNE | authenticated, service_role | déclarée |
| `fn_toggle_pool_urgence` | à venir | 4 (T11) | RPC_UTILISATEUR_AUTH_INTERNE | authenticated, service_role | déclarée |
| `fn_toggle_pool_urgence_sms` | à venir | 4 (T11) | RPC_UTILISATEUR_AUTH_INTERNE | authenticated, service_role | déclarée |
| `fn_mes_exclusions_recues` | à venir | 4 (T11) | RPC_UTILISATEUR_AUTH_INTERNE | authenticated, service_role | déclarée |
| `fn_retirer_exclusion` | à venir | 4 (T11) | RPC_UTILISATEUR_AUTH_INTERNE | authenticated, service_role | déclarée |
| `fn_exclure_utilisateur` | à venir | 4 (T11) | RPC_UTILISATEUR_AUTH_INTERNE | authenticated, service_role | déclarée |

## Lot 4 — lecture des exceptions PostgREST et des réponses edge

Règle normative pour T1 et pour chaque gateway du lot 4 (`LOT4_PLAN.md` §2.4, corrections 14 et 15).
`SupabaseErrorMapping.unauthorizedCodes` contient `42501` (`SupabaseErrorMapping.swift` l.23) et
`SupabaseErrorMapping.map` perd `PostgrestError.message` : sans interception, un refus d'accès métier
afficherait « Votre session a expiré », et un `FunctionsError.httpError(code:data:)` (SDK
`Sources/Functions/Types.swift` l.10, traité par aucune branche de `SupabaseErrorMapping.map`) deviendrait le
message générique. Les exceptions PostgREST sont donc lues **avant** `SupabaseErrorMapping.map`, dans
`RPCResponse.swift` : la surcharge `appeler(…, exceptionsMetier:)` livrée par le lot 3 T1 est étendue par le
lot 4 T1 au couple « SQLSTATE **et** message connu » (`executer` est `private` : un fichier d'extension ne
peut pas s'intercaler) ; les corps des réponses edge sont décodés par `EdgeResponse` (lot 3 T1) avant tout
mapping. `SupabaseErrorMapping.swift` reste inchangé.

| SQLSTATE / forme | Message (valeur exacte) | RPC émettrice (ligne du dump) | Traitement natif |
|---|---|---|---|
| `28000` | `Non authentifié` | `fn_lister_conversations_messagerie` (l.39748), `fn_interlocuteurs_conversations` (l.38746), `fn_marquer_messages_lus` (l.41288), `fn_user_id_pour_etablissement` (l.64708), `fn_obtenir_conversation` (l.45636) | `.unauthorized` |
| `28000` | `NON_AUTHENTIFIE` | `fn_typing_start` (l.64362), `fn_update_presence` (l.64451) | `.unauthorized` |
| `42501` | `Accès refusé` | `fn_marquer_messages_lus` (l.41295, l.41325, l.41333, l.41341) | issue `accesRefuse` : conversation retirée après relecture, pas de déconnexion |
| `42501` | `Conversation non autorisée` | `fn_obtenir_conversation` (l.45679) | issue « conversation indisponible » |
| `42501` | `Non autorisé` | `fn_user_id_pour_etablissement` (l.64760) | issue « conversation indisponible » |
| `42501` | `NON_AUTORISE` | `fn_typing_start` (l.64370) | indicateur de saisie abandonné sans message |
| `42501` | `Compte inactif` | `fn_interlocuteurs_conversations` (l.38749) | refus métier, noms d'interlocuteurs non affichés, pas de déconnexion par cet appel |
| `42501` | `COPIE_ACCES_REFUSE` | `fn_lister_copies_bulletins` (l.39845), `fn_signaler_copie_bulletin` (l.56191) | refus d'accès à la copie |
| `42501` | tout autre message | — | `.unauthorized` (comportement du lot 0 conservé) |
| `22023` | `Curseur incomplet`, `Trop de conversations demandées`, `Interlocuteur invalide`, `COPIE_MOTIF_INVALIDE` | `fn_lister_conversations_messagerie` (l.39751), `fn_interlocuteurs_conversations` (l.38755), `fn_obtenir_conversation` (l.45640), `fn_signaler_copie_bulletin` (l.56193) | défaut du client : `.contract`, jamais « session expirée » |
| `23514` | violation de `reclamations_categorie_check` (texte PostgreSQL) | `fn_soumettre_reclamation` (catégorie hors liste) | libellé générique (liste fermée côté app) |
| `P0001` | `Le signalement n’a pas pu être enregistré. Veuillez réessayer.` | `fn_signaler_notation` (l.56264) | message serveur restitué (rédigé pour l'utilisateur) |
| `P0001` | `Attribution du parrain non persistée` | `fn_appliquer_parrainage` (l.19097) | erreur générique, code de parrainage conservé |
| HTTP 200 | `{missions:[], error:'auth_required'}`, `{ok:false, error:'auth_required'}`, `{success:false, error_code:'NON_AUTHENTIFIE'}` | `fn_obtenir_missions_swipe`, `fn_enregistrer_swipe`, `fn_creer_reclamation_score`, `fn_mes_notations_recues_avec_stats` | `.unauthorized` |
| `FunctionsError.httpError(code:data:)` | corps JSON de l'edge | `messagerie-validate`, `copies-bulletins` | `EdgeResponse` : code et message lus avant tout mapping (fiches edge ci-dessous) |

Complément du T0 au blueprint : le plan de lot citait trois messages `42501` (`Accès refusé`,
`Conversation non autorisée`, `COPIE_ACCES_REFUSE`) ; le dump en compte six (`Non autorisé`, `NON_AUTORISE` et
`Compte inactif` en plus). La garde relève tous les `42501` des corps du lot 4 et échoue si l'un manque à ce
tableau.

## Lot 4 — actions `SWIPE_LIKE` et `URGENCE` de `fn_confirmer_action_planning_v1`

- **Statut natif** : à venir (lot 4 ; RPC du lot 1, fiche `fn_confirmer_action_planning_v1` ci-dessus). L'enum
  `ActionPlanning` reçoit `.swipeLike = "SWIPE_LIKE"` et `.urgence = "URGENCE"` en T1 (D2), avec
  `p_creneaux_confirmes` exact (`CreneauxConfirmes.pourAction`, golden du lot 1 T2). Les refus propres à la
  RPC (planning à reconfirmer, conflit, repos de 11 h) précèdent la délégation et sont décrits dans sa fiche.
- **`SWIPE_LIKE`** (❤️, T3a) : délègue à `fn_enregistrer_swipe(p_mission_id, 'LIKE', p_choix_contrat)` ; la
  réponse est celle de `fn_enregistrer_swipe` — `{ok:true, …, candidature_id, choix_contrat}`,
  **pas de `success`** — et ses refus `{ok:false, …}` (fiche `fn_enregistrer_swipe`). `choix_requis` →
  `ChoixContratSheet` → nouvel appel `SWIPE_LIKE` avec `p_choix_contrat` ; planning à reconfirmer → relecture
  de la mission et nouveau récapitulatif. Relecture : candidature par `candidature_id`.
- **`URGENCE`** (acceptation rapide du pool, T11) : délègue à `fn_accepter_mission_urgence(p_mission_id)`
  (`public.sql` l.5145), qui **ignore `p_choix_contrat`** (`fn_resoudre_contrat_mission(p_mission_id, v_uid,
  NULL)`, l.5174, correction 10). Succès `{success:true, candidature_id, choix_contrat, profession_requise,
  message:"Acceptation enregistrée. En attente de validation par l'établissement."}`, candidature créée en
  `EN_ATTENTE_VALIDATION_ETAB` ; refus `{success:false, error}` : `'Non authentifié'` (→ `.unauthorized`),
  `'Profil soignant introuvable'`, `'Mission introuvable'`, `'Mission urgente non disponible'`,
  `'Profession ou spécialité incompatible'`, `'Accès refusé'` (exclusion),
  `'Vous avez déjà candidaté à cette mission'`, `'Vos documents ne sont pas validés pour cette mission ' || lower(contrat)` avec
  `documents_requis_pour` (message composé côté serveur, affiché tel quel) ; `{success:false, choix_requis:true,
  error, options}` relayé de `fn_resoudre_contrat_mission` : **non rejouable** en `URGENCE` → message et lien
  vers le détail de la mission (POSTULER / ACCEPTER, lot 1), jamais de feuille de choix. Libellé du bouton
  repris du web : « Confirmer mon acceptation urgente » (`PoolUrgenceSoignant.tsx` l.257-264). Relecture :
  candidature par `candidature_id`, puis `fn_pool_urgence_missions_pour_soignant` (`statut_candidature`).
- **Exemple de réponse STAGING** : `SWIPE_LIKE` recommandé dans le run T14 ; `URGENCE` non exigé.

## fn_obtenir_missions_swipe

- **Statut natif** : à venir (lot 4, T3a).
- **Usage prévu** : Paquet de la vue Swipe d'Explorer (`p_limit = 20`, borné 1-100 côté serveur) : missions `OUVERTE` à venir, éligibles (`fn_soignant_eligible_mission`), au taux minimum du soignant, jamais déjà swipées (`NOT EXISTS swipes`, l.46095-46096), cohorte TEST respectée (`est_compte_test`, l.46090) ; puis créneaux PREVISIONNEL hors pauses par `MissionSlotPager` (lot 0) et filtre du paquet (port de `VueSwipeMissions.tsx` l.373-392, golden T2). Relu à l'apparition et à la reprise après 60 s.
- **Signature SQL** (`supabase/schema/public.sql` l.46023) :

```sql
CREATE OR REPLACE FUNCTION "public"."fn_obtenir_missions_swipe"("p_limit" integer DEFAULT 20) RETURNS "jsonb"
    LANGUAGE "plpgsql" SECURITY DEFINER
    SET "search_path" TO 'public'
```

- **Classe d'authentification (manifeste)** : `RPC_UTILISATEUR_AUTH_INTERNE` pour `fn_obtenir_missions_swipe(integer)` — RPC utilisateur : identité `auth.uid()` lue en interne, appel avec le JWT du soignant.
- **GRANT connu** : `REVOKE ALL … FROM PUBLIC` puis `GRANT ALL … TO "authenticated", "service_role"`.
- **Signature TypeScript** (`types.ts`, section `Functions`) : `Args: { p_limit?: number }` ; `Returns: Json`.
- **Contrat de réponse** : succès `{missions:[{mission_id, intitule, profession_requise, etablissement_id, etablissement_nom, etablissement_ville, etablissement_code_postal, etablissement_logo_url, etablissement_score, taux_horaire_base, duree_heures, debut_le, fin_le, est_urgente, service, type_contrat_applique, type_contrat_recherche, nb_creneaux, total_brut, net_a_payer, net_estime, montant_ifm, montant_icp, montant_majoration_nuit, montant_majoration_dimanche, montant_majoration_ferie, score, breakdown, paiement_rapide, distance_km}]}` (l.46040-46084, l.46102) — **pas de `success`**. Non authentifié : `{missions:[], error:'auth_required'}` (l.46033, HTTP 200) → `.unauthorized`. Ordre `score + random()*13` (l.46039) : aucune assertion d'ordre, démo déterministe. `score` vaut `COALESCE(ms.score_global, 0)` (l.46067) : une mission sans ligne `matching_scores` affiche 0 aujourd'hui (correction 13) ; décodé `Int?` en prévision de B1 (B9, D5), valeur serveur affichée telle quelle. `breakdown` vaut `{}` par défaut (raisons « Pourquoi N ? », golden T2). Montants affichés tels quels ; `etablissement_nom` vient du payload, sans appel à `fn_etablissements_safe`.
- **Exemple de réponse STAGING** : recommandé dans le run T14 (paquet non vide sur la fixture D4, égalité de `etablissement_nom` avec le nom de fixture), corps anonymisé.

## fn_enregistrer_swipe

- **Statut natif** : à venir (lot 4, T3a).
- **Usage prévu** : ✕ (`DISLIKE`) et ⭐ (`FAVORI`) appelés directement ; ❤️ passe par `fn_confirmer_action_planning_v1(…, 'SWIPE_LIKE', …)`, qui délègue ici avec `'LIKE'` (fiche « Lot 4 — actions `SWIPE_LIKE` et `URGENCE` »). Jamais de `SUPER_LIKE` (réécrit en `FAVORI`, l.32771, D3). Une carte n'est retirée du paquet qu'après `ok:true`.
- **Signature SQL** (`supabase/schema/public.sql` l.32753) :

```sql
CREATE OR REPLACE FUNCTION "public"."fn_enregistrer_swipe"("p_mission_id" "uuid", "p_direction" "text", "p_choix_contrat" "text" DEFAULT NULL::"text") RETURNS "jsonb"
    LANGUAGE "plpgsql" SECURITY DEFINER
    SET "search_path" TO 'public'
```

- **Classe d'authentification (manifeste)** : `RPC_UTILISATEUR_AUTH_INTERNE` pour `fn_enregistrer_swipe(uuid,text,text)` — RPC utilisateur : identité `auth.uid()` lue en interne, appel avec le JWT du soignant.
- **GRANT connu** : `REVOKE ALL … FROM PUBLIC` puis `GRANT ALL … TO "authenticated", "service_role"`.
- **Signature TypeScript** (`types.ts`, section `Functions`) : `Args: { p_direction: string; p_mission_id: string }` ; `Returns: Json`.
- **Contrat de réponse** : succès `LIKE` / `DISLIKE` `{ok:true, swipe_id, direction, candidature_id, choix_contrat, profession_requise, docs_a_completer, warning}` (l.32845-32851) ; succès `FAVORI` `{ok:true, swipe_id, direction:'FAVORI', sauvegardee:true}` (l.32829) — **pas de `success`** : discrimination par `ok`. Refus `{ok:false, error}` (HTTP 200) à codes techniques, traduits par la table `SwipeRefus` (libellés produit vouvoyés, non juridiques) : `auth_required` (l.32770, → `.unauthorized`), `direction_invalide` (l.32773), `mission_indisponible` (l.32779), `profil_introuvable` (l.32782), `profession_incompatible` (l.32787), `acces_refuse` (l.32790, établissement qui a exclu le soignant), `mission_deja_swipee` (l.32822, `swipes` unique et immuable). Messages rédigés, affichés verbatim (`LIKE` seulement) : `'Vous avez déjà candidaté à cette mission'` (l.32795) ; `'Les documents requis pour candidater en libéral sont manquants ou expirés.'` avec `documents_requis_pour:'LIBERAL'` (l.32809-32813) ; `{ok:false, error:<message de fn_conflit_planning_soignant>, conflit_planning:true}` (l.32799) ; relais de `fn_resoudre_contrat_mission` privé de sa clé `ok` (`{ok:false, choix_requis:true, error, options}`, l.32805). `docs_a_completer:true` → encart « documents à compléter » et renvoi `/soignant/mes-documents` (lot 2) ; `warning` affiché. Relecture : ⭐ → `missions_sauvegardees` ; `LIKE` → candidature par `candidature_id`.
- **Exemple de réponse STAGING** : recommandé dans le run T14 : `LIKE` puis effets serveur relus en SQL (`badges_soignant`, `streaks_soignant`, D3), `FAVORI` relu dans `missions_sauvegardees`.

## fn_retirer_candidature

- **Statut natif** : à venir (lot 4, T3a).
- **Usage prévu** : « Annuler » du toast de 5 s qui suit un ❤️ (D4) : supprime la candidature `EN_ATTENTE`. La ligne `swipes` reste (immuable) : la carte n'est **jamais** remise dans le paquet, un nouveau `LIKE` répondrait `mission_deja_swipee` (correction 12). Seule RPC « pas avant le lot 4 » (`RPC_PAS_AVANT_LOT4`), suivie ici avec `lot: 4`.
- **Signature SQL** (`supabase/schema/public.sql` l.54817) :

```sql
CREATE OR REPLACE FUNCTION "public"."fn_retirer_candidature"("p_candidature_id" "uuid") RETURNS "jsonb"
    LANGUAGE "plpgsql" SECURITY DEFINER
    SET "search_path" TO 'public'
```

- **Classe d'authentification (manifeste)** : `RPC_UTILISATEUR_AUTH_INTERNE` pour `fn_retirer_candidature(uuid)` — RPC utilisateur : identité `auth.uid()` lue en interne, appel avec le JWT du soignant.
- **GRANT connu** : `REVOKE ALL … FROM PUBLIC` puis `GRANT ALL … TO "authenticated", "service_role"`.
- **Signature TypeScript** (`types.ts`, section `Functions`) : absente (`types.ts` en retard sur le schéma ; contrat tenu par `public.sql`, `types: null` dans `rpc-contracts.json`).
- **Contrat de réponse** : `{success:true}` (l.54844) ; `{success:false, error}` : `'Non authentifié'` (l.54827, → `.unauthorized`), `'Candidature introuvable'` (l.54834), `'Non autorisé'` (l.54837), `'La candidature a déjà été traitée et ne peut plus être retirée ici.'` (l.54840, statut ≠ `EN_ATTENTE`) — messages verbatim (`RetraitOutcome`). Relecture : candidature absente.
- **Exemple de réponse STAGING** : non exigé (démo + tests de gateway) ; enregistré dans le run T14 si le `LIKE` y figure.

## fn_initialiser_preferences_matching

- **Statut natif** : à venir (lot 4, T3a).
- **Usage prévu** : Quiz de préférences au premier contact (D6 : marqueur local par userId absent **et** aucun swipe en base), sans la question « dispo urgence » (D26, remplacée par un lien vers Pool urgence). Quatre préférences dans [0, 1].
- **Signature SQL** (`supabase/schema/public.sql` l.38646) :

```sql
CREATE OR REPLACE FUNCTION "public"."fn_initialiser_preferences_matching"("p_pref_nuit" numeric, "p_pref_jour" numeric, "p_pref_weekend" numeric, "p_pref_semaine" numeric) RETURNS "jsonb"
    LANGUAGE "plpgsql" SECURITY DEFINER
    SET "search_path" TO 'public'
```

- **Classe d'authentification (manifeste)** : `RPC_UTILISATEUR_AUTH_INTERNE` pour `fn_initialiser_preferences_matching(numeric,numeric,numeric,numeric)` — RPC utilisateur : identité `auth.uid()` lue en interne, appel avec le JWT du soignant.
- **GRANT connu** : `REVOKE ALL … FROM PUBLIC` puis `GRANT ALL … TO "authenticated", "service_role"`.
- **Signature TypeScript** (`types.ts`, section `Functions`) : absente (`types.ts` en retard sur le schéma ; contrat tenu par `public.sql`, `types: null` dans `rpc-contracts.json`).
- **Contrat de réponse** : `{success:true}` (l.38672) ; `{success:false, error:'Non authentifié'}` (l.38654) → `.unauthorized` ; `{success:false, error:'Préférences hors bornes [0,1]'}` (l.38658), impossible si l'app borne ses valeurs, verbatim sinon. Upsert de `matching_preferences_soignant` **seulement tant que** `nb_signaux = 0` (l.38670) : au-delà, `{success:true}` sans effet. Aucune relecture (table non lue par l'app).
- **Exemple de réponse STAGING** : non exigé.

## fn_lister_mes_filtres_sauvegardes

- **Statut natif** : à venir (lot 4, T4).
- **Usage prévu** : Liste de `/soignant/parametres/recherches-sauvegardees` et relecture après chaque mutation ; toujours `p_audience = 'SOIGNANT_RECHERCHE_MISSIONS'`.
- **Signature SQL** (`supabase/schema/public.sql` l.39947) :

```sql
CREATE OR REPLACE FUNCTION "public"."fn_lister_mes_filtres_sauvegardes"("p_audience" "public"."filtre_audience" DEFAULT NULL::"public"."filtre_audience") RETURNS "jsonb"
    LANGUAGE "plpgsql" STABLE SECURITY DEFINER
    SET "search_path" TO 'public', 'extensions'
```

- **Classe d'authentification (manifeste)** : `RPC_UTILISATEUR_AUTH_INTERNE` pour `fn_lister_mes_filtres_sauvegardes(filtre_audience)` — RPC utilisateur : identité `auth.uid()` lue en interne, appel avec le JWT du soignant.
- **GRANT connu** : `REVOKE ALL … FROM PUBLIC` puis `GRANT ALL … TO "authenticated", "service_role"`.
- **Signature TypeScript** (`types.ts`, section `Functions`) : `Args: { p_audience?: Database["public"]["Enums"]["filtre_audience"] }` ; `Returns: Json`.
- **Contrat de réponse** : tableau `[{id, nom, audience, filtres, alerte_active, frequence_alerte, dernier_check_le, nb_resultats_dernier_check, cree_le, mis_a_jour_le}]` trié par `mis_a_jour_le` décroissant (l.39957-39964) ; `[]` si `auth.uid()` est nul (l.39955), indiscernable d'une liste vide (la session est vérifiée ailleurs) ; aucun `{error}`.
- **Exemple de réponse STAGING** : recommandé dans le run T14 (création puis relecture).

## fn_creer_filtre_sauvegarde

- **Statut natif** : à venir (lot 4, T4).
- **Usage prévu** : Sauvegarde d'une recherche et « Créer une alerte » 1-tap depuis Explorer. `p_audience` est obligatoire (aucun défaut) : toujours `'SOIGNANT_RECHERCHE_MISSIONS'`. `p_filtres` en **camelCase**, les sept clés `profession, rayonKm, tauxMin, typeContrat, urgentesOnly, horaire, villeRecherche` toujours présentes avec les valeurs par défaut du web (forme `CriteresAlerteMissions`, `src/lib/alertes-recherche-missions.ts` l.1-9 ; validateur `private.fn_filtres_recherche_missions_valides`, migration `20260925093121`) : `MissionFilters.ville` → `villeRecherche`, `etablissementId` retiré, nombres entiers écrits sans `.0`, `typeContrat ∈ {TOUS, CDD, LIBERAL}`, `horaire ∈ {TOUS, JOUR, NUIT, WEEKEND}`. Avant création, une recherche strictement identique (clé `JSON.stringify` triée, `AlerteRecherche`, golden T2) est réactivée plutôt que dupliquée.
- **Signature SQL** (`supabase/schema/public.sql` l.26466) :

```sql
CREATE OR REPLACE FUNCTION "public"."fn_creer_filtre_sauvegarde"("p_nom" "text", "p_audience" "public"."filtre_audience", "p_filtres" "jsonb", "p_alerte_active" boolean DEFAULT false, "p_frequence_alerte" "public"."filtre_frequence_alerte" DEFAULT 'QUOTIDIENNE'::"public"."filtre_frequence_alerte") RETURNS "jsonb"
    LANGUAGE "plpgsql" SECURITY DEFINER
    SET "search_path" TO 'public', 'extensions'
```

- **Classe d'authentification (manifeste)** : `RPC_UTILISATEUR_AUTH_INTERNE` pour `fn_creer_filtre_sauvegarde(text,filtre_audience,jsonb,boolean,filtre_frequence_alerte)` — RPC utilisateur : identité `auth.uid()` lue en interne, appel avec le JWT du soignant.
- **GRANT connu** : `REVOKE ALL … FROM PUBLIC` puis `GRANT ALL … TO "authenticated", "service_role"`.
- **Signature TypeScript** (`types.ts`, section `Functions`) : `Args: { p_alerte_active?: boolean; p_audience: Database["public"]["Enums"]["filtre_audience"]; p_filtres: Json; p_frequence_alerte?: Database["public"]["Enums"]["filtre_frequence_alerte"]; p_nom: string }` ; `Returns: Json`.
- **Contrat de réponse** : `{success:true, id}` (l.26522) puis relecture de la liste ; refus `{error}` seul (HTTP 200) : `'Non authentifié'` (l.26475, → `.unauthorized`), `'Nom invalide (1-100 caractères)'` (l.26477), `'Compte ou critères de recherche invalides.'` (l.26490 : destinataire d'alerte inactif ou critères refusés par le validateur), `"Limite de 20 recherches sauvegardées atteinte. Supprimez-en une avant d'en créer une nouvelle."` (l.26499), `'Un filtre avec ce nom existe déjà'` (l.26525, `unique_violation`) — verbatim. Refus propres à l'audience établissement, inatteignables par l'app : `'Votre compte doit être actif et rattaché à un établissement.'` (l.26482), `'Critères de recherche invalides. Recréez la recherche depuis l’annuaire.'` (l.26485), `'Les alertes ne sont pas encore disponibles. Vous pouvez sauvegarder sans alerte.'` (l.26493). Audits `FILTRE_CREE` et, si l'alerte est active, `ALERTE_ACTIVEE`, écrits par la RPC.
- **Exemple de réponse STAGING** : recommandé dans le run T14.

## fn_modifier_filtre_sauvegarde

- **Statut natif** : à venir (lot 4, T4).
- **Usage prévu** : Renommage, bascule de l'alerte et fréquence (`IMMEDIATE`, `QUOTIDIENNE`, `HEBDOMADAIRE`) ; `filtres` n'est pas modifiable (absent de la signature). Un paramètre `NULL` laisse la valeur inchangée (`COALESCE`).
- **Signature SQL** (`supabase/schema/public.sql` l.43089) :

```sql
CREATE OR REPLACE FUNCTION "public"."fn_modifier_filtre_sauvegarde"("p_id" "uuid", "p_nom" "text" DEFAULT NULL::"text", "p_alerte_active" boolean DEFAULT NULL::boolean, "p_frequence_alerte" "public"."filtre_frequence_alerte" DEFAULT NULL::"public"."filtre_frequence_alerte") RETURNS "jsonb"
    LANGUAGE "plpgsql" SECURITY DEFINER
    SET "search_path" TO 'public', 'extensions'
```

- **Classe d'authentification (manifeste)** : `RPC_UTILISATEUR_AUTH_INTERNE` pour `fn_modifier_filtre_sauvegarde(uuid,text,boolean,filtre_frequence_alerte)` — RPC utilisateur : identité `auth.uid()` lue en interne, appel avec le JWT du soignant.
- **GRANT connu** : `REVOKE ALL … FROM PUBLIC` puis `GRANT ALL … TO "authenticated", "service_role"`.
- **Signature TypeScript** (`types.ts`, section `Functions`) : `Args: { p_alerte_active?: boolean; p_frequence_alerte?: Database["public"]["Enums"]["filtre_frequence_alerte"]; p_id: string; p_nom?: string }` ; `Returns: Json`.
- **Contrat de réponse** : `{success:true}` (l.43152) puis relecture de la liste ; refus `{error}` : `'Non authentifié'` (l.43097, → `.unauthorized`), `'Filtre introuvable'` (l.43100), `'Nom invalide (1-100 caractères)'` (l.43103), `'Compte ou critères de recherche invalides.'` (l.43117 : activation d'une alerte dont les critères ne passent plus le validateur), `'Un filtre avec ce nom existe déjà'` (l.43155) ; audience établissement seulement : `'Votre compte doit être actif et rattaché à un établissement.'` (l.43108), `'Critères de recherche invalides. Recréez la recherche depuis l’annuaire.'` (l.43111), `'Les alertes ne sont pas encore disponibles.'` (l.43120). Audits `FILTRE_MODIFIE`, `ALERTE_ACTIVEE` / `ALERTE_DESACTIVEE` serveur.
- **Exemple de réponse STAGING** : non exigé.

## fn_supprimer_filtre_sauvegarde

- **Statut natif** : à venir (lot 4, T4).
- **Usage prévu** : Suppression d’une recherche sauvegardée.
- **Signature SQL** (`supabase/schema/public.sql` l.59994) :

```sql
CREATE OR REPLACE FUNCTION "public"."fn_supprimer_filtre_sauvegarde"("p_id" "uuid") RETURNS "jsonb"
    LANGUAGE "plpgsql" SECURITY DEFINER
    SET "search_path" TO 'public', 'extensions'
```

- **Classe d'authentification (manifeste)** : `RPC_UTILISATEUR_AUTH_INTERNE` pour `fn_supprimer_filtre_sauvegarde(uuid)` — RPC utilisateur : identité `auth.uid()` lue en interne, appel avec le JWT du soignant.
- **GRANT connu** : `REVOKE ALL … FROM PUBLIC` puis `GRANT ALL … TO "authenticated", "service_role"`.
- **Signature TypeScript** (`types.ts`, section `Functions`) : `Args: { p_id: string }` ; `Returns: Json`.
- **Contrat de réponse** : `{success:true}` (l.60016) ; `{error:'Non authentifié'}` (l.60002, → `.unauthorized`), `{error:'Filtre introuvable'}` (l.60005). Audit `FILTRE_SUPPRIME`. Relecture : ligne absente.
- **Exemple de réponse STAGING** : non exigé.

## fn_definir_disponibilite

- **Statut natif** : à venir (lot 4, T5).
- **Usage prévu** : Grille de 4 semaines depuis le lundi courant (Europe/Paris), créneaux `JOURNEE` et `NUIT` comme le web, jours passés désactivés ; bascule **sans état optimiste** puis relecture PostgREST `disponibilites_soignant` (RLS `dispos_soignant_select` l.77827).
- **Signature SQL** (`supabase/schema/public.sql` l.29712) :

```sql
CREATE OR REPLACE FUNCTION "public"."fn_definir_disponibilite"("p_jour" "date", "p_creneau" "text", "p_disponible" boolean) RETURNS "jsonb"
    LANGUAGE "plpgsql" SECURITY DEFINER
    SET "search_path" TO 'public'
```

- **Classe d'authentification (manifeste)** : `RPC_UTILISATEUR_AUTH_INTERNE` pour `fn_definir_disponibilite(date,text,boolean)` — RPC utilisateur : identité `auth.uid()` lue en interne, appel avec le JWT du soignant.
- **GRANT connu** : `REVOKE ALL … FROM PUBLIC` puis `GRANT ALL … TO "authenticated", "service_role"`.
- **Signature TypeScript** (`types.ts`, section `Functions`) : absente (`types.ts` en retard sur le schéma ; contrat tenu par `public.sql`, `types: null` dans `rpc-contracts.json`).
- **Contrat de réponse** : `{success:true}` (l.29738) ; refus `{error}` seul : `'Profil soignant introuvable'` (l.29720, y compris quand `auth.uid()` est nul), `'Créneau invalide'` (l.29723 ; la RPC admet `JOURNEE`, `MATIN`, `APRES_MIDI`, `NUIT`, l'app n'envoie que `JOURNEE` et `NUIT`), `"La disponibilité doit être entre aujourd'hui et J+90"` (l.29726) — verbatim. La borne `CURRENT_DATE` du serveur fait foi ; le jour est calculé à Paris côté app (vecteurs autour des changements d'heure, T2). Idempotent (`ON CONFLICT DO NOTHING` ou `DELETE`).
- **Exemple de réponse STAGING** : recommandé dans le run T14 (disponibilité posée puis relue).

## fn_obtenir_mes_parrainages

- **Statut natif** : à venir (lot 4, T6).
- **Usage prévu** : Écran Parrainage : filleuls et progression, gains, prime et seuil **serveur** (`fn_param_num('prime_parrainage_eur', 25)`, `fn_param_num('seuil_gmv_parrainage_eur', 500)`, l.45954-45955), `mon_parrain`. Code et `badge_ambassadeur` lus par PostgREST `soignants`.
- **Signature SQL** (`supabase/schema/public.sql` l.45947) :

```sql
CREATE OR REPLACE FUNCTION "public"."fn_obtenir_mes_parrainages"() RETURNS "jsonb"
    LANGUAGE "plpgsql" STABLE SECURITY DEFINER
    SET "search_path" TO 'public'
```

- **Classe d'authentification (manifeste)** : `RPC_UTILISATEUR_AUTH_INTERNE` pour `fn_obtenir_mes_parrainages()` — RPC utilisateur : identité `auth.uid()` lue en interne, appel avec le JWT du soignant.
- **GRANT connu** : `REVOKE ALL … FROM PUBLIC` puis `GRANT ALL … TO "authenticated", "service_role"`.
- **Signature TypeScript** (`types.ts`, section `Functions`) : `Args: never` ; `Returns: Json`.
- **Contrat de réponse** : `{filleuls:[{id, filleul_id, prenom, statut, cree_le, filleul_active_le, commission_cumulee_filleul, gmv_cumule_filleul, reste_gmv_avant_prime, seuil_gmv, seuil_atteint, prime_versee_le, premiere_mission_le, bonus_heures}], total_gains_eur, nb_primes_versees, prime_eur, seuil_gmv_eur, mon_parrain}` (l.45958-45978, `mon_parrain` JSON `null` sans parrain) — pas de `success` ; `{error:'Non authentifié'}` (l.45957) → `.unauthorized`. `seuil_atteint` exige GMV ≥ seuil **et** commission ≥ 4 × prime (l.45965-45966), condition absente du texte web (correction 23). Défaut de prime 25 ici, 50 dans `fn_appliquer_parrainage` (l.19071) : divergence signalée (§6.10 du plan de lot), aucune valeur en dur côté app (le web code « 25€ » / « 500€ »). Le bloc « conditions de la prime » reste sous HARD STOP n°4 (T6-HS).
- **Exemple de réponse STAGING** : non exigé (démo + tests de gateway).

## fn_appliquer_parrainage

- **Statut natif** : à venir (lot 4, T6).
- **Usage prévu** : Application d'un code capté par Universal Link (`?ref=` / `?parrain=`, fenêtre de 30 jours, codes `ETB-` ignorés) au premier `.ready` qui suit la capture (D14), une seule fois par userId et code.
- **Signature SQL** (`supabase/schema/public.sql` l.19059) :

```sql
CREATE OR REPLACE FUNCTION "public"."fn_appliquer_parrainage"("p_code" "text") RETURNS "jsonb"
    LANGUAGE "plpgsql" SECURITY DEFINER
    SET "search_path" TO 'public'
```

- **Classe d'authentification (manifeste)** : `RPC_UTILISATEUR_AUTH_INTERNE` pour `fn_appliquer_parrainage(text)` — RPC utilisateur : identité `auth.uid()` lue en interne, appel avec le JWT du soignant.
- **GRANT connu** : `REVOKE ALL … FROM PUBLIC` puis `GRANT ALL … TO "authenticated", "service_role"`.
- **Signature TypeScript** (`types.ts`, section `Functions`) : `Args: { p_code: string }` ; `Returns: Json`.
- **Contrat de réponse** : succès `{success:true, message}` (l.19115) : le `message` (« Code accepté ! Votre prime de … € sera versée après votre 1ère mission terminée et 100€ de commission encaissée par Jolene. ») contredit la page web et n'est **jamais affiché** (HARD STOP n°4) ; l'app affiche le toast neutre du web « Code de parrainage enregistré. » (`useAppliquerParrainage.ts` l.89) puis relit `fn_obtenir_mes_parrainages` (`mon_parrain` non nul). Refus JSON `{error}` (HTTP 200), définitifs (marqueur « appliqué », comme `useAppliquerParrainage.ts` l.20-25) : `'Code de parrainage invalide'` (l.19080), `'Vous ne pouvez pas vous parrainer vous-même'` (l.19081), `'Le parrain a atteint la limite de 20 filleuls validés'` (l.19083), `'Vous avez déjà appliqué un code de parrainage'` (l.19084) ; non définitifs (code conservé, nouvel essai à la session suivante, web l.71-81) : `'Non authentifié'` (l.19073), `'Compte suspendu, supprimé ou désactivé'` (l.19074), `'Profil soignant introuvable'` (l.19078). Exception PostgREST `'Attribution du parrain non persistée'` (l.19097, `RAISE` sans SQLSTATE, donc `P0001`) : erreur, code conservé.
- **Exemple de réponse STAGING** : non exigé.

## fn_ouvrir_litige_rate_limited

> **Fiche partagée avec le lot 2** (`DECISIONS_LOT4.md`, précision 10). Le T0 du lot 2 (`origin/lot2/l2-t0`,
> `LOT2_PLAN.md` §3 T0) suit cette RPC en `lot: 2` (contestation d'une présence validée,
> `p_type_litige = 'DESACCORD_HEURES_POINTAGE'`, T5b) et pose la fiche de référence, avec une sous-fiche par
> surcharge. Sur une branche sans ce T0, l'en-tête ci-dessous en tient lieu et `RPC_PARTAGEES_LOT4`
> (`scripts/mobile/check-rpc-contracts.mjs`) ajoute l'entrée en `a_venir`, `lot: 4`. **Fusion avec le T0 du
> lot 2, jamais « garder les deux côtés »** : garder l'en-tête et les sous-fiches du lot 2, y déplacer telle
> quelle la sous-section « Usage du lot 4 » ci-dessous, supprimer le reste de cette fiche, puis relancer
> `node scripts/mobile/check-rpc-contracts.mjs --update` ; la garde du lot 4 exige un seul titre
> `## fn_ouvrir_litige_rate_limited` et lit l'usage du lot 4 dans cette sous-section.

- **Statut natif** : à venir (lot 4, T8) tant que l'entrée du lot 2 est absente ; sinon celui de l'entrée du
  lot 2, portée par sa tranche T5b.
- **Signature SQL** (`supabase/schema/public.sql` l.46354, l.46379, l.46568) :

```sql
CREATE OR REPLACE FUNCTION "public"."fn_ouvrir_litige_rate_limited"("p_mission_id" "uuid", "p_motif" "text") RETURNS "jsonb"
    LANGUAGE "plpgsql" SECURITY DEFINER
    SET "search_path" TO 'public'

CREATE OR REPLACE FUNCTION "public"."fn_ouvrir_litige_rate_limited"("p_mission_id" "uuid", "p_type_litige" "public"."type_litige", "p_motif" "text") RETURNS "jsonb"
    LANGUAGE "plpgsql" SECURITY DEFINER
    SET "search_path" TO 'public'

CREATE OR REPLACE FUNCTION "public"."fn_ouvrir_litige_rate_limited"("p_mission_id" "uuid", "p_type_litige" "public"."type_litige", "p_motif" "text", "p_facture_id" "uuid") RETURNS "jsonb"
    LANGUAGE "plpgsql" SECURITY DEFINER
    SET "search_path" TO 'public', 'extensions'
```

- **Classe d'authentification (manifeste)** : `RPC_UTILISATEUR_AUTH_INTERNE` pour `fn_ouvrir_litige_rate_limited(uuid,text)` ; `RPC_UTILISATEUR_AUTH_INTERNE` pour `fn_ouvrir_litige_rate_limited(uuid,type_litige,text)` — RPC utilisateur : identité `auth.uid()` lue en interne, appel avec le JWT du soignant.
- **GRANT connu** : 3 surcharges, chacune : `REVOKE ALL … FROM PUBLIC` puis `GRANT ALL … TO "authenticated", "service_role"`.
- **Signature TypeScript** (`types.ts`, section `Functions`) : déclarée l.10147 en union des surcharges à 2 et 3 arguments (`Args: { p_mission_id: string; p_motif: string }` ou `Args: { p_mission_id: string; p_motif: string; p_type_litige: Database["public"]["Enums"]["type_litige"] }`, `Returns: Json`), forme que `extractTypesSignature` ne lit pas : `types: null` dans `rpc-contracts.json`.
- **Contrat de réponse (HTTP 200)** : succès `{success:true, litige_id, est_informatif, facture_id}` (l.46551-46556) ; refus `{error}` sans `success`, affichés verbatim. Surcharge appelée et refus lus par le lot 4 : sous-section « Usage du lot 4 ».

### Usage du lot 4 (T8, type `AUTRE`)

- **Statut natif (lot 4)** : à venir (lot 4, T8). Aucun statut propre au lot 4 : l'entrée partagée garde celui du lot qui la suit (passage en `consommee` par la tranche T5b du lot 2, ou par T15 du lot 4 si l'entrée est la sienne).
- **Usage prévu** : Ouverture d'un litige de type `AUTRE` sur une mission `EN_COURS` ou `TERMINEE` assignée au soignant (missions contestables = celles-ci moins celles déjà en litige, web l.137-146). L'app appelle **uniquement** la signature canonique à 3 arguments nommés (`p_mission_id`, `p_type_litige = 'AUTRE'`, `p_motif`), équivalente au wrapper déprécié à 2 arguments que le web appelle encore (`LitigesSoignant.tsx` l.172) ; fiche « Surcharges ».
- **Contrat de réponse** : 3 arguments (l.46379) : succès `{success:true, litige_id, est_informatif, facture_id}` (l.46551-46556), `litige_id` exigé (`requiredString`) puis relecture de `litiges` par id ; refus `{error}` **sans** `success` (HTTP 200), affichés verbatim (`RPCResponse.leverSiErreur`) : `'Accès refusé'` (l.46400, non authentifié ou compte inactif), `'Le motif doit contenir entre 10 et 2 000 caractères.'` (l.46405), `'Mission introuvable'` (l.46416), `"Vous n'êtes pas partie prenante de cette mission."` (l.46432), `'Un litige de ce type est déjà ouvert pour cette mission.'` (l.46447), `'Trop de litiges ouverts récemment. Réessayez plus tard.'` (l.46469, `rate_limit_litiges_par_heure`, défaut 3), et deux refus inatteignables avec `AUTRE` : `'Aucune facture contestable (ÉMISE, EN RETARD ou PAYÉE) pour cette mission.'` (l.46488, types facture), `'Fenêtre de contestation fermée pour ce type de litige. Contactez le support.'` (l.46518 ; la fenêtre de `AUTRE` est toujours ouverte, `fn_fenetre_contestation_ouverte` l.36596). Wrapper à 2 arguments (l.46354) : `'Accès refusé'` puis délégation en `AUTRE`. Effets : trigger `dec_litige_48h` (l.75396) sans `RAISE`, audit `LITIGE_OUVERTURE` serveur.
- **Exemple de réponse STAGING** : **obligatoire** dans le run T14 (plan l.209 : litige ouvert et relu ; D20).

## fn_ajouter_message_litige

- **Statut natif** : à venir (lot 4, T8).
- **Usage prévu** : Fil d'un litige : ajout d'un message de 10 caractères au moins ; champ masqué si le litige est résolu (`estResolu`, golden T2). Lecture du fil par PostgREST `messages_litige` (RLS `pol_messages_litige_select` l.79349). Accords amiables et clôture : renvoi web (D9).
- **Signature SQL** (`supabase/schema/public.sql` l.16835) :

```sql
CREATE OR REPLACE FUNCTION "public"."fn_ajouter_message_litige"("p_litige_id" "uuid", "p_contenu" "text") RETURNS "jsonb"
    LANGUAGE "plpgsql" SECURITY DEFINER
    SET "search_path" TO ''
```

- **Classe d'authentification (manifeste)** : `MIXTE_TENANT_ADMIN` pour `fn_ajouter_message_litige(uuid,text)` — Mixte tenant / admin : la fonction distingue en interne soignant, établissement et admin ; appel avec le JWT utilisateur.
- **GRANT connu** : `REVOKE ALL … FROM PUBLIC` puis `GRANT ALL … TO "authenticated", "service_role"`.
- **Signature TypeScript** (`types.ts`, section `Functions`) : `Args: { p_contenu: string; p_litige_id: string }` ; `Returns: Json`.
- **Contrat de réponse** : `{success:true, message_id}` (l.16977-16980) puis relecture du fil ; refus `{error}` : `'Accès refusé'` (l.16848, l.16892), `'Litige introuvable ou accès refusé'` (l.16865), `'Ce litige est clôturé.'` (l.16872, statut hors `OUVERT, EN_DISCUSSION, EN_MEDIATION, MEDIATION_EN_COURS, REVUE_ADMIN`), `'Le message doit contenir entre 10 et 5000 caractères.'` (l.16879) — verbatim. Effet : notification `SYSTEM` à l'établissement (titres serveur).
- **Exemple de réponse STAGING** : recommandé dans le run T14 (message relu dans le fil du litige ouvert).

## fn_soumettre_reclamation

- **Statut natif** : à venir (lot 4, T8).
- **Usage prévu** : Réclamation générale (onglet `?tab=reclamations` de `/soignant/litiges`) : catégorie dans la liste fermée du web (`MISSION`, `PAIEMENT`, `TECHNIQUE`, `COMPORTEMENT`, `AUTRE`, `MesReclamations.tsx` l.22-28), sujet, détails, mission optionnelle. Liste par PostgREST `reclamations` (RLS `reclamations_select_own` l.79820).
- **Signature SQL** (`supabase/schema/public.sql` l.57403) :

```sql
CREATE OR REPLACE FUNCTION "public"."fn_soumettre_reclamation"("p_categorie" "text", "p_sujet" "text", "p_details" "text", "p_mission_id" "uuid" DEFAULT NULL::"uuid") RETURNS "jsonb"
    LANGUAGE "plpgsql" SECURITY DEFINER
    SET "search_path" TO 'public'
```

- **Classe d'authentification (manifeste)** : `RPC_UTILISATEUR_AUTH_INTERNE` pour `fn_soumettre_reclamation(text,text,text,uuid)` — RPC utilisateur : identité `auth.uid()` lue en interne, appel avec le JWT du soignant.
- **GRANT connu** : `REVOKE ALL … FROM PUBLIC` puis `GRANT ALL … TO "authenticated", "service_role"`.
- **Signature TypeScript** (`types.ts`, section `Functions`) : `Args: { p_categorie: string; p_details: string; p_mission_id?: string; p_sujet: string }` ; `Returns: Json`.
- **Contrat de réponse** : succès `{id, statut:'EN_ATTENTE'}` (l.57406) — **ni `success` ni `ok`** : succès = `requiredString("id")` puis relecture de `reclamations` (`estSucces` est faux ici). Refus `{error}` : `'Non authentifié'` → `.unauthorized` ; `'Rôle non autorisé'` (rôle lu dans `raw_app_meta_data.role` : compte legacy sans rôle, à recenser sur STAGING) verbatim. Catégorie hors liste : exception PostgREST `23514` (`reclamations_categorie_check`, `public.sql` l.71443), libellé générique, jamais « session expirée ». Audit `RECLAMATION_CREEE` serveur.
- **Exemple de réponse STAGING** : non exigé.

## fn_mon_breakdown_actuel

- **Statut natif** : à venir (lot 4, T9).
- **Usage prévu** : Page « Mon score » : dernier calcul `scoring_breakdown` du soignant.
- **Signature SQL** (`supabase/schema/public.sql` l.44525) :

```sql
CREATE OR REPLACE FUNCTION "public"."fn_mon_breakdown_actuel"() RETURNS "jsonb"
    LANGUAGE "plpgsql" STABLE SECURITY DEFINER
    SET "search_path" TO 'public', 'extensions'
```

- **Classe d'authentification (manifeste)** : `RPC_UTILISATEUR_AUTH_INTERNE` pour `fn_mon_breakdown_actuel()` — RPC utilisateur : identité `auth.uid()` lue en interne, appel avec le JWT du soignant.
- **GRANT connu** : `REVOKE ALL … FROM PUBLIC` puis `GRANT ALL … TO "authenticated", "service_role"`.
- **Signature TypeScript** (`types.ts`, section `Functions`) : `Args: never` ; `Returns: Json`.
- **Contrat de réponse** : ligne `scoring_breakdown` complète en JSON (`to_jsonb(b.*)`, l.44534) ou `{}` sans calcul (l.44536) ; `{error:'Non authentifié'}` (l.44533) → `.unauthorized`. Décodage tolérant, valeurs affichées telles quelles (aucun barème client).
- **Exemple de réponse STAGING** : non exigé.

## fn_mes_evenements_score

- **Statut natif** : à venir (lot 4, T9).
- **Usage prévu** : Événements de score des 12 derniers mois (`p_limit = 20` comme le web) ; base de la contestation (`fn_creer_reclamation_score`).
- **Signature SQL** (`supabase/schema/public.sql` l.41672) :

```sql
CREATE OR REPLACE FUNCTION "public"."fn_mes_evenements_score"("p_limit" integer DEFAULT 20) RETURNS "jsonb"
    LANGUAGE "plpgsql" STABLE SECURITY DEFINER
    SET "search_path" TO 'public'
```

- **Classe d'authentification (manifeste)** : `RPC_UTILISATEUR_AUTH_INTERNE` pour `fn_mes_evenements_score(integer)` — RPC utilisateur : identité `auth.uid()` lue en interne, appel avec le JWT du soignant.
- **GRANT connu** : `REVOKE ALL … FROM PUBLIC` puis `GRANT ALL … TO "authenticated", "service_role"`.
- **Signature TypeScript** (`types.ts`, section `Functions`) : `Args: { p_limit?: number }` ; `Returns: Json`.
- **Contrat de réponse** : `{success:true, type:'SOIGNANT', events:[{id, type_evenement, points, points_corriges, motif, contestable, decision_admin, cree_le, mission_id}]}` (l.41686-41700) — clé **`events`** (le web lit `evenements` et n'affiche rien, correction 16) ; `contestable` est calculé serveur (`contestable AND decision_admin IS NULL AND reclamation_id IS NULL`, l.41689), la réponse ne porte aucun champ `reclamation`. `{success:false, error:'Non authentifié'}` (l.41682) → `.unauthorized` ; `{success:false, error:'Profil non identifié'}` (l.41722) verbatim. Une réponse `type:'ETAB'` (l.41719) est inattendue pour un soignant → `.contract`.
- **Exemple de réponse STAGING** : recommandé dans le run T14 : l'app est le premier client réel de la contestation.

## fn_evolution_score_soignant

- **Statut natif** : à venir (lot 4, T9).
- **Usage prévu** : Graphique d’évolution de « Mon score » (`GraphiqueEvolutionScore`, `PageScoreSoignant.tsx` l.166), `p_limit = 6` comme le web (`GraphiqueEvolutionScore.tsx` l.27).
- **Signature SQL** (`supabase/schema/public.sql` l.35523) :

```sql
CREATE OR REPLACE FUNCTION "public"."fn_evolution_score_soignant"("p_limit" integer DEFAULT 6) RETURNS "jsonb"
    LANGUAGE "plpgsql" STABLE SECURITY DEFINER
    SET "search_path" TO 'public', 'extensions'
```

- **Classe d'authentification (manifeste)** : `RPC_UTILISATEUR_AUTH_INTERNE` pour `fn_evolution_score_soignant(integer)` — RPC utilisateur : identité `auth.uid()` lue en interne, appel avec le JWT du soignant.
- **GRANT connu** : `REVOKE ALL … FROM PUBLIC` puis `GRANT ALL … TO "authenticated", "service_role"`.
- **Signature TypeScript** (`types.ts`, section `Functions`) : `Args: { p_limit?: number }` ; `Returns: Json`.
- **Contrat de réponse** : tableau `[{mois:'YYYY-MM', score, niveau, cree_le}]` trié par mois (l.35535-35538), un point par mois, limite bornée 1-50 ; non authentifié : **objet** `{error:'Non authentifié'}` (l.35532) au lieu d'un tableau → `.unauthorized` (le décodeur accepte les deux formes).
- **Exemple de réponse STAGING** : non exigé.

## fn_lister_notations_recues

- **Statut natif** : à venir (lot 4, T9).
- **Usage prévu** : Notations reçues affichées sur « Mon score » ; lecture double-aveugle (fiche « Jamais `notations_missions` … »).
- **Signature SQL** (`supabase/schema/public.sql` l.40284) :

```sql
CREATE OR REPLACE FUNCTION "public"."fn_lister_notations_recues"("p_limit" integer DEFAULT 20) RETURNS "jsonb"
    LANGUAGE "plpgsql" STABLE SECURITY DEFINER
    SET "search_path" TO 'public', 'extensions'
```

- **Classe d'authentification (manifeste)** : `RPC_UTILISATEUR_AUTH_INTERNE` pour `fn_lister_notations_recues(integer)` — RPC utilisateur : identité `auth.uid()` lue en interne, appel avec le JWT du soignant.
- **GRANT connu** : `REVOKE ALL … FROM PUBLIC` puis `GRANT ALL … TO "authenticated", "service_role"`.
- **Signature TypeScript** (`types.ts`, section `Functions`) : `Args: { p_limit?: number }` ; `Returns: Json`.
- **Contrat de réponse** : tableau `[{id, mission_id, mission_intitule, mission_fin_le, critere_1, critere_2, critere_3, critere_4, note_moyenne, commentaire, cree_le}]` (l.40308-40320), filtré `masque = false AND publie_le IS NOT NULL` (l.40324-40325) ; `{error:'Non authentifié'}` (l.40305) → `.unauthorized`. Le `LIMIT` est appliqué **après** `jsonb_agg` (l.40326) et n'a donc aucun effet : la liste peut dépasser `p_limit` (point ouvert du plan de lot §6.10) ; l'app tronque à l'affichage, aucune moyenne recalculée.
- **Exemple de réponse STAGING** : recommandé dans le run T14 (double-aveugle : notation N1 publiée visible, N2 non publiée absente).

## fn_creer_reclamation_score

- **Statut natif** : à venir (lot 4, T9).
- **Usage prévu** : Contestation d'un événement `contestable` : `p_evenement_type = 'SOIGNANT'`, motif parmi `URGENCE_MEDICALE`, `DEUIL`, `FORCE_MAJEURE`, `ERREUR_JOLENE`, `CONTEXTE_PARTICULIER`, `AUTRE`, texte de 20 caractères au moins ; **`p_justificatif_storage_path` n'est jamais envoyé** (D10 : données de santé, `docs/CONFORMITE.md` §1.2, garde-fou 8 ; sous-ligne « justificatif : renvoi web assumé »).
- **Signature SQL** (`supabase/schema/public.sql` l.27482) :

```sql
CREATE OR REPLACE FUNCTION "public"."fn_creer_reclamation_score"("p_evenement_id" "uuid", "p_evenement_type" "text", "p_motif_categorie" "text", "p_texte_libre" "text", "p_justificatif_storage_path" "text" DEFAULT NULL::"text") RETURNS "jsonb"
    LANGUAGE "plpgsql" SECURITY DEFINER
    SET "search_path" TO 'public'
```

- **Classe d'authentification (manifeste)** : `RPC_UTILISATEUR_AUTH_INTERNE` pour `fn_creer_reclamation_score(uuid,text,text,text,text)` — RPC utilisateur : identité `auth.uid()` lue en interne, appel avec le JWT du soignant.
- **GRANT connu** : `REVOKE ALL … FROM PUBLIC` puis `GRANT ALL … TO "authenticated", "service_role"`.
- **Signature TypeScript** (`types.ts`, section `Functions`) : `Args: { p_evenement_id: string; p_evenement_type: string; p_justificatif_storage_path?: string; p_motif_categorie: string; p_texte_libre: string }` ; `Returns: Json`.
- **Contrat de réponse** : `{success:true, reclamation_id, statut:'PENDING'}` (l.27601) puis relecture des événements (`contestable == false`) ; refus `{success:false, error_code, error?}` (l.27494-27554), `error` affiché verbatim, `error_code` pour la logique : `'NON_AUTHENTIFIE'` (sans `error`, → `.unauthorized`), `'TYPE_INVALIDE'` (`'evenement_type doit être SOIGNANT ou ETAB'`), `'MOTIF_INVALIDE'` (`'Motif catégorie invalide'`), `'TEXTE_REQUIS'` (`'Texte libre obligatoire (min 20 caractères)'`), `'EVENT_INTROUVABLE'` (`'Événement de score introuvable'`), `'NON_AUTORISE'` (« Vous n'êtes pas concerné par cet événement »), `'NON_CONTESTABLE'` (« Cet événement n'est pas contestable »), `'DEJA_TRAITE'` (`'Cet événement a déjà été traité par un admin'`), `'RECLAMATION_EN_COURS'` (`'Une réclamation est déjà ouverte pour cet événement'`, avec `reclamation_id`). Effets : `externalisation_actions` `EMAIL_NOTIF` vers l'admin, audit `SYSTEM` `RECLAMATION_SCORE_CREEE`.
- **Exemple de réponse STAGING** : recommandé dans le run T14.

## fn_mes_notations_recues_avec_stats

- **Statut natif** : à venir (lot 4, T9).
- **Usage prévu** : Écran Évaluations : statistiques globales, évolution sur 6 mois (Swift Charts), filtres période (`TOUT`, `3M`, `6M`, `12M`), note minimale et établissement, pagination de 20 (`p_limit = 20`, `p_offset`), lecture seule (édition non portée, D11) ; lecture double-aveugle (fiche dédiée).
- **Signature SQL** (`supabase/schema/public.sql` l.42039) :

```sql
CREATE OR REPLACE FUNCTION "public"."fn_mes_notations_recues_avec_stats"("p_periode" "text" DEFAULT 'TOUT'::"text", "p_note_min" integer DEFAULT NULL::integer, "p_etablissement_id" "uuid" DEFAULT NULL::"uuid", "p_limit" integer DEFAULT 50, "p_offset" integer DEFAULT 0) RETURNS "jsonb"
    LANGUAGE "plpgsql" STABLE SECURITY DEFINER
    SET "search_path" TO 'public', 'extensions'
```

- **Classe d'authentification (manifeste)** : `RPC_UTILISATEUR_AUTH_INTERNE` pour `fn_mes_notations_recues_avec_stats(text,integer,uuid,integer,integer)` — RPC utilisateur : identité `auth.uid()` lue en interne, appel avec le JWT du soignant.
- **GRANT connu** : `REVOKE ALL … FROM PUBLIC` puis `GRANT ALL … TO "authenticated", "service_role"`.
- **Signature TypeScript** (`types.ts`, section `Functions`) : `Args: { p_etablissement_id?: string; p_limit?: number; p_note_min?: number; p_offset?: number; p_periode?: string }` ; `Returns: Json`.
- **Contrat de réponse** : `{success:true, total, limit, offset, notations:[{id, mission_id, mission_intitule, mission_fin_le, etablissement_id, etablissement_nom, critere_1, critere_2, critere_3, critere_4, note_moyenne, commentaire, signale, cree_le}], stats:{note_moyenne_globale, total_evaluations, pct_5_etoiles}, evolution_6m:[{mois, note_moyenne, nb}], etabs_disponibles:[{id, nom}]}` (l.42088-42176) ; `{success:false, error_code:'NON_AUTHENTIFIE'}` (l.42065) → `.unauthorized`. Les cinq lectures de `notations_missions` filtrent `masque = false AND publie_le IS NOT NULL` (l.42081-42082, l.42114-42115, l.42133, l.42149-42150, l.42162). Aucune moyenne recalculée côté app.
- **Exemple de réponse STAGING** : recommandé dans le run T14 (double-aveugle N1 / N2).

## fn_signaler_notation

- **Statut natif** : à venir (lot 4, T9).
- **Usage prévu** : Signalement d'une notation reçue, motif de 10 caractères au moins côté app (web `EvaluationsSoignant.tsx` l.458).
- **Signature SQL** (`supabase/schema/public.sql` l.56216) :

```sql
CREATE OR REPLACE FUNCTION "public"."fn_signaler_notation"("p_notation_id" "uuid", "p_motif" "text" DEFAULT NULL::"text") RETURNS "jsonb"
    LANGUAGE "plpgsql" SECURITY DEFINER
    SET "search_path" TO 'public', 'extensions'
```

- **Classe d'authentification (manifeste)** : `RPC_UTILISATEUR_AUTH_INTERNE` pour `fn_signaler_notation(uuid,text)` — RPC utilisateur : identité `auth.uid()` lue en interne, appel avec le JWT du soignant.
- **GRANT connu** : `REVOKE ALL … FROM PUBLIC` puis `GRANT ALL … TO "authenticated", "service_role"`.
- **Signature TypeScript** (`types.ts`, section `Functions`) : `Args: { p_motif?: string; p_notation_id: string }` ; `Returns: Json`.
- **Contrat de réponse** : `{success:true}` (l.56267) puis relecture de la page (`signale == true`) ; refus `{success:false, error}` : `'Non authentifié'` (l.56227, → `.unauthorized`), `'Compte suspendu, supprimé ou désactivé'` (l.56231), `'Vous ne pouvez signaler que les notations vous concernant'` (l.56243), `'Notation déjà signalée'` (l.56247) — verbatim. Exception PostgREST `P0001` `'Le signalement n’a pas pu être enregistré. Veuillez réessayer.'` (l.56264 : audit non écrit, transaction annulée) : message serveur restitué, jamais « session expirée ».
- **Exemple de réponse STAGING** : non exigé.

## fn_lister_conversations_messagerie

- **Statut natif** : à venir (lot 4, T7a).
- **Usage prévu** : Liste des conversations : pagination keyset par 100 comme le web (`PageMessagerie.tsx` l.184-216), onglets actives et archivées (`archived_at`), arrêt si le curseur ne change pas ; relue sur INSERT `messages_chat` d'une conversation inconnue (pas d'abonnement `conversations`).
- **Signature SQL** (`supabase/schema/public.sql` l.39736) :

```sql
CREATE OR REPLACE FUNCTION "public"."fn_lister_conversations_messagerie"("p_avant" timestamp with time zone DEFAULT NULL::timestamp with time zone, "p_avant_id" "uuid" DEFAULT NULL::"uuid", "p_limite" integer DEFAULT 100) RETURNS TABLE("id" "uuid", "participant_1_id" "uuid", "participant_2_id" "uuid", "mission_id" "uuid", "etablissement_id" "uuid", "soignant_id" "uuid", "dernier_message_le" timestamp with time zone, "cree_le" timestamp with time zone, "archived_at" timestamp with time zone, "autre_id" "uuid", "dernier_contenu" "text", "non_lus" bigint, "mission_intitule" "text", "ordre_le" timestamp with time zone)
    LANGUAGE "plpgsql" SECURITY DEFINER
    SET "search_path" TO ''
```

- **Classe d'authentification (manifeste)** : `MIXTE_TENANT_ADMIN` pour `fn_lister_conversations_messagerie(timestamp with time zone,uuid,integer)` — Mixte tenant / admin : la fonction distingue en interne soignant, établissement et admin ; appel avec le JWT utilisateur.
- **GRANT connu** : `REVOKE ALL … FROM PUBLIC` puis `GRANT ALL … TO "authenticated"` (pas de `service_role`).
- **Signature TypeScript** (`types.ts`, section `Functions`) : absente (`types.ts` en retard sur le schéma ; contrat tenu par `public.sql`, `types: null` dans `rpc-contracts.json`).
- **Contrat de réponse** : `TABLE(id, participant_1_id, participant_2_id, mission_id, etablissement_id, soignant_id, dernier_message_le, cree_le, archived_at, autre_id, dernier_contenu, non_lus bigint, mission_intitule, ordre_le)` (l.39736) triée par `(ordre_le, id)` décroissant ; curseur suivant = `(p_avant: ordre_le, p_avant_id: id)` de la dernière ligne. `autre_id` = interlocuteur opérationnel de l'établissement pour le soignant (`private.fn_interlocuteur_operationnel_id`, l.39785-39786) : cible du blocage. `non_lus` sert à l'affichage par conversation seulement (badge = `fn_messages_non_lus`). Exceptions PostgREST : `'Non authentifié'` `28000` (l.39748, aussi compte inactif) → `.unauthorized` ; `'Curseur incomplet'` `22023` (l.39751, un seul des deux paramètres) → défaut client, `.contract`.
- **Exemple de réponse STAGING** : **obligatoire** dans le run T14 (conversation de la fixture D4 listée, D20).

## fn_interlocuteurs_conversations

- **Statut natif** : à venir (lot 4, T7a).
- **Usage prévu** : Noms et avatars des interlocuteurs des conversations chargées (100 identifiants au plus par appel, une page).
- **Signature SQL** (`supabase/schema/public.sql` l.38738) :

```sql
CREATE OR REPLACE FUNCTION "public"."fn_interlocuteurs_conversations"("p_conversation_ids" "uuid"[]) RETURNS TABLE("conversation_id" "uuid", "participant_id" "uuid", "prenom" "text", "nom" "text", "avatar_url" "text", "est_jolene" boolean)
    LANGUAGE "plpgsql" SECURITY DEFINER
    SET "search_path" TO ''
```

- **Classe d'authentification (manifeste)** : `RPC_UTILISATEUR_AUTH_INTERNE` pour `fn_interlocuteurs_conversations(uuid[])` — RPC utilisateur : identité `auth.uid()` lue en interne, appel avec le JWT du soignant.
- **GRANT connu** : `REVOKE ALL … FROM PUBLIC` puis `GRANT ALL … TO "authenticated"` (pas de `service_role`).
- **Signature TypeScript** (`types.ts`, section `Functions`) : `Args: { p_conversation_ids: string[] }` ; `Returns: { avatar_url: string | null; conversation_id: string; est_jolene: boolean; nom: string; participant_id: string; prenom: string }[]`.
- **Contrat de réponse** : `TABLE(conversation_id, participant_id, prenom, nom, avatar_url, est_jolene)` (l.38738), deux lignes par conversation au plus ; un établissement est rendu avec `prenom` = nom de l'établissement, `nom` vide, `avatar_url` = logo ; ni soignant ni établissement → `prenom` = `'Jolene'`, `est_jolene:true` (l.38795-38802). Liste vide → aucune ligne (l.38751-38752). Exceptions : `'Non authentifié'` `28000` (l.38746) → `.unauthorized` ; `'Compte inactif'` `42501` (l.38749) → refus métier connu, jamais « session expirée » ; `'Trop de conversations demandées'` `22023` (l.38755, plus de 100 identifiants) → défaut client, `.contract`.
- **Exemple de réponse STAGING** : obligatoire dans le run T14 (nom de l’établissement de fixture relu).

## fn_marquer_messages_lus

- **Statut natif** : à venir (lot 4, T7a).
- **Usage prévu** : À l'ouverture du fil puis à chaque INSERT entrant fil ouvert (web l.381, l.404), suivi d'une relecture du badge `fn_messages_non_lus`.
- **Signature SQL** (`supabase/schema/public.sql` l.41278) :

```sql
CREATE OR REPLACE FUNCTION "public"."fn_marquer_messages_lus"("p_conversation_id" "uuid") RETURNS "void"
    LANGUAGE "plpgsql" SECURITY DEFINER
    SET "search_path" TO ''
```

- **Classe d'authentification (manifeste)** : `MIXTE_TENANT_ADMIN` pour `fn_marquer_messages_lus(uuid)` — Mixte tenant / admin : la fonction distingue en interne soignant, établissement et admin ; appel avec le JWT utilisateur.
- **GRANT connu** : `REVOKE ALL … FROM PUBLIC` puis `GRANT ALL … TO "authenticated"` (pas de `service_role`).
- **Signature TypeScript** (`types.ts`, section `Functions`) : `Args: { p_conversation_id: string }` ; `Returns: undefined`.
- **Contrat de réponse** : `void` (aucun corps) ; exceptions : `'Non authentifié'` `28000` (l.41288) → `.unauthorized` ; `'Accès refusé'` `42501` (l.41295 conversation inexistante ; l.41325 et l.41333 relation non partagée ; l.41341 relation de messagerie non autorisée) → issue `accesRefuse`, conversation retirée de la liste après relecture, **jamais** de déconnexion.
- **Exemple de réponse STAGING** : obligatoire dans le run T14 (message du pair marqué lu, relu en SQL).

## fn_messages_non_lus

- **Statut natif** : à venir (lot 4, T7b).
- **Usage prévu** : Badge du bouton Messages de la barre de navigation (correction 19, `src/hooks/useMessagesNonLus.ts` l.13, l.38) ; relu au premier plan, après chaque `fn_marquer_messages_lus` et à chaque INSERT entrant.
- **Signature SQL** (`supabase/schema/public.sql` l.42496) :

```sql
CREATE OR REPLACE FUNCTION "public"."fn_messages_non_lus"() RETURNS integer
    LANGUAGE "sql" SECURITY DEFINER
    SET "search_path" TO ''
```

- **Classe d'authentification (manifeste)** : `RPC_UTILISATEUR_AUTH_INTERNE` pour `fn_messages_non_lus()` — RPC utilisateur : identité `auth.uid()` lue en interne, appel avec le JWT du soignant.
- **GRANT connu** : `REVOKE ALL … FROM PUBLIC` puis `GRANT ALL … TO "authenticated"` (pas de `service_role`).
- **Signature TypeScript** (`types.ts`, section `Functions`) : `Args: never` ; `Returns: number`.
- **Contrat de réponse** : `integer` nu (l.42496, `LANGUAGE sql`) : messages non lus des autres participants, conversations archivées exclues (`archived_at IS NULL`, l.42503) ; aucune erreur (`auth.uid()` nul → 0).
- **Exemple de réponse STAGING** : recommandé dans le run T14.

## fn_typing_start

- **Statut natif** : à venir (lot 4, T7a).
- **Usage prévu** : Indicateur de saisie tant que le fil est ouvert ; arrêt par `fn_typing_stop`.
- **Signature SQL** (`supabase/schema/public.sql` l.64354) :

```sql
CREATE OR REPLACE FUNCTION "public"."fn_typing_start"("p_conversation_id" "uuid") RETURNS "void"
    LANGUAGE "plpgsql" SECURITY DEFINER
    SET "search_path" TO ''
```

- **Classe d'authentification (manifeste)** : `RPC_UTILISATEUR_AUTH_INTERNE` pour `fn_typing_start(uuid)` — RPC utilisateur : identité `auth.uid()` lue en interne, appel avec le JWT du soignant.
- **GRANT connu** : `REVOKE ALL … FROM PUBLIC` puis `GRANT ALL … TO "authenticated"` (pas de `service_role`).
- **Signature TypeScript** (`types.ts`, section `Functions`) : `Args: { p_conversation_id: string }` ; `Returns: undefined`.
- **Contrat de réponse** : `void` ; exceptions : `'NON_AUTHENTIFIE'` `28000` (l.64362) → `.unauthorized` ; `'NON_AUTORISE'` `42501` (l.64370 : conversation inaccessible ou écriture interdite) → refus métier connu, indicateur abandonné sans message, jamais « session expirée ». Effet : upsert `typing_status` (Realtime).
- **Exemple de réponse STAGING** : non exigé (indicateur observé en démo et sur appareil).

## fn_typing_stop

- **Statut natif** : à venir (lot 4, T7a).
- **Usage prévu** : Fin de l’indicateur de saisie (envoi, champ vidé, fil fermé).
- **Signature SQL** (`supabase/schema/public.sql` l.64391) :

```sql
CREATE OR REPLACE FUNCTION "public"."fn_typing_stop"("p_conversation_id" "uuid") RETURNS "void"
    LANGUAGE "plpgsql" SECURITY DEFINER
    SET "search_path" TO ''
```

- **Classe d'authentification (manifeste)** : `RPC_UTILISATEUR_AUTH_INTERNE` pour `fn_typing_stop(uuid)` — RPC utilisateur : identité `auth.uid()` lue en interne, appel avec le JWT du soignant.
- **GRANT connu** : `REVOKE ALL … FROM PUBLIC` puis `GRANT ALL … TO "authenticated"` (pas de `service_role`).
- **Signature TypeScript** (`types.ts`, section `Functions`) : `Args: { p_conversation_id: string }` ; `Returns: undefined`.
- **Contrat de réponse** : `void` ; aucune erreur (retour silencieux si non authentifié, l.64398-64399) ; supprime la ligne `typing_status` de l'appelant.
- **Exemple de réponse STAGING** : non exigé.

## fn_update_presence

- **Statut natif** : à venir (lot 4, T7a).
- **Usage prévu** : Battement de présence toutes les 30 s tant que le fil est visible (web `useConversationRealtime.ts` l.42, l.191-210) ; le premier battement part **après** le `subscribeWithError()` réussi du canal du fil (signal du pair STAGING, T14).
- **Signature SQL** (`supabase/schema/public.sql` l.64443) :

```sql
CREATE OR REPLACE FUNCTION "public"."fn_update_presence"() RETURNS "void"
    LANGUAGE "plpgsql" SECURITY DEFINER
    SET "search_path" TO ''
```

- **Classe d'authentification (manifeste)** : `RPC_UTILISATEUR_AUTH_INTERNE` pour `fn_update_presence()` — RPC utilisateur : identité `auth.uid()` lue en interne, appel avec le JWT du soignant.
- **GRANT connu** : `REVOKE ALL … FROM PUBLIC` puis `GRANT ALL … TO "authenticated"` (pas de `service_role`).
- **Signature TypeScript** (`types.ts`, section `Functions`) : `Args: never` ; `Returns: undefined`.
- **Contrat de réponse** : `void` ; exception `'NON_AUTHENTIFIE'` `28000` (l.64451) → `.unauthorized`. Effet : upsert `presence_status` à `ONLINE` (Realtime).
- **Exemple de réponse STAGING** : obligatoire dans le run T14 (signal du pair établissement).

## fn_est_bloque

- **Statut natif** : à venir (lot 4, T7b).
- **Usage prévu** : État du bouton « Bloquer / Débloquer » de l'interlocuteur (`autre_id`, masqué pour Jolene), comme le web `PageMessagerie.tsx` l.703-712.
- **Signature SQL** (`supabase/schema/public.sql` l.34695) :

```sql
CREATE OR REPLACE FUNCTION "public"."fn_est_bloque"("p_cible_id" "uuid") RETURNS boolean
    LANGUAGE "sql" STABLE SECURITY DEFINER
    SET "search_path" TO 'public'
```

- **Classe d'authentification (manifeste)** : `RPC_UTILISATEUR_AUTH_INTERNE` pour `fn_est_bloque(uuid)` — RPC utilisateur : identité `auth.uid()` lue en interne, appel avec le JWT du soignant.
- **GRANT connu** : `REVOKE ALL … FROM PUBLIC` puis `GRANT ALL … TO "authenticated", "service_role"`.
- **Signature TypeScript** (`types.ts`, section `Functions`) : absente (`types.ts` en retard sur le schéma ; contrat tenu par `public.sql`, `types: null` dans `rpc-contracts.json`).
- **Contrat de réponse** : `boolean` nu (l.34695-34700, `LANGUAGE sql`) : vrai si l'appelant a bloqué la cible ; aucune erreur (`auth.uid()` nul → faux).
- **Exemple de réponse STAGING** : non exigé.

## fn_bloquer_utilisateur

- **Statut natif** : à venir (lot 4, T7b).
- **Usage prévu** : Blocage de l'interlocuteur (Apple 1.2) ; textes de la feuille repris verbatim du web (`BloquerUtilisateur.tsx` l.36-63), relecture HARD STOP n°4.
- **Signature SQL** (`supabase/schema/public.sql` l.20927) :

```sql
CREATE OR REPLACE FUNCTION "public"."fn_bloquer_utilisateur"("p_cible_id" "uuid", "p_motif" "text" DEFAULT NULL::"text") RETURNS "jsonb"
    LANGUAGE "plpgsql" SECURITY DEFINER
    SET "search_path" TO 'public'
```

- **Classe d'authentification (manifeste)** : `RPC_UTILISATEUR_AUTH_INTERNE` pour `fn_bloquer_utilisateur(uuid,text)` — RPC utilisateur : identité `auth.uid()` lue en interne, appel avec le JWT du soignant.
- **GRANT connu** : `REVOKE ALL … FROM PUBLIC` puis `GRANT ALL … TO "authenticated", "service_role"`.
- **Signature TypeScript** (`types.ts`, section `Functions`) : absente (`types.ts` en retard sur le schéma ; contrat tenu par `public.sql`, `types: null` dans `rpc-contracts.json`).
- **Contrat de réponse** : `{success:true}` (l.20940) ; refus `{error}` : `'Non authentifié'` (l.20933, → `.unauthorized`), `'Cible invalide.'` (l.20935, cible nulle ou soi-même). Upsert `utilisateurs_bloques` (le motif est remplacé). Relecture : `fn_est_bloque == true`.
- **Exemple de réponse STAGING** : non exigé.

## fn_debloquer_utilisateur

- **Statut natif** : à venir (lot 4, T7b).
- **Usage prévu** : Déblocage de l’interlocuteur.
- **Signature SQL** (`supabase/schema/public.sql` l.28068) :

```sql
CREATE OR REPLACE FUNCTION "public"."fn_debloquer_utilisateur"("p_cible_id" "uuid") RETURNS "jsonb"
    LANGUAGE "plpgsql" SECURITY DEFINER
    SET "search_path" TO 'public'
```

- **Classe d'authentification (manifeste)** : `RPC_UTILISATEUR_AUTH_INTERNE` pour `fn_debloquer_utilisateur(uuid)` — RPC utilisateur : identité `auth.uid()` lue en interne, appel avec le JWT du soignant.
- **GRANT connu** : `REVOKE ALL … FROM PUBLIC` puis `GRANT ALL … TO "authenticated", "service_role"`.
- **Signature TypeScript** (`types.ts`, section `Functions`) : absente (`types.ts` en retard sur le schéma ; contrat tenu par `public.sql`, `types: null` dans `rpc-contracts.json`).
- **Contrat de réponse** : `{success:true}` (l.28076), y compris si rien n'était bloqué ; `{error:'Non authentifié'}` (l.28074) → `.unauthorized`. Relecture : `fn_est_bloque == false`.
- **Exemple de réponse STAGING** : non exigé.

## fn_signaler_utilisateur

- **Statut natif** : à venir (lot 4, T7b).
- **Usage prévu** : « Signaler » depuis la messagerie (ajout natif assumé, Apple 1.2) et depuis le détail de mission (correction 20) : cible = `etablissement_id` de la conversation ou de la mission avec `p_cible_type = 'ETABLISSEMENT'` (comme `DetailMissionSoignant.tsx` l.1175), catégories et textes du web (`SignalerUtilisateur.tsx` l.6-45), motif de 10 caractères au moins, `p_mission_id` quand il existe.
- **Signature SQL** (`supabase/schema/public.sql` l.56275) :

```sql
CREATE OR REPLACE FUNCTION "public"."fn_signaler_utilisateur"("p_cible_id" "uuid", "p_cible_type" "text", "p_categorie" "text", "p_motif" "text", "p_mission_id" "uuid" DEFAULT NULL::"uuid") RETURNS "jsonb"
    LANGUAGE "plpgsql" SECURITY DEFINER
    SET "search_path" TO 'public'
```

- **Classe d'authentification (manifeste)** : `MIXTE_TENANT_ADMIN` pour `fn_signaler_utilisateur(uuid,text,text,text,uuid)` — Mixte tenant / admin : la fonction distingue en interne soignant, établissement et admin ; appel avec le JWT utilisateur.
- **GRANT connu** : `REVOKE ALL … FROM PUBLIC` puis `GRANT ALL … TO "authenticated", "service_role"`.
- **Signature TypeScript** (`types.ts`, section `Functions`) : `Args: { p_categorie: string; p_cible_id: string; p_cible_type: string; p_mission_id?: string; p_motif: string }` ; `Returns: Json`.
- **Contrat de réponse** : `{success:true, signalement_id}` (l.56304) ; refus `{success:false, error}` (l.56285-56292), verbatim : `'Non authentifié'` (→ `.unauthorized`), `'Cible invalide'`, `'Catégorie invalide'` (hors `COMPORTEMENT_INAPPROPRIE, FRAUDE_SUSPECTEE, FAUX_DOCUMENT, NON_PROFESSIONNALISME, SECURITE_DANGER, USURPATION_IDENTITE, AUTRE`), `'Motif obligatoire (10 caractères minimum).'`, `'Vous ne pouvez pas vous signaler vous-même.'`, `'Profil signaleur inconnu'`. Effets : notification `SYSTEM` à chaque administrateur plateforme, audit `SIGNALEMENT_UTILISATEUR`. Pas de relecture (aucune lecture de `signalements` portée) : succès = `signalement_id` présent.
- **Exemple de réponse STAGING** : non exigé.

## fn_user_id_pour_etablissement

- **Statut natif** : à venir (lot 4, T7b).
- **Usage prévu** : Première étape de « Écrire à l'établissement » depuis le détail d'une mission `ASSIGNEE`, `EN_COURS`, `TERMINEE`, `ABSENCE` ou `LITIGE` (correction 20, D25, `src/hooks/useOuvrirConversation.ts` l.10-16) : résout l'interlocuteur opérationnel de l'établissement.
- **Signature SQL** (`supabase/schema/public.sql` l.64699) :

```sql
CREATE OR REPLACE FUNCTION "public"."fn_user_id_pour_etablissement"("p_etablissement_id" "uuid") RETURNS "uuid"
    LANGUAGE "plpgsql" STABLE SECURITY DEFINER
    SET "search_path" TO ''
```

- **Classe d'authentification (manifeste)** : `MIXTE_TENANT_ADMIN` pour `fn_user_id_pour_etablissement(uuid)` — Mixte tenant / admin : la fonction distingue en interne soignant, établissement et admin ; appel avec le JWT utilisateur.
- **GRANT connu** : `REVOKE ALL … FROM PUBLIC` puis `GRANT ALL … TO "authenticated", "service_role"`.
- **Signature TypeScript** (`types.ts`, section `Functions`) : `Args: { p_etablissement_id: string }` ; `Returns: string`.
- **Contrat de réponse** : `uuid` nu, ou `null` si aucun interlocuteur actif (issue « conversation indisponible ») ; exceptions : `'Non authentifié'` `28000` (l.64708) → `.unauthorized` ; `'Non autorisé'` `42501` (l.64760 : ni mission assignée ni candidature `ACCEPTEE` dans cet établissement) → issue « conversation indisponible », jamais « session expirée ».
- **Exemple de réponse STAGING** : obligatoire dans le run T14 (fil de mission ouvert depuis le détail).

## fn_obtenir_conversation

- **Statut natif** : à venir (lot 4, T7b).
- **Usage prévu** : Seconde étape : `fn_obtenir_conversation(p_autre_id, p_mission_id)` retrouve ou crée le fil de la mission (`ChatConversation.tsx` l.125-145), puis `.secondaire(.messagerie(conversationId:))`. La création libre de conversation reste exclue (D8) : l'app n'appelle jamais sans `p_mission_id`.
- **Signature SQL** (`supabase/schema/public.sql` l.45620) :

```sql
CREATE OR REPLACE FUNCTION "public"."fn_obtenir_conversation"("p_autre_id" "uuid", "p_mission_id" "uuid" DEFAULT NULL::"uuid") RETURNS "uuid"
    LANGUAGE "plpgsql" SECURITY DEFINER
    SET "search_path" TO ''
```

- **Classe d'authentification (manifeste)** : `MIXTE_TENANT_ADMIN` pour `fn_obtenir_conversation(uuid,uuid)` — Mixte tenant / admin : la fonction distingue en interne soignant, établissement et admin ; appel avec le JWT utilisateur.
- **GRANT connu** : `REVOKE ALL … FROM PUBLIC` puis `GRANT ALL … TO "authenticated"` (pas de `service_role`).
- **Signature TypeScript** (`types.ts`, section `Functions`) : `Args: { p_autre_id: string; p_mission_id?: string }` ; `Returns: string`.
- **Contrat de réponse** : `uuid` de conversation, retrouvée ou créée sous verrou consultatif (l.45729-45736) ; exceptions : `'Non authentifié'` `28000` (l.45636) → `.unauthorized` ; `'Interlocuteur invalide'` `22023` (l.45640, nul ou soi-même) → défaut client, `.contract` ; `'Conversation non autorisée'` `42501` (l.45679, relation refusée par `private.fn_relation_messagerie_autorisee`) → issue « conversation indisponible », jamais « session expirée ».
- **Exemple de réponse STAGING** : obligatoire dans le run T14.

## fn_lister_copies_bulletins

- **Statut natif** : à venir (lot 4, T10).
- **Usage prévu** : Liste des copies officielles déposées par l'employeur (Revenus › Bulletins, composant monté `CopiesBulletinsListe.tsx`), appelée sans paramètre ; filtre employeur côté app quand plusieurs établissements (l.25-27). Les simulations de paie restent un renvoi web (D12).
- **Signature SQL** (`supabase/schema/public.sql` l.39838) :

```sql
CREATE OR REPLACE FUNCTION "public"."fn_lister_copies_bulletins"("p_etablissement_id" "uuid" DEFAULT NULL::"uuid", "p_mission_id" "uuid" DEFAULT NULL::"uuid") RETURNS "jsonb"
    LANGUAGE "plpgsql" STABLE SECURITY DEFINER
    SET "search_path" TO ''
```

- **Classe d'authentification (manifeste)** : absente du manifeste (capture production du 2026-07-29) — **classement manuel `RPC_UTILISATEUR_AUTH_INTERNE`** (modèle lot 1 décision 6, sans régénération du manifeste) : identité `auth.uid()` lue en interne, appel avec le JWT du soignant ; `ios-native/rpc-contracts.json` garde `manifeste: null` (fait observé).
- **GRANT connu** : `REVOKE ALL … FROM PUBLIC` puis `GRANT ALL … TO "authenticated"` (pas de `service_role`).
- **Signature TypeScript** (`types.ts`, section `Functions`) : absente (`types.ts` en retard sur le schéma ; contrat tenu par `public.sql`, `types: null` dans `rpc-contracts.json`).
- **Contrat de réponse** : tableau `[{id, etablissement_id, etablissement_nom, soignant_id, soignant_nom, soignant_prenom, periode_debut, periode_fin, statut, version, publie_le, remplace_id, motif_remplacement, mission_ids, taille_octets, sha256, signalee}]` trié par `periode_fin` puis `publie_le` décroissants, statut `RESERVEE` exclu (l.39846-39856). Décodage **strict** comme le web (`validerListeCopiesBulletins`, `src/lib/copiesBulletins.ts` l.67-86 : uuid, dates `YYYY-MM-DD`, statut ∈ `PUBLIEE`, `REMPLACEE`, `RETIREE`, `taille_octets` ≤ 10 Mo, `sha256` de 64 caractères hexadécimaux, `mission_ids` non vide) : une ligne invalide refuse la liste (« La liste des copies ne peut pas être vérifiée. Réessayez. », l.86), exception assumée au décodage tolérant (intégrité documentaire). Exception `42501` `COPIE_ACCES_REFUSE` (l.39845 : non authentifié, compte inactif, ou `p_etablissement_id` non géré) → refus métier connu, jamais « session expirée ».
- **Exemple de réponse STAGING** : non exigé (D12 : fixture de PDF réel coûteuse ; démo + tests de gateway).

## fn_signaler_copie_bulletin

- **Statut natif** : à venir (lot 4, T10).
- **Usage prévu** : Signalement d'une copie, feuille « Quelle erreur souhaitez-vous signaler ? » aux trois motifs du web (`DESTINATAIRE`, `CONTENU`, `AUTRE` ; `copiesBulletins.ts` l.10, `CopiesBulletinsListe.tsx` l.15, l.87-90).
- **Signature SQL** (`supabase/schema/public.sql` l.56182) :

```sql
CREATE OR REPLACE FUNCTION "public"."fn_signaler_copie_bulletin"("p_copie_id" "uuid", "p_motif" "text") RETURNS "jsonb"
    LANGUAGE "plpgsql" SECURITY DEFINER
    SET "search_path" TO ''
```

- **Classe d'authentification (manifeste)** : hors manifeste — **classement manuel `RPC_UTILISATEUR_AUTH_INTERNE`** (modèle lot 1 décision 6, sans régénération du manifeste) ; `manifeste: null` dans le JSON.
- **GRANT connu** : `REVOKE ALL … FROM PUBLIC` puis `GRANT ALL … TO "authenticated"` (pas de `service_role`).
- **Signature TypeScript** (`types.ts`, section `Functions`) : absente (`types.ts` en retard sur le schéma ; contrat tenu par `public.sql`, `types: null` dans `rpc-contracts.json`).
- **Contrat de réponse** : `{ok:true}` (l.56208) — pas de `success` ; un second signalement répond aussi `{ok:true}` (`ON CONFLICT DO NOTHING`, l.56194). **`DESTINATAIRE` retire la copie** (`statut = 'RETIREE'`, `retire_le`, l.56204-56207) : avertissement du web affiché verbatim avant confirmation, « La copie sera immédiatement retirée et son PDF ne sera plus accessible dans Jolene. » (`CopiesBulletinsListe.tsx` l.90 ; relecture HARD STOP n°4). Exceptions : `42501` `COPIE_ACCES_REFUSE` (l.56191 : copie inconnue, autre destinataire, compte inactif, copie `RESERVEE`) → refus métier connu ; `22023` `COPIE_MOTIF_INVALIDE` (l.56193) → défaut client, `.contract`. Relecture de la liste : `signalee == true`, et `statut == 'RETIREE'` pour `DESTINATAIRE`. Effet : notification `SYSTEM` « Document à vérifier » à l'établissement.
- **Exemple de réponse STAGING** : non exigé (D12).

## fn_pool_urgence_missions_pour_soignant

- **Statut natif** : à venir (lot 4, T11).
- **Usage prévu** : Écran Pool urgence : état (actif, rayon, SMS) et missions urgentes éligibles dans le rayon ; relu après chaque bascule et après une acceptation `URGENCE` (`statut_candidature`).
- **Signature SQL** (`supabase/schema/public.sql` l.47819) :

```sql
CREATE OR REPLACE FUNCTION "public"."fn_pool_urgence_missions_pour_soignant"() RETURNS "jsonb"
    LANGUAGE "plpgsql" STABLE SECURITY DEFINER
    SET "search_path" TO 'public', 'extensions'
```

- **Classe d'authentification (manifeste)** : `RPC_UTILISATEUR_AUTH_INTERNE` pour `fn_pool_urgence_missions_pour_soignant()` — RPC utilisateur : identité `auth.uid()` lue en interne, appel avec le JWT du soignant.
- **GRANT connu** : `REVOKE ALL … FROM PUBLIC` puis `GRANT ALL … TO "authenticated", "service_role"`.
- **Signature TypeScript** (`types.ts`, section `Functions`) : `Args: never` ; `Returns: Json`.
- **Contrat de réponse** : `{missions:[{id, intitule, profession_requise, specialite_medicale_requise, type_contrat_recherche, taux_horaire_base, debut_le, fin_le, service, etablissement_nom, etablissement_ville, distance_km, deja_candidate, statut_candidature}], pool_actif, rayon_km, sms_opt_in}` (l.47832-47880 ; rayon 30 par défaut) — pas de `success` ; `{error:'Non authentifié'}` (l.47828) → `.unauthorized` ; `{error:'Profil soignant introuvable'}` (l.47830) verbatim. Complété par PostgREST `missions(id, nb_creneaux, duree_heures)` et les créneaux (web l.66-80).
- **Exemple de réponse STAGING** : non exigé.

## fn_toggle_pool_urgence

- **Statut natif** : à venir (lot 4, T11).
- **Usage prévu** : Activation et rayon (curseur 5-50 km comme le web, `PoolUrgenceToggle.tsx` l.164-165), `p_creneaux = []` (web l.65-69) ; texte d'engagement du pool repris verbatim (l.229-230, relecture HARD STOP n°4). Seule voie native d'écriture de `soignants.disponible_urgence` (D26, correction 17).
- **Signature SQL** (`supabase/schema/public.sql` l.61516) :

```sql
CREATE OR REPLACE FUNCTION "public"."fn_toggle_pool_urgence"("p_actif" boolean, "p_rayon_km" integer DEFAULT 15, "p_creneaux" "jsonb" DEFAULT NULL::"jsonb") RETURNS "jsonb"
    LANGUAGE "plpgsql" SECURITY DEFINER
    SET "search_path" TO 'public'
```

- **Classe d'authentification (manifeste)** : `RPC_UTILISATEUR_AUTH_INTERNE` pour `fn_toggle_pool_urgence(boolean,integer,jsonb)` — RPC utilisateur : identité `auth.uid()` lue en interne, appel avec le JWT du soignant.
- **GRANT connu** : `REVOKE ALL … FROM PUBLIC` puis `GRANT ALL … TO "authenticated", "service_role"`.
- **Signature TypeScript** (`types.ts`, section `Functions`) : `Args: { p_actif: boolean; p_creneaux?: Json; p_rayon_km?: number }` ; `Returns: Json`.
- **Contrat de réponse** : `{success:true, disponible_urgence, documents_salarie_ok, documents_liberal_ok}` (l.61554-61559) ; refus `{error}` : `'Non authentifié'` (l.61526, → `.unauthorized`), `'Profil soignant introuvable'` (l.61529), `'Le rayon doit être compris entre 1 et 200 km.'` (l.61531, borne serveur), `'Validez les documents d’au moins un type de mission (salariée ou libérale) pour rejoindre le pool urgence.'` avec `documents_salarie_ok:false, documents_liberal_ok:false` (l.61539-61543) — verbatim, avec un lien vers les documents (lot 2). Aucun audit écrit par la RPC. Relecture : `fn_pool_urgence_missions_pour_soignant`.
- **Exemple de réponse STAGING** : non exigé.

## fn_toggle_pool_urgence_sms

- **Statut natif** : à venir (lot 4, T11).
- **Usage prévu** : Opt-in SMS du pool (description verbatim du web, `PoolUrgenceToggle.tsx` l.184-187).
- **Signature SQL** (`supabase/schema/public.sql` l.61567) :

```sql
CREATE OR REPLACE FUNCTION "public"."fn_toggle_pool_urgence_sms"("p_actif" boolean) RETURNS "jsonb"
    LANGUAGE "plpgsql" SECURITY DEFINER
    SET "search_path" TO 'public', 'extensions'
```

- **Classe d'authentification (manifeste)** : `RPC_UTILISATEUR_AUTH_INTERNE` pour `fn_toggle_pool_urgence_sms(boolean)` — RPC utilisateur : identité `auth.uid()` lue en interne, appel avec le JWT du soignant.
- **GRANT connu** : `REVOKE ALL … FROM PUBLIC` puis `GRANT ALL … TO "authenticated", "service_role"`.
- **Signature TypeScript** (`types.ts`, section `Functions`) : `Args: { p_actif: boolean }` ; `Returns: Json`.
- **Contrat de réponse** : `{success:true, pool_urgence_sms_opt_in}` (l.61595) ; `{success:false, error:'Non authentifié'}` (l.61575) → `.unauthorized` ; `{success:false, error:'Profil soignant introuvable'}` (l.61583). Audit `POOL_URGENCE_SMS_TOGGLE` (l.61586-61593). Relecture de l'état.
- **Exemple de réponse STAGING** : non exigé.

## fn_mes_exclusions_recues

- **Statut natif** : à venir (lot 4, T11).
- **Usage prévu** : Onglet « reçues » de `/soignant/exclusions`. Les exclusions **envoyées** sont lues par PostgREST `exclusions` (`exclu_par = auth.uid()`, RLS `pol_exclusion_select` l.79211), noms via `fn_etablissements_safe`.
- **Signature SQL** (`supabase/schema/public.sql` l.41730) :

```sql
CREATE OR REPLACE FUNCTION "public"."fn_mes_exclusions_recues"() RETURNS "jsonb"
    LANGUAGE "plpgsql" STABLE SECURITY DEFINER
    SET "search_path" TO 'public'
```

- **Classe d'authentification (manifeste)** : `RPC_UTILISATEUR_AUTH_INTERNE` pour `fn_mes_exclusions_recues()` — RPC utilisateur : identité `auth.uid()` lue en interne, appel avec le JWT du soignant.
- **GRANT connu** : `REVOKE ALL … FROM PUBLIC` puis `GRANT ALL … TO "authenticated", "service_role"`.
- **Signature TypeScript** (`types.ts`, section `Functions`) : `Args: never` ; `Returns: Json`.
- **Contrat de réponse** : tableau `[{id, exclu_par, type_exclu_par, motif, etablissement_nom, cree_le}]` trié par `cree_le` décroissant (l.41736-41743) ; aucune erreur (non authentifié → `[]`).
- **Exemple de réponse STAGING** : non exigé.

## fn_retirer_exclusion

- **Statut natif** : à venir (lot 4, T11).
- **Usage prévu** : Retrait d'une exclusion envoyée. Le paramètre est l'`exclu_id` (l'établissement exclu), **pas** l'id de la ligne (l.54888-54891).
- **Signature SQL** (`supabase/schema/public.sql` l.54875) :

```sql
CREATE OR REPLACE FUNCTION "public"."fn_retirer_exclusion"("p_exclu_id" "uuid") RETURNS "jsonb"
    LANGUAGE "plpgsql" SECURITY DEFINER
    SET "search_path" TO 'public'
```

- **Classe d'authentification (manifeste)** : `RPC_UTILISATEUR_AUTH_INTERNE` pour `fn_retirer_exclusion(uuid)` — RPC utilisateur : identité `auth.uid()` lue en interne, appel avec le JWT du soignant.
- **GRANT connu** : `REVOKE ALL … FROM PUBLIC` puis `GRANT ALL … TO "authenticated", "service_role"`.
- **Signature TypeScript** (`types.ts`, section `Functions`) : `Args: { p_exclu_id: string }` ; `Returns: Json`.
- **Contrat de réponse** : `{success:true}` (l.54908) ; `{success:false, error}` : `'Non authentifié'` (l.54885, → `.unauthorized`), `'Exclusion introuvable'` (l.54894). Audit `EXCLUSION_SUPPRIMEE`. Relecture des deux listes.
- **Exemple de réponse STAGING** : non exigé.

## fn_exclure_utilisateur

- **Statut natif** : à venir (lot 4, T11).
- **Usage prévu** : « Ne plus travailler ensemble » depuis le détail de mission (correction 20, D25, `BoutonExclusion.tsx` l.53-75, textes verbatim, relecture HARD STOP n°4) : `p_exclu_id` = `etablissement_id`, `p_type = 'SOIGNANT'` (type de l'auteur), motif optionnel.
- **Signature SQL** (`supabase/schema/public.sql` l.35556) :

```sql
CREATE OR REPLACE FUNCTION "public"."fn_exclure_utilisateur"("p_exclu_id" "uuid", "p_type" "text", "p_motif" "text" DEFAULT NULL::"text") RETURNS "jsonb"
    LANGUAGE "plpgsql" SECURITY DEFINER
    SET "search_path" TO 'public'
```

- **Classe d'authentification (manifeste)** : `RPC_UTILISATEUR_AUTH_INTERNE` pour `fn_exclure_utilisateur(uuid,text,text)` — RPC utilisateur : identité `auth.uid()` lue en interne, appel avec le JWT du soignant.
- **GRANT connu** : `REVOKE ALL … FROM PUBLIC` puis `GRANT ALL … TO "authenticated", "service_role"`.
- **Signature TypeScript** (`types.ts`, section `Functions`) : `Args: { p_exclu_id: string; p_motif?: string; p_type: string }` ; `Returns: Json`.
- **Contrat de réponse** : `{success:true}` (l.35600) ; refus `{success:false, error}`, verbatim : `'Non authentifié'` (l.35565, → `.unauthorized`), `'Type invalide'` (l.35569), `"Impossible de s'exclure soi-même"` (l.35574), `'Exclusion déjà existante'` (l.35579). Audit `EXCLUSION_CREEE`. Relecture des exclusions envoyées.
- **Exemple de réponse STAGING** : non exigé.

## Edge `messagerie-validate`

- **Statut natif** : à venir (lot 4, T7a/T7b). Pas une RPC : `supabase/functions/messagerie-validate/index.ts`, seul chemin d'envoi d'un message (`MessageriePort.envoyer`). `fn_envoyer_message` n'a aucun GRANT client (`REVOKE ALL … FROM PUBLIC`, `public.sql` l.82619, sans GRANT) et `fn_envoyer_message_valide` est réservée à l'edge (COMMENT l.33094, appel en service_role l.297-308) : garde-fou 19 de `tests/non-regression/guards.sh`.
- **Transport** : `POST`, corps `{conversation_id, content}`, en-tête `Authorization: Bearer <access_token utilisateur>`. `supabase/config.toml` l.183-184 : `verify_jwt = false` (vérification dans la fonction par `auth.getUser`, classe `USER_OR_ADMIN_CUSTOM` de `supabase/EDGE_AUTH_MANIFEST.json` l.73) ; comme pour `delete-account`, l'app ne suppose rien de la Gateway et traite tout 401 comme un refus. Limite edge de 60 envois par minute et par compte (`applyRateLimit`, l.79), complétée par le quota SQL durable de `fn_envoyer_message_valide`. L'anti-fuite bloque coordonnées et liens tant que la mission liée n'est ni `ASSIGNEE`, ni `EN_COURS`, ni `TERMINEE` (l.155-171).
- **Codes HTTP et corps** — liste exhaustive des réponses de `index.ts` (la garde relit le fichier et échoue si un statut ou un code manque ici) :
  - **200** `{success:true, message_id}` (l.340-343) → relecture de la ligne `messages_chat` par `message_id`, puis affichage ; l'INSERT Realtime du même id est ignoré (dédoublonnage par id). Un 200 sans `message_id` est un refus `REPONSE_ENVOI_INVALIDE` comme sur le web (`src/lib/messagerieEnvoi.ts` l.70-80) → `nonConfirme` et relecture du fil.
  - **400** `ANTI_LEAK_REFUSE` — `{success:false, error, detected_type}` (l.286-293 ; l.324-332 quand le refus vient de la RPC), `detected_type` ∈ `TELEPHONE`, `EMAIL`, `URL`, `HANDLE`, `KEYWORD` (`supabase/functions/_shared/anti-leak.ts` l.15) → `EnvoiOutcome.antiFuite(DetectedType)` et modale éducative (textes verbatim du web, relecture HARD STOP n°4) ; `BAD_REQUEST` (l.88-101, corps illisible) ; `CONTENT_EMPTY` (l.110-115).
  - **401** `NON_AUTHENTIFIE` (l.53-58, l.68-73) → `.unauthorized`.
  - **403** `CONVERSATION_NON_AUTORISEE` (l.126-131) ; erreur métier relayée de `fn_envoyer_message_valide`, ou `ENVOI_REFUSE` par défaut (`sendResult?.error || "ENVOI_REFUSE"`, l.334-337) → `refuse(code:, message:)`.
  - **405** `METHOD_NOT_ALLOWED` (l.43-48) : jamais émis par l'app (`POST` seul).
  - **409** `CONVERSATION_ARCHIVEE` (l.132-137) → composeur désactivé après relecture de la liste.
  - **413** `CONTENT_TOO_LARGE` — `{success:false, error, max:4000}` (l.103-108 ; `MAX_CONTENT_LENGTH` l.27, clé `max`) : impossible si le composeur borne la saisie à 4 000 caractères (compteur affiché dès 3 500).
  - **429** `RATE_LIMIT` (l.79-84 limite edge ; l.311-316 quota SQL, exception `P0001` « Trop de messages »).
  - **500** `INTERNAL_ERROR` — `{success:false, error, message}` (l.344-347).
  - **503** `AUTORISATION_INDISPONIBLE` (l.139-145) ; `ENVOI_INDISPONIBLE` (l.317-321).
  - Tous les refus ont la forme `{success:false, error:<code>}`, plus les clés indiquées.
  - Hors fonction : une erreur de plateforme (passerelle, délai) peut renvoyer un autre statut ou un corps non JSON → `nonConfirme`.
- **Règle app** : bouton désactivé pendant l'appel (verrou synchrone, web `InputMessage.tsx` l.52-55) ; texte saisi conservé sur tout refus ; délai dépassé ou statut inattendu = `nonConfirme` puis relecture du fil, **aucun renvoi automatique** (D8) ; un flux Realtime n'est jamais une preuve d'envoi. Contenu des messages jamais journalisé (`policy.redact`).
- **Preuve STAGING** : **obligatoire** dans le run T14 — message envoyé par l'app et reçu en Realtime par le pair établissement, puis l'inverse (plan l.209, D20) ; contenus alphabétiques (pas de faux positif anti-fuite).

## Edge `copies-bulletins`

- **Statut natif** : à venir (lot 4, T10). Pas une RPC : `supabase/functions/copies-bulletins/` (`index.ts`, `handler.ts`, `auth.ts`), action `telecharger` seule côté soignant (`finaliser` est l'action de dépôt de l'établissement).
- **Transport** : `POST`, corps strict `{action:'telecharger', copie_id}` (1 024 octets au plus ; clés admises `action`, `copie_id`, `destinataire_confirme`, `handler.ts` l.35-46), en-tête `Authorization: Bearer <access_token utilisateur>`. `supabase/config.toml` l.3-4 : `verify_jwt = true` (classe `PLATFORM_JWT`, `EDGE_AUTH_MANIFEST.json` l.14) ; l'edge revérifie la session auprès d'Auth (`authentifierCopie`, clés de service refusées), puis appelle `fn_acces_copie_bulletin(p_copie_id, 'telecharger')` avant et après la lecture Storage (révocation pendant la lecture), et contrôle taille et SHA-256 côté serveur (l.49-58). Délai borné à 30 s comme le web (`src/lib/copiesBulletins.ts` l.232).
- **Codes HTTP et corps** (table `ERREURS` l.17-21 et réponses `json(…)` du handler ; la garde relit le fichier) :
  - **200** octets du PDF, `Content-Type: application/pdf`, `Cache-Control: no-store`, `Content-Disposition: attachment; filename="copie-bulletin.pdf"`, `Content-Length` (l.69-73) → l'app compare `Content-Type`, taille et SHA-256 (CryptoKit) à la ligne de `fn_lister_copies_bulletins` ; refus d'intégrité sinon. Fichier temporaire `NSFileProtectionComplete` supprimé après partage ou au retour ; aucun `URLCache`.
  - Tout refus a la forme `{error:<code>}` (JSON, `Cache-Control: no-store`).
  - **400** `REQUETE_INVALIDE` (l.35-46).
  - **401** `AUTHENTIFICATION_REQUISE` (l.33) → `.unauthorized`.
  - **403** `COPIE_ACCES_REFUSE`.
  - **405** `METHODE_INTERDITE` (l.30) : jamais émis par l'app.
  - **409** `COPIE_INTEGRITE_INVALIDE`, `COPIE_FICHIER_ABSENT` ; propres à `finaliser`, sans objet pour le soignant : `COPIE_RESERVATION_EXPIREE`, `COPIE_VERSION_CONFLIT`, `COPIE_MISSIONS_INVALIDES`.
  - **410** `COPIE_RETIREE` : le `55000` de `fn_acces_copie_bulletin` (l.5233) n'arrive jamais tel quel au client → liste relue, copie affichée `RETIREE` sans bouton d'ouverture.
  - **422** `COPIE_PDF_INVALIDE`.
  - **503** `COPIE_SERVICE_INDISPONIBLE` (toute autre erreur, message brut jamais exposé, l.74-78).
- **`fn_acces_copie_bulletin`** (appelée par l'edge, jamais par l'app) lève `COPIE_ACCES_REFUSE` (`42501`), `COPIE_RETIREE` (`55000`) et `COPIE_RESERVATION_EXPIREE` (`55000`, `finaliser`) ; l'edge les traduit en 403, 410 et 409.
- **Preuve STAGING** : non exigée au lot 4 (D12) ; démo (une copie valide, une au SHA-256 faux, une `RETIREE`) et tests de gateway par code.

## Realtime : tables, RLS, filtres, cycle de vie

- **Publication versionnée** `supabase_realtime` (`supabase/migrations/20260729143000_reinstaller_dependances_auth_storage_apres_bootstrap.sql` l.245-250) : `messages_chat`, `messages_mission`, `notifications`, `presence_status`, `typing_status`.
- **`conversations` est absente de la publication versionnée** (correction 3) alors que le plan §4.1 l.106 la cite : l'abonnement web aux INSERT `conversations` (`src/pages/PageMessagerie.tsx` l.330-334) ne reçoit rien. L'app ne s'y abonne pas ; une conversation nouvelle apparaît par relecture de la liste (apparition de l'écran, retour au premier plan, INSERT `messages_chat` d'une conversation inconnue).
- **Publication réelle** : la production et STAGING ne sont pas relevées par ce T0 (aucun accès en lecture ouvert à la tranche) ; relevé en lecture seule `SELECT tablename FROM pg_publication_tables WHERE pubname = 'supabase_realtime'` en attente (`DECISIONS_LOT4.md`, « En attente de Gabrielle » n°6), à consigner ici.
- **Tables écoutées par l'app (D7)** : `messages_chat` (liste et fil), `typing_status` et `presence_status` (fil ouvert seulement). `messages_mission` et `notifications` ne sont pas écoutées au lot 4 (notifications : lot 3).
- **Canaux et RLS** : liste — canal `messagerie-liste-<uid>`, `postgresChange(InsertAction, table: "messages_chat")` sans filtre, la RLS `pol_msg_select` (`public.sql` l.79371, `fn_conversation_accessible(conversation_id)`) ne laisse passer que les messages visibles par le JWT ; fil — canal `chat-conv-<id>` avec le filtre `.eq("conversation_id", id)` ; saisie — canal `typing-<id>`, INSERT/UPDATE/DELETE `typing_status` (RLS `pol_typing_status_select` l.79758) ; présence — canal `presence-<autre>`, `presence_status` (RLS `pol_presence_status_select` l.79528).
- **Cycle de vie** : client `client.realtimeV2` (SDK `Sources/Supabase/SupabaseClient.swift` l.139) ; abonnement au premier plan seulement (`scenePhase == .active`) par `subscribeWithError()` (SDK `RealtimeChannelV2.swift` l.231) ; à chaque passage « rejoint » après coupure : relecture du fil depuis le dernier `cree_le` connu et relecture de la liste ; un canal retiré ou fermé par le serveur ne rejoint plus jamais (SDK l.224-226) → nouveau canal et relecture ; arrière-plan → `removeAllChannels()` (aucun `UIBackgroundModes`, plan §4.5) ; retour au premier plan → réabonnement et relecture ; changement d'epoch d'identité → `fermerTout()` avant toute nouvelle session ; le jeton suit le rafraîchissement (`realtimeV2.setAuth`, `SupabaseClient.swift` l.519). `fn_update_presence` toutes les 30 s tant que le fil est visible, premier battement après le `subscribeWithError()` réussi du canal du fil.
- **Règles** : un flux n'est jamais une preuve d'envoi (relecture par `message_id`) ; dédoublonnage par id ; badge = `fn_messages_non_lus()` relu, jamais la somme des `non_lus` d'une page.
- **Preuve** : STAGING bidirectionnelle obligatoire (T14, pair établissement `scripts/mobile/staging-lot4-peer.mjs`) ; appareil physique pour premier plan, arrière-plan, retour et coupure réseau (`RECETTE_DEVICE_LOT4.md`).

## Jamais `notations_missions` / `evaluations` / `evaluations_publiees` côté natif

- **Règle** (`CLAUDE.md`, « Publication différée = filtre de visibilité centralisé », Finding #3) : une notation non publiée ne transparaît jamais. La source canonique est la vue `evaluations_publiees` (`public.sql` l.69517-69543, `publie_le IS NOT NULL AND masque = false`), mais elle n'est accordée qu'à `service_role` (l.86074) et n'est pas `security_invoker` : le client ne peut pas la lire et ne doit jamais l'obtenir (elle contournerait la RLS).
- **Sources uniques côté app** : `fn_mes_notations_recues_avec_stats` (cinq lectures de `notations_missions`, toutes filtrées `n.masque = false AND n.publie_le IS NOT NULL`) et `fn_lister_notations_recues` (une lecture, l.40324-40325). La garde compte, dans chaque corps, autant de filtres `publie_le IS NOT NULL` et `masque = false` que de lectures de la table.
- **Interdits** : aucune requête PostgREST, aucun canal Realtime, aucun littéral Swift égal à `notations_missions`, `evaluations` ou `evaluations_publiees` dans `ios-native/Packages` et `ios-native/Jolene` — garde-fou 18 de `tests/non-regression/guards.sh` et test Swift `EvaluationsSourceGuardTests` (T9), qui construit son motif sans écrire ces noms entre guillemets. `EcranSecondaire.evaluations` garde sa valeur brute implicite et `cleDrapeau` s'écrit `"ios_natif_\(rawValue)_actif"`. Le garde-fou 18 ne lit que les fichiers `*.swift` : une fixture de démo, un vecteur golden (`LinkRouter`), un catalogue de chaînes ou un xcassets peut porter la valeur brute `evaluations` (nom d'écran ou de route), qui n'est pas un lecteur de table ; un dossier absent ou illisible le fait échouer (code 2 de grep), comme le garde-fou 19.
- **Surfaces web hors natif** : le classement `/soignant/classement` lit `soignants.note_moyenne`, alimentée par la table legacy `evaluations.visible` (`dec_maj_note_moyenne` l.2226-2268), et non `evaluations_publiees` : renvoi web assumé (`LOT4_PLAN.md` §1.3), aucune surface native.
- **Preuve STAGING** recommandée (T14) : notation N1 publiée visible, notation N2 non publiée absente des deux RPC.

## Surcharges de `fn_ouvrir_litige_rate_limited` : seule la 3 arguments est appelée

```sql
CREATE OR REPLACE FUNCTION "public"."fn_ouvrir_litige_rate_limited"("p_mission_id" "uuid", "p_motif" "text") RETURNS "jsonb"
CREATE OR REPLACE FUNCTION "public"."fn_ouvrir_litige_rate_limited"("p_mission_id" "uuid", "p_type_litige" "public"."type_litige", "p_motif" "text") RETURNS "jsonb"
CREATE OR REPLACE FUNCTION "public"."fn_ouvrir_litige_rate_limited"("p_mission_id" "uuid", "p_type_litige" "public"."type_litige", "p_motif" "text", "p_facture_id" "uuid") RETURNS "jsonb"
```

- **2 arguments** (`public.sql` l.46354) : `COMMENT` l.46375 « DEPRECATED + AUDITED (FIX 2). Wrapper rétrocompat 2-arg → 3-arg. … À supprimer en Sub-PR 3. » ; renvoie `'Accès refusé'` ou délègue avec `AUTRE`. Appelée par le web (`src/pages/LitigesSoignant.tsx` l.172) ; jamais appelée par l'app.
- **3 arguments** (l.46379, `COMMENT` l.46564 « Signature canonique (3 args) ») : **seule surcharge appelée par l'app**, paramètres nommés `p_mission_id`, `p_type_litige`, `p_motif` : `p_type_litige = 'DESACCORD_HEURES_POINTAGE'` au lot 2 (T5b, contestation d'une présence validée) et `p_type_litige = 'AUTRE'` au lot 4 (T8). Une seule fiche `fn_ouvrir_litige_rate_limited` et une seule entrée suivie, partagée entre les deux lots (`RPC_PARTAGEES_LOT4`) ; l'usage du lot 4 est sa sous-section « Usage du lot 4 ».
- **4 arguments** (l.46568) : litiges typés sur facture (`WizardOuvertureLitige.tsx`, monté par `MesFacturesHonoraires.tsx`), renvoi web assumé (D9 : gel et dégel de facture, `trg_litige_gel_degel_facture` l.76028) ; `p_facture_id` sans valeur par défaut, donc aucune ambiguïté PostgREST avec la 3 arguments ; hors manifeste ; jamais appelée par l'app. Ses refus ne sont pas repris dans la fiche (sans objet).
- Les trois surcharges sont accordées à `authenticated` et `service_role` et figurent dans `ios-native/rpc-contracts.json` (une dérive de l'une fait échouer la CI). `types.ts` (l.10147) ne déclare que les surcharges à 2 et 3 arguments, en union.

## Hors périmètre de ce document

Les RPC publiques consommées par le second client sans persistance (plan §4.1 : cinq RPC `PUBLIC_VOLONTAIRE`)
et les RPC établissement du lot 5 (`fn_traiter_candidature_planning_v1`, `fn_creer_mission_multi_jours_v4`,
`fn_mes_permissions_etab`) seront ajoutées à `RPC_SUIVIES` dans `scripts/mobile/check-rpc-contracts.mjs`
au lot qui les consomme, jamais avant.
