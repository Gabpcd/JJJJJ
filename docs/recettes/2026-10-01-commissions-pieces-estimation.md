# Commissions des pièces et estimation de mission

Candidat testé localement, non exécuté contre PostgreSQL. Les 35 simulations
frontend sont vertes ; la preuve SQL en CI reste attendue. Le témoin précédent reste
byte-identique : SHA-256 `66beb3a107d9151d7a1fdd16183370e5cd1daef1bd56aa4c3786a3f3b22039d4`.
Aucun paiement réel ou Stripe TEST n’est revendiqué par ce lot.

## Comportement corrigé

Après correction tardive de 4 h à 3 h sur la première semaine, la pièce de 80 €
est remplacée par 60 € et sa commission par 9 € HT. La seconde semaine reste à
80 € et doit porter 12 € HT de commission. Le cumul documentaire est 140 €
d’honoraires et 21 € HT de commission, soit 165,20 € TTC au total pour
l’établissement, avec les honoraires exonérés de cette fixture.

Le planning reste à 8 h × 20 € = 160 €. On ne remplace pas ce montant par 140 € :
`fn_calculer_montant_periode` en dépend encore et attribuerait à tort 70 € à
chaque moitié. Les colonnes de mission restent donc estimatives et cohérentes :
160 € / 24 € HT / 4,80 € TVA / 28,80 € TTC. Elles ne sont pas la dette des pièces.
Cette séparation reprend `docs/logique-paiements-v1.md` § 2.2 et
`docs/cp4-refonte-fn-calculer-financier.md` § 8 ; aucun nouveau barème n’est ajouté.

Deux fonctions seulement changent, à partir de leurs corps LIVE conservés localement :

- `fn_preparer_facture_commission_periode` calcule la commission sur le HT de la
  pièce et le taux figé de mission, avec repli sur le taux déjà stocké. La finale
  somme les honoraires actifs signés et leurs commissions ; elle ne solde plus
  le budget prévisionnel. Seuls les centimes d’arrondi peuvent être lissés.
- `dec_calculer_commission` maintient aussi la cohérence des estimations libérales
  EN_COURS, après le trigger de calcul du planning. La branche TERMINEE existante
  reste inchangée. Aucun recalcul massif de missions ou de pièces n’est lancé.

Une finale refuse explicitement une pièce antérieure sans commission, avec des
commissions ambiguës ou incohérentes, ou un écart historique dépassant les
arrondis. Elle ne répare pas silencieusement cet historique. Les verrous,
permissions, retours idempotents et le helper de remplacement corrigé `c793…`
restent en place. La TVA de commission demeure calculée par pièce à 20 % ; la
TVA d’une pièce déjà émise n’est pas compensée dans la suivante.

## Lecture des montants dans l’interface

Le KPI principal de MesGains et son graphique libéral reposent sur les pièces
actives TTC, avec avoirs déduits et remplacements exclus, selon la date d’émission.
Le lecteur RLS exige le nombre exact de lignes, poursuit les pages plafonnées et
refuse un total incomplet, variable ou dupliqué. Un zéro exige une lecture
exhaustive prouvée. Les estimations du planning et les paiements restent distincts.
Le CSV existant exporte toujours le planning, désormais nommé explicitement.

La décomposition établissement qualifie sa commission d’estimation. Le coût de
la carte À payer utilise déjà les obligations documentaires dans le snapshot
source ; le corps LIVE de ce RPC n’a pas été relu dans ce lot. La simulation ne
sera pas présentée comme une preuve de ce RPC distant.

Un autre lecteur reste ouvert : `WorkflowPaiementMission` affiche le
`montant_soignant` de `fn_mode_paiement_mission` comme « Honoraires à verser ».
Le snapshot de cette fonction lit encore le `net_a_payer` estimatif de mission.
Ce candidat ne corrige pas ce chemin de paiement et ne valide donc pas son solde
après une correction documentaire. Le cas établissement vérifie les obligations
et la décomposition prévisionnelle, sans cliquer sur un paiement.

## Défilement des menus

Les cinq formats ont reproduit une remise à zéro du défilement lors de
l'ouverture du Select de période : `body { height:100% }` combiné au verrou
`overflow:hidden` de Radix ramenait la hauteur défilable à celle de l'écran.
La règle `body[data-scroll-locked] { height:auto }` conserve la hauteur du
contenu pendant ce verrou. Elle ne retire ni le verrou, ni la compensation de
scrollbar, ni le focus. Le compteur imbriqué du Select dans un dialogue est
également couvert jusqu'à sa fermeture.

Le diagnostic initial avec CSS injectée est conservé séparément ; il ne vaut
pas validation du build. Le test sur le build réel utilise tap/clic, ferme la
modale d'évaluation par son bouton et vérifie la position après fermeture. Les
événements clavier dans une textarea ne prouvent pas un clavier logiciel sur
un appareil physique. Le dialogue testé s'ouvre depuis la page Litiges courte ;
aucune préservation de position sur toute page longue n'est revendiquée.

Deux défauts du nouveau banc ont aussi été conservés puis corrigés : les points
à 3 px des coins d'une alerte arrondie touchaient son parent transparent ; les
sondes portent désormais sur les bords utiles, le centre, le texte et le bouton
entiers. L'import de Stripe JS par Facturation reçoit une réponse locale inerte
pour le seul GET de script exact observé ; toute autre requête fournisseur ou
mutation métier reste interdite. Cela ne valide aucun paiement.

## Matrice SQL candidate

Les 49 suites précédentes, le témoin figé puis la matrice nouvelle s’exécutent sous
rollback. La synchronisation de la base main1009 reste le seul chemin staging
existant ; la migration candidate ne doit jamais y persister. Le raccord exige
le rouge exact du témoin avant migration puis un catalogue indépendant inchangé.
Après application transactionnelle du correctif, les mêmes règles documentaires
sont attendues vertes.

Les neuf histoires de la matrice sont indépendantes et annulées avant la suivante :
TVA des honoraires à 20 %, taux figé à 12 %, lissage d’un centime sur finale,
avoir, complément, remplacement historique sans snapshots, commission manquante,
taux historique incohérent et commission ambiguë. Les assertions portent sur
les pièces, l’estimation après triggers, la période suivante, le cumul signé,
l’idempotence, l’immutabilité des anciennes pièces et les refus atomiques.

Les scénarios avoir/complément représentent un historique PAYEE synthétique dans
la transaction de test, avec zéro paiement, PaymentIntent, transfert ou avance
réel. Ce seed de maintenance ne prouve pas un encaissement. Les claims, la TVA et
les snapshots sont synthétiques, sans signature, mandat, qualification ou MFA.
Les références PDF/XML ne désignent aucun objet Storage réel. Les triggers
restent actifs ; les deux emails de clôture et les éventuelles requêtes pg_net
restent non commités et sont annulés. Une séquence technique peut consommer un
numéro. Les compteurs/catalogues et les résidus sont contrôlés indépendamment.

L’ancien cas heures seules de PR1009 conserve son scénario ; son attendu passe
explicitement de 160/21 à 160/24 dans la PR produit. Les quatre autres attentes
restent inchangées. Le rouge historique 160/21 déjà acquis est conservé ; il
n’est pas rebaptisé validation comptable. Le nouveau témoin rouge et son
catalogue ne sont pas modifiés.

## Preuves locales et limites restantes

- Rouge PostgreSQL exact avant migration, puis 51 suites vertes et contrôle
  indépendant après rollback sur le même SHA.
- Tests locaux déjà acquis : parseur SQL/PLpgSQL, 59 tests Node, 67 tests Vitest
  dont 19 du lecteur documentaire, 17 gardes, `tsc -b` et actionlint. Aucun de
  ces contrôles n'exécute le PostgreSQL métier du candidat.
- 35 simulations vertes, sans retry ni skip : six nouveaux scénarios et un
  historique salarié/mixte sur iPhone, Android, iPad portrait/paysage et
  ordinateur. Montants exacts, erreurs de pagination, reprise, navigation,
  rechargement, fermeture des menus/dialogue et dumps ARIA sont contrôlés.
  Les réponses API sont fictives et fermées ; aucune intégration distante
  n'est déduite de ces résultats. Les captures iPhone et ordinateur ont été
  relues. Le libellé de commission se replie sans toucher son montant.
- Revue indépendante du diff final et contrôle de déploiement après merge.

Ni concurrence réelle entre transactions, ni fournisseur, ni appareil physique,
ni lancement national prêt ne sont prouvés par ce candidat.
