# Banc D2 — deux candidatures salariées, préparation locale

Base : intégration `1e898d4b`. Ce lot distinct ne livre ni capacité nationale,
ni charge D distante, ni émission F. Aucun compte distant créé pendant son
implémentation. Les simulations UI utilisent des réponses simulées.

## Périmètre exact

Deux AS SALARIE test non vérifiés, prénom/nom/date de naissance/téléphone
fictifs suffisants pour candidater ; aucune vérification d’identité, diplôme,
RPPS ou document déclarée acquise. Un établissement CLINIQUE_PRIVEE test
EN_ATTENTE, sans publication, contrat signé, SEPA ou Chorus. Une mission
OUVERTE/CANDIDATURE, non urgente et non affectée ; un créneau futur de quatre
heures (09–13 UTC). C’est un seed de recette sous rôle serveur, pas une preuve
que cet établissement est autorisé à publier.

k6 : deux VUs, une itération chacun, 60 s maximum, aucun override. Chaque VU
appelle `fn_confirmer_action_planning_v1` comme le frontend : POSTULER, planning
exact, contrat demandé null (résolu SALARIE), message marqueur du run. Les deux
lignes EN_ATTENTE doivent être relues par leur propriétaire puis ensemble par
l’établissement. Un HTTP 200 avec erreur, un autre candidat, zéro ligne ou un
setup incomplet ne peut passer. Aucun accepter, contrat, pointage ou paiement.

## Conditions avant la première écriture distante

Le préparateur `scripts/ci/prepare-candidatures-fixture.mjs` expose `catalogue`
(SELECT uniquement), puis `prepare`, `verify` et `cleanup`. Aucun raccord de
préparation D dans `.github/workflows/load-tests.yml` n’est activé par ce lot.
Le sélecteur D ordinaire refuse sans lot privé ; F et all ne deviennent pas verts.
Un mode manuel distinct de preuve SQL annulée est décrit ci-dessous : il ne
prépare aucun compte Auth HTTP et ne lance ni navigateur ni k6.

- Destination unique : staging `mejpriaetwgtcstbgfid`, URL exacte ; aucune
  valeur prod autorisée. Run explicite, nouveau, non réutilisé ; date de mission
  entre un et 31 jours dans le futur. Aucun volume/durée configurable.
- Revue du préflight par le parent, puis exécution future sous le verrou
  `jolene-supabase-staging-writes` commun aux CI SQL. La variable explicite
  `LOAD_D_EXECUTION_APPROUVEE=DEUX_PROFILS` est requise par les actions qui
  touchent des fixtures ; sa présence n’est pas une preuve de revue ou de verrou.
- `LOAD_TEST_RUN_ID`, `LOAD_D_JOUR`, `LOAD_D_MANIFEST` et les trois accès staging
  existants ; mots de passe aléatoires distincts, masqués et transmis uniquement
  par `GITHUB_ENV`. Aucun JWT dans manifestes/rapports. Auth admin create avec
  email déjà confirmé, sans invitation ni signup public ; contrat documenté :
  https://supabase.com/docs/reference/javascript/auth-admin-createuser .
- Zéro cron actif. Catalogue de fonctions public/private, ACL, triggers,
  colonnes/défauts/contraintes figé par empreinte lue sur staging le 30/09.
  Toute différence impose lecture de la nouvelle définition et revue ; aucune
  actualisation automatique d’empreinte. Le hash large peut bloquer aussi une
  migration sans lien direct : c’est volontaire avant ce premier pilote.
- Aucun FK du journal vers les identités/objets jetables ; rôle Management
  avec lecture complète, sans identité utilisateur. Aucun ID/email préexistant,
  aucun reçu de préparation/nettoyage déjà présent.

## Effets externes : ce qui a été lu, ce qui n’est pas affirmé

Aucun interrupteur global d’email n’a été trouvé ou supposé. Les branches LIVE
pertinentes ont été lues avant de figer le catalogue :

| Déclencheur | Condition empêchant son effet externe dans D2 |
|---|---|
| `fn_trg_favori_nouvelle_mission` | Établissement neuf sans favoris ; `app.test_mode=true` empêche de sélectionner un token d’envoi. La définition contient une URL Edge prod : une dérive du contrat bloque le seed. |
| `fn_trg_auto_notify_mission_urgente` | Mission non urgente ; établissement marqué test. |
| `fn_trg_compteur_absences_sans_prevenir` | Statut OUVERTE, jamais ABSENCE ni affectation. |
| `fn_trg_tripwire_premier_mandat_sepa` | Aucun identifiant SEPA et établissement test. |
| `fn_mirror_teleportation_alerte_systeme` | Reçus PREPARE/CLEANUP, jamais TELEPORTATION_DETECTED. |
| Notifications candidature | INSERT in-app uniquement dans la RPC lue ; aucun trigger INSERT d’envoi. Préférences des trois identités email/SMS/push/in-app à false, crons inactifs. |

La policy SELECT missions LIVE autorise la lecture des missions ouvertes par
les soignants compatibles de la même cohorte test, sans exiger VERIFIE pour
ce chemin de lecture. Cela ne constitue pas une vérification métier de l’établissement.

Les écritures SQL préparent exactement deux profils, un établissement, une
mission, un créneau, trois préférences et un reçu immuable. Les candidatures
ajoutent chacune une notification établissement et un rappel documents,
plus un compteur de rate limit par soignant. La limite produit de 20/h est
inchangée. Les données de diagnostic sont projetées sur des champs fixes.

## Nettoyage et reprise

Le manifeste des trois identités, de la mission, du créneau et des reçus est
écrit avant le premier POST. Les IDs des candidatures et notifications sont
attribués par le serveur ; leurs parents, types, messages et cardinalités sont
contrôlés avant de reconnaître ces effets comme appartenant au lot. Chaque compte
passe séparément par planned/auth-created/prepared/cleanup-started/cleaned.
Pas de recréation automatique après erreur. Une création Auth dont la réponse
est perdue et qui apparaît absente reste ambiguë : jamais cleaned par défaut.

Prepare et cleanup partagent un verrou transactionnel du run et des verrous
de tables bornés au staging. Le reçu immuable empêche un seed SQL retardé de
recréer des données après nettoyage. Les empreintes des profils, établissement,
mission et créneau doivent rester identiques (seule dernière activité exclue).
Chaque candidature doit appartenir aux deux soignants et à la mission, porter
le message du run, rester EN_ATTENTE/SALARIE. Notifications attendues non
expédiées seulement ; toute forme NULL inattendue, notamment lien=NULL, est refusée ; files email, tokens push et présence de ces identités
interdits. Dépendances FK inconnues refusées, CASCADE compris ; pas de DELETE
par préfixe. Les seuls objets supprimés sont ceux du manifeste et leurs effets
explicitement reconnus. Auth est supprimée après le nettoyage SQL et une
seconde vérification du marqueur ; un DELETE dont la réponse est perdue se
reprend par GET et contrôle SQL, sans deuxième suppression si déjà absent.

Les audits et reçus sont conservés et comptés. Le statut cleaned n’est écrit
qu’après preuve des zéros Auth/profils/établissement/mission/créneau/préférences/
notifications/compteurs/sessions/identités/candidatures du run.

## Vérifications locales et limites

- 47 tests Node ciblés ; banque complète de 131 tests verte en exécution
  séquentielle. Le premier lancement parallèle a rencontré une erreur de
  transport interne Node 24 (« Unable to deserialize cloned data »), sans
  échec d’assertion métier ; journal conservé séparément. Couverture : scénarios réellement importés avec HTTP en mémoire, deux
  candidatures exactes, résultats négatifs, refus de production/volumes,
  manifestes altérés, réponses perdues, dépendances et canaris secrets.
- SQL et PL/pgSQL des quatre requêtes du préparateur et de la recette rollback analysés par pglast ; aucune exécution SQL
  de fixtures, donc pas de preuve que toutes les contraintes métier passent.
- 15 simulations frontend (trois scénarios × cinq formats), voir
  `recette/2026-09-30-candidatures-deux-as/README.md`. Jeux UI indépendants :
  créneau 09–13 Paris, distinct du créneau UTC du préparateur. Réponses simulées,
  sans connexion staging, fournisseur, ou appareil physique.
- Relecture indépendante ciblée : P2 lien NULL corrigé, delta relu sans nouveau
  P1/P2 ; lecture statique uniquement, sans revue B8 fraîche ni SQL réel.
- TypeScript et ESLint ciblé verts ; actionlint sur les deux workflows vert ;
  17 guards locaux verts. Aucun nouveau build ou installation de dépendances.

Avant tout pilote : revue indépendante du préflight et du cleanup, exécution
SQL sur le schéma courant sous le verrou CI, preuve de création/lectures par
les bons comptes, contrôle frontend réel puis cleanup exact. Aucun résultat
ci-dessus ne prouve le parcours staging D2 ni un volume supérieur à deux.

## Auth : réemploi d’E10 et différence établissement

Même POST admin `/auth/v1/admin/users`, mêmes emails fictifs, mots de passe
aléatoires, `email_confirm:true` et marqueurs test qu’E10. D2 remplace le kind
par CANDIDATURES_D2 et ajoute un ADMIN_ETABLISSEMENT dont `etablissement_id`
doit être exactement son propre ID, contrôlé dans prepare, setup et SQL.
Le seed SQL exige `email_confirmed_at` non NULL. Aucune invitation, téléphone
Auth ou signup public n’est utilisé. Prepare puis setup effectuent chacun
un login par identité : ne pas annoncer exactement trois sessions.

Catalogue relu : `auth.users` ne porte aucun trigger utilisateur INSERT/UPDATE,
seulement AFTER DELETE `trg_auth_user_deleted_cleanup`. Les INSERT explicites
soignants/établissements appellent `trg_init_prefs_soignant` et
`trg_init_prefs_etab` → `fn_trg_init_preferences_notifications` : préférences
initiales true/false/true/true, puis quatre canaux false dans la même transaction.
Les valeurs intermédiaires ne sont donc pas un état commité. Aucun transport
n’a été trouvé dans cette chaîne ; UPDATE préférences ne fait que dater la ligne.

Cela ne prouve pas la configuration des hooks GoTrue/Auth du plan de contrôle
(avant création, token, vérification de mot de passe, messages), ni SMTP.
Avant tout prepare Auth : lecture ciblée de leurs drapeaux et destinations par
un accès autorisé, sans exporter URL privée ou secret, et preuve que les hooks
éventuellement activés ne produisent aucun effet externe pour ces identités.
En l’absence de cette preuve, le pilote reste bloqué ; email_confirm n’est pas
un coupe-circuit universel. Aucun appel fournisseur n’a été réalisé ici.

## Recette SQL réelle préparée, non exécutée

`generate-candidatures-rollback.mjs` génère seulement du SQL, sans client réseau :

```sh
node scripts/ci/generate-candidatures-rollback.mjs suffixe-unique 2026-10-14 > /tmp/jolene-D2-sql-rollback.sql
```

La date doit rester entre un et 31 jours dans le futur lors de son exécution.
Le préfixe de run `sql-d2-` distingue ses IDs et reçus de ceux d’un futur pilote
Auth. Le texte reprend les vrais blocs seed/check/cleanup du préparateur :
INSERT SQL Auth confirmées sans mot de passe ni session, deux POSTULER sous
rôle authenticated, lectures propriétaires/établissement, liens NULL et rôle
Auth absent refusés avant cleanup, nettoyage deux fois, audits conservés,
seed tardif refusé. Une sentinelle dans un sous-bloc annule les écritures même
si un wrapper retire le ROLLBACK externe, puis exige tous les compteurs à zéro,
y compris les reçus annulés de cette preuve synthétique.

Conditions avant exécution : destination staging exacte vérifiée par le runner,
verrou global `jolene-supabase-staging-writes`, revue du texte et des effets,
zéro cron, catalogue correspondant exactement aux constantes versionnées.
Aucun raccord de cette recette au job SQL validate-pr dans ce lot : #1000
applique des migrations qui peuvent modifier l’empreinte globale avant ses
suites. Après sa fusion et synchronisation, relire les définitions changées et
justifier explicitement toute nouvelle empreinte avant de raccorder D2 ; aucune
recapture automatique, garde désactivée ou attente de vert artificiel.

La syntaxe SQL/PLpgSQL est vérifiée localement ; les assertions ci-dessus ne
sont **pas exécutées** et ne constituent encore aucune preuve SQL réelle.
Cette future recette ne prouvera pas Auth HTTP, hooks externes, sessions ni
nettoyage concurrent multi-connexion. Les verrous SQL sont libérés avant les
DELETE Auth HTTP ; `load_cleanup_pending` est un marqueur de reprise, pas une
garde métier. Avant un pilote, le runner doit être isolé et tous les appels
terminés avant cleanup. La concurrence avec un appel encore en vol reste non
validée et ne doit pas être annoncée comme couverte.

## Mode manuel SQL seul, à exécuter après revue

Le workflow existant `load-tests.yml` propose désormais
`candidatures_sql_only=true`, exclusivement avec le scénario
`04-candidatures-simultanees`, et exige `candidatures_sql_date=YYYY-MM-DD`.
Une date sans drapeau, un autre scénario, le mode E, le diagnostic C ou des
overrides sont refusés. Toute sélection D2 SQL exclut les deux jobs k6/E10,
y compris lorsque les paramètres sont invalides. Le verrou global existant
`jolene-supabase-staging-writes` reste détenu pendant le job ; aucune annulation
automatique du run précédent n'est activée.

Ce job vérifie ses paramètres hors réseau puis appelle
`scripts/ci/prove-candidatures-rollback.mjs run`. Il ne charge aucune clé anon
ou service_role, ne synchronise pas les migrations et n'appelle aucun endpoint
Auth. Seul le token Management staging est injecté à l'étape d'exécution.
L'URL et le projet staging sont imposés, les redirections refusées. Les deux
requêtes envoyées à `database/query` sont le SELECT catalogue exact puis le
texte exact de `generate-candidatures-rollback.mjs`, sans réessai automatique.
Le suffixe `ci-GITHUB_RUN_ID-GITHUB_RUN_ATTEMPT` sépare chaque tentative. Le
créneau à 09 h UTC doit être strictement après maintenant + 1 jour et au plus
maintenant + 31 jours ; la même garde existe dans le SQL.

Le succès exige exactement une ligne JSON
`{"preuve":"D2_SQL_ROLLBACK","annule":true}` sans autre champ. HTTP 200,
chaîne `"true"`, ligne supplémentaire, JSON invalide ou réponse perdue ne
peuvent produire de succès. Le contrôle final des zéros, la sentinelle interne
JD201 et le ROLLBACK externe sont conservés. Les lignes métier, notifications
in-app et audits de cette preuve SQL synthétique sont créés puis annulés dans
la transaction ; aucun message n'est expédié. Cela ne modifie pas la règle de
conservation des audits d'un futur pilote Auth HTTP.

Seul `tests/load/results/d2-sql-rollback.json` est téléversé : état fermé,
run/SHA/date/staging, empreintes et SHA256 du SQL si réussite. Ni fichier SQL,
identités, sessions, secrets ni corps d'erreur fournisseur ne sont publiés.
Le job n'installe pas les dépendances de l'application et n'exécute aucun build.

Exemple de commande **à ne lancer qu'après publication de la branche revue**,
sans fusion requise, avec une date encore autorisée lors de l'exécution :

```sh
gh workflow run load-tests.yml --repo Gabpcd/JJJJJ --ref test/candidatures-deux-profils \
  -f scenario=04-candidatures-simultanees \
  -f candidatures_sql_only=true -f candidatures_sql_date=2026-10-07
```

Préflight SELECT effectué séparément le 30/09 à 14:03:57 UTC : les trois hashes
versionnés correspondent, zéro cron actif, zéro FK audit, aucune des sept
migrations #1000 persistée. Le mode peut donc fournir une preuve sur ce
catalogue **avant** leur déploiement ; il n'applique aucune de ces migrations.
Après synchronisation de #1000, sa garde peut refuser le nouveau catalogue :
relire les définitions et justifier le delta, sans recapture automatique.

Validation locale du raccord : 34 tests Node ciblés, puis banque complète
séquentielle 146/146 ; 17 guards, syntaxe Node, ESLint ciblé, actionlint des deux
workflows et `git diff --check` verts. Pglast accepte les 12 instructions SQL
et les deux blocs PL/pgSQL du texte généré. Le test de routage E10 exige aussi
son exclusion en mode D2 ; ses assertions de séquencement restent conservées.
Les tests simulent les réponses Management ; aucune exécution PostgreSQL du
générateur, aucun compte distant ou workflow lancé. Les 15 simulations frontend
antérieures restent une preuve UI indépendante ; ce raccord sans modification
produit n'en ajoute aucune.

## Ancien seed F fermé

`seed_load_test_data=true` reste accepté comme input déprécié pour produire un
refus explicite à la première étape, avant checkout, outils et accès DB.
Les anciens scripts seed/cleanup lèvent une exception et ne contiennent plus
de purge ou création. Les instructions contradictoires de `docs/staging.md`
sont retirées. Aucun reset, bootstrap, purge, cron F ni appel fournisseur n’a
été lancé pour effectuer ce retrait.
