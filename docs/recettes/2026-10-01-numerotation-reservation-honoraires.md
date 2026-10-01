# Numérotation et reprise de génération des honoraires

## Défaut et périmètre

Les anciens générateurs utilisaient huit caractères du SIRET ou de l’UUID du
soignant. Deux émetteurs pouvaient donc produire le même numéro, alors que
l’unicité de `factures_honoraires.numero_facture` est globale. Un appel RPC isolé
à `next_invoice_number` ne réservait rien : l’INSERT Edge intervenait dans une
transaction suivante. Enfin `lpad(...,5)` tronquait une séquence à six chiffres.

Le contrôle agrégé production du 1er octobre a constaté trois factures JOL,
un émetteur et aucune collision présente. Il ne démontre pas l’absence du
risque. Aucune pièce ni donnée individuelle n’a été modifiée. Les définitions
et droits des deux générateurs ont été lus avant modification ; le préflight de
la migration exige ces identités exactes. La source Edge LIVE v678 correspond
à la base du lot, à un saut de ligne final près.

La nouvelle série utilise l’UUID complet sans tirets, l’année et la séquence
historique du même émetteur, avec au moins cinq chiffres. Les numéros déjà
attribués restent inchangés. Les producteurs SQL d’avoirs/remplacements gardent
leur transaction existante ; la réservation Edge insère désormais le numéro et
la pièce dans une seule transaction. Aucun montant, TVA ou règle de correction
comptable n’est modifié.

## Réservation, bail et émission

- `fn_reserver_facture_honoraires` est réservée au JWT service et à son ACL.
  Elle verrouille mission puis pièce, vérifie les parties et la période, fixe
  numéro/type/nature/statut côté SQL et conserve l’INSERT métier ordinaire.
- Une pièce canonique retrouvée conserve ses snapshots. Un historique ambigu
  ou une période différente refuse explicitement. Un remplacement en attente
  se génère par son identifiant, jamais comme un nouvel original de mission.
- `fn_acquerir_generation_honoraires` acquiert un bail privé de dix minutes,
  avec token serveur qui ne sort pas dans la réponse HTTP utilisateur. Un bail
  actif refuse un deuxième rendu. Une erreur ou un bail expiré se reprend sur
  la même pièce et le même numéro, avec un nouveau token.
- La finalisation verrouille mission, pièce puis bail. Seul le token courant et non
  expiré peut inscrire les références/hashes, le registre et l’émission dans
  la même transaction. Un succès acquis reste rejouable après expiration ;
  son échec tardif ne rétrograde pas la pièce. Un ancien renderer ne peut ni
  finaliser ni marquer en erreur après réattribution du bail.
- Le renderer relit les snapshots persistés dès la première génération. Les
  références PDF longues sont repliées selon les métriques de la police ;
  textes, noms et numéros restent exacts. PDF et XML sont deux fichiers séparés.

Un upload partiel ou un renderer expiré peut laisser un objet Storage non
référencé. Le bail protège l’émission ; il ne supprime pas arbitrairement ces
objets. Une régénération volontaire d’une pièce déjà émise conserve le mécanisme
historique de nouvelles versions, distinct de la reprise de première émission.

## Preuves locales acquises

Dossier privé de preuves : `/private/tmp/jolene-numerotation-validation-20261001`.

| Contrôle | Résultat et portée |
|---|---|
| Handler réel, PDF/XML, réservation et pannes | 24 tests Node verts ; IO Supabase/Storage simulées et fermées |
| Première version du banc | 17/18 : seul le double de commission refusait l’identifiant canonique ; journal conservé, attendu produit inchangé |
| Frontend | 15/15 initiaux puis 5/5 ciblés remplacement émis, chaque passage sans retry, sur iPhone, Android, iPad portrait/paysage et ordinateur |
| Gestes | Téléchargement soignant facture/avoir, remplacement établissement avant paiement, refus et reprise, rechargement |
| Numéros affichés | Série complète avec six chiffres, numéro conservé en PDF/XML ; lecture PDF supplémentaire jusqu’à 19 chiffres |
| Mise en page | Référence avoir avant correction dépassant x=586,51 pour une marge à 545 ; référence de pièce remplacée atteignant x=672,01. Témoins conservés |
| Après correction | Six PDF, neuf pages facture/avoir/rectificative : caractères dans les marges ; captures d’identité Unicode et page suivante inspectées |
| TypeScript/Vite | Typage et compilation web verts ; aucun SDK ni dépendance installé |
| Catalogue indépendant | 18 tests Node verts, transport simulé ; erreurs, clés inattendues, compteurs et DDL divergents refusés |
| Raccord et verrous | 100 tests Node verts : parité des quatre corps, inventaire historique, deux bases Git, catalogues et synchronisation/portées CI ; aucune exécution PostgreSQL dans ces tests |
| Sources SQL | Migration réservation 27 instructions/7 corps PLpgSQL ; ordre des quatre commissions 6/6 ; témoin staging 8/1 ; matrice F1 14/5 ; catalogue 4/0 parsés |

La reprise d’un remplacement déjà émis ou payé appelait le préparateur de
commission originale. Quatre témoins du vrai handler ont reproduit le refus
erroné ; le choix suit désormais la nature canonique de la pièce. Les quatre
cas émission/paiement × lecture initiale/course de réservation passent sans
rendu, version, notification ou émission supplémentaire. Le parcours ciblé
exécute cette reprise dans le handler, puis les gestes existants de consultation,
téléchargement et rechargement ; aucun bouton de génération n’a été inventé.
Les 71 contrôles Node du gel précédent passent ; le journal rouge puis les
journaux corrigés restent séparés.

Les cinq formats sont des simulations de navigateur, pas des appareils
physiques. Le frontend est réel et télécharge les octets produits par le vrai
handler local ; ses lectures REST et son Storage restent simulés. Cette preuve
ne certifie ni PDF/A-3, ni conformité Factur-X, ni intégration cloud.

## Contrôles CI préparés, non encore exécutés pour ce lot

Le job `numerotation-concurrence` utilise PostgreSQL officiel 17.6 éphémère,
loopback, image figée. Il charge la migration entière, les vrais types/tables de
pièces, index actifs, trigger de période et émetteur du snapshot. Ses tables
annexes minimales ne représentent pas toutes les RLS ni tous les triggers
Supabase. Il conserve les témoins historiques de collision UUID/SIRET, le
passage 99 999 → 100 000 et la conservation intégrale d’une ancienne pièce.

Quatre courses utilisent deux écrivains et une troisième connexion observant
`pg_blocking_pids` : même émetteur/deux missions, même mission, reprise de bail
expiré et finalisation répétée. Les cas séquentiels couvrent snapshots,
historique ambigu, token périmé, expiration, chemin de document erroné,
réponse perdue, avoir/parent exact et droits. Aucun fournisseur n’intervient.

Le raccord de verrous ajoute cinq témoins avant/après : les quatre préparateurs
de commission et le finaliseur de complément. Les anciens préparateurs prennent
une facture avant la mission, alors que la réservation prend la mission avant
la facture. Le complément émis traverse aussi l’advisory de période avant de
lire son origine. Les témoins exigent un interblocage PostgreSQL `40P01` exact,
puis l’émission ou commission unique et le rejeu inchangé après correction.
Un timeout ou une autre erreur ne vaut jamais reproduction. Le cas finaliseur
emploie le vrai émetteur/trigger et le préfixe mission/origine du résolveur,
sans revendiquer l’exécution intégrale du résolveur ni ses RLS.

La migration distincte `20261001160404` prend la mission avant toute pièce dans
les quatre préparateurs. Après retrait des seules lignes de verrouillage et de
relecture, leurs calculs, gardes, écritures et retours sont byte-identiques aux
corps précédents, vérifiés par empreinte. Les propriétaires, droits et registres
sont strictement contrôlés avant et après. La période exige le corps documentaire
8030 installé par main 1010 ; elle ne réadmet pas l’ancien calcul encore observé
sur stage/prod lors de la lecture de métadonnées de 16:02 UTC.

Les blocs d’inventaire historiques de la matrice F1 restent byte-identiques à
1010. Leurs quatre anciennes fonctions exactes sont reconstruites sous contrôle
de corps/définition dans une sous-transaction dédiée ; le rejeu est annulé puis
les quatre définitions, droits, configurations et registres candidats sont
comparés intégralement avant les neuf cas métier inchangés. Le témoin rouge
historique et la migration 1010 ne sont pas modifiés. Le pilote cloud fermé
reste sur son ancienne empreinte : son activation après ce lot exige une
nouvelle revue du catalogue, pas une mise à jour implicite. Le pré-catalogue CI
choisit une seule empreinte selon la présence de la migration d’ordre dans
`BASE_SHA`, vérifié comme commit : c793 avant, c736 après. Le HEAD candidat ne
décide pas de l’attendu ; deux commits Git réels et une base invalide sont testés.

Le témoin `numerotation-factures.test.sql` exerce le graphe métier staging réel
sous sous-transaction annulée : cohorte synthétique TEST, canaux fermés,
planning passé/futur, réservation, panne, reprise, émission unique, notifications
internes et registre. Ses chemins/hashes Storage sont synthétiques : aucun
fichier n’est créé par ce SQL. Il ne revendique pas de mandat ou qualification
réels. Aucune fonction métier distante n’a encore été exécutée pour ce lot.

Le raccord conserve le verrou staging partagé et toutes les suites antérieures.
Le nouveau témoin s’ajoute seulement à la voie avec migration. Avant, puis
indépendamment après succès ou erreur, un `BEGIN READ ONLY` contrôle 29 compteurs,
les fonctions/droits, triggers, inventaire et DDL du bail, ainsi que zéro résidu
F172. Le bail est compté aussi après son futur déploiement ; avant création,
son absence est explicitement empreintée. Toute divergence bloque. Les autres
catalogues préexistants restent obligatoires.

La revue indépendante finale, le témoin PostgreSQL concurrent et le SQL staging
réel demeurent requis avant validation fonctionnelle backend. Le déploiement
Edge doit suivre celui de la migration ; aucune génération production n’est
incluse dans cette recette.
