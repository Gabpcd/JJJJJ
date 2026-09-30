# D2 : un titre de mission distinct du nom de l’établissement

Le run staging `36745509238`, sur `902db17f3cbc4691a7ded135864ed372165a8bc7`, s’arrête à `mission_titre` sans candidature. Les réponses sont HTTP 200, sans refus réseau ni erreur navigateur. Le diagnostic indique 8 024 ms au début du matcher et 10 177 ms à la fin ; sa catégorie `delai_attente` ne suffit pas à conclure à un timeout réel.

La cause est reproduite localement avec **la même empreinte SHA256 du message d’exception** : `8d4f93ee3a40c7e3dc09ee623e821be265b489c8ccc0e088e5ab725e51d4f920`.

Le seed utilise son marker comme `missions.intitule` et comme `etablissements.nom`. Le détail soignant affiche la mission en `h1` et l’établissement en `h3`. Le matcher cherchait tout heading avec ce nom, alors que la fixture locale utilisait auparavant deux noms différents.

Une reproduction indépendante hors runner Playwright, avec sa version 1.58.2, passe par le formulaire de connexion puis les mêmes barrières URL dashboard, activité et networkidle avant la vraie fonction `deposerCandidatureD`. Elle s’arrête avant toute candidature, même simulée :

| Fixture | Titres correspondants | h1 / h3 | Durée du matcher | Résultat |
|---|---:|---:|---:|---|
| Noms distincts | 1 | 1 / 0 | 388 ms | Titre visible |
| Même marker, comme le seed réel | 2 | 1 / 1 | 399 ms | `strict mode violation`, empreinte distante identique |

Les deux variantes ont une activité et un audit de connexion simulés, zéro requête inconnue, zéro pageerror et zéro dépôt. Le message Playwright de violation stricte contient aussi `Timeout: 5000ms`, d’où l’ancienne classification trompeuse. La durée distante reflète l’arrivée des deux éléments ; elle ne prouve ni une limite de deux secondes, ni une panne Auth.

Le correctif cible uniquement le titre principal avec `level: 1`. La projection classe désormais `strict mode violation` en `strict_mode` avant la recherche du motif timeout, sans exporter de texte, URL, identité ou session. Aucun délai, règle métier, endpoint, budget d’écriture ou garde réseau ne change.

La fixture du parcours runner utilise maintenant le même nom pour l’établissement et la mission. Un nouveau test attend les deux titres, vérifie le refus du sélecteur ambigu, puis l’unicité et la visibilité du h1. Le test Node vérifie aussi que la présence du mot timeout ne masque plus cette ambiguïté et que les canaris restent absents de la projection.

Validation locale : **24/24 tests Node**, typecheck E2E ciblé et diff-check verts. **15/15 simulations**, trois tests sur chacun des cinq formats (ordinateur, iPhone, Android, iPad portrait et paysage), zéro skip, retry ou flaky. Cela inclut deux dépôts fictifs, rechargements et relecture établissement, le contre-exemple du titre et la conservation des erreurs navigateur bloquantes. Aucun nouveau run staging n’est lancé par ce lot.

La simulation réutilise le Vite local 5173 du checkout capacité, sans modifier celui-ci. Le frontend est identique à la révision de départ. Le diagnostic autonome conserve les erreurs console du banc de développement/HMR bloqué ; il ne revendique pas zéro console error pour ce banc. Les gardes de la spec existante ne sont ni filtrées ni relâchées. La validation staging sur build compilé reste distincte et sera lancée par root après relecture.

Preuves et reproduction : `/private/tmp/jolene-d2-diagnostic-titre-20260930/`, avec archive compacte et manifeste sous `audits/2026-09-30-preparation-nationale/preuves/d2-titre-mission-ambigu/` du workspace Jolene. La source du runner de base est conservée pour reproduire l’erreur après application du correctif. Les preuves indépendantes de nettoyage du run initial restent dans `/private/tmp/jolene-d2-36745509238-artifact/` ; elles ne sont pas réexécutées ici.
