# D2 — préparation du parcours frontend staging

Lot distinct de #1000, construit sur le banc D2 `483e8bca`. Le SQL réel annulé a réussi dans le run [36729455524](https://github.com/Gabpcd/JJJJJ/actions/runs/36729455524), avec sentinelle et SELECT indépendants zéro résidu ; il ne prouve ni Auth HTTP ni navigateur. Ce nouveau mode est préparé localement, sans dispatch ni nouvelle fixture distante.

## Périmètre et ordre

Entrées `candidatures_frontend_only=true`, scénario `04-candidatures-simultanees`, `candidatures_frontend_date` explicite entre un et 31 jours dans le futur. Les modes SQL D2, E10, diagnostic, all et tout override volume/durée sont refusés avant accès. Une date UI seule sélectionne aussi le job UI pour y être refusée, sans repli vers k6. Le verrou global `jolene-supabase-staging-writes`, sans annulation du run précédent, couvre tout le workflow.

1. Vérifier contexte manuel/repository/SHA/destination staging exacte, puis les trois empreintes D2 figées et zéro cron actif/FK audit. Les migrations de #1000 ne sont jamais appliquées par ce job ; une dérive de catalogue bloque avant Auth.
2. Résoudre les clés staging, construire sans DSN/Turnstile et vérifier la preview locale E10 avant la création de comptes. Aucune installation ou compilation supplémentaire n'a été effectuée localement pour cette préparation ; la CI emploie son `npm ci` habituel.
3. Réutiliser `prepare-candidatures-fixture.mjs` inchangé : deux AS SALARIE non vérifiés, un établissement EN_ATTENTE incapable de publier, une mission OUVERTE non urgente et un créneau 09:00–13:00 UTC. `email_confirm:true`, trois mots de passe distincts et trois password grants préparatoires. Canaux de préférences tous fermés dans le seed. La console Auth du 30 septembre ne montrait aucun hook personnalisé ni SMTP custom (`audits/.../auth-staging-console-20260930.md`) ; ce constat ne désactive pas le service email intégré.
4. Trois connexions par formulaire dans des contextes WebKit indépendants : AS1 iPhone, AS2 iPad, établissement iPad. Chacun suit d'abord son dashboard normal. Les deux AS déposent successivement, via le dialogue réel, un POSTULER exactement lié au manifeste ; chacun vérifie rappel documentaire, attente et recharge. L'établissement relit les deux noms/EN_ATTENTE/documents non validés et recharge. Aucun accepter/refuser, messagerie, paiement, k6 ou test de concurrence DB.
5. Fermer chaque contexte puis le navigateur avant de rendre la main au job. Vérifier la corrélation exacte des deux IDs retournés avec le backend et les quatre notifications attendues. Même en échec UI : snapshot des audits après fermeture, cleanup du manifeste exact, puis zéros et conservation des audits. Les gardes du préparateur/SQL restent inchangées.

## Écritures UI inventoriées

| Écriture | Limite avant réseau | Preuve attendue |
| --- | --- | --- |
| Password grant UI | 1 par identité, email/password exacts | user.id/email/rôle/marqueurs du manifeste + jeton présent, jamais sérialisé |
| `fn_audit_connexion` | 1 CONNEXION par identité | 3 audits exacts, conservés après cleanup |
| `fn_maj_activite_soignant` | 1 corps vide par AS | empreinte du timestamp d'activité changée depuis avant ; la valeur DEFAULT now() n'est pas une preuve d'avancement |
| `fn_ecrire_audit_safe` | 1 pour le seul établissement, action DONNEES_PERSO_CONSULTATION et page dashboard_etablissement | 1 audit de consultation exact conservé |
| `fn_confirmer_action_planning_v1` | 1 POSTULER par AS, mission/message/créneau du manifeste, choix_contrat et candidature_id null | 2 candidatures EN_ATTENTE/SALARIE + 4 notifications exactes via le vérificateur D2 existant |

L'audit de consultation est automatique dans `DashboardEtablissement.tsx:363` après la connexion. La définition LIVE de `fn_ecrire_audit_safe`, lue sans exécution, a le MD5 `04cc44127e325b434445113e88ce38b7` et insère seulement le journal. Le catalogue global figé couvre ce corps et son trigger d'audit. Aucun journal n'est supprimé. Les timestamps/IP/user-agent et corps réseau ne sont pas exportés ; seule l'empreinte d'activité permet de vérifier le changement.

`fn_update_presence` reste interdit. Le hook ne se monte que via PageMessagerie ou ChatConversation ; dans les deux détails mission, le chat exige un statut assigné ou ultérieur et un soignant assigné. D2 reste OUVERTE sans assignation. Les gardes existantes continuent de refuser présence, email_queue, tokens_push, conversation et toute dépendance inconnue. La cloche peut donc montrer la perte de connexion realtime attendue dans ce banc.

## Réseau et secrets

L'interception est installée avant la première page. Seuls preview locale et staging exact sont autorisés ; RPC de lecture inventoriées, tables en lecture avec filtres liés au manifeste, aucune Edge/Storage/fournisseur. Les WebSockets sont fermés sans `connectToServer`. L'import Stripe du détail établissement reçoit uniquement un stub local qui jette s'il est invoqué ; aucun SDK Stripe n'est téléchargé. La preview éphémère retire la feuille Google Fonts et utilise la police de secours existante, sans modifier le produit.

Les écritures ont chacune un budget unitaire consommé avant transport : une réponse perdue n'autorise aucun second POST. Le créneau accepte les deux représentations ISO strictes du même instant (`.000Z` et `+00:00`), avec fuseau explicite et aucune perte de précision ; les dates locales, heures voisines ou clés supplémentaires sont refusées.

Le manifeste avec ses états reste dans `$RUNNER_TEMP/d2-frontend-manifest.json`, hors artefacts. Les mots de passe ne passent que par le canal privé GITHUB_ENV déjà utilisé par le préparateur. Le processus navigateur reçoit seulement PATH/HOME/TMPDIR et les variables système d'affichage, aucun secret serveur dans son environnement. Aucun storageState/HAR/trace/vidéo/session n'est écrit. Seul `tests/load/results/d2-frontend/` est téléversé : compteurs, diagnostic de phases/origines/routes connues/statuts, captures de main après vérifications. Une disparition du runner avant cleanup exige une investigation des IDs déterministes et des états ; ne pas recréer les comptes ou fabriquer un manifeste « cleaned ».

## Commande à soumettre à revue avant toute exécution

```sh
gh workflow run load-tests.yml -R Gabpcd/JJJJJ --ref test/candidatures-deux-profils \
  -f scenario=04-candidatures-simultanees \
  -f candidatures_frontend_only=true -f candidatures_frontend_date=2026-10-07 \
  -f candidatures_sql_only=false -f dashboard_fixture_only=false -f diagnostic_sql=false
```

Vérifier le SHA exact du run avant d'interpréter les résultats. Garder les dates SQL et overrides vides. Aucun dispatch n'est effectué par ce lot. Si la date sort de la fenêtre, choisir explicitement une autre date après revue ; ne pas contourner le garde.

## Validation locale et limites

Le test Node couvre le routage exclusif, les refus avant accès, les canaris secrets, les écritures unitaires, les réponses Auth/POSTULER, la corrélation backend, l'activité inchangée refusée, les audits conservés et la fermeture effective sur exception. Les conditions workflow imposent snapshot et cleanup même après échec du navigateur.

`recette-complete-candidatures-runner.spec.ts` appelle les mêmes fonctions de parcours et la même garde réseau sur le frontend local, avec réponses/sessions simulées et horloge fixe. Il vérifie les cinq formats ; le mock existant conserve son créneau indépendant 09:00–13:00 Paris et ses noms fictifs. Cela ne remplace pas les trois connexions ni les effets backend réels du futur run. Les simulations initiales ont signalé un sélecteur qui incluait les badges dans le nom ; le runner compare maintenant les nœuds texte propres du paragraphe, sans relâcher l'identité attendue. Résultats chiffrés et SHA256 sont conservés dans le dossier durable d'audit associé au commit.

Validation terminée le 30 septembre : 160/160 contrats Node (dont 14 nouveaux), 17 gardes, `tsc -b`, typecheck E2E isolé, ESLint ciblé, actionlint sur les deux workflows, trois contrôles pglast de portée catalogue et parse du SELECT d'audit. Simulation : iPad portrait 1/1 puis iPad paysage/iPhone/Android/ordinateur 4/4, zéro retry/skip. Une tentative locale a rencontré ENOSPC avant capture ; les quatre formats restants ont ensuite tous passé. Les sept captures retenues (cinq établissement, deux soignant) et rapports filtrés sont dans le dossier racine `audits/2026-09-30-preparation-nationale/d2-frontend-local`, manifeste SHA256 `0099fce28c2a6706416dfdb0fb701f212025375a9081b4e89fd67661658c1aba`. Le serveur local a été arrêté. Les textes produit du socle antérieur, notamment BlocConformite, ne sont pas modifiés par ce banc.

## Premier pilote et diagnostic complémentaire

Le run staging `36735437993`, SHA `51d0c992`, échoue après le POSTULER du second AS. Le premier AS iPhone a réellement postulé et rechargé ; le second POSTULER répond HTTP200 et passe le contrat de réponse, mais sa capture/recharge et le parcours établissement ne sont pas atteints. Quatre erreurs navigateur sont comptées, sans refus réseau ni erreur HTTP. Leur nature n'était pas conservée : aucune cause produit ou fixture n'est prouvée. Cleanup et vérification sont verts ; SELECT indépendants confirment les zéros du lot, les deux audits CONNEXION plus PREPARE/CLEANUP conservés et le catalogue inchangé. Preuves racine `audits/2026-09-30-preparation-nationale/d2-frontend-staging-36735437993`, manifeste SHA256 `5dd50a0e4d5670dc037c1de037531de36e3cbc3af8a2c9d5ab8ef89c1a1dcb04`.

Le complément conserve chaque pageerror/console.error comme erreur bloquante et ajoute une projection fermée : source, classe connue, catégorie réseau/abandon/contexte fermé/WebSocket/React/autre, code React numérique et SHA256 du texte. Aucun texte brut, stack, URL complète, query ou fragment n'est exporté. L'emplacement éventuel se limite à un fichier JavaScript réellement inventorié dans `dist/assets`, sur l'origine preview exacte, avec ligne/colonne numériques. Le slot émetteur est fixé lors de l'installation du contexte ; le slot de phase courant est séparé pour attribuer une erreur tardive. L'agrégation est bornée à32 entrées et le nombre d'entrées non détaillées est conservé ; le total reste bloquant.

Validation du complément : 17/17 tests Node, `tsc -b`, typecheck E2E isolé, ESLint ciblé et syntaxe Node verts ; 10/10 simulations (parcours D2 et injection de vraies erreurs navigateur sur chacun des cinq formats), zéro retry/skip. Les erreurs injectées restent comptées et ne divulguent aucun canari. Les cinq captures établissement après reload sont relues. Preuves racine `audits/2026-09-30-preparation-nationale/d2-frontend-diagnostic-local`, manifeste SHA256 `07ed24e8297a12946955f95de0b5bca29085a2796ce73198449ac7fcf60b8dfa`. Contrat réseau, budgets de mutation, parcours et nettoyage restent inchangés. Aucune relance distante n'est effectuée par ce complément.
