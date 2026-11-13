# Blueprint du lot 3 — app iOS Swift native Jolene (push, inscription, profil et compte, revenus et Connect, Sentry)

> **Copie versionnée** (tranche T0 du lot 3, 2026-11-02) du blueprint préparé en lecture seule. Les décisions du
> §7 sont tranchées dans `docs/mobile-swift/DECISIONS_LOT3.md` (toutes les recommandations fermes adoptées, mandat
> de Gabrielle du 02/11/2026) et le §6 y est repris sous « En attente de Gabrielle ». Le texte ci-dessous n'est pas
> réécrit : les mentions « (scratchpad) » renvoient aux documents versionnés `docs/mobile-swift/LOT1_PLAN.md`
> (décisions du lot 1 à son §7) et `docs/mobile-swift/LOT2_PLAN.md` (versionné par la T0 du lot 2) ; les fiches de
> contrat livrées par T0 sont dans `docs/mobile-swift/CONTRATS_RPC_SOIGNANT.md`, gardées par
> `tests/node/check-rpc-contracts-lot3.node.mjs`.

> Préparé le 2026-11-02 en lecture seule. Base : `main` = `d1b0f39c` (socle lot 0, PR #1106) + branches lot 1 non mergées
> `origin/feat/ios-native-lot1-t1-fondation` (`d246a062`), `origin/feat/ios-native-lot1-t1b-design` (`528c49b1`),
> `origin/feat/ios-native-lot1-t2-golden-planning` (`bda09c20`), lues par `git show` / `git diff origin/main...`.
> Périmètre : `docs/PLAN_APP_NATIVE_SWIFT.md` §5 « Lot 3 » (l.191-200). Règles : `docs/mobile-swift/PRINCIPES.md` (amendé §2/§5
> sur la branche fondation), `docs/mobile-swift/DECISIONS_LOT0.md`, `LOT1_PLAN.md` / `LOT1_DECISIONS.md` (scratchpad), `CLAUDE.md`.
> Lignes SQL = `supabase/schema/public.sql` (dump prod re-baseliné le 01/11/2026) sauf mention. SDK = supabase-swift **2.55.5**
> (checkout `~/Library/Developer/Xcode/DerivedData/Jolene-fictynhifqofdkcrmrmflcvffnqm/SourcePackages/checkouts/supabase-swift`, `v2.55.5`).
> **Contre-relecture v2 (corrigé v2, 2026-11-02)** : sources relues en plus — `origin/feat/ios-lot1-t0-contrats-docs` (contrats lot 1),
> `origin/feat/ios-lot1` (intégration), `origin/lot1/t8` (suppression de compte, hub `ProfileScreen`), `LOT2_PLAN.md` (scratchpad,
> conflits inter-lots). `main` a avancé à `7c6dc86b` (#1107, #1108 : docs/CI hors `ios-native/`, sans effet sur ce plan).

## Objectif

Rendre l'app soignant autonome hors parcours cœur : notifications APNs (enregistrement, routage des taps, préférences,
désactivation au logout), inscription native (signUp PKCE → `fn_demarrer_inscription` → `register-soignant`), profil et compte
(profil, avatar, localisation, mot de passe, thème, export RGPD), revenus en lecture avec confirmation/contestation d'un paiement
déclaré, IBAN, Stripe Connect hosted, Sentry Cocoa, et Universal Links complets côté soignant. Critères de sortie du plan
(l.196-200) : push réel sur iPhone physique (≥ 6 types, table testée sur `src/lib/pushNative.test.ts`), inscription STAGING par
Universal Link, onboarding Connect STAGING avec retour dans l'app, crash Sentry taggé 2.0.0 (25), TestFlight externe.
(corrigé v2) Couverture : push → T2, T4, T5, T16, T17 ; inscription → T7, T8, T16, T17 (« PKCE échangé » à reformuler, §6.4) ;
Connect → T14a, T16, T17 (iOS ≥ 17.4, correction 6) ; Sentry → T15, T17 ; TestFlight externe → §6.10 (hors tranche).
Périmètre « PSC si credentials ANS présents » → §1.2, §7 D8.

## Dépendances au lot 1 (doivent être sur `main` avant la tranche indiquée)

| Livrable lot 1 | Utilisé par | Pourquoi |
|---|---|---|
| T1 fondation : `Gateways` additif (`Ports.swift` l.74-115 de la branche), `UnwiredPort`/`UnwiredPorts.erreur` (`Lot1Ports.swift` l.119-128), `Session/Bounded.swift`, `RPCResponse` (`RPC/RPCResponse.swift`, interception `[CODE DU TRAVAIL]` l.225-235 avant `SupabaseErrorMapping`), `AuditPort`/`AuditAction` (`Lot1Results.swift` l.189-198), `FlagsPort` + `EcranNatif` (5 onglets) | T1 lot 3 et toutes les gateways | même mécanique, étendue de façon additive. (corrigé v2) La surcharge `UnwiredPorts.erreur(port:tranche:lot:)` est **aussi** prévue par L2-T1 (`LOT2_PLAN.md` §2.2) : la première T1 (lot 2 ou lot 3) mergée l'ajoute sous forme générique (`lot: Int` → `docs/mobile-swift/LOT<lot>_PLAN.md`), l'autre la réutilise — deux déclarations identiques ne compilent pas |
| (corrigé v2) T0 contrats (`origin/feat/ios-lot1-t0-contrats-docs`) : `fn_mon_profil_soignant_complet` reclassée `lot: 3` (`RPC_SUIVIES` l.53-80 sur cette branche), `RPC_JAMAIS_SUIVIES`/`RPC_PAS_AVANT_LOT4` + `verifierExclusions` (l.83-111) | T0 lot 3 | les numéros de ligne de `RPC_SUIVIES` cités plus bas (l.42-59) sont ceux de `main` ; après merge de L1-T0 ce sont l.53-80 |
| T1b design (`ConfirmationSheet`, `FilterChip`, `InlineNotice`, `StickyActionBar`, `SkeletonBlock`, `JoleneButton.destructive`, couleurs dynamiques clair/sombre `JoleneColor.swift` l.73-109) | T1b lot 3, tous les écrans, thème | composants et jetons sombres déjà prêts |
| T7 `ReceiptJournal` + `KeychainReceiptStore` (`app.jolene.receipts`) | T10 (avatar) | reçu durable avant tout upload (PRINCIPES §4) |
| T8 compte (suppression, `ProfileScreen` hub, `EdgeResponse` éventuel) | T11, T4 (désinscription locale à la suppression) | le hub Profil existe : c'est `Jolene/Screens/ProfileScreen.swift`, monté par `MainTabView.swift` l.55-60, auquel T8 ajoute `SuppressionCompteSection` et l'identifiant `profile-list` (`origin/lot1/t8`), et L2 `Screens/Profil/EspaceSoignantSection.swift`. (corrigé v2) T8 a bien écrit un décodeur d'edge local (`SupabaseAccountGateway.lire`/`refus`, `FunctionsError.httpError` → `RPCResponse`) : T1 lot 3 le remplace par `EdgeResponse` sans changer son comportement (`CompteSuppressionVerbatimTests` inchangé) ; T8 ajoute aussi `Session/LocalSignOut.swift`, réutilisé par T4 pour la désinscription locale |
| T9 session (audit `connexion/deconnexion` dans `SessionStore`, biométrie, `FeatureFlags`) ; **B0** (5 clés `ios_natif_*_actif`) | T4 (ordre du logout), T11, T12 | `revenus` et `profil` sont déjà pilotés par B0 ; aucun nouveau drapeau au lot 3 |
| T10 liens (`JoleneApp.onOpenURL`/`onContinueUserActivity`, `DeepLinkCoordinator`, `DeepLinkIntent`, intention mémorisée avant `.ready`, argument DEBUG `-JOLENE_OPEN_URL`, option B du reset) | T3, T5, T7, T14a (corrigé v2) | point d'entrée unique des liens et des taps push |
| T11 STAGING (`ios-swift-lot1-staging.yml`, groupe `jolene-supabase-staging-writes`, fixture D3, `createDeletionSafetyGate`-équivalent) | T16 | (corrigé v2) le lot 3 reprend le **modèle** (policy, admission, groupe, garde de suppression) dans un workflow jumeau `ios-swift-lot3-staging.yml`, comme L2 (`ios-swift-lot2-staging.yml`), sans éditer le fichier du lot 1 (§7 D24) |

Dépendance souple au lot 2 : l'IBAN exige un RIB `VERIFIE` (voir correction 4) ; tant que l'écran documents du lot 2 n'est pas
mergé, le CTA « Téléverser mon RIB » est un renvoi web. Le port de localisation ponctuelle est partagé avec le lot 2 (T10).
(corrigé v2) Le lot 2 a déjà figé ce port : `LocationPort` dans `JoleneCore/Ports/AppareilPorts.swift`, porté par `struct Appareil`
injectée par `AppContainer` (`autorisation()`, `demanderAutorisation()`, `positionUnique(delai: 15) async -> ObservationGps`,
`LOT2_PLAN.md` §2.3, livré par L2-T1). Le lot 3 n'en crée **aucune** variante (pas de `positionPonctuelle(precision:)`) : la
localisation du profil attend L2-T1 (T10). Conflits inter-lots à prévoir au rebase (aucun lot n'en est propriétaire unique) :
`Ports/Ports.swift` (bloc lot 2 et bloc lot 3 au même endroit), `Lot1Ports.swift` (surcharge `erreur`), `Lot1Results.swift`
(`AuditAction`), `DemoWorld.swift`, `SupabaseGateways.swift`, `JoleneRoute.swift`/`LinkRouter.swift`/`DeepLinkCoordinator.swift`
(L2-T10), `ProfileScreen.swift`, `AppContainer.swift`, `export-golden-vectors.mjs` + `RulesGoldenTests.swift` (L2-T2),
`check-rpc-contracts.mjs`/`rpc-contracts.json`, `export-demo-fixtures.mjs`, `ios-swift-ci.yml` l.322, `PARITE_SOIGNANT.md`.
Le nom « fixture D4 » est déjà pris par le lot 2 (`staging-lot2-fixture.mjs`) : la fixture du lot 3 s'appelle **D5** (T16).

## Corrections vs plan (faits du dépôt qui contredisent `PLAN_APP_NATIVE_SWIFT.md`)

1. **`stripe-connect-onboard` refuse un client sans en-tête Origin** : `getTrustedStripeReturnOrigin` renvoie `null` si Origin
   absente (`supabase/functions/stripe-connect-onboard/index.ts` l.20-31) → `403 {"error":"ORIGINE_NON_AUTORISEE"}` (l.69-75).
   Le plan §2.3 (« un client URLSession n'envoie pas d'Origin : c'est le comportement voulu ») et §8.2 sont faux pour cette edge.
   Parade sans backend : envoyer `Origin: https://jolene.app` (accepté par `_shared/cors.ts` l.19-42, `return_url` =
   `https://jolene.app/soignant/stripe-connect?success=true`, l.200-204) — §7 D6.
2. **Cohorte TEST et push/Stripe** : tant que `parametres_systeme.inscriptions_publiques_actives = 0`, tout INSERT `soignants` /
   `etablissements` est forcé `est_compte_test = true` (`private.fn_forcer_compte_test_prelaunch`, migration
   `20260925143334` l.43-48). Or `send-push` saute tout destinataire test (`reason: 'test_account'`, `send-push/index.ts`
   l.390-417) et toute source test (`mission_id`, `litige_id`, `etablissement_id`, `soignant_id`, l.418-445 ;
   `_shared/test-account.ts` l.170-215), et `stripe-connect-onboard` répond `403 TEST_ACCOUNT_PAYMENT_DISABLED` (l.94-111).
   Les preuves « push réel » et « onboarding Connect STAGING » sont **impossibles avec la cohorte de recette actuelle** :
   il faut une cohorte non-test sur STAGING (§6.3, §7 D17). (corrigé v2) STAGING vaut aujourd'hui `0` et d'autres recettes en
   dépendent : `scripts/recette-fournisseurs/sql/finance-cohortes-rollback.sql` l.18-20 lève « Etat staging inattendu » si la
   valeur n'est pas 0, et `verify-finance-fixture-isolation.mjs` rend `INITIAL_STATE_INVALID` : passer le paramètre à 1 de façon
   durable casserait ces recettes et reclasserait « réelles » toutes les inscriptions STAGING (e2e compris). Le même script montre
   la voie sûre : bascule à 1 puis retour à 0 **dans une seule transaction backend** (l.33-57), invisible des autres sessions.
3. **Contestation de paiement cassée en base** : `fn_contester_paiement_soignant` (l.25741-25795) insère une notification
   `type = 'CONTESTATION_PAIEMENT'` (l.25779), absente de `notifications_type_check` (l.70815) → violation 23514, transaction
   annulée : la contestation échoue aujourd'hui sur le web comme en natif (même famille que l'incident Lot 13 de `CLAUDE.md`).
   La fonction n'a en outre **aucune garde de statut ni d'idempotence** (UPDATE inconditionnel l.25753-25759). (corrigé v2) Un
   second appel ne crée **pas** un second litige : l'index unique partiel `uq_litige_mission_type_ouvert_legacy` (l.75280,
   `(mission_id, type_litige)` si `facture_id IS NULL` et statut ouvert ; `type_litige` vaut `AUTRE` par défaut) lève 23505 et
   annule tout ; pour la même raison, la **première** contestation échoue aussi (23505) dès qu'un litige `AUTRE` sans facture est
   déjà ouvert sur la mission. Le trigger `trg_notifier_creation_litige` (l.76080, `dec_notifier_creation_litige`) notifie déjà
   l'établissement (`LITIGE_OUVERT`) à toute création de litige `initie_par = 'SOIGNANT'` : la notification explicite est redondante.
   PR backend **B3** (B9, go humain) avant T13 ; à confirmer d'abord sur la définition live (`pg_get_constraintdef`, garde-fou 9.0 n°2).
4. **L'IBAN n'est pas une saisie libre** : `fn_enregistrer_mon_iban` (l.32251-32300) exige un RIB `VERIFIE`
   (`RIB_VERIFIE_REQUIS`), puis `fn_lier_iban_verifie_document` (l.39402-39514, service_role seul l.83209-83210) exige identité
   vérifiée + `coherence_identite = 'COHERENT'`, pièce d'identité `VERIFIE` et `resultat_ia.iban_preuve_hash_v1 =
   sha256(iban || ':' || doc_id)`. Le web affiche un **faux succès** quand le refus ne porte que `error_code`
   (`SectionPaiements.tsx` l.259-262 ne teste que `result?.error`). Natif : succès = `success == true` puis relecture.
   (corrigé v2) La liste complète des conditions de `fn_lier_iban_verifie_document` (l.39464-39477) exige aussi, sur le RIB,
   `resultat_ia.verdict_serveur = 'VERIFIE'`, `resultat_ia.iban_valide = 'true'`, `resultat_ia.iban_last4 = right(iban,4)`,
   `coherence_nom = true` et `nom_extrait_ia`/`prenom_extrait_ia` concordants (`fn_noms_personne_correspondent`), et sur la pièce
   d'identité `coherence_nom = true` + noms extraits concordants (l.39444-39462) ; le titulaire saisi doit égaler « prénom nom »
   ou « nom prénom » normalisés (`fn_enregistrer_mon_iban` l.32273-32289). Sept des neuf `error_code` arrivent **sans** `error`
   (seuls `TITULAIRE_NON_CONCORDANT` et `RIB_VERIFIE_REQUIS` en portent un) : les messages natifs des sept autres sont des
   textes nouveaux (non juridiques) à faire relire, faute de texte web.
5. **Un seul `APNS_ENVIRONMENT` par projet** (`_shared/apns-client.ts` l.97-99) et la configuration Release est
   `Production.xcconfig` (`ios-native/project.yml` l.16-18) : tout build TestFlight parle à la **production** Supabase avec
   `aps-environment = production`. La recette push STAGING se fait donc avec un **build Debug installé par Xcode** (profil de
   développement, token sandbox) et `APNS_ENVIRONMENT = sandbox` sur STAGING. Un token sandbox envoyé à l'hôte production
   reçoit `BadDeviceToken` et est **désactivé** (`apns-client.ts` l.128, `send-push` l.722-727, l.765-770).
   (corrigé v2) Deux faits de plus : (a) la présence des secrets APNs **sur STAGING** n'a jamais été mesurée — `apns-probe.yml`
   ne vise que la production (`SUPABASE_PROJECT_REF: flripxtsyegjshnhzjkz`, l.30) — et sans eux `send-push` **désactive** tout
   token `IOS` d'un destinataire non-test (`apnsReady` faux → `expiredTokenIds`, l.714-730) ; (b) `Staging.xcconfig` ne versionne
   pas la clé publishable (« injectée par la CI », l.2) : un build Debug installé par Xcode sur iPhone exige un xcconfig local non
   versionné (ou `xcodebuild … JOLENE_SUPABASE_PUBLISHABLE_KEY=`), sinon la garde d'environnement bloque l'app.
6. **`ASWebAuthenticationSession` avec rappel https exige iOS 17.4** (`Callback.https(host:path:)`) alors que la cible est
   iOS 16 (`Base.xcconfig` l.6) et que le plan interdit les schemes custom (§4.5). PSC (§4.3 du plan) n'est donc pas faisable
   proprement en iOS 16 ; s'y ajoutent l'absence des credentials ANS (`docs/PSC-BASCULE-PROD.md` l.3, l.29-30) et l'absence de
   PSC hors production (l.4). PSC n'est pas construit au lot 3 (§7 D8). (corrigé v2) Même limite pour Stripe : sous iOS 17.4,
   `SFSafariViewController` charge la `return_url` (redirection serveur de Stripe vers `https://jolene.app/soignant/stripe-connect?success=true`)
   **dans la feuille** ; la remise de cet Universal Link à l'app qui présente la feuille n'est pas garantie. Le critère « retour
   dans l'app par Universal Link » n'est donc prouvable que sur un iPhone en iOS ≥ 17.4 (rappel `.https` associé à
   `webcredentials:jolene.app`, présent dans `Jolene.entitlements` et dans l'AASA pour `GDU5AA28M9.app.jolene`).
7. **`fn_mon_profil_soignant_complet` renvoie des données sensibles** (`numero_secu` l.44668, `siret_liberal`, `code_ape`,
   `numero_tva` l.44672, `stripe_account_id`, `iban_last4` l.44675) et pas les clés `specialite_*` que le web lit : décodage
   en liste blanche stricte + test-garde (T9).
8. **Le profil web enregistre `type_exercice` et `attestation_cumul_activite` en citant l'art. L1222-5**
   (`ProfilSoignant.tsx` l.252-256, l.274-278) : règle juridique exposée → HARD STOP n°4, non portée (renvoi web).
9. **« Supprimer les lues » ne supprime rien** : `pol_notif_delete` réserve DELETE à `est_admin()` (l.79387) ; le web retire
   les lignes localement (`PageNotifications.tsx` l.106-113), elles réapparaissent au rechargement. Non porté.
10. **Confirmation d'inscription par lien** : même défaut que le reset du lot 1 (correction 3) — un modèle `{{ .ConfirmationURL }}`
    passe par `https://<ref>.supabase.co/auth/v1/verify` puis redirige vers jolene.app, donc Safari ; le `?code=` PKCE n'est
    échangeable que là où `signUp` a posé le verifier (slot unique, `AuthClient.swift` l.384). Le compte est néanmoins confirmé
    par `/verify` avant la redirection : la reconnexion par mot de passe reste un repli valable (§7 D10).
11. **Ordre du logout** : `SessionController.signOut` avance l'epoch avant le réseau (branche fondation l.120-134) ; la
    désactivation du token (`fn_desactiver_mon_token_push`, JWT requis) doit donc précéder `controller.signOut()` dans
    `SessionStore.signOut`, bornée à 2,5 s comme le web (`src/lib/pushDeviceToken.ts` l.90-92, l.113) — exception à la décision 14
    du lot 1 (15 s), §7 D3.
12. **Formes d'erreur hétérogènes** : `fn_upsert_token_push` renvoie `void` et lève (42501 « Non authentifie » l.64642, 22023
    l.64645-64674) ; `fn_demarrer_inscription` lève 42501/22023/23505 avec des messages utilisateur (l.30110-30127) ;
    `fn_desactiver_mon_token_push` et la plupart des autres répondent `{error}` / `{success:false}` en HTTP 200. Les exceptions
    métier doivent être lues **avant** `SupabaseErrorMapping` (qui les réduit au message générique, `SupabaseErrorMapping.swift`
    l.49-54), comme `[CODE DU TRAVAIL]` au lot 1.
13. **RPC hors manifeste et hors `types.ts`** : `fn_demarrer_inscription`, `fn_enregistrer_parcours_inscription` (absentes de
    `SECURITY_DEFINER_MANIFEST.json` et de `types.ts`) ; `fn_param_bool` hors `types.ts`. Classement manuel en T0.
    (corrigé v2) `fn_mes_paiements_escrow` est aussi absente de `types.ts` (présente au manifeste). « Classement manuel » = fiche
    `CONTRATS_RPC_SOIGNANT.md` seulement : `buildContracts` accepte `types: null` et `manifeste: null` (l.204-220 de L1-T0), et
    `supabase/SECURITY_DEFINER_MANIFEST.json` est sous `supabase/`, interdit par PRINCIPES §1.
14. **Le critère « inscription STAGING de bout en bout par Universal Link : email reçu » n'est pas exécutable en CI** : simulateur
    non signé (`CODE_SIGNING_ALLOWED[sdk=iphonesimulator*] = NO`, `Base.xcconfig` l.12) donc sans associated domains, et aucune
    boîte mail. Découpage : niveau 3 en CI (lien `token_hash` relu en SQL puis injecté par `-JOLENE_OPEN_URL`), niveau 5 sur
    iPhone avec une adresse de Gabrielle (T17).
15. `navigationPathForEvent` route `PAIEMENT_RECU` vers `/soignant/mes-gains?tab=paiements` (`pushNative.ts` l.294-296), onglet
    qui n'existe pas (`MesGains.tsx` l.899-956 : `apercu`, `factures`, `bulletins`, `avances`) : le natif ouvre la section
    « Paiements à confirmer » de Revenus.
16. (corrigé v2) **`fn_upsert_token_push` renvoie `void`** : PostgREST répond sans corps JSON. `RPCResponse.appeler` (L1-T1
    l.215-223) décode toujours `AnyJSON` (`execute().value`), ce qui **lève une erreur de décodage sur un succès** (supabase-swift
    2.55.5 `PostgrestBuilder.execute<T: Decodable>` l.159-169). La gateway push appelle la surcharge `execute()` → `Void`
    (l.137-141), avec la même interception d'exceptions avant `SupabaseErrorMapping` ; test `StubURLProtocol` : 204 / 200 à corps
    vide = succès.
17. (corrigé v2) **`stripe-connect-status` sert un cache de 5 min** (`CACHE_TTL_MS`, l.8-13, l.78-110) et n'accepte que `POST`
    (l.30, défaut de `FunctionInvokeOptions`). Au retour de Stripe, le web relit avec `?force=true` (`PageStripeConnect.tsx`
    l.48-51, l.109) ; sans ce paramètre, l'app peut relire `EN_COURS` pendant 5 min après un onboarding terminé. Natif :
    `FunctionInvokeOptions(query: [URLQueryItem(name: "force", value: "true")])` au retour et sur « Actualiser ».
18. (corrigé v2) **Hub réellement monté** : l'onglet Profil rend `Jolene/Screens/ProfileScreen.swift` (`MainTabView.swift`
    l.55-60), étendu par L1-T8 et L2. Créer un `MonCompteScreen` parallèle reproduirait l'incident des « deux surfaces empilées »
    (`CLAUDE.md`, règle « livré ≠ mergé ») : le lot 3 étend `ProfileScreen.swift` (T11).
19. (corrigé v2) **`MesGains.tsx` ne lit pas les colonnes du plafond Rist** : son `select` (l.95) omet `rist_plafond_applique`,
    `taux_rist_plafonne`, `soignant_assigne_id` et `profession_requise` ; `corrigerAncienPlafondImpossible`
    (`missionFinanceDisplay.ts` l.41-61) n'y modifie donc jamais le montant. Avec les **mêmes colonnes**, le natif affiche le même
    chiffre que le web sans aucun recalcul effectif (PRINCIPES §3 respecté) ; sélectionner ces colonnes en plus ferait diverger
    les deux surfaces (§7 D5).
20. (corrigé v2) **RPPS à l'inscription** : le web l'exige pour `PROFESSIONS_RPPS_REQUIS` (`MEDECIN, DENTISTE, SAGE_FEMME,
    PHARMACIEN`, `src/lib/constantes.ts` l.61, `InscriptionSoignant.tsx` l.221-225), le rend optionnel pour les autres professions
    à RPPS et pour `AS`, et le masque pour `PROFESSIONS_SANS_RPPS` hors `AS` (l.55, l.201-208) ; `register-soignant` applique la
    même liste (l.260-270). Aucune de ces listes n'est portée au lot 1 (absentes de `origin/feat/ios-lot1`, `origin/lot1/*`).
21. (corrigé v2) **`/inscription/completer` n'affiche ni rayon ni localisation** : rayon 30 km transmis silencieusement
    (`InscriptionSoignant.tsx` l.671-675) ; le champ « Êtes-vous actuellement salarié(e) … ? » et l'avertissement d'exclusivité
    sont de l'affichage pur (`estSalarieEtablissement` n'est pas envoyé à `register-soignant`, `inscriptionProgressive.ts`
    l.179-205).

## 1. Périmètre

### 1.1 Dans le lot 3

| Domaine | Livré | Source web de référence | Backend consommé |
|---|---|---|---|
| Push — enregistrement | Token APNs hex → `fn_upsert_token_push(p_token, 'IOS')` à chaque `.ready` et retour au premier plan si autorisé ; contrôle d'identité/epoch avant l'appel ; rotation ; jamais de prompt au login | `src/lib/pushNative.ts` l.25-38, l.73-207 ; `src/contexts/AuthContext.tsx` l.145-167 | `fn_upsert_token_push` l.64628 (GRANT authenticated l.85471-85473), table `tokens_push` l.72348 (UNIQUE token l.73657) |
| Push — logout | `fn_desactiver_mon_token_push(p_token)` (2,5 s) puis `unregisterForRemoteNotifications()`, oubli du token ; désinscription locale seule sur `.signedOut` serveur et après suppression de compte | `pushDeviceToken.ts` l.68-124 ; `AuthContext.tsx` l.202-276 | `fn_desactiver_mon_token_push` l.30176 (GRANT l.82446-82448) |
| Push — taps | Délégué `UNUserNotificationCenter` (premier plan : bannière + son + liste ; tap à froid et à chaud), routage `navigationPathForEvent` porté (golden) → `LinkRouter.resolve(link:)` → `DeepLinkCoordinator` ; rôle lu dans le snapshot | `pushNative.ts` l.59-66, l.160-175, l.251-315 ; `pushNative.test.ts` | payload `send-push` : clés racine `type_evenement`, `lien`, + `ALLOWED_DATA_KEYS` (l.75-79, l.687-692) à côté de `aps` (`apns-client.ts` l.103-109) |
| Push — pré-prompt | Écran natif à partir de la 2e session, jamais si déjà accordé/refusé, puis `requestAuthorization` ; textes soignant verbatim | `src/components/DemandePermissionPush.tsx` l.19-28, l.53-91, l.148-150 ; `src/lib/session-count.ts` l.72-74 | — |
| Centre de notifications | `/soignant/notifications` : 200 dernières, marquer lue, tap → route ; pas de Realtime (lot 4), pas de suppression | `src/pages/PageNotifications.tsx` l.46-104 | `notifications` SELECT/UPDATE (RLS l.79399, l.79403 ; GRANT l.86271) |
| Préférences | `/soignant/parametres/notifications` : 4 canaux, matrice par événement (`EVENTS_SOIGNANT` verbatim, filtre de régime), alertes SMS, état d'autorisation de l'appareil + « Ouvrir les réglages » | `src/pages/PageParametresNotifications.tsx` l.42-56, l.105-138, l.140-196, l.206-249 | `fn_obtenir_mes_preferences_notifications` l.45986, `fn_modifier_preferences_notifications` l.44100 ; `soignants.sms_alertes_actives` (GRANT colonne l.85758) |
| Inscription — compte | « Créer un compte » : email, mot de passe ≥ 8, profession, CGU (texte verbatim) → `signUp(data: inscription_progressive, redirectTo: https://jolene.app/inscription/confirmer)` ; compte existant détecté ; confirmation par lien (`token_hash`, implicit, `code`) | `src/pages/InscriptionRapide.tsx` l.55-118, l.255-286, l.320-326 ; `src/lib/inscriptionProgressive.ts` l.41-99 ; `src/pages/ConfirmationInscription.tsx` l.8-34, l.70-84 | GoTrue `signUp` (AuthClient.swift l.377-383), `verifyOTP(tokenHash:type:)` l.1185 (`.signup`/`.email`), `exchangeCodeForSession` l.737 |
| Inscription — parcours | Rôle `INCONNU` : lecture `parcours_inscription`, sinon intention `user_metadata.inscription_progressive` → `fn_demarrer_inscription` (repli `useRole.ts` l.150-170 porté) | `src/pages/ParcoursInscription.tsx` l.33-89, l.93-130 ; `mobile-native/src/account/resolveContext.ts` | `fn_demarrer_inscription` l.30099 (GRANT l.82434-82436), table `parcours_inscription` l.70967 (RLS SELECT l.78227) |
| Inscription — complétion | Prénom, nom, téléphone, date de naissance, contrats acceptés (filtrés par `fn_types_exercice_autorises`), RPPS, rayon ; brouillon serveur ; `register-soignant` ; `refreshSession` puis `start()` | `src/pages/InscriptionSoignant.tsx` l.53-104, l.180-233 ; `inscriptionProgressive.ts` l.117-124, l.169-238 | `fn_enregistrer_parcours_inscription` l.32423 ; `fn_types_exercice_autorises` l.64333 (anon l.85429) ; edge `register-soignant` |
| Profil | `/soignant/profil` : lecture (liste blanche) + audit consultation ; édition identité, téléphone, date de naissance, RPPS non vérifié, rayon, ville de recherche, taux minimum, contrats acceptés, bio, années d'expérience | `src/pages/ProfilSoignant.tsx` l.153-200, l.246-297 ; `src/lib/valider-profil-soignant.ts` | `fn_mon_profil_soignant_complet` l.44659, `fn_modifier_mon_profil` l.43891 |
| Avatar, localisation | Photo (PHPicker/caméra, HEIC → JPEG, 256 px) dans `jolene-documents/<uid>/avatar-<ts>.jpg`, URL signée 5 ans, reçu durable ; position ponctuelle + géocodage inverse (corrigé v2 : le web écrit `avatar-<ts>.webp` en `image/webp`, `AvatarUpload.tsx` l.49-53, l.136-140 ; JPEG natif = écart assumé, D14 ; localisation seulement après L2-T1) | `src/components/AvatarUpload.tsx` l.33-60, l.116-170 ; `SectionProfilPrincipal.tsx` l.623-643 ; `src/lib/geocodage.ts` l.16-19 | Storage (`20260713222000` l.1339-1404, aucune politique UPDATE/DELETE) ; `api-adresse.data.gouv.fr/reverse` |
| Compte | Hub `/soignant/mon-compte` complété : mot de passe (ancien vérifié, 12 car. + 5 critères), thème Système/Clair/Sombre, export RGPD JSON/CSV, liens légaux (Safari), BuildStamp (`profile-version`) | `src/pages/MonCompteSoignant.tsx` l.37-43, l.112-123, l.197-207 ; `src/components/soignant/ChangementMotDePasse.tsx` l.44-100, l.198-208 ; `SectionConfidentialite.tsx` l.30-78 (corrigé v2 : monté par `ProfilSoignant.tsx` l.506, onglet confidentialité du profil, et non par `MonCompteSoignant.tsx` ; le natif le range dans le hub, écart de placement assumé) | `update(user:)` l.1309 ; `fn_rgpd_exporter_rate_limited` l.55321 ; `fn_ecrire_audit_safe` |
| Revenus (lecture) | Onglet Revenus : totaux serveur, paiements rapides à venir, missions terminées avec montant (règle web golden) et état du paiement ; factures, bulletins, avances = renvoi web | `src/pages/MesGains.tsx` l.92-153 ; `src/lib/missionFinanceDisplay.ts` l.41-130 ; `src/lib/paiementSoignantUi.ts` ; `src/components/gains/PaiementsEscrowAVenir.tsx` l.44-80, l.100 ; `PageStripeConnect.tsx` l.70-82 | `fn_mes_revenus_connect` l.42347, `fn_mes_paiements_escrow` l.42184, PostgREST `missions`/`presences`/`mission_creneaux`/`paiements_soignant` (RLS l.79419) |
| Paiement déclaré | Liste `DECLARE`, détail, « Confirmer la réception », « Contester » (motif ≤ 500), relecture | `src/components/BandeauPaiementDeclare.tsx` l.47-66, l.89-170, l.178-206 | `fn_confirmer_paiement_soignant` l.24548, `fn_contester_paiement_soignant` l.25741 (après B3) |
| Stripe Connect | `/soignant/stripe-connect` : statut, onboarding hosted, retour (`?success`/`?refresh`) puis relecture **forcée** (`?force=true`, correction 17) ; compte test et non-libéral : messages verbatim, décidés comme le web par la lecture `soignants.est_compte_test, type_exercice, statut_liberal` **avant** tout appel d'edge (`PageStripeConnect.tsx` l.94-111) (corrigé v2) | `PageStripeConnect.tsx` l.27-60, l.134-150, l.325-500 ; `SectionPaiements.tsx` l.16-63 | edges `stripe-connect-status`, `stripe-connect-onboard` |
| IBAN | Consultation, saisie (contrôle mod 97 local), refus `error_code` traduits, relecture | `SectionPaiements.tsx` l.212-273 | `fn_consulter_mon_iban` l.25539, `fn_enregistrer_mon_iban` l.32251 |
| Sentry Cocoa | Crashs + app hangs, sans PII, release `app.jolene@2.0.0+25`, environnement staging/production, désactivé en démo | `docs/sentry-setup.md` | projet Sentry iOS à créer (§6.5) |
| Universal Links | Routes soignant restantes : `/soignant/notifications`, `/soignant/parametres/notifications`, `/soignant/stripe-connect`, `/inscription/soignant`, `/inscription/reprendre`, `/inscription/completer`, sections de `/soignant/mes-gains?tab=` | `src/App.tsx` l.283-292, l.313-341, l.393-397 ; AASA `/soignant/*`, `/inscription/*` | — |

### 1.2 Hors périmètre

- PSC (`psc-authorize`, `/auth/psc/callback`, `/inscription/soignant/completion`, `psc-logout`) : non construit (§7 D8) ; la
  route reste `.safari` (`LinkRouter.swift` l.23). Parcours étudiant (`fn_professions_autorisees_scolarite`) et vérification
  RPPS en temps réel (`verify-rpps` depuis le formulaire) : renvoi web / contrôle serveur seul (§7 D11).
- Type d'exercice, attestation de cumul (L1222-5), spécialité, consentement GPS (lot 2), pool urgence (lot 4), score et
  évaluations (lot 4) : non édités dans le profil natif (renvoi web).
- Factures d'honoraires, bulletins (lot 4), avances, charges, mandat (décision 3) : renvoi web ; KPI agrégés calculés côté client
  à partir des lignes chargées (`MesGains.tsx` l.92-145, l.165-330) : non portés.
- Realtime des notifications (lot 4), badge d'icône (le serveur n'en envoie pas, `apns-client.ts` l.104-107), extension de
  service de notification, `UIBackgroundModes`.
- Inscription établissement (`/inscription/etablissement`) : renvoi web. Aucune modification sous `ios/`, `android/`,
  `capacitor.config.ts`, `mobile-native/` ; la seule PR backend (B3) est séparée du chantier iOS.

### 1.3 Bloqué ou codable

| Élément | Codable et testable maintenant (niveaux 1-3) | Bloqué |
|---|---|---|
| Push | État d'autorisation, enregistrement et rotation via `PushRegistrarPort` injecté, format hex, `fn_upsert_token_push`/`fn_desactiver_mon_token_push` (stubs + STAGING avec un token factice DEBUG, relu en SQL), ordre du logout, routage golden, tap à froid (XCUITest `-JOLENE_SIMULER_PUSH`), premier plan, pré-prompt, centre et préférences | **Clé APNs sous `GDU5AA28M9`** (sonde négative, `DECISIONS_LOT0.md` décision 7 ; témoin 02/11 `PORTE_LOT0.md` 4.1) + **iPhone physique** (build Debug signé, push entitlement) + **cohorte STAGING non-test** (correction 2) + `APNS_ENVIRONMENT = sandbox` STAGING : réception réelle, tap réel sur ≥ 6 types (niveaux 4-5) |
| Inscription | Tout le flux en démo ; STAGING niveau 3 (signUp réel, `token_hash` relu en SQL, `register-soignant`, ligne `soignants`) | Mesure captcha GoTrue STAGING et prod (`PORTE_LOT0.md` 3.1-3.2), modèle « Confirm signup » et Redirect URLs (Dashboard), réception d'email et Universal Link sur appareil |
| Profil, compte | Tout (démo + STAGING) | Réglage « secure password change » (nonce) inconnu (§6.4) |
| Revenus, paiements, IBAN | Démo + STAGING (fixture D5, corrigé v2) | Contestation : **B3** mergée ; IBAN : RIB `VERIFIE` seedé (D5) ou lot 2 |
| Stripe Connect | Démo + STAGING compte test (le `403 TEST_ACCOUNT_PAYMENT_DISABLED` verbatim est le résultat attendu) | Onboarding réel : soignant LIBERAL **non-test** STAGING + `sk_test_` + saisie des valeurs de test Stripe par Gabrielle sur appareil |
| Sentry | Démarrage, nettoyage, désactivation démo (tests) | Projet `jolene-ios`, DSN, lecture de l'événement |
| PSC | — | Credentials ANS, environnement de test, iOS 17.4 |

## 2. Architecture

### 2.1 Modules touchés

| Module | Ajouts | Invariants |
|---|---|---|
| `JoleneCore` | `Ports/Lot3Ports.swift` (protocoles + stubs `Unwired…`, message via `UnwiredPorts.erreur(port:tranche:lot:)` ajouté) ; `Ports/Ports.swift` : **bloc « Lot 3 » de champs additifs** + extension de `unwiredPorts` ; `Models/Lot3Results.swift` ; `Push/PushRouting.swift`, `Push/PushPolicy.swift`, `Push/PushCoordinator.swift` (acteur) ; `Inscription/InscriptionRules.swift`, `Inscription/OnboardingResolution.swift` ; `Profil/ProfilComplet.swift` (liste blanche), `Profil/ValidationProfil.swift` ; `Compte/ForceMotDePasse.swift`, `Compte/ExportRGPD.swift` (aplatissement CSV) ; `Revenus/MontantMission.swift`, `Revenus/EtatPaiement.swift`, `Revenus/IbanRules.swift` ; `Crash/CrashScrubber.swift` ; `AuditAction` : `donneesPersoConsultation`, `donneesPersoModification`, `rgpdExportDonnees` ; `Demo/Demo*Gateway.swift` | zéro UIKit/SwiftUI/réseau (`DemoNoNetworkTests`) ; `Mission.swift`, `Account.swift`, `Environment.swift` intouchés (`MobileAccess` n'est pas étendu : l'onboarding est résolu dans la vue, §2.5) ; tout port `Sendable` |
| `JoleneSupabase` | `Edge/EdgeResponse.swift` ; `RPC/RPCResponse.swift` : surcharge `appeler(…, exceptionsMetier:)` (SQLSTATE 22023, 23505, P0002 restitués en refus structuré avant `SupabaseErrorMapping`) ; `Push/SupabasePushGateway.swift`, `Notifications/SupabaseNotificationsGateway.swift`, `Notifications/SupabasePreferencesGateway.swift`, `Inscription/SupabaseInscriptionGateway.swift`, `Profil/SupabaseProfilGateway.swift`, `Profil/SupabaseAvatarStorage.swift`, `Compte/SupabaseMotDePasseGateway.swift`, `Compte/SupabaseExportGateway.swift`, `Revenus/SupabaseRevenusGateway.swift`, `Revenus/SupabasePaiementsGateway.swift`, `Revenus/SupabaseIbanGateway.swift`, `Revenus/SupabaseStripeConnectGateway.swift`, `Geo/ApiAdresseGeocodage.swift`, `Keychain/KeychainPushTokenStore.swift` (service `app.jolene.push`) | `SupabaseErrorMapping` inchangé ; `SupabaseGateways.make(client:clock:enrich:)` garde sa signature ; tests `StubURLProtocol` |
| `JoleneDesign` | `ToggleRow`, `SegmentedChoice`, `AvatarView`, `AmountRow` (montant + nature + astérisque), `StatusPill` (états paiement/escrow/Connect), `PermissionCard`, `PasswordCriteriaList` | iOS 16 ; couleurs dynamiques existantes |
| App `Jolene/` | `Composition/PushAppDelegate.swift` (`@UIApplicationDelegateAdaptor`), `Composition/PushRegistrar.swift`, `Composition/NotificationCenterDelegate.swift`, `Composition/ExternalFlowPresenter.swift` (ASWebAuthenticationSession ≥ 17.4 / SFSafariViewController), `Composition/CrashReporting.swift` (Sentry), `Composition/ThemePreference.swift`, `Composition/OneShotLocation.swift` ; écrans `Screens/Push/`, `Screens/Notifications/`, `Screens/Inscription/`, `Screens/Profil/`, `Screens/Compte/`, `Screens/Revenus/` ; `RootView.swift` (aiguillage onboarding l.42-51), `MainTabView.swift` (Revenus l.47-53 ; corrigé v2 : Profil l.55-60 **non modifié**, le hub reste `Screens/ProfileScreen.swift`, étendu par T11) | wrappers `@MainActor` pour UIKit/UN/AuthenticationServices/CoreLocation ; Sentry importé **seulement** dans la cible app |
| `JoleneUITests` | `DemoPushTests`, `DemoNotificationsTests`, `DemoPreferencesTests`, `DemoInscriptionTests`, `DemoProfilTests`, `DemoCompteLot3Tests`, `DemoRevenusTests`, `DemoPaiementsTests`, `DemoStripeTests`, `DemoIbanTests` (corrigé v2), `DemoLiensLot3Tests`, `StagingLot3Tests` | gate `ios-swift-ci.yml` l.379 inchangée (aucun `XCTSkip` démo) ; `StagingLot3Tests` ajouté à `-skip-testing` (l.322) |
| Scripts / CI / docs | `check-rpc-contracts.mjs` (`RPC_SUIVIES` l.42-59 sur `main`, l.53-80 après L1-T0), `export-golden-vectors.mjs`, `export-demo-fixtures.mjs`, `scripts/mobile/staging-lot3-fixture.mjs` + `scripts/ci/lot3-fixture-sql.mjs`, (corrigé v2) workflow `ios-swift-lot3-staging.yml`, `project.yml` (paquet Sentry), `Info.plist` (`JoleneSentryDSN`), `PrivacyInfo.xcprivacy` (vérification seulement), `docs/mobile-swift/{LOT3_PLAN,CONTRATS_RPC_SOIGNANT,PARITE_SOIGNANT,RECETTE_DEVICE_LOT3,PORTE_LOT3}.md` | exporters déterministes (`git diff --exit-code` du job « Cœur ») |
| Backend (PR séparée) | **B3** : `supabase/migrations/<date>_contestation_paiement.sql` | B9 paiements + DROP CONSTRAINT → go humain |

### 2.2 `Gateways` : bloc lot 3

Même règle que le lot 1 (PRINCIPES §2 amendé) : champs ajoutés **dans le corps** du struct, chacun avec un stub par défaut ; les
deux inits existants (branche fondation l.90-104) restent mot pour mot ; **pas de troisième init** : chaque monde assigne ses
ports lot 3 après l'init lot 1 complet, dans une fonction unique `câblerLot3(_:)`, et la liste attendue vit à un seul endroit
(`DemoWorldTests.portsEnAttenteLot3`) ; `SupabaseGatewaysTests` compare toujours les deux mondes.

```swift
// Ports/Ports.swift — seule modification : bloc ajouté après la ligne 88 + noms ajoutés à `unwiredPorts`
// Lot 3 — ajout additif (PRINCIPES §2) ; stubs dans Ports/Lot3Ports.swift (message : « …livré par la tranche Tn du lot 3 »).
public var push: PushRegistrationPort = UnwiredPushRegistrationPort()            // T4
public var notifications: NotificationsCenterPort = UnwiredNotificationsCenterPort() // T5
public var preferences: NotificationPreferencesPort = UnwiredNotificationPreferencesPort() // T6
public var inscription: InscriptionPort = UnwiredInscriptionPort()               // T7, T8
public var profil: ProfilPort = UnwiredProfilPort()                              // T9
public var avatar: AvatarStoragePort = UnwiredAvatarStoragePort()                // T10
public var geocodage: GeocodagePort = UnwiredGeocodagePort()                     // T10
public var motDePasse: MotDePassePort = UnwiredMotDePassePort()                  // T11
public var exportRGPD: ExportRGPDPort = UnwiredExportRGPDPort()                  // T11
public var revenus: RevenusPort = UnwiredRevenusPort()                           // T12
public var paiements: PaiementsDeclaresPort = UnwiredPaiementsDeclaresPort()     // T13
public var iban: IbanPort = UnwiredIbanPort()                                    // T14b (corrigé v2)
public var stripeConnect: StripeConnectPort = UnwiredStripeConnectPort()         // T14a (corrigé v2)
```

Ports **hors `Gateways`** (capacités système, injectés par `AppContainer`, doubles en démo et en test) : `PushPermissionPort`
(`UNUserNotificationCenter`), `PushRegistrarPort` (`UIApplication.registerForRemoteNotifications`), `ExternalFlowPort`,
`CrashReportingPort`, `LocationPort` — (corrigé v2) **uniquement** celui du lot 2 (`Ports/AppareilPorts.swift`, `Appareil.location`,
`positionUnique(delai: 15) async -> ObservationGps`, L2-T1) ; aucune signature parallèle n'est créée au lot 3.

### 2.3 Nouveaux ports (tous `Sendable`)

| Port | Méthodes | Relecture / règle |
|---|---|---|
| `PushRegistrationPort` | `enregistrer(token: String, context:)`, `desactiver(token: String) -> Int` | `void` = succès ; 22023 → `.contract` sans renvoi ; `{success:false}` de la désactivation → `nonDesactive` (jamais bloquant) |
| `PushPermissionPort` | `etat() async -> AutorisationPush` (`nonDemandee/accordee/refusee/provisoire`), `demander() async throws -> Bool` | jamais appelé sans tap utilisateur |
| `PushRegistrarPort` | `enregistrer() async throws -> Data` (token), `desinscrire()` | démo : token fixe `demo` hex 64 |
| `NotificationsCenterPort` | `liste(context:) -> [NotificationJolene]`, `marquerLue(id:, context:) -> NotificationJolene` | relit la ligne (`lue == true`) |
| `NotificationPreferencesPort` | `lire(context:) -> PreferencesNotifications`, `enregistrer(_:, smsAlertes: Bool?, context:) -> PreferencesNotifications` | relit `fn_obtenir…` après `{success:true}` ; n'envoie que des types du catalogue |
| `InscriptionPort` | `creerCompte(email:, motDePasse:, intention:) -> ResultatCompte` (`.confirmationEnvoyee`, `.sessionOuverte`, `.connexionRequise`) ; `confirmer(_ credentials: AuthCallbackCredentials) -> ResultatConfirmation` ; `contexte() -> ContexteOnboarding?` (user courant, email confirmé, `user_metadata.inscription_progressive`) ; `parcours(userId:) -> ParcoursInscription?` ; `demarrer(intention:) -> ParcoursInscription` ; `enregistrerBrouillon(_:) -> ParcoursInscription` ; `typesExercice(profession:) -> [String]?` ; `finaliser(_ form:) -> ResultatFinalisation` | après `register-soignant` 200 : `refreshSession()` puis `SessionStore.start()` ; `.ready` relu = preuve |
| `ProfilPort` | `profil(context:) -> ProfilComplet`, `modifier(_ champs: ModificationProfil, context:) -> ProfilComplet` | relit `fn_mon_profil_soignant_complet` ; audit `DONNEES_PERSO_CONSULTATION` best-effort à la lecture (web l.157-163) |
| `AvatarStoragePort` | `televerser(jpeg: Data, context:) -> URL` | reçu `prepared → started → …` ; `fn_modifier_mon_profil(p_avatar_url:)` puis relecture `avatar_url` |
| `GeocodagePort` | `adresse(lat:, lng:) -> AdresseGeocodee?` | best-effort ; démo = fixture |
| `MotDePassePort` | `changer(ancien:, nouveau:, context:) -> ResultatMotDePasse` | ancien vérifié par `signIn` du même utilisateur ; audit `DONNEES_PERSO_MODIFICATION` |
| `ExportRGPDPort` | `exporter(context:) -> AnyJSON` | `{error}` verbatim ; audit `RGPD_EXPORT_DONNEES` |
| `RevenusPort` | `totaux(context:)`, `paiementsRapides(context:)`, `missionsTerminees(context:, page:)` | lecture seule ; audit `DONNEES_PERSO_CONSULTATION` (`page: mes_gains`) |
| `PaiementsDeclaresPort` | `aConfirmer(context:)`, `confirmer(id:, context:)`, `contester(id:, motif:, context:)` | relit `paiements_soignant` (`CONFIRME` / `CONTESTE`), jamais de retrait local d'office |
| `IbanPort` | `consulter(context:)`, `enregistrer(iban:, titulaire:, context:) -> ResultatIban` | succès = `success == true` puis `consulter` relu |
| `StripeConnectPort` | `statut(context:)`, `lienOnboarding(context:) -> ResultatLienConnect` | statut relu à chaque retour |
| `ExternalFlowPort` | `ouvrir(url:, retour: RetourAttendu) async -> IssueFlux` (`.retour(URL)`, `.ferme`) | l'issue n'est jamais un succès : elle déclenche une relecture |
| `CrashReportingPort` | `demarrer(environnement:, release:)`, `utilisateur(id: String?)` | démo : no-op ; `id` seul |

`JoleneError.Kind` n'est pas étendu ; refus métier par enums de résultat (`Lot3Results.swift`).

### 2.4 Formes de réponse et traitement

| Appel | Succès | Refus HTTP 200 | Exceptions / statuts | Swift |
|---|---|---|---|---|
| `fn_upsert_token_push(text,text)` → `void` | corps vide | — | 42501 « Non authentifie » (l.64642), 22023 token/plateforme (l.64645-64648) | 42501 → `.unauthorized` (mapping l.23) ; 22023 → `.contract` par `exceptionsMetier`, jamais de renvoi ; (corrigé v2) appel par `execute()` → `Void`, jamais `RPCResponse.appeler` (décodage `AnyJSON` en échec sur corps vide, correction 16) ; erreur avalée par `PushCoordinator` (best-effort, jamais de déconnexion) |
| `fn_desactiver_mon_token_push(text)` → jsonb | `{success:true,tokens_desactives,scope:'CURRENT_DEVICE'}` (l.30214-30218) | `{success:false,error:'Non authentifie'\|'Token push invalide'}` (l.30186-30191) | — | `RPCResponse` ; échec = journal DEBUG + désinscription locale quand même |
| `fn_obtenir_mes_preferences_notifications()` | `{global:{canal_email,canal_sms,canal_push,canal_in_app,…}, par_evenement:[{type_evenement,canal,actif}]}` (l.46015) ; **crée la ligne par défaut** (l.46001-46006) | `{error:'Non authentifié'}` (l.45995) | — | validation stricte des 4 booléens (web l.117) sinon erreur d'écran, jamais de défauts affichés |
| `fn_modifier_preferences_notifications(5 args)` | `{success:true}` (l.44147) | `{error}` | 22P02 si type/canal hors enum (casts l.44130-44131) | n'envoie que les types de `EVENTS_SOIGNANT` ; 22P02 → `.contract` ; relecture |
| `fn_demarrer_inscription(5 args)` → ligne `parcours_inscription` | jsonb de la ligne | — | 42501 « Session invalide. », 22023 messages utilisateur (l.30114-30120), 23505 = code de réservation `ACCOUNT_*` (l.30127) | 22023 verbatim ; 23505 → « Ce compte possède déjà un espace Jolene. Connectez-vous pour le retrouver. » (web l.98-104) |
| `fn_enregistrer_parcours_inscription(jsonb)` | ligne | — | 22023 « Brouillon invalide. » / « Champ non autorisé dans le brouillon. » (liste blanche l.32436-32442), P0002 (l.32456) | n'envoie que les clés de la liste blanche, jamais mot de passe ni email |
| `fn_types_exercice_autorises(text)` → `text[]` | tableau ; défaut `SALARIE,LIBERAL,MIXTE` si profession absente de la table (l.64340-64342) | — | — | indisponible → message web « Le référentiel est momentanément indisponible… » (`InscriptionSoignant.tsx` l.92-97), `LIBERAL` retiré tant que non confirmé (l.192-199) |
| edge `register-soignant` (POST, Bearer, `verify_jwt=false` `config.toml` l.48-49) | 200 `{ok:true,success:true,soignant_id}` (l.400-403) | — | `{ok:false,code,message,error,details?}` (`_shared/errors.ts` l.34-46) : 401 `UNAUTHORIZED`/`INVALID_TOKEN`, 409 `ACCOUNT_*`/`USER_ALREADY_REGISTERED`/`RPPS_ALREADY_REGISTERED`, 400 `MISSING_REQUIRED_FIELDS`/`UNDERAGE`/`RPPS_*`, 429 `RATE_LIMITED` (5/10 min/IP l.29-44), 503 `ACCOUNT_RESERVATION_UNAVAILABLE`/`ACCOUNT_FINALIZATION_PENDING` (l.364-367), 500 `INTERNAL_ERROR` | `FunctionsError.httpError(code:data:)` (FunctionsClient.swift l.253-255) décodé par `EdgeResponse` ; `message` verbatim ; 503 FINALIZATION → déconnexion locale + message serveur |
| `fn_mon_profil_soignant_complet()` | ligne jsonb | `{error:'Non authentifié'\|'Profil introuvable'}` (l.44665, l.44681) | — | décodeur liste blanche + règles de `validerProfilSoignant` (golden) |
| `fn_modifier_mon_profil(29 args)` | `{success:true}` (l.44015) | `{error}` prénom/nom vides (l.43906-43909) | — | **`COALESCE` : un champ ne peut pas être vidé** (l.43933-43977) → le natif n'offre pas « effacer », relecture |
| Storage `jolene-documents` | `<uid>/avatar-<ts>.jpg`, `upsert:false` | — | 400/403 (MIME, taille 25 Mo, politique `fn_peut_gerer_objet_jolene`) | reçu `refused` ; URL signée 5 ans (web l.143-148) |
| `fn_rgpd_exporter_rate_limited()` | export jsonb | `{error}` (30/h, l.55333-55336) | — | `{error}` verbatim, aucun fichier écrit |
| `paiements_soignant` SELECT `statut=DECLARE` | lignes (RLS l.79419) | — | — | noms d'établissement via `fn_etablissements_safe` seul |
| `fn_confirmer_paiement_soignant(uuid)` | `{success,confirme_le,facture_honoraires_id}` (l.24596-24600) | `{error}` : introuvable, accès refusé, déjà confirmé, statut (l.24557-24577) | — | relecture `statut = CONFIRME` et `confirme_par_soignant` |
| `fn_contester_paiement_soignant(uuid,text)` | `{success,litige_id}` | `{error}` introuvable / accès refusé (l.25750-25751) | **23514 aujourd'hui** (correction 3) ; (corrigé v2) **23505** si un litige `AUTRE` sans facture est déjà ouvert sur la mission (`uq_litige_mission_type_ouvert_legacy` l.75280) | bouton verrouillé tant que B3 n'est pas mergée (§3 T13) ; relecture `CONTESTE` |
| `fn_consulter_mon_iban()` | `{iban_renseigne,iban_verifie,verification_requise,iban_last4,iban_titulaire}` (l.25576-25582) | `{error}` | — | affichage `•••• {last4}` |
| `fn_enregistrer_mon_iban(text,text)` | `{success:true,iban_last4,titulaire,source_document_id}` (l.39511-39516) | `{success:false,error_code,[error]}` : `NON_AUTHENTIFIE`, `PROFIL_INTROUVABLE`, `TITULAIRE_NON_CONCORDANT`, `RIB_VERIFIE_REQUIS`, `IBAN_INVALIDE`, `RIB_COURANT_REQUIS`, `IDENTITE_VERIFIEE_REQUISE`, `IDENTITE_COURANTE_REQUISE`, `RIB_NON_CONCORDANT` | — | `RPCResponse.codeErreur` (l.112) → messages ; `error` serveur verbatim s'il existe |
| `fn_mes_revenus_connect(date)` | `{mois_en_cours,total,en_attente,stripe_connect_actif}` (l.42411-42416) | — | — | trois nombres finis exigés (web `PageStripeConnect.tsx` l.73-76) sinon section en erreur |
| `fn_mes_paiements_escrow()` | tableau `{mission_id,mission_intitule,etablissement_nom,honoraires_cents,etat,date_affichee,mission_date,a_litige}`, `etat` ∈ `VERSE, ANNULE, RETARDE, LITIGE, VERSEMENT_EN_COURS, ATTENTE_VALIDATION, RESERVE` | — | — | libellés verbatim (`PaiementsEscrowAVenir.tsx` l.44-80, invariant « jamais garanti ») |
| edge `stripe-connect-status` (POST, corrigé v2) | `{statut,onboarding_complete,charges_enabled,payouts_enabled,iban_last4,requirements,disabled_reason,cached…}` ; `NON_DEMANDE` sans appel Stripe si aucune ligne (l.56-60) | — | non-2xx → erreur d'écran : 401/403 (`Consultation utilisateur uniquement` l.36), 405 hors POST (l.30), 503 `STRIPE_STATUS_UNAVAILABLE`/`STRIPE_NOT_CONFIGURED` (l.53, l.115) | `COMPLET` accepté seulement si les trois drapeaux sont vrais (web l.53-54) ; statut hors des six valeurs → erreur ; cache 5 min contourné par `?force=true` au retour (correction 17) |
| edge `stripe-connect-onboard` (POST, `Origin: https://jolene.app`) | 200 `{success,url,account_id}` (l.208-212) | — | 401 `{error:"Non autorisé"}`, 403 `ORIGINE_NON_AUTORISEE`, (corrigé v2) 404 `Soignant introuvable` (l.87-92), 403 `TEST_ACCOUNT_PAYMENT_DISABLED`, 403 non-libéral (l.115-130), 503 classification, erreurs Stripe mappées `{error:code,message}` (l.218-229) | `EdgeResponse` ; test → « Stripe désactivé sur ce compte de test » (verbatim web) |
| `notifications` | SELECT 200 lignes, UPDATE `lue`,`lue_le` (RLS l.79403) | — | — | relecture de la ligne ; pas de DELETE |

`EdgeResponse` (T1) : `{ok,success,code,message,error,details}` tolérant ; lit le corps de `FunctionsError.httpError` avant tout
mapping ; `401` → `.unauthorized` ; `code` connu → refus structuré ; sinon `message`/`error` verbatim ; aucun renvoi.

### 2.5 Flux

```
Push — enregistrement
  .ready(snapshot) | scène .active  →  PushCoordinator(epoch)
    PushPermissionPort.etat() == .accordee|.provisoire ?  sinon rien (aucun prompt)
    PushRegistrarPort.enregistrer() → token Data → hex minuscule (64+ car.)
    controller.gateways(for: epoch) != nil ?  sinon abandon (identité changée, web l.25-29)
    push.enregistrer(token, context)  → KeychainPushTokenStore.memoriser(token, userId)
  Pré-prompt : sessionCount >= 2 (lancements à froid, UserDefaults `jolene.sessionCount`) ET état .nonDemandee
             ET pas de marque `jolene.pushPrePrompt` → PermissionCard (5 s après .ready, web l.79) ; « Activer » → demander()

Push — tap (UNUserNotificationCenterDelegate posé dans PushAppDelegate.didFinishLaunching)
  userInfo [String:String] → PushRouting.path(data:, role: snapshot.role.role) (golden, lien explicite d'abord)
    → LinkRouter.resolve(link:) → JoleneRoute → DeepLinkCoordinator
  avant .ready : intention mémorisée (lot 1 T10), rejouée une fois prête, rôle alors connu (mieux que le web, l.40-57)
  premier plan : willPresent → [.banner, .sound, .list] + rafraîchissement du centre si visible

Déconnexion volontaire (SessionStore.signOut)
  audit DECONNEXION (lot 1 T9) → push.desactiver(token mémorisé) borné 2,5 s → PushRegistrar.desinscrire()
  → oubli du token → CrashReporting.utilisateur(nil) → controller.signOut() (epoch++)
Déconnexion subie (.signedOut du SDK) et suppression de compte : desinscrire() + oubli, sans RPC (JWT absent)

Inscription
  Login « Créer un compte » → InscriptionRapideScreen → inscription.creerCompte
    .confirmationEnvoyee → message verbatim (InscriptionRapide l.320-326)
    .sessionOuverte → inscription.demarrer(intention) → session.start()
    .connexionRequise (email déjà inscrit ou identities vide, inscriptionProgressive.ts l.78-94) → LoginScreen pré-rempli
  Lien /inscription/confirmer (UL ou -JOLENE_OPEN_URL) → AuthCallbackCredentials.signup (l.53-68)
    tokenHash → verifyOTP(tokenHash:, type: .signup|.email) ; implicit → setSession ; pkce → exchangeCodeForSession (une fois)
    échec → texte verbatim ConfirmationInscription l.75-78 + « Se connecter »
  RootView : .blocked(.unsupportedRole(nil | "PROFIL_INCOMPLET"))  →  OnboardingRootView
    inscription.contexte() + parcours(userId) ; sans parcours mais intention SOIGNANT valide (cgu == true) → demarrer
    parcours SOIGNANT → CompletionProfilScreen → enregistrerBrouillon → finaliser (register-soignant)
      200 → refreshSession() → session.start() → .ready (preuve)   ;  ETABLISSEMENT → renvoi web
  SessionController et MobileAccess ne changent pas : l'écart « rôle INCONNU » (PRINCIPES §5) est résolu dans la vue

Stripe Connect
  stripeConnect.lienOnboarding (Origin jolene.app) → ExternalFlowPort.ouvrir(url, retour: /soignant/stripe-connect)
    iOS ≥ 17.4 : ASWebAuthenticationSession(prefersEphemeral: true, callback .https(host:"jolene.app", path:"/soignant/stripe-connect"))
    iOS < 17.4 : SFSafariViewController ; la return_url se charge dans la feuille (UL non garanti, correction 6) ; « OK » → .ferme
      (corrigé v2) si un UL /soignant/stripe-connect?… arrive malgré tout, il ferme la feuille ; ce n'est jamais la preuve
  toute issue → stripeConnect.statut(force: true) relu (corrigé v2, correction 17) ; ?refresh=true → nouveau lien sur tap (jamais automatique)

Paiement déclaré
  confirmer → {success} → relecture CONFIRME ; contester(motif non vide ≤ 500) → {success, litige_id} → relecture CONTESTE
  bouton désactivé pendant l'appel ; un timeout impose une relecture, jamais un renvoi (PRINCIPES §3-§4)
```

### 2.6 Données et cache

- Aucun cache persistant d'écran. Mémoire par epoch (`controller.gateways(for:)` avant appel, `controller.epoch == snapshot.epoch`
  avant écriture d'état), comme au lot 1.
- Persistance locale du lot 3 : token APNs + userId (Keychain `app.jolene.push`, `kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly`) ;
  compteur de lancements et marque du pré-prompt (UserDefaults, par appareil) ; thème (UserDefaults `jolene.theme`, par appareil) ;
  reçu d'avatar (journal lot 1). Jamais de brouillon d'inscription local : le brouillon est serveur (`parcours_inscription`) ;
  jamais de mot de passe, d'IBAN ni d'export persistés (fichier d'export temporaire `NSFileProtectionComplete`, supprimé à la
  fermeture de la feuille de partage).
- **État dérivé** : profession de la complétion = `parcours.donnees.profession` (lecture seule) ; contrats proposés = réponse de
  `fn_types_exercice_autorises` (table paramétrée, aucune règle en dur) ; état d'un paiement = `classerPaiementSalaire` sur la
  dernière déclaration (`indexerDernierPaiementParMission`) ; montant = `montantFinanceAfficheMission` sur
  `missions.type_contrat_applique` puis `type_contrat_recherche` (règle `CLAUDE.md` « régime/contrat », jamais
  `soignants.type_exercice`) ; état Connect = serveur seul.
- Visibilité : nom d'établissement **exclusivement** via `fn_etablissements_safe` (lot 1) ; `fn_mes_paiements_escrow` fournit son
  propre `etablissement_nom` pour les missions du soignant (l.42192).
- Données sensibles : `ProfilComplet` sans propriété pour `numero_secu`, `numero_adeli`, `siret_liberal`, `code_ape`,
  `assujetti_tva`, `numero_tva`, `stripe_account_id`, `iban_last4` (test-garde par `Mirror`) ; (corrigé v2) `adresse_lat`/`adresse_lng`
  sont décodées (localisation du profil) mais jamais affichées ni journalisées ; Sentry ne reçoit ni URL de rappel
  (`token_hash`, `code`, `access_token`, `refresh_token`), ni corps de requête, ni IBAN.

### 2.7 Mode démo et fixtures (`scripts/mobile/export-demo-fixtures.mjs`, horloge `2026-11-02T00:00:00Z`)

| Écran | Fixture / double | Comportement démo |
|---|---|---|
| Push | `DemoPushPermission` (argument DEBUG `-JOLENE_PUSH_AUTORISATION nonDemandee\|accordee\|refusee`), `DemoPushRegistrar` (token fixe), `DemoPushGateway` (actor, compte les appels) ; `-JOLENE_SIMULER_PUSH <TYPE>[:mission_id][:lien]` traité comme un tap à froid ; `-JOLENE_SESSION_COUNT 2` | aucune feuille système ; état visible `push-etat-appareil` |
| Centre | `demo-notifications.json` : 7 lignes (mission démo, `/soignant/missions`, `/soignant/mes-gains?tab=factures`, `/soignant/stripe-connect`, `/soignant/parametres/notifications`, `/soignant/litiges` → Safari, 1 lue) | marquer lue dans l'actor |
| Préférences | `demo-preferences.json` (global + 3 exceptions) | enregistrement relu depuis l'actor |
| Inscription | `DemoInscriptionGateway` : `creerCompte` → `.confirmationEnvoyee` ; `-JOLENE_OPEN_URL https://jolene.app/inscription/confirmer?token_hash=demo&type=signup` → identité `demo-nouveau-soignant` + `demo-parcours.json` ; `demo-types-exercice.json` (IDE : 3 types, AS : `SALARIE`) ; `finaliser` → bascule vers l'espace `demo-soignant` (les autres gateways refusent toujours un autre userId, `.demoOnly`) | `register-soignant` simulé avec les codes 400 `UNDERAGE` et 409 via `-JOLENE_DEMO_INSCRIPTION_REFUS <code>` |
| Profil / avatar / localisation | `demo-profil-complet.json` (liste blanche **seulement** ; test qui échoue si une clé interdite y apparaît), image démo en ressource, `DemoGeocodage` (« Lyon ») | upload en mémoire, reçu Keychain réel |
| Compte | `DemoMotDePasse` (ancien = `demo-motdepasse`), `demo-export-rgpd.json` | partage via `UIActivityViewController` réel sur fichier démo |
| Revenus | `demo-revenus.json`, `demo-escrow.json` (les 7 états), `demo-missions-terminees.json` (LIBERAL, SALARIE, contrat non choisi, plafond Rist historique) | lecture |
| Paiements déclarés | `demo-paiements-declares.json` (2 `DECLARE`) + actor | confirmer/contester relus ; contestation activée en démo |
| Stripe / IBAN | `demo-stripe-status.json` (variantes par `-JOLENE_DEMO_STRIPE NON_DEMANDE\|EN_COURS\|COMPLET\|SUSPENDU\|REJETE\|SUPPRIME\|TEST` — corrigé v2 : `REJETE` ajouté, statut de la contrainte `stripe_connect_onboarding_statut_check` l.72036 et écran web l.490-520), `DemoExternalFlow` (rend `.retour(?success=true)`), `demo-iban.json` ; IBAN d'exemple ISO 13616 `FR7630006000011234567890189` uniquement | statut relu après le « retour » |
| Sentry | `CrashReporting` n'est jamais initialisé en démo | test unitaire + sentinelle « 0 requête » inchangée |

## 3. Tranches PR

Taille 400 à 1 400 lignes Swift (hors JSON). Chaque PR : tests d'abord, implémentation, XCUITest démo sur iPhone, iPad portrait,
iPad paysage ; `swift test` des deux packages avec `-strict-concurrency=complete` et 0 avertissement ; exporters sans diff ;
`xcodegen generate` relancé après rebase (pbxproj versionné) ; CI verte + revue fraîche B8 ; merge sériel squash. Identifiants
d'accessibilité sur tout contrôle testé (PRINCIPES §6) ; les identifiants du lot 0 conservés (`profile-email`, `profile-role`,
`profile-profession`, `logout-button`, `profile-version`, `network-sentinel`, `access-blocked`).

### B3 — PR backend : contestation de paiement (hors chantier iOS, 0 ligne Swift)

- **Objectif** : rendre `fn_contester_paiement_soignant` exécutable et idempotente.
- **Fichiers** : `supabase/migrations/<YYYYMMDDHHMMSS>_contestation_paiement.sql` : `ALTER TABLE notifications DROP CONSTRAINT
  notifications_type_check, ADD CONSTRAINT … ('…liste live…', 'CONTESTATION_PAIEMENT')` à partir de `pg_get_constraintdef` live ;
  `CREATE OR REPLACE fn_contester_paiement_soignant` depuis la définition **live** (`scripts/dump-live-def.sh`) avec garde
  `auth.uid() IS NOT NULL AND fn_compte_auth_actif()`, `FOR UPDATE`, statut ∈ (`DECLARE`,`EN_ATTENTE`) sinon `{error}`, motif
  non vide ; test SQL de régression (`test:regression`) ; ACL conservées (`CREATE OR REPLACE`).
- (corrigé v2) **Option recommandée, sans DDL destructif** : ne pas élargir le CHECK ; supprimer l'INSERT explicite
  `CONTESTATION_PAIEMENT` (l.25776-25784), redondant avec `trg_notifier_creation_litige` qui notifie déjà l'établissement en
  `LITIGE_OUVERT` (l.76080 ; le motif reste lisible dans `litiges.motif`, « Paiement contesté — … »). Option de repli si
  Gabrielle veut garder une notification dédiée : élargissement du CHECK ci-dessus (DROP/ADD CONSTRAINT depuis la définition
  live). Dans les deux cas : garde `NOT conteste AND NOT confirme_par_soignant` en plus du statut, motif `btrim` 1-500, et
  traitement explicite de `uq_litige_mission_type_ouvert_legacy` (l.75280) : si un litige ouvert sans facture existe déjà pour la
  mission, `{error}` clair (ou rattachement du paiement à ce litige — à trancher dans la PR) au lieu d'un 23505 opaque.
  `test:escrow` requis en plus de `test:regression` + `guards` (diff sous `supabase/` et paiements, B7).
- **Critère** : contestation STAGING → `paiements_soignant.statut = CONTESTE`, une ligne `litiges`, une notification
  établissement (`LITIGE_OUVERT`, ou `CONTESTATION_PAIEMENT` dans l'option de repli) ; second appel → `{error}` sans second
  litige ni 23505 ; contestation sur une mission portant déjà un litige ouvert → `{error}` explicite.
- **B9 / HARD STOP** : B9 (paiements ; DROP CONSTRAINT dans l'option de repli) → **go humain**. **Dépendances** : aucune ; préalable à T13.

### T0 — Contrats et documentation du lot 3 (0 ligne Swift)

- **Fichiers** : `scripts/mobile/check-rpc-contracts.mjs` (`RPC_SUIVIES` : `fn_upsert_token_push` déjà lot 3 ; ajouter en
  `a_venir` lot 3 `fn_desactiver_mon_token_push`, `fn_obtenir_mes_preferences_notifications`, `fn_modifier_preferences_notifications`,
  `fn_demarrer_inscription`, `fn_enregistrer_parcours_inscription`, `fn_types_exercice_autorises`, `fn_modifier_mon_profil`,
  `fn_rgpd_exporter_rate_limited`, `fn_confirmer_paiement_soignant`, `fn_contester_paiement_soignant`, `fn_consulter_mon_iban`,
  `fn_enregistrer_mon_iban`, `fn_mes_revenus_connect`, `fn_mes_paiements_escrow` ; `fn_mon_profil_soignant_complet` déjà lot 3
  par T0 du lot 1) + `--update` → `ios-native/rpc-contracts.json` ; `docs/mobile-swift/CONTRATS_RPC_SOIGNANT.md` (une fiche par
  RPC du §2.4 + fiches edges `register-soignant`, `stripe-connect-status`, `stripe-connect-onboard` (Origin), payload
  `send-push`, « PSC non consommé ») ; classement manuel `RPC_UTILISATEUR_AUTH_INTERNE` de `fn_demarrer_inscription` et
  `fn_enregistrer_parcours_inscription` (SECURITY DEFINER, `auth.uid()`, GRANT authenticated) — (corrigé v2) consigné **dans la
  fiche seulement** (`manifeste: null` accepté par le générateur, correction 13 ; aucun fichier sous `supabase/`) ; ajout de
  `fn_lier_iban_verifie_document` à `RPC_JAMAIS_SUIVIES` (service_role seul, l.83209-83210 : un appel natif serait un 42501 et
  contournerait la garde de `fn_enregistrer_mon_iban`) ; `PARITE_SOIGNANT.md` (lignes
  lot 3 : `profil`, `mes-gains`, `notifications`, `stripe-connect`, `parametres/notifications`, alias `reputation` ; factures,
  avances, bulletins → « renvoi web assumé jusqu'au lot 4 ») ; `docs/mobile-swift/LOT3_PLAN.md` ; squelettes
  `RECETTE_DEVICE_LOT3.md`, `PORTE_LOT3.md`.
- **Critère** : préalable à tous. **B9 / HARD STOP** : aucun. **Dépendances** : aucune.

### T1 — Fondation lot 3 (~800 lignes)

- **Fichiers** : `JoleneCore/Ports/Lot3Ports.swift`, `Ports/Ports.swift` (bloc §2.2 + `unwiredPorts`), `Models/Lot3Results.swift`
  (`ResultatCompte`, `ResultatConfirmation`, `ResultatFinalisation`, `ResultatMotDePasse`, `ResultatIban`, `ResultatLienConnect`,
  `IssuePaiement`, `AutorisationPush`, `IssueFlux`), `Models/Lot1Results.swift` (`AuditAction` +3 cas), `Demo/DemoWorld.swift`
  (`câblerLot3` avec stubs), `JoleneSupabase/Edge/EdgeResponse.swift`, `RPC/RPCResponse.swift` (surcharge `exceptionsMetier`,
  l.220-235 de la branche ; (corrigé v2) + variante `appelerSansCorps` pour les RPC `void`, `execute()` → `Void`, correction 16),
  `SupabaseGateways.swift` (bloc lot 3), `docs/mobile-swift/PRINCIPES.md` §2 (« bloc lot 3, pas de troisième init »),
  (corrigé v2) `Ports/Lot1Ports.swift` : surcharge générique `UnwiredPorts.erreur(port:tranche:lot:)` **seulement si** L2-T1 ne
  l'a pas déjà ajoutée.
- **Tests d'abord** : `Lot3PortsTests` (chaque stub lève `.contract` citant sa tranche), `DemoWorldTests.portsEnAttenteLot3`,
  `SupabaseGatewaysTests` (mondes comparés), `EdgeResponseTests` (200 ; `httpError` 400/401/403/409/429/503 avec et sans `code` ;
  corps non JSON → `fallback`), `RPCResponseExceptionsTests` (22023 message restitué, 23505 code restitué, 42501 → `.unauthorized`
  inchangé, PGRST202 → `.contract` inchangé ; (corrigé v2) RPC `void` : 204 et 200 à corps vide = succès, 22023 restitué).
- **Critère** : préalable. **B9 / HARD STOP** : aucun. **Dépendances** : T0 ; lot 1 T1 mergé.

### T1b — JoleneDesign lot 3 (~500 lignes)

- **Fichiers** : `ToggleRow.swift`, `SegmentedChoice.swift`, `AvatarView.swift` (initiales + couleur de repli, port
  `AvatarUpload.tsx` l.25-31), `AmountRow.swift`, `StatusPill.swift`, `PermissionCard.swift`, `PasswordCriteriaList.swift`,
  `Tests/JoleneDesignTests/JoleneDesignLot3Tests.swift` (contraste AA clair/sombre, cibles 44 pt, identifiants).
- **Critère** : XCUITest indirect. **Dépendances** : lot 1 T1b ; parallèle à T1.

### T2 — Golden lot 3 (~1 000 lignes hors JSON)

- **Fichiers** : `scripts/mobile/export-golden-vectors.mjs` : hook de résolution étendu par une **liste d'exceptions nommée**
  pour `src/lib/pushNative.ts` seulement (`@/integrations/supabase/client`, `./platform`, `./logger`, `./pushDeviceToken`,
  `./nativeResume`, `./navigationNotification` → modules inertes qui lèvent s'ils sont appelés ; `./nativeLinks` réel — (corrigé
  v2) il importe `@capacitor/core` (l.1, utilisé seulement par `urlCallbackPublique` l.41) : vérifier à l'ouverture qu'il s'évalue
  sous Node, sinon module inerte `Capacitor.isNativePlatform() → false` ; exception nommée, documentée dans le hook, car L1-T2
  refuse tout alias `@/` hors `@/lib/`) ; grilles :
  `navigationPathForEvent` ((corrigé v2) les **32** types des `case` de `pushNative.ts` l.263-313 + un type inconnu × rôles
  `SOIGNANT`/`ADMIN_ETABLISSEMENT`/`ETABLISSEMENT`/`ADMIN`/`null` × ids présents, absents, à encoder × liens explicites
  internes/externes/racine, y compris les clés `link` et `url` lues par `lienExplicite` l.61) + les **15** attentes (6 `it`) de
  `pushNative.test.ts` ;
  `missionFinanceDisplay.ts` (cas de son test + grille contrat × montants nuls × plafond Rist) ; `paiementSoignantUi.ts`
  (`repartirPaiementConfirme`, `indexerDernierPaiementParMission`, `classerPaiementSalaire`) ; `valider-profil-soignant.ts`
  (cas de son test + types invalides) ; `session-count.ts` (`estSessionRecurrente` sur compteur) ; (corrigé v2)
  `preferencesModesExercice.ts` (`modeExerciceSelectionne`, `modifierPreferenceModeExercice`, cas de son test : `CDD`/`VACATION`
  /`SALARIE` = salarié) et les listes `PROFESSIONS_SANS_RPPS` / `PROFESSIONS_RPPS_REQUIS` de `constantes.ts` l.55, l.61 (vecteur
  de dérive, pas une règle juridique). Sorties
  `push-routing.json`, `mission-finance-display.json`, `paiement-soignant-ui.json`, `valider-profil-soignant.json`,
  `preferences-modes-exercice.json`, `professions-rpps.json`.
  Swift : `Push/PushRouting.swift`, `Revenus/MontantMission.swift`, `Revenus/EtatPaiement.swift`, `Profil/ValidationProfil.swift`,
  `Push/PushPolicy.swift`, (corrigé v2) `Profil/ModesExercice.swift`, `Inscription/ProfessionsRpps.swift` ; `RulesGoldenTests.swift`
  (`Golden.fichiers` +6) ; `ios-swift-ci.yml` (filtre de chemins +6 modules).
- **Règle** : on corrige le port, jamais le vecteur. `PushRouting` délègue la normalisation à `JoleneLink.normalize` ((corrigé v2)
  couverte au lot 0 par un **port 1:1** des tests de `nativeLinks.test.ts`, `LinksNormalizeTests.swift`, et non par un vecteur
  exporté).
- **Critère** : « table de routage testée unitairement sur les cas de `src/lib/pushNative.test.ts` » (plan l.196). **B9** :
  aucun (règles pures). **Dépendances** : lot 1 T2 mergé (loader) ; parallèle à T1.

### T3 — Universal Links complets côté soignant (~600 lignes)

- **Fichiers** : `JoleneCore/Links/JoleneRoute.swift` (+ `.notifications`, `.parametresNotifications`,
  `.stripeConnect(retour: RetourConnect?)`, `.inscription(EtapeInscription)` pour `/inscription/soignant|reprendre|completer` —
  (corrigé v2) la query est conservée dans `EtapeInscription` : `?ref=`/`?parrain=` (web `InscriptionSoignant.tsx` l.109-117)
  sert au lot 4 (T6 parrainage) ; et (corrigé v2) séparation de `.profil` (aujourd'hui commun à `/soignant/profil` et
  `/soignant/mon-compte`, `LinkRouter.swift` l.68-70) en `.monCompte` (hub : `mon-compte`, `parametres`, `parametres-complet`)
  et `.profil` (édition : `profil`, `reputation` ; `score`/`fiabilite*` restent sur le hub tant que la page score est lot 4)),
  `LinkRouter.swift` (l.57-88 : nouveaux chemins ; `/inscription/etablissement`, `/inscription/soignant/completion`,
  `/auth/psc/callback` restent `.safari`), `DeepLinkIntent.swift` (section Revenus depuis `?tab=` : `factures`/`bulletins`/
  `avances` → `.safari` canonique, `paiements` → section « Paiements à confirmer »), `Jolene/Composition/DeepLinkCoordinator.swift`
  (chaque nouvelle route mappée sur `.safari(canonique)` jusqu'à la tranche de son écran, qui change **une ligne**),
  `LinksRouterTests.swift`, `LinksAASATests.swift`, `JoleneUITests/DemoLiensLot3Tests.swift`.
- **Tests d'abord** : table complète (15 motifs AASA inchangés, nouvelles routes, query/fragment conservés, ids encodés) ;
  XCUITest : `-JOLENE_OPEN_URL https://jolene.app/soignant/notifications` → écran (Safari tant que T5 n'est pas mergé : test
  ajusté par T5).
- **Critère** : « Universal Links complets » soignant. **Dépendances** : T1, lot 1 T10.

### T4 — Push : autorisation, enregistrement, logout (~1 000 lignes)

- **Fichiers** : `JoleneCore/Push/PushCoordinator.swift` (acteur : epoch, état, `surReady`, `surActive`, `avantDeconnexion`,
  `surDeconnexionSubie`), `Session/SessionStore.swift` (hooks : `.ready` → `surReady` ; `signOut` → `avantDeconnexion` borné
  2,5 s avant `controller.signOut()` ; `handleAuthEvent(.signedOut)` → `surDeconnexionSubie`), `JoleneSupabase/Push/SupabasePushGateway.swift`,
  `Keychain/KeychainPushTokenStore.swift`, `Demo/DemoPush*.swift`, `Jolene/Composition/PushAppDelegate.swift`
  (`didRegisterForRemoteNotificationsWithDeviceToken`, `didFailToRegister…`), `PushRegistrar.swift` (continuation unique, délai
  15 s comme le web l.178-191), `JoleneApp.swift` (`@UIApplicationDelegateAdaptor`, `.active` → `surActive`), `AppContainer.swift`
  (injection), `Screens/Profil/EtatNotificationsAppareilRow.swift` (`push-etat-appareil`, `push-ouvrir-reglages` →
  `UIApplication.openNotificationSettingsURLString`), `JoleneUITests/DemoPushTests.swift` (partie autorisation).
- **Tests d'abord** : `PushCoordinatorTests` (pas d'autorisation → aucun appel ; autorisé → upsert avec hex ; epoch changé pendant
  l'enregistrement → aucun upsert ; token tourné → nouvel upsert ; `.active` sans changement → idempotent ; déconnexion : RPC puis
  désinscription puis oubli, RPC en échec ou > 2,5 s → désinscription quand même ; `.signedOut` subi → désinscription sans RPC) ;
  `SupabasePushGatewayTests` (corps `{p_token,p_plateforme:"IOS"}`, `void` ; (corrigé v2) réponse 204 et 200 à corps vide =
  succès, sans décodage `AnyJSON` (correction 16) ; 42501 ; 22023 → `.contract` sans renvoi ;
  désactivation `{success:false}`) ; `SessionStoreTests` (ordre audit → push → signOut ; (corrigé v2) suppression de compte →
  désinscription locale via `LocalSignOut` de L1-T8, sans RPC).
- **Critère** : enregistrement et « désactivation au logout » prouvés niveau 1-2 ; STAGING (T16) avec token factice DEBUG
  `-JOLENE_PUSH_TOKEN_FACTICE` relu dans `tokens_push` (`actif` true puis false). **B9** : non. **Dépendances** : T1, lot 1 T9.

### T5 — Push : taps, premier plan, pré-prompt, centre de notifications (~1 200 lignes)

- **Fichiers** : `Jolene/Composition/NotificationCenterDelegate.swift`, `JoleneCore/Push/PushTapIntent.swift`,
  `Screens/Push/PrePromptPushScreen.swift` (textes soignant verbatim `DemandePermissionPush.tsx` l.21-27 et l.148-150 ; ids
  `push-preprompt`, `push-preprompt-activer`, `push-preprompt-plus-tard`), `MainTabView.swift` (présentation du pré-prompt — corrigé v2, au lieu de `RootView.swift`),
  `JoleneSupabase/Notifications/SupabaseNotificationsGateway.swift`, `Screens/Notifications/NotificationsScreen.swift` (ids
  `notifications-screen`, `notification-<id>`, `notification-non-lue-<id>`, `notifications-empty`, `notifications-error`,
  `notifications-retry`), `DeepLinkCoordinator` (`.notifications` natif), `JoleneUITests/DemoPushTests.swift` (taps),
  `DemoNotificationsTests.swift`. (corrigé v2) Le pré-prompt est présenté depuis `MainTabView.swift` (il n'existe qu'à
  `.ready`) et non depuis `RootView.swift` (propriété de T7) ; l'entrée « Notifications » du hub est posée par T11
  (propriétaire unique de `ProfileScreen.swift`).
- **Tests d'abord** : `PushTapIntentTests` (tap avant `.ready` différé puis rejoué avec le rôle ; tap pour un autre epoch ignoré ;
  lien externe refusé ; `lien: "/"` + type connu → repli métier) ; `PushPolicyTests` (2e lancement, marque déjà posée, refusé) ;
  `SupabaseNotificationsGatewayTests` (select borné 200, `update` puis relecture, RLS vide → liste vide sans faux succès) ;
  XCUITest : `-JOLENE_SIMULER_PUSH RAPPEL_MISSION:demo-presence-j1` → `mission-detail` ; `CANDIDATURE_ACCEPTEE` →
  `mission-detail` ; `MISSION_A_POURVOIR` sans id → `missions-list` ; `MISSION_ANNULEE_ETAB` → onglet Mes missions ;
  `CONTRAT_A_SIGNER:contrat_id` → `/contrat/<id>` (Safari ou écran lot 2) ; `LITIGE_OUVERT` → renvoi Safari (`blocking-screen`
  absent, URL vérifiée par le double d'ouverture) ; pré-prompt avec `-JOLENE_SESSION_COUNT 2`. (corrigé v2) `FACTURE_EMISE`,
  `PAIEMENT_RECU` et le lien `/soignant/parametres/notifications` visent des écrans livrés **après** T5 (T12, T13, T6) : T5
  n'asserte que la `JoleneRoute` résolue (libellé DEBUG `deeplink-route` exposé par `DeepLinkCoordinator`) ; l'écran final
  (`revenus-screen`, `revenus-paiements-declares`, `prefs-screen`) est vérifié par un cas de tap ajouté dans la tranche qui le livre.
- **Critère** : « tap ouvrant l'écran attendu pour au moins six types » (niveau 2 ici, niveau 5 en T17). **B9** : non.
  **HARD STOP** : textes verbatim. **Dépendances** : T2, T3, T4.

### T6 — Préférences de notifications (~900 lignes)

- **Fichiers** : `JoleneCore/Notifications/PreferencesNotifications.swift` (catalogue `EVENTS_SOIGNANT` porté verbatim
  `PageParametresNotifications.tsx` l.42-56 avec `regime`, filtre de régime sur `soignants.type_exercice` comme le web),
  `JoleneSupabase/Notifications/SupabasePreferencesGateway.swift`, `Screens/Notifications/PreferencesScreen.swift` (ids
  `prefs-screen`, `prefs-canal-email|push|sms|inapp`, `prefs-sms-alertes`, `prefs-evt-<TYPE>-<CANAL>`, `prefs-enregistrer`,
  `prefs-enregistre`, `prefs-error`, `prefs-retry`, + `push-etat-appareil` de T4), `DeepLinkCoordinator`
  (`.parametresNotifications`), `JoleneUITests/DemoPreferencesTests.swift`.
- **Tests d'abord** : (corrigé v2) absence de ligne `par_evenement` = actif (web l.194-197) ; décodage strict (4 booléens), canal global désactivé → cases grisées (web l.398-410), enregistrement →
  `{success:true}` → relecture ; `{error}` verbatim ; type inconnu jamais envoyé ; SMS alertes : `update` colonne puis relecture,
  échec partiel → message web l.236-238.
- **Critère** : « préférences par canal ». **B9** : non (préférence, pas un consentement juridique ; à confirmer §7 D18).
  **Dépendances** : T1, T1b, T3, (corrigé v2) T4 (`EtatNotificationsAppareilRow`).

### T7 — Inscription : compte rapide, confirmation, aiguillage onboarding (~1 200 lignes)

- **Préalable** : `PORTE_LOT0.md` 3.1 mesurée (captcha STAGING) ; 3.2 (prod) avant TestFlight externe. (corrigé v2) Si l'une
  renvoie un refus captcha, `PORTE_LOT0.md` l.57-58 impose une décision avant le lot 3 : §7 D25 (renvoi web de l'inscription).
  Indice, pas une preuve : la coquille 1.0.7 s'inscrit déjà sans jeton (`TURNSTILE_REQUIRED` faux en natif,
  `CaptchaTurnstile.tsx` l.12).
- **Fichiers** : `JoleneCore/Inscription/InscriptionRules.swift` (email regex web l.59, mot de passe ≥ 8 l.61, profession dans
  `MissionPresentation.professions`, CGU obligatoire ; `intention` → `user_metadata.inscription_progressive`
  `{type,profession,nom,cgu,cgv}`), `Inscription/OnboardingResolution.swift` (port de `registrationIntent`/`registrationDraft` de
  `mobile-native/src/account/resolveContext.ts` + `ParcoursInscription.tsx` l.39-75), `JoleneSupabase/Inscription/SupabaseInscriptionGateway.swift`
  (`signUp(email:password:data:redirectTo:captchaToken: nil)`, détection compte existant `identities` vide, confirmation 3 formats,
  `fn_demarrer_inscription` avec `exceptionsMetier`), `Screens/Inscription/InscriptionRapideScreen.swift` (texte CGU verbatim
  `InscriptionRapide.tsx` l.264-284, liens `/cgu` et `/confidentialite` en `SFSafariViewController` ; ids `login-create-account`,
  `inscription-email`, `inscription-password`, `inscription-profession`, `inscription-cgu`, `inscription-submit`,
  `inscription-confirmation-envoyee`, `inscription-erreur`, `inscription-se-connecter`),
  `ConfirmationInscriptionScreen.swift` (remplace l'écran « continuez sur jolene.app » du lot 1 ; ids
  `confirmation-inscription-screen`, `confirmation-inscription-erreur`), `OnboardingRootView.swift` (choix d'espace : soignant
  natif, établissement → web ; « Se déconnecter » ; (corrigé v2) textes verbatim `ParcoursInscription.tsx` l.97-127 :
  « Reprendre votre inscription », « Choisissez votre espace pour terminer la création de votre compte. », « Je suis soignant »,
  « Je représente un établissement », « Votre espace est momentanément indisponible. Réessayez. »), `RootView.swift` l.42-51
  (propriétaire unique au lot 3), `LoginScreen.swift`, `Demo/DemoInscriptionGateway.swift`,
  `JoleneUITests/DemoInscriptionTests.swift`.
- **Tests d'abord** : `InscriptionRulesTests` ; `OnboardingResolutionTests` (parcours prime sur l'intention ; intention sans
  `cgu:true` ignorée ; ETABLISSEMENT → renvoi) ; `SupabaseInscriptionGatewayTests` (signUp sans session → confirmation ; avec
  session → `demarrer` ; email existant ; captcha refusé → message générique + renvoi web ; `verify` `type=recovery` refusé ;
  22023/23505 restitués) ; XCUITest : création → message de confirmation ; lien démo → onboarding → complétion (T8).
- **Critère** : moitié « compte + confirmation + parcours » du critère inscription. **B9** : **oui** (consentement CGU,
  `fn_demarrer_inscription p_cgu`) → go humain. **HARD STOP** : texte CGU/confidentialité verbatim. **Dépendances** : T1, T1b, T3.

### T8 — Inscription : complétion du profil et `register-soignant` (~1 200 lignes)

- **Fichiers** : `Screens/Inscription/CompletionProfilScreen.swift` (prénom, nom, téléphone regex web l.228, date de naissance
  (l'âge est contrôlé par le serveur, `UNDERAGE` verbatim), profession figée du parcours, contrats proposés depuis
  `fn_types_exercice_autorises` ; encadré `ExerciceTypeSection` verbatim (`InscriptionSoignant.tsx` l.62-71, question l.77-81
  « Êtes-vous actuellement salarié(e) d'un établissement de santé ? » Oui/Non, et l.84, phrase entière (corrigé v2) :
  « ℹ️ Vous pourrez effectuer des missions sur Jolene en complément de votre activité salariée. Vérifiez que votre contrat de
  travail n'inclut pas de clause d'exclusivité. ») ; (corrigé v2) choix des modes par le port de `ChoixModesExercice.tsx`
  (libellés l.20-27 « Salarié (CDD compris) », « Libéral », « Modes d'exercice recherchés » et messages l.41-48 verbatim ; logique
  `preferencesModesExercice.ts` golden T2) ; (corrigé v2) RPPS : **obligatoire** pour `PROFESSIONS_RPPS_REQUIS`, optionnel pour
  les autres professions à RPPS et pour `AS`, masqué pour `PROFESSIONS_SANS_RPPS` hors `AS` (correction 20 ; listes **non**
  portées au lot 1 : port en T2), textes d'aide l.584-592 verbatim, refus final par `register-soignant` (D11) ; (corrigé v2)
  **pas de champ rayon** (le web n'en affiche pas, 30 km transmis, correction 21) ; « Je suis étudiant » → renvoi web ; ids
  `completion-*`),
  `SupabaseInscriptionGateway` (`enregistrerBrouillon` liste blanche, `finaliser` via `EdgeResponse`, `refreshSession()`),
  `Demo/DemoInscriptionGateway.swift`, `DemoInscriptionTests.swift` (suite).
- **Tests d'abord** : brouillon sans clé interdite ; chaque code `register-soignant` → message serveur verbatim ; 503
  `ACCOUNT_FINALIZATION_PENDING` → déconnexion locale + message (web l.364-367) ; succès → `start()` → `.ready` (sinon erreur,
  jamais d'espace ouvert sans profil relu) ; `LIBERAL` retiré si `fn_types_exercice_autorises` indisponible.
- **Critère** : « profil créé » ; preuve STAGING en T16. **B9** : **oui** (inscription, consentement relayé par l'audit
  `RGPD_CONSENTEMENT_DONNE` serveur l.376-387) → go humain. **HARD STOP** : avertissement d'exclusivité et libellés de mode
  d'exercice verbatim, aucune règle de mode d'exercice en dur. **Dépendances** : T7, (corrigé v2) T2 (`ModesExercice`,
  `ProfessionsRpps`).

### T9 — Profil : lecture et édition (~1 100 lignes)

- **Fichiers** : `JoleneCore/Profil/ProfilComplet.swift` (liste blanche §2.6), `Profil/ModificationProfil.swift` (seuls les
  paramètres `p_prenom, p_nom, p_telephone, p_date_naissance, p_numero_rpps (si non vérifié), p_rayon_deplacement_km,
  p_ville_recherche, p_taux_horaire_minimum, p_types_contrat, p_bio, p_annees_experience` ; jamais `p_type_exercice`,
  `p_attestation_cumul_activite`, `p_consentement_gps`, `p_disponible_urgence`, `p_profession`),
  `JoleneSupabase/Profil/SupabaseProfilGateway.swift`, `Screens/Profil/ProfilEditionScreen.swift` ((corrigé v2) nom distinct de
  `Screens/ProfileScreen.swift`, le hub ; contrats acceptés par le même composant que T8, `ModesExercice` + `fn_types_exercice_autorises`
  comme `SectionPreferences.tsx` l.64 ; ids `profil-screen`, `profil-prenom`,
  `profil-nom`, `profil-telephone`, `profil-date-naissance`, `profil-rpps`, `profil-rayon`, `profil-ville-recherche`,
  `profil-taux-min`, `profil-bio`, `profil-experience`, `profil-enregistrer`, `profil-enregistre`, `profil-erreur`,
  `profil-exercice-web`), `DeepLinkCoordinator` (`.profil` → écran ; alias `reputation`), `JoleneUITests/DemoProfilTests.swift`.
- **Tests d'abord** : `ProfilCompletTests` (vecteurs `valider-profil-soignant.json`, `{error}` → erreur, `Mirror` sans clé
  interdite) ; `SupabaseProfilGatewayTests` (seuls les paramètres autorisés partent ; `{error}` prénom vide verbatim ; relecture) ;
  audit `DONNEES_PERSO_CONSULTATION` une fois par ouverture, jamais bloquant ; XCUITest édition → relecture.
- **Critère** : « profil ». **B9** : non. **HARD STOP** : type d'exercice/cumul (L1222-5) non portés, renvoi web libellé.
  **Dépendances** : T1, T2, T3.

### T10 — Avatar et localisation (~900 lignes)

- **Fichiers** : `Jolene/Composition/AvatarPicker.swift` (PHPicker + caméra, conversion HEIC → JPEG systématique, 256 px, qualité
  0,8 ; (corrigé v2) la limite web de 2 Mo porte sur le **fichier d'origine** (l.122-125) et refuserait une grande partie des
  photos HEIC d'iPhone : le natif l'applique au JPEG envoyé, réduction par `CGImageSourceCreateThumbnailAtIndex` sans décoder
  l'original en pleine taille), `JoleneSupabase/Profil/SupabaseAvatarStorage.swift`
  (`<uid>/avatar-<epochms>.jpg`, `contentType image/jpeg`, `upsert:false`, `createSignedURL(path:expiresIn: 157_680_000)`),
  reçu `ReceiptJournal` (lot 1), (corrigé v2) `Appareil.location` du lot 2 **seulement** (pas de `OneShotLocation.swift` : si
  L2-T1 n'est pas sur `main`, `profil-localiser` est absent et la localisation glisse dans une PR T10b après L2-T1),
  `JoleneSupabase/Geo/ApiAdresseGeocodage.swift`
  (`https://api-adresse.data.gouv.fr/reverse/?lon=&lat=`, aucun identifiant envoyé), `ProfilScreen` (`profil-avatar`,
  `profil-avatar-changer`, `profil-localiser`), `DemoProfilTests` (suite).
- **Tests d'abord** : conversion HEIC (fixture HEIC dans les tests) → JPEG valide ; 403 Storage → reçu `refused`, aucun
  `p_avatar_url` envoyé ; arrêt entre upload et RPC → relecture `avatar_url` au retour, pas de second upload automatique ;
  localisation refusée → message web l.637-641 ; géocodage en échec → « Position récupérée. ».
- **Critère** : « avatar, adresse ». **B9** : non. **Dépendances** : T9, lot 1 T7, (corrigé v2) L2-T1 pour la localisation.

### T11 — Compte : mot de passe, thème, export RGPD, hub (~1 000 lignes)

- **Fichiers** : `JoleneCore/Compte/ForceMotDePasse.swift` (port de `calculerForce`, `ChangementMotDePasse.tsx` l.198-208),
  `Compte/ExportRGPD.swift` (aplatissement CSV identique au web l.50-63, nom `mes-donnees-jolene-AAAA-MM-JJ.json|csv`),
  `JoleneSupabase/Compte/SupabaseMotDePasseGateway.swift` (ancien vérifié par `signIn` sur le même email ; si l'id renvoyé diffère
  → refus ; `update(user: UserAttributes(password:))` ; erreur « nonce requis » → refus verrouillé « Utilisez « Mot de passe
  oublié ? » » (§7 D13)), `SupabaseExportGateway.swift`, `Composition/ThemePreference.swift` (`preferredColorScheme`, posé à la
  racine dans `JoleneApp.swift` — une ligne, corrigé v2),
  (corrigé v2) `Screens/ProfileScreen.swift` **étendu** (hub réellement monté, correction 18 ; T11 en est le seul propriétaire au
  lot 3) — sections : Mon profil (`.profil`), Notifications (`.notifications`) et Préférences (`.parametresNotifications`),
  Paiements (si libéral/mixte, règle web `MonCompteSoignant.tsx` l.45-48 : Stripe `.stripeConnect`), Coordonnées bancaires,
  Sécurité (lot 1), Thème, Export, Aide & légal en Safari (l.126-136), Suppression (`SuppressionCompteSection` de L1-T8,
  conservée en dernière section), Déconnexion, `profile-version`, `profile-list` ; chaque entrée passe par `JoleneRoute` →
  `DeepLinkCoordinator`, donc renvoi `.safari(canonique)` tant que la tranche de l'écran n'a pas basculé sa ligne ;
  `MotDePasseScreen.swift` (ids `compte-mdp-ancien`, `compte-mdp-nouveau`, `compte-mdp-confirmation`, `compte-mdp-critere-<cle>`,
  `compte-mdp-submit`, `compte-mdp-succes`, `compte-mdp-erreur`), `JoleneUITests/DemoCompteLot3Tests.swift` ; **pas** de
  `MonCompteScreen.swift` ni de modification de `MainTabView.swift`.
- **Tests d'abord** : `ForceMotDePasseTests` (5 critères, 12 caractères) ; ancien incorrect → « Ancien mot de passe incorrect. »
  (web l.57-59) ; succès → audit best-effort ; `SessionController` ne change pas d'epoch sur `.session(même userId)` (test) ;
  export `{error}` → aucun fichier ; fichier supprimé après partage ; thème appliqué et persistant.
- **Critère** : « mot de passe, thème, export RGPD ». **B9** : non. **HARD STOP** : textes RGPD verbatim. **Dépendances** : T1,
  T1b, (corrigé v2) T3 (routes `.monCompte`/`.notifications`/`.stripeConnect` des entrées du hub), lot 1 T8-T9.

### T12 — Revenus en lecture (~1 300 lignes)

- **Fichiers** : `JoleneCore/Revenus/RevenusModel.swift`, `MontantMission.swift` et `EtatPaiement.swift` (T2),
  `JoleneSupabase/Revenus/SupabaseRevenusGateway.swift` (`fn_mes_revenus_connect`, `fn_mes_paiements_escrow`, missions
  `TERMINEE` paginées 50 avec **exactement** les colonnes de `MesGains.tsx` l.95 (corrigé v2 : ni `rist_plafond_applique`, ni
  `taux_rist_plafonne`, ni `soignant_assigne_id` — correction 19 ; embed `presences(...)` conservé) sans embed `etablissements`, dernière déclaration
  `paiements_soignant`, noms via `fn_etablissements_safe`), `Screens/Revenus/RevenusScreen.swift` (ids `revenus-screen`,
  `revenus-kpi-mois`, `revenus-kpi-total`, `revenus-kpi-attente`, `revenus-escrow-<missionId>`, `revenus-mission-<id>`,
  `revenus-mission-montant-<id>`, `revenus-mission-etat-<id>`, `revenus-factures-web`, `revenus-bulletins-web`, `revenus-avances-web`,
  `revenus-error`, `revenus-retry`, `revenus-load-more`), `MainTabView.swift` l.47-53, `DeepLinkCoordinator` (`.revenus` + sections),
  `JoleneUITests/DemoRevenusTests.swift`.
- **Tests d'abord** : montants = vecteurs golden (libellés « Honoraires bruts », « Net salarié estimé* », « Rémunération brute
  indicative » verbatim) ; (corrigé v2) test-garde : la requête n'envoie aucune colonne Rist (`select` comparé à la chaîne de
  `MesGains.tsx` l.95) ; `fn_mes_revenus_connect` incomplet → section en erreur ; les 7 états escrow et leurs libellés ;
  audit consultation une fois ; (corrigé v2) tap push `FACTURE_EMISE` → `revenus-screen` (cas reporté de T5).
- **Critère** : « revenus en lecture ». **B9** : **oui** (paiements/escrow) → go humain. **HARD STOP** : libellés escrow et
  note « net estimé » verbatim. **Dépendances** : T1, T1b, T2, T3.

### T13 — Paiements déclarés : confirmer, contester (~800 lignes)

- **Fichiers** : `JoleneSupabase/Revenus/SupabasePaiementsGateway.swift` (liste `DECLARE` + missions, présences, créneaux comme
  `BandeauPaiementDeclare.tsx` l.95-152 ; RPC + relectures), `Screens/Revenus/PaiementsDeclaresSection.swift` (ids
  `revenus-paiements-declares`, `paiement-declare-<id>`, `paiement-confirmer-<id>`, `paiement-contester-<id>`, `paiement-motif`,
  `paiement-contestation-envoyer`, `paiement-confirme`, `paiement-conteste`, `paiement-erreur` ; libellés verbatim web
  l.47-66, l.69-77), `Demo/DemoPaiementsGateway.swift`, `JoleneUITests/DemoPaiementsTests.swift`.
- **Verrou** (« un gap connu reste verrouillé ») : tant que B3 n'est pas sur `main`, « Contester » est remplacé par un message
  explicite + référence `CONTRATS_RPC_SOIGNANT.md#fn_contester_paiement_soignant` ; levé dans la PR qui suit B3. (corrigé v2) Le
  message **ne renvoie pas vers jolene.app** : la contestation y échoue aussi (correction 3) ; texte proposé (nouveau, non
  juridique, à faire relire) : « La contestation d'un paiement est momentanément indisponible. Contactez Jolene depuis Mon compte
  › Contacter Jolene. », avec renvoi vers le contact (web `MonCompteSoignant.tsx` l.131, `ModalContacterJolene`).
- **Tests d'abord** : confirmer → relecture `CONFIRME` ; `{error:'Paiement déjà confirmé'}` verbatim ; contester sans motif
  impossible ; `{success, litige_id}` sans relecture `CONTESTE` → erreur (jamais de succès) ; double tap impossible ; (corrigé v2)
  23505 (litige déjà ouvert, si B3 ne le traite pas) → message serveur ou générique, jamais de succès ; tap push `PAIEMENT_RECU`
  → `revenus-paiements-declares` (cas reporté de T5).
- **Critère** : « confirmation et contestation de paiement déclaré ». **B9** : **oui** → go humain. **Dépendances** : T12, B3.

### T14a — Stripe Connect (~800 lignes) (corrigé v2 : T14 scindée, deux domaines B9 et deux écrans indépendants)

- **Fichiers** : `JoleneSupabase/Revenus/SupabaseStripeConnectGateway.swift` (`functions.invoke("stripe-connect-status")` en POST,
  `?force=true` par `FunctionInvokeOptions(query:)` au retour et sur « Actualiser » (correction 17),
  `invoke("stripe-connect-onboard", options: .init(headers: ["Origin": "https://jolene.app"]))`), lecture préalable
  `soignants.est_compte_test, type_exercice, statut_liberal` (web l.94-111), `Jolene/Composition/ExternalFlowPresenter.swift`,
  `Screens/Revenus/StripeConnectScreen.swift` (statuts `NON_DEMANDE`, `EN_COURS`, `COMPLET`, `SUSPENDU`, `SUPPRIME`, `REJETE`,
  compte test, non éligible ; textes verbatim `PageStripeConnect.tsx` l.300-520 et `SectionPaiements.tsx` l.16-139 ; ids
  `stripe-screen`, `stripe-statut-<STATUT>`, `stripe-onboarding`, `stripe-actualiser`, `stripe-compte-test`, `stripe-non-eligible`,
  `stripe-erreur`), `DeepLinkCoordinator` (`.stripeConnect` natif, ferme le flux externe et relit), `AppContainer.swift` (une
  ligne : `ExternalFlowPort`), `JoleneUITests/DemoStripeTests.swift`.
- **Tests d'abord** : en-tête Origin présent ; 403 `ORIGINE_NON_AUTORISEE` → erreur de contrat ; `TEST_ACCOUNT_PAYMENT_DISABLED`
  → écran compte test ; `est_compte_test = true` lu → écran compte test **sans** appel d'edge ; `COMPLET` sans les trois drapeaux →
  `EN_COURS` ; statut hors des six valeurs → erreur ; toute issue du flux → relecture avec `force=true`.
- **Critère** : « onboarding Connect hosted… retour `/soignant/stripe-connect` ». **B9** : **oui** (Stripe) → go humain.
  **HARD STOP** : textes verbatim (« Aucun frais pour le soignant », etc.). **Dépendances** : T1, T1b, T3.

### T14b — IBAN (~550 lignes) (corrigé v2)

- **Fichiers** : `JoleneCore/Revenus/IbanRules.swift` (mod 97, port `SectionPaiements.tsx` l.212-225), `SupabaseIbanGateway.swift`,
  `Screens/Revenus/IbanScreen.swift` (clavier ASCII, sans autocorrection ni suggestion, champ vidé après envoi ; textes verbatim
  l.274-376 ; ids `iban-screen`, `iban-actuel`, `iban-input`, `iban-titulaire`, `iban-valide`, `iban-invalide`, `iban-enregistrer`,
  `iban-erreur`, `iban-rib-requis` → documents lot 2 ou web), `DeepLinkCoordinator` (une ligne), `JoleneUITests/DemoIbanTests.swift`.
- **Tests d'abord** : `success:false` sans `error` → message du code (sept textes nouveaux, correction 4), jamais « IBAN
  enregistré » ; `TITULAIRE_NON_CONCORDANT` / `RIB_VERIFIE_REQUIS` → `error` serveur verbatim ; succès → `consulter` relu
  (`iban_verifie == true` exigé) ; IBAN jamais journalisé ni persisté.
- **Critère** : « IBAN ». **B9** : **oui** (données bancaires) → go humain. **HARD STOP** : aucun texte juridique ; messages des
  sept codes sans `error` relus par Gabrielle (§6.7). **Dépendances** : T1, T1b, T3.

### T15 — Sentry Cocoa (~600 lignes)

- **Fichiers** : `project.yml` (paquet `Sentry` `https://github.com/getsentry/sentry-cocoa`, `exactVersion` relevée à l'ouverture
  de la tranche, compatible Xcode 16.4 local et 26.4.1 CI), `Jolene/Composition/CrashReporting.swift` (`SentrySDK.start` :
  `dsn` lu dans `Info.plist` `JoleneSentryDSN` ← xcconfig, vide → désactivé ; `environment` = `JoleneEnvironment.mode` ;
  `releaseName` `app.jolene@2.0.0+25` ((corrigé v2) construit depuis `CFBundleShortVersionString` + `CFBundleVersion`, jamais
  codé en dur) ; `sendDefaultPii = false`, `attachScreenshot = false`, `attachViewHierarchy = false`,
  `enableNetworkBreadcrumbs = false`, `enableCaptureFailedRequests = false`, `tracesSampleRate = 0`, (corrigé v2)
  `enableAutoSessionTracking = true` (défaut, conservé explicitement : le lot 4 mesure le crash-free sessions ≥ 99,5 %),
  `enableAppHangTracking = true`, `beforeSend` /
  `beforeBreadcrumb` → `CrashScrubber`), `JoleneCore/Crash/CrashScrubber.swift`, `JoleneApp.swift` (démarrage avant le conteneur,
  jamais en démo), `SessionStore` (utilisateur `id` sur `.ready`, `nil` au logout), `PrivacyInfo.xcprivacy` ((corrigé v2) **déjà**
  déclarés au lot 0 : `CrashData` l.199, `PerformanceData` l.209, `OtherDiagnosticData` l.222, UserDefaults `CA92.1` l.248-251 —
  T15 vérifie seulement que le manifeste embarqué par le paquet Sentry est agrégé), argument DEBUG `-JOLENE_SENTRY_CRASH_TEST`
  (`SentrySDK.crash()` une fois), `docs/mobile-swift/SENTRY_IOS.md`.
- **Tests d'abord** : `CrashScrubberTests` (URLs avec `token_hash`, `code`, `access_token`, IBAN, email → masqués) ;
  `CrashReportingTests` (démo / DSN vide → jamais démarré ; sentinelle réseau démo toujours à 0).
- **Critère** : « Sentry reçoit un crash de test taggé release 2.0.0 (25) » (lecture en T17). **B9** : non. **Dépendances** : T4
  (`JoleneApp.swift`, `AppContainer.swift`).

### T16 — Preuves STAGING lot 3 + fixture D5 (~700 lignes Swift + scripts) (corrigé v2 : « D4 » est le nom de la fixture du lot 2)

- **Fixture D5** (`scripts/mobile/staging-lot3-fixture.mjs` + `scripts/ci/lot3-fixture-sql.mjs`, modèle D3, catalogue md5
  propre, transaction `SET LOCAL request.jwt.claim.role='service_role'`) : soignant D5 (cohorte test ; (corrigé v2) soignant **et**
  établissement de la même cohorte, `app_metadata {est_compte_test:true, is_test_playwright:true}` comme D3, sinon
  `fn_etablissements_safe` masque le nom) avec mission `TERMINEE` ((corrigé v2) `type_contrat_applique = 'SALARIE'` : en LIBERAL,
  `trg_paiement_liberal_facture` exige une `factures_honoraires` au montant exact, migration `20261001122318` l.123-140 ; aucune
  ligne `paiements_escrow`, sinon `trg_bloquer_paiement_manuel_escrow` refuse la déclaration, l.62588) +
  ligne `paiements_soignant` `DECLARE` (`methode VIREMENT`, `montant_net > 0`, CHECK l.70908-70910) ; RIB `VERIFIE` + pièce
  d'identité `VERIFIE` + `identite_verifiee`, `coherence_identite='COHERENT'`, `resultat_ia.iban_preuve_hash_v1 =
  sha256('FR7630006000011234567890189:' || doc_id)` ((corrigé v2) et toutes les conditions de la correction 4 : `verdict_serveur`,
  `iban_valide`, `iban_last4 = '0189'`, `coherence_nom`, noms extraits = prénom/nom D5 sur les deux pièces, `s3_cle` non nulle) ;
  notifications démo ; **cohorte non-test D5-R** ((corrigé v2) créée **sans** changer durablement `inscriptions_publiques_actives` :
  dans la transaction backend, `UPDATE … SET valeur = 1`, INSERT des acteurs avec `est_compte_test = false` explicite, retour à
  `0` avant `COMMIT`, modèle `finance-cohortes-rollback.sql` l.18-62 mais validé ; assertion finale `valeur = 0` ; §7 D17) :
  soignant LIBERAL + établissement + mission pour push et Stripe.
  Triggers relus en live avant d'écrire le SQL (garde-fou 9.0 n°2).
- **XCUITest `StagingLot3Tests`** : token factice upsert → `tokens_push` relu (`plateforme IOS`, `actif`) → logout → `actif=false`
  relu ; préférences enregistrées puis relues ; profil modifié relu ; avatar : objet Storage + `avatar_url` relus ; export non vide ;
  paiement `DECLARE` confirmé → `CONFIRME` relu ; contestation (après B3) → `CONTESTE` + `litiges` + notification relus ; IBAN →
  `iban_last4` relu ; Stripe compte test → `stripe-compte-test` (et D5-R : URL d'onboarding obtenue) ; inscription :
  `native-insc-<uuid>@example.invalid` → signUp app → `token_hash` lu en SQL (`auth.users.confirmation_token` ou
  `auth.one_time_tokens.token_hash`, à vérifier sur STAGING) → relance `-JOLENE_OPEN_URL …/inscription/confirmer?token_hash=…&type=signup`
  (valeur masquée par `policy.redact` et `::add-mask::`) → parcours → complétion → ligne `soignants` relue → nettoyage.
  (corrigé v2) Avant la branche inscription : lire `mailer_autoconfirm` et `site_url` STAGING (Management API
  `GET /v1/projects/{ref}/config/auth`) ; autoconfirm vrai → `signUp` ouvre la session, la branche « lien » est consignée non
  exercée ; une seule inscription par run (rate-limit e-mail GoTrue et `register-soignant` 5/10 min). (corrigé v2) Émission push
  pour T17 : script de recette appelant `send-push` STAGING en **service_role** (destinataire D5-R, `type_evenement` ∈ six types
  routés natifs, `mission_id` D5-R, `idempotency_key` unique ; `send-push/index.ts` l.297-336), jamais depuis la CI simulateur.
- **Workflow** : (corrigé v2, §7 D24) workflow jumeau `.github/workflows/ios-swift-lot3-staging.yml` (mêmes `policy.mjs`/`admit.mjs`
  non modifiés, groupe `jolene-supabase-staging-writes`, environnement protégé comme L2, dispatch sur `main`), `ios-swift-ci.yml`
  l.322 (+ `-skip-testing:JoleneUITests/StagingLot3Tests`).
- **Critère** : niveau 3 de tous les critères. **B9** : **oui** (secrets STAGING, suppression de comptes jetables, (corrigé v2)
  bascule transactionnelle de `inscriptions_publiques_actives`) → go humain au dispatch. **Dépendances** : T4-T14b mergés, B3.

### T17 — Clôture (~100 lignes, docs)

- **Fichiers** : `PARITE_SOIGNANT.md` (lignes lot 3 statuées avec preuve), `RECETTE_DEVICE_LOT3.md` (push sandbox reçu et tap pour
  6 types sur iPhone avec build Debug STAGING, cohorte D5-R, (corrigé v2) push émis par le script service_role de T16 ; UL
  d'inscription depuis Mail ; retour Stripe TEST **sur iOS ≥ 17.4** (correction 6), mécanisme consigné (rappel `.https` associé) ;
  crash Sentry lu ; thème sombre ; HEIC réel ; `tokens_push.actif` relu après chaque envoi), `PORTE_LOT3.md`,
  `DemoWorldTests.portsEnAttenteLot3` vide.
- **Critère** : tous ; TestFlight externe (Gabrielle). **Dépendances** : tout.

## 4. Ordre d'exécution et parallélisme

(corrigé v2) La v1 plaçait T6, T9, T11 et T12 dans la même vague que T3 alors qu'elles en dépendent (routes de T3) : ordre corrigé.

| Vague | Tranches | Condition d'entrée |
|---|---|---|
| 0 | **T0**, **B3** (backend) | aucune — démarrables tout de suite |
| 1 | **T1**, **T1b**, **T2** | lot 1 T1, T1b, T2 sur `main` (+ L1-T0 pour T0 lot 3) |
| 2 | **T3** (lot 1 T10), **T4** (lot 1 T9, T8) | T1 |
| 3 | **T5** (T2, T3, T4), **T6** (T1b, T3, T4), **T7** (T1b, T3 + `PORTE_LOT0` 3.1), **T9** (T2, T3), **T11** (T1b, T3, lot 1 T8-T9), **T12** (T1b, T2, T3), **T14a** (T1b, T3), **T14b** (T1b, T3), **T15** (T4) | T3 et T4 sur `main` |
| 4 | **T8** (T2, T7), **T10** (T9, lot 1 T7 ; localisation : L2-T1), **T13** (T12 + B3) | — |
| 5 | **T16** (go Gabrielle), puis **T17** (appareil iOS ≥ 17.4, clé APNs, cohorte D5-R) | — |

Fichiers chauds et propriétaire unique : `Ports/Ports.swift` (T1 seul) ; `JoleneRoute.swift`, `LinkRouter.swift`,
`DeepLinkIntent.swift` (T3 seul ; les tranches d'écran ne changent qu'**une ligne** de `DeepLinkCoordinator.swift` — en vague 3,
neuf tranches touchent ce fichier : merge sériel, rebase trivial) ; `export-golden-vectors.mjs` (T2 seul) ;
(corrigé v2) `ProfileScreen.swift` (T11 seul) ; `RootView.swift` (T7 seul ; le pré-prompt de T5 vit dans `MainTabView`) ;
`MainTabView.swift` (T5 surcouche du pré-prompt, puis T12 onglet Revenus) ; `JoleneApp.swift` (T4, puis T11 thème et T15 Sentry,
une ligne chacun) ; `AppContainer.swift` (T4, puis T14a `ExternalFlowPort` et T15 `CrashReportingPort`, une ligne chacun) ;
`SessionStore.swift` (T4 puis T15) ; `DemoWorld.swift`, `SupabaseGateways.swift`, `export-demo-fixtures.mjs`,
`rpc-contracts.json` (une ligne ou une section par tranche, rebase trivial) ; `project.pbxproj` regénéré par `xcodegen generate`
après chaque rebase. (corrigé v2) La v1 affirmait que le lot 3 « n'édite aucun fichier du lot 2 » : faux — voir la liste des
conflits inter-lots sous « Dépendances » (Ports, liens, `ProfileScreen`, golden, contrats, CI). Les deux lots avancent en
parallèle, mais chaque rebase sur un merge de l'autre lot relance `swift test` des deux packages et l'exporter golden.

## 5. Risques et parades

| Risque | Parade |
|---|---|
| Clé APNs encore sous `FPQ78HDF4Y` : toute absence de push sera attribuée à tort au code | T4-T5 prouvés aux niveaux 1-3 ; aucune conclusion « push cassé » avant rotation + sonde témoin + envoi sandbox (`PORTE_LOT0` 4.1-4.2) |
| Token sandbox envoyé à l'hôte production → désactivé en silence | `APNS_ENVIRONMENT = sandbox` STAGING, build Debug pour la recette, relecture `tokens_push.actif` après chaque envoi de recette |
| Cohorte test : `send-push` et Stripe sautent tout compte test | cohorte non-test D5-R dédiée, créée par bascule transactionnelle (§7 D17, corrigé v2) ; sinon preuves 4-5 consignées « non mesurables », jamais simulées |
| (corrigé v2) Secrets APNs absents de STAGING : `send-push` désactive alors tout token `IOS` non-test (l.714-730) | mesure avant T17 (§6.1) ; relecture `tokens_push.actif` après chaque envoi de recette |
| (corrigé v2) `Site URL` STAGING différent de `https://jolene.app` : un modèle `{{ .SiteURL }}/inscription/confirmer…` n'ouvre pas l'app (AASA servie par jolene.app seulement) | modèle STAGING avec l'hôte `https://jolene.app` écrit en dur, ou `Site URL` vérifié (§6.4) ; e2e STAGING qui lisent ce lien recensés avant le changement |
| (corrigé v2) Bounces et quota e-mail GoTrue STAGING (`@example.invalid`, lot 0 3.1, reset lot 1, inscription lot 3) | une inscription par run ; SMTP STAGING vérifié (fournisseur, suppression des bounces) avant T16 |
| (corrigé v2) `api-adresse.data.gouv.fr` : service tiers hors Supabase (coordonnées envoyées), pérennité à vérifier à l'ouverture de T10 (migration annoncée vers la Géoplateforme IGN, non vérifiée ici) | géocodage best-effort, aucun identifiant envoyé, échec → « Position récupérée. » ; App Privacy au lot 6 |
| Faux succès (IBAN web, préférences, notifications supprimées) | règle « succès = drapeau serveur + relecture » testée par gateway ; « Supprimer les lues » non porté |
| `fn_contester_paiement_soignant` en échec 23514 et sans idempotence | B3 avant ouverture du bouton ; verrou explicite jusque-là ; bouton désactivé pendant l'appel |
| `stripe-connect-onboard` 403 sans Origin | en-tête explicite + test ; fiche de contrat |
| Retour Stripe non déclenché par SFSafariViewController (redirection, pas un tap) | ASWebAuthenticationSession `.https` dès iOS 17.4 ; dessous, relecture du statut (`force=true`) à la fermeture : la preuve est le statut serveur, pas le lien ; (corrigé v2) sur STAGING, une `return_url` non interceptée charge le site **de production** jolene.app dans la feuille (sans effet, mais trompeur) |
| Lien de confirmation d'inscription ouvert dans Safari (modèle `ConfirmationURL`) ou verifier écrasé | modèle `token_hash` (§6.4) ; repli « Se connecter » valable car `/verify` a confirmé l'email ; jamais `supabase.auth.handle(url)` |
| Captcha GoTrue activé un jour | `PORTE_LOT0` 3.1/3.2 avant T7/TestFlight ; erreur captcha → message générique + renvoi web d'inscription |
| `register-soignant` limite 5 essais / 10 min / IP | messages verbatim ; une inscription par run STAGING |
| Exceptions métier réduites au message générique par `SupabaseErrorMapping` | `exceptionsMetier` par appel (22023, 23505, P0002) lues avant le mapping, testées |
| `fn_modifier_mon_profil` ne peut pas vider un champ (`COALESCE`) | l'UI n'offre pas d'effacement ; documenté dans la fiche de contrat |
| Données sensibles du profil complet | décodeur en liste blanche + test `Mirror` ; fixtures démo contrôlées |
| Vérification de l'ancien mot de passe par `signIn` émet `.signedIn` | test : même userId → pas d'epoch++ ni de rechargement ; id différent → refus |
| « Secure password change » activé (nonce) | refus verrouillé renvoyant vers « Mot de passe oublié ? » (lot 1 T10) |
| PHPicker HEIC, WebP non encodable par ImageIO en iOS 16 | JPEG systématique ; MIME autorisé par le bucket (`20260713222000` l.1342) |
| XCUITest : feuilles système (notifications, localisation, photos) | ports injectés en démo, aucun prompt réel ; gate `skipped = 0` intacte |
| Temps du job UI (≈ 10 classes lot 1 + ~6 lot 2 + 12 lot 3 × 3 formats) | (corrigé v2) étape bornée à 30 min (`ios-swift-ci.yml` l.300) : si un format dépasse 20 min (seuil du lot 2) : tranche CI de découpage par `-only-testing:JoleneUITests/Demo<X>Tests` (décision 17 du lot 1) |
| Conflits `project.pbxproj` | regénération XcodeGen après rebase ; CI de vérification « pbxproj à jour » |
| Sentry : fuite de jetons dans les breadcrumbs | breadcrumbs réseau coupés, `CrashScrubber` testé, `sendDefaultPii = false`, pas de capture d'écran |
| Sentry et App Privacy | `PrivacyInfo.xcprivacy` mis à jour en T15 ; App Privacy App Store Connect au lot 6 |
| Règle de montant côté client (`corrigerAncienPlafondImpossible`, `missionFinanceDisplay.ts` l.41-61) contraire à « jamais recalculé » | port golden à l'identique du web (même chiffre sur les deux surfaces) + candidate RPC consignée (§7 D5) |
| `pol_paie_soig_update` permet au soignant un UPDATE direct de `paiements_soignant` (l.79423) | (corrigé v2) borné par `trg_protect_paiement_soignant` (`fn_protect_paiement_soignant` l.50543 : montant, méthode, mission, établissement figés ; statut seulement vers `CONFIRME`/`CONTESTE`) mais ce chemin contourne les effets de la RPC (facture `PAYEE`, litige) ; le natif n'écrit que par RPC ; signalé à Gabrielle (RLS, B9) sans correction dans ce lot |
| TestFlight = backend production | TestFlight externe seulement après porte lot 3 signée et go explicite (données réelles) |

## 6. Ce qui exige Gabrielle

1. **APNs** : créer une clé APNs sous `GDU5AA28M9`, tourner `APNS_KEY_P8`, `APNS_KEY_ID`, `APNS_TEAM_ID` (STAGING et prod),
   positionner `APNS_ENVIRONMENT = sandbox` sur STAGING (`production` en prod), relancer `apns-probe.yml` en mode témoin.
   (corrigé v2) Constater d'abord que ces secrets **existent** sur STAGING (la sonde ne vise que la prod, `apns-probe.yml` l.30) ;
   `APNS_BUNDLE_ID` absent = `app.jolene` (`apns-client.ts` l.97), identique au bundle natif (`Base.xcconfig` l.2).
2. **iPhone physique** : appareil enregistré dans le compte développeur, profil de **développement** `app.jolene` (Push +
   Associated Domains), build Debug « Jolene-Staging » installé par Xcode ; recette `RECETTE_DEVICE_LOT3.md`. (corrigé v2) iOS
   **≥ 17.4** (critère Stripe, correction 6) ; clé publishable STAGING fournie dans un xcconfig local non versionné
   (`Staging.xcconfig` l.2), signature manuelle (`CODE_SIGN_STYLE = Manual`, `Base.xcconfig` l.10-11).
3. **Cohorte STAGING non-test** : (corrigé v2) **ne pas** passer `inscriptions_publiques_actives` à 1 de façon durable (casse
   `finance-cohortes-rollback.sql` / `verify-finance-fixture-isolation.mjs` et reclasse toutes les inscriptions STAGING) ; go pour
   la bascule **transactionnelle** de la fixture D5-R (1 → INSERT → 0 avant COMMIT, §7 D17) ; confirmer `STRIPE_SECRET_KEY`
   STAGING en `sk_test_`.
4. **Dashboard Auth (STAGING puis prod, B9 auth)** : modèle « Confirm signup » au format
   `{{ .SiteURL }}/inscription/confirmer?token_hash={{ .TokenHash }}&type=signup` ; `https://jolene.app/inscription/confirmer` dans
   Redirect URLs ; mesures `PORTE_LOT0` 3.1 (STAGING, dispatch) et 3.2 (prod, manuelle) ; réglage « secure password change ».
   (corrigé v2) Sur STAGING, `{{ .SiteURL }}` doit valoir `https://jolene.app` (seul domaine de l'AASA) ou l'hôte est écrit en
   dur dans le modèle. **Reformulation du critère du plan à valider** : avec ce modèle, « PKCE échangé » devient « lien
   `token_hash` vérifié dans l'app (`verifyOTP`) » ; l'échange `code` reste couvert aux niveaux 1-2 seulement (le modèle
   `{{ .ConfirmationURL }}` passe par `supabase.co/auth/v1/verify` puis redirige, ce qui n'ouvre pas l'app de façon fiable).
5. **Sentry** : créer le projet `jolene-ios` (org `jolene-z6`), fournir le DSN, lire l'événement de crash de test ; jeton dSYM
   local si la symbolication est voulue.
6. **Go B9** : B3 (et choix d'option : suppression de la notification redondante recommandée, ou élargissement du CHECK) ; T7,
   T8 (consentement) ; T12, T13, T14a, T14b (paiements, Stripe, IBAN — corrigé v2) ; dispatch T16 (secrets STAGING, suppression
   des comptes jetables, bascule transactionnelle de cohorte) ; signalement RLS `pol_paie_soig_update`.
7. **HARD STOP (validation de textes)** : CGU/confidentialité de l'inscription, avertissement d'exclusivité, libellés de mode
   d'exercice, libellés escrow et note « net estimé », textes Stripe, RGPD (export), contestation de paiement ; tous verbatim web
   tant que non validés. (corrigé v2) Textes **sans équivalent web**, à relire (non juridiques) : messages des sept `error_code`
   IBAN sans `error` (T14b), message du verrou de contestation (T13).
8. **Stripe TEST sur appareil** : parcourir l'onboarding hébergé avec les valeurs de test publiées par Stripe (saisie par
   Gabrielle), constater le retour et le statut relu.
9. **Boîte mail** : une adresse qu'elle contrôle pour l'inscription STAGING depuis Mail (UL réel).
10. **TestFlight externe** : groupe de soignants pilotes, informations de test, Beta App Review ; décision explicite car le build
    parle à la production.
11. (corrigé v2) **Captcha** : si `PORTE_LOT0` 3.1 ou 3.2 renvoie un refus captcha, trancher §7 D25 avant d'ouvrir T7.

## 7. Décisions (recommandation ferme pour chacune)

1. **Prompt de notification** : jamais au login ; pré-prompt natif à partir du 2e lancement, masqué si déjà accordé/refusé, plus
   l'activation depuis Préférences. **Recommandé : parité web (`DemandePermissionPush.tsx`, `session-count.ts`).**
2. **Logout** : RPC de désactivation puis `unregisterForRemoteNotifications()` **toujours**, oubli du token ; déconnexion subie :
   désinscription locale seule. **Recommandé : parité web (`pushDeviceToken.ts` l.108-120).**
3. **Délai de désactivation** : 2,5 s (web) au lieu de 15 s (décision 14 du lot 1), pour ne jamais bloquer une déconnexion hors
   ligne. **Recommandé : 2,5 s, seule exception consignée.** (corrigé v2) L'audit `DECONNEXION` de L1-T9 précède le push et garde
   sa borne lot 1 : hors ligne, la déconnexion peut donc attendre audit + 2,5 s. Recommandé en plus : lancer audit et
   désactivation **en parallèle** (deux appels JWT indépendants, `async let`), puis `controller.signOut()` dès que les deux ont
   rendu ou expiré — à faire accepter par la revue de T4 comme amendement local de L1-T9.
4. **Revenus au lot 3** : totaux serveur (`fn_mes_revenus_connect`), paiements rapides, missions terminées, paiements déclarés,
   Stripe, IBAN natifs ; factures, bulletins, avances en renvoi web ; aucun KPI calculé côté client. **Recommandé.**
5. **Montant par mission** : porter `montantFinanceAfficheMission` (y compris la correction du plafond Rist historique) avec
   vecteurs golden, plutôt qu'afficher un champ brut divergent du web ; consigner la règle comme candidate RPC. **Recommandé.**
   (corrigé v2) **et** lire exactement les colonnes de `MesGains.tsx` l.95 (sans colonnes Rist) : la correction reste alors
   inactive comme sur le web (correction 19), aucun montant n'est recalculé côté client et PRINCIPES §3 n'a pas à être amendé.
6. **Stripe sans Origin** : envoyer `Origin: https://jolene.app` depuis l'app (aucune modification backend) plutôt que modifier
   `stripe-connect-onboard` (B9). **Recommandé : en-tête client.**
7. **Présentation des flux hébergés** : ASWebAuthenticationSession éphémère avec rappel `.https` dès iOS 17.4,
   SFSafariViewController en dessous ; dans tous les cas succès = statut relu (`force=true`). **Recommandé.** (corrigé v2) Le
   critère « retour dans l'app par Universal Link » est prouvé sur iOS ≥ 17.4 uniquement (correction 6) ; sous 17.4 la recette
   consigne « retour par fermeture de la feuille + statut relu ».
8. **PSC** : non construit au lot 3 (credentials ANS absents, pas d'environnement de test, rappel https iOS 17.4) ; route
   `/auth/psc/callback` laissée à Safari ; tranche ouverte le jour J. **Recommandé.**
9. **Onboarding** : pas d'exploration des missions avant le profil complet (écart assumé avec `ParcoursInscription.tsx`
   l.144-145) ; écran de complétion bloquant avec « Se déconnecter ». **Recommandé.**
10. **Formats du lien de confirmation** : accepter `token_hash`, implicit et `code` (échange tenté une fois, repli « Se
    connecter ») — contrairement au reset (option B du lot 1), car le compte est confirmé par `/verify` et le verifier a été posé
    par le signUp natif ; passer le modèle au format `token_hash`. **Recommandé.**
11. **Étudiants et RPPS temps réel** : parcours étudiant en renvoi web ; RPPS contrôlé par `register-soignant` seul, refus
    verbatim. **Recommandé.** (corrigé v2) « Seul » vaut pour la **vérification** (pas d'appel `verify-rpps` depuis l'app) ;
    l'obligation de saisie suit la même liste que le web et le serveur (`PROFESSIONS_RPPS_REQUIS`, correction 20), portée en
    vecteur golden pour détecter toute dérive.
12. **Périmètre du profil** : identité, coordonnées, préférences de recherche, bio, expérience, avatar, localisation ; type
    d'exercice, cumul (L1222-5), spécialité, GPS, pool urgence en renvoi web ou autres lots. **Recommandé.**
13. **Mot de passe** : parité (ancien vérifié, 12 caractères + 5 critères) ; si le nonce est exigé, refus verrouillé vers « Mot de
    passe oublié ? » plutôt qu'un flux `reauthenticate` OTP au lot 3. **Recommandé.**
14. **Avatar** : JPEG 256 px qualité 0,8, `<uid>/avatar-<ts>.jpg`, URL signée 5 ans comme le web. **Recommandé.** (corrigé v2)
    Le web écrit du **WebP** (`AvatarUpload.tsx` l.51, l.136-140) : le JPEG est un écart assumé (MIME autorisé par le bucket ;
    encodage WebP non garanti par ImageIO en iOS 16), sans effet sur la lecture par l'URL signée.
15. **Géocodage** : `api-adresse.data.gouv.fr` (mêmes libellés que le web) plutôt que `CLGeocoder`. **Recommandé.**
16. **Thème** : Système / Clair / Sombre par appareil, défaut Système. **Recommandé.**
17. **Preuves push et Stripe sur STAGING** : (corrigé v2) créer la cohorte non-test D5-R par une **bascule transactionnelle**
    (dans la transaction backend de la fixture : `inscriptions_publiques_actives` 0 → 1, INSERT des trois acteurs avec
    `est_compte_test = false`, retour à 0, assertion, COMMIT — modèle `finance-cohortes-rollback.sql` l.18-62) plutôt que passer
    le paramètre à 1 sur STAGING (v1), qui casserait les recettes finance existantes (correction 2) ; nettoyage des acteurs D5-R
    en fin de recette. **Recommandé** ; sans ce go, les deux preuves restent « non mesurables ».
18. **Classement B9 du lot 3** : go humain pour B3, T7, T8, T12, T13, T14a, T14b, T16 (corrigé v2) ; auto-merge (CI verte + revue
    B8) pour les autres, préférences comprises (préférence de notification, pas un consentement juridique). **Recommandé.**
19. **Contestation** : B3 (garde de statut + idempotence + traitement du litige déjà ouvert, depuis la définition live) avant
    d'ouvrir le bouton ; verrou explicite d'ici là. (corrigé v2) **Recommandé : sans élargir le CHECK**, en retirant la
    notification `CONTESTATION_PAIEMENT` redondante avec `trg_notifier_creation_litige` (pas de DDL destructif) ; élargissement du
    CHECK seulement si Gabrielle veut une notification dédiée.
20. **IBAN** : le natif confirme l'IBAN du RIB vérifié (règle serveur), succès strict ; ouvrir une PR web séparée pour le faux
    succès de `SectionPaiements.tsx` l.259-262 (B9, go humain). **Recommandé.**
21. **Sentry** : projet iOS séparé `jolene-ios`, aucune PII, ni capture d'écran ni breadcrumbs réseau, traces à 0, crash de test
    en DEBUG uniquement. **Recommandé.**
22. **Exporter golden du push** : modules inertes nommés pour `pushNative.ts`, sans modifier `src/`. **Recommandé** (plutôt
    qu'extraire `src/lib/pushRouting.ts`). (corrigé v2) C'est une exception explicite à la règle du hook de L1-T2 (« tout alias
    `@/` hors `@/lib/` est refusé ») : liste nommée limitée à `pushNative.ts`, chaque module inerte lève s'il est appelé.
23. **Centre de notifications** : liste, lecture, tap ; ni suppression (RLS admin) ni Realtime (lot 4). **Recommandé.**
24. **Workflow STAGING** : (corrigé v2) workflow jumeau `ios-swift-lot3-staging.yml` (mêmes `policy.mjs`/`admit.mjs` non modifiés,
    groupe `jolene-supabase-staging-writes`, environnement protégé), comme le lot 2 (`ios-swift-lot2-staging.yml`) : la v1
    (job ajouté au fichier du lot 1) éditait un fichier possédé par L1-T11 et laissait le go B9 du dispatch sans garde
    technique. **Recommandé.**
25. (corrigé v2) **Captcha GoTrue refusé (`PORTE_LOT0` 3.1/3.2)** : `PORTE_LOT0.md` l.57-58 exige une décision avant le lot 3.
    **Recommandé : T7 livre alors « Créer un compte » en renvoi web (`/inscription/soignant` en Safari)**, la confirmation et la
    complétion natives restant valables pour un compte créé sur le web ; pas de SDK captcha natif ni d'exemption serveur au lot 3
    (dépendance tierce et changement Auth B9).
