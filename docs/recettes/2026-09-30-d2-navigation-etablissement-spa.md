# D2 — navigation établissement depuis le dashboard

## Pilote réel conservé

Le run [36753100895](https://github.com/Gabpcd/JJJJJ/actions/runs/36753100895), tête
`3396b1fa326325631a8765115acbf29098c878dc`, a échoué le 30 septembre 2026 à
17:43:25 UTC. Il n'a été ni relancé ni annulé pendant ce diagnostic.

- Deux connexions soignants, deux POSTULER HTTP 200, confirmations/documents et
  recharges soignants franchis ; quatre captures conservées dans l'artefact.
- Connexion établissement puis assertions deux candidatures, noms abrégés,
  deux rappels documents et deux boutons Accepter franchies. Aucun bouton
  d'acceptation n'est activé. Arrêt à `etablissement_capture`, à 41 863 ms,
  avant sa capture et sa recharge : la garde navigateur refuse une pageerror.
- Une seule pageerror WebKit `controle_origine`, à 39 111 ms, soit 258 ms après
  le début de `etablissement_navigation`. Empreinte :
  `c7b4e6c9454734c933cf2e136b901bf25144eb7efaa0ca27767170d1651450bd`.
  Les 186 réponses HTTP projetées sont 200 ; aucun refus de la garde ni échec
  transport projeté. Le score répond après le début de navigation ; aucune
  réponse BFA n'est enregistrée.
- Les vérifications backend finales du runner ne sont pas atteintes. Ce run
  n'est donc pas une validation intégrée complète. E10, k6 et la recette SQL
  distincte sont volontairement ignorés par ce mode exclusif.

Les trois SELECT indépendants, observés à 17:47:55 UTC sur staging uniquement,
confirment tous les résidus du manifeste à zéro (Auth, profils, établissement,
mission, créneaux, candidatures, préférences, notifications, limites, sessions,
identités). Six audits restent conservés : trois connexions, une consultation
et deux reçus de fixture dont le reçu cleanup. Aucun email en queue, token push
ou présence du lot. Catalogue schéma/fonctions/triggers inchangé ; zéro cron
actif et zéro FK d'audit. Les validateurs versionnés ont vérifié ces résultats
contre le snapshot avant cleanup. Le jour auxiliaire `2026-10-07` passé au
constructeur local du manifeste ne figure dans aucun prédicat de ces SELECT ;
seul le runId détermine les identifiants ciblés.

## Cause reproduite et correction du banc

`fn_ecrire_audit_safe` est attendu dans la query du dashboard avant son retour.
Ce retour monte ensuite les cartes dont les effets lancent `fn_mon_score_etab`
et `fn_bfa_info`. Le `networkidle` puis le drain des routes déjà interceptées
ne constituent pas une barrière pour ces futures lectures.

Le replay local contrôlé libère la réponse fictive de l'audit puis navigue à
la frontière exacte de ce drain. Avec `page.goto`, il observe deux documents
et deux pageerrors sur les lectures score/BFA. Avec le vrai bouton React
« Voir détail », il observe un document, les deux réponses terminées et aucune
pageerror. L'empreinte BFA correspond exactement à celle du run réel après
remplacement du seul hôte local par l'hôte staging ; aucun token, paramètre,
corps ou texte personnel n'entre dans cette comparaison.

Les deux premières expériences, qui conservaient les lectures déjà
interceptées en vol puis les libéraient, ne reproduisaient pas la pageerror.
Elles restent conservées. Les rapports gardent également les warnings locaux
du build simulé ; aucune preuve ne prétend que ces warnings n'existent pas.
Ce replay établit le mécanisme de la navigation forcée, pas l'identité de tous
les délais et composants de l'infrastructure CI.

Seul le runner change : la carte portant le titre exact de la mission est
ciblée et son bouton « Voir détail » activé. Aucun changement produit, Auth,
permission, règle métier, budget d'écriture, timeout ou filtre d'erreurs.
La recharge explicite demeure et les tests de liens directs sont conservés.

## Validation locale et limites

Le build compilé F1 existant (correctif preload `c5930bac`) est réutilisé sur
loopback ; aucune nouvelle compilation, session distante ni connexion
fournisseur. Les modules runner/spec viennent de cette branche.

- Première matrice : 15 cas existants verts, 5 nouveaux cas tardifs rouges.
  Cause de ces cinq échecs : mot de passe fictif absent de l'acteur du nouveau
  test ; la garde refusait correctement le login. Traces, captures, rapport et
  patch initial sont conservés. La garde n'a pas été modifiée.
- Après ajout de ce champ fictif, seuls les cinq cas affectés sont rejoués :
  **5/5 verts**. Le bilan est **20 scénarios distincts validés en deux passes**,
  pas une première passe de 20/20. Zéro skip, flaky ou retry automatique.
- Les cinq formats sont ordinateur, Android, iPhone, iPad portrait et paysage.
  Les trois identités passent par le formulaire et leur dashboard. La navigation
  établissement exige un document puis deux après reload, deux candidatures
  en attente et les noms abrégés. Aucun contrat, affectation ou paiement.
- Le nouveau stress garde les deux réponses score/BFA délibérément en vol
  jusqu'après le clic réel, puis vérifie leur achèvement, la recharge, les
  bornes réseau et zéro pageerror/console.error projetée. Aucun sleep ajouté.
- **25/25 tests Node**, typecheck E2E ciblé, `tsc -b` et diff-check verts.
  Capture iPhone après recharge inspectée : attente, documents à vérifier et
  absence d'affectation cohérentes. L'erreur du badge Realtime simulé reste
  visible puisque toutes les sockets de ce banc sont fermées.

Commandes : `node --test tests/node/candidatures-staging-ui.node.mjs`,
`playwright test --config=e2e/playwright.recette-complete.config.ts e2e/recette-complete-candidatures-runner.spec.ts`,
puis le même spec avec `--grep='lectures dashboard tardives'` pour la reprise.
`RECETTE_RESULTS_DIR` sépare les passes et `PLAYWRIGHT_BASE_URL` cible uniquement
`http://127.0.0.1:18480`.

Preuves sources : `/private/tmp/jolene-d2-36753100895-artifact` et
`/private/tmp/jolene-d2-36753100895-diagnostic`. Archive durable compacte :
`audits/2026-09-30-preparation-nationale/preuves/d2-navigation-etablissement-spa/`
dans le workspace Jolene, avec manifeste SHA256. Les traces d'échec restent
dans leur dossier initial, référencées par chemin et empreinte. La relecture
croisée de capacité, en lecture seule sans relancer les tests, ne relève aucun
P1/P2 sur les deux fichiers ; elle ne constitue pas une revue B8 fraîche. Aucun nouveau
pilote réel n'est lancé par l'auteur : la revue root précède toute décision.
