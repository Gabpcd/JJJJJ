# Statut Stripe : cohérence serveur et interface

Une lecture Stripe pouvait afficher un compte complet sans renseigner
`onboarding_complete` en base. Le traitement des primes pouvait alors conserver
un état incomplet malgré les autres indicateurs. Les deux écritures (lecture
du statut et webhook Connect) synchronisent désormais ces informations.

Une ligne de cache incohérente impose une nouvelle lecture Stripe. Aucun
backfill ne déclare des comptes complets à partir des seules données locales.
Le webhook relit le compte courant pour qu'un ancien événement rejoué ne
rétablisse pas un état complet après suspension. Une écriture refusée ou un
compte local remplacé ne produit pas de confirmation de réussite.

Dans l'écran Paiements, une erreur ou une réponse incohérente affiche un
message et un bouton Réessayer. Elle ne suggère plus de créer un compte Stripe
et n'affiche plus un faux succès d'actualisation. Le texte salarié distingue
le salaire versé par l'employeur du bulletin décrivant le montant dû.

## Vérifications locales

- 48 tests backend, dont 10 exécutent les vrais handlers avec des fournisseurs
  simulés : réparation du cache, trois critères de complétude, suppression,
  refus de persistance, événement ancien, idempotence et réessai.
- 20 scénarios frontend (quatre parcours sur cinq formats), sans retry :
  salarié, panne initiale, panne après succès, retour Stripe incohérent,
  reprise et rechargement. Captures iPad portrait et Android relues.
- Typecheck et compilation frontend réussis.

Ces scénarios ne déclenchent aucun versement, prime, remboursement ni nouvel
onboarding fournisseur. Ils ne constituent pas une preuve de virement bancaire.
Le dépôt du bulletin officiel et le regroupement de la paie par période restent
un chantier séparé.

La référence `public.sql` reprend exactement le snapshot produit après le
déploiement de la PR987. Elle ne contient pas de nouvelle migration à exécuter.
