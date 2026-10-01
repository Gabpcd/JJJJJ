# Consulter les factures pendant une mission en cours

Une facture hebdomadaire peut être émise avant la fin d’une mission. Sur la base `9ac91fa18c756208423c36d4276f33c3504cc988`, trois parcours ne donnaient pas accès à son PDF : l’échéance « À payer » de l’établissement et les détails de mission des deux parties. Trois simulations ordinateur ont reproduit l’absence du bouton sur cette base.

La page de facturation propose désormais « Consulter la facture PDF » indépendamment de l’action de paiement. Le téléchargeur existant récupère exclusivement l’original archivé via une URL signée ; il ne génère pas de nouvelle pièce. Dans les détails, la carte documentaire n’attend plus le statut TERMINEE. Côté soignant, elle est réservée au soignant assigné à une mission libérale. Les autorisations serveur et les conditions des actions de paiement restent celles existantes.

## Vérification

Sur iPhone, Android, iPad portrait, iPad paysage et ordinateur, les trois surfaces sont parcourues avec une mission EN_COURS. La simulation vérifie le PDF original et, dans les détails, l’avoir existant, une panne de téléchargement503 avec message entièrement visible, une nouvelle tentative, un rechargement puis les mêmes téléchargements. Les empreintes des fichiers téléchargés correspondent aux vrais octets PDF produits par le banc. Aucune action de paiement, d’émission ou de fin de mission n’est permise par le transport simulé.

Les échanges Auth/REST/Storage sont fictifs et fermés. Les trois appels automatiques du chat (présence, obtention de conversation, lecture des messages) reçoivent explicitement des réponses inertes : cette recette n’en prouve pas les écritures réelles. Les gardes RLS, les fournisseurs et les appareils physiques ne sont pas validés par ces simulations.

Résultat local final (v5) : quinze cas réussis en99,846s, cinquante téléchargements, aucun retry, saut ou cas instable. Les captures ont révélé un créneau de fixture artificiellement étiré sur la période entière ; la fixture finale comporte deux créneaux prévisionnels de quatre heures, un effectif de quatre heures et le compteur de deux créneaux. La nouvelle matrice confirme «2 créneaux ·8h au total», sans modifier le code produit. Le diff des trois pages et du spec validé porte le SHA256 `d980daa72053ae70087a3e673bfa18abedabe691c4afd315fb84bf2dc508d8c3`. Revue indépendante : CLÔTURABLE.

Les témoins rouges, deux passages interrompus par manque d’espace et la correction de la liste d’appels autorisés sont conservés sous `/private/tmp/jolene-f1-ui-acces-tests-20261001`. Ils ne sont pas présentés comme des validations réussies. Compilation TypeScript, douze tests unitaires existants de carte/résumé documentaire et dix-sept garde-fous réussis.

Aucune livraison mobile, mise à jour OTA ou soumission aux stores n’est déclenchée par ce lot.
