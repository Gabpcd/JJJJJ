# Candidatures : notification vers un établissement secondaire ou un groupe

Le relais notifie les membres actifs PROPRIETAIRE, ADMIN_GROUPE et RH de l’établissement de la mission. Ces droits ne dépendent pas de l’établissement unique retourné par `mon_etablissement_id()`. Le détail historique lisait pourtant la mission et les candidatures dans ce seul périmètre ; la route excluait également le vrai rôle applicatif ADMIN_GROUPE. Un propriétaire A/RH B pouvait recevoir B et avoir le droit de décider, sans pouvoir ouvrir sa candidature.

Le point d’entrée reste `/etablissement/missions/<uuid>`. Pour un compte établissement autorisé par la RLS existante, il rend le détail habituel. Les autres membres passent par `fn_lire_candidatures_mission_habilitee(uuid)` : compte actif et confirmé, adhésion actuellement habilitée à cet établissement, même permission `candidatures` que les décisions existantes et repli propriétaire historique borné. Le groupe de santé seul, la métadonnée de rôle, un rôle plateforme ou une ancienne adhésion ne donnent aucun droit. La projection contient la mission, son planning et ses candidatures de la même cohorte TEST, avec nom masqué et scores existants ; aucun document, finance ou coordonnées.

Aucune policy, RPC de décision, liste de destinataires ou règle de livraison push n’est modifiée. Le reste de l’application conserve son établissement canonique. La liste existante reçoit deux lecteurs bornés ; elle revalide le planning avant confirmation. Les messages et retours asynchrones appartiennent au couple utilisateur/mission courant. Le retour vers l’espace et le nom de l’établissement restent visibles.

## État vérifié au 3 octobre 2026

Les sections de préparation ci-dessous conservent leurs limites initiales. La qualification PostgreSQL 17 isolée est depuis réussie : [run 37062151311](https://github.com/Gabpcd/JJJJJ/actions/runs/37062151311), source produit `2ce64a8afb57fcefc797fac9d0884aeba6cad1ea`. Les 218 migrations ont été importées octet pour octet ; huit empreintes de helpers, policies et permissions concordent avec la référence. Accès autorisés et refus, projections et révocations ont été exécutés avec les vrais helpers ; rollback confirmé par quatorze compteurs nuls avant/après. Le nettoyage indépendant ne retrouve aucun conteneur, volume ou réseau de cette recette.

Trois défauts du banc ont été corrigés sans changer les permissions produit : variable SQL ambiguë, comparaison RLS avec un format différent de la collecte, ordre de créneau fictif dupliqué. Le test final a pour SHA256 `7373d4a3` (préfixe ; empreinte complète dans la preuve du run). Ces correctifs restent inclus dans la branche produit.

La simulation frontend avec réponses synthétiques a réussi 45/45 observations : neuf scénarios sur iPhone, Android, iPad portrait, iPad paysage et ordinateur. Elle couvre connexion, résolution de rôle, accès/refus/révocation, reprise et rechargement. Le premier essai37/45 reste conservé ; la reprise complète suit la correction de l'interception PSC et de l'attente avant rechargement, sans retrait d'assertion.

Ces résultats ne sont ni un déploiement de la migration, ni une connexion au fournisseur PSC, ni une réception push physique. Les scénarios fournisseur et les actions réelles avec comptes autorisés après déploiement restent à qualifier. Le parcours SOIGNANT + adhésion établissement est interdit par le schéma ; son positif DOM injecté ne démontre aucun accès métier réel. Aucun build mobile, OTA ou store n'est déclenché par cette recette.

## Reprise après connexion

Le lien canonique survit à la connexion par mot de passe ou biométrie pour les rôles reconnus ; l’accès est ensuite contrôlé par la garde et la RPC.

PSC transmet uniquement ce chemin à l’authorize. L’Edge signe l’aléa existant, l’UUID cible et l’expiration de quinze minutes par HMAC SHA-256 avec séparation d’usage et le secret PSC déjà utilisé au callback. Le **state signé complet** est conservé puis consommé atomiquement : tronquer la signature pour revenir à l’ancien format ne retrouve pas la session. Les sessions historiques à 43 caractères restent admises sans retour. Le callback ignore tout paramètre de retour libre ; aucune origine externe, autre route, query ou fragment ne peut être signé. PKCE, nonce, contrôles JWT/identité et association des comptes restent inchangés.

Après OTP, seul le SOIGNANT existant déjà admis par PSC reprend le chemin ; la RPC décide ensuite de l’accès. **Limite établie pendant la préparation PG : le trigger du dépôt `fn_protect_famille_compte_membre_etablissement` interdit une adhésion active à une famille SOIGNANT (23514).** Le positif DOM SOIGNANT + réponse RPC autorisée est donc un contrat de navigation injecté, pas une configuration métier normalement créable. Le test PG prépare au contraire le rejet de cette adhésion et le refus de lecture. Aucun trigger ni rôle n’est élargi pour fabriquer ce parcours. La définition LIVE de ce trigger reste à rapprocher. PSC n’acquiert aucun nouveau rôle ADMIN_GROUPE ou établissement. L’inscription d’un nouveau soignant passe toujours d’abord par sa complétion ; une reprise après cette complétion n’est pas ajoutée. Le réessai conserve le chemin canonique et une navigation plus récente n’est pas écrasée.

**Déploiement futur : callback compatible avant authorize émettant le nouveau state**, puis frontend. La boucle CI place désormais callback avant authorize et garde authorize inchangé si callback échoue ; les autres fonctions continuent, et le job échoue explicitement. Deux tests locaux exécutent cette boucle avec un transport factice, sans lancer de CI. Comparer les deux versions Edge LIVE avant cette opération. Une rotation du secret impose de relancer un retour signé encore ouvert. Aucun déploiement n’a été effectué par cette préparation.

## Catalogue et migration

Les catalogues primaire staging/production du 2 octobre à 06:09 UTC confirment les helpers, les 43 colonnes utilisées, les policies et les ACL. Le complément PSC à 06:34 UTC confirme `state text` sans limite/CHECK 43, sa clé primaire, l’expiration de quinze minutes et les droits service_role ; anon/authenticated ne peuvent lire, insérer ou supprimer ces sessions. postgres possède BYPASSRLS.

Migration créée par la CLI : `20261002064017_lire_candidatures_mission_habilitee.sql`. Propriétaire postgres explicite, révocation PUBLIC/anon/service_role — ce dernier est accordé par les defaults LIVE — et EXECUTE authenticated. L’inventaire utilise `md5(pg_proc.prosrc)` et `RPC_UTILISATEUR_AUTH_INTERNE`. Le contrat RPC est ajouté aux types frontend. La migration, ses ACL résultantes et sa projection n’ont pas encore été exécutées en PostgreSQL ; l’ordre des migrations distantes reste à recontrôler avant publication.

## Vérifications de cette préparation

Les tests du dépôt utilisent les véritables pages, liste et handlers proposés. Contexte Auth, transports, réponses SQL/PSC et JWT sont simulés ; la signature HMAC utilise WebCrypto réel avec une clé synthétique. Aucun fournisseur, navigateur, téléphone, compilation ou base distante n’est appelé.

- Nouvelle page : 17 cas DOM, dont vrai rôle groupe, B secondaire, refus, réessai, actualisation, changement de compte et réponse tardive.
- Liste : 3 nouveaux cas DOM lecteurs/planning/notes et 8 régressions existantes.
- Connexion : 6 cas avec la vraie garde et 19 régressions existantes, dont invitation et biométrie.
- PSC : 9 cas DOM connexion/bouton/callback/garde, 16 signatures/allowlist, 6 handlers exécutés en mémoire et 8 gardes existantes d’identité/profession.

Les 94 cas distincts passent dans les exécutions ciblées, dont les deux scénarios d’ordre de déploiement. Le premier lancement utilisait jsdom pour les handlers Edge : deux scénarios échouaient sur une API de runtime, sans appel réseau. Ces deux suites déclarent désormais l’environnement Node ; l’initialisation globale `matchMedia` est limitée au DOM. Les 22 cas Node passent après adaptation, puis 17 cas DOM repassent après cette garde. Les avertissements existants React Router/Vite restent visibles. Résultats locaux hors dépôt : `/private/tmp/jolene-notifications-integration-memoire-20261002.json`, `/private/tmp/jolene-notifications-integration-node-20261002.json` , `/private/tmp/jolene-notifications-integration-dom-regression-20261002.json` et `/private/tmp/jolene-notifications-integration-deploy-order-20261002.json`.

Commande ciblée pour reproduire l’ensemble ultérieurement :

```sh
node_modules/.bin/vitest run src/pages/MissionDepuisNotification.test.tsx src/components/ListeCandidatures.habilitees.test.tsx src/components/ListeCandidatures.test.tsx src/pages/PageConnexion.notification.test.tsx src/pages/PageConnexion.role-resolution.test.tsx src/pages/PscCallback.notification.test.tsx tests/admin/security/psc-return.test.ts tests/admin/security/psc-return-handlers.test.ts tests/admin/security/psc-security.test.ts tests/admin/security/psc-deploy-order.test.ts --maxWorkers=1 --minWorkers=1
```

Le test `tests/security/candidatures-multi-etablissements.test.sql` est préparé pour une base PostgreSQL 17 locale isolée et rollback. Il emploie les vrais helpers et claims, sans simuler la permission ; ses conditions d’isolation doivent être satisfaites avant lancement. Il ne doit pas être ajouté au runner SQL d’une base staging partagée. Il n’a pas été exécuté pendant cette préparation.

## Recette restante avant validation fonctionnelle

Employer les mêmes objets mission/candidature sur iPhone, Android, iPad portrait/paysage et ordinateur :

1. Propriétaire A/RH B puis RH A/RH B : ouvrir B depuis la notification après connexion et déjà connecté ; voir B, son candidat et ses créneaux, accepter/refuser avec confirmation puis reload. A reste le périmètre du reste de l’application. C non membre est refusé.
2. Vrai rôle applicatif ADMIN_GROUPE avec adhésion active B : même parcours et retour espace groupe. Groupe sans adhésion B, adhésion révoquée/rétrogradée, compte inactif/non confirmé : refus sans donnée B. Conserver le détail mono-E et sa lecture actuelle.
3. Planning modifié pendant confirmation : nouvelle confirmation obligatoire. Décision dans deux onglets, changement de compte et réponse tardive : pas de résultat d’une autre mission ou identité. Tap sur la même page, panne/reprise et reload visibles.
4. PSC : aller/retour PSC de test réel lorsque disponible, chemin canonique après OTP puis refus sans données pour le soignant sans adhésion, réessai après erreur et reload. Ne pas fabriquer une adhésion SOIGNANT + RH contraire au trigger existant pour obtenir un succès. Les membres établissement/groupe utilisent leur méthode actuellement admise (mot de passe ou biométrie). Nouvel inscrit PSC : complétion prioritaire. Aucune extension des familles de compte.
5. Dans PostgreSQL 17 isolé, vérifier les assertions préparées, l’ACL effective et les policies inchangées. Puis revue indépendante du commit exact, typecheck/build/guards/CI et campagne frontend coordonnée.

Aucun parcours ci-dessus n’est déclaré validé par les tests mémoire. La présence des dix noms APNs/FCM/VAPID et de téléphones enregistrés, relue en production le 2 octobre, ne prouve ni la validité des clés/environnements ni la réception. Les douze notifications observées sur sept jours visaient des comptes TEST, dont le transport est volontairement exclu. La recette physique iPhone/Android demeure distincte ; aucun build de livraison, OTA ou store n’est autorisé par ce lot.
