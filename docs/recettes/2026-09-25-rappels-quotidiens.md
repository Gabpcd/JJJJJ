# Rappels quotidiens : file durable et drain borné

Le mode daily d’email-cron envoyait directement un email et parfois un SMS pour chaque mission J-1, puis deux emails par contrat de travail manquant. Il pouvait dépasser le plafond d’invocations Edge et s’arrêter avant les derniers destinataires. Ce lot supprime ces boucles de transport : une seule transaction prépare les reçus et email_queue, puis le drain existant traite les messages par lots.

## Contrat conservé

Les trois fonctions de sélection et de marquage ont été relues en production, en lecture seule, le 25 septembre : `fn_email_rappels_j1`, `fn_lister_missions_contrat_travail_manquant`, `fn_marquer_rappel_contrat_travail_envoye`. Leurs définitions ne sont pas modifiées.

- J-1 : mission ASSIGNEE, début le lendemain selon CURRENT_DATE, soignant avec email ; heure affichée en Europe/Paris. SMS uniquement avec téléphone et sans refus des deux options SMS, hors compte test. La relecture au transport refuse un ancien téléphone et un rappel ayant dépassé son jour J-1.
- Contrat de travail : fonction canonique des missions SALARIE à venir dans les 36 heures, sans contrat et sans rappel déjà comptabilisé ce jour. Destinataires établissement/soignant et types de templates inchangés.
- Documents expirants, facturation mensuelle, purge GPS, tokens push, médiation et notation gardent leurs fonctions, compteurs et exécution daily. Aucun montant, droit financier ni horaire cron ne change.

## Livraison et reprise

`private.rappels_quotidiens_livraisons` garde l’identité, le contenu et les destinataires du lot. L’unicité porte sur mission, destinataire, nature et jour. La FK différée permet de créer reçu et file dans la même transaction ; une panne d’insertion annule les deux. Un second passage daily ne crée aucun doublon.

Les quatre types de file CRON_DAILY sont traités par un helper dédié. Le serveur relit l’affectation, le début, le régime, l’absence de contrat et le téléphone selon le rappel. Le helper réutilise les scopes et formats d’identité des anciens appels ; la clé idempotente ne varie pas lors d’une reprise. Il transmet les types canoniques aux transports existants, notamment RAPPEL_MISSION_J1 au SMS pour garder son contrôle de préférences. Refus de préférence = ANNULE, sans envoi déclaré. Timeout/pending = EN_ATTENTE. Échec confirmé = ERREUR avec reprise exponentielle de 1 à 60 minutes. Une panne d’acquittement conserve une reprise avec la même identité.

Le reçu et le marquage du contrat sont acquittés dans une transaction, seulement après un succès réel ou son acquittement idempotent. Chaque cible est indépendante. Un succès ne peut pas être rétrogradé par un worker concurrent. Les RPC sont réservées à service_role ; la table privée n’est pas accessible directement aux clients ou à service_role.

Le budget existant continue à limiter le drain à cinq onboarding et vingt messages de file, au plus 25 transports, 40 s pour commencer et 45 s pour interrompre le réseau métier. Il s’applique désormais également au mode all. Daily prépare toute la file sans transport Edge par destinataire. Ses compteurs indiquent explicitement les mises en file, jamais des emails prétendument envoyés.

## Vérifications effectuées

- **41/41 unités** : sept tests du véritable handler daily avec transports/RPC strictement simulés, six du drain, douze du budget et seize gardes P0. Un lot de 120 reçus est entièrement écoulé en six passages de vingt ; répétition daily, mode all, timeout, 503, refus de préférence et acquittement perdu sont couverts. Le garde source P0 suit maintenant le compteur du drain et le nouveau helper, sans supprimer le contrôle pending avant acquittement.
- **SQL local PGlite** : définitions de sélection LIVE, schéma réduit explicitement annoncé, double application de migration, 120 reçus, panne de file atomique, unicité, droits, contenu inchangé au retry, backoff, SMS désactivé/téléphone changé, désassignation, passage de jour J-1 et comptabilisation indépendante des contrats. Toutes les fixtures sont annulées. Ce préflight ne remplace pas PostgreSQL staging complet.
- ESLint ciblé, TypeScript applicatif et contrôle des espaces du diff : verts.
- Revue indépendante Banach : P2 « demain après minuit » corrigé et fermé ; aucun autre P1/P2 démontré sur le delta.

`tests/security/rappels-quotidiens-file.test.sql` est intégré à validate-pr pour le test PostgreSQL staging sous transaction. **Son résultat CI réel reste à obtenir sur le SHA final.** Aucun email/SMS réel, aucune migration distante ou activation de cron n’a été effectué pendant ce lot.

La mise en file évite l’abandon dû au plafond Edge ; elle ne prouve pas un débit national. Les rappels partagent les vingt places par minute avec les autres messages. Le volume en attente et son ancienneté doivent rester visibles ; un J-1 expiré est annulé plutôt qu’envoyé avec un texte temporel faux. Les autres traitements SQL daily ne deviennent pas, par ce changement, une preuve de durée totale bornée.
