# Recette financière intégrée — périmètre et résultats attendus

Cette recette doit partir des boutons de Jolene, puis rapprocher les mêmes
identifiants et centimes avec Stripe TEST et le staging
`mejpriaetwgtcstbgfid`. Les tests de configuration ne la valident pas.

## Constat du 28 septembre 2026, définition SQL staging relue

Le paiement interactif de la page Facturation établissement appelle
`stripe-connect-pay-mission`. C'est un paiement Connect groupant honoraires
et commission. Le résolveur de litige `fn_admin_resoudre_litige` choisit
explicitement `VIREMENT_MANUEL` lorsqu'un transfert Connect existe. Le worker
`process-stripe-refunds` refuse également ce paiement dans sa branche avoir
standard (`CONNECT_TRANSFER_REVERSAL_REQUIRED`). Ce circuit ne constitue
donc pas aujourd'hui un remboursement automatique intégré.

Ne pas supprimer ces deux protections pour faire réussir une recette : le
remboursement doit aussi traiter le transfert au soignant et rapprocher le
solde restant. La queue des avoirs standards exige actuellement que le montant
de la facture d'origine corresponde au montant total du PaymentIntent ; ce
n'est pas le cas d'un paiement Connect honoraires + commission.

Les remboursements escrow suivent un autre circuit. Ils passent par
`fn_escrow_rembourser`, notamment lors d'une validation d'accord de litige,
puis par la queue de remboursements. Une preuve de ce circuit ne couvre pas
le remboursement du bouton « Payer via Stripe » après mission.

## Matrice à exécuter

| Parcours | Action frontend | Contrôle fournisseur et base |
|---|---|---|
| Paiement Connect | Facturation → Payer via Stripe → carte TEST | Session TEST, montant honoraires + commission, paiement acquis, transfert exact, factures payées |
| Paiement refusé | Même formulaire avec carte TEST refusée | Message lisible, facture impayée, aucun faux encaissement |
| Reprise | Rechargement après succès, nouveau clic éventuel | Aucun second paiement ni second transfert |
| Correction Connect | Litige → résolution avec montant réduit | Avoir conservé ; état de traitement manuel visible tant que le reversal intégré n'est pas implémenté |
| Escrow remboursable | Accord de litige → validation administrateur | Une queue, un remboursement TEST réussi, reversal conforme à l'état escrow, rapprochement des mêmes montants |
| Retour utilisateur | Facturation établissement + revenus soignant après rechargement | États concordants avec les écritures et Stripe TEST |

Les vues établissement se vérifient au minimum en 390 × 844 et 1440 × 900,
ainsi que sur tablette et Android selon le parcours. Conserver les assertions
et dumps ARIA avant/après, sans mot de passe, session ni secret Stripe.

## Prérequis encore à attester avant création d'acteurs financiers

- Configuration des PR978 et979 effectivement exécutée sur staging.
- Clé publique TEST du frontend associée au même compte que les handlers,
  attestée par la lecture d'une Session Checkout avant sa confirmation.
- Acteurs nouveaux et isolés, aucun changement de cohorte d'un compte existant.
  Le staging a actuellement `inscriptions_publiques_actives=0` : ses créations
  ordinaires sont donc volontairement classées test et exclues des paiements.
  Il faut définir et relire le mode de préparation des acteurs admissibles,
  sans retirer cette exclusion ni réutiliser les comptes fixes des autres tests.
- Routage des appels serveur de staging vérifié. La présence d'un nom Vault
  n'atteste pas sa valeur ; l'accès MCP ne permet pas de déchiffrer ces valeurs.
  Le workflow de bootstrap staging dispose déjà d'un contrôle SQL de routage
  via ses accès dédiés. Aucun secret ne doit sortir dans un rapport.
- `generate_invoice_url` est absent dans `parametres_litiges` du staging :
  la régénération automatique d'un avoir par ce chemin n'y est pas configurée.
- Crons inactifs et queues financières étrangères vides avant chaque action
  de worker ; conservation explicite des écritures financières non supprimables.

**Statut : non exécutée.** Aucun paiement ou remboursement n'est prouvé par ce
document. Le harnais historique `recette-escrow-stripe.ts` reste verrouillé.
