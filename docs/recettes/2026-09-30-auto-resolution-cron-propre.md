# Auto-résolution de sa propre alerte cron

Le job `jolene_auto_resoudre_alertes` voit sa propre exécution courante en
`running`. L'ancienne sélection du dernier run empêchait donc la résolution de
son alerte historique, même après un succès terminé postérieur. Le constat LIVE
transmis le 30 septembre relevait trois succès à 04:20, 06:20 et 08:20 UTC, avec
une alerte du 10 août encore active.

La migration part de la définition LIVE relue (empreinte
`7783733961ba50b6bd0c8b80c5645f32`) et refuse de s'appliquer si elle a changé.
Seul ce job prend sa dernière exécution terminée (`succeeded` ou `failed`, avec
`end_time`). Un succès plus ancien que l'alerte, un dernier échec ou un run
incomplet ne permettent aucune résolution. Le `runid` départage les mêmes dates
de début. Les autres jobs conservent la lecture de leur dernier statut.

Aucune alerte historique n'est acquittée par la migration. La garde cron/admin,
le propriétaire, SECURITY DEFINER et les droits d'exécution restent identiques.
Le filtre `CRON%` laisse les alertes financières intactes ; le délai de 72 heures
pour les crons décommissionnés est conservé.

## Contrôles

Le test SQL ajouté à `validate-pr` clone **la fonction réellement migrée** vers
`pg_temp` et redirige ses trois relations vers des tables temporaires. Il couvre
succès puis run courant, dernier échec, égalité de date/runid, succès trop ancien,
statut incomplet, autre cron encore en cours puis repris, délai orphelin,
idempotence, alerte financière intacte, refus d'un utilisateur non administrateur,
ACL et empreinte d'inventaire. Le contexte cron à UUID NULL reste autorisé : ce
n'est pas le témoin du refus utilisateur. Le test se termine par rollback.

Validation locale : pglast accepte SQL et PL/pgSQL de la migration, du test et
du clone sans référence aux tables réelles ; TypeScript, les 17 garde-fous,
ESLint ciblé et actionlint passent. **Il s'agit d'analyse syntaxique SQL, pas
d'exécution PostgreSQL locale** : aucun runtime n'a été installé. L'exécution
SQL réelle sous transaction annulée reste à confirmer en CI avant merge.

Simulation frontend administrateur : cinq formats (iPhone, Android, iPad portrait
et paysage, ordinateur). L'alerte technique disparaît après reprise et reload,
l'alerte financière reste visible ; un vrai état d'échec simulé demeure après
actualisation et reload. Aucun clic « Résoudre » ni appel d'acquittement n'est
effectué. Les réponses API sont entièrement simulées ; le frontend produit est
inchangé et identique au build local de main utilisé pour cette recette.

Preuves locales : `/private/tmp/jolene-auto-resolution-pglast.json`,
`/private/tmp/jolene-auto-resolution-guards.txt` et
`/private/tmp/jolene-auto-resolution-ui-final/results.json` (captures et arbres
d'accessibilité associés).

Aucun cron réel, acquittement production, nouvelle session Auth distante ou
mouvement financier n'a été lancé. Après déploiement, seule une lecture de la
prochaine exécution normale et de l'état des alertes pourra confirmer l'effet
réel. Une CI verte ne prouve pas à elle seule cette reprise en production.
