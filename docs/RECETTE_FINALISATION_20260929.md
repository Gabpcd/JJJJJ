# Finalisation du 29 septembre 2026

## Périmètre intégré

La PR de finalisation reprend les corrections relues des PR983 (référence du
schéma et déclencheur du snapshot), 984 (rapprochement des remboursements et
audit financier), 986 (reprise native, inscription aux notifications et avis
de mise à jour), ainsi que le suivi financier corrigé dans la PR987.
Les contrôles CI et la revue finale doivent porter sur leur combinaison exacte.

La PR985 est déjà sur `main`. Les livraisons mobiles sont **manuelles** et le
workflow GitHub est désactivé pendant les corrections. Aucun build destiné aux
stores, aucune OTA et aucune soumission ne fait partie de cette finalisation.
Les builds web de vérification et la simulation Android restent des tests.

## Suivi financier : corrections et preuves

- La table `paiements_escrow` reste privée. La première tentative de lecture
  directe a échoué réellement avec HTTP403 ; elle a été remplacée par
  `fn_suivi_escrow_mission`, qui retourne uniquement `statut` et `paye_le`.
- La RPC vérifie le compte actif, la mission et le soignant affecté ou les
  droits financiers dans l'établissement. Les accès d'autres utilisateurs,
  des membres sans droits financiers, des comptes suspendus et sans session
  sont refusés. La suite SQL est exécutée sous `ROLLBACK` sur staging ; aucun
  élargissement de SELECT sur la table financière.
- Le suivi distingue prélèvement, fonds disponibles, versement, litige,
  remboursement demandé et confirmé. Un remboursement n'est jamais une
  confirmation de réception par le soignant. Les états de mission LITIGE,
  ABSENCE et EXPIREE ne sont plus traités comme inconnus.
- Lorsqu'un paiement intégré existe, le formulaire de déclaration d'un
  second virement manuel est retiré. Les honoraires contractuels affichés ne
  sont pas présentés comme un solde restant à verser.
- En cas de panne de lecture du blocage d'utilisateur : statut inconnu,
  réessai explicite, sans supposer l'utilisateur débloqué. Les requêtes sont
  bornées et annulées au démontage. Un échec d'action laisse un message et
  permet de réessayer.

Preuves locales avant intégration finale : 55 scénarios de suivi financier
avec réponses simulées et 15 scénarios remboursement/blocage sur les cinq
formats, sans retry. Les 10 parcours réels (2 rôles × 5 formats) se connectent
aux comptes fictifs isolés et relisent le remboursement existant dans le
staging avant/après rechargement : RPC200 et aucun formulaire de second
paiement. Les assertions, dumps ARIA et captures sont conservés dans l'audit
local `finance-ui/remboursement-reel` ; aucune identité réelle ou secret n'est
nécessaire dans le dépôt public.

Le rechargement réel intervient après chargement complet. Un diagnostic de
rechargement immédiat a montré que WebKit peut remonter une annulation fetch
au niveau natif comme `pageerror`, sans événement `window.error` ni rejet non
géré. Cette observation reste tracée ; aucune exception n'est filtrée dans
le replay réel final. Le scénario de requête suspendue puis rechargement est
exercé séparément par `recette-complete-blocage-reprise.spec.ts`.

Le remboursement fournisseur utilisé est en **Stripe TEST** : 283,56 € au
total, dont 240,00 € d'honoraires et 43,56 € de commission. Le remboursement,
le reversement inverse et le remboursement de commission ont été rapprochés
sur les mêmes objets. Cette PR ne crée aucun nouveau mouvement fournisseur.

## Distinctions conservées

Le circuit salarié demande le net exact du bulletin officiel pour enregistrer
le virement de l'employeur. Une estimation, une déclaration de paiement et une
confirmation de réception sont des états distincts. Cette PR ne crée pas un
service de paie et n'implémente pas le dépôt du bulletin officiel.

La preuve financière ci-dessus couvre le remboursement du circuit escrow.
Elle ne prouve pas le remboursement automatique du paiement Connect interactif
après mission : la limite indiquée dans `RECETTE_FINANCIERE_INTEGREE.md` reste
à traiter séparément. Le rapprochement des webhooks secondaires doit être
rejoué après déploiement des handlers corrigés en staging.

Les interfaces natives utilisent un pont simulé : cela couvre les retours
au dashboard, formulaires/modales/signatures préservés, liens de notification,
avis du store et erreurs réseau. La réception effective APNs/FCM sur un
téléphone verrouillé et la disponibilité du plugin de mise à jour dans le
prochain binaire nécessitent encore une validation sur appareils physiques.
Ces tests ne constituent pas une déclaration de préparation nationale complète.
