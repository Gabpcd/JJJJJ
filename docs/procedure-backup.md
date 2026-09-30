# Sauvegarde et reprise — Jolene

État documentaire : 30 septembre 2026. Cette procédure décrit les contrôles et
l'exercice à réaliser ; elle ne constitue pas une preuve de sauvegarde active ni
de restauration réussie. Aucun exercice de restauration n'est attesté ici.

## Configuration à relever avant toute décision

La [documentation Supabase sur les sauvegardes](https://supabase.com/docs/guides/platform/backups)
distingue sauvegardes quotidiennes et **PITR, add-on à activer**. La formule Pro
n'implique pas que PITR soit actif. Les sauvegardes quotidiennes et la durée
réellement disponible se vérifient dans le dashboard ; ne pas les déduire du
nom de la formule. Quand PITR est activé, il remplace les sauvegardes quotidiennes.

Consigner, sans clé ni donnée personnelle :

- projet, région, version PostgreSQL et date du relevé ;
- formule, mode de sauvegarde actif, rétention et points restaurables visibles ;
- dates du dernier backup réussi et du dernier contrôle ;
- accès des responsables habilités et accès de secours ;
- méthode de restauration choisie : projet existant ou clone séparé ;
- inventaire des buckets, règles d'accès et stockage de secours existant.

Utiliser le dashboard ou la Management API en lecture seule pour l'inventaire.
Une capture des réglages prouve la configuration, pas la restaurabilité. Une
nouvelle option payante doit faire l'objet d'une décision chiffrée avant achat.

Après déploiement du workflow manuel `backup-status.yml`, le relevé non sensible
peut être demandé avec `gh workflow run backup-status.yml --ref main`.
L'artefact ne remplace ni le contrôle des fichiers Storage ni l'exercice ci-dessous.

## Objectifs à mesurer

| Objectif | Cible interne | État |
|---|---|---|
| Perte de données maximale (RPO) | 5 minutes | Non démontrée ; dépend du mode actif et du dernier point effectivement restaurable |
| Retour au service (RTO) | 4 heures | Non démontré ; à mesurer de la décision de reprise à la recette frontend terminée |

Ne pas annoncer ces cibles comme garanties du fournisseur. Mesurer séparément
restauration DB, récupération des fichiers, remise en place des intégrations et
recette. Une restauration peut rendre le projet inaccessible pendant l'opération.

## Exercice isolé, avant de s'appuyer sur le plan

1. **Préparer le périmètre.** Responsable, remplaçant, projet source et destination
   nommés ; estimation du coût, durée et critère d'arrêt. Utiliser d'abord un jeu
   synthétique. Une copie de production contient des données privées et exige
   des accès et une conservation adaptés ; ne pas l'utiliser comme staging public.
2. **Isoler avant activation.** Préparer un projet de restauration distinct et
   vérifier la méthode officielle [Restore to a new project](https://supabase.com/docs/guides/platform/clone-project).
   Empêcher les jobs, webhooks, emails, SMS, push et paiements sortants restaurés
   de viser des utilisateurs ou fournisseurs réels. Inventorier aussi les
   commandes cron et références Vault embarquées dans la base. Le clone physique
   restaure aussi les secrets Vault et les extensions : les jobs peuvent repartir
   dès sa restauration, sans étape préalable permettant de les suspendre.
   Si l'absence
   d'effets externes au démarrage n'est pas démontrable, arrêter avant la création
   du clone. Préparer un environnement synthétique sans intégration réelle, ou
   une restauration logique expurgée et revue selon la procédure officielle ;
   cette dernière ne prouve pas à elle seule le fonctionnement de PITR.
3. **Établir le témoin.** Dans l'environnement synthétique, conserver un manifeste
   d'identifiants et de hashes : comptes des rôles concernés, mission, contrat,
   présences, document financier et fichiers originaux. Un événement postérieur
   au point de sauvegarde sert de témoin de la borne temporelle.
4. **Restaurer la base isolée.** Choisir un point disponible, noter heures de début
   et de fin, comparer les lignes attendues, contraintes et permissions. Vérifier
   séparément Auth, RLS, Storage, extensions, crons et intégrations : le schéma
   seul ne valide pas tout le projet. Une branche de développement n'est pas, à
   elle seule, une preuve de restauration d'un backup.
5. **Restaurer les fichiers.** Suivre l'inventaire Storage ci-dessous et comparer
   les octets au manifeste. Les métadonnées DB ne remplacent pas les objets.
6. **Reconfigurer la destination.** Déployer les Edge Functions versionnées via le
   chemin CI prévu ; rétablir les seuls secrets de test nécessaires depuis le
   coffre existant, sans les exporter dans un rapport. Configurer une preview
   frontend isolée avec l'URL et la clé publique de la destination. Changer ces
   variables Vercel n'est pas une opération DNS. Un restore sur place ne change
   pas systématiquement l'identifiant projet ; un clone est une destination
   distincte. Vérifier URLs de callback, CORS et configuration fournisseur test.
7. **Recetter l'interface.** Connexion soignant/établissement et admin si concerné ;
   lecture de la même mission, contrat, planning, présences et document ;
   téléchargement du fichier original et refus d'accès d'un tiers. Vérifier
   résultats, messages, onglets, erreurs et reprise après rechargement sur
   iPhone, Android, iPad portrait/paysage et ordinateur en simulation. Rapprocher
   les mêmes objets en backend. Une simulation API ne prouve pas la restauration.
8. **Clore avec preuves.** Noter RPO/RTO observés, différences et limites ; conserver
   manifeste non sensible, assertions UI et résultat de rapprochement. Désactiver
   ou supprimer exclusivement les ressources de l'exercice selon le plan validé,
   après conservation des preuves et contrôle des dépendances. L'exercice ne
   modifie ni le trafic ni les données de production.

## Storage : sauvegarder les octets originaux

Les sauvegardes DB Supabase ne contiennent **pas** les objets Storage. Un restore
DB ne récupère donc pas un fichier supprimé après le point de sauvegarde.

Inventorier les buckets actuels et leurs usages, y compris pièces de dossier,
contrats/signatures, factures et copies de bulletins employeur. La régénération
d'un PDF calculé ne reconstitue pas une pièce originale ni une signature.

Pour chaque classe : consigner la fréquence de copie réellement configurée, la
rétention, le chiffrement, les personnes habilitées, les hashes et le résultat
d'un téléchargement restauré. Vérifier qu'une suppression accidentelle ne se
réplique pas immédiatement sur toutes les copies. Aucun outil, bucket de secours
ni cron rclone opérationnel n'est attesté par ce document. Une copie mensuelle
ne suffit pas à soutenir l'objectif de RPO de cinq minutes.

Les purges de sauvegardes doivent suivre la politique de conservation applicable
et les accès privés ; ne pas conserver indéfiniment les copies par défaut.

## Incident réel

Suivre [incident-response.md](incident-response.md), circonscrire l'impact et
choisir restauration ou correction en avant. Une restauration de production
remplace des données et interrompt potentiellement le service : préparer la
cible, le point retenu, les écarts récents à rapprocher et la décision explicite
avant l'action. Ne jamais importer un CSV approximatif directement en production.

Les migrations suivent le chemin CI `deploy-supabase` imposé par `CLAUDE.md`.
Seul un incident avéré relève de son exception de hotfix, avec recapture et
traçabilité le jour même. Ne pas remettre en marche un paiement, webhook ou cron
financier sans rapprochement des événements arrivés pendant l'interruption.

Le retour au service exige une recette frontend reliée au backend restauré,
puis le suivi des erreurs et des files. La communication aux utilisateurs passe
par les canaux autorisés et les responsables désignés.

## Fréquence et éléments restant à confirmer

- Avant de déclarer la reprise maîtrisée : inventaire réel + premier exercice isolé.
- Après changement important d'infrastructure : revoir le plan et ses accès.
- Trimestriellement : refaire un exercice borné et conserver les mesures.
- Annuellement : tester aussi l'indisponibilité du responsable principal.

Restent à établir : configuration effective, copie Storage, accès de secours,
responsables/astreinte, sauvegarde des réglages hors DB et mesures de restauration.
Les coordonnées et engagements de support fournisseurs sont à vérifier dans les
contrats/dashboards existants ; aucune durée de réponse n'est promise ici.
