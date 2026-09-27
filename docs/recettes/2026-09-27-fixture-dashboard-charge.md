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

**Reste à mesurer en CI :** E à 100 VUs pendant une minute, avec cleanup confirmé et rapport k6. Une seule identité partage son JWT entre les VUs ; aucun résultat ne doit être présenté comme 100 soignants distincts, comme un historique métier rempli ou comme une garantie de capacité nationale. Les seuils existants restent inchangés.
