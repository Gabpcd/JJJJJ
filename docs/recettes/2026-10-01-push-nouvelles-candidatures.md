# Relais push des nouvelles candidatures

Le raccord ajoute une action de file lors des deux créations canoniques d’une candidature (`fn_postuler_mission` et `fn_enregistrer_swipe`). La candidature, sa notification interne et les actions push appartiennent à la même transaction. Aucun balayage de l’historique ni rattrapage n’est ajouté.

Les destinataires sont les membres actifs PROPRIETAIRE, ADMIN_GROUPE et RH, ainsi que le propriétaire historique dont l’identifiant Auth est exactement celui de l’établissement. Un simple rattachement dans les métadonnées ne suffit pas. Les comptes bannis, supprimés, non confirmés, TEST, de cohorte inconnue, les membres révoqués et les préférences PUSH désactivées sont exclus. La provenance et les préférences sont relues au dispatch. Les métadonnées transmises se limitent aux identifiants candidature, mission, soignant, établissement et notification, avec le destinataire, le titre/message de la notification et le lien interne. Le message libre de candidature n’est pas transmis.

Le type dédié `PUSH_CANDIDATURE_RECUE` ferme la fenêtre entre migration et déploiement Edge : le claim historique à deux arguments l’exclut ; seul le nouveau claim à trois arguments, capacité explicite et droit service_role, peut le prendre. L’ancien worker ne consomme donc aucune tentative de ces actions. Le nouveau conserve la limite globale, l’ordre et les verrous existants. Il utilise le relais `send-push` inchangé, avec une clé d’idempotence stable par action. Un refus ou un résultat ambigu du relais reste un échec ; aucun succès de queue ne remplace un succès d’envoi.

La notification OS créée localement par le panneau web est retirée pour ce seul événement afin de respecter les préférences et d’éviter le doublon avec Web Push. Les notifications internes, le toast et les autres événements restent inchangés. Le délai dépend du worker et des fournisseurs existants ; aucune livraison immédiate garantie n’est annoncée.

## Sources et préconditions

Base de développement : `dfd62dfbdf4d1262c72f0c627d4eee2975a04179`. Le catalogue de production a été lu sans appel métier le 1 octobre 2026 : définitions, ACL, colonnes, contraintes et triggers. La migration refuse toute dérive des préconditions, la présence d’un ancien stock de push candidature et une installation partielle. Les fonctions exposées sont inventoriées ; un contrôle final vérifie propriétaires, droits, search_path et modes de sécurité.

Le worker LIVE v412 et ses quatre fichiers étaient identiques à la base ; `send-push` LIVE v808 et ses six fichiers aussi. `fn_externalisation_echec` LIVE (`e9f4dfc258514e4b450e2f2aedb356c9`, relevé 14:58:51 UTC) atteint l’état terminal ERROR après trois échecs : l’exclusion du nouveau type dans l’ancien claim évite cette perte pendant la transition.

## Vérifications locales

- 31 tests Node hors réseau : vrai dispatch extrait du worker, ancien dispatch byte-identique, payload fermé, préférences/révocation, erreurs, clé stable ; vrai handler send-push avec transports WEB/APNs/FCM remplacés localement, refus TEST/inconnu et état ambigu sans nouvelle tentative fournisseur.
- 32 tests Vitest ciblés : panneau de notifications et gardes existantes des externalisations/cron. Le panneau conserve toast/compteur tout en évitant la seconde notification OS candidature.
- TypeScript application et build web fictif verts. Actionlint, diff-check et parse PostgreSQL : migration 19 instructions/10 unités PL/pgSQL ; témoin 36 instructions/6 unités PL/pgSQL.
- 15 simulations initiales, sans retry : préférences globales/événement avec enregistrement et reload ; ouverture de la candidature depuis une notification après connexion/reload pour le propriétaire et depuis la fiche déjà ouverte pour RH. Chaque scénario couvre iPhone, Android, iPad portrait/paysage et ordinateur.
- 5 reprises finales des préférences vérifient le bouton dans le viewport, son hit-test et le rechargement, avec captures lisibles sans modification CSS ni masquage des barres fixes. Les premières captures et deux échecs de préparation locale (configuration sparse et normalisation de témoin) sont conservés.

Les réponses Auth/REST et les événements natifs sont simulés, les WebSockets fermés. Ces preuves ne valident ni Realtime, ni APNs/FCM/Web Push réels, ni un appareil physique. Les premiers cadrages pleine page ne constituent pas une preuve que chaque carte longue tient dans le viewport ; les captures finales ciblent le contrôle effectivement manipulé.

## Validation encore requise

Le témoin SQL est raccordé à Validate PR, sous transaction puis ROLLBACK, sans token push ni invocation Edge. Il couvre les deux producteurs, six destinataires exacts, exclusions, révocation/préférence tardive, provenance forgée, refus rétroactif, ancien et nouveau claim sur le même ensemble, limite/ordre, absence de doublon et rollback atomique si la file échoue. Les fixtures de cohorte réelle sont nouvelles et synthétiques, uniquement dans cette transaction ; aucun compte TEST existant n’est transformé, aucun trigger n’est désactivé.

Ce témoin n’a pas encore été exécuté sur PostgreSQL distant. La revue indépendante, la CI SQL et ses contrôles après annulation doivent précéder toute publication/déploiement. La réception physique reste une recette distincte autorisée sur destinataires de test maîtrisés ; aucune notification réelle n’a été envoyée par ce lot.

Preuves locales conservées dans `/private/tmp/jolene-push-candidatures-preuves-20261001`, avec les états rouges initiaux, les catalogues, les JSON de résultats, les captures et les empreintes du build servi. Le build se trouve dans `/private/tmp/jolene-push-candidatures-dist-20261001` ; aucun serveur local n’est laissé actif.

### Isolement du témoin SQL sur une file préexistante — 1er octobre 2026

Le run de PR 1013 au commit `66c7aacf` a refusé le contexte avant toute fixture
(`PUSH_RECETTE_CONTEXTE_NON_ISOLE`). La lecture indépendante a confirmé trois
anciennes actions `PENDING` réelles ; ce constat ne permet pas de les exécuter ni
de présumer qu'elles sont jetables. Les contrôles après échec étaient inchangés.

Le correctif porte seulement sur le banc et sa preuve indépendante. Sous le
verrou CI existant, le test acquiert `SHARE ROW EXCLUSIVE` sur la file, avec
`lock_timeout = 5s` et `statement_timeout = 90s`. Il garde une photo JSONB privée
complète de toutes les lignes préexistantes, refuse tout trigger ou règle UPDATE
actif, pince les corps des deux claims et la définition du classificateur, et
refuse toute collision des sept identifiants de worker du test. Cette dernière
garde couvre aussi le SELECT final du claim, qui retrouve les prises récentes
par identifiant de worker.

Dans cette seule transaction, les états `PENDING`/`PENDING_AIFE` voient uniquement
leur `next_retry_at` reporté, et `PROCESSING` uniquement `cron_lock_at`. Les dates
sont placées un jour après le début de la transaction. Les autres colonnes et
états restent identiques. Le prédicat temporel exact des deux claims est vérifié
sur toutes les lignes étrangères, indépendamment de leur type et de leur
classification réelle. Chaque réponse de claim, y compris la boucle des anciens
workers, doit contenir uniquement les huit actions de fixture recensées et aucune
ligne de la photo. La photo est contrôlée après chaque claim.

Avant le ROLLBACK final, le test refuse les ajouts hors fixture, les suppressions
ou tout changement hors des deux dates prévues, puis restaure exactement ces
dates et compare chaque ligne entière à la photo. Aucun payload étranger n'est
renvoyé ou journalisé. Le SELECT indépendant avant/après renvoie désormais aussi
une empreinte ordonnée de toutes les lignes complètes de la file : une altération
à compte constant bloque donc la preuve. Les 24 compteurs, les autres empreintes,
les gardes cron/réseau et le contrôle `always` restent en place.

Les fonctions produit, les règles de claim, les fixtures de candidature et les
attendus métier sont inchangés. Les contrôles locaux vérifient la source et le
contrôleur avec transport simulé ; ils ne prouvent pas encore l'exécution SQL du
nouveau banc. Celle-ci doit passer dans la CI transactionnelle avec son SELECT
indépendant. Aucune nouvelle campagne UI n'est attribuée à ce delta de banc :
les simulations frontend du lot push restent des preuves distinctes, sans
livraison réelle de notification ni mouvement fournisseur.
