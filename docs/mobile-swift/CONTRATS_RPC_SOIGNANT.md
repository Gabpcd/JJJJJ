# Contrats RPC du parcours soignant (lot 0, plan §11 jour 8 ; lot 1, T0 ; lot 2, T0)

Document de référence des trente-trois RPC que le client Swift consomme ou consommera (seize au lot 0,
onze ajoutées par la tranche T0 du lot 1, `docs/mobile-swift/LOT1_PLAN.md` §3 ; la tranche T0 du lot 2,
`docs/mobile-swift/LOT2_PLAN.md` §3, retire les quatre RPC du système de pointage ① et en ajoute dix,
dont une RPC de recette STAGING), plus des fiches hors RPC : l'edge function `delete-account`
(suppression de compte, Apple 5.1.1), l'interdiction de `fn_etablissement_public` côté natif et, au lot 2,
la fiche « `nouveau_code` jamais lu », les edges `verify-document` et `generate-contrat-mission-pdf`, le
Storage du lot 2, l'interdiction du système de pointage ① et celle de `fn_creer_notification`. Pour chaque RPC : la
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
automatique `auto/schema-baseline` (`schema-snapshot.yml`) qui modifie l'une des trente-trois RPC suivies
(signature, GRANT, ou corps dont une fiche cite les réponses) reste bloquée — c'est voulu, fail-closed — et
`drift-check.yml` reste rouge tant qu'elle n'est pas mergée. Ne jamais corriger sur `auto/schema-baseline` :
le `git push --force` du run suivant efface tout commit manuel. Procédure : une **PR humaine**, depuis une
branche dédiée, porte le dump (`supabase/schema/public.sql` de la PR automatique ou de l'artefact
`schema-public-sql`) ; après relecture de la définition live (`scripts/dump-live-def.sh`) et des gateways
Swift concernées, elle ajoute `node scripts/mobile/check-rpc-contracts.mjs --update` (nouveau
`ios-native/rpc-contracts.json`) et la fiche ajustée dans ce document ; CI verte et revue fraîche, merge,
puis fermeture de la PR automatique devenue sans objet (le run suivant de `schema-snapshot.yml` ne trouve
plus de diff).

**Autres sources lues par la garde.** Outre les trente-trois RPC suivies, la garde lit : les corps de six fonctions non suivies (`fn_conflit_planning_soignant`, `fn_postuler_mission`, `fn_postuler_mission_rate_limited`, `fn_finaliser_attribution_mission`, `fn_resoudre_contrat_mission`, `fn_demander_confirmations_presence`) ; le web `src/pages/DetailMissionSoignant.tsx` (chaînes de présence, tests `data?.choix_requis`, classement « mission perdue ») et `src/lib/erreurs.ts` (`estBlocageCodeTravail`) ; l'edge `supabase/functions/delete-account/index.ts` et `supabase/functions/_shared/admin-auth.ts` ; tout littéral `"fn_…"` des fichiers `ios-native/**/*.swift`. Une PR web, edge ou de re-baseline qui modifie l'une de ces sources met la fiche concernée à jour **dans la même PR**.

**Sources ajoutées par le lot 2 (T0).** Les corps de `fn_exiger_conformite_demarrage_mission`, `trg_exiger_conformite_premier_pointage` et `dec_fenetre_pointage` (exceptions de la première OUVERTURE) et les triggers `dec_fenetre_pointage`, `trg_01_exiger_conformite_premier_pointage`, `trg_01_exiger_conformite_mission_en_cours`, `trg_notifier_creation_litige` ; le supplément `scripts/ci/sms-signature-staging.sql` (`fn_admission_otp_signature_recette`, statut `staging_seulement`) ; le web `src/components/pointage/PointageRotatifSoignant.tsx` (RPC appelées, clés `p_metadata`, surcharge du message `P0002`), `src/pages/PresencesSoignant.tsx` et `src/components/pointage/BlocPointageMission.tsx` (système ① non appelé), `src/components/CartePointage.tsx` et `src/lib/qr-offline-queue.ts` (importeurs), `src/components/PanneauContestation.tsx` (trois clés, `fn_creer_notification`, constante 72 h), `src/components/SignerContratOtp.tsx` (`MESSAGES_ERREUR`) et `src/lib/signatureSmsStagingAdmission.ts` (garde d'URL STAGING) ; les edges `supabase/functions/verify-document/index.ts` et `supabase/functions/generate-contrat-mission-pdf/index.ts` et leur ligne `verify_jwt` de `supabase/config.toml` ; toutes les politiques `storage.objects` de `supabase/migrations/*.sql` (état final, quel que soit leur nom) ; aucun `nouveau_code` dans les sources Swift. Ajouts de la revue fraîche de T0 : les corps de `fn_codes_pointage_mission`, `fn_pointer_arrivee`, `dec_antifraude_presence`, `fn_generer_qr_mission`, `fn_valider_scan_qr` et `fn_creer_notification`, et les GRANT `authenticated` des RPC ① et de `fn_creer_notification` (constats B9 de `DECISIONS_LOT2.md`) ; `docs/audit-fonctionnel-pre-lancement.md` (statut « FIXÉ » de `fn_creer_notification`) ; le rejoueur ① `src/lib/horsLigne.ts` (`stockerPointageHorsLigne`), `src/components/SyncHorsLigne.tsx` et `src/components/LayoutApp.tsx` (importeurs) ; les filtres de chemins de `.github/workflows/ios-swift-ci.yml` (supplément SMS, consigne pour T2). Ajouts de la seconde revue fraîche de T0 : les corps de `fn_generer_code_secours_mission` et `fn_valider_code_secours` (troisième chaîne de pointage à distance) et le GRANT `authenticated` du générateur ; les importeurs et appelants de `src/components/etablissement/QRPointageEtab.tsx` et `src/components/soignant/SaisieCodeSecours.tsx` (code de secours non monté) ; les gardes d'accès de toutes les RPC GRANT `authenticated` qui comparent nûment à `mon_etablissement_id()` (« Motif à auditer » de `DECISIONS_LOT2.md`) ; le corps de `est_admin_valide` (booléen non nul : `est_etab` de `fn_etat_pointage_mission` vaut `null` pour un soignant) ; `scripts/mobile/export-demo-fixtures.mjs` et les fixtures `.json`/`.swift` de `ios-native/` (aucun `est_etab: false`).

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

Règles ajoutées au lot 2 (`LOT2_PLAN.md` §2.4, `DECISIONS_LOT2.md`) : les refus du pointage sont des
**exceptions PostgREST** (`{code, message}`), pas du jsonb. Chaque RPC qui en lève déclare son ensemble de
SQLSTATE métier (`exceptionsMetier`) ; le message `PostgrestError.message` est lu **avant**
`SupabaseErrorMapping` (ordre : `[CODE DU TRAVAIL]` → exceptions métier → mapping du lot 0), restitué
verbatim, jamais `details` ni `hint`. Un `42501` métier n'est jamais une session expirée ; « permission denied
for … » (GRANT manquant) reste une erreur de contrat. Toute `PostgrestError` décodée prouve un rollback : refus,
jamais `.incertain` ; seuls `URLError`, le délai `bounded` et un statut HTTP sans corps PostgREST (502/504) sont
incertains, réconciliés par relecture. Statut `staging_seulement` : RPC de recette définie par un supplément
STAGING (`source`), absente de `public.sql` et de `types.ts` ; `buildContracts` échoue si elle apparaît en
production. Les RPC du système de pointage ① (`RPC_POINTAGE_SYSTEME_1`) et `fn_creer_notification`
(`RPC_JAMAIS_SUIVIES`) ne sont jamais suivies.

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
| `fn_scanner_code_pointage` | à venir | 2 (T3) | RPC_UTILISATEUR_AUTH_INTERNE | authenticated, service_role | déclarée |
| `fn_etat_pointage_mission` | à venir | 2 (T3) | MIXTE_TENANT_ADMIN | authenticated, service_role | absente |
| `fn_envoyer_otp_signature` | consommée lot 2 (T8) | 2 (T8 gateway, T9b écran) | RPC_UTILISATEUR_AUTH_INTERNE | authenticated, service_role | déclarée |
| `fn_signer_contrat_otp` | consommée lot 2 (T8) | 2 (T8 gateway, T9b écran) | RPC_UTILISATEUR_AUTH_INTERNE | authenticated, service_role | déclarée |
| `fn_remplacer_document_soignant` | à venir | 2 (T6) | RPC_UTILISATEUR_AUTH_INTERNE | authenticated, service_role | absente |
| `fn_consentir_gps` | à venir | 2 (T3, T4b) | RPC_UTILISATEUR_AUTH_INTERNE | authenticated, service_role | déclarée |
| `fn_relancer_validation_presence` | à venir | 2 (T3, T5a) | RPC_UTILISATEUR_AUTH_INTERNE | authenticated, service_role | absente |
| `fn_presences_detail_mission` | à venir | 2 (T3, T5a) | MIXTE_TENANT_ADMIN | authenticated, service_role | déclarée |
| `fn_fenetre_contestation_ouverte` | à venir | 2 (T5b) | hors manifeste (SECURITY INVOKER) | authenticated, service_role | déclarée |
| `fn_ouvrir_litige_rate_limited` | à venir | 2 (T5b, surcharge `(uuid, type_litige, text)`) | RPC_UTILISATEUR_AUTH_INTERNE (deux surcharges sur trois) | authenticated, service_role | absente |
| `fn_creer_notation_mission` | à venir | 2 (T5a) | MIXTE_TENANT_ADMIN | authenticated, service_role | déclarée |
| `fn_demander_revue_document` | à venir | 2 (T6) | RPC_UTILISATEUR_AUTH_INTERNE | authenticated | absente |
| `fn_verifier_coherence_documents` | à venir | 2 (T6) | MIXTE_TENANT_ADMIN | authenticated, service_role | déclarée |
| `fn_signer_attestation_sante` | à venir | 2 (T6) | RPC_UTILISATEUR_AUTH_INTERNE | authenticated, service_role | déclarée |
| `fn_admission_otp_signature_recette` | STAGING seulement (câblée T8) | 2 (T8) | hors manifeste (supplément STAGING) | authenticated | absente (jamais en production) |
| `fn_upsert_token_push` | à venir | 3 | RPC_UTILISATEUR_AUTH_INTERNE | authenticated, service_role | déclarée |

Quatre RPC sont absentes de `types.ts` (`fn_confirmer_action_planning_v1`, `fn_param_bool`,
`fn_etat_pointage_mission`, `fn_remplacer_document_soignant`) : leur contrat est tenu par `public.sql` seul
jusqu'à régénération des types (`supabase gen types`) ; le web les appelle déjà avec `as any`
(`src/hooks/useParamBool.ts` l.18). Une RPC est hors manifeste (`fn_confirmer_action_planning_v1`, créée
après la capture du 2026-07-29) : **classée manuellement `RPC_UTILISATEUR_AUTH_INTERNE`** par la décision 6
du lot 1 (`LOT1_PLAN.md` §7), sans régénération du manifeste — voir sa fiche. `ios-native/rpc-contracts.json`
garde `manifeste: null` pour elle : c'est le fait observé, le classement est documentaire.

Lot 2 : trois RPC de plus sont absentes de `types.ts` (`fn_relancer_validation_presence`,
`fn_ouvrir_litige_rate_limited`, `fn_demander_revue_document`), appelées par le web avec `as any`.
`fn_admission_otp_signature_recette` n'y figure pas par construction (recette STAGING, jamais en production).
Hors manifeste : `fn_fenetre_contestation_ouverte` est `SECURITY INVOKER` (le manifeste ne recense que les
fonctions `SECURITY DEFINER`), `fn_admission_otp_signature_recette` n'existe que sur STAGING, et la troisième
surcharge `fn_ouvrir_litige_rate_limited(uuid, type_litige, text, uuid)` est absente de la capture du
2026-07-29 (elle n'est pas appelée par le natif).

Plusieurs RPC ne sont pas suivies, pour des raisons différentes, et `verifierExclusions`
(`scripts/mobile/check-rpc-contracts.mjs`) fait échouer la CI si l'une d'elles y entre :
**jamais** `fn_etablissement_public` et `fn_creer_notification` (`RPC_JAMAIS_SUIVIES`, fiches « Interdite côté
natif » en fin de document) ; **jamais** les neuf RPC du système de pointage ① (`RPC_POINTAGE_SYSTEME_1`, fiche
« Interdit côté natif : système de pointage ① ») ; **pas avant le lot 4** `fn_retirer_candidature` (swipe),
suivie au plus tôt avec `lot: 4`. À part, `fn_mon_profil_soignant_complet` reste suivie mais est reclassée
lot 3 (voir sa fiche).

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

## fn_scanner_code_pointage

- **Statut natif** : à venir (lot 2, T3 gateway, T4b écran ; décisions 1, 2, 6 de `DECISIONS_LOT2.md`).
- **Usage prévu** : seul système de pointage du natif (code rotatif à six chiffres affiché par l'établissement,
  saisi ou lu dans le QR de `AffichageCodeRotatifEtab`). Arrivée, départ et pauses alternent OUVERTURE et
  FERMETURE d'un segment `mission_creneaux` `EFFECTIF`. Reçu `RecuScan` écrit avant l'appel (`LOT2_PLAN.md`
  §2.6), **une seule requête**, jamais de renvoi automatique, aucune file hors ligne (décision 2) ; succès
  affiché seulement après relecture de `fn_etat_pointage_mission` et de `scans_pointage`.
- **Signature SQL** (`supabase/schema/public.sql` l.55622) :

```sql
CREATE OR REPLACE FUNCTION "public"."fn_scanner_code_pointage"("p_code" "text", "p_metadata" "jsonb" DEFAULT NULL::"jsonb") RETURNS "jsonb"
    LANGUAGE "plpgsql" SECURITY DEFINER
    SET "search_path" TO 'public'
```

- **Classe d'authentification (manifeste)** : `RPC_UTILISATEUR_AUTH_INTERNE` pour `fn_scanner_code_pointage(text,jsonb)` — RPC utilisateur : identité `auth.uid()` lue en interne, appel avec le JWT du soignant.
- **GRANT connu** : `REVOKE ALL … FROM PUBLIC` puis `GRANT ALL … TO "authenticated", "service_role"`.
- **Signature TypeScript** (`types.ts`, section `Functions`) : `Args: { p_code: string; p_metadata?: Json }` ; `Returns: Json`.
- **Requête** : corps `{"p_code":"<6 chiffres>","p_metadata":{…}}` ; clés de `p_metadata` identiques au web
  (`src/components/pointage/PointageRotatifSoignant.tsx` l.122-126) : `id_terminal` toujours (`TERM_IOS_` +
  20 caractères base32, décision 7), `latitude`, `longitude`, `precision_gps_m` seulement si le consentement
  GPS est donné **et** la position précise disponible (décision 5) ; jamais `ip_address` (lue par le serveur
  l.55731 et l.55806 mais non envoyée par le web). Le serveur horodate (`v_now := now()`, l.55628) : un code rejoué plus
  tard serait un faux pointage, d'où l'absence de file.
- **Contrat de réponse (HTTP 200)** : `{type_scan_effectue, prochain_type_scan, creneau_effectif_id,
  horodatage_effectif, horodatage_arrondi, numero_scan, validation_etab_requise, nouveau_code, nouveau_hmac}`
  (l.55871-55886). Le décodeur Swift est une **liste blanche** sans `nouveau_code` ni `nouveau_hmac` (fiche
  « `fn_scanner_code_pointage` : `nouveau_code` jamais lu »). Aucun refus en jsonb : tous les refus sont des
  exceptions.
- **Exceptions PostgREST de la RPC** (message `PostgrestError.message` verbatim ; `%` = valeur formatée par le
  serveur) :
  - `P0002` (`no_data_found`) « Code de pointage invalide ou expiré. » (l.55649) — seule surcharge client,
    celle du web (`PointageRotatifSoignant.tsx` l.135-136 : « Code de pointage invalide ou expiré. Demande le code
    actuel à l’établissement. »), dont seule la personne du verbe change (décision 6) : « Code de pointage invalide
    ou expiré. Demandez le code actuel à l’établissement. » (forme exacte, apostrophe typographique ’ du web) ;
  - `42501` (`insufficient_privilege`) « Vous n'êtes pas assigné(e) à cette mission. » (l.55652) — **refus métier, jamais une session expirée** ;
  - `23514` (`check_violation`) « Scan déjà pris en compte. Prochain scan possible dans % secondes. » (l.55662, anti-rejeu de 2 min) ;
  - `23514` « Le contrat doit être signé avant le pointage. » (l.55677, OUVERTURE seulement) ;
  - `23514` « Pointage trop tôt. Mission commence à %. Possible à partir de %. » (l.55686, 15 min avant le premier créneau PREVISIONNEL, heures `Europe/Paris`) ;
  - `P0002` « Aucun créneau effectif ouvert à fermer. » (l.55775, FERMETURE) ;
  - `23514` « La fin réelle doit être postérieure au début réel du créneau. » (l.55778, FERMETURE).
- **Exceptions des triggers de la première OUVERTURE** (INSERT `presences`, puis UPDATE `missions` vers
  `EN_COURS`) : `trg_01_exiger_conformite_premier_pointage` (l.75592) et `trg_01_exiger_conformite_mission_en_cours`
  (l.75588) appellent `fn_exiger_conformite_demarrage_mission` (l.35858) :
  - `22023` « Mission et soignant requis » ;
  - `42501` « Le soignant n'est pas affecté à cette mission. » ;
  - `23514` « La mission ne peut pas être démarrée dans son état actuel. » ;
  - `23503` « Profil soignant introuvable. » ;
  - `23514` « Le contrat signé par les deux parties est requis avant le pointage. » ;
  - `23514` « Les justificatifs requis ne sont plus tous vérifiés. Déposez ou faites valider la preuve courante avant de démarrer. » ;
  - `dec_fenetre_pointage` (BEFORE INSERT `presences`, l.75384) : `P0001` « Pointage trop tôt. La mission commence à %. »
    (l.1961, 30 min avant `missions.debut_le`, heure formatée **sans** fuseau, donc en UTC : affiché verbatim,
    correctif backend à proposer hors lot 2, `LOT2_PLAN.md` §5).
  - Liste non exhaustive des autres triggers qui peuvent lever (`LOT2_PLAN.md` correction 10) : tout autre
    SQLSTATE reste un **refus** (message générique), jamais un incertain.
- **Interception** (`RPCResponse.appeler(…, exceptionsMetier:)`, T1) : ensemble déclaré pour cette RPC
  `["P0001", "P0002", "22023", "23503", "23514", "42501"]`, restitué `{success:false, ok:false,
  code:"SQLSTATE_<code>", error:<message>}` avant `SupabaseErrorMapping`. « permission denied for function
  fn_scanner_code_pointage » (GRANT manquant) → `.contract` ; PGRST202, 300-303 → mapping du lot 0. Statuts
  HTTP des stubs de test : `42501` → 403, `23503` → 409, `P0001`, `22023`, `23514` → 400, `P0002` → 500
  (comportement de PostgREST).
- **Relecture** : `fn_etat_pointage_mission` (`nb_scans` = `numero_scan`, `prochain_type_scan` basculé) puis
  `scans_pointage?select=id,numero_scan,type_scan,scanne_le,id_terminal,precision_gps_m&mission_id=eq.<id>&order=numero_scan.desc`
  (une preuve hors de la base du reçu, même `id_terminal`) ; jamais `code_saisi`, `ip_address`, `latitude`,
  `longitude` (lisibles par `sp_select` l.79931 mais inutiles). Réconciliation « non reçu » seulement ≥ 8 s
  après `started` (décision 2).
- **Preuve STAGING** : T11 — deux lignes `scans_pointage` (OUVERTURE puis FERMETURE, `numero_scan` 1 puis 2,
  `id_terminal ~ '^TERM_IOS_[A-Z2-7]{20}$'`, `precision_gps_m` non nul), segment `EFFECTIF` fermé,
  `missions.statut = 'EN_COURS'`, `presences.perimetre_gps_valide = true`.

## fn_etat_pointage_mission

- **Statut natif** : à venir (lot 2, T3).
- **Usage prévu** : état du pointage d'une mission, relu toutes les 15 s quand le bloc est visible
  (`PointageRotatifSoignant.tsx` l.64-72) et après chaque scan (règle « aucun succès fabriqué »).
- **Signature SQL** (`supabase/schema/public.sql` l.35145) :

```sql
CREATE OR REPLACE FUNCTION "public"."fn_etat_pointage_mission"("p_mission_id" "uuid") RETURNS "jsonb"
    LANGUAGE "plpgsql" STABLE SECURITY DEFINER
    SET "search_path" TO 'public'
```

- **Classe d'authentification (manifeste)** : `MIXTE_TENANT_ADMIN` pour `fn_etat_pointage_mission(uuid)` — Mixte tenant / admin : la fonction distingue en interne soignant, établissement et admin ; appel avec le JWT utilisateur.
- **GRANT connu** : `REVOKE ALL … FROM PUBLIC` puis `GRANT ALL … TO "authenticated", "service_role"`.
- **Signature TypeScript** (`types.ts`, section `Functions`) : absente (types.ts en retard sur le schéma).
- **Contrat de réponse (HTTP 200)** : `{error:'Mission introuvable'}` (l.35162) ; `{error:'Accès interdit'}`
  (l.35169) ; succès `{statut, intitule, prochain_type_scan, nb_scans, segment_ouvert, segments, code_pointage_actif, est_etab}`
  (l.35180-35190) : `statut`, `intitule`, `prochain_type_scan` (`OUVERTURE`/`FERMETURE`), `nb_scans`,
  `segment_ouvert` (`COALESCE(…, false)`, jamais nul), `segments` (`[{id, debut, fin}]`, créneaux `EFFECTIF` triés
  par début), `code_pointage_actif` (non nul pour l'établissement seulement, l.35188), `est_etab`. Décodeur en
  liste blanche : **`code_pointage_actif` jamais décodé** côté soignant, même présent. `{error}` → refus verbatim
  (parité `PointageRotatifSoignant.tsx` l.81-92).
- **est_etab vaut null pour tout compte sans établissement (soignant assigné compris), jamais false ; non décodé côté soignant.**
  `v_is_etab := est_admin() OR v_mission.etablissement_id = mon_etablissement_id()` (l.35165) : `est_admin()` rend
  un booléen non nul (`est_admin_valide`, `COALESCE(EXISTS …)`, l.4852), `mon_etablissement_id()` vaut NULL hors
  établissement (l.67092), donc `false OR NULL` = NULL, renvoyé tel quel (`'est_etab', v_is_etab`, l.35189) : JSON
  `null`. Seul un compte d'un **autre** établissement reçoit `false` (il passe la garde quand
  `soignant_assigne_id` est NULL). `est_etab` n'est jamais décodé côté soignant (à défaut, `Bool?` ignoré) : un
  décodage en `Bool` non optionnel échouerait sur toutes les réponses réelles, alors qu'un stub `false` passerait.
  Stubs et fixtures de T3 : `est_etab: null` (`DECISIONS_LOT2.md`, « Consignes aux tranches suivantes ») ; garde
  `tests/node/check-rpc-contracts.node.mjs` sur l.35165 et l.35189, et aucune fixture `est_etab: false`.
- **Écart constaté (hors lot 2, B9 RLS/auth)** : la garde d'accès (l.35165-35170) est en logique ternaire.
  Pour un utilisateur sans établissement, `mon_etablissement_id()` vaut NULL, donc `v_is_etab` vaut NULL et
  `NOT v_is_etab AND NOT v_is_soignant` vaut NULL : le refus « Accès interdit » n'est jamais renvoyé à un
  soignant **non assigné**, qui lit statut, intitulé et segments (le code reste masqué). Constat sur le dump
  `public.sql` (#1097), traité par l'audit des gardes NULL du 3 novembre 2026 (B9 : renvoi « Gardes NULL » de
  `DECISIONS_LOT2.md` › En attente de Gabrielle) ; le natif n'appelle la RPC que pour ses missions et n'en dépend pas.
- **Preuve STAGING** : T11 (relecture après OUVERTURE et FERMETURE).

## fn_envoyer_otp_signature

- **Statut natif** : consommée (lot 2, T8) par `JoleneSupabase/Contrats/SupabaseContratsGateway.swift`
  (`ContratsPort.envoyerOtp`), session `JoleneCore/Contrats/SessionSignatureOtp.swift` ; écran T9b (HARD STOP) ;
  décisions 18 et 20. Appel `POST /rest/v1/rpc/fn_envoyer_otp_signature`, corps `{"p_contrat_id"}` seul, une
  requête (`RPCResponse.appelerMutation`, jamais rejouée), session du compte affiché exigée ; **avant** l'appel,
  relecture `contrats_mission?select=id,hash_document&id=eq.<id>` : si l'empreinte affichée n'est plus celle du
  serveur, aucun SMS et refus local `HASH_DOCUMENT_CHANGE` (bloquant). Tests : `SupabaseContratsGatewayTests`.
- **Usage** : envoi du code OTP SMS après consentement lié à la révision affichée (clé
  `(contratId, empreinte, documentPrêt)`) ; minuteur 10 min ; un succès ne prouve pas l'envoi réel du SMS
  (`net.http_post` sans retour, l.33266-33283).
- **Signature SQL** (`supabase/schema/public.sql` l.33098) :

```sql
CREATE OR REPLACE FUNCTION "public"."fn_envoyer_otp_signature"("p_contrat_id" "uuid") RETURNS "jsonb"
    LANGUAGE "plpgsql" SECURITY DEFINER
    SET "search_path" TO 'public', 'extensions'
```

- **Classe d'authentification (manifeste)** : `RPC_UTILISATEUR_AUTH_INTERNE` pour `fn_envoyer_otp_signature(uuid)` — RPC utilisateur : identité `auth.uid()` lue en interne, appel avec le JWT du soignant.
- **GRANT connu** : `REVOKE ALL … FROM PUBLIC` puis `GRANT ALL … TO "authenticated", "service_role"`.
- **Signature TypeScript** (`types.ts`, section `Functions`) : `Args: { p_contrat_id: string }` ; `Returns: Json`.
- **Contrat de réponse (HTTP 200)** — refus `{success:false, error_code, error}` (valeurs JSON réelles) :
  `NON_AUTHENTIFIE` « Non authentifié » (l.33120) ; `NON_AUTORISE` « Non autorisé à signer ce contrat »
  (l.33124, l.33154) ; `CONTRAT_INTROUVABLE` « Contrat introuvable » (l.33136) ; `CONTRAT_INACTIF`
  « Ce contrat n'est plus actif (statut : <statut>). » (l.33139) ; `CONTRAT_DEJA_COMPLET` « Ce contrat est déjà
  entièrement signé. » (l.33142) ; `DEJA_SIGNE` « Vous avez déjà signé ce contrat. » (l.33160, l.33206, l.33258) ;
  `TROP_DE_SMS_IP` « Trop de demandes de signature depuis votre IP. Réessayez dans 1h. » + `envois_courant`, `max`
  (l.33166-33169) ; `TELEPHONE_MANQUANT` « Numéro de téléphone manquant. Mettez à jour votre profil avant de
  signer. » (l.33174) ; `CONFIGURATION_SMS_INDISPONIBLE` « Envoi du code indisponible. Réessayez plus tard. »
  (l.33187-33189) ; `TROP_DE_SMS` « Trop de SMS envoyés (3 max / 24h). » + `sms_envoyes`, `reset_le`
  (l.33216-33220). **STAGING seulement** (le supplément remplace la fonction, `scripts/ci/sms-signature-staging-render.mjs`
  l.11-23) : `SMS_RECETTE_INDISPONIBLE` « Envoi du code indisponible pour cette recette. » pour un compte TEST
  sans capacité. Succès `{success:true, role, telephone_masked, expire_dans_minutes:10, sms_envoyes, sms_restants}`
  (l.33286-33293) ; seul `telephone_masked` serveur est affiché, jamais un numéro en clair.
- **Messages affichés** (web `src/components/SignerContratOtp.tsx` l.30-44, `MESSAGES_ERREUR`, déjà vouvoyés ;
  centralisés par TL) : `NON_AUTHENTIFIE` « Session expirée. Reconnectez-vous puis réessayez. » ;
  `NON_AUTORISE` « Vous n'êtes pas autorisé(e) à signer ce contrat. » ; `CONTRAT_INTROUVABLE` « Contrat
  introuvable. Rechargez la page. » ; `CONTRAT_INACTIF` « Ce contrat a été annulé ou a expiré et ne peut plus
  être signé. » ; `CONTRAT_DEJA_COMPLET` « Ce contrat est déjà entièrement signé par les deux parties. » ;
  `TELEPHONE_MANQUANT` « Votre numéro de téléphone est manquant. Mettez à jour votre profil avant de signer. » ;
  `TROP_DE_SMS` « Trop de SMS envoyés (3 max / 24h). Réessayez plus tard ou contactez le support. » ;
  `OTP_NON_DEMANDE` « Demandez d'abord un code SMS en cliquant sur le bouton. » ; `OTP_EXPIRE` « Le code SMS a
  expiré (10 min). Demandez un nouveau code. » ; `OTP_INCORRECT` « Code incorrect. Vérifiez votre SMS et
  réessayez. » ; `TROP_DE_TENTATIVES` « Trop de tentatives. Renvoyez un nouveau code SMS. » ; `DEJA_SIGNE`
  « Vous avez déjà signé ce contrat. » ; `HASH_DOCUMENT_CHANGE` « Le contrat a été modifié depuis votre
  chargement. Rechargez la page avant de signer. ». Code absent de la table (`TROP_DE_SMS_IP`,
  `CONFIGURATION_SMS_INDISPONIBLE`, `SMS_RECETTE_INDISPONIBLE`) → `error` serveur verbatim (`messageDepuisCode`
  l.46-49), sinon « Une erreur est survenue. Réessayez. ». Bloquants (l.115-120) : `TELEPHONE_MANQUANT`,
  `TROP_DE_SMS`, `CONTRAT_INACTIF`, `CONTRAT_DEJA_COMPLET`, `DEJA_SIGNE`, `NON_AUTORISE`, `HASH_DOCUMENT_CHANGE`.
- **Preuve STAGING** : T11 temps 3 (capacité S1 allouée après le rendu) : `signatures_contrats.statut_signature
  = 'otp_envoye'`, `sms_envoyes_count = 1`.

## fn_signer_contrat_otp

- **Statut natif** : consommée (lot 2, T8) par `SupabaseContratsGateway.signer` ; écran T9b (HARD STOP n°4 de
  l'écran de signature). Corps exact `{"p_contrat_id", "p_otp_code", "p_hash_document", "p_signature_image": null}` ;
  code hors `^[0-9]{6}$` ou empreinte hors format : refus local, aucune requête ; exception déclarée `23514`
  (`RPCResponse.appelerMutation(…, exceptionsMetier: ["23514"])`) restituée verbatim ; succès annoncé seulement
  après relecture du contrat (`signature_soignant`, même `hash_document`) et de la ligne `signatures_contrats` du
  compte (`statut_signature = 'signe'`, même empreinte) ; réponse perdue → même relecture, jamais de renvoi.
- **Usage** : signature avec le code OTP et l'empreinte SHA-256 du HTML original affiché
  (`p_hash_document`) ; `p_signature_image` **toujours NULL** (OTP seul, décision 18) ; relecture
  `contrats_mission.signature_soignant` et `signatures_contrats.statut_signature = 'signe'`.
- **Signature SQL** (`supabase/schema/public.sql` l.56473) :

```sql
CREATE OR REPLACE FUNCTION "public"."fn_signer_contrat_otp"("p_contrat_id" "uuid", "p_otp_code" "text", "p_hash_document" "text" DEFAULT NULL::"text", "p_signature_image" "text" DEFAULT NULL::"text") RETURNS "jsonb"
    LANGUAGE "plpgsql" SECURITY DEFINER
    SET "search_path" TO 'public', 'extensions'
```

- **Classe d'authentification (manifeste)** : `RPC_UTILISATEUR_AUTH_INTERNE` pour `fn_signer_contrat_otp(uuid,text,text,text)` — RPC utilisateur : identité `auth.uid()` lue en interne, appel avec le JWT du soignant.
- **GRANT connu** : `REVOKE ALL … FROM PUBLIC` puis `GRANT ALL … TO "authenticated", "service_role"`.
- **Signature TypeScript** (`types.ts`, section `Functions`) : `Args: { p_contrat_id: string; p_hash_document?: string; p_otp_code: string; p_signature_image?: string }` ; `Returns: Json`.
- **Contrat de réponse (HTTP 200)** — refus `{success:false, error_code, error}` : `NON_AUTHENTIFIE` « Non
  authentifié » (l.56489) ; `NON_AUTORISE` « Non autorisé à signer ce contrat » (l.56493, l.56529) ;
  `CONTRAT_INTROUVABLE` « Contrat introuvable » (l.56503) ; `CONTRAT_INACTIF` « Ce contrat ne peut plus être
  signé. » (l.56506) ; `OTP_NON_DEMANDE` « Aucune demande OTP en cours. Cliquez d'abord sur "Recevoir un code SMS". »
  (l.56515) ; `DEJA_SIGNE` « Vous avez déjà signé ce contrat. » + `signe_a` (l.56521) ; `TROP_DE_TENTATIVES`
  « Trop de tentatives. Renvoyez un nouveau code SMS. » (l.56532) ; `OTP_EXPIRE` « Code expiré. Renvoyez un nouveau
  code SMS. » (l.56536) ; `OTP_INCORRECT` « Code incorrect. » + `tentatives_restantes` (l.56544, cinq essais) ;
  `HASH_DOCUMENT_CHANGE` « Le document a change ou sa preuve est indisponible. Rechargez la page avant de signer. »
  (l.56563-56564, sans accent dans la source). Messages affichés : table `MESSAGES_ERREUR` (fiche
  `fn_envoyer_otp_signature`). Exception : `23514` « Rôle de signature invalide » (l.56600, incohérence interne,
  refus définitif). Succès `{success:true, role, contrat_complet}` (l.56607).
- **Empreinte** (l.56549-56565) : SHA-256 hexadécimal des octets UTF-8 de `contrats_mission.contenu_html` ; le
  serveur exige `hash_document` sur 64 hex, `p_hash_document` égal, `storage_path` et `contenu_html_rendu_le`
  non nuls, aucune variable `{{…}}`, et aucune signature antérieure sur une autre empreinte. Un code non numérique
  ou de longueur ≠ 6 n'est jamais envoyé (refus local, aucune requête).
- **Preuve** : signature complète par Gabrielle sur iPhone (T12, P5), relue en SQL (`signatures_contrats.statut_signature
  = 'signe'`, `hash_document` = `contrats_mission.hash_document`).

## fn_remplacer_document_soignant

- **Statut natif** : à venir (lot 2, T6 ; décision 14).
- **Usage prévu** : enregistrement atomique d'un justificatif après l'upload Storage sous
  `<uid>/documents/<TYPE>/<ms>-<nom assaini>` (`DocumentsSoignant.tsx` l.404) ; reçu `RecuDocument` écrit avant
  l'upload ; puis `verify-document` **une seule fois** pour ce `document_id`. Seule mutation **rejouable** du lot 2 :
  idempotente sur `s3_cle` (verrou consultatif l.53119-53120, ligne existante active → `idempotent:true`).
- **Signature SQL** (`supabase/schema/public.sql` l.53079) :

```sql
CREATE OR REPLACE FUNCTION "public"."fn_remplacer_document_soignant"("p_type_document" "text", "p_libelle" "text", "p_s3_cle" "text", "p_nom_fichier" "text", "p_type_mime" "text", "p_taille_octets" bigint) RETURNS "jsonb"
    LANGUAGE "plpgsql" SECURITY DEFINER
    SET "search_path" TO 'pg_catalog', 'public'
```

- **Classe d'authentification (manifeste)** : `RPC_UTILISATEUR_AUTH_INTERNE` pour `fn_remplacer_document_soignant(text,text,text,text,text,bigint)` — RPC utilisateur : identité `auth.uid()` lue en interne, appel avec le JWT du soignant.
- **GRANT connu** : `REVOKE ALL … FROM PUBLIC` puis `GRANT ALL … TO "authenticated", "service_role"`.
- **Signature TypeScript** (`types.ts`, section `Functions`) : absente (types.ts en retard sur le schéma).
- **Contrat de réponse (HTTP 200)** — refus `{success:false, error_code}` **sans** `error` : `NON_AUTHENTIFIE`
  (l.53090) ; `TYPE_DOCUMENT_INVALIDE` (l.53099, valeur hors enum `type_document`) ; `CHEMIN_DOCUMENT_INVALIDE`
  (l.53109 : préfixe `<uid>/documents/<type>/`, ≤ 512 caractères, sans `..` ni `\`, quatrième segment
  `^[A-Za-z0-9._-]+$`) ; `METADONNEES_DOCUMENT_INVALIDES` (l.53117 : MIME `application/pdf`, `image/jpeg`,
  `image/png`, `image/webp` ; 1 à 10 485 760 octets ; nom ≤ 255 ; libellé ≤ 500) ; `DOCUMENT_INACTIF` (l.53131,
  clé déjà prise par une preuve supprimée ou révoquée). Succès `{success:true, document_id, idempotent}`
  (l.53134 rejoué, l.53162 créé, statut `EN_ATTENTE`, audit serveur `DOCUMENT_TELEVERSEMENT`).
- **Exceptions des triggers** (INSERT `documents_soignants`) : `trg_bloquer_documents_sante` (l.75716 →
  `fn_trg_bloquer_documents_sante` l.62571) lève `P0001` pour `VACCINATIONS`, `MEDECINE_TRAVAIL`, `ARRET_MALADIE`
  (types jamais proposés par l'app) ; `trg_10_remplacer_preuves_documentaires_actives` (l.75608) révoque la
  preuve active du même type.
- **Refus côté app** : `cleanup_orphan` (edge `verify-document`) puis message du web (`DocumentsSoignant.tsx`
  l.427-436 : « Le document ne peut pas être enregistré. Vérifie son format puis réessaie. » pour
  `CHEMIN_DOCUMENT_INVALIDE` / `METADONNEES_DOCUMENT_INVALIDES`, vouvoyé côté natif, décision 9 du lot 1).
- **Preuve STAGING** : T11 (P4) — une ligne `documents_soignants` `type_mime = 'image/jpeg'` pour une source HEIC.

## fn_consentir_gps

- **Statut natif** : à venir (lot 2, T3 gateway, T4b consentement et Profil ; décision 4).
- **Usage prévu** : premier consentement GPS (`soignants.consentement_gps IS NULL`) avant le premier pointage,
  texte verbatim de `ConsentementGPS.tsx` ; retrait et réactivation depuis le Profil natif (`SectionPreferences.tsx`
  l.128-168). Relecture `soignants.consentement_gps` (SELECT direct, comme `PresencesSoignant.tsx` l.58) ; audit
  client `RGPD_CONSENTEMENT_DONNE` au premier consentement (parité `PresencesSoignant.tsx` l.74-80, l.93-99) ; aucun
  audit `GPS_CONSENTEMENT_ACTIVE` / `GPS_CONSENTEMENT_RETIRE` (absents de `journaux_audit_action_check` l.70243 :
  l'audit du web échoue en silence).
- **Signature SQL** (`supabase/schema/public.sql` l.25474) :

```sql
CREATE OR REPLACE FUNCTION "public"."fn_consentir_gps"("p_accepte" boolean) RETURNS "jsonb"
    LANGUAGE "plpgsql" SECURITY DEFINER
    SET "search_path" TO 'public'
```

- **Classe d'authentification (manifeste)** : `RPC_UTILISATEUR_AUTH_INTERNE` pour `fn_consentir_gps(boolean)`.
- **GRANT connu** : `GRANT ALL … TO "authenticated", "service_role"`.
- **Signature TypeScript** : `Args: { p_accepte: boolean }` ; `Returns: Json`.
- **Contrat de réponse (HTTP 200)** : `{success:true}` seulement (l.25489), y compris quand aucune ligne
  `soignants` n'est modifiée : le succès n'est donc jamais une preuve, **relecture obligatoire**. Le serveur pose
  `consentement_gps`, `consentement_gps_le` et journalise `DONNEES_PERSO_MODIFICATION` (l.25484-25486).
- **Preuve STAGING** : T11 (consentement accepté dans l'app, `soignants.consentement_gps = true` relu).

## fn_relancer_validation_presence

- **Statut natif** : à venir (lot 2, T3 gateway, T5a écran).
- **Usage prévu** : relance de l'établissement quand une présence à pointage complet attend sa validation
  (`DetailPresencesMission.tsx` l.116-124).
- **Signature SQL** (`supabase/schema/public.sql` l.53013) :

```sql
CREATE OR REPLACE FUNCTION "public"."fn_relancer_validation_presence"("p_mission_id" "uuid") RETURNS "jsonb"
    LANGUAGE "plpgsql" SECURITY DEFINER
    SET "search_path" TO 'public'
```

- **Classe d'authentification (manifeste)** : `RPC_UTILISATEUR_AUTH_INTERNE` pour `fn_relancer_validation_presence(uuid)` ; filtre `soignant_assigne_id = auth.uid()`.
- **GRANT connu** : `GRANT ALL … TO "service_role", "authenticated"`.
- **Signature TypeScript** : absente (le web appelle avec `as any`).
- **Contrat de réponse (HTTP 200)** : refus `{success:false, error}` dont `error` est un **code** :
  `NON_AUTHENTIFIE` (l.53023), `MISSION_INCONNUE` (l.53030), `RIEN_A_VALIDER` (l.53041), `DEJA_RELANCE` avec
  `message` « Tu as déjà relancé cet établissement aujourd'hui. Il a été notifié. » (l.53051-53052, une relance par
  24 h). Succès `{success:true, message}` avec « Établissement relancé. Il a été notifié de valider tes présences. »
  (l.53070-53071), notification `RAPPEL_VALIDATION_PRESENCE` à l'établissement et audit `PRESENCE_RELANCE_VALIDATION`.
- **Messages affichés** : `message` serveur verbatim quand il existe (tutoyé côté serveur, décision 9 du lot 1) ;
  code sans message → repli du web « Relance impossible. » (l.123), jamais le code brut.

## fn_presences_detail_mission

- **Statut natif** : à venir (lot 2, T3 gateway, T5a écran ; `LOT2_PLAN.md` correction 16).
- **Usage prévu** : carte de synthèse du détail des présences (`DetailPresencesMission.tsx` l.140, l.338-344) ;
  lecture tolérante, `heures_reelles` jamais affichée (les segments `EFFECTIF` fermés font foi, web l.341-344).
- **Signature SQL** (`supabase/schema/public.sql` l.48908) :

```sql
CREATE OR REPLACE FUNCTION "public"."fn_presences_detail_mission"("p_mission_id" "uuid") RETURNS "jsonb"
    LANGUAGE "plpgsql" SECURITY DEFINER
    SET "search_path" TO 'public'
```

- **Classe d'authentification (manifeste)** : `MIXTE_TENANT_ADMIN` pour `fn_presences_detail_mission(uuid)`.
- **GRANT connu** : `GRANT ALL … TO "authenticated", "service_role"` (l.84091-84092).
- **Signature TypeScript** : `Args: { p_mission_id: string }` ; `Returns: Json`.
- **Contrat de réponse (HTTP 200)** : `{error:'Mission introuvable'}` (l.48918) ; `{error:'Accès refusé'}`
  (l.48922) ; sans présence `{pointage_effectue:false, heures_planifiees}` (l.48928) ; sinon `{pointage_effectue:true,
  heures_planifiees, heures_reelles, pointage_arrivee, pointage_depart, methode_arrivee, methode_depart, retard_min,
  depart_anticipe_min, duree_brute_min, duree_pause_min, duree_nette_min, nb_pauses, pauses, distance_m,
  perimetre_valide, alerte_teleportation, alertes, valide}` (l.48938-48958 ; `pauses` vient de `pauses_presence`,
  table du système ①, vide en système rotatif). `{error}` → carte masquée, reste de l'écran rendu.
- **Écart constaté (hors lot 2, B9 RLS/auth)** : même garde ternaire que `fn_etat_pointage_mission`
  (l.48920-48923) : pour un soignant, `v_mission.etablissement_id != mon_etablissement_id()` vaut NULL et le refus
  « Accès refusé » n'est jamais renvoyé ; un soignant non assigné qui connaît l'identifiant d'une mission lit la
  synthèse de présence d'un autre soignant (horaires, `distance_m`, `alertes`). Constat sur le dump, à confirmer
  sur la définition live par une PR backend séparée (B9, `DECISIONS_LOT2.md` « En attente de Gabrielle ») ; le
  natif n'appelle la RPC que pour ses missions.

## fn_fenetre_contestation_ouverte

- **Statut natif** : à venir (lot 2, T5b — HARD STOP n°4, décision 9).
- **Usage prévu** : décider l'affichage du bouton « contester » d'une présence validée avec le **même prédicat que
  le refus serveur** : appel `{p_type_litige:'DESACCORD_HEURES_POINTAGE', p_mission_id}` ; le bouton exige en plus
  `valide_le` non nul et aucun litige existant (parité `PanneauContestation.tsx` l.103-108). Erreur → bouton
  masqué (fail-closed). Aucune constante de délai dans le Swift : le web garde `DELAI_CONTESTATION_MS` = 72 h
  (`PanneauContestation.tsx` l.46), le serveur lit `parametres_litiges.delai_contestation_pointage_h`, défaut 48 h
  (l.36600) — divergence remontée à Gabrielle (HARD STOP n°4), aucun texte de délai affiché avant sa décision.
- **Signature SQL** (`supabase/schema/public.sql` l.36578) :

```sql
CREATE OR REPLACE FUNCTION "public"."fn_fenetre_contestation_ouverte"("p_type_litige" "public"."type_litige", "p_mission_id" "uuid", "p_facture_id" "uuid" DEFAULT NULL::"uuid") RETURNS boolean
    LANGUAGE "plpgsql" STABLE
    SET "search_path" TO 'public'
```

- **Classe d'authentification** : hors manifeste — fonction `SECURITY INVOKER` (`STABLE`) : elle lit `presences`
  sous RLS du soignant et `parametres_litiges` (lisible par `authenticated`, `pol_param_litiges_select` l.79455).
- **GRANT connu** : `GRANT ALL … TO "authenticated", "service_role"` (l.82942-82943).
- **Signature TypeScript** : `Args: { p_facture_id?: string; p_mission_id: string; p_type_litige: Database["public"]["Enums"]["type_litige"] }` ; `Returns: boolean`.
- **Contrat de réponse (HTTP 200)** : un booléen nu. `SECURITE_DANGER`, `NON_PAIEMENT`, `AUTRE` → toujours vrai
  (l.36596) ; `DESACCORD_HEURES_POINTAGE` → vrai si aucune présence n'est validée (l.36621), sinon
  `valide_le + delai_contestation_pointage_h > now()` (défaut 48 h, l.36600-36622).

## fn_ouvrir_litige_rate_limited

- **Statut natif** : à venir (lot 2, T5b — HARD STOP n°4, décision 9 ; réponse et clôture : renvoi web, lot 4).
- **Usage prévu** : contester une présence validée. Appel par **trois clés exactes**
  `{p_mission_id, p_type_litige:'DESACCORD_HEURES_POINTAGE', p_motif}` (comme `PanneauContestation.tsx` l.127-131),
  pour que PostgREST retienne la surcharge canonique : sans `p_type_litige`, il choisirait en silence la surcharge à
  deux clés, qui ouvre un litige `AUTRE` à fenêtre toujours ouverte ; la surcharge à quatre clés exige
  `p_facture_id` sans défaut ; seule une ambiguïté réelle donnerait `PGRST203` → `.contract`. Motif nettoyé comme
  `sanitizeText` (balises retirées, `trim`), 10 à 2 000 caractères. Audit client `PRESENCE_CONTESTATION` (dans le
  CHECK l.70243) ; **aucun** appel `fn_creer_notification` (fiche « Interdite côté natif »). Relecture `litiges`
  par `presence_id` (le serveur rattache la dernière présence de la mission, l.46521-46527).
- **Classe d'authentification (manifeste)** : `RPC_UTILISATEUR_AUTH_INTERNE` pour `fn_ouvrir_litige_rate_limited(uuid,text)`
  et `(uuid,type_litige,text)` ; la surcharge `(uuid,type_litige,text,uuid)` est absente de la capture du 2026-07-29.
- **GRANT connu** : `GRANT ALL … TO "authenticated", "service_role"` sur les trois surcharges (l.83909-83922).
- **Signature TypeScript** : absente (le web appelle avec `as any`).
- **Contrat de réponse (HTTP 200)** : refus `{error}` verbatim (surcharge appelée, ci-dessous) ; succès
  `{success:true, litige_id, est_informatif, facture_id}` (l.46551-46556). Plafond : `rate_limit_litiges_par_heure`
  de `parametres_litiges`, défaut 3 par heure.

### Surcharge `(uuid, text)`

```sql
CREATE OR REPLACE FUNCTION "public"."fn_ouvrir_litige_rate_limited"("p_mission_id" "uuid", "p_motif" "text") RETURNS "jsonb"
    LANGUAGE "plpgsql" SECURITY DEFINER
    SET "search_path" TO 'public'
```

`supabase/schema/public.sql` l.46354, commentaire « DEPRECATED + AUDITED » (l.46375) : refus `{error:'Accès refusé'}`
(l.46362), sinon délégation à la surcharge canonique avec `'AUTRE'::public.type_litige`. Jamais appelée par le natif.

### Surcharge `(uuid, type_litige, text)`

```sql
CREATE OR REPLACE FUNCTION "public"."fn_ouvrir_litige_rate_limited"("p_mission_id" "uuid", "p_type_litige" "public"."type_litige", "p_motif" "text") RETURNS "jsonb"
    LANGUAGE "plpgsql" SECURITY DEFINER
    SET "search_path" TO 'public'
```

`supabase/schema/public.sql` l.46379, **surcharge appelée par le natif**. Refus `{error}` : « Accès refusé »
(l.46400) ; « Le motif doit contenir entre 10 et 2 000 caractères. » (l.46405) ; « Mission introuvable » (l.46416) ;
« Vous n'êtes pas partie prenante de cette mission. » (l.46432) ; « Un litige de ce type est déjà ouvert pour cette
mission. » (l.46447) ; « Trop de litiges ouverts récemment. Réessayez plus tard. » (l.46469) ; « Aucune facture
contestable (ÉMISE, EN RETARD ou PAYÉE) pour cette mission. » (l.46488, types de facture seulement, jamais pour
`DESACCORD_HEURES_POINTAGE`) ; « Fenêtre de contestation fermée pour ce type de litige. Contactez le support. »
(l.46518, prédicat `fn_fenetre_contestation_ouverte`).

### Surcharge `(uuid, type_litige, text, uuid)`

```sql
CREATE OR REPLACE FUNCTION "public"."fn_ouvrir_litige_rate_limited"("p_mission_id" "uuid", "p_type_litige" "public"."type_litige", "p_motif" "text", "p_facture_id" "uuid") RETURNS "jsonb"
    LANGUAGE "plpgsql" SECURITY DEFINER
    SET "search_path" TO 'public', 'extensions'
```

`supabase/schema/public.sql` l.46568 (contestation d'une facture, lot 3/4, jamais appelée au lot 2). Refus
`{success:false, error}` : « Accès refusé » (l.46584) ; « Le motif doit contenir entre 10 et 2 000 caractères. »
(l.46594) ; « Vous n’êtes pas autorisé à contester cette facture. » (l.46613) ; « La facture sélectionnée est
introuvable ou non contestable. » (l.46633) ; « Cette facture n’est pas encore émise. Signalez plutôt un désaccord
sur les heures. » (l.46641) ; « La fenêtre de contestation de cette facture est fermée. Contactez le support. »
(l.46649) ; « Un litige de ce type est déjà ouvert pour cette facture. » (l.46665) ; « Trop de litiges ouverts
récemment. Réessayez plus tard. » (l.46687) ; `p_facture_id` NULL → délégation à la surcharge canonique.

## fn_creer_notation_mission

- **Statut natif** : à venir (lot 2, T5a ; décision 10).
- **Usage prévu** : notation rapide proposée une fois par mission au départ final (FERMETURE quand
  `now ≥ fin_le − 30 min`, `PointageRotatifSoignant.tsx` l.152-163), `p_sens = 'SOIGNANT_VERS_ETAB'`, note globale
  répliquée sur les quatre critères (`NotationRapide.tsx` l.47-53), commentaire optionnel ou NULL. **Écriture
  seule** : aucune lecture de `notations_missions` (double-aveugle, filtre centralisé `evaluations_publiees`).
- **Signature SQL** (`supabase/schema/public.sql` l.27282) :

```sql
CREATE OR REPLACE FUNCTION "public"."fn_creer_notation_mission"("p_mission_id" "uuid", "p_sens" "text", "p_critere_1" integer, "p_critere_2" integer, "p_critere_3" integer, "p_critere_4" integer, "p_commentaire" "text" DEFAULT NULL::"text") RETURNS "jsonb"
    LANGUAGE "plpgsql" SECURITY DEFINER
    SET "search_path" TO 'public', 'extensions'
```

- **Classe d'authentification (manifeste)** : `MIXTE_TENANT_ADMIN` pour `fn_creer_notation_mission(uuid,text,integer,integer,integer,integer,text)`.
- **GRANT connu** : `GRANT ALL … TO "authenticated", "service_role"`.
- **Signature TypeScript** : `Args: { p_commentaire?: string; p_critere_1: number; p_critere_2: number; p_critere_3: number; p_critere_4: number; p_mission_id: string; p_sens: string }` ; `Returns: Json`.
- **Contrat de réponse (HTTP 200)** : refus `{success:false, error}` : « Non authentifié » (l.27300) ; « Compte
  suspendu, supprimé ou désactivé » (l.27304) ; « Sens invalide » (l.27311, l.27315) ; « Accès non autorisé à cette
  mission. » (l.27326, l.27347) ; « Critères doivent être entre 1 et 5 » (l.27331) ; « Commentaire max 2000
  caractères » (l.27335) ; « Seules les missions TERMINEE peuvent être notées » (l.27359 ; une mission `EN_COURS`
  dont le départ est pointé est acceptée, l.27351-27357) ; « Notation impossible pendant un litige en médiation ou
  en revue admin. Vous pourrez noter après résolution. » (l.27368-27369) ; « Mission sans soignant assigné »
  (l.27375, sens établissement) ; « Mission déjà notée pour ce sens » (l.27399) → `.dejaNotee` silencieux (parité
  `NotationRapide.tsx` l.61). Exception `P0001` « La notation n’a pas pu être enregistrée. Veuillez réessayer. »
  (l.27425, l.27439 : audit refusé, transaction annulée). Succès `{success:true, id, tardive}` (l.27442).

## fn_demander_revue_document

- **Statut natif** : à venir (lot 2, T6).
- **Usage prévu** : revue humaine d'un justificatif à la demande du soignant (`DocumentsSoignant.tsx` l.369-391),
  motif fixe du web « Contestation du verdict automatique depuis l’espace Documents ».
- **Signature SQL** (`supabase/schema/public.sql` l.30015) :

```sql
CREATE OR REPLACE FUNCTION "public"."fn_demander_revue_document"("p_document_id" "uuid", "p_motif" "text") RETURNS "jsonb"
    LANGUAGE "plpgsql" SECURITY DEFINER
    SET "search_path" TO 'pg_catalog', 'public'
```

- **Classe d'authentification (manifeste)** : `RPC_UTILISATEUR_AUTH_INTERNE` pour `fn_demander_revue_document(uuid,text)`.
- **GRANT connu** : `GRANT ALL … TO "authenticated"` seulement (l.82430).
- **Signature TypeScript** : absente (le web appelle avec `as any`).
- **Contrat de réponse (HTTP 200)** : refus `{success:false, error_code}` : `NON_AUTHENTIFIE` (l.30026),
  `MOTIF_INVALIDE` (l.30029, motif < 10 caractères après `btrim`), `DOCUMENT_INTROUVABLE` (l.30038, document
  remplacé, supprimé ou révoqué). Succès `{success:true, revue_id, message}` avec « Demande transmise — en attente
  d'attribution. » (l.30087-30091) ; le document passe `REVUE_MANUELLE_REQUISE` et `verification_attempt_id`
  repasse à NULL.
- **Messages affichés** : ceux du web (l.375-381), vouvoyés côté natif (décision 9 du lot 1).

## fn_verifier_coherence_documents

- **Statut natif** : à venir (lot 2, T6).
- **Usage prévu** : bannière de cohérence des noms entre justificatifs et profil, **lecture best-effort** : appel
  **sans** `p_soignant_id` (parité web `DocumentsSoignant.tsx` l.328), toute erreur avalée (l.328-338).
- **Signature SQL** (`supabase/schema/public.sql` l.65809) :

```sql
CREATE OR REPLACE FUNCTION "public"."fn_verifier_coherence_documents"("p_soignant_id" "uuid" DEFAULT NULL::"uuid") RETURNS "jsonb"
    LANGUAGE "plpgsql" SECURITY DEFINER
    SET "search_path" TO 'public'
```

- **Classe d'authentification (manifeste)** : `MIXTE_TENANT_ADMIN` pour `fn_verifier_coherence_documents(uuid)`.
- **GRANT connu** : `GRANT ALL … TO "authenticated", "service_role"`.
- **Signature TypeScript** : `Args: { p_soignant_id?: string }` ; `Returns: Json`.
- **Contrat de réponse (HTTP 200)** : `{error:'Soignant introuvable'}` (l.65850) ; aucun document vérifié ou en
  attente → `{coherent:true, message, documents:[]}` avec « Pas assez de documents vérifiés » (l.65868-65872) ;
  sinon `{coherent, problemes, documents, profil_nom, profil_prenom, docs_sans_nom_lisible}` (l.65963-65970),
  `problemes` étant des textes serveur affichés tels quels.
- **Exception** : `42501` « Accès refusé » (l.65833 compte inactif, l.65839 `p_soignant_id` ≠ appelant sans droit
  admin) — interceptée (`exceptionsMetier: ["42501"]`) : aucune bannière, jamais `.unauthorized`.

## fn_signer_attestation_sante

- **Statut natif** : à venir (lot 2, T6 gateway, T7 écran ; décision 15, textes TL).
- **Usage prévu** : signature des deux attestations sur l'honneur de l'onglet Justificatifs ; relecture
  `soignants.attestation_sante_signee_le`.
- **Signature SQL** (`supabase/schema/public.sql` l.56311) :

```sql
CREATE OR REPLACE FUNCTION "public"."fn_signer_attestation_sante"() RETURNS "jsonb"
    LANGUAGE "plpgsql" SECURITY DEFINER
    SET "search_path" TO 'public'
```

- **Classe d'authentification (manifeste)** : `RPC_UTILISATEUR_AUTH_INTERNE` pour `fn_signer_attestation_sante()`.
- **GRANT connu** : `GRANT ALL … TO "authenticated", "service_role"`.
- **Signature TypeScript** : `Args: never` ; `Returns: Json`.
- **Contrat de réponse (HTTP 200)** : `{error:'Non authentifié'}` (l.56322) ; `{error:'Soignant introuvable'}`
  (l.56326) ; succès `{success:true, signe_le}` (l.56354) ; le serveur capture IP et User-Agent et journalise
  `ATTESTATION_SANTE_SIGNEE`.

## fn_admission_otp_signature_recette

- **Statut natif** : **STAGING seulement** (`statut: 'staging_seulement'`, lot 2, T8 ; décisions 18 et 20) ; câblée
  par `SupabaseContratsGateway.admissionRecette` : appelée seulement si l'origine du projet du client
  (`AdmissionRecette.origine`, barre finale et chemin ignorés) est l'URL STAGING, corps `{"p_contrat_id"}` ; toute
  erreur (dont `PGRST202`) ou réponse incohérente → aucune admission.
- **Source** : `scripts/ci/sms-signature-staging.sql` l.120-142 (supplément « STAGING-ONLY », installé sur STAGING
  par `scripts/ci/install-sms-staging-closed-sql.mjs`, jamais en production) ; absente de `public.sql` et de
  `types.ts` : `buildContracts` échoue si elle y apparaît.
- **Usage prévu** : admettre un compte TEST à l'OTP réel sur STAGING (capacité S1). Appelée **uniquement** si
  l'environnement est STAGING et l'URL Supabase `https://mejpriaetwgtcstbgfid.supabase.co` (garde du web
  `src/lib/signatureSmsStagingAdmission.ts` l.1, l.6) ; en production elle n'existe pas (`PGRST202`) et n'est
  jamais appelée. Sans admission, un compte TEST est renvoyé vers le web pour signer (décision 18).
- **Signature SQL** (supplément, `CREATE FUNCTION public.fn_admission_otp_signature_recette(p_contrat_id uuid)`) :
  `RETURNS jsonb LANGUAGE plpgsql STABLE SECURITY DEFINER SET search_path=''`.
- **GRANT connu** : `REVOKE ALL … FROM PUBLIC,anon,service_role` puis `GRANT EXECUTE … TO authenticated` (l.141-142).
- **Contrat de réponse (HTTP 200)** : `{admitted:false}` pour tout refus ou erreur (`EXCEPTION WHEN OTHERS`) ;
  sinon `{admitted, can_send, can_validate, otp_expires_at, expires_at, remaining}` : `admitted`, `can_send`
  (`remaining > 0`), `can_validate` (OTP envoyé il y a moins de 10 min et encore valide), `otp_expires_at`,
  `expires_at` (fin de la capacité, ≤ 60 min), `remaining` (0 à 2 envois restants pour l'acteur). Validation
  stricte du web (l.9-24) reprise telle quelle : toute incohérence → pas d'admission, jamais une erreur de contrat.

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

## `fn_scanner_code_pointage` : `nouveau_code` jamais lu

- **Constat** (`LOT2_PLAN.md` correction 9) : la réponse de `fn_scanner_code_pointage` contient encore le code
  suivant de la mission (`'nouveau_code', v_new_code` et `'nouveau_hmac', v_new_hmac`, `public.sql` l.55872-55873).
  Un soignant qui le lirait pourrait fermer son segment hors de l'établissement. Le web l'ignore
  (`PointageRotatifSoignant.tsx` ne lit que `type_scan_effectue`) ; le pilote RN l'écartait explicitement.
- **Règle native** : décodeur en **liste blanche** — `type_scan_effectue`, `prochain_type_scan`,
  `creneau_effectif_id`, `horodatage_effectif`, `horodatage_arrondi`, `numero_scan`, `validation_etab_requise` ;
  `nouveau_code` et `nouveau_hmac` ne sont ni décodés, ni conservés, ni journalisés, ni joints à un rapport
  (tests de T3 : absents du modèle et de tout `attachText`). Aucun fichier source Swift (hors tests) ne mentionne
  ces clés ; garde `tests/node/check-rpc-contracts.node.mjs`.
- **Correctif serveur** : PR backend **B1** (B9, `SECURITY DEFINER` → go explicite de Gabrielle,
  `DECISIONS_LOT2.md` décision 8) qui retire les deux clés depuis la définition live. B1 vise `main`, où la présente
  fiche et la garde « `nouveau_code` présent dans le dump » de `tests/node/check-rpc-contracts.node.mjs` n'existent
  pas tant que le lot 2 n'y est pas : la garde rougit au merge de `main` dans `feat/ios-lot2` qui suit la
  re-baseline du dump après B1, et ce merge (ou le commit qui le suit sur `feat/ios-lot2`) bascule la garde et la
  fiche. Si T0 est déjà sur `main` quand B1 arrive, la PR B1 les bascule elle-même.

## Edge `verify-document`

- **Statut natif** : à venir (lot 2, T6). Pas une RPC : `supabase/functions/verify-document/index.ts`, appelée par
  `client.functions.invoke("verify-document")` avec le JWT du soignant (`Authorization: Bearer <access_token>`),
  comme le web (`DocumentsSoignant.tsx` l.343, l.427, l.445). `supabase/config.toml` : `verify_jwt = false` — la
  vérification est faite **dans** la fonction (`verifyUserOrServiceRole`, mêmes réponses 401/403/500 que la fiche
  `delete-account`).
- **Deux actions** :
  1. **Vérification** — corps `{document_id}`, envoyée **une seule fois** par `document_id`, jamais relancée
     automatiquement : chaque appel crée une nouvelle tentative (`verification_attempt_id`, l.434-442) qui
     invalide la précédente et consomme un appel IA ; « Revérifier » est un geste manuel (parité
     `DocumentsSoignant.tsx` l.340-366). La réconciliation lit `statut_verification`, `resultat_ia` et
     `verification_attempt_id` avant tout appel.
  2. **`cleanup_orphan`** — corps `{action:'cleanup_orphan', s3_cle}`, appelée seulement si
     `fn_remplacer_document_soignant` a refusé l'enregistrement (parité l.427-429) ; chemin contrôlé comme le
     serveur (quatre segments `<uuid>/documents/<TYPE>/<nom>`, ≤ 512 caractères, sans `..` ni `\`, l.333-343).
- **Codes HTTP et corps** (messages verbatim de `index.ts`) :
  - **200** vérification : `{success:true, verdict, analysis:{motif_rejet, type_detecte, confiance, date_expiration,
    profession_certifiee}}` (l.1345-1359), `verdict` ∈ `VERIFIE`, `REJETE`, `EN_ATTENTE`, `REVUE_MANUELLE_REQUISE` ;
    formes courtes `{success:true, verdict:"REJETE", reason}` (MIME ou signature binaire refusés, l.488, l.502) et
    `{success:true, verdict:"REVUE_MANUELLE_REQUISE", reason}` (IA en délai, indisponible ou réponse illisible,
    l.653, l.680, l.710) ; `cleanup_orphan` : `{success:true}` (l.379).
  - **401** `verifyUserOrServiceRole` (jeton absent, invalide ou expiré).
  - **403** `{error:"Chemin de document non autorisé"}` (l.344, l.408) ; `{error:"Accès refusé"}` (l.354
    nettoyage d'un objet d'autrui, l.395 document d'autrui) ; et le 403 de `verifyUserOrServiceRole`.
  - **409** `{error:"Ce document est encore référencé"}` (l.370, nettoyage d'un objet rattaché) ;
    `{error:"Le profil ou le document a changé pendant la vérification. Relancez le contrôle."}` (l.1275-1279,
    conflit de sérialisation `40001`, sinon **503**).
  - **429** `{error:'Trop de vérifications. Réessayez dans 1 minute.'}` (l.322-329, 10 appels par minute et par IP,
    compteur en mémoire de l'instance, nettoyage compris) → aucun renvoi, verdict « vérification manuelle en
    attente » affiché, « Revérifier » plus tard.
  - **500** `{error:<message>}` (l.1359-1376) pour toute exception : « Tentative de vérification absente »,
    « Document introuvable », « Nettoyage du document incomplet », « document_id requis », « Impossible de
    télécharger le fichier », « Fichier vide ou trop volumineux », messages techniques d'écriture ou de lecture,
    à défaut « Une erreur interne est survenue. » ; le document est alors placé en revue manuelle.
  - **503** `{error:"Service de vérification automatique non configuré"}` (l.444-457, clé IA absente : document en
    revue manuelle) ; second cas du 409 ci-dessus.
- **Règle app** : tout statut ≠ 200 est un refus, jamais rejoué ; le verdict affiché est **relu** dans
  `documents_soignants` (polling 5 s pendant 60 s, `DocumentsSoignant.tsx` l.277-284).
- **Preuve STAGING** : T11 (P4) — 1 ligne `journaux_audit` `DOCUMENT_VERIFICATION_AUTO` pour le `document_id`
  (l.1322-1330) ou 1 ligne `file_revue_manuelle`, et 1 seule invocation dans les logs edge du run.

## Edge `generate-contrat-mission-pdf`

- **Statut natif** : consommée (lot 2, T8) par `SupabaseContratsGateway.original` (un appel, puis relecture du
  contrat ; tout refus → `MotifOriginalIndisponible.renduRefuse(messageServeur:)` verbatim, jamais rejoué). Malgré son nom, l'edge stocke et renvoie du **HTML** (`text/html`,
  `upload(path, …, { contentType: 'text/html', upsert: false })`, `index.ts` l.261-262), jamais un PDF
  (`LOT2_PLAN.md` correction 6). Corps `{contrat_id}` seulement : **jamais** de `donnees_cdd` côté soignant
  (décision 19). Demandée seulement si le contrat n'est pas signé, n'est pas un CDD et n'a pas d'original
  (`contratNecessiteRenduServeur`, `src/lib/contratMissionUi.ts` l.21-28), une seule fois, puis relecture de
  `contrats_mission`. `supabase/config.toml` : `verify_jwt = false` (contrôle par `auth.getUser()` puis
  `fn_contrat_storage_path` dans la fonction).
- **Codes HTTP et corps** (messages verbatim de `index.ts`) :
  - **200** `{success:true, contrat_id, storage_path, hash_document, signed_url, ttl_seconds}` (l.203-204 ; clés
    `contrat_id`, `storage_path`, `hash_document`, `signed_url`, `ttl_seconds`) ; l'URL signée vaut 24 h (`ttl_seconds` = 86 400) ; le natif ne l'utilise pas pour afficher : il télécharge
    l'objet `contrats-signes/<storage_path>` et contrôle l'empreinte (triple contrôle, `LOT2_PLAN.md` §2.5).
  - **400** `{error:'Identifiant de contrat invalide'}` (l.155).
  - **401** `{error:'Non authentifié'}` (l.171).
  - **403** `{error:'Accès au contrat refusé.'}` (l.281).
  - **404** `{error:'Contrat indisponible.'}` (l.282).
  - **405** `{error:'Méthode interdite'}` (l.150).
  - **409** `{error:'Le document original est indisponible. Aucune régénération automatique n’est possible.'}`
    (l.191) ; `{error:'Le contrat a changé. Rechargez la page.'}` (l.194, l.201) ; `{error:'Ce contrat ne peut plus
    être préparé.'}` (l.212, contrat `ANNULE`, `EXPIRE` ou `REFUSE`) ; `{error:'Le contrat a changé pendant sa
    préparation. Rechargez la page.'}` (l.278).
  - **422** `{error:'Informations contractuelles à compléter et confirmer par l’employeur.', code:'CDD_DONNEES_EMPLOYEUR_REQUISES', champs}`
    (l.228-231, code `CDD_DONNEES_EMPLOYEUR_REQUISES` ; CDD : le natif ne l'atteint pas, message du web l.603 à la
    place) ; `{error:'Les données nécessaires au contrat ne sont pas disponibles.'}` (l.244) ; `{error:'Les
    informations du contrat libéral sont incomplètes. Complétez-les avant de signer.', code:'CONTRAT_LIBERAL_DONNEES_REQUISES', champs}`
    (l.250-252, code `CONTRAT_LIBERAL_DONNEES_REQUISES`).
  - **503** `{error:'Service indisponible'}` (l.160) ; `{error:'Le document original ne peut pas être ouvert.
    Réessayez.'}` (l.197) ; `{error:'La préparation du contrat a échoué. Réessayez.'}` (l.241) ; `{error:'Le document
    n’a pas pu être enregistré. Réessayez.'}` (l.263) ; `{error:'L’enregistrement du contrat n’a pas été confirmé.
    Réessayez.'}` (l.277) ; `{error:'Le service contrat est indisponible. Réessayez.'}` (l.283).
- **Règle app** : tout statut ≠ 200 est un refus affiché avec le message serveur verbatim, jamais rejoué
  automatiquement ; un 409 « Le contrat a changé » impose une relecture du contrat (et remet le consentement à zéro,
  `SessionSignatureOtp`).

## Storage du lot 2

- **`jolene-documents`** (justificatifs, T6) : politiques `pol_storage_jolene_insert` (`FOR INSERT TO authenticated`,
  `fn_peut_gerer_objet_jolene(name)`) et `pol_storage_jolene_select` (`FOR SELECT TO authenticated`,
  `fn_peut_lire_objet_jolene(name)`), toutes deux sous `fn_compte_auth_actif()`, dans leur dernière version
  `supabase/migrations/20260729143000_reinstaller_dependances_auth_storage_apres_bootstrap.sql` l.90-106 (première
  version `20260713222000` l.1400-1406). **Aucune politique UPDATE ni DELETE** côté client
  (`pol_storage_jolene_update` et `pol_storage_jolene_delete` supprimées par `20260713222000` l.1397-1398, jamais
  recréées) : un objet n'est jamais écrasé (`upload(_:data:options:)` avec `FileOptions(contentType:, upsert: false)` —
  jamais `upload(path:file:options:)`, déprécié dans supabase-swift 2.55.5, `LOT2_PLAN.md` correction 18) ; un
  orphelin est nettoyé par l'edge (`cleanup_orphan`, service_role) ou reste non référencé. Réconciliation de
  l'objet par `exists(path:)` (HEAD). Chemin `<uid>/documents/<TYPE>/<ms>-<nom assaini>`. Consultation par
  `createSignedURL(path:expiresIn: 3600)` + audit `DOCUMENT_CONSULTATION` (présent dans le CHECK l.70243).
- **`contrats-signes`** (originaux de contrat, T8) : `pol_contrats_signes_select` (`FOR SELECT TO authenticated`,
  compte actif, admin ou `contrats_mission.storage_path = name` pour le soignant ou l'établissement du contrat),
  `20260729143000` l.126-142. Aucune écriture client ; l'objet est écrit par l'edge `generate-contrat-mission-pdf`
  (service_role). Téléchargement `download(path:)` borné à 2 Mo, empreinte SHA-256 comparée à `hash_document`.
- **Garde** : `tests/node/check-rpc-contracts.node.mjs` rejoue dans l'ordre toutes les instructions `CREATE`, `ALTER`
  et `DROP POLICY … ON storage.objects` écrites en clair dans `supabase/migrations/*.sql` (commentaires `--`
  retirés) et évalue l'état final : elle échoue si l'une des trois politiques disparaît ou change de commande, ou si
  une politique permissive encore active, **quel que soit son nom**, ouvre `UPDATE`, `DELETE` ou `ALL` sur
  `jolene-documents`, ou une écriture (`INSERT`, `UPDATE`, `DELETE`, `ALL`) sur `contrats-signes`. Une politique
  sans `FOR` vaut `ALL`, une politique qui ne restreint aucun `bucket_id` vaut pour tous les buckets, une politique
  `AS RESTRICTIVE` n'ouvre rien. Limite : une politique créée par SQL dynamique (`EXECUTE format(…)`) ou hors
  migration n'est pas vue.

## Interdit côté natif : système de pointage ①

- **Statut natif** : **jamais** (`RPC_POINTAGE_SYSTEME_1`, `scripts/mobile/check-rpc-contracts.mjs` ;
  `DECISIONS_LOT2.md` décision 1). `verifierExclusions` refuse toute entrée de `RPC_SUIVIES` qui en fait partie et la
  garde des littéraux `"fn_…"` du Swift la signale avec un message dédié.
- **RPC concernées** (neuf, toutes présentes au dump, la garde échoue si l'une disparaît sans mise à jour de cette
  fiche) : `fn_pointer_arrivee` (l.47421), `fn_pointer_depart` (l.47563), `fn_pointer_debut_pause` (l.47529),
  `fn_pointer_fin_pause` (l.47620), `fn_valider_scan_qr` (l.65545), `fn_generer_qr_mission` (l.37981),
  `fn_valider_code_secours` (l.64991), `fn_codes_pointage_mission` (l.23784) et, par l'amendement de la décision 1
  (seconde revue fraîche de T0), `fn_generer_code_secours_mission` (l.37455), générateur du code de secours que
  `fn_valider_code_secours` consomme.

```sql
CREATE OR REPLACE FUNCTION "public"."fn_pointer_arrivee"("p_mission_id" "uuid", "p_lat" numeric DEFAULT NULL::numeric, "p_lng" numeric DEFAULT NULL::numeric, "p_precision" numeric DEFAULT NULL::numeric, "p_terminal_id" "text" DEFAULT NULL::"text", "p_modele" "text" DEFAULT NULL::"text", "p_code_arrivee" "text" DEFAULT NULL::"text") RETURNS "jsonb"
CREATE OR REPLACE FUNCTION "public"."fn_pointer_depart"("p_presence_id" "uuid", "p_lat" numeric DEFAULT NULL::numeric, "p_lng" numeric DEFAULT NULL::numeric, "p_precision" numeric DEFAULT NULL::numeric, "p_terminal_id" "text" DEFAULT NULL::"text", "p_modele" "text" DEFAULT NULL::"text", "p_code_depart" "text" DEFAULT NULL::"text") RETURNS "jsonb"
CREATE OR REPLACE FUNCTION "public"."fn_pointer_debut_pause"("p_presence_id" "uuid", "p_motif" "text" DEFAULT 'DEJEUNER'::"text") RETURNS "jsonb"
CREATE OR REPLACE FUNCTION "public"."fn_pointer_fin_pause"("p_presence_id" "uuid") RETURNS "jsonb"
CREATE OR REPLACE FUNCTION "public"."fn_valider_scan_qr"("p_token" "text", "p_lat" numeric DEFAULT NULL::numeric, "p_lng" numeric DEFAULT NULL::numeric, "p_precision" numeric DEFAULT NULL::numeric, "p_terminal_id" "text" DEFAULT NULL::"text") RETURNS "jsonb"
CREATE OR REPLACE FUNCTION "public"."fn_generer_qr_mission"("p_mission_id" "uuid", "p_type" "text" DEFAULT 'UNIVERSEL'::"text") RETURNS "jsonb"
CREATE OR REPLACE FUNCTION "public"."fn_valider_code_secours"("p_mission_id" "uuid", "p_code" "text", "p_lat" numeric DEFAULT NULL::numeric, "p_lng" numeric DEFAULT NULL::numeric, "p_precision" numeric DEFAULT NULL::numeric, "p_terminal_id" "text" DEFAULT NULL::"text") RETURNS "jsonb"
CREATE OR REPLACE FUNCTION "public"."fn_codes_pointage_mission"("p_mission_id" "uuid") RETURNS "jsonb"
CREATE OR REPLACE FUNCTION "public"."fn_generer_code_secours_mission"("p_mission_id" "uuid", "p_type" "text" DEFAULT 'UNIVERSEL'::"text") RETURNS "jsonb"
```

- **Toujours appelables** (revue fraîche de T0) : « mortes » côté web, les neuf RPC sont toujours GRANT
  `authenticated` en production (`public.sql` l.81953, l.83013, l.83079, l.83997, l.84003, l.84009, l.84015,
  l.85495, l.85523) : PostgREST les sert à tout compte connecté. Au moins trois gardes (≥ 3) d'accès en logique
  ternaire (`mon_etablissement_id()` NULL pour un soignant) permettent à un soignant de pointer à distance :
  1. `fn_codes_pointage_mission` (l.23799) lui rend `code_arrivee` et `code_depart`, que `fn_pointer_arrivee` et
     `fn_pointer_depart` acceptent sans GPS avec `perimetre_gps_valide = true` (l.47449-47455, l.47577-47582) ;
  2. `fn_generer_qr_mission` (l.38006) laisse le soignant assigné générer son propre jeton, que `fn_valider_scan_qr`
     accepte (GPS non bloquant) ;
  3. `fn_generer_code_secours_mission` (garde l.37478, `NOT (est_admin() OR v_mission.etablissement_id =
     mon_etablissement_id())`, GRANT l.83013) rend au soignant un code de secours **en clair** (l.37510-37517), que
     `fn_valider_code_secours` (l.64991) accepte en ne vérifiant que l'affectation (l.65012), sans contrôle de
     position dans la RPC (coordonnées facultatives, enregistrées telles quelles ; sans coordonnées,
     `dec_antifraude_presence` ne recalcule rien, l.646), et inscrit la présence `CODE_SECOURS` (l.65067-65072,
     l.65085-65091).
  Constat B9 de `DECISIONS_LOT2.md` (« En attente de Gabrielle »), à confirmer sur la définition live par une PR
  backend séparée ; proposition : `REVOKE EXECUTE … FROM authenticated` sur les neuf RPC (générateur du code de
  secours compris) après vérification de `SyncHorsLigne`, ou gardes `IS DISTINCT FROM` sur
  `fn_codes_pointage_mission`, `fn_generer_qr_mission` et `fn_generer_code_secours_mission`, avec un rejet
  explicite. Le natif n'en dépend pas.
- **Pourquoi** (`LOT2_PLAN.md` corrections 1 à 3) : depuis la PR #664 (22/06/2026), le seul composant de pointage
  monté côté soignant est `PointageRotatifSoignant` (via `BlocPointageMission`, `PresencesSoignant.tsx`), qui
  n'appelle que `fn_etat_pointage_mission` et `fn_scanner_code_pointage`. `pointerArrivee` et `pointerDepart`
  (`PresencesSoignant.tsx`) ne sont appelés nulle part ; `CartePointage` (qui monte `ScannerQRPointageSoignant` et
  `SaisieCodeSecours`) n'est importé par aucune page ; `src/lib/qr-offline-queue.ts` n'est importé que par
  `CartePointage.tsx`. `SyncHorsLigne` reste monté (`LayoutApp.tsx`) et rejoue `fn_pointer_*` depuis
  `src/lib/horsLigne.ts`, alimenté seulement par `stockerPointageHorsLigne`, appelée uniquement dans les fonctions
  mortes `pointerArrivee` / `pointerDepart` : résidu web, non reproduit. Côté
  établissement, le QR affiché par `AffichageCodeRotatifEtab` encode `code_pointage_actif`, pas un jeton de
  `fn_generer_qr_mission` ; `QRPointageEtab` (seul appelant de `fn_generer_code_secours_mission` et de
  `fn_generer_qr_mission`) n'est monté par aucun écran (seul un test l'importe) et `SaisieCodeSecours` (seul appelant
  de `fn_valider_code_secours`) n'est monté que par `CartePointage`. Porter ① ajouterait deux chemins dont le contrôle
  « contrat signé » n'est pas dans la RPC elle-même (`fn_valider_scan_qr` et `fn_valider_code_secours` ne le
  vérifient pas, alors que `fn_pointer_arrivee` le fait, l.47439-47440, et `fn_scanner_code_pointage` à chaque
  OUVERTURE, l.55670-55678) : seul le trigger de première arrivée le fait (`trg_01_exiger_conformite_premier_pointage`,
  `BEFORE INSERT OR UPDATE OF pointage_arrivee_le ON presences`, l.75592, fonction l.67759 →
  `fn_exiger_conformite_demarrage_mission`, l.35858 : `SIGNE_COMPLET` et les deux signatures, l.35910-35921) ; ①
  reste bloquant pour les missions multi-jours, et sa file hors ligne rejoue automatiquement (contraire à
  `PRINCIPES.md` §4).
- **Équivalents natifs** : pauses = FERMETURE puis OUVERTURE de `fn_scanner_code_pointage` ; code de secours =
  saisie manuelle des six chiffres du code rotatif ; « pointage sans téléphone » = déclaration de fin
  rétroactive côté établissement (web).
- **Garde de revue** : `tests/node/check-rpc-contracts.node.mjs` échoue si `pointerArrivee` ou `pointerDepart`
  redevient appelé dans `PresencesSoignant.tsx`, si `CartePointage` est de nouveau importé, si
  `qr-offline-queue` gagne un importeur, si `stockerPointageHorsLigne` gagne un importeur ou un appel hors de
  `pointerArrivee` / `pointerDepart` (le rejoueur `SyncHorsLigne` reprendrait du service), ou si
  `PointageRotatifSoignant` appelle une autre RPC, si `QRPointageEtab` est de nouveau monté ou si `SaisieCodeSecours`
  gagne un importeur : la décision 1 est alors à revoir. Elle échoue aussi quand une PR backend retire le GRANT
  `authenticated` de l'une des neuf RPC ou corrige l'une des trois gardes : basculer alors le paragraphe « Toujours
  appelables » et le constat B9, au moment fixé par `DECISIONS_LOT2.md` « Ordonnancement et branches ».

## Interdite côté natif : `fn_creer_notification`

- **Statut natif** : **jamais** (`RPC_JAMAIS_SUIVIES` ; `DECISIONS_LOT2.md` décision 9).
- **Pourquoi** : après une contestation de présence, le web appelle `fn_creer_notification` (`PanneauContestation.tsx`
  l.147-155, type `CONTESTATION_PRESENCE`) pour prévenir l'autre partie. L'insertion du litige déclenche déjà
  `trg_notifier_creation_litige` (`AFTER INSERT ON litiges`, `public.sql` l.76080) : l'appel client crée un doublon
  et suppose le droit, pour tout compte authentifié, d'écrire une notification arbitraire à un destinataire de son
  choix (`fn_creer_notification` l.27450). Le natif ne reproduit pas cet appel ; la relecture du litige suffit.
- **Constat B9** (revue fraîche de T0, `DECISIONS_LOT2.md` « En attente de Gabrielle ») : la fonction est
  `SECURITY DEFINER` (l.27450-27475), toujours GRANT `authenticated` (`public.sql` l.82276), et son seul contrôle
  est `auth.uid() IS NULL` (refus des appels anonymes hors cron, l.27461-27463) : tout compte connecté peut écrire
  une notification arbitraire (destinataire, type, titre, corps, `lien`). `docs/audit-fonctionnel-pre-lancement.md`
  l.177 la marque pourtant « ✅ FIXÉ » (seul ce contrôle d'authentification a été ajouté). À confirmer sur la
  définition live par une PR backend séparée ; la garde rougit si le GRANT disparaît ou si le destinataire est
  contrôlé.
- **Garde** : `verifierExclusions` refuse son entrée dans `RPC_SUIVIES` ; la garde des littéraux Swift la signale.

## Hors périmètre de ce document

Les RPC publiques consommées par le second client sans persistance (plan §4.1 : cinq RPC `PUBLIC_VOLONTAIRE`)
et les RPC établissement du lot 5 (`fn_traiter_candidature_planning_v1`, `fn_creer_mission_multi_jours_v4`,
`fn_mes_permissions_etab`) seront ajoutées à `RPC_SUIVIES` dans `scripts/mobile/check-rpc-contracts.mjs`
au lot qui les consomme, jamais avant.
