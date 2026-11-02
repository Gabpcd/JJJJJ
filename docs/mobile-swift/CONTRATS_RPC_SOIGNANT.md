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

Deux RPC ne sont pas suivies, pour des raisons différentes, et `verifierExclusions`
(`scripts/mobile/check-rpc-contracts.mjs`) fait échouer la CI si l'une d'elles y entre trop tôt :
**jamais** `fn_etablissement_public` (fiche « Interdite côté natif » en fin de document) ; **pas avant le
lot 4** `fn_retirer_candidature` (swipe), suivie au plus tôt avec `lot: 4`. À part, `fn_mon_profil_soignant_complet`
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
- **Mes missions (lot 1, T5, `SupabaseMesMissionsGateway`)** : seule source du nom sur les trois onglets. Les lectures PostgREST de `MissionsSoignant.tsx` (`candidatures` avec `missions(...)` embarquée, `missions` à venir et passées) sont reprises **sans** l'embed `etablissements(...)` du web (`pol_etab_select`) ; la RPC rend la ligne d'une mission assignée au soignant (tout statut, donc les passées) ou OUVERTE de l'établissement (les candidatures en attente), même cohorte (l.35073-35095). En échec, repli « Établissement » comme `fetchEtablissementsSafe` du web, qui ignore l'erreur ; une session expirée est propagée.
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

## Hors périmètre de ce document

Les RPC publiques consommées par le second client sans persistance (plan §4.1 : cinq RPC `PUBLIC_VOLONTAIRE`)
et les RPC établissement du lot 5 (`fn_traiter_candidature_planning_v1`, `fn_creer_mission_multi_jours_v4`,
`fn_mes_permissions_etab`) seront ajoutées à `RPC_SUIVIES` dans `scripts/mobile/check-rpc-contracts.mjs`
au lot qui les consomme, jamais avant.
