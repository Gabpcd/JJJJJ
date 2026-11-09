# Contrats RPC du parcours soignant (lot 0, plan §11 jour 8 ; lots 1 et 3, T0)

Document de référence des quarante et une RPC que le client Swift consomme ou consommera (seize au lot 0,
onze ajoutées par la tranche T0 du lot 1, `docs/mobile-swift/LOT1_PLAN.md` §3, quatorze par la tranche T0 du
lot 3, `docs/mobile-swift/LOT3_PLAN.md` §3), plus des fiches hors RPC : l'edge function `delete-account`
(suppression de compte, Apple 5.1.1) et l'interdiction de `fn_etablissement_public` côté natif (lot 1) ; les
edges `register-soignant`, `stripe-connect-status` et `stripe-connect-onboard`, le payload de `send-push`,
l'interdiction de `fn_lier_iban_verifie_document` et PSC non consommé (lot 3). Pour chaque RPC : la
signature SQL exacte extraite de `supabase/schema/public.sql` (dump de production re-baseliné par
`schema-snapshot.yml`), la classe d'authentification du manifeste `supabase/SECURITY_DEFINER_MANIFEST.json`
(capture production du 2026-07-29, 422 fonctions), le GRANT connu, la signature TypeScript de
`src/integrations/supabase/types.ts` et l'emplacement de l'exemple de réponse STAGING à enregistrer en semaine 2.

Le fichier machine correspondant est `ios-native/rpc-contracts.json`, régénéré et comparé par
`node scripts/mobile/check-rpc-contracts.mjs` dans le job « Cœur — golden et contrats » de
`.github/workflows/ios-swift-ci.yml`. Toute dérive de signature, de GRANT ou de classe fait échouer la CI ;
`--update` réécrit le JSON après relecture des gateways Swift. Le présent document est lui-même gardé par
`tests/node/check-rpc-contracts.node.mjs` (une fiche par RPC suivie, RPC interdites, formes de réponse
confrontées à `public.sql` et à l'edge `delete-account`) et, pour le lot 3, par
`tests/node/check-rpc-contracts-lot3.node.mjs` (formes de réponse confrontées aux corps SQL, aux edges et aux
pages web citées), exécutés sur toute PR par l'étape « Garde de
livraison mobile » du check requis « Typecheck + build » de `.github/workflows/validate-pr.yml`.

**Re-baseline du schéma (procédure).** Parce que cette garde tourne dans un check requis, une PR
automatique `auto/schema-baseline` (`schema-snapshot.yml`) qui modifie l'une des RPC suivies
(signature, GRANT, ou corps dont une fiche cite les réponses) reste bloquée — c'est voulu, fail-closed — et
`drift-check.yml` reste rouge tant qu'elle n'est pas mergée. Ne jamais corriger sur `auto/schema-baseline` :
le `git push --force` du run suivant efface tout commit manuel. Procédure : une **PR humaine**, depuis une
branche dédiée, porte le dump (`supabase/schema/public.sql` de la PR automatique ou de l'artefact
`schema-public-sql`) ; après relecture de la définition live (`scripts/dump-live-def.sh`) et des gateways
Swift concernées, elle ajoute `node scripts/mobile/check-rpc-contracts.mjs --update` (nouveau
`ios-native/rpc-contracts.json`) et la fiche ajustée dans ce document ; CI verte et revue fraîche, merge,
puis fermeture de la PR automatique devenue sans objet (le run suivant de `schema-snapshot.yml` ne trouve
plus de diff).

**Autres sources lues par la garde.** Outre les RPC suivies, la garde du lot 1 lit : les corps de six fonctions non suivies (`fn_conflit_planning_soignant`, `fn_postuler_mission`, `fn_postuler_mission_rate_limited`, `fn_finaliser_attribution_mission`, `fn_resoudre_contrat_mission`, `fn_demander_confirmations_presence`) ; le web `src/pages/DetailMissionSoignant.tsx` (chaînes de présence, tests `data?.choix_requis`, classement « mission perdue ») et `src/lib/erreurs.ts` (`estBlocageCodeTravail`) ; l'edge `supabase/functions/delete-account/index.ts` et `supabase/functions/_shared/admin-auth.ts` ; tout littéral `"fn_…"` des fichiers `ios-native/**/*.swift`. La garde du lot 3 (`tests/node/check-rpc-contracts-lot3.node.mjs`) lit en outre : les corps de `fn_reserver_type_compte` et `fn_lier_iban_verifie_document`, les contraintes `notifications_type_check` et `stripe_connect_onboarding_statut_check`, `journaux_audit_action_check`, l'index `uq_litige_mission_type_ouvert_legacy`, les enums `canal_notification` et `type_evenement_notification` ; les edges `supabase/functions/register-soignant/index.ts`, `supabase/functions/stripe-connect-status/index.ts`, `supabase/functions/stripe-connect-onboard/index.ts`, `supabase/functions/send-push/index.ts`, `supabase/functions/_shared/apns-client.ts`, `supabase/functions/_shared/errors.ts` et `supabase/functions/_shared/admin-auth.ts` ; le web `src/pages/InscriptionRapide.tsx` (message du 23505) et `src/pages/PageStripeConnect.tsx` (texte du compte de test) ; `ios-native/Packages/JoleneCore/Sources/JoleneCore/Links/LinkRouter.swift` (route PSC vers Safari). Une PR web, edge ou de re-baseline qui modifie l'une de ces sources met la fiche concernée à jour **dans la même PR**.

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

Règles ajoutées au lot 3 (`LOT3_PLAN.md` §2.4, corrections 12 et 16) : les exceptions métier PostgREST (22023,
23505, P0002 de `fn_demarrer_inscription`, `fn_enregistrer_parcours_inscription` et `fn_upsert_token_push`) sont
lues **avant** `SupabaseErrorMapping` par une liste `exceptionsMetier` propre à chaque appel, comme
`[CODE DU TRAVAIL]` au lot 1 ; 42501 reste `.unauthorized` et PGRST202 `.contract`. Une RPC qui renvoie `void`
(`fn_upsert_token_push`) répond sans corps JSON : elle est appelée par `execute()` sans décodage (204 ou 200 à
corps vide = succès), jamais par `RPCResponse.appeler`. Les edges (`register-soignant`, `stripe-connect-status`,
`stripe-connect-onboard`) sont décodées par `EdgeResponse`, qui lit le corps de `FunctionsError.httpError` avant
tout mapping. Un succès n'est admis que sur le drapeau serveur (`success == true`, `ok == true`) suivi d'une
relecture ; un `error_code` sans `error` est un refus, jamais un succès (IBAN). Aucune RPC réservée au
`service_role` n'est appelée (fiche « Interdite côté natif : `fn_lier_iban_verifie_document` »). Les trois actions
d'audit écrites par l'app au lot 3 (`DONNEES_PERSO_CONSULTATION`, `DONNEES_PERSO_MODIFICATION`,
`RGPD_EXPORT_DONNEES`, via `fn_ecrire_audit_safe`) figurent dans `journaux_audit_action_check`.

## Synthèse

| RPC | Statut natif | Lot | Classe manifeste | GRANT | types.ts |
|---|---|---|---|---|---|
| `fn_get_my_role` | consommée lot 0 | 0 | MIXTE_TENANT_ADMIN | authenticated, service_role | déclarée |
| `fn_etablissements_safe` | consommée lot 0 | 0 | MIXTE_TENANT_ADMIN | authenticated, service_role | déclarée |
| `fn_mon_profil_soignant_complet` | consommée lot 3 (T9) | 3 (T9 ; reclassée, lot 1 v2 n°4) | RPC_UTILISATEUR_AUTH_INTERNE | authenticated, service_role | déclarée |
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
| `fn_upsert_token_push` | consommée lot 3 (T4) | 3 (T4) | RPC_UTILISATEUR_AUTH_INTERNE | authenticated, service_role | déclarée |
| `fn_desactiver_mon_token_push` | consommée lot 3 (T4) | 3 (T4) | RPC_UTILISATEUR_AUTH_INTERNE | authenticated, service_role | déclarée |
| `fn_obtenir_mes_preferences_notifications` | consommée lot 3 (T6) | 3 (T6) | RPC_UTILISATEUR_AUTH_INTERNE | authenticated, service_role | déclarée |
| `fn_modifier_preferences_notifications` | consommée lot 3 (T6) | 3 (T6) | RPC_UTILISATEUR_AUTH_INTERNE | authenticated, service_role | déclarée |
| `fn_demarrer_inscription` | consommée lot 3 (T7) | 3 (T7) | hors manifeste — classée RPC_UTILISATEUR_AUTH_INTERNE (T0 du lot 3) | authenticated, service_role | absente |
| `fn_enregistrer_parcours_inscription` | consommée lot 3 (T8) | 3 (T8) | hors manifeste — classée RPC_UTILISATEUR_AUTH_INTERNE (T0 du lot 3) | authenticated, service_role | absente |
| `fn_types_exercice_autorises` | consommée lot 3 (T8) | 3 (T8) | PUBLIC_VOLONTAIRE | anon, authenticated, service_role | déclarée |
| `fn_modifier_mon_profil` | consommée lot 3 (T9) | 3 (T9) | RPC_UTILISATEUR_AUTH_INTERNE | authenticated, service_role | déclarée |
| `fn_rgpd_exporter_rate_limited` | consommée lot 3 (T11) | 3 (T11) | RPC_UTILISATEUR_AUTH_INTERNE | authenticated, service_role | déclarée |
| `fn_confirmer_paiement_soignant` | à venir | 3 (T13, B9) | RPC_UTILISATEUR_AUTH_INTERNE | authenticated, service_role | déclarée |
| `fn_contester_paiement_soignant` | à venir | 3 (T13, B3 mergée #1118, B9) | MIXTE_TENANT_ADMIN | authenticated, service_role | déclarée |
| `fn_consulter_mon_iban` | à venir | 3 (T14b, B9) | RPC_UTILISATEUR_AUTH_INTERNE | authenticated, service_role | déclarée |
| `fn_enregistrer_mon_iban` | à venir | 3 (T14b, B9) | RPC_UTILISATEUR_AUTH_INTERNE | authenticated, service_role | déclarée |
| `fn_mes_revenus_connect` | à venir | 3 (T12, T14a, B9) | RPC_UTILISATEUR_AUTH_INTERNE | authenticated, service_role | déclarée |
| `fn_mes_paiements_escrow` | à venir | 3 (T12, B9) | RPC_UTILISATEUR_AUTH_INTERNE | authenticated, service_role | absente |

Quatre RPC sont absentes de `types.ts` (`fn_confirmer_action_planning_v1`, `fn_param_bool`,
`fn_etat_pointage_mission`, `fn_remplacer_document_soignant`) : leur contrat est tenu par `public.sql` seul
jusqu'à régénération des types (`supabase gen types`) ; le web les appelle déjà avec `as any`
(`src/hooks/useParamBool.ts` l.18). Une RPC est hors manifeste (`fn_confirmer_action_planning_v1`, créée
après la capture du 2026-07-29) : **classée manuellement `RPC_UTILISATEUR_AUTH_INTERNE`** par la décision 6
du lot 1 (`LOT1_PLAN.md` §7), sans régénération du manifeste — voir sa fiche. `ios-native/rpc-contracts.json`
garde `manifeste: null` pour elle : c'est le fait observé, le classement est documentaire.

Lot 3 (T0, correction 13 du blueprint) : trois RPC de plus sont absentes de `types.ts` (`fn_demarrer_inscription`,
`fn_enregistrer_parcours_inscription`, `fn_mes_paiements_escrow`) ; deux sont hors manifeste
(`fn_demarrer_inscription`, `fn_enregistrer_parcours_inscription`, créées après la capture du 2026-07-29) et
**classées manuellement `RPC_UTILISATEUR_AUTH_INTERNE` dans leur fiche**, avec `manifeste: null` dans le JSON et
aucun fichier sous `supabase/` (PRINCIPES §1). `fn_types_exercice_autorises` est `PUBLIC_VOLONTAIRE` (GRANT `anon`) :
le natif l'appelle avec le JWT de la session d'inscription, jamais en anonyme.

Trois RPC ne sont pas suivies, pour des raisons différentes, et `verifierExclusions`
(`scripts/mobile/check-rpc-contracts.mjs`) fait échouer la CI si l'une d'elles y entre trop tôt :
**jamais** `fn_etablissement_public` et `fn_lier_iban_verifie_document` (lot 3 : service_role seul ; fiches
« Interdite côté natif » en fin de document) ; **pas avant le lot 4** `fn_retirer_candidature` (swipe), suivie au
plus tôt avec `lot: 4`. À part, `fn_mon_profil_soignant_complet`
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

- **Statut natif** : consommée (lot 3, T9) par `JoleneSupabase/Profil/SupabaseProfilGateway.swift`, appelée par
  `JoleneCore/Profil/ProfilEdition.swift` (`ProfilEditionModel`) ; reclassée lot 3 par le blueprint du lot 1
  (correction v2 n°4). Définition live relue en lecture seule le 08/11/2026 : corps identique au dump,
  `SECURITY DEFINER`, `search_path=public`, EXECUTE `authenticated`.
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
- **Contrat de réponse (HTTP 200, lot 3 T9)** : `{error:'Non authentifié'}` (l.44665) ; `{error:'Profil introuvable'}`
  (l.44681, aucune ligne `soignants`) ; sinon la ligne en jsonb (l.44667-44679). Décodage `ProfilComplet` en
  **liste blanche** stricte, avec test-garde par `Mirror` (T9, correction 7) : les clés sensibles `numero_secu`,
  `numero_adeli`, `siret_liberal`, `code_ape`, `assujetti_tva`, `numero_tva`, `stripe_account_id`, `iban_last4` sont
  renvoyées par le serveur et **jamais décodées** ; `adresse_lat` / `adresse_lng` sont décodées pour la localisation,
  jamais affichées ni journalisées. La RPC ne renvoie pas les clés `specialite_*` que lit le web (spécialité non
  éditée en natif). Audit `DONNEES_PERSO_CONSULTATION` best-effort à la lecture (web `ProfilSoignant.tsx` l.157-163).
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

- **Statut natif** : consommée (lot 3, T4) par `JoleneSupabase/Push/SupabasePushGateway.swift`, appelée par
  `JoleneCore/Push/PushCoordinator.swift`.
- **Usage** : Enregistrement du token APNs (`p_plateforme = IOS`) à chaque session (`.ready` d'un nouvel epoch) et
  au retour au premier plan, seulement si l'appareil autorise déjà les notifications (jamais de demande implicite, D1) ;
  identité vérifiée (epoch) avant l'appel ; token mémorisé (`KeychainPushTokenStore`, service `app.jolene.push`) après
  le succès. Contrat lu dans le dump du 01/11/2026 : `SECURITY DEFINER`, `search_path=pg_catalog, public`
  (l.64629-64630), EXECUTE `authenticated` et `service_role`, révoqué de `PUBLIC` (l.85471-85473).
- **Signature SQL** (`supabase/schema/public.sql` l.64628) :

```sql
CREATE OR REPLACE FUNCTION "public"."fn_upsert_token_push"("p_token" "text", "p_plateforme" "text" DEFAULT 'WEB'::"text") RETURNS "void"
    LANGUAGE "plpgsql" SECURITY DEFINER
    SET "search_path" TO 'pg_catalog', 'public'
```

- **Classe d'authentification (manifeste)** : `RPC_UTILISATEUR_AUTH_INTERNE` pour `fn_upsert_token_push(text,text)` — RPC utilisateur : identité `auth.uid()` lue en interne, appel avec le JWT du soignant.
- **GRANT connu** : `REVOKE ALL … FROM PUBLIC` puis `GRANT ALL … TO "authenticated", "service_role"`.
- **Signature TypeScript** (`types.ts`, section `Functions`) : `Args: { p_plateforme?: string; p_token: string }` ; `Returns: undefined`.
- **Contrat de réponse (lot 3, T4)** : la fonction renvoie `void` — succès = réponse PostgREST **sans corps JSON**
  (204, ou 200 à corps vide). `RPCResponse.appeler` décode toujours `AnyJSON` et lèverait une erreur de décodage sur
  ce succès : la gateway appelle `execute()` sans type de retour (correction 16, variante sans corps de T1).
  Exceptions, jamais `{error}` en HTTP 200 : **42501** `'Non authentifie'` (l.64642 : `auth.uid()` nul ou compte
  inactif → `.unauthorized` par le mapping) ; **22023** `'Token push invalide'` (l.64645, longueur hors 16-4096),
  `'Plateforme push invalide'` (l.64648, hors `WEB`, `IOS`, `ANDROID`), `'Abonnement Web Push JSON invalide'`
  (l.64661), `'Abonnement Web Push incomplet'` (l.64671), `'Abonnement Web Push JSON requis'` (l.64674) — les trois
  dernières ne concernent que le Web Push (token commençant par `{`) ; le natif envoie le token APNs en
  hexadécimal minuscule avec `p_plateforme = 'IOS'`. 22023 est lu par `exceptionsMetier` avant
  `SupabaseErrorMapping` → `.contract`, sans renvoi. `ON CONFLICT (token)` (l.64684) : un token réattribué à un autre
  utilisateur change de propriétaire et redevient `actif`. Best-effort côté app (`PushCoordinator`) : un échec
  n'entraîne jamais de déconnexion.
- **Preuve STAGING** : token factice DEBUG upserté puis `tokens_push` relu (`plateforme = 'IOS'`, `actif = true`),
  puis `actif = false` après déconnexion (T16).
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

## fn_desactiver_mon_token_push

- **Statut natif** : consommée (lot 3, T4) par `JoleneSupabase/Push/SupabasePushGateway.swift`, appelée par
  `JoleneCore/Push/PushCoordinator.swift` depuis `SessionStore.signOut`. Contrat lu dans le dump du 01/11/2026 :
  `SECURITY DEFINER` (l.30177), EXECUTE `authenticated` et `service_role`, révoqué de `PUBLIC` (l.82446-82448).
- **Usage** : Déconnexion volontaire : désactivation du token APNs mémorisé (`KeychainPushTokenStore`,
  service `app.jolene.push`) **avant** `controller.signOut()` — le JWT est requis (correction 11) —, bornée à
  **2,5 s** comme le web (`src/lib/pushDeviceToken.ts` l.90-92, l.113 ; décision D3), puis
  `unregisterForRemoteNotifications()` et oubli du token, que la RPC ait répondu ou non ; un second tap pendant
  l'appel est ignoré. Déconnexion subie (`.signedOut` du SDK, revalidation qui ne trouve plus de session, depuis
  un espace prêt ou bloqué) : désinscription locale seule, sans appel (JWT absent), après la publication de
  l'écran de connexion. Suppression de compte : désinscription locale avant la purge, sans appel. Lancement sans
  session (le SDK n'a rien restauré) avec un token laissé par une session précédente : désinscription locale et
  oubli, sans appel. Ces fins de session ne partent que d'une absence de session confirmée par
  `SessionController` (`absencesConfirmees`) : un `.signedOut` transitoire (restauration impossible hors ligne,
  rôle ou profil illisible, et au merge de L1-T9 le verrou biométrique) ne désinscrit rien et garde le token.
- **Signature SQL** (`supabase/schema/public.sql` l.30176) :

```sql
CREATE OR REPLACE FUNCTION "public"."fn_desactiver_mon_token_push"("p_token" "text") RETURNS "jsonb"
    LANGUAGE "plpgsql" SECURITY DEFINER
    SET "search_path" TO 'pg_catalog', 'public'
```

- **Classe d'authentification (manifeste)** : `RPC_UTILISATEUR_AUTH_INTERNE` pour `fn_desactiver_mon_token_push(text)` ; périmètre strict `utilisateur_id = auth.uid()`.
- **GRANT connu** : `REVOKE ALL … FROM PUBLIC` puis `GRANT ALL … TO "authenticated", "service_role"`.
- **Signature TypeScript** : `Args: { p_token: string }` ; `Returns: Json`.
- **Contrat de réponse (HTTP 200)** : `{success:false, error:'Non authentifie'}` (l.30187 : `auth.uid()` nul ou
  compte inactif) ; `{success:false, error:'Token push invalide'}` (l.30190 : longueur hors 16-4096) ;
  `{success:true, tokens_desactives:<n>, scope:'CURRENT_DEVICE'}` (l.30214-30218 ; `n` vaut 0 si le token
  n'appartient pas à l'utilisateur ou n'existe plus). Messages sans accent, comme la source. Refus, délai dépassé
  ou erreur de transport : journal DEBUG, la déconnexion locale a lieu quand même (jamais bloquant).
- **Preuve STAGING** : `tokens_push.actif = false` relu pour le token factice DEBUG du run, après déconnexion (T16).

## fn_obtenir_mes_preferences_notifications

- **Statut natif** : consommée (lot 3, T6) par `JoleneSupabase/Notifications/SupabasePreferencesGateway.swift`,
  appelée par `JoleneCore/Notifications/PreferencesModel.swift` (écran `PreferencesScreen`, entrée « Réglages ›
  Notifications » du hub Profil). Contrat lu dans le dump du 01/11/2026 (aucune relecture live : règle 4 du mémo
  des lots 2 à 5).
- **Usage** : Écran `/soignant/parametres/notifications` : lecture des quatre canaux globaux et des exceptions
  par événement (web `PageParametresNotifications.tsx` l.105-138), suivie, comme le web l.120-125, de
  `soignants.select('sms_alertes_actives, type_exercice').eq('id', <utilisateur de la session>)` en
  `maybeSingle` (aucune ligne → alerte SMS ni affichée ni écrite ; erreur → écran en erreur) ; relue après chaque
  enregistrement, seule preuve d'un succès. Décodage strict (`PreferencesNotifications.decoder`) : quatre booléens
  `canal_*`, chaque ligne `par_evenement` lisible (type non vide, canal de l'enum, `actif` booléen) ; une ligne
  illisible est une erreur d'écran, jamais une absence (qui vaudrait « actif »).
- **Signature SQL** (`supabase/schema/public.sql` l.45986) :

```sql
CREATE OR REPLACE FUNCTION "public"."fn_obtenir_mes_preferences_notifications"() RETURNS "jsonb"
    LANGUAGE "plpgsql" SECURITY DEFINER
    SET "search_path" TO 'public', 'extensions'
```

- **Classe d'authentification (manifeste)** : `RPC_UTILISATEUR_AUTH_INTERNE` pour `fn_obtenir_mes_preferences_notifications()`.
- **GRANT connu** : `REVOKE ALL … FROM PUBLIC` puis `GRANT ALL … TO "authenticated", "service_role"`.
- **Signature TypeScript** : `Args: never` ; `Returns: Json`.
- **Contrat de réponse (HTTP 200)** : `{error:'Non authentifié'}` (l.45995) ; sinon
  `{global:{canal_email, canal_sms, canal_push, canal_in_app, cree_le, mis_a_jour_le}, par_evenement:[{type_evenement, canal, actif}]}`
  (l.46015 : `global` = ligne `preferences_notifications` sans `utilisateur_id` ; `par_evenement` = `[]` sans
  exception). **Effet de bord** : la lecture crée la ligne par défaut si elle manque (l.46001-46006,
  `INSERT … ON CONFLICT DO NOTHING` ; défauts e-mail `true`, SMS `false`, push `true`, in-app `true`) — ce n'est
  pas une lecture pure, mais elle est idempotente. Les quatre booléens `canal_*` sont exigés (web l.117) : absents
  ou non booléens → erreur d'écran, jamais des défauts affichés.
- **Preuve STAGING** : préférences relues après enregistrement (T16).

## fn_modifier_preferences_notifications

- **Statut natif** : consommée (lot 3, T6) par `JoleneSupabase/Notifications/SupabasePreferencesGateway.swift`,
  appelée par `JoleneCore/Notifications/PreferencesModel.swift`. Contrat lu dans le dump du 01/11/2026.
- **Usage** : Enregistrement des canaux et de la matrice par événement ; l'app n'envoie que les types du
  catalogue soignant `EVENTS_SOIGNANT` (web `PageParametresNotifications.tsx` l.42-56 ; le filtre de régime n'en
  retire rien, la RPC mettant à jour par clé sans rien supprimer) puis relit `fn_obtenir_mes_preferences_notifications`
  après `{success:true}` ; « Préférences enregistrées » n'est annoncé que si la relecture concorde avec la demande.
  L'alerte SMS (`soignants.sms_alertes_actives`, GRANT de colonne l.85758) s'écrit à part, jamais par cette RPC :
  `PATCH soignants` de cette seule colonne (`return=minimal`, comme supabase-js), seulement si la ligne a été lue
  (web `profilSmsPresent`, l.230) ; son échec n'arrête pas la relecture, qui montre la valeur serveur, et l'écran
  annonce l'échec partiel du web (l.237). Aucun renvoi automatique ; une issue inconnue (délai dépassé, réseau)
  impose une relecture. Préférence, pas un consentement juridique (D18 : non B9).
- **Signature SQL** (`supabase/schema/public.sql` l.44100) :

```sql
CREATE OR REPLACE FUNCTION "public"."fn_modifier_preferences_notifications"("p_canal_email" boolean DEFAULT NULL::boolean, "p_canal_sms" boolean DEFAULT NULL::boolean, "p_canal_push" boolean DEFAULT NULL::boolean, "p_canal_in_app" boolean DEFAULT NULL::boolean, "p_par_evenement" "jsonb" DEFAULT NULL::"jsonb") RETURNS "jsonb"
    LANGUAGE "plpgsql" SECURITY DEFINER
    SET "search_path" TO 'public', 'extensions'
```

- **Classe d'authentification (manifeste)** : `RPC_UTILISATEUR_AUTH_INTERNE` pour `fn_modifier_preferences_notifications(boolean,boolean,boolean,boolean,jsonb)`.
- **GRANT connu** : `REVOKE ALL … FROM PUBLIC` puis `GRANT ALL … TO "authenticated", "service_role"`.
- **Signature TypeScript** : `Args: { p_canal_email?: boolean; p_canal_in_app?: boolean; p_canal_push?: boolean; p_canal_sms?: boolean; p_par_evenement?: Json }` ; `Returns: Json`.
- **Contrat de réponse** : `{error:'Non authentifié'}` (l.44108) ; `{success:true}` (l.44147). Un canal `NULL`
  reste inchangé (`COALESCE`, l.44118-44121). `p_par_evenement` = tableau `[{type_evenement, canal, actif}]`
  casté en enums (l.44130-44131) : une valeur hors enum lève **22P02** (exception PostgREST, transaction annulée)
  → `.contract`, jamais un succès. `canal` ∈ `EMAIL`, `SMS`, `PUSH`, `IN_APP` (`canal_notification`) ;
  `type_evenement` ∈ les dix-huit valeurs de `type_evenement_notification` : `NOUVELLE_MISSION_MATCHANT_FILTRE`,
  `CANDIDATURE_RECUE`, `CANDIDATURE_ACCEPTEE`, `MISSION_ASSIGNEE`, `RAPPEL_J1_MISSION`, `POINTAGE_MANQUANT`,
  `FACTURE_EMISE`, `PAIEMENT_RECU`, `CONTRAT_TRAVAIL_DEPOSE`, `LITIGE_OUVERT`, `LITIGE_RESOLU`, `DOCUMENT_EXPIRANT`,
  `MANDAT_RE_SIGNATURE`, `SERIE_ONBOARDING`, `URGENCE`, `NOUVEAU_SOIGNANT_MATCHANT_FILTRE`,
  `FAVORI_NOUVELLE_MISSION`, `NOTATION_RAPPEL`. Audit `PREFERENCE_NOTIFICATION_MODIFIEE` écrit par la RPC
  (l.44138-44145, action présente dans `journaux_audit_action_check`) : l'app n'en écrit pas.
- **Preuve STAGING** : préférences enregistrées puis relues (T16).

## fn_demarrer_inscription

- **Statut natif** : consommée (lot 3, T7) par `JoleneSupabase/Inscription/SupabaseInscriptionGateway.swift`, appelée par
  `JoleneCore/Inscription/InscriptionModels.swift` (`InscriptionRapideModel` après un `signUp` qui ouvre la session ou
  « Je suis soignant » ; `OnboardingModel` sur l'intention `user_metadata.inscription_progressive` sans parcours) —
  **B9** (consentement CGU relayé par `p_cgu`, D18) : PR préparée, jamais mergée sans le go de Gabrielle. Exceptions
  restituées par `exceptionsMetier` 22023 et 23505 (`SupabaseInscriptionGateway.exceptionsDemarrage`), traduites par
  `InscriptionRules.refusDemarrage` ; la ligne rendue est relue en liste blanche (`OnboardingResolution.parcours`,
  propriétaire = utilisateur de la session). Le parcours est lu sous RLS (`parcours_inscription`,
  `user_id,type_compte,donnees,consentement_cgu_le,modifie_le`). Lignes du dump re-baseliné : définition l.30148-30189,
  exceptions l.30159, l.30163, l.30167, l.30176.
- **Usage prévu** : Création du parcours d'inscription après un `signUp` qui ouvre la session, ou à la première
  session au rôle `INCONNU` portant l'intention `user_metadata.inscription_progressive` (repli de `useRole.ts`
  l.150-170) ; paramètres de l'intention web (`src/lib/inscriptionProgressive.ts` l.26-39) : `p_type_compte = 'SOIGNANT'`,
  `p_profession`, `p_nom = null`, `p_cgu = true` (case CGU cochée, texte verbatim), `p_cgv = false`.
- **Signature SQL** (`supabase/schema/public.sql` l.30099) :

```sql
CREATE OR REPLACE FUNCTION "public"."fn_demarrer_inscription"("p_type_compte" "text", "p_profession" "text" DEFAULT NULL::"text", "p_nom" "text" DEFAULT NULL::"text", "p_cgu" boolean DEFAULT false, "p_cgv" boolean DEFAULT false) RETURNS "jsonb"
    LANGUAGE "plpgsql" SECURITY DEFINER
    SET "search_path" TO 'pg_catalog', 'public', 'auth'
```

- **Classe d'authentification (manifeste)** : hors manifeste (absente de la capture du 2026-07-29) — classée manuellement `RPC_UTILISATEUR_AUTH_INTERNE` par la T0 du lot 3 (`SECURITY DEFINER`, identité `auth.uid()` lue en interne l.30104, GRANT `authenticated`) ; classement documentaire dans cette fiche seulement (correction 13) : `manifeste: null` dans `ios-native/rpc-contracts.json`, aucun fichier sous `supabase/` modifié (PRINCIPES §1).
- **GRANT connu** : `GRANT ALL … TO "service_role"` et `TO "authenticated"` (l.82435-82436).
- **Signature TypeScript** : absente de `types.ts` (le web appelle avec `as any`).
- **Contrat de réponse** : succès = la ligne `parcours_inscription` en jsonb (`to_jsonb`, l.30138) :
  `{user_id, type_compte, donnees:{profession}, consentement_cgu_le, consentement_cgv_le, cree_le, modifie_le}`.
  `consentement_cgu_le` est posé par le défaut de colonne à l'INSERT (table l.70971) : c'est la preuve serveur du
  consentement que `register-soignant` reprend dans l'audit `RGPD_CONSENTEMENT_DONNE`, d'où B9. `ON CONFLICT (user_id)
  DO NOTHING` (l.30134) : un second appel rend la ligne existante, sans erreur. **Exceptions** (jamais `{error}` en
  HTTP 200), lues par `exceptionsMetier` avant `SupabaseErrorMapping` (correction 12) :
  - **42501** `'Session invalide.'` (l.30110) → `.unauthorized` ;
  - **22023** `'Vérifiez le type de compte et les conditions acceptées.'` (l.30114), `'Choisissez votre profession.'`
    (l.30118), `'Indiquez le nom de votre établissement.'` (l.30120, établissement seulement) → message verbatim ;
  - **23505** dont le message **est** le code de réservation de `fn_reserver_type_compte`
    (`RAISE EXCEPTION '%', v_reservation ->> 'code'`, l.30127) : `ACCOUNT_TYPE_INVALID`, `ACCOUNT_AUTH_INACTIVE`,
    `ACCOUNT_PROFILE_CONFLICT`, `ACCOUNT_TYPE_MISMATCH`, `ACCOUNT_ALREADY_REGISTERED`,
    `ACCOUNT_REGISTRATION_INCOMPLETE`, `ACCOUNT_REGISTRATION_IN_PROGRESS` (`fn_reserver_type_compte` l.54203-54296).
    Le web (`src/pages/InscriptionRapide.tsx` l.98-101) affiche « Ce compte possède déjà un espace Jolene. Connectez-vous pour le retrouver. »
    pour `ACCOUNT_ALREADY_REGISTERED`, `ACCOUNT_TYPE_MISMATCH` et `ACCOUNT_REGISTRATION_INCOMPLETE`, et son message
    générique (`mapperErreurInscription`) pour les autres ; le natif reprend les mêmes textes.
- **Preuve STAGING** : ligne `parcours_inscription` relue après le `signUp` de l'app (T16).

## fn_enregistrer_parcours_inscription

- **Statut natif** : consommée (lot 3, T8) par `JoleneSupabase/Inscription/SupabaseInscriptionGateway.swift`, appelée par
  `JoleneCore/Inscription/CompletionProfilModel.swift` (« Enregistrer et continuer plus tard », puis avant
  `register-soignant` comme `finaliserProfil` l.178) — **B9** (inscription, D18). Définition live relue en lecture seule
  le 09/11/2026 (`pg_get_functiondef`) : corps identique au dump, `SECURITY DEFINER`, EXECUTE `authenticated` (pas
  `anon`). Clés envoyées : `CompletionRules.clesBrouillon` ; 22023 et P0002 restitués par `exceptionsMetier`, message
  serveur verbatim (`RefusInscription`) ; ligne relue en liste blanche, propriétaire vérifié.
- **Usage prévu** : Brouillon **serveur** de la complétion (`/inscription/completer`), enregistré à chaque étape
  (jamais de brouillon local, `LOT3_PLAN.md` §2.6) ; l'app n'envoie que des clés de la liste blanche (web
  `inscriptionProgressive.ts` l.117-124), jamais mot de passe, email, jeton ni coordonnées (`lat`, `lng` sont aussi
  exclues par `restaurerFormulaire`, l.132).
- **Signature SQL** (`supabase/schema/public.sql` l.32423) :

```sql
CREATE OR REPLACE FUNCTION "public"."fn_enregistrer_parcours_inscription"("p_donnees" "jsonb") RETURNS "jsonb"
    LANGUAGE "plpgsql" SECURITY DEFINER
    SET "search_path" TO 'pg_catalog', 'public', 'auth'
```

- **Classe d'authentification (manifeste)** : hors manifeste (absente de la capture du 2026-07-29) — classée manuellement `RPC_UTILISATEUR_AUTH_INTERNE` par la T0 du lot 3 (`SECURITY DEFINER`, `auth.uid()` lu en interne l.32429 et l.32455, GRANT `authenticated`) ; classement documentaire dans cette fiche seulement (correction 13) : `manifeste: null` dans `ios-native/rpc-contracts.json`, aucun fichier sous `supabase/` modifié (PRINCIPES §1).
- **GRANT connu** : `GRANT ALL … TO "service_role"` et `TO "authenticated"` (l.82591-82592).
- **Signature TypeScript** : absente de `types.ts`.
- **Contrat de réponse** : succès = la ligne `parcours_inscription` mise à jour (`donnees = donnees || p_donnees`,
  fusion de premier niveau, l.32454-32457). **Exceptions** :
  - **42501** `'Session invalide.'` (l.32430) ;
  - **22023** `'Brouillon invalide.'` (l.32433 : non-objet ou plus de 32 768 octets), `'Champ non autorisé dans le brouillon.'`
    (l.32442), `'Brouillon de mission invalide.'` (l.32448), `'Choix des internes invalide dans le brouillon.'`
    (l.32453) — les deux derniers ne concernent que le parcours établissement ;
  - **P0002** `'Inscription introuvable.'` (l.32456 : aucun parcours, `fn_demarrer_inscription` jamais appelée).
  Liste blanche des clés de premier niveau (l.32436-32441) : `profession`, `prenom`, `nom`, `telephone`,
  `dateNaissance`, `typesContrat`, `rpps`, `rayon`, `estSalarieEtablissement`, `estEtudiant`, `scolariteFormation`,
  `scolariteAnnee`, `siret`, `finess`, `type`, `rue`, `ville`, `codePostal`, `departement`, `emailContact`,
  `telephoneContact`, `numeroLicence`, `missionProfession`, `missionVille`, `missionDate`, `missionDebut`,
  `missionFin`, `missionChoisie`, `brouillonMission`, `missionFormulaire`. Clés soignant envoyées par le natif :
  `prenom`, `nom`, `telephone`, `dateNaissance`, `typesContrat`, `rpps`, `rayon`, `estSalarieEtablissement` (réponse
  « salarié(e) » enregistrée et restaurée comme le web, jamais transmise à `register-soignant`, correction 21 ; revue B8
  de T8, m4). `estEtudiant`, `scolariteFormation`, `scolariteAnnee` : lues seulement, jamais écrites par le natif ; un
  brouillon `estEtudiant: true` n'est jamais finalisé en natif (D11, revue B8 de T8, B1).
- **Preuve STAGING** : brouillon relu dans `parcours_inscription.donnees` pendant la complétion (T16).

## fn_types_exercice_autorises

- **Statut natif** : consommée (lot 3, T8) par `JoleneSupabase/Inscription/SupabaseInscriptionGateway.swift`, appelée par
  `JoleneCore/Inscription/CompletionProfilModel.swift` et par l'édition du profil (`ProfilEditionModel`, T9 : « Réessayer
  la vérification » effectif depuis T8). Définition live relue en lecture seule le 09/11/2026 : corps identique au dump,
  EXECUTE `authenticated` et `anon`. Réponse : tableau de chaînes, sinon nil (indisponible, jamais supposé) ; référentiel
  démo `demo-types-exercice.json` lu dans le seed `20260714084802_synchroniser_regles_profil_exercice.sql`.
- **Usage prévu** : Contrats proposés à la complétion selon la profession du parcours (lecture seule de
  `parcours.donnees.profession`), depuis la **table paramétrée** `regles_exercice_profession` (zéro règle en dur) ;
  web `src/hooks/useTypesExerciceAutorises.ts` l.30, `InscriptionSoignant.tsx` l.92-97 et l.192-199.
- **Signature SQL** (`supabase/schema/public.sql` l.64333) :

```sql
CREATE OR REPLACE FUNCTION "public"."fn_types_exercice_autorises"("p_profession" "text") RETURNS "text"[]
    LANGUAGE "plpgsql" STABLE SECURITY DEFINER
    SET "search_path" TO 'public'
```

- **Classe d'authentification (manifeste)** : `PUBLIC_VOLONTAIRE` pour `fn_types_exercice_autorises(text)` — référentiel public (commentaire SQL « SECURITY DEFINER anonyme revue : référentiel public. »), d'où le GRANT `anon` ; le natif l'appelle **avec le JWT** de la session d'inscription, jamais en anonyme.
- **GRANT connu** : `GRANT ALL … TO "authenticated"`, `TO "anon"`, `TO "service_role"` (l.85428-85430).
- **Signature TypeScript** : `Args: { p_profession: string }` ; `Returns: string[]`.
- **Contrat de réponse** : un tableau `text[]` nu, jamais `{error}` ; `COALESCE(v_result, ARRAY['SALARIE', 'LIBERAL', 'MIXTE'])`
  (l.64342) : une profession absente de la table rend `SALARIE`, `LIBERAL`, `MIXTE` (défaut serveur, pas un refus).
  Indisponible (transport, délai) → message web verbatim de `InscriptionSoignant.tsx` l.92-97 et `LIBERAL` retiré
  tant que non confirmé (l.192-199).

## fn_modifier_mon_profil

- **Statut natif** : consommée (lot 3, T9) par `JoleneSupabase/Profil/SupabaseProfilGateway.swift`, appelée par
  `JoleneCore/Profil/ProfilEdition.swift` (`ProfilEditionModel`) ; T10 y ajoute `p_avatar_url` (seul paramètre de
  `EnvoiAvatar`, `JoleneCore/Profil/EnvoiAvatar.swift`, après le dépôt Storage, puis relecture de `avatar_url`) et la
  position `p_adresse_lat` / `p_adresse_lng` (« Utiliser ma position actuelle », toujours en paire, envoyée avec
  « Enregistrer les modifications ») ; `p_adresse_rue`, `p_adresse_ville`, `p_adresse_code_postal` restent jamais
  envoyés. Définition live relue en lecture seule le 08/11/2026 :
  corps identique au dump, `SECURITY DEFINER`, `search_path=pg_catalog, public`, EXECUTE `authenticated`.
- **Usage prévu** : Édition du profil natif (identité, téléphone, date de naissance, RPPS non vérifié, rayon, ville
  de recherche, taux minimum, contrats acceptés, bio, années d'expérience ; avatar et position en T10) puis relecture
  `fn_mon_profil_soignant_complet`. **Jamais** envoyés par le natif : `p_type_exercice`, `p_attestation_cumul_activite`,
  `p_est_cumul_activite`, `p_est_salarie_etablissement` (règle L1222-5 exposée → HARD STOP n°4, correction 8),
  `p_consentement_gps` (lot 2), `p_disponible_urgence`, `p_urgence_rayon_km`, `p_ville_urgence` (lot 4),
  `p_specialites`, `p_profession`, `p_numero_adeli`.
- **Signature SQL** (`supabase/schema/public.sql` l.43891) :

```sql
CREATE OR REPLACE FUNCTION "public"."fn_modifier_mon_profil"("p_prenom" "text" DEFAULT NULL::"text", "p_nom" "text" DEFAULT NULL::"text", "p_telephone" "text" DEFAULT NULL::"text", "p_date_naissance" "date" DEFAULT NULL::"date", "p_adresse_rue" "text" DEFAULT NULL::"text", "p_adresse_ville" "text" DEFAULT NULL::"text", "p_adresse_code_postal" "text" DEFAULT NULL::"text", "p_adresse_lat" numeric DEFAULT NULL::numeric, "p_adresse_lng" numeric DEFAULT NULL::numeric, "p_rayon_deplacement_km" integer DEFAULT NULL::integer, "p_numero_rpps" "text" DEFAULT NULL::"text", "p_numero_adeli" "text" DEFAULT NULL::"text", "p_avatar_url" "text" DEFAULT NULL::"text", "p_types_contrat" "text"[] DEFAULT NULL::"text"[], "p_bio" "text" DEFAULT NULL::"text", "p_annees_experience" integer DEFAULT NULL::integer, "p_specialites" "text"[] DEFAULT NULL::"text"[], "p_taux_horaire_minimum" numeric DEFAULT NULL::numeric, "p_type_exercice" "text" DEFAULT NULL::"text", "p_ville_recherche" "text" DEFAULT NULL::"text", "p_ville_urgence" "text" DEFAULT NULL::"text", "p_disponible_urgence" boolean DEFAULT NULL::boolean, "p_urgence_rayon_km" integer DEFAULT NULL::integer, "p_attestation_cumul_activite" boolean DEFAULT NULL::boolean, "p_est_cumul_activite" boolean DEFAULT NULL::boolean, "p_est_salarie_etablissement" boolean DEFAULT NULL::boolean, "p_consentement_gps" boolean DEFAULT NULL::boolean, "p_types_contrat_acceptes" "text" DEFAULT NULL::"text", "p_profession" "text" DEFAULT NULL::"text") RETURNS "jsonb"
    LANGUAGE "plpgsql" SECURITY DEFINER
    SET "search_path" TO 'pg_catalog', 'public'
```

- **Classe d'authentification (manifeste)** : `RPC_UTILISATEUR_AUTH_INTERNE` pour `fn_modifier_mon_profil(text,text,text,date,text,text,text,numeric,numeric,integer,text,text,text,text[],text,integer,text[],numeric,text,text,text,boolean,integer,boolean,boolean,boolean,boolean,text,text)`.
- **GRANT connu** : `REVOKE ALL … FROM PUBLIC` puis `GRANT ALL … TO "authenticated", "service_role"`.
- **Signature TypeScript** : vingt-neuf paramètres optionnels (`types.ts`, section `Functions`, mêmes noms que la signature SQL) ; `Returns: Json`.
- **Contrat de réponse (HTTP 200)** : `{error:'Non authentifié'}` (l.43904) ; `{error:'Le prénom ne peut pas être vide'}`
  (l.43906) ; `{error:'Le nom ne peut pas être vide'}` (l.43909) ; `{success:true}` (l.44015). **`COALESCE` partout**
  (l.43933-43985) : un paramètre `NULL` ne change rien. (Précision T9, mineur 4 de la revue B8 de T0 : une chaîne
  `''` **écrase** un champ texte — `COALESCE('', x) = ''` ; seuls prénom et nom sont protégés, par le refus
  l.43906-43909 et `NULLIF(btrim(…), '')`.) Le web envoie `champ || null` ; le natif (T9) n'envoie que les champs
  modifiés (`ModificationProfil.depuis`) et jamais une chaîne vide pour un champ texte vidé (téléphone, ville, bio,
  RPPS : paramètre omis, valeur serveur relue) — l'app n'offre pas « effacer ». Écart assumé : un prénom ou un nom
  vidé est **envoyé** vide pour que le serveur le refuse avec son message (`{error}` verbatim) au lieu du faux
  succès du web (`prenom || null` → inchangé puis « Profil mis à jour avec succès ! »).
  `numero_rpps` n'est modifiable que tant que `rpps_verifie` est faux (l.43949-43952), sans erreur
  sinon : relecture obligatoire. Sans ligne `soignants`, la RPC en **crée** une (l.43917-43930) : chemin jamais
  emprunté par le natif, qui n'ouvre l'écran profil qu'au rôle `SOIGNANT` résolu. Audit `MODIFICATION_PROFIL` écrit
  par la RPC (l.44005-44014).
- **Exceptions PostgREST de l'UPDATE** (revue B8 de T9 ; définitions live relues en lecture seule le 08/11/2026,
  identiques au dump) : 23514 `chk_telephone_format` (l.68090, `^\+?[0-9\s\-\.]{8,20}$`, téléphone en saisie libre)
  ou `chk_rayon_raisonnable` ; 23505 `soignants_numero_rpps_key` (l.73502) ; P0001 « Vous devez avoir au moins 18 ans
  pour vous inscrire. » (`dec_verifier_age_minimum` l.3887-3895, trigger `dec_age_minimum` BEFORE INSERT OR UPDATE).
  Chacune annule l'UPDATE entier (aucun champ enregistré, aucun audit). Le natif les déclare en `exceptionsMetier`
  (lues avant `SupabaseErrorMapping`) et les rend en refus certain sans relecture : 23505 `numero_rpps` → texte web
  `erreurs.ts` l.510 (autre 23505 → l.511), 23514 → l.514, P0001 → message serveur verbatim (le web affiche son
  message générique, écart consigné dans `DECISIONS_LOT3.md`). Toute autre erreur (HTTP 5xx, passerelle, SQLSTATE
  non déclaré) est une issue ambiguë : relecture, jamais de renvoi.
- **Preuve STAGING** : profil modifié puis relu par `fn_mon_profil_soignant_complet` (T16).

## fn_rgpd_exporter_rate_limited

- **Statut natif** : consommée (lot 3, T11) par `JoleneSupabase/Compte/SupabaseExportGateway.swift`, appelée par
  le modèle de la section « Mes données (RGPD) » du hub (`JoleneCore/Compte/ExportRGPDModel.swift`).
- **Usage** : export RGPD (JSON `JSON.stringify(data, null, 2)` et CSV aplati par `flatten`, comme le web, sans
  recalcul) depuis le hub Compte — écart de placement assumé : le web le monte dans l'onglet confidentialité du
  profil (`SectionConfidentialite.tsx` l.30-78, monté par `ProfilSoignant.tsx` l.506) ; fichier temporaire écrit
  avec `NSFileProtectionComplete` dans un dossier propre à l'export, supprimé à la fermeture de la feuille de
  partage (résidus purgés à l'ouverture suivante) ; le contenu n'est jamais affiché ni journalisé par l'app.
- **Signature SQL** (`supabase/schema/public.sql` l.55370) :

```sql
CREATE OR REPLACE FUNCTION "public"."fn_rgpd_exporter_rate_limited"() RETURNS "jsonb"
    LANGUAGE "plpgsql" SECURITY DEFINER
    SET "search_path" TO 'public'
```

- **Classe d'authentification (manifeste)** : `RPC_UTILISATEUR_AUTH_INTERNE` pour `fn_rgpd_exporter_rate_limited()`.
- **GRANT connu** : `REVOKE ALL … FROM PUBLIC` puis `GRANT ALL … TO "authenticated", "service_role"`.
- **Signature TypeScript** : `Args: never` ; `Returns: Json`.
- **Contrat de réponse (HTTP 200)** : `{error:'Non authentifié'}` (l.55379) ;
  `{error:"Trop d'exports en peu de temps. Réessayez dans quelques minutes."}` (l.55385 : 30 exports par heure,
  `fn_verifier_rate_limit(…, 'rgpd_export', 30, 3600)` l.55383 ; valeur JSON réelle, le littéral SQL double
  l'apostrophe) ; sinon le jsonb de `fn_rgpd_exporter_donnees_soignant` (l.55388 ; 32 clés, l.55318-55351), écrit
  tel quel. Un `{error}` « vrai » (test JavaScript du web, l.37) est affiché verbatim et **aucun fichier n'est
  écrit** ; « Non authentifié » → session expirée ; corps non objet → refus de contrat.
- **Lecture native** (T11) : POST sans paramètre, une seule fois ; corps rendu **octet pour octet**
  (`execute()` → `Data`, jamais `AnyJSON` qui passe par un dictionnaire) puis relu dans l'ordre des clés d'un
  objet JavaScript (`JSONOrdonne` : indices de tableau d'abord, puis ordre d'insertion = ordre du jsonb) : le fichier
  natif est celui du web, clé pour clé (`ExportRGPDTests`, attendus produits par le code web lui-même).
- **Audit** : `fn_rgpd_exporter_donnees_soignant` écrit déjà `RGPD_EXPORT_DONNEES` (l.55353-55360) ; le web en ajoute
  un second par `fn_ecrire_audit_safe` (`SectionConfidentialite.tsx` l.42-48). T11 suit le blueprint (audit
  `RGPD_EXPORT_DONNEES` best-effort après l'écriture du fichier, détails `{format}`, parité web) : doublon consigné,
  sans effet utilisateur.
- **Signalement (hors lot 3, non corrigé ici)** : la clé `notations_recues` de l'export (l.55349) lit
  `notations_missions` avec `masque = false` **sans** `publie_le IS NOT NULL` : l'export d'un soignant contient les
  notes reçues **non publiées** (double-aveugle D8), contrairement à la vue canonique `evaluations_publiees`
  (principe « Publication différée » de `CLAUDE.md`). **Écart confirmé sur la définition live** (lecture seule
  `pg_get_functiondef`, 08/11/2026, T11 : corps identique au dump). L'écran natif n'affiche rien du contenu : il
  transmet le fichier du serveur à la feuille de partage, comme le web ; la fuite passe donc par le fichier, sur les
  deux surfaces. PR backend séparée à décider par Gabrielle (droit d'accès RGPD contre double-aveugle), voir
  `DECISIONS_LOT3.md`.
- **Preuve STAGING** : export non vide (T16).

## fn_confirmer_paiement_soignant

- **Statut natif** : à venir (lot 3, T13) — **B9** (paiements, D18).
- **Usage prévu** : « Confirmer la réception » d'un paiement manuel `DECLARE` (web `BandeauPaiementDeclare.tsx`
  l.178-206) ; bouton désactivé pendant l'appel ; état « confirmé » affiché seulement après relecture
  `paiements_soignant` (`statut = 'CONFIRME'`, `confirme_par_soignant = true`), jamais de retrait local d'office.
- **Signature SQL** (`supabase/schema/public.sql` l.24548) :

```sql
CREATE OR REPLACE FUNCTION "public"."fn_confirmer_paiement_soignant"("p_paiement_id" "uuid") RETURNS "jsonb"
    LANGUAGE "plpgsql" SECURITY DEFINER
    SET "search_path" TO 'public', 'pg_temp'
```

- **Classe d'authentification (manifeste)** : `RPC_UTILISATEUR_AUTH_INTERNE` pour `fn_confirmer_paiement_soignant(uuid)`.
- **GRANT connu** : `REVOKE ALL … FROM PUBLIC` puis `GRANT ALL … TO "authenticated", "service_role"`.
- **Signature TypeScript** : `Args: { p_paiement_id: string }` ; `Returns: Json`.
- **Contrat de réponse (HTTP 200)** : `{error:'Non authentifié'}` (l.24557) ; `{error:'Paiement introuvable'}`
  (l.24565) ; `{error:'Accès refusé'}` (l.24568) ; `{error:'Paiement déjà confirmé'}` (l.24571) ;
  `{error:'Ce paiement ne peut plus être confirmé (statut: <statut>)'}` (l.24574-24577, statut hors `DECLARE`,
  `EN_ATTENTE`) ; `{success:true, confirme_le, facture_honoraires_id}` (l.24596-24600). Verrou `FOR UPDATE`
  (l.24563) et refus « déjà confirmé » : un second appel ne double rien. Effet serveur : la facture d'honoraires liée
  passe `PAYEE` si elle était `EMISE` ou `EN_RETARD` (l.24587-24594). Refus affichés verbatim ; un délai dépassé
  impose une relecture, jamais un renvoi.
- **Preuve STAGING** : paiement `DECLARE` de la fixture D5 confirmé puis `CONFIRME` relu (T16).

## fn_contester_paiement_soignant

- **Statut natif** : à venir (lot 3, T13) — **B9**. La PR backend **B3** est sur `main` (#1118, migration
  `20261102205808_contestation_paiement_soignant.sql`, D19, correction 3) : le verrou côté app de T13 peut être levé
  dans la PR de T13, qui consomme le contrat ci-dessous.
- **Usage prévu** : « Contester » avec un motif non vide de 500 caractères au plus ; relecture
  `paiements_soignant.statut = 'CONTESTE'` et de la ligne `litiges` ; bouton désactivé pendant l'appel.
- **Signature SQL** (`supabase/schema/public.sql` l.25741) :

```sql
CREATE OR REPLACE FUNCTION "public"."fn_contester_paiement_soignant"("p_paiement_id" "uuid", "p_motif" "text") RETURNS "jsonb"
    LANGUAGE "plpgsql" SECURITY DEFINER
    SET "search_path" TO 'public'
```

- **Classe d'authentification (manifeste)** : `MIXTE_TENANT_ADMIN` pour `fn_contester_paiement_soignant(uuid,text)` ;
  depuis B3, garde `v_uid IS NULL OR NOT public.fn_compte_auth_actif()` en tête du corps (l.25753).
- **GRANT connu** : `REVOKE ALL … FROM PUBLIC` puis `GRANT ALL … TO "authenticated", "service_role"` (l.82215-82217).
- **Signature TypeScript** : `Args: { p_motif: string; p_paiement_id: string }` ; `Returns: Json`.
- **Contrat de réponse** (dump de `main` après B3, l.25741-25839 ; relu à l'intégration du lot 3 le 08/11/2026) :
  toujours HTTP 200, refus `{error, error_code}` :
  - `NON_AUTHENTIFIE` : « Non authentifié ou compte inactif » (l.25754) ;
  - `MOTIF_INVALIDE` : « Motif requis » (motif vide après `btrim`, l.25758) ou
    « Motif trop long (500 caractères maximum) » (l.25761) ;
  - `PAIEMENT_INTROUVABLE` : « Paiement introuvable » (l.25771) ; `ACCES_REFUSE` : « Accès refusé » (l.25774) ;
  - `DEJA_CONTESTE` : « Paiement déjà contesté » (l.25778, idempotence : jamais un second litige) ;
    `DEJA_CONFIRME` : « Paiement déjà confirmé » (l.25781) ;
  - `STATUT_INVALIDE` : « Ce paiement ne peut plus être contesté (statut: <statut>) » hors `DECLARE`/`EN_ATTENTE`
    (l.25783-25787) ;
  - `LITIGE_DEJA_OUVERT` : « Un litige de ce type est déjà ouvert pour cette mission. » (l.25820-25823) — la
    **23505** sur `uq_litige_mission_type_ouvert_legacy` (l.75327) est interceptée dans un sous-bloc : paiement et
    litige sont annulés ensemble ; toute autre violation d'unicité remonte telle quelle (`RAISE`, l.25818).
  Le paiement est lu `FOR UPDATE` (l.25766-25769, verrou de ligne : deux contestations simultanées sont
  sérialisées). Succès `{success:true, litige_id}` (l.25837) après l'UPDATE `CONTESTE`, l'INSERT `litiges` et une
  notification `SYSTEM` à un administrateur (l.25830-25835).
- **Correction 3 levée par B3** : l'INSERT `notifications` de type `'CONTESTATION_PAIEMENT'`, absent de
  `notifications_type_check` (l.70862), qui faisait échouer toute contestation en **23514**, est retiré ;
  l'établissement reste notifié en `LITIGE_OUVERT` par `trg_notifier_creation_litige` (l.76127).
- **Verrou côté app** (T13, « un gap connu reste verrouillé ») : il couvrait l'état d'avant B3 (aucun appel,
  message explicite). B3 étant mergée, T13 ouvre « Contester » dans sa propre PR (B9) avec ces refus restitués et
  une relecture après toute issue ambiguë.
- **Preuve STAGING** : `CONTESTE` + une ligne `litiges` + notification établissement `LITIGE_OUVERT` relues (T16) ;
  second appel → `{error:'Paiement déjà contesté', error_code:'DEJA_CONTESTE'}` sans second litige.

## fn_consulter_mon_iban

- **Statut natif** : à venir (lot 3, T14b) — **B9** (données bancaires, D18).
- **Usage prévu** : Affichage `•••• {iban_last4}`, titulaire et état de vérification ; relue après
  `fn_enregistrer_mon_iban`.
- **Signature SQL** (`supabase/schema/public.sql` l.25539) :

```sql
CREATE OR REPLACE FUNCTION "public"."fn_consulter_mon_iban"() RETURNS "jsonb"
    LANGUAGE "plpgsql" STABLE SECURITY DEFINER
    SET "search_path" TO 'pg_catalog', 'public'
```

- **Classe d'authentification (manifeste)** : `RPC_UTILISATEUR_AUTH_INTERNE` pour `fn_consulter_mon_iban()`.
- **GRANT connu** : `REVOKE ALL … FROM PUBLIC` puis `GRANT ALL … TO "authenticated", "service_role"`.
- **Signature TypeScript** : `Args: never` ; `Returns: Json`.
- **Contrat de réponse (HTTP 200)** : `{error:'Non authentifié'}` (l.25549) ; profil absent ou supprimé →
  `{iban_renseigne:false, iban_verifie:false}` sans autre clé (l.25554) ; sinon
  `{iban_renseigne, iban_verifie, verification_requise, iban_last4, iban_titulaire}` (l.25576-25582).
  `iban_verifie` exige l'empreinte, le RIB et la pièce d'identité `VERIFIE` encore valides (l.25556-25575). L'IBAN
  complet n'est jamais renvoyé.

## fn_enregistrer_mon_iban

- **Statut natif** : à venir (lot 3, T14b) — **B9** (données bancaires, D18).
- **Usage prévu** : Confirmation de l'IBAN **du RIB vérifié** (règle serveur, correction 4) : contrôle mod 97 local
  avant envoi (`IbanRules`, port de `SectionPaiements.tsx` l.212-225) ; titulaire = « prénom nom » ou « nom prénom »
  normalisés (l.32273-32289) ; succès admis seulement sur `success == true` **puis** relecture `fn_consulter_mon_iban`
  (`iban_verifie == true`). Le web affiche un faux succès quand le refus ne porte que `error_code`
  (`SectionPaiements.tsx` l.259-262 ne teste que `result?.error`) : écart non reproduit, PR web séparée (D20, B9).
- **Signature SQL** (`supabase/schema/public.sql` l.32251) :

```sql
CREATE OR REPLACE FUNCTION "public"."fn_enregistrer_mon_iban"("p_iban" "text", "p_titulaire" "text") RETURNS "jsonb"
    LANGUAGE "plpgsql" SECURITY DEFINER
    SET "search_path" TO 'pg_catalog', 'public'
```

- **Classe d'authentification (manifeste)** : `RPC_UTILISATEUR_AUTH_INTERNE` pour `fn_enregistrer_mon_iban(text,text)` ; délègue la liaison à `fn_lier_iban_verifie_document` (l.32305), interdite côté natif (fiche en fin de document).
- **GRANT connu** : `REVOKE ALL … FROM PUBLIC` puis `GRANT ALL … TO "authenticated", "service_role"`.
- **Signature TypeScript** : `Args: { p_iban: string; p_titulaire: string }` ; `Returns: Json`.
- **Contrat de réponse (HTTP 200)** : refus `{success:false, error_code, error?}`, neuf codes :
  `NON_AUTHENTIFIE` (l.32264) ; `PROFIL_INTROUVABLE` (l.32270) ; `TITULAIRE_NON_CONCORDANT` avec
  `error:'Le titulaire doit correspondre exactement à votre identité vérifiée.'` (l.32283-32287) ;
  `RIB_VERIFIE_REQUIS` avec `error:'Téléversez puis faites vérifier le RIB correspondant.'` (l.32299-32303) ;
  puis, dans `fn_lier_iban_verifie_document` : `IBAN_INVALIDE` (l.39421), `RIB_COURANT_REQUIS` (l.39433),
  `IDENTITE_VERIFIEE_REQUISE` (l.39443 : identité non vérifiée ou `coherence_identite` ≠ `COHERENT`),
  `IDENTITE_COURANTE_REQUISE` (l.39461 : pièce d'identité `VERIFIE` sans `coherence_nom` ou noms discordants),
  `RIB_NON_CONCORDANT` (l.39477 : `resultat_ia.verdict_serveur`, `iban_valide`, `iban_last4`,
  `iban_preuve_hash_v1 = sha256(iban || ':' || doc_id)`, `coherence_nom`, noms extraits). Sept codes sur neuf
  arrivent **sans** `error` : messages natifs nouveaux (non juridiques, à relire, §6.7 du blueprint), jamais
  « IBAN enregistré ». Succès `{success:true, iban_last4, titulaire, source_document_id}` (l.39511-39516) ; audit
  `IBAN_RENSEIGNE` / `IBAN_MODIFIE` écrit par le serveur. L'IBAN n'est ni journalisé ni persisté côté app.
- **Preuve STAGING** : `iban_last4` relu sur la fixture D5 (RIB et pièce d'identité `VERIFIE` seedés avec toutes les
  conditions ci-dessus) (T16).

## fn_mes_revenus_connect

- **Statut natif** : à venir (lot 3, T12 ; T14a pour l'écran Stripe Connect) — **B9** (paiements, D18).
- **Usage prévu** : Totaux serveur de l'onglet Revenus et de l'écran Stripe Connect (web `PageStripeConnect.tsx`
  l.70-82), affichés tels quels, jamais recalculés (D4) ; aucun KPI calculé côté client.
- **Signature SQL** (`supabase/schema/public.sql` l.42347) :

```sql
CREATE OR REPLACE FUNCTION "public"."fn_mes_revenus_connect"("p_mois_debut" "date" DEFAULT NULL::"date") RETURNS "jsonb"
    LANGUAGE "plpgsql" STABLE SECURITY DEFINER
    SET "search_path" TO ''
```

- **Classe d'authentification (manifeste)** : `RPC_UTILISATEUR_AUTH_INTERNE` pour `fn_mes_revenus_connect(date)`.
- **GRANT connu** : `REVOKE ALL … FROM PUBLIC` puis `GRANT ALL … TO "authenticated", "service_role"`.
- **Signature TypeScript** : `Args: { p_mois_debut?: string }` ; `Returns: Json`.
- **Contrat de réponse (HTTP 200)** : `{mois_en_cours, total, en_attente, stripe_connect_actif}` (l.42411-42416) :
  `mois_en_cours`, `total` et `en_attente` en euros (transferts Connect, paiements manuels `CONFIRME` hors Connect,
  escrow `PAYE` ; l'attente additionne Connect `EN_ATTENTE` et l'escrow en cours) ; `stripe_connect_actif` booléen.
  Ni garde `auth.uid()` ni `{error}` : sans identité les sommes valent 0 (inatteignable avec le seul GRANT
  `authenticated`). Les trois nombres doivent être finis (web l.73-76), sinon section en erreur. `p_mois_debut`
  omis = mois courant.

## fn_mes_paiements_escrow

- **Statut natif** : à venir (lot 3, T12) — **B9** (paiements/escrow, D18).
- **Usage prévu** : « Paiements rapides » de l'onglet Revenus, libellés verbatim web (`PaiementsEscrowAVenir.tsx`
  l.44-80, invariant « jamais garanti ») ; `etablissement_nom` est fourni par la RPC pour les missions du soignant
  (JOIN sans filtre de cohorte, l.42205), sans passer par `fn_etablissements_safe`.
- **Signature SQL** (`supabase/schema/public.sql` l.42184) :

```sql
CREATE OR REPLACE FUNCTION "public"."fn_mes_paiements_escrow"() RETURNS "jsonb"
    LANGUAGE "sql" STABLE SECURITY DEFINER
    SET "search_path" TO 'public'
```

- **Classe d'authentification (manifeste)** : `RPC_UTILISATEUR_AUTH_INTERNE` pour `fn_mes_paiements_escrow()` ; filtre `pe.soignant_id = auth.uid()`.
- **GRANT connu** : `REVOKE ALL … FROM PUBLIC` puis `GRANT ALL … TO "authenticated", "service_role"`.
- **Signature TypeScript** : absente de `types.ts` (correction 13).
- **Contrat de réponse (HTTP 200)** : un tableau jsonb, jamais `{error}` (`[]` sans ligne). Chaque élément :
  `mission_id`, `mission_intitule`, `etablissement_nom`, `honoraires_cents`, `etat`, `date_affichee`,
  `mission_date`, `a_litige` (l.42234-42248). `etat` ∈ `VERSE`, `ANNULE`, `RETARDE`, `LITIGE`,
  `VERSEMENT_EN_COURS`, `ATTENTE_VALIDATION`, `RESERVE` (l.42220-42230, dérivé de `paiements_escrow.statut` et des
  présences) ; `date_affichee` nulle hors `VERSE`, `VERSEMENT_EN_COURS` et `RETARDE`. Ordre serveur conservé.
  `honoraires_cents` est figé à la confirmation (règle #11 de `CLAUDE.md`) : affiché sans recalcul.

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

## Edge `register-soignant` (finalisation de l'inscription, lot 3)

- **Statut natif** : consommée (lot 3, T8) par `JoleneSupabase/Inscription/SupabaseInscriptionGateway.swift`
  (`finaliser` : brouillon, puis l'edge, puis `refreshSession()`) — **B9** (inscription, consentement relayé, D18).
  Version déployée relue en lecture seule le 09/11/2026 (`get_edge_function`, version 876, `verify_jwt = false`) :
  `index.ts`, `_shared/errors.ts` et `_shared/attribution.ts` identiques au dépôt. Corps envoyé : `CompletionRules.corpsFinalisation`
  (ni `lat`/`lng`, ni `est_etudiant`/`etudiant_details`, ni `navigateur`, ni `attribution`) ; 200 exige `success` ou `ok`
  vrai et un `soignant_id` (sinon erreur de contrat, jamais un succès) ; 503 `ACCOUNT_FINALIZATION_PENDING` et échec du
  `refreshSession()` → déconnexion locale et message ; 401 → session expirée ; (revue B8 de T8) brouillon relu déclaré
  étudiant → aucun appel de l'edge (D11, verrou, B1) ; issue inconnue — tout statut ≥ 500, 2xx illisible, 409
  `ACCOUNT_ALREADY_REGISTERED` / `ACCOUNT_REGISTRATION_IN_PROGRESS` / `USER_ALREADY_REGISTERED`
  (`CompletionRules.issueIndeterminee`) → rôle relu, `message` verbatim en repli (M1) ; Bearer d'une session valide
  (`auth.session`, m1) ; autres refus → `message` verbatim. Pas une RPC :
  `supabase/functions/register-soignant/index.ts`, appelée par `client.functions.invoke("register-soignant")`
  comme le web (`src/lib/inscriptionProgressive.ts` l.169-238).
- **Transport** : `POST`, corps JSON `{prenom, nom, telephone, dateNaissance, profession, typesContrat, rpps, rayon,
  lat?, lng?, navigateur?, attribution?}` (champs lus l.230), en-tête `Authorization: Bearer <access_token>` de la
  session ouverte par `signUp` ou par la confirmation ; `supabase/config.toml` l.48-49 : `verify_jwt = false` (JWT
  vérifié dans la fonction, l.149-158). Limite **5 appels / 10 min** par IP (`x-forwarded-for`, compteur en mémoire
  de l'instance, l.29-44) : une seule inscription par run STAGING. Le natif n'envoie ni `est_etudiant` ni
  `etudiant_details` (parcours étudiant en renvoi web, D11) ; rayon 30 km par défaut comme le web (l.295,
  correction 21).
- **Décodage** : supabase-swift lève `FunctionsError.httpError` (code HTTP et corps) sur tout statut non 2xx ;
  `EdgeResponse` (T1) lit ce corps avant tout mapping : `{ok:false, code, message, error, details?}`
  (`supabase/functions/_shared/errors.ts` l.34-46, `error` = miroir de `message`). `message` affiché verbatim ;
  aucune nouvelle tentative automatique.
- **Réponses** — liste exhaustive de `index.ts`, confrontée au source par `tests/node/check-rpc-contracts-lot3.node.mjs` :
  - **200** `{ok:true, success:true, soignant_id}` (l.401-403) → `refreshSession()` puis `SessionStore.start()` : seul
    `.ready` relu prouve le succès.
  - **429** `'RATE_LIMITED'` « Trop de tentatives. Réessayez dans quelques minutes. » (l.144).
  - **401** `'UNAUTHORIZED'` « Non authentifié. » (l.151, en-tête absent) ; `'INVALID_TOKEN'` « Session invalide. Reconnectez-vous et réessayez. »
    (l.157) ; `ACCOUNT_AUTH_INACTIVE` (réservation refusée, l.206).
  - **409** réservation refusée (l.204-212), code = celui de `fn_reserver_type_compte` : `ACCOUNT_ALREADY_REGISTERED`
    « Ce compte soignant existe déjà. Connectez-vous pour continuer. » ; `ACCOUNT_REGISTRATION_IN_PROGRESS`
    « Une inscription est déjà en cours pour ce compte. Patientez quelques instants puis réessayez. » ; tout autre
    code (`ACCOUNT_TYPE_MISMATCH`, `ACCOUNT_PROFILE_CONFLICT`, `ACCOUNT_REGISTRATION_INCOMPLETE`,
    `ACCOUNT_TYPE_INVALID`) « Ce compte est déjà associé à un autre espace Jolene. Utilisez une autre adresse ou contactez le support. » ;
    `'RPPS_ALREADY_REGISTERED'` « Ce numéro RPPS est déjà associé à un compte Jolene. Connectez-vous à ce compte, ou contactez le support si ce n'est pas vous. »
    (l.328) ; `'USER_ALREADY_REGISTERED'` « Un compte existe déjà avec cet email. Connectez-vous ou utilisez une autre adresse. »
    (l.332).
  - **400** `'MISSING_REQUIRED_FIELDS'` « Champs obligatoires manquants (prénom, nom, profession). » avec
    `details.champs_manquants` (l.237) ou « Date de naissance requise. » (l.241) ; `'UNDERAGE'` « Vous devez avoir au moins 18 ans pour vous inscrire. »
    (l.252) ; `'RPPS_FORMAT_INVALID'` « Numéro RPPS invalide (11 chiffres attendus). » (l.266) ou « Le numéro RPPS est obligatoire pour votre profession (11 chiffres). »
    (l.270 : professions de `PROFESSIONS_RPPS_REQUIS` = `['MEDECIN', 'DENTISTE', 'SAGE_FEMME', 'PHARMACIEN']`,
    l.260, correction 20) ; `'RPPS_TRAITS_MISMATCH'` avec le message de l'annuaire « Les informations saisies (nom, prénom) ne correspondent pas au numéro RPPS. »
    (l.127, `RPPS_TRAITS_MISMATCH`), repli « Ce numéro RPPS ne correspond pas à votre identité. » (l.287) ;
    `'RPPS_PROFESSION_MISMATCH'` avec « Ce numéro RPPS correspond à la profession « <profession de l'annuaire> », différente de celle que vous avez déclarée. »
    (l.129, gabarit), repli « Ce numéro RPPS correspond à une autre profession que celle déclarée. » (l.291).
    `RPPS_NOT_FOUND` (« Aucun professionnel trouvé avec ce numéro RPPS dans l'Annuaire Santé. », l.124) et
    `RPPS_API_UNAVAILABLE` (« Impossible de vérifier le numéro RPPS pour le moment. Réessayez dans quelques minutes. »,
    l.121, l.135) ne bloquent pas : inscription acceptée avec `rpps_verifie = false`.
  - **500** `'INTERNAL_ERROR'` « Erreur lors de la création du profil soignant. Notre équipe a été notifiée. Réessayez dans quelques minutes. »
    (l.338) ; « Erreur lors de la configuration du compte. Réessayez dans quelques minutes. » (l.348) ;
    « Erreur serveur. Notre équipe a été notifiée. Réessayez dans quelques minutes. » (l.407).
  - **503** `'ACCOUNT_RESERVATION_UNAVAILABLE'` « Inscription momentanément indisponible. Réessayez dans quelques minutes. »
    (l.201) ou « Votre inscription est conservée. Réessayez dans quelques instants. » (l.221) ;
    `'ACCOUNT_FINALIZATION_PENDING'` « Votre profil est enregistré. Reconnectez-vous pour reprendre votre espace. »
    (l.366-367) → déconnexion locale puis message serveur.
- **Effets serveur** (aucun côté app) : ligne `soignants`, `app_metadata.role = 'SOIGNANT'`, audits `INSCRIPTION` et,
  si `parcours_inscription.consentement_cgu_le` existe, `RGPD_CONSENTEMENT_DONNE` (l.370-387), e-mail de bienvenue et
  série d'onboarding (best-effort).
- **Preuve STAGING** : ligne `soignants` relue après la complétion (T16), compte jetable
  `native-insc-<uuid>@example.invalid` nettoyé (B9 données, go au dispatch).

## Edge `stripe-connect-status` (lot 3)

- **Statut natif** : à venir (lot 3, T14a) — **B9** (Stripe, D18).
- **Transport** : `POST` seulement (l.30 : toute autre méthode → **405**), corps vide, Bearer utilisateur
  (`verifyUserOrServiceRole`, service_role refusé) ; `verify_jwt = false` (`supabase/config.toml` l.102-103). Cache
  serveur de **5 min** (`CACHE_TTL_MS`, l.13, l.78-110) contourné par `?force=true` (l.80) :
  `FunctionInvokeOptions(query: [URLQueryItem(name: "force", value: "true")])` au retour de Stripe et sur
  « Actualiser », comme le web (`PageStripeConnect.tsx` l.48-51, l.158 ; correction 17). Sans `force`, l'app peut
  relire `EN_COURS` jusqu'à 5 min après un onboarding terminé.
- **Réponses** (décodées par `EdgeResponse`) :
  - **200** `{statut, onboarding_complete, charges_enabled, payouts_enabled, iban_last4, requirements, disabled_reason, cached, cache_age_seconds?, message?}`.
    `statut` ∈ les six valeurs de `stripe_connect_onboarding_statut_check` (`public.sql` l.72036) : `NON_DEMANDE`,
    `EN_COURS`, `COMPLET`, `SUSPENDU`, `REJETE`, `SUPPRIME`. `NON_DEMANDE` sans appel Stripe si aucune ligne
    d'onboarding (l.56-60) ; `SUPPRIME` avec `disabled_reason:'account_deleted'` et le message « Votre compte Stripe Connect a été supprimé. Contactez le support ou recommencez l'onboarding. »
    (l.64-76, l.168-177). Règle app (web l.53-54) : `COMPLET` accepté seulement si `onboarding_complete`,
    `charges_enabled` et `payouts_enabled` valent `true`, sinon statut indisponible ; tout statut hors des six
    valeurs → erreur d'écran.
  - **401** `{error:'Authorization Bearer manquant'}` (`_shared/admin-auth.ts` l.111) ; `{error:'Token invalide ou expiré'}` (l.145).
  - **403** `{error:'Consultation utilisateur uniquement'}` (`index.ts` l.36 : service_role ou JWT sans utilisateur) ;
    `{error:'Compte desactive'}` (`admin-auth.ts` l.150, l.155).
  - **405** `{error:'Methode non autorisee'}` (l.30).
  - **500** `{error:'Configuration serveur incomplète (SUPABASE_URL/ANON_KEY)'}` (`admin-auth.ts` l.139).
  - **503** `{error:'Configuration serveur incomplete'}` (l.42) ; `{error:'STRIPE_STATUS_UNAVAILABLE', message:'Statut de paiement temporairement indisponible.'}`
    (l.53, l.148, l.224) ; `{error:'STRIPE_NOT_CONFIGURED', message:'Service Stripe temporairement indisponible.'}` (l.115).
  - Erreur Stripe : `{error:<code>, message:<message utilisateur>}` au statut de `mapStripeError`
    (`_shared/stripe-errors.ts`, l.237-244) → message verbatim.
- **Preuve STAGING** : compte test de la fixture D5 → `NON_DEMANDE` relu ; cohorte non-test D5-R → statut relu après
  l'onboarding (T16, T17).

## Edge `stripe-connect-onboard` (lot 3)

- **Statut natif** : à venir (lot 3, T14a) — **B9** (Stripe, D18).
- **Transport** : `POST` (la fonction ne contrôle pas la méthode ; l'app n'envoie que `POST`), Bearer utilisateur,
  **en-tête `Origin: https://jolene.app` obligatoire** (correction 1, D6) : `getTrustedStripeReturnOrigin`
  (l.21-32) rend `null` si `Origin` est absente — un client URLSession n'en envoie pas — ou non reconnue par
  `_shared/cors.ts` (l.19-42) → **403** `ORIGINE_NON_AUTORISEE`. Avec cet en-tête, `return_url` =
  `https://jolene.app/soignant/stripe-connect?success=true` et `refresh_url` =
  `https://jolene.app/soignant/stripe-connect?refresh=true` (l.200-205) : retour par Universal Link
  (`ASWebAuthenticationSession` à rappel `.https` dès iOS 17.4, `SFSafariViewController` en dessous, D7,
  correction 6). `verify_jwt = false` (`supabase/config.toml` l.99-100). Avant tout appel, l'app lit
  `soignants.est_compte_test, type_exercice, statut_liberal` comme le web (`PageStripeConnect.tsx` l.94-111) :
  compte test → écran « Stripe désactivé sur ce compte de test » (texte web l.307) **sans** appel d'edge ; non
  éligible → message web, sans appel.
- **Réponses** (décodées par `EdgeResponse`) :
  - **200** `{success:true, url, account_id}` (l.207-212) → `ExternalFlowPort.ouvrir(url)` ; l'issue du flux n'est
    jamais un succès : relecture `stripe-connect-status?force=true`.
  - **401** `{error:"Non autorisé"}` (l.49-52 en-tête absent ; l.63-67 jeton refusé).
  - **403** `{error:"ORIGINE_NON_AUTORISEE"}` (l.71-75) → erreur de contrat (bug de l'app, jamais affiché tel quel) ;
    `{error:"TEST_ACCOUNT_PAYMENT_DISABLED"}` (l.106-113, cohorte test, correction 2) → écran compte test ;
    `{error:"Stripe Connect est réservé aux soignants en exercice libéral ou mixte"}` (l.120-131 : ni `LIBERAL`, ni
    `MIXTE`, ni `statut_liberal = 'ACTIF'`).
  - **404** `{error:"Soignant introuvable"}` (l.87-92).
  - **503** `{error:"TEST_ACCOUNT_CLASSIFICATION_UNAVAILABLE"}` (l.98-105).
  - Erreur Stripe : `{error:<code>, message:<message utilisateur>}` au statut de `mapStripeError` (l.218-231).
- **Preuve STAGING** : compte test → 403 `TEST_ACCOUNT_PAYMENT_DISABLED` (résultat attendu, niveau 3) ; cohorte
  non-test D5-R → URL d'onboarding obtenue (T16) ; retour par Universal Link sur iPhone en iOS ≥ 17.4 (T17).

## Payload `send-push` (taps de notification)

- **Statut natif** : lecture seule (lot 3, T5) ; l'app n'appelle jamais `send-push` (service_role, admin ou
  établissement autorisé uniquement).
- **Payload APNs** (`supabase/functions/_shared/apns-client.ts` l.103-109) :
  `{aps:{alert:{title, body}, sound:'default'}, …données}` — **aucun badge** (le serveur n'en envoie pas,
  `LOT3_PLAN.md` §1.2), pas de `mutable-content`. Les données sont des clés **racine** à côté de `aps`
  (`userInfo` en `[String: String]`) : `type_evenement` (toujours présent, chaîne vide possible ; motif
  `^[A-Z0-9_:-]{1,100}$` exigé à l'émission, l.326-327), `lien` (seulement s'il est fourni : chemin relatif ou URL
  `https://jolene.app` / `www.jolene.app` normalisée par `safeNotificationLink`, l.55-73 ; tout autre lien est
  refusé à l'émission, 400 « Lien de notification interdit », l.323-325), et les seules clés de `ALLOWED_DATA_KEYS`
  (`supabase/functions/send-push/index.ts` l.75-79) : `mission_id`, `contrat_id`, `candidature_id`, `facture_id`,
  `litige_id`, `presence_id`, `conversation_id`, `etablissement_id`, `soignant_id`, `notification_id`, `action`,
  `statut`, `tab`, `source` — scalaires convertis en chaîne, 500 caractères, 30 clés et 2 500 octets au plus
  (`safeScalarData`, l.93-110).
- **Routage natif** : `PushRouting.path(data:role:)` porte `navigationPathForEvent` (`src/lib/pushNative.ts`
  l.251-315) : lien explicite d'abord, puis table par `type_evenement`, rôle lu dans le snapshot ; vecteurs golden
  tirés de `src/lib/pushNative.test.ts` (T2). Correction 15 : `PAIEMENT_RECU` ouvre la section « Paiements à
  confirmer » de Revenus (le web vise `?tab=paiements`, onglet inexistant).
- **Émission (rappel pour la recette)** : `send-push` saute tout destinataire de la cohorte test
  (`reason: 'test_account'`, l.416) et toute source test (`reason: 'test_source'`, l.446) — correction 2 ; un token
  `IOS` qui reçoit `BadDeviceToken`, `Unregistered` ou 410 passe `tokens_push.actif = false` (l.725) ; sans secrets
  APNs (`apnsReady` faux), tout token `IOS` est désactivé (l.717-730). Un seul `APNS_ENVIRONMENT` par projet
  (`apns-client.ts` l.97-99, défaut `production`) : recette avec un build Debug (token sandbox) sur STAGING réglé
  en `sandbox` (correction 5).
- **Preuve** : niveau 5 sur iPhone (T17), push émis par le script service_role de T16 vers la cohorte D5-R.

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

## Interdite côté natif : `fn_lier_iban_verifie_document`

- **Statut natif** : **jamais** (`RPC_JAMAIS_SUIVIES` de `scripts/mobile/check-rpc-contracts.mjs`, lot 3 T0 ;
  `verifierExclusions` fait échouer la CI si elle entre dans `RPC_SUIVIES`).
- **Pourquoi** : GRANT au seul `service_role` (`REVOKE ALL … FROM PUBLIC` puis `GRANT ALL … TO "service_role"`,
  `public.sql` l.83209-83210) et garde interne `RAISE EXCEPTION 'Service role requis' USING ERRCODE = '42501'`
  (l.39417) : un appel avec le JWT soignant est un 42501. Elle lie un IBAN au RIB désigné **sans** contrôler que le
  document appartient à l'appelant ni le titulaire saisi ; elle n'est sûre que derrière `fn_enregistrer_mon_iban`
  (titulaire normalisé, RIB `VERIFIE` du soignant connecté), qui l'appelle elle-même côté serveur (l.32305, fonction
  `SECURITY DEFINER` dont le propriétaire passe la garde). Un appel direct contournerait cette garde.
- **Garde** : `tests/node/check-rpc-contracts.node.mjs` (liste `INTERDITES_NATIF`, littéraux `"fn_…"` du Swift) et
  `tests/node/check-rpc-contracts-lot3.node.mjs` (GRANT et garde relus dans le dump) ; un
  `git grep fn_lier_iban_verifie_document ios-native/` doit rester vide.

## PSC (Pro Santé Connect) : non consommé au lot 3

- **Statut natif** : **non consommé** (décision 8 du lot 3) : ni `psc-authorize`, ni `psc-callback`, ni `psc-logout`,
  ni `psc-test-connexion` (`supabase/functions/psc-*`) ne sont appelés par l'app ; la route `/auth/psc/callback`
  reste `.safari` (`JoleneCore/Links/LinkRouter.swift` l.23), comme `/inscription/soignant/completion`.
- **Pourquoi** : credentials ANS absents (`docs/PSC-BASCULE-PROD.md` l.3, l.29-30), aucun environnement PSC hors
  production (l.4), et le rappel `https` d'`ASWebAuthenticationSession` exige iOS 17.4 alors que la cible est iOS 16
  (correction 6 ; le plan interdit les schemes custom, §4.5).
- **Réouverture** : tranche dédiée le jour où les credentials ANS existent ; les edges et RPC PSC entrent alors dans
  `RPC_SUIVIES` et dans ce document dans la même PR, jamais avant.

## Hors périmètre de ce document

Les RPC publiques consommées par le second client sans persistance (plan §4.1 : cinq RPC `PUBLIC_VOLONTAIRE`)
et les RPC établissement du lot 5 (`fn_traiter_candidature_planning_v1`, `fn_creer_mission_multi_jours_v4`,
`fn_mes_permissions_etab`) seront ajoutées à `RPC_SUIVIES` dans `scripts/mobile/check-rpc-contracts.mjs`
au lot qui les consomme, jamais avant.
