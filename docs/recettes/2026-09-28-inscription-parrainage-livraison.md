# Inscription, reprise du parrainage et contrôle de livraison

Le dossier soignant, le profil et la complétion Pro Santé Connect présentent deux modes : **Salarié (CDD compris)** et **Libéral**, selon le référentiel professionnel. Les codes historiques CDD, VACATION et SALARIE sont conservés lors d’une sauvegarde sans changement de choix. VACATION n’est plus retiré lorsqu’une profession n’autorise pas le libéral. La complétion PSC restaure aussi les préférences existantes et dispose d’un repère principal accessible.

La création rapide du compte et la navigation libre restent accessibles sans dossier professionnel. Le dossier reste facultatif jusqu’à la candidature. Les simulations couvrent les sauvegardes refusées puis reprises, les changements de profession, la panne du référentiel et les anciennes préférences.

## Parrainage

L’ancien hook consommait le code même après une erreur réseau et utilisait un marqueur commun à tous les comptes du navigateur. Il n’était monté que sur le tableau de bord, alors que l’inscription rapide mène à Explorer.

L’attribution est désormais déclenchée dans le cadre soignant une fois le profil réellement disponible. Le code est conservé pendant la découverte et les pannes, les marqueurs sont limités au compte et au code, les requêtes en cours sont partagées entre remontages et les réponses tardives ne consomment pas le code d’une autre session. Les refus métier connus restent définitifs pour ce code ; une réponse inconnue ou une absence d’authentification ne l’est pas. Aucun barème, droit métier ni RPC de parrainage n’est modifié.

Reproduction avant correction : 8 échecs sur 11 cas ciblés. Après correction : 11 cas réussis, plus les deux tests de navigation persistante. Deux parcours navigateur ont passé sur les cinq formats : inscription minimale puis finalisation directement depuis une mission ; panne suivie d’une déconnexion/reconnexion. Les appels HTTP sont simulés et inspectés ; ces résultats ne prouvent pas encore une attribution en base staging ni une prime versée.

## Diagnostic SMS

Le panneau administratif ne présente plus une réponse inconnue comme un succès. Il distingue une demande acceptée avec SID, un envoi non effectué et un résultat incertain. L’acceptation fournisseur ne prétend pas prouver la réception sur le téléphone. Onze tests de logique et six tests des boutons/messages couvrent les réponses attendues et ambiguës, sans SMS réel.

## Livraison et preuves distantes

Le garde mobile exige une preuve de déploiement Supabase réussi compatible avec la source du binaire, y compris lorsque le changement frontend suit un déploiement backend échoué. Les relances partielles réutilisent les derniers états des jobs sans masquer un nouvel échec ou un déploiement intervenant. Le contrôle est répété avant publication d’une mise à jour signée ou soumission aux stores ; son code est extrait du main figé, même pour une ancienne réservation. Il ne constitue pas un verrou atomique contre une opération externe ultérieure.

Le diagnostic manuel des stores lit les états Apple et Google avec les accès CI existants. Il ne crée pas de transaction Play, ne charge aucun binaire et ne publie aucune version. Les états inconnus restent partiels. Voir `scripts/mobile/store-status.md`.

Le collecteur fournisseurs inventorie uniquement les métadonnées staging et Stripe test, sans modifier les services. Son rapport reste NON_PRET : il documente ce qui manque, sans prétendre que les transports sont autorisés ou que le cycle complet est validé. Voir `scripts/recette-fournisseurs/README.md`.

## Livraison de ce lot

Le numéro mobile reste 1.0.6 (23), déjà soumis à Apple et Google sur une source antérieure. Ce lot n’utilise pas le label OTA et ne réserve pas de nouvelle version. La mise à jour native de l’inscription nécessite une version ultérieure, après lecture de l’état exact des stores. Les corrections présentes dans main ne doivent pas être décrites comme déjà installées sur les téléphones.

Les captures et journaux locaux sont conservés sous `audits/2026-09-28-finalisation` dans le workspace. Les simulations utilisent des fixtures et ne remplacent ni une authentification PSC réelle, ni les signatures/SMS/paiements du cycle intégré, ni les mesures sur appareils physiques.
