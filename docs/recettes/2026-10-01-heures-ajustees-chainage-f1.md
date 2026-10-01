# Heures ajustées : commission suivante et clôture F1

Ce candidat est distinct du correctif de taux de PR 1009. Il cherche à reproduire
l’effet d’une correction d’heures sur les commissions documentaires suivantes,
sans traiter le montant prévisionnel de mission comme un solde payable.
Il n’a pas encore été exécuté en SQL. Le raccord pré-migration ajouté reste à relire ;
aucun lancement distant n’est autorisé avant la coordination de publication.

La règle existante est décrite dans `docs/logique-paiements-v1.md`, § 2.2 :
commission libérale = taux figé × honoraires. `docs/cp4-refonte-fn-calculer-financier.md`,
§ 8, distingue la facture, document financier de référence, de l’estimation de
mission. Aucun nouveau taux, régime juridique, paiement ou remboursement n’est
introduit ici.

Le test prépare deux histoires indépendantes sous rollback : deux semaines
passées, chacune avec 4 h prévues et 4 h effectives fermées, à 20 €/h. La première
facture de 80 € et sa commission de 12 € HT sont émises par les vrais helpers SQL.
Le vrai résolveur administrateur reçoit le payload UI `heures=3, taux=20` et crée
un remplacement de 60 €, puis le helper de commission émet 9 € HT. Cette correction
est tardive : la seconde semaine est déjà effectuée lorsque la première est corrigée.

1. La seconde facture est émise comme période intermédiaire sur la mission EN_COURS.
2. Dans une autre transaction interne, l’établissement appelle la vraie RPC
   `fn_terminer_mission`, sans clôture anticipée ; la seconde facture est finale.

Dans les deux cas, les attendus documentaires sont indépendants : facture suivante
80 €, commission suivante 12 € HT + 2,40 € TVA = 14,40 € TTC ; cumul actif des
honoraires 140 € ; cumul des commissions 21 € HT + 4,20 € TVA = 25,20 € TTC.
Le cumul RPC, la liaison de la finale, l’idempotence et l’absence de changement
des deux premières pièces sont contrôlés. Les agrégats de mission sont relevés
comme diagnostic ; le test ne les écrit pas pour les forcer à ces soldes.
Les deux observations sont recueillies, chacune annulée, puis une exception
finale signale toute divergence. Une préparation refusée échoue immédiatement.

L’analyse statique prévoit 10,50 € HT dans la première histoire : le helper actuel
applique `21 × 80 / 160`. Après clôture, le trigger peut restaurer 24 € de commission
prévisionnelle, et la finale réclamer `24 − 9 = 15 € HT`. Ce sont des hypothèses à
mesurer en CI, pas des résultats déjà obtenus. La simulation frontend distincte
a déjà montré la formule contradictoire « 15 % × 160 € » avec 21 € affichés dans
les cinq formats ; aucune intégration SQL n’est déduite de cette simulation.

Les identités, créneaux et snapshots de taux sont synthétiques. Le seed de
maintenance ne prouve ni attribution, signature, mandat, qualification ni MFA.
`fige_le` reste NULL. La clôture teste les gardes SQL sous claims de l’établissement,
pas une connexion réelle. Les références PDF/XML sont fictives, sans octets,
Storage ni Edge.

Les lectures LIVE staging ont couvert les fonctions financières, les gardes de
clôture, tous les triggers de mission, les compteurs/scorings et les tables de
queue concernées. Les corps et leurs empreintes restent dans les preuves locales.
La clôture enfile deux emails `MISSION_TERMINEE` malgré les préférences fermées :
le test vérifie cet effet transactionnel au lieu d’en prétendre l’absence. La
queue ne voit jamais de COMMIT. Le mandat absent et les factures déjà présentes
écartent le générateur automatique ; l’absence de paiement/préfinancement et de
présence validée écarte l’escrow. Aucun cron actif, trigger désactivé, contexte
forcé ou override de seed n’est admis. Les éventuelles requêtes pg_net de litige
sont annulées ; leur séquence technique peut toutefois consommer un numéro.

Le catalogue candidat contrôle 25 compteurs, les fonctions/triggers et les résidus
des cohortes `f131` et `f141`. Il impose l’empreinte de définition corrigée
`c793ac81eaef0fe18fb5920c9264c675` du helper de remplacement avant toute transaction.
Il est lu avant et après le test, indépendamment du résultat, sous le verrou
staging déjà partagé. La voie test-only exécute les deux bancs sans ouvrir
bootstrap/sync/CLI ; la voie migration conserve les 49 suites précédentes dans
leur ordre et ajoute ce témoin. Le banc à cinq cas de PR 1009 est inchangé.
La publication partira de main après fusion de PR 1009. La voie test-only ne
synchronise rien et refuse un staging dont le helper corrigé est absent. Pour
une PR contenant la migration produit, la synchronisation existante de la base
main vers staging reste seule responsable de cette mise à niveau ; aucun nouveau
déployeur ni reset n’est ajouté.

Après preuve rouge, le correctif envisagé doit rester limité au calcul documentaire
à partir des honoraires et du taux historique, préserver plafond Rist, TVA,
arrondis, idempotence et corrections/avoirs. Les pièces déjà émises et les paiements
ne doivent pas être réécrits. La cohérence du bloc prévisionnel reste un contrôle
séparé ; aucune validation nationale n’est revendiquée par ce témoin.


## Témoin rouge avant la migration produit

Le script `scripts/ci/f1-heures-temoin-avant-migration.mjs` est raccordé uniquement
lorsque la PR ajoute la migration
`20261001102511_aligner_commissions_pieces_et_estimation.sql`. Il s’exécute après
la synchronisation existante de main et le catalogue initial, avant l’application
transactionnelle de la migration candidate. Le verrou staging est inchangé.
Le témoin SQL et son catalogue sont vérifiés par SHA-256 puis envoyés tels quels.

`JF141` est seulement la sentinelle interne qui annule chaque histoire. L’erreur
finale attendue a le SQLSTATE externe `P0001`. Le raccord exige HTTP 400, le format
Management API déjà observé, le préfixe métier exact et les deux diagnostics JSON
complets, dans leur ordre, sans valeur ou champ supplémentaire :

- Intermédiaire : mission après correction 160 € / 21 € HT ; commission suivante
  10,50 € HT / 2,10 € TVA / 12,60 € TTC ; cumuls honoraires 140 € et commissions
  19,50 € HT.
- Finale : même correction, puis mission après clôture 160 € / 24 € HT ; commission
  suivante 15 € HT / 3 € TVA / 18 € TTC ; cumuls honoraires 140 € et commissions
  24 € HT.

Les bruts, TVA et TTC des agrégats sont également comparés strictement. Cette
liste reste une prévision à mesurer : aucun rouge réel de ce témoin n’est encore
revendiqué. Toute autre erreur, succès inattendu, réponse ambiguë ou panne réseau
bloque la suite. Aucun retry de la fixture n’est autorisé.

Une nouvelle requête READ ONLY contrôle ensuite le catalogue et les 25 compteurs,
y compris si la réponse du témoin est perdue. Ils doivent être identiques au
contrôle initial et sans résidus. Ce contrôle indépendant est obligatoire avant
que le script n’accepte la reproduction et que la migration puisse commencer.
Le contrôle `always()` existant après le job SQL reste également en place.
La preuve compacte conserve uniquement les diagnostics synthétiques, les codes
et les empreintes ; elle n’imprime aucun corps fournisseur inconnu ni secret.
Les tests Node utilisent exclusivement des réponses fictives et ne prouvent pas
une exécution PostgreSQL ou une intégration frontend.
