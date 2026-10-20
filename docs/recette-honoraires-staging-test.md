# Recette d’émission d’honoraires en STAGE

L’admission est fermée par défaut : ni son installation ni le déploiement du
worker n’allouent de capacité ou ne déclenchent une génération. Le résultat de
chaque campagne doit être consigné séparément avec son commit et ses preuves.

## Périmètre et différence avec le parcours réel

Le scénario vise une mission TEST existante, privée, LIBERAL / TAUX_HORAIRE /
FINALE_UNIQUE, avec contrat signé et mandat actif. La clôture et la validation
des présences doivent être faites par les écrans habituels. Leur trigger crée
la demande 1075. L’admission ne crée ni ne modifie une mission ou une demande.

`{ "mode": "demandes-test" }` appelle une réservation dédiée dans **la même
file** `private.demandes_facturation_honoraires`. Elle prend le vrai bail,
appelle `generate-invoice`, puis `fn_constater_demande_facturation_honoraires`.
La génération garde la réservation, la numérotation, le bail documentaire,
PDF/XML, les snapshots et la commission canoniques. Le sélecteur des missions
réelles et le calendrier restent inchangés. Le prédicat TEST continue à renvoyer
`false` ; l’admission explicite ne prétend pas valider le sélecteur de production.

Ce scénario prouve le traitement automatique d’une demande après clôture,
déclenché par un appel opérateur du worker. Il ne prouve ni le déclenchement
temporel de pg_cron, ni HEBDO_ET_FINALE, ni une livraison email, ni un paiement.
La recette TEST n’active aucun cron.

## Fermeture et garde d’admission

Le script `scripts/ci/honoraires-staging-test.sql` est un supplément STAGE,
pas une migration de production. Il crée une table vide, sans activation,
deux fonctions et un trigger d’immuabilité. Il doit être appliqué dans une
transaction opérateur revue, sur le seul projet `mejpriaetwgtcstbgfid`, après
comparaison de ses empreintes avec les sources approuvées. Aucune règle
d’installation automatique ou modification des workflows n’est ajoutée.

Avant même la création du client Supabase, ce mode exige l’URL STAGE exacte,
une clé service présentée dans `Authorization: Bearer …`, et une configuration
temporaire exacte. Le secret d’automatisation seul ne suffit pas. La RPC impose
à nouveau le rôle service, l’identité STAGE et la capacité. Aucun droit de table
n’est accordé au service, à anon ou à authenticated.

La capacité désigne une seule mission, le soignant
`abba3c93-5408-47bf-96e3-0864c7de3cb7`, l’établissement
`fcaa6c97-46c1-4da9-8f74-1395aed616c5`, leur owner Auth de cohorte exact,
un SHA de source et un manifeste revus, et une fenêtre non prolongeable de
60 minutes maximum. Le SHA de configuration est une liaison au reçu de
déploiement, pas une preuve autonome du code déployé.

À chaque prise et juste avant invocation : profils/Auth toujours TEST, actifs,
non supprimés, contrat signé et hashé, régime/TVA/mandat inchangés, aucun
opt-in de cession automatique Defacto, établissement
privé sans Chorus, absence de mouvement/claim financier de cette mission,
crons tous inactifs, aucun cron en cours ni requête pg_net en attente, gate
Connect fermée et autres capacités SMS/Connect fermées. Les variables runtime
des admissions Stripe, SMS et email doivent également être absentes. Leur
absence sur **toutes** les fonctions concernées sera prouvée par l’opérateur ;
la lecture de l’environnement du worker seul ne prouve pas les autres Edge.

La première prise exige zéro FH/FC. Le compteur d’invocation est consommé
durablement avant l’appel. Une réponse perdue ne permet pas un second appel.
Pendant un bail actif, le rejeu renvoie 409 sans acquitter un travail en cours.
Après expiration du bail ou du délai de reprise, il prend un nouveau bail
uniquement pour le constat des pièces existantes. Une absence de pièces reste
un échec visible : ne pas réallouer, réinitialiser ou régénérer pour le masquer.
Une mission ne peut recevoir une seconde capacité dans cette table.

## Ordre opérateur à préparer après revue et tests

1. Confirmer le main/source déployé du worker, du générateur et de leurs helpers,
   les trois corps SQL 1075, leurs droits, le projet API et l’identité DB STAGE.
   Vérifier les autres capacités/variables fermées et l’exclusivité de campagne.
   Installer le supplément vide dans une transaction distincte, vérifier table
   vide, RLS/owner/ACL et garder les empreintes des objets préexistants.
2. Choisir une mission existante convenable dans la cohorte. Ne pas clôturer
   une fixture historique par commodité : relire contrat, plannings et preuves
   attachées. Aucun nouveau SMS, paiement ou changement de flags TEST.
3. Conserver l’état avant clôture et les empreintes hors mission. Valider les
   présences puis terminer via l’UI établissement ; recharger. Observer une
   demande durable, zéro FH/FC, absence de bail et de génération engagée.
4. Lier un UUID neuf, le SHA approuvé, le SHA du manifeste, cette mission et une
   fenêtre fraîche dans une copie opérateur. Le JSON runtime contient exactement
   `capabilityId`, `missionId`, `sourceSha`, `manifestSha256`, `createdAt`,
   `expiresAt`. Les timestamps correspondent exactement à la ligne SQL. Aucune
   valeur n’est fournie par cette préparation ; runtime absent = fermé.
   La ligne est d’abord désactivée, puis l’activation exige un preview rollback
   et une revue indépendante des bindings. Aucun helper d’allocation ouvert.
5. Faire un seul POST service `{ "mode": "demandes-test" }` sur le worker.
   Conserver l’intention durable et la réponse brute avant décodage. Ni retry HTTP
   automatique, ni appel direct au générateur, ni lancement du cron global.
6. Lire demande terminée, FH originale/finale unique, FC unique liée, numéros,
   heures/tarif et snapshots, version PDF/XML et chemins. Télécharger les deux
   fichiers et comparer leurs octets aux hashes SQL. Ouvrir les pièces dans les
   interfaces soignant/établissement et recharger, sur les formats requis.
7. Rejouer le même mode dans la fenêtre. Vérifier mêmes FH/FC/version/numéros,
   aucune nouvelle génération, aucun changement hors mission. Les lignes
   documentaires d’émission en file sont attendues du générateur canonique ;
   leur présence ne prouve aucun email envoyé. Vérifier explicitement zéro
   envoi email/SMS et zéro opération financière nouveaux.
8. Révoquer cette seule capacité (`enabled=false`, `revoked_at` présent),
   retirer le runtime et prouver le refus. Conserver lignes, pièces et historique.
   Aucun DELETE de capacité, réouverture ou prolongation de fenêtre.

## Vérifications ciblées

- `tests/node/honoraires-staging-test.node.mjs` : vrai handler/client/helpers,
  transports simulés ; refus avant SQL, portée exacte, budget avant invocation,
  réponse perdue, replay sans génération, constat obligatoire.
- `tests/node/demandes-facturation-honoraires.node.mjs` : assertions normales
  conservées ; seul chargement du nouveau module ajouté au banc.
- `tests/security/honoraires-staging-test-isolated.test.sql` : base PG17 vide
  avec `jolene.isolated_sql_test=on`, rollback intégral. Vrai trigger/producteur,
  prédicat canonique, demandes/baux/constat, ACL, refus cohorte/projet/transport,
  budget irréversible et reprise du constat. Les documents SQL sont des fixtures,
  pas une preuve PDF réelle. Aucun provider ou transport réseau dans ce banc.

Les suites utilisent des transports simulés ou une base jetable. Leur réussite
ne remplace pas la campagne intégrée décrite ci-dessus : les documents doivent
être réellement générés, téléchargés et relus dans l’interface avant d’annoncer
cette étape validée.
