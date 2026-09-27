# Recherche publique : comptage unique

Sur le staging, le [test de charge à 200 utilisateurs virtuels](https://github.com/Gabpcd/JJJJJ/actions/runs/36150387540) a produit 22 751 recherches sans erreur HTTP, mais un p95 de 1 634,56 ms, supérieur à la cible de 1 000 ms. Ce résultat reste un échec de performance.

Le [diagnostic suivant](https://github.com/Gabpcd/JJJJJ/actions/runs/36153459506) a préparé 500 missions fictives, mesuré le plan en lecture seule, puis nettoyé le catalogue. Le comptage du CTE était exécuté 500 fois : l’agrégat rescannait 500 lignes à chaque passage. Ce travail explique environ 40 ms des 44,495 ms du SELECT développé hors charge. Il n’explique pas à lui seul toute la latence HTTP.

La migration `20260925153200` remplace la jointure du comptage par `count(*) OVER ()`. Elle conserve la signature, chaque colonne, les filtres métier, les exclusions, l’éligibilité, les droits et le tri. Elle ne plafonne pas les résultats et n’assouplit aucun seuil de test.

Le harness local `tests/load/seed/verify-public-search-local.mjs` compare l’ancienne définition LIVE à la migration compilée. Quinze cas sur 500 missions et onze sentinelles vérifient toutes les colonnes, les comptes, les filtres, l’ordre par groupes, les exclusions et les appels aux contrôles de droits. Les UUID ex aequo ne disposent d’aucun ordre contractuel supplémentaire. Double application, ACL et rollback passent. Le nouveau plan utilise une seule boucle WindowAgg ; cette mesure locale ne vaut pas un p95 en réseau.

La suite `tests/security/recherche-publique-comptage.test.sql` est ajoutée à la validation réelle sous rollback du staging. Le diagnostic exige désormais l’empreinte de la nouvelle fonction, `904e83ab283dac36554a465d7ee717a8`, avant de mesurer son plan. La clôture performance exige ensuite un nouveau run à 200 utilisateurs virtuels avec les mêmes seuils.
