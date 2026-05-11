# TODO Refactor — dette technique tracée

> Ce fichier liste les chantiers de refactor connus à exécuter de façon
> indépendante. Chaque entrée précise le contexte, l'effort estimé et la
> raison pour laquelle elle n'a pas été traitée en même temps que le bug
> ou la feature qui l'a révélée.

## CORS — migration des `getCorsOrigin` inline vers `_shared/cors.ts`

**Status :** à planifier — non bloquant.

**Contexte.** Suite à l'incident d'inscription sur `app.jolene.app` (CORS
preflight rejeté car le sous-domaine n'était pas dans l'allowlist), la
correction immédiate a consisté à ajouter `origin === "https://app.jolene.app"`
dans la fonction `getCorsOrigin` inline de **chaque** edge function
concernée (22 fonctions au total, mergées via 5 PRs successives :
batches 1-4 + batch final de 13 fonctions).

Ce duplicat de code (la même allowlist répétée 22 fois) est fragile :
ajouter ou retirer un domaine nécessite de modifier 22 fichiers à la
main, et l'audit qui a déclenché ce ticket prouve qu'on peut en
oublier facilement.

**Cible.** Le fichier `supabase/functions/_shared/cors.ts` existe déjà
et contient l'allowlist correcte (`https://app.jolene.app` inclus). Le
chantier consiste à :

1. Auditer toutes les edge functions qui définissent encore localement
   `getCorsOrigin` / `corsHeaders` (probablement 22, à confirmer
   via `grep -l 'function getCorsOrigin' supabase/functions/*/index.ts`).
2. Pour chacune : supprimer la fonction inline et `import { corsHeaders } from "../_shared/cors.ts";` à la place.
3. Vérifier que `corsHeaders` exporté supporte les mêmes headers
   `Access-Control-Allow-Headers` que ceux utilisés localement
   (`x-supabase-client-platform`, `x-supabase-client-platform-version`,
   `x-supabase-client-runtime`, `x-supabase-client-runtime-version`,
   `apikey`, `content-type`, `authorization`, `x-client-info`).
   Étendre `_shared/cors.ts` si besoin pour couvrir le sur-ensemble.
4. Déployer les 22 fonctions et tester avec une requête OPTIONS depuis
   `Origin: https://app.jolene.app` pour confirmer que chaque endpoint
   répond `Access-Control-Allow-Origin: https://app.jolene.app`.

**Effort estimé.** ~2h (changement mécanique + tests).

**Pourquoi pas tout de suite.** Les 5 PRs CORS étaient hot-fix
production (inscription cassée). Refactorer dans la foulée aurait :
- multiplié la taille du diff au moment où il fallait pouvoir le relire vite,
- augmenté le risque de régression sur un sous-ensemble de fonctions,
- mélangé "fix urgent" et "amélioration architecturale" dans le même
  commit, ce qui rend la rétroaction (revert si bug) plus chère.

**Critère d'achèvement.** `grep -l 'function getCorsOrigin' supabase/functions/*/index.ts | wc -l` retourne `0`.
