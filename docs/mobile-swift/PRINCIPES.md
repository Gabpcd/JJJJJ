# Principes d'architecture de l'app iOS Swift (lot 0)

Règles portées de `mobile-native/AGENTS.md` (pilote React Native, gelé) et du plan
`docs/PLAN_APP_NATIVE_SWIFT.md` §4, adaptées à Swift, SwiftUI et supabase-swift. Les
consignes de Gabrielle et de `CLAUDE.md` s'appliquent en plus : « livré ≠ mergé »,
preuve par assertions, HARD STOP sur tout wording juridique exposé à l'utilisateur.

## 1. Modules et dépendances

- `ios-native/` contient `Jolene.xcodeproj` (généré par XcodeGen depuis `project.yml`,
  source de vérité) et trois packages locaux : `JoleneCore` (zéro UIKit ni SwiftUI),
  `JoleneSupabase` (seul module qui importe le SDK), `JoleneDesign` (jetons et composants).
- supabase-swift est le seul SDK réseau, épinglé en version exacte (`2.55.5`). Pas de
  Firebase. Sentry Cocoa au lot 3 seulement.
- Swift 5 avec `SWIFT_STRICT_CONCURRENCY=complete` : tout type qui traverse une
  frontière de tâche est `Sendable` ; l'état partagé vit dans des acteurs.
- Jamais de modification sous `ios/`, `android/`, `capacitor.config.ts`, `supabase/`
  ni `mobile-native/` depuis ce chantier.

## 2. Ports et gateways

- Chaque domaine est un protocole de port dans `JoleneCore/Ports` (`AuthPort`,
  `RolePort`, `MissionsPort`, `ClockPort`, puis présence, documents, contrats, compte,
  stockage sécurisé, GPS). Les vues et le contrôleur de session ne connaissent que les ports.
- Un jeu complet de ports par mode d'exécution (`Gateways`) : Demo (fixtures JSON
  versionnées, aucun réseau), Staging et Production (supabase-swift). Les gateways ne
  contiennent aucune règle métier ; le filtrage est serveur (PostgREST, RPC).
- Les modèles sont `Codable` à clés snake_case explicites, dérivés de
  `src/integrations/supabase/types.ts` et des projections du pilote ; pas de stratégie
  de conversion automatique, pour que le contrat se lise ligne à ligne.
- Les signatures existantes de `Mission.swift`, `Account.swift`, `Ports.swift` et
  `Environment.swift` sont le contrat partagé entre agents : on les étend (nouveaux
  fichiers, extensions), on ne les change pas. Seule exception, consignée au lot 1 :
  l'ajout additif de champs à `Gateways`, dans le corps du struct (Swift interdit les
  propriétés stockées en extension), chacun avec un port « non câblé » par défaut, et d'un
  second init complet ; l'init du lot 0 est conservé.
- Un port « non câblé » (`Ports/Lot1Ports.swift`) ne rend jamais un état vide plausible :
  il lève `.contract` en citant la tranche qui le livre. `Gateways.unwiredPorts` nomme les
  ports encore stubs. La liste attendue n'existe qu'à un endroit
  (`DemoWorldTests.portsEnAttenteLot1`) ; `SupabaseGatewaysTests` compare le monde Supabase
  au monde démo, si bien qu'un port câblé dans un seul monde rougit un test. Chaque tranche
  câble son port dans les deux mondes et le retire de la liste dans la même PR ; elle est
  vide à la clôture du lot (`unwiredPorts.isEmpty`, T12).

## 3. Aucun succès fabriqué

- Aucune réponse fictive ne remplace une erreur serveur. Un bouton de mutation
  n'annonce un succès qu'après réponse serveur vérifiée **et relecture de l'objet**
  (mission, présence, document, contrat) par le port de lecture.
- Les erreurs PostgREST `PGRST202` et `300` à `303` sont des refus définitifs : pas
  de renvoi automatique, message utilisateur en français sans valeur saisie ni détail
  technique (`JoleneError`).
- Montants, net estimé, heures facturées, règles juridiques (mode d'exercice,
  avertissements) sont des **valeurs serveur** affichées telles quelles, jamais
  recalculées ni interprétées côté client. Tout texte juridique est celui du web.
- Les écrans d'un établissement (lot 5) utilisent l'identifiant et les permissions
  renvoyés par le serveur (`fn_mes_permissions_etab`), jamais `user.id` par défaut.

## 4. Reçus durables et réconciliation

- Avant tout upload Storage et avant tout scan de pointage, un reçu est écrit en
  Keychain avec les phases `prepared` → `started` → `refused` / `not_sent` / terminé.
- Règle : **aucun renvoi automatique**. Après un arrêt forcé ou une coupure, l'app
  réconcilie par relecture serveur (état de la présence, ligne `documents_soignants`)
  et ne rejoue une action que si la relecture prouve qu'elle n'a pas été reçue.
- La file hors-ligne QR garde la sémantique de `src/lib/qr-offline-queue.ts` : un QR
  expiré n'est jamais remis en file.

## 5. Session et epoch d'identité

- Le contrôleur de session est un acteur avec un **epoch d'identité** : toute
  connexion, déconnexion ou changement d'utilisateur incrémente l'epoch et invalide
  tous les caches (listes, détails, profil, rôle). Une réponse réseau portant un
  epoch périmé est ignorée.
- La session complète est conservée par supabase-swift dans le Keychain
  (`kSecAttrAccessibleWhenUnlockedThisDeviceOnly`, sans sauvegarde iCloud). On ne
  copie pas le schéma Capgo du refresh token stocké à part.
- Rôle résolu par `fn_get_my_role`, raccourci `app_metadata.role` puis repli legacy
  `ETABLISSEMENT`. Rôles non servis nativement : écran de renvoi vers jolene.app,
  aucune RPC `fn_admin_*` embarquée.
- **Écart assumé, rôle `INCONNU`** : le web (`src/hooks/useRole.ts` l.150-165) relit
  `parcours_inscription` et ouvre l'espace soignant si `type_compte = 'SOIGNANT'` (compte en
  cours d'inscription). Le port Swift (`RoleResolution.resolve` → `candidate = nil` →
  `.blocked(.unsupportedRole(nil))`, test `testUnknownRoleIsBlockedWithNil`) renvoie vers
  jolene.app sans ce repli : l'inscription est hors périmètre natif jusqu'au lot 3, qui
  portera le repli `parcours_inscription` avec l'inscription (`PARITE_SOIGNANT.md`).
- Chaque appel de port de la résolution (restauration, rôle, profil) est borné à 15 s
  (`SessionController.resolutionTimeout`, comme le pilote) ; au-delà, l'état est
  récupérable (`.signedOut` avec message générique, epoch inchangé), jamais un chargement
  sans issue. Depuis le lot 1, la borne est le helper public `bounded(timeout:_:)`
  (`Session/Bounded.swift`) et `resolutionTimeout` est public : les modèles d'écran bornent
  leurs lectures et mutations au même délai. Un délai dépassé sur une mutation impose une
  relecture, jamais un renvoi. L'annulation de l'appelant (vue qui disparaît) lève
  `CancellationError`, jamais le message de délai dépassé.
- Le SDK est observé (`AuthPort.authEvents()` → `SessionController.handleAuthEvent`) : une
  session effacée côté serveur (révocation, déconnexion globale, refresh refusé) avance
  l'epoch et ramène l'écran de connexion sans action de l'utilisateur. Une revalidation
  (reprise après 30 minutes) ne démonte pas l'espace prêt et tolère une erreur transitoire.
- Garde d'environnement : seuls `demo`, `staging`, `production` ; un mode inconnu ou absent
  est refusé (écran bloquant qui nomme la valeur), jamais remplacé par `production` ; clé
  `sb_publishable_` obligatoire, toute clé secrète refusée, ref de projet dans
  l'allowlist, sinon écran bloquant. Le mode démo n'a ni URL ni clé. Les surcharges de
  lancement ne sont honorées qu'en build DEBUG.

## 6. Identifiants d'accessibilité

- Convention reprise du pilote : `tab-accueil`, `tab-explorer`, `tab-missions`,
  `tab-revenus`, `tab-profil` ; `login-email`, `login-password`, `login-submit`,
  `login-scroll` ; `contract-otp` ; cartes et écrans nommés `mission-card-<id>`,
  `mission-detail`, `blocking-screen`.
- Un identifiant est posé sur chaque contrôle qu'un XCUITest doit atteindre, jamais
  déduit du libellé affiché (les libellés changent, vouvoiement compris).
- Les XCUITest atteignent un contrôle par défilement borné dans le conteneur
  identifié ; aucun scénario n'est sauté parce qu'un contrôle n'est pas visible.
- Budget CI (revue B8 de T5, 2e passe) : chaque classe XCUITest démo est rangée dans un
  groupe de `scripts/mobile/ui-test-groups.mjs` (un job par format et par groupe dans
  `ios-swift-ci.yml`, étape de 30 min chacun ; le job « Cœur » échoue sur une classe non
  rangée). Un lancement coûte une connexion démo (jusqu'à 220 s sur iPad paysage) : les
  recettes d'états dont les surcharges sont compatibles partagent un lancement, et un groupe
  qui dépasse l'alerte de 20 min est scindé avant la tranche suivante.

## 7. Preuves par niveau

Cinq niveaux hérités du pilote ; un lot n'est livré que si les niveaux exigés par ses
critères de sortie sont acquis. Aucun niveau ne prouve les autres.

| Niveau | Ce qu'il prouve | Où |
|---|---|---|
| 1. Tests injectés | Règles pures, contrats de décodage, transports simulés (PGRST202, 300-303) | `swift test` dans `JoleneCore` et `JoleneSupabase` ; vecteurs golden exportés des tests vitest |
| 2. Démo simulateur | Navigation, écrans, orientation, aucune requête réseau en mode démo | `JoleneUITests` sur iPhone, iPad portrait, iPad paysage (`ios-swift-ci.yml`, un job par format et par groupe de `scripts/mobile/ui-test-groups.mjs`) |
| 3. STAGING | Connexion réelle, rôle, lecture et mutations relues sur `mejpriaetwgtcstbgfid` | `ios-swift-staging.yml` (dispatch manuel, environnement protégé) |
| 4. Fournisseurs TEST | Stripe TEST, APNs sandbox, SMS de recette | Workflows dédiés, preuves reliées aux objets backend |
| 5. Appareil physique | Caméra, GPS, Keychain, Face ID, push, arrêt forcé | Recette consignée dans `docs/mobile-swift/RECETTE_DEVICE_LOT<n>.md` |

- La preuve est une **assertion** (XCTest, résumé xcresult relu, requête SQL STAGING),
  jamais une capture seule. Les captures sont des artefacts pour l'humain ; leur
  orientation est contrôlée par `mobile-native/scripts/png-dimensions.mjs` repris tel quel.
- Un run sans capture n'est pas une preuve d'orientation ; le résumé du job le dit.
- Les logs publics ne contiennent jamais d'identifiant, de mot de passe ni de jeton :
  rédaction par `policy.redact`, masquage `::add-mask::` de chaque forme encodée,
  xcresult STAGING conservé privé.
- Mode démo explicitement affiché dans l'app ; intégration uniquement sur STAGING avec
  clé publishable et JWT utilisateur. Aucun accès privilégié, aucun repli production.

## 8. Livraison

- Aucun build de livraison, aucune soumission store automatique depuis la CI du lot 0.
  `mobile-delivery.yml` n'est réécrit qu'au lot 6.
- Disque local serré : un seul `DerivedData` (`~/Library/Developer/Xcode/DerivedData/JoleneNative`),
  les packages se compilent avec `swift build` / `swift test` dans leur dossier.
- Toolchain CI fixée (Xcode 26.4.1 build 17E202, runtime iOS 26.2, simulateurs
  « iPhone 17 » et « iPad (A16) ») : jamais de repli silencieux vers une autre version.
