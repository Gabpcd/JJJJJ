# Identité temporaire pour la charge du tableau de bord — 27 septembre 2026

Le run E `36152172775` avait échoué au login du compte fixe avant toute itération ; il ne démontrait aucune capacité du tableau de bord. E utilise désormais une identité temporaire de staging propre au run. Aucun compte fixe, secret de production ni SQL produit n’est modifié.

## Contrat de la fixture

- Ref **et** URL exactes du staging obligatoires. UUID déterministe enregistré dans un manifeste avant l’appel Auth, email `example.invalid`, création Admin avec confirmation email intégrée : aucun email d’inscription envoyé.
- Métadonnées privées `role=SOIGNANT`, `est_compte_test=true`, `is_test_playwright=true`, type et identifiant du run. Profil AS/SALARIÉ minimal ; identité, diplôme, RPPS et documents restent non vérifiés, pas de téléphone ni de donnée financière.
- Mot de passe aléatoire, masque GitHub avant usage et transmission par `GITHUB_ENV` seulement. Le manifeste ne contient ni mot de passe, ni clé, ni jeton. Aucun corps d’erreur HTTP ou détail d’exception réseau n’est affiché.
- Login réel puis préflight de la RPC. L’UUID et les métadonnées du login doivent être ceux de la fixture. Le RPC LIVE ne projette pas `profil.id` : le nom fictif `Dashboard <UUID>` et le prénom `Recette`, enregistrés dans le manifeste, sont vérifiés au préflight **et à chaque réponse de charge**, ainsi que la profession et l’absence de validation.
- Aucun trigger ni contrainte n’est désactivé. Les déclencheurs concernés ont été relus sur staging ; leurs empreintes sont contrôlées avant préparation/nettoyage. Tous les crons staging doivent être inactifs.

## Nettoyage et réponses ambiguës

L’étape de nettoyage s’exécute en `always()`. Elle vérifie l’UUID, l’email, les métadonnées privées et les marqueurs du profil. Toute dépendance métier est refusée, même si sa FK autoriserait une cascade ; les FK non simples ou ne visant pas `id` sont également refusées. Préférences/profil sont supprimés explicitement par UUID, puis l’API Auth retire l’identité et ses sessions/identités techniques. Une dernière lecture SQL doit confirmer zéro compte, profil et préférence de ce run.

Préparation du profil et nettoyage partagent un verrou transactionnel. Le nettoyage marque l’identité privée avant de retirer le profil : une préparation SQL retardée est refusée après ce point. Une réponse perdue après création Auth, création du profil ou suppression Auth conserve le manifeste et permet un contrôle ciblé. Si la création Auth reste ambiguë **et** que le compte est encore absent, le nettoyage échoue explicitement ; il ne peut pas prouver qu’une requête tardive ne créera pas ce compte ensuite. Aucun nettoyage global par préfixe n’est utilisé.

## Vérification effectuée

- **75/75 tests Node verts** sur le banc complet (charge, fixtures recherche/dashboard, diagnostic recherche et attente staging), dont **13 nouveaux tests du préparateur dashboard**. Transport en mémoire : création, préflight, mauvaise identité, réponse perdue aux trois étapes, marqueur altéré, dépendance et nettoyage vérifiés.
- Une probe PGlite locale a exécuté le SQL réel avec les **10 définitions de triggers LIVE** concernées, sur un schéma minimal : profil AS non vérifié, transports désactivés, dépendance métier avec FK CASCADE refusée, nettoyage exact et rejet d’un seed SQL retardé. Le générateur aléatoire de code parrainage est simulé localement ; ce n’est pas le schéma staging complet ni une contention de plusieurs sessions.
- Syntaxe Node et contrôle de diff : verts. [Journal Node](assets/2026-09-27-fixture-dashboard/node-resultats.txt), [résultat SQL local](assets/2026-09-27-fixture-dashboard/sql-local.txt).
- Relecture indépendante finale : aucun finding bloquant démontré ; l’oracle d’identité et la garde des clés référencées ont été vérifiés après correction.

## Première mesure réelle : fonctionnel vert, seuil p99 échoué

Run [36324096829](https://github.com/Gabpcd/JJJJJ/actions/runs/36324096829), révision `746847dcf988cb57bcc27e4dedfdc45ebf3cc754`, staging seulement. La configuration demandée et la bannière k6 confirment **100 VUs constants dès le démarrage, pendant une minute** ; aucune période de démarrage n’est exclue. Préparation et nettoyage ont réussi ; le job est rouge parce que le seuil p99 a échoué.

| Mesure | Résultat |
|---|---:|
| Itérations dashboard | 8 594 |
| Requêtes HTTP (login + préflight inclus) | 8 596 |
| Contrôles réussis | 17 190 / 17 190 |
| Échecs HTTP | 0 |
| RPC dashboard p50 | 111,08 ms |
| RPC dashboard p95 | 153,07 ms — seuil < 2 000 ms réussi |
| RPC dashboard p99 | Valeur exacte non exportée — seuil < 3 500 ms échoué |
| RPC dashboard maximum | 6 163,47 ms |

Le journal montre zéro itération terminée à 2,6 s, 58 à 6,6 s puis 214 à 7,6 s. Ce démarrage lent participe intégralement à l’échec du seuil. Le `pg_stat_statements` du statement PostgREST dashboard, relu après le run, compte 8 597 appels, une moyenne d’exécution SQL de 0,906 ms, un maximum de 1 039,614 ms et zéro bloc lu sur disque. Ces compteurs cumulatifs ne fournissent pas la chronologie de chaque requête : ils ne permettent pas d’attribuer précisément les 6,16 s HTTP au SQL, à l’attente de connexion ou à une autre couche. Aucun changement produit ni réglage de pool n’a été appliqué sur cette seule hypothèse. La signature LIVE reste `fn_dashboard_soignant_complet() → jsonb`, empreinte `dc2194c3bfdb61151578d8fc30e274ff`.

Une lecture indépendante après nettoyage confirme **0 compte Auth, 0 profil, 0 préférence, 0 session et 0 identité technique** pour l’UUID exact du run. Le manifeste final est `cleaned`.

## Correction du rapport de charge

k6 inclut les données retournées par `setup()` dans son objet de résumé. Ces données peuvent contenir une session de test et ne doivent pas être sérialisées dans un rapport. Les preuves conservées ici ne comprennent que les mesures et contrôles nécessaires à la recette.

Les six scénarios utilisent désormais une projection explicite des métriques, contrôles, état et options de présentation. `setup_data`, les options inconnues et tout futur champ racine sont exclus. Les quantiles p50/p95/p99 sont explicitement exportés ; les seuils et la charge restent identiques. **34/34 tests Node ciblés verts**, avec une session fictive injectée dans les six vrais `handleSummary` pour vérifier qu’aucune sortie ne la contient. Le moteur k6 n’est pas installé localement ; la prochaine mesure CI doit confirmer le rapport du moteur réel. La ligne historique « Configuration effective : {} » est une limite de reporting du premier run, pas une preuve de charge nulle : les VUs et la durée sont confirmés par la bannière et les métriques du moteur.

Preuves assainies : [mesures k6](assets/2026-09-27-fixture-dashboard/mesure-36324096829-assainie.json), [nettoyage et relevé SQL](assets/2026-09-27-fixture-dashboard/controle-36324096829.json).

**Reste à valider :** le seuil p99 avec sa valeur exacte exportée lors d’une nouvelle mesure, toujours avec 100 VUs dès le démarrage. Une seule identité partage son JWT entre les VUs ; aucun résultat ne doit être présenté comme 100 soignants distincts, comme un historique métier rempli ou comme une garantie de capacité nationale. Les seuils existants restent inchangés.
