# JOLENE-APP-19 — sonde JavaScript externe refusée par la CSP

## Observation production (12 octobre 2026)

Incident : https://jolene-z6.sentry.io/issues/153004050/

Les deux mails reçus renvoient au même incident (14 occurrences au relevé) :

- `7e9a931fe14c4d598908be29d9d5cc16`, `/connexion`, 08:31:17 CEST ;
- `47af72562dd84a0784a278a2721aa780`, `/aide/pro-sante-connect`, 08:35:34 CEST.

Les deux événements ont été lus dans Sentry authentifié : release `6f29b64a`,
`EvalError`, refus de `unsafe-eval`, mécanisme
`auto.browser.global_handlers.onunhandledrejection`, pile anonyme
`eval ← predicate:234:30 ← next:234:30`. Les breadcrumbs immédiatement précédents
portent `backpack: secure-background FromContentScriptTransportSender`.
Un troisième événement recommandé présente la même signature. Les quatorze
événements n’ont pas tous été inspectés individuellement.

Cette combinaison indique une sonde injectée extérieure au bundle Jolene ;
l’éditeur exact de cette sonde n’est pas établi. La seule présence d’une
extension ne prouverait pas cette attribution. La CSP a bien refusé l’exécution.
La navigation publique connexion → aide PSC et le rechargement ont aussi été
exécutés dans le navigateur de production, sans erreur console observée.
Cela ne qualifie pas une authentification PSC complète.

## Correction ciblée

`beforeSend` exclut seulement la combinaison observée : un unique EvalError
avec ce message CSP, rejet global non traité, trois frames anonymes exactes
`next,predicate,eval` (234:30 pour les deux premières), sans chemin applicatif,
et breadcrumb du transport externe dans les cinq secondes précédentes.

Aucun ajout de `unsafe-eval`, aucun filtre global sur les EvalError, aucun
changement de règle d’alerte Sentry. Une pile inconnue, un fichier applicatif,
une erreur chaînée ou une preuve externe absente reste transmis. Ce changement
traite le bruit de supervision ; il ne modifie pas le script de l’extension.

La documentation Sentry décrit le filtrage ciblé dans `beforeSend` :
https://www.sentry.help/en/articles/13965217-javascript-how-do-i-filter-events-based-on-the-entire-stack-trace

## Recette

- Tests unitaires : signature positive et contre-exemples conservés.
- TypeScript et build de production.
- Recette frontend dédiée `sentry-csp.yml`, cinq formats, Chromium/WebKit :
  connexion, affichage du mot de passe, navigation vers l’aide, retour et
  rechargements avec la CSP de `vercel.json`.
- Vrai SDK Sentry initialisé, enveloppes interceptées localement : rejeu
  synthétique de la sonde exclu ; témoin applicatif conservé ; véritable `eval`
  d’un script de la page déclenché au clic, bloqué et remonté comme erreur.
- Aucune connexion fournisseur, authentification réelle, opération financière
  ou livraison mobile dans ce banc. Les artefacts portent les snapshots ARIA
  et les reçus locaux ; ils ne prouvent pas une exécution sur appareil physique.

Les résultats finaux CI, revue et déploiement sont consignés dans la PR.
