# Annulation — préchargement redondant du bundle d’entrée

Sur le build compilé, l’ouverture de la modale d’annulation depuis
`DetailMission` ajoutait un `modulepreload` vers le script d’entrée déjà
exécuté. WebKit émettait ensuite un warning de ressource préchargée inutilisée.
Le parcours métier passait, mais l’exigence de zéro warning échouait en CI.

La reproduction sur `c33fa55d` distingue le scénario local rapide (1,8 s,
avant le warning différé) de l’observation diagnostique : document chargé à
124 ms, préchargement redondant ajouté à 430 ms, puis même warning que la CI.
La modale importait `extraireMessageErreur` et `useNotification`, regroupés
par Rolldown dans le bundle d’entrée. Le helper Vite dédupliquait les links
existants, sans reconnaître le script module déjà exécuté.

## Correction bornée

La seule modale `ModaleAnnulationMissionEtab` est importée statiquement dans
la page, qui reste elle-même lazy. Son montage reste conditionné à son
ouverture ; props, callbacks, `Suspense`, lectures et actions sont inchangés.
L’évaluation de mission reste chargée à la demande. Aucun réglage global Vite,
filtre de console ou mécanisme de récupération n’est modifié.

La recette ajoute une assertion du DOM après l’ouverture : aucun link
`modulepreload` ne doit cibler un script module d’entrée présent. Elle échoue
sur l’ancien build, sans attente ni hash de fichier figé. Dans le nouveau
graphe, `DetailMission` importe la modale statiquement ; son seul import
dynamique restant est l’évaluation. D’autres imports imbriqués restent hors
du périmètre de cette correction.

## Vérification

- Six tests unitaires de la modale passent, ainsi que `tsc -b` et le typecheck
  E2E ciblé.
- La nouvelle assertion produit le rouge attendu sur l’ancien build.
- La preuve finale utilise le build de la base `31f760ff` avec ce diff, API
  fictive locale et aucun upload. Une copie diagnostique hors dépôt de la
  recette conserve toutes les assertions et attend un événement warning
  pendant au maximum huit secondes avant chaque rechargement. Cette observation
  ne fait partie ni du produit ni de la spec committée.
- Les vingt cas compilés passent : quatre formulaires sur iPhone, Android,
  iPad portrait/paysage et ordinateur, zéro retry, skip, erreur ou warning
  navigateur, en 215,4 s à partir du 30 septembre à 17:16:34 UTC. La relecture
  croisée du diff ne relève aucun P1/P2 ; elle reste distincte d'une revue B8.

Les résultats des vingt cas (quatre formulaires sur cinq formats), les
captures d’annulation et les empreintes sont conservés dans le dossier racine
`audits/2026-09-30-preparation-nationale/preload-annulation-corrigee/`.
Le diagnostic avant correction reste dans
`audits/2026-09-30-preparation-nationale/webkit-preload-annulation-c33fa55d/`.

Les API sont simulées. Aucun compte distant, SQL, notification, paiement,
fournisseur ou appareil physique n’est vérifié ou sollicité par cette recette.
