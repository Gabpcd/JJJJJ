# Admission SMS de signature — préparation fermée du 14 octobre 2026

Ce lot prépare uniquement un circuit isolé sur `mejpriaetwgtcstbgfid`. Il ne
crée aucun compte ni capacité, ne configure aucun fournisseur et n'envoie aucun
SMS. Aucun fichier n'est ajouté aux migrations de production. Aucun exécuteur
réseau ni workflow d'installation/activation n'est fourni : installation,
activation et recette restent non autorisées par ces fichiers seuls.

## Provenance et fermeture

Le corps LIVE de `fn_envoyer_otp_signature` a été lu via MCP SQL en lecture seule
le 14 octobre ; son MD5 est `786555c2ebd4bf148204b18cb48e9c1c`. La définition
exacte est conservée dans `scripts/ci/sms-signature-staging-otp.source.sql` et
épinglée par SHA256 dans le générateur. Les corps du ledger existant sont aussi
épinglés par le préflight SQL. Toute dérive interdit la génération/installation,
sans rechercher automatiquement une autre source compatible.

Le supplément `scripts/ci/sms-signature-staging.sql` crée une table privée vide,
avec RLS sans policy et aucun droit direct de compte applicatif. Une capacité
figerait deux acteurs TEST, leurs téléphones contrôlés, un contrat/mission et
document final, le fournisseur/expéditeur, un manifeste et un SHA relus.
`enabled=false` par défaut, fenêtre maximale 60 minutes, deux tentatives
fournisseur par acteur (quatre au total), compteurs monotones, filiation
immuable et révocation irréversible. Les capacités Stripe existantes restent
distinctes et inchangées : leur facture n'existe pas au moment de signer.

Le futur exécuteur devra prouver lui-même le projet staging, la source et le
manifeste exacts avant tout DDL ; la garde SQL Vault et la garde URL Edge ne
remplacent pas cette preuve indépendante. Il devra d'abord exécuter un témoin
PG17 puis installer le supplément complet sous transaction, sans reset, avec
relecture finale. Ne pas envoyer ce fragment via le déploiement production.

## Transport et interface

L'exception conserve les cohortes TEST et ne concerne que `OTP_SIGNATURE`
interne service-role. La requête doit correspondre au code hashé courant, au
contrat, à la mission, au rôle, au téléphone, à la fenêtre et au compteur réels.
Le template et le préfixe sont stricts. La réservation utilise le ledger actuel
sous verrou de contrat et de capacité ; tout `RESERVE`, reprise d'un échec
explicite comprise, consomme une tentative avant le POST. Les doublons et les
résultats en cours/indéterminés ne provoquent aucun nouvel envoi. Une exception
budgétaire annule atomiquement la réservation. Aucun code OTP n'est renvoyé au
client ou ajouté à l'audit applicatif.

Les préférences SMS restent obligatoires. Si `canal_sms=false`, l'interface
ne reçoit pas d'admission et aucun transport n'a lieu. Leur activation doit
être un choix explicite des seuls comptes contrôlés, dans l'interface. Aucun
autre canal ni acteur n'est activé.

`ContratMission` garde CANVAS pour les comptes TEST ordinaires. Le seul frontend
connecté à l'URL staging exacte peut lire la RPC d'admission liée à l'appelant.
Une admission valide révèle l'option OTP sans la choisir automatiquement ; la
lecture échoue fermée lorsque le supplément manque. Relecture après chargement,
changement de document ou retour de fenêtre ; fermeture à expiration. La RPC
métier et le dispatcher vérifient encore le périmètre avant chaque envoi.

## Vérification disponible et limites

Commande locale sans secret ni réseau :

```sh
node --test tests/node/signature-sms-staging.node.mjs
```

Les tests exécutent le vrai helper et le vrai dispatcher avec Auth/SQL/Twilio
simulés : configuration exacte, exclusions ordinaires, refus navigateur,
préférences, idempotence, erreur SQL, transport ambigu, expurgation et frontend
fail-closed. Ils vérifient aussi le générateur sur la définition LIVE figée.
Ils **n'exécutent pas le SQL** et ne prouvent ni verrous PostgreSQL, ni réception
SMS, ni rendu frontend, ni intégration fournisseur. Typecheck/build, revue
indépendante, témoin PostgreSQL 17 et simulation UI restent à exécuter.

Le 14 octobre, les 41 tests Node réussissent ; le parseur local `pglast`
analyse les 22 instructions SQL et les 9 unités PL/pgSQL générées. Cette
vérification syntaxique ne remplace pas leur exécution dans PostgreSQL.

Témoin PG17 requis : schéma fermé, ACL et rôle appelant, acteurs/contrat/hash/
téléphones exacts, projet étranger, dates, changement de téléphone/document,
révocation, immutabilité, préférence OFF, OTP périmé/supplanté, deux réservations
concurrentes, retries ERREUR comptés, INDETERMINE sans transport, budget épuisé
avec rollback du ledger, compteurs et cohortes inchangés hors ressources du run.

Simulation requise sur iPhone, Android, iPad portrait, iPad paysage, ordinateur,
pour soignant et établissement : CANVAS ordinaire, admission fermée/ouverte,
consentement, demande, refus/erreurs, code invalide/expiré, signature, rechargement,
changement de document, expiration et retour après révocation. Les cinq formats
partagent ensuite les mêmes objets d'une seule recette fournisseur ; aucun
budget n'est multiplié par format.

Le workflow `signature-sms-staging.yml` prépare un build Vite isolé avec l'URL
staging exacte et une clé publique factice. Sa matrice couvre les cinq projets
du config Playwright existant, chacun exécutant les huit scénarios de
`recette-complete-signature-sms-staging.spec.ts` (deux rôles). Toutes les routes
Auth/REST/RPC sont interceptées ; l'origine staging ne peut jamais atteindre
le réseau, les autres destinations sont bloquées, WebSocket compris. Le corpus
ordinaire ignore cette suite tant que `RECETTE_SIGNATURE_SMS_STAGING=1` manque,
car son build utilise une URL locale différente. Le harnais de mission existant
conserve son défaut local ; son option staging est explicitement bornée à cette
simulation. Les preuves incluent assertions, snapshots ARIA et captures, sans
SMS ni intégration fournisseur réels. Aucun build ou navigateur n'a été lancé
pour préparer ces fichiers.

## Prérequis encore absents

Téléphones/acteurs contrôlés exacts, comptes TEST actifs avec préférences
explicitement activées, contrat neuf issu de création → candidature → acceptation,
document final rendu, identifiants fournisseur/expéditeur et credentials Twilio
capables de livrer, manifeste final et exécuteur d'installation/activation relu.
L'identité PSC TEST et l'iPhone disponibles relèvent de leurs recettes distinctes.
Un SID accepté ne suffit pas : réception sur téléphone, signatures et relecture
fournisseur devront être reliées aux mêmes objets, sans exposer le code.

Une opération déjà réservée peut être en vol lors de la révocation : attendre
son terme et la rapprocher avant clôture. Ne pas remettre à zéro le ledger,
réactiver une capacité usagée ou reclasser des comptes TEST en non TEST.
