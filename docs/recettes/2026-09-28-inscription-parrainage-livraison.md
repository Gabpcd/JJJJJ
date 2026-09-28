# Inscription, reprise du parrainage et contrôle de livraison

Le dossier soignant, le profil et la complétion Pro Santé Connect présentent deux modes : **Salarié (CDD compris)** et **Libéral**, selon le référentiel professionnel. Les codes historiques CDD, VACATION et SALARIE sont conservés lors d’une sauvegarde sans changement de choix. VACATION n’est plus retiré lorsqu’une profession n’autorise pas le libéral. La complétion PSC restaure aussi les préférences existantes et dispose d’un repère principal accessible.

La création rapide du compte et la navigation libre restent accessibles sans dossier professionnel. Le dossier reste facultatif jusqu’à la candidature. Les simulations couvrent les sauvegardes refusées puis reprises, les changements de profession, la panne du référentiel et les anciennes préférences.

## Parrainage

L’ancien hook consommait le code même après une erreur réseau et utilisait un marqueur commun à tous les comptes du navigateur. Il n’était monté que sur le tableau de bord, alors que l’inscription rapide mène à Explorer.

L’attribution est désormais déclenchée dans le cadre soignant une fois le profil réellement disponible. Le code est conservé pendant la découverte et les pannes, les marqueurs sont limités au compte et au code, les requêtes en cours sont partagées entre remontages et les réponses tardives ne consomment pas le code d’une autre session. Les refus métier connus restent définitifs pour ce code ; une réponse inconnue ou une absence d’authentification ne l’est pas.

La vérification des définitions déployées a ensuite trouvé que le trigger de protection annulait `parraine_par` malgré le succès de la RPC. Un contexte transactionnel lié à la relation exacte autorise désormais ce seul champ, en conservant les protections de profession, d’heures et de qualification. L’insertion directe par les utilisateurs est retirée ; la RPC authentifiée reste disponible et une contrainte garantit un seul parrain par filleul. Les comptes inactifs sont refusés. Aucun barème ni versement de prime n’est modifié. Les agrégats production et staging montraient zéro relation avant correction, donc aucune réparation de données historiques n’est effectuée.

Une suite SQL teste le refus d’INSERT direct, les doublons, les profils inactifs et les tentatives de falsification des heures ou du statut libéral. La recette navigateur staging ajoute une attribution avec le véritable JWT du filleul, sa reconnexion et la relecture du lien en base. Les acteurs sont des comptes jetables non vérifiés ; aucun envoi ni prime n’est déclenché. Le nettoyage contrôle la propriété privée, refuse les relations étrangères ou qualifiées et conserve un journal explicite si une création ou attribution reste ambiguë. Ces vérifications distantes doivent être vertes avant fusion ; leur présence dans ce document ne prouve pas encore leur exécution.

Reproduction avant correction : 8 échecs sur 11 cas ciblés. Après correction : 11 cas réussis, plus les deux tests de navigation persistante. Deux parcours navigateur ont passé sur les cinq formats : inscription minimale puis finalisation directement depuis une mission ; panne suivie d’une déconnexion/reconnexion. Les appels HTTP sont simulés et inspectés ; ces résultats ne prouvent pas encore une attribution en base staging ni une prime versée.

## Diagnostic SMS

Le panneau administratif ne présente plus une réponse inconnue comme un succès. Il distingue une demande acceptée avec SID, un envoi non effectué et un résultat incertain. L’acceptation fournisseur ne prétend pas prouver la réception sur le téléphone. Onze tests de logique et six tests des boutons/messages couvrent les réponses attendues et ambiguës, sans SMS réel.

## Livraison et preuves distantes

Le garde mobile exige une preuve de déploiement Supabase réussi compatible avec la source du binaire, y compris lorsque le changement frontend suit un déploiement backend échoué. Les relances partielles réutilisent les derniers états des jobs sans masquer un nouvel échec ou un déploiement intervenant. Le contrôle est répété avant publication d’une mise à jour signée ou soumission aux stores ; son code est extrait du main figé, même pour une ancienne réservation. Il ne constitue pas un verrou atomique contre une opération externe ultérieure.

Le diagnostic manuel des stores lit les états Apple et Google avec les accès CI existants. Il ne crée pas de transaction Play, ne charge aucun binaire et ne publie aucune version. Les états inconnus restent partiels. Voir `scripts/mobile/store-status.md`.

La préparation des futures soumissions iOS attend désormais le traitement du build exact, même s’il a déjà été chargé lors d’une tentative précédente. Elle exige un build valide, non expiré et la déclaration d’exportation attendue. Un remplacement ne retire que la soumission observée en attente, correspondant à la seule version et au seul élément attendus, après une relecture immédiate. Elle attend ensuite la fin effective de l’annulation avant la nouvelle soumission. Une revue commencée, une publication en attente, un état inconnu ou d’autres éléments bloquent l’automatisation. Vingt-quatre groupes de tests hors réseau couvrent ces cas ; aucun retrait ni chargement Apple n’a été effectué pour les tester. Apple n’offre pas de condition atomique sur l’état lors de l’annulation : une transition entre la dernière lecture et la requête reste possible. Voir `fastlane/README-ios-review.md`.

Le collecteur fournisseurs inventorie uniquement les métadonnées staging et Stripe test, sans modifier les services. Son rapport reste NON_PRET : il documente ce qui manque, sans prétendre que les transports sont autorisés ou que le cycle complet est validé. Voir `scripts/recette-fournisseurs/README.md`.

## Livraison de ce lot

Le numéro mobile reste 1.0.6 (23), déjà soumis à Apple et Google sur une source antérieure. Ce lot n’utilise pas le label OTA et ne réserve pas de nouvelle version. La mise à jour native de l’inscription nécessite une version ultérieure, après lecture de l’état exact des stores. Les corrections présentes dans main ne doivent pas être décrites comme déjà installées sur les téléphones.

Les captures et journaux locaux sont conservés sous `audits/2026-09-28-finalisation` dans le workspace. Les simulations utilisent des fixtures et ne remplacent ni une authentification PSC réelle, ni les signatures/SMS/paiements du cycle intégré, ni les mesures sur appareils physiques.

## Éligibilité professionnelle

Le regroupement des préférences ne modifie aucun seuil ni référentiel d’exercice. Les contrôles serveur de profession, transition libérale, justificatifs et affectation ont été retrouvés actifs en production, avec les mêmes définitions sur staging. Le message des professions sans offre libérale décrit le périmètre de Jolene, sans en déduire une interdiction juridique générale.

La vérification a aussi identifié une limite antérieure : le compteur d’activité ne distingue pas automatiquement toutes les conditions d’ancienneté et d’admissibilité des heures selon installation, remplacement ou autre activité. Le choix kiné de zone reste déclaratif. Cette PR ne prétend pas résoudre ces règles de conventionnement ni certifier l’éligibilité réglementaire complète ; une évolution doit séparer ces preuves du compteur d’activité et faire l’objet d’une recette dédiée.
