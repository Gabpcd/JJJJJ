# Préférences, administration et groupe — corrections du 25 septembre 2026

Lot frontend sur la branche `fix/preparation-lancement-national`, base `ec2315473c0b619ae5f97a489fbab3c71969315f`. Modifications non commitées, dans le checkout partagé `/private/tmp/jolene-recette-complete-20260924`. Les empreintes des 15 fichiers du lot sont conservées dans `resultats/admin-groupe/manifest-source.json` du dossier d’audit permanent.

## Résultat et périmètre

Les défauts G01 et AG01–AG07 de la revue ciblée sont corrigés. **20 scénarios navigateur distincts sur cinq formats passent**, sans retry ni skip. **18 nouveaux tests unitaires passent**, ainsi que les 13 contrôles existants ciblés (31 cas uniques). Le compilateur application et ESLint passent sur les fichiers du lot. Aucune modification de droits, migration ou envoi réel d’email n’a été effectuée dans ce lot.

| Exigence | Comportement corrigé | Preuve |
|---|---|---|
| G01 Préférences | Une lecture HTTP503, une réponse inexploitable ou l’échec de lecture SMS empêche l’accès au formulaire et toute sauvegarde ; réessai explicite. Les préférences chargées appartiennent à l’utilisateur/périmètre courant. Aucun flag SMS absent du profil minimal n’est proposé à la sauvegarde. | Unités deux rôles + panne SMS ; 10 cas navigateur (2 rôles × 5 formats), contrôle du payload conservant email/push désactivés et choix par événement. |
| AG01 Envoi groupe | Contrôle de `data/error`, refus des succès encore en cours ou ignorés ; brouillon conservé et résultat partiel visible. Même clé d’idempotence lors du réessai, destinataires déjà confirmés exclus ; pas de double clic concurrent. | Unité avec succès A, HTTP503 B, reprise B seule et même clé. |
| AG02 Groupe établissement | Utilise `useEtablissementScope().etablissementId`, et non l’identifiant utilisateur. Panne distincte d’un établissement indépendant ; réessai et garde de résultat après changement de scope. | Unité et 5 cas navigateur avec utilisateur et établissement d’identifiants différents, panne puis groupe peuplé et badge « Vous êtes ici ». |
| AG03 Statistiques en panne | Chaque lecture vérifie ses erreurs ; compte nul ne devient pas zéro. Chargement, erreur et réessai sont distincts ; une ancienne sélection ne remplace pas la nouvelle. | Unités panne/reprise et réponse tardive ; 5 cas navigateur de panne puis reprise. |
| AG04 Sélection groupe | Un même ensemble d’établissements alimente requêtes, nombre actif et tableau. Liste des missions paginée par 1 000 ; quatre cartes sur deux colonnes jusqu’à xl. Trois listes déroulantes nommées pour l’accessibilité. | Unité et navigateur avec A/B puis A seul : B absent du tableau et nombre actif égal à 1 ; contrôle absence de débordement document. |
| AG05 Email de test | Promesse rejetée ou réponse non confirmée : erreur française, bouton libéré en `finally`, réessai avec même clé. Historique en erreur distinct d’une liste vide. | Unités rejet réseau/reprise, pending, skipped, success:false, null et historique503/reprise. |
| AG06 Copie commerciale | Succès affiché après résolution du presse-papier seulement, erreur en cas de refus et nouvelle tentative possible. | Unité intégrée à la page AdminSales : promesse en attente, rejet, puis réussite au second clic. |
| AG07 Lectures admin | Équipe, configuration, contrats et modèles affichent une erreur durable/réessai ; les résultats obsolètes ne remplacent pas les lectures récentes. Réponse invalide traitée comme erreur. | Quatre unités 503 puis réponse vide contractuelle. |

## Exécution

- `npx tsc --project tsconfig.app.json --noEmit` : vert ; journal final vide. Ne pas confondre avec la commande sans `--project`, qui ne vérifie pas l’application dans ce dépôt.
- ESLint ciblé sur les 15 fichiers source/tests : 0 erreur, 0 avertissement.
- Première passe ciblée de quatre fichiers Vitest : 30/30 ; ajout du contrôle copie, fichier AdminContinuite repris 12/12. Union : 31 cas uniques, dont 18 nouveaux, sans décompter deux fois les reprises.
- Bundle Vite dédié `/private/tmp/jolene-admin-groupe-8901`, API configurée sur `http://127.0.0.1:8901`, DSN/Turnstile absents. Aucun `dist` du dépôt créé.
- Playwright : `e2e/recette-complete-admin-groupe.spec.ts`, 4 scénarios × iPad portrait WebKit 820×1180, iPad paysage WebKit 1180×820, iPhone WebKit 390×844, Android Chromium et ordinateur Chromium 1440×900. Résultat final : **20 passed**, 0 failed, 0 flaky, 0 skipped, 57,7 secondes, début `2026-09-25T10:11:08.972Z`.
- Diagnostic antérieur : 3/4 sur iPad. Le quatrième échouait parce que l’assertion ciblait le parent du titre KPI sans sa valeur ; snapshot et capture montraient bien 1. Le sélecteur a été corrigé, puis les quatre scénarios ont été rejoués sur les cinq formats. Cette passe n’ajoute pas de cas uniques.

## Preuves et limites

Les résultats, journaux, ARIA et captures sont archivés hors Git dans `/Users/gabrielle/Documents/Claude/Projects/Jolene/audits/2026-09-25-lancement-national/resultats/admin-groupe/`. Les captures iPad du groupe sélectionné et du groupe d’un établissement invité ont été relues ; les rubriques attendues sont présentes et les cartes restent lisibles.

Les helpers soignant/établissement existants bloquent les WebSockets et le réseau externe, retirent les hints preconnect/dns-prefetch, refusent les endpoints non déclarés. Le complément groupe autorise seulement GET/HEAD sur ses trois tables, refuse les autres méthodes et fournit des comptes cohérents avec ses seules missions ouvertes. Les connexions passent par le vrai formulaire de l’application, avec session et backend simulés. Aucun email réel ni mutation admin distante, aucun secret dans les fixtures.

Cette preuve est une recette frontend simulée, pas une validation RLS réelle, une preuve de délivrabilité email ou une certification de toutes les interfaces administrateur. Les pages email/équipe/configuration/contrats/modèles et la copie ont des preuves unitaires ; les 20 parcours navigateur concernent uniquement notifications, tableau de groupe et rattachement établissement. La pagination a été corrigée mais un jeu supérieur à 1 000 missions n’a pas été exécuté dans cette matrice. La reprise idempotente d’email est conservée tant que la page reste montée ; elle ne constitue pas une file persistante après rechargement.

Relecture indépendante Banach des trois pages notifications/groupe : aucun défaut P1/P2 démontré. Limite adjacente héritée signalée : une sauvegarde des préférences terminant après le départ de l’écran peut encore émettre un toast global. Aucun statut de livraison native ou de CI future n’est déduit de ces tests locaux.
