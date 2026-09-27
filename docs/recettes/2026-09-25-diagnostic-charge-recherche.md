# Diagnostic borné de la recherche publique — 25 septembre 2026

Le scénario C à 200 VUs pendant deux minutes sur 500 missions fictives staging a produit 22 751 itérations, 22 752 requêtes HTTP (préflight inclus), zéro échec HTTP et 68 253 contrôles fonctionnels réussis. **Ses seuils de latence ont échoué** : médiane 659,442 ms et p95 1 634,561 ms, pour des cibles respectives de 400 et 1 000 ms. Run GitHub : `36150387540`. Ce résultat ne prouve pas une capacité nationale suffisante.

La durée moyenne HTTP est de 753,759 ms, dont 752,672 ms d’attente de réponse ; la réception moyenne est de 1,026 ms. Le téléchargement du corps seul n’explique donc pas la majeure partie du temps. Cela ne permet pas encore de distinguer calcul SQL, attente de connexions et charge du service API. Aucun seuil, pagination ou filtre métier n’a été modifié pour faire passer la mesure.

## Instrumentation ajoutée

Le workflow manuel `load-tests.yml` accepte `diagnostic_sql=true`, uniquement pour C ou `all`. Après préparation du catalogue et avant k6, `scripts/ci/diagnose-load-fixtures.mjs` exécute exactement six sondes séquentielles :

1. Identité SQL, version PostgreSQL, JIT, statistiques des trois tables, activité agrégée, compte exact des UUID du manifeste et statistiques cumulées du seul RPC de recherche (aucun texte de requête exporté).
2. Nombre de lignes et tailles JSON/PostgreSQL des résultats sans filtre, IDE à Paris et ville Paris seule. Les lignes métier elles-mêmes ne sont pas exportées.
3. `EXPLAIN (ANALYZE, BUFFERS, FORMAT JSON)` du RPC sans filtre, agrégation JSON incluse.
4. Même mesure pour IDE à Paris.
5. RPC sans filtre avec `plan_cache_mode=force_custom_plan`, limité à la transaction de diagnostic.
6. Plan du SELECT interne anonyme, développé d’après la définition LIVE relue ce jour. Cette sonde exige le même propriétaire SQL que le RPC ; elle n’installe ni ne remplace aucune fonction.

L’empreinte de la définition LIVE est vérifiée avant chaque sonde. Une définition différente impose sa relecture et fait échouer explicitement le diagnostic. Les plans du RPC peuvent ne montrer qu’un `Function Scan` ; l’expansion interne donne le détail, sans prétendre reproduire le cache des connexions PostgREST.

Chaque sonde est enfermée dans `BEGIN READ ONLY` / `ROLLBACK`, avec `auth.uid()` nul et claims anonymes. Le rôle Management et le propriétaire de la fonction sont consignés : cette voie ne mesure pas le pool PostgREST. Les plafonds sont de 8 s par instruction SQL, 2 s d’attente de verrou, 12 s par réponse HTTP, 75 s pour le lot et 512 Kio par corps. Aucun `ANALYZE` de table, index, quota, donnée ou permission n’est modifié.

La ref **et** l’URL exactes du staging sont obligatoires, tout comme le manifeste déterministe en état `prepared`. Aucune URL externe configurable, redirection HTTP ou nouvelle tentative automatique n’est acceptée. En cas de panne, les mesures déjà terminées sont conservées, le rapport reste `failed`, le corps serveur et les erreurs réseau privées ne sont pas affichés. Le nettoyage du catalogue reste exécuté en `always()`.

Résultat attendu : `tests/load/results/diagnostic-recherche.json`, joint à l’artefact k6 existant. Les statistiques cumulées, le réchauffement possible des caches et la différence entre ces sondes hors charge et l’API sous concurrence sont explicitement signalés dans ce fichier.

## Vérification et limites actuelles

- **59/59 tests Node verts** : 8 nouveaux du diagnostic et 51 existants du banc de charge/préparation/attente staging. Tous utilisent un transport simulé, sans token ni réseau réel.
- Syntaxe Node et `git diff --check` verts. Relecture indépendante : aucun P1/P2 démontré.
- La sonde de métadonnées a été exécutée en lecture seule via MCP staging, après nettoyage du catalogue : elle confirme `uid_null=true`, lecture seule et JIT désactivé. Elle ne constitue pas une mesure sur 500 missions.
- Le rôle MCP `supabase_read_only_user` n’a pas `EXECUTE` sur le RPC ni la possibilité de changer de rôle. Les sondes RPC n’ont donc pas été exécutées par MCP. Aucun accès ni droit supplémentaire n’a été créé. La CI possède déjà l’accès Management nécessaire au préparateur ; elle doit maintenant produire les plans sur le catalogue préparé.

Lancer d’abord C à 10 VUs / 30 s avec `diagnostic_sql=true`, conserver les plans et le nettoyage confirmé, puis décider de la comparaison à 200 VUs. Les diagnostics ne changent pas les critères d’acceptation k6.

Documentation consultée : [API Management SQL](https://supabase.com/docs/reference/api/v1-run-a-query), [diagnostic PostgreSQL Supabase](https://supabase.com/docs/guides/database/inspect), [changelog du 25 septembre](https://supabase.com/changelog). Aucun changement de version PostgreSQL n’est effectué par ce lot.
