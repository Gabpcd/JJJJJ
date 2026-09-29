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
Le retour Stripe lance une seule lecture forcée ; une génération de requête
empêche une ancienne réponse d'écraser une vérification plus récente.
Une panne ou une absence de profil affiche une erreur neutre avec réessai ;
elle ne classe jamais le compte en salarié par défaut.
Une réponse de revenus invalide ou en erreur masque les chiffres et affiche
une indisponibilité explicite ; aucun montant zéro n'est inventé et aucun NaN
n'est affiché. La fixture de revenus utilise les clés du vrai contrat SQL.

## Vérifications locales

- 48 tests backend, dont 10 exécutent les vrais handlers avec des fournisseurs
  simulés : réparation du cache, trois critères de complétude, suppression,
  refus de persistance, événement ancien, idempotence et réessai.
- 45 scénarios frontend (neuf parcours sur cinq formats), sans retry :
  profil en panne ou absent, réessai sans rechargement puis reprise ;
  salarié, panne initiale, panne après succès, retour Stripe incohérent,
  reprise, rechargement et absence de lecture cache concurrente au retour de
  Stripe en cas d'erreur ou de suspension ; revenus invalides, indisponibles puis
  reçus correctement. Captures iPad portrait et Android relues.
- Typecheck et compilation frontend réussis.

Ces scénarios ne déclenchent aucun versement, prime, remboursement ni nouvel
onboarding fournisseur. Ils ne constituent pas une preuve de virement bancaire.
Le dépôt du bulletin officiel et le regroupement de la paie par période restent
un chantier séparé.

La référence `public.sql` reprend exactement le snapshot produit après le
déploiement de la PR987. Elle ne contient pas de nouvelle migration à exécuter.

Cinq parcours supplémentaires avec le backend staging et Stripe TEST ont
confirmé le statut connecté, son actualisation et sa persistance après
rechargement, sur les mêmes cinq formats. La lecture en base confirme les
indicateurs cohérents. Aucun nouveau paiement, remboursement ou onboarding
n’a été lancé. Le simulateur utilise une origine locale déjà autorisée ;
aucune règle CORS n’a été élargie pour ce contrôle.
