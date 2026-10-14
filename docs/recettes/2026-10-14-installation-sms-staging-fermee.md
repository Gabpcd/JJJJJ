# Installation fermée du supplément SMS staging

Ce workflow manuel prépare uniquement `mejpriaetwgtcstbgfid`. Il déploie le
seul dispatcher `send-sms`, puis installe le supplément SQL complet avec une
table de capacités vide. Il ne configure aucun secret, n’alloue aucune capacité,
ne crée aucun compte, contrat ou OTP et ne contacte aucun fournisseur. Le
registre des migrations et les données métier restent inchangés.

## Exécution sur main

Après merge validé de l’installateur, choisir le workflow
`Installer SMS signature staging fermé (manuel)` sur **main**, avec
`expected_sha` égal au SHA complet de main relu. Il n’existe aucun input de
projet, source SQL, slug, manifeste, compte ou téléphone. Les identifiants du
témoin sont ceux du manifeste versionné ; tout changement exige une nouvelle
revue de ce manifeste.

Le workflow partage `jolene-supabase-staging-writes` avec les autres écritures
staging et refuse une relance du même run. Il utilise uniquement le token
Management staging et le token GitHub en lecture. Aucun credential Twilio,
PSC ou service-role applicatif n’est lu ou transmis.

## Preuves et séquence

Le manifeste lie les 31 fichiers produit/témoin utiles au head relu
`5d8b08b879885d4807c6cfa6a15af0b176106239`. Les runs PG17 `38591583136`
(58 cas, nettoyage confirmé) et frontend `38591583466` (80 scénarios simulés)
ont exécuté le merge `8d21229d749c767ccac1341640856008a02541a9`, dont les parents
sont `6922565` et ce head. L’adaptateur vérifie la filiation, les blobs du tree
exécuté, les runs/jobs verts, et l’empreinte du petit artefact PG17 déjà relu.
Le pin de cet artefact atteste le reçu synthétique de 58 cas ; le workflow ne
télécharge aucun ZIP de captures. Ces preuves ne prouvent pas un SMS réel.

Avant toute mutation : main exact, fichiers/manifeste, identité indépendante
du projet via Management API, PostgreSQL 17, sources/ACL/configuration des cinq
routines LIVE, absence des nouveaux objets et quiescence. La fonction LIVE
`send-sms` doit encore être ACTIVE en version 23, JWT désactivé, sans import map,
avec le bundle et les cinq sources de la baseline du 14 octobre. Ces sources
correspondent à Git `6922565` ; le commit de déploiement n’est pas attribué.

Les lectures SQL conservent le rôle opérateur Management (`read_only:false`)
pour lire les catalogues privés. PostgreSQL impose `BEGIN READ ONLY` ; le SQL
vérifie `current_user=session_user=postgres`, la transaction non modifiable et
`row_security=off`. Aucun rôle ni privilège n’est changé.

L’adaptateur déploie `send-sms` **une seule fois**, sur le projet constant. Il
vérifie version 24, bundle renouvelé, sources et imports locaux exacts, ainsi que
les métadonnées inchangées de toutes les autres Edge Functions. Ce dispatcher
ferme les SMS ordinaires staging même pour les comptes NORMAL ; son exception
TEST reste impossible tant que la table de capacités est vide.

Il applique ensuite le SQL rendu entier, avec timeouts et verrous, sous
transaction annulée, puis confirme la restauration. Une seule transaction de
commit suit, avec les mêmes préconditions et assertions. La relecture confirme
table vide, RLS/ACL fermées, routines et inventaire attendus, registre et données
inchangés. Le digest après rollback confirme seulement l’égalité commit/relecture :
il ne remplace pas les pins de sources ni les assertions sur les objets visés.

## Arrêt et limites

Une réponse perdue, ambiguë ou non conforme après le début d’une mutation laisse
un reçu `uncertain`. Cet état est persisté par remplacement atomique **avant**
l’appel de mutation, afin qu’un kill, timeout ou cancel conserve l’incertitude
même sans exécution du catch. **Ne pas relancer** : relire l’état distant et faire revoir
un nouveau manifeste d’installation ou de réparation approprié. Il n’existe
aucun retry de mutation, reset, rollback compensatoire, `db push`, ni écriture
dans `schema_migrations`.

Une installation fermée réussie laisse la capacité vide et les préférences,
cohortes TEST et anciennes capacités Stripe inchangées. L’activation, les nouveaux
objets de recette, les téléphones contrôlés et la réception fournisseur sont des
travaux distincts. L’ancien indice de 401 Vault/PSC reste à requalifier séparément ;
ce workflow ne lit ni ne corrige cette clé et n’appelle pas de métier pour la tester.
