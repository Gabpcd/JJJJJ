# Auth native STAGING — adaptation du 29 octobre 2026

Préparation adaptée au client source le 29 octobre et intégrée au candidat basé sur `46df363c4ec2446ccc73e5cc962702f3d44b8618`. Aucun build ni test d’interface de ce scénario n’a encore été lancé. Cette préparation n’est pas une preuve de connexion.

La cohorte existante du 27 octobre est conservée : deux comptes synthétiques confirmés, dont les marqueurs TEST et l’absence de profil, parcours et appartenance ont été relus sur STAGING le 29 octobre. Aucun compte supplémentaire n’est créé. La preuve de login API du 27 octobre reste distincte de la future preuve native. Les secrets ordinaires de ces deux comptes restent dans le stockage privé de recette et ne sont pas inclus dans ce document ou le dépôt.

## Client vérifié prévu

Les trois formats iOS utilisent désormais le même client Debug compilé depuis les sources React Native que les scénarios Consultation/Documents/Contrats. `ios-compiled-client.mjs` et `rn-text-input-patch.cjs` sont copiés sans modification depuis la base indiquée, uniquement pour disposer de la référence locale. Ils ne doivent pas écraser des versions ultérieures à l’intégration.

Le runner exige le SHA revu, applique le correctif TextInput déjà verrouillé, désactive le cœur RN précompilé, construit dans un DerivedData neuf, vérifie les objets natifs, le bundle `app.jolene.nativepilot`, la cible simulateur, l’absence de signature de livraison et le port Metro 8090. Il conserve les reçus de compilation dans son dossier privé. Android reste sur Expo Go SDK 57, comme la simulation actuelle du pilote.

Le démarrage iOS et les quatre redémarrages obligatoires passent uniquement `-RCT_jsLocation 127.0.0.1:8090`. XCTest cible le processus Jolene ; il n’utilise plus les arguments ou préférences d’Expo Go. Aucun jeton ni identifiant n’est injecté dans l’application. Les dépendances, le schéma Auth et les écrans de connexion restent ceux du checkout relu.

La compilation CI exige 15 Gio avant de démarrer, puis le runner contrôle une marge de 5 Gio toutes les quinze secondes pendant les commandes. Les limites de job et d’étape iOS sont alignées sur les simulations source existantes : 140 et 130 minutes. Ce sont des plafonds d’arrêt, pas une durée estimée. Aucun SDK ou build lourd n’est exécuté sur le Mac local.

## Parcours prévu

Quatre formats exécutés successivement avec les deux mêmes identités TEST isolées : iPhone, iPad portrait, iPad paysage, Android. Pour A puis B : saisie dans les champs ordinaires, connexion unique, admission uniquement à l’inscription incomplète, arrêt et redémarrage du processus sans ressaisie, déconnexion normale, nouvel arrêt/redémarrage et absence des deux identités. Aucun profil, permission métier, document, contrat ou paiement n’est modifié par le driver.

Le projet est exclusivement `mejpriaetwgtcstbgfid`, avec sa clé publique moderne. Les autres origines, clés administratives, mode démo et anciens dispositifs de recette fermés sont refusés. Le dispatch exige `main`, le SHA demandé/revu/checké/du workflow identique et l’environnement GitHub prévu. Les préconditions de provenance, CAPTCHA et comptes ne sont pas déduites de la présence de cette préparation.

## Données privées et preuves publiques

Le secret temporaire de cohorte entre dans une seule étape minimale, puis passe par fichier `0600`, stdin et dossier privé `0700`. Le runner ordinaire reçoit une liste explicite de variables publiques ; les indicateurs de compilation viennent de la configuration fixée, sans hériter de clé serveur, jeton GitHub, identifiant ou `.env` local. Le SHA source est public. Les identités arrivent seulement au runner XCTest par un xctestrun privé, ou dans les flows Maestro privés. iOS emploie le collage natif puis vide le presse-papiers. Les quatre relances ne ressaisissent jamais le mot de passe.

Les logs filtrés, résultats automatiques, xctestrun et reçus de compilation restent privés et sont supprimés en fin d’exécution. La sortie publique conserve exclusivement `report.json` et les quatre captures autorisées de l’écran d’inscription après authentification, jamais les champs de connexion. L’email fictif `@example.invalid` peut apparaître, sans mot de passe ni jeton. Le rapport distingue `compiled-debug-source` sur iOS et `expo-go` sur Android. Une relecture visuelle des captures demeure nécessaire.

## Vérifications et limites

Les 19 contrôles hors réseau de la politique, des canaris et du protocole ont passé après adaptation. Ils ne remplacent pas l’exécution native. La syntaxe JS/Swift/YAML est vérifiée séparément ; aucune installation de dépendance n’est nécessaire à ces contrôles.

Restent à réaliser : revue indépendante finale, intégration sur une base main verte, configuration du canal temporaire de la cohorte existante selon ses préconditions et permissions acquises, exécution réelle des quatre formats, relecture des preuves et suppression du secret temporaire créé pour la campagne, y compris en cas d’échec. Le collage iOS, sa demande d’autorisation et le transport xctestrun doivent encore être éprouvés dans le client compilé. Une réussite démontrerait Auth TEST, persistance, déconnexion et isolation A/B ; elle ne démontrerait pas les rôles professionnels, pointages, fournisseurs, appareils physiques ou binaires des stores.

L’ancienne préparation et son historique sont conservés sans modification dans `/private/tmp/jolene-native-auth-staging-preparation-20261027`.
