# D2 : ouvrir la mission depuis son lien dans le tableau de bord

Le sixième pilote `36748309666`, tête `dfd3d71e4334f2c32baa6904d308767d3221427f`, échoue le 30 septembre 2026 à la capture de la candidature du second soignant. Le titre principal passe ; ce n’est pas la réapparition du sélecteur ambigu précédent.

Les deux appels POSTULER répondent HTTP 200 et passent la vérification de réponse du runner. Le premier parcours termine son rechargement. Une pageerror WebKit de catégorie `controle_origine` survient pour le second soignant à 22 890 ms, 31 ms après le début de `mission_navigation`. Aucun HTTP en erreur ni refus du garde n’est enregistré. La capture reste bloquée par cette erreur, comme prévu ; le parcours établissement n’est pas exécuté.

## Nettoyage vérifié indépendamment

Après les étapes cleanup réussies du workflow, trois SELECT construits par les fonctions existantes du préparateur et du contrat UI sont exécutés sur le staging seulement :

- zéro compte Auth, profil, établissement, mission, créneau, candidature, préférence, notification, rate limit, session et identité du lot ;
- quatre audits conservés : deux connexions et les reçus prepare/cleanup ; reçu cleanup exact présent ;
- zéro email, token push et présence pour chacun des trois comptes ; activité des profils absente après nettoyage ;
- empreintes schéma/fonctions/triggers identiques au catalogue figé, zéro cron actif et zéro FK audit ciblée.

`validerEtatD`, `validerCatalogueD` et `verifierAuditsD` valident ces lectures. Elles ne provoquent aucune mutation. Le jour auxiliaire utilisé pour reconstruire le manifeste n’entre dans aucun de ces SELECT : les identifiants dépendent exclusivement du run. Les JSON et les requêtes sont conservés sous `/private/tmp/jolene-d2-36748309666-artifact/`. Le ZIP filtré de 1,74 Mo est conservé ; seules ses petites entrées JSON sont extraites.

## Reproduction causale locale

La comparaison utilise le build compilé F1 `c33fa55d`, un formulaire de connexion réel avec identité fictive et deux origines loopback distinctes. Toutes les réponses métier sont simulées ; aucune requête Supabase distante ni candidature n’est émise. Les requêtes de la première vague dashboard sont contrôlées par une promesse, sans sleep. Leur finalisation déclenche ensuite les lectures de métadonnées et de créneaux côté navigateur.

| Navigation après la première vague | Résultat |
|---|---|
| `page.goto` dès retour du drain | Deux pageerrors WebKit `controle_origine`, portant sur `missions` et `mission_creneaux` |
| Attendre/clique sur le vrai lien de mission | Le lien attend le rendu du planning ; zéro pageerror, le détail est visible |

La reproduction contrôle cet entrelacement ; elle ne prétend pas rejouer le scheduler Linux ni le timing exact de networkidle du run distant. La seconde vague commence 3 à 4 ms après le retour du drain dans les reproductions. `drainer()` attend les opérations déjà connues ; sa résolution ne prouve pas que React a consommé les réponses et lancé toutes les lectures dépendantes. La navigation remplaçant le document peut donc interrompre cette seconde vague. Le lien React évite cette interruption et suit le parcours disponible à l’utilisateur.

Cette comparaison reproduit le mécanisme et la catégorie, **pas l’empreinte exacte du message distant**. La ressource précise du message distant n’est donc pas affirmée. Les trois comparaisons et tous les messages projetés sont conservés. Deux avertissements console communs au banc (dont un lié au service worker bloqué) restent dans les preuves ; ils ne sont ni filtrés ni présentés comme une preuve zéro console warning.

## Correction et couverture

Le seul changement de comportement du runner est le clic sur le lien accessible exact `Voir la mission …`, au lieu de `page.goto` après connexion. Aucun endpoint, budget d’écriture, garde, délai ou traitement d’erreur ne change. Les erreurs navigateur restent bloquantes. Le parcours établissement et les rechargements explicites restent inchangés.

La recette existante commence maintenant par le formulaire de connexion fictif pour les deux soignants, puis reprend les barrières URL, activité et networkidle. Le nombre de documents chargés est vérifié : un jusqu’au dépôt (page de connexion initiale), deux après le rechargement explicite. Un hard reload entre dashboard et mission fait donc échouer cette assertion. Les tests de lien profond et de titre identique restent présents, ainsi que les erreurs navigateur synthétiques bloquantes.

Validation : **15/15 simulations** (trois cas × ordinateur, iPhone, Android, iPad portrait et paysage), zéro skip, retry ou flaky ; **24/24 tests Node**, typecheck E2E ciblé avec analyse des imports JS, `tsc -b` et diff-check verts. L’ajout explicite de `location: undefined` et `stack: undefined` corrige l’appel de test lors de ce typecheck plus strict, sans changer son comportement. La matrice conserve les contrôles réseau et pageerror préexistants ; elle ne constitue pas une nouvelle assertion générale sur tous les avertissements console.

Preuves : `/private/tmp/jolene-d2-36748309666-diagnostic/`, archive compacte avec manifeste sous `audits/2026-09-30-preparation-nationale/preuves/d2-navigation-dashboard-spa/` du workspace Jolene. Aucun septième pilote staging n’a été déclenché par ce lot. Sa validation intégrée reste à effectuer après revue ; le run rouge précédent n’est pas requalifié en succès.
