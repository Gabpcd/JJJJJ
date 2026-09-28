# Confirmations financières — simulation frontend du 28 septembre 2026

## Corrections

- Administration, Litiges : la validation d'un accord ne présente plus un
  remboursement mis en file comme un mouvement financier déjà exécuté. La
  réponse doit confirmer le statut résolu et l'exécution de l'accord. Une
  réponse vide ou incomplète affiche une incertitude, puis relit le dossier.
  Pendant la requête, les boutons de validation sont désactivés.
- Soignant, Mes gains : un paiement rapide annulé reste visible dans « Annulés ».
  Il reste séparé des paiements à venir et versés ; leurs calculs sont inchangés.

## Résultats

35 simulations Playwright réussies : sept scénarios sur cinq formats
(iPhone 390×844, Android, iPad portrait et paysage, ordinateur 1440×900).
Les réponses backend sont **simulées** ; aucun compte réel ni paiement Stripe
n'est créé par ces tests.

Administration : remboursement en attente, réponse vide, succès incomplet,
refus métier, réponse perdue après validation, réponse lente avec second clic.
Assertions : message exact, statut du dossier, une seule requête de validation,
reprise après rechargement pour les cinq scénarios de réponse, absence de
débordement et d'erreurs JavaScript. La réponse lente vérifie aussi le bouton
désactivé pendant la requête.

Soignant : annulation de 255,00 €, réservation de 90,00 € et versement de
100,00 € présents simultanément ; l'annulation est isolée dans sa rubrique.
Après rechargement avec le seul paiement annulé, celui-ci reste visible.

Les tests conservent des dumps ARIA avant/après et des captures iPad dans les
artifacts Playwright. Le journal local complet et les preuves sont archivés
dans l'audit du projet (`finance-ui/preuves-35-simulations`). TypeScript, build,
lint ciblé et test Vitest préexistant du lien litige réussis.

## Texte visible

Avant : « Accord validé — mouvement financier exécuté. »

Après : « Accord validé. Consultez le suivi des paiements pour confirmer le
traitement financier. »

Réponse non confirmée : « La validation n’a pas été confirmée. Actualisez le
dossier avant de réessayer. »

Soignant : région « Paiements rapides annulés », titre « Annulés », libellé
« Paiement annulé », montant « 255,00 € » dans le scénario de recette.

## Limites

Ces assertions ne prouvent pas un paiement ni un remboursement Stripe TEST.
La recette intégrée restante est détaillée dans
[`RECETTE_FINANCIERE_INTEGREE.md`](../RECETTE_FINANCIERE_INTEGREE.md).
Un échec de relecture du dossier peut laisser l'ancien état à l'écran ; la
protection contre une seconde exécution métier reste assurée par le verrou
et le contrôle d'exécution de la RPC, pas uniquement par l'interface.
