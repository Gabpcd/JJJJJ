# Versement bancaire Connect standard

Le paiement carte reste un Checkout plateforme, puis un transfert des honoraires TTC exacts vers le compte Connect. La commission TTC reste chez Jolene avant frais Stripe. Ce transfert ne prouve pas une arrivée à la banque.

Les comptes conservent `settings.payouts.schedule.interval=manual` : passer tout un compte en automatique pourrait libérer également des fonds du circuit escrow. Le cron authentifié `escrow-release` exécute désormais un consumer standard distinct après son consumer escrow existant. Aucun nouveau cron, secret, SDK ou version d'API n'est nécessaire.

Le ledger reste `stripe_transfers`. Un trigger admet seulement une nouvelle transition TRANSFERE liée à une intention canonique TRANSFER (Session, charge, pièces, acteurs et montants exacts). Les lignes historiques ne sont pas réadmises automatiquement. Les RPC service-only prennent un lease et utilisent l'ordre de verrouillage mission → trace → honoraires → commission → intention. La barrière générale Connect reste exigée avant un nouveau payout.

Avant création, le consumer relit le compte Connect et sa metadata propriétaire, la charge/PaymentIntent acquis et le transfert exact. Il vérifie ensuite le paiement reçu sur le compte connecté (`transfer.destination_payment`), sa balance transaction réellement `available` et son montant net exact, puis le solde EUR/card disponible. Un solde global positif, qui peut contenir des fonds escrow, ne suffit pas.

Chaque tentative possède la clé `connect_payout_<trace>_<attempt>`, des metadata exactes et une fenêtre de création de vingt heures. Une réponse perdue ou une persistance indisponible conserve la tentative ; une liste de payouts complète et bornée récupère d'abord l'objet exact. Hors fenêtre sans objet, ou si le listing est incomplet/ambigu, l'état devient REVIEW, sans nouvelle création aveugle. Les reprises terminales n'ont une nouvelle clé qu'après constat du payout failed/canceled et de sa balance transaction de retour available ; au plus trois nouvelles tentatives sont admises.

Un payout pending/in_transit reste SUBMITTED. Le cron et les webhooks Connect relisent le même objet courant ; seul `paid` met la trace à PAYE. Un échec bancaire conserve TRANSFERE et un état bancaire FAILED : il ne relance jamais la charge client ni le transfert. Un statut contradictoire exige une revue, sans cacher le reçu historique. Les transitions paid/failed/canceled sont auditées atomiquement.

La migration retire INSERT/UPDATE/DELETE client sur `stripe_connect_onboarding`, conserve la lecture sous RLS et ajoute un trigger INSERT/UPDATE serveur. Les fonctions onboard et account.updated restent les producteurs des références/capacités Stripe. Elle n'a pas d'effet rétroactif d'audit ou de réparation des références existantes.

## Validation et livraison

Appliquer la migration fermée avant de déployer `escrow-release`, `stripe-webhook` et `stripe-connect-webhook`. Faire relire leurs sources/pins, puis vérifier le cron existant et les abonnements payout.created/paid/failed/canceled. La migration ne modifie pas la valeur du gate général. Les tests du helper utilisent des transports simulés ; le test SQL ACL utilise les rôles réels dans une transaction de base éphémère. Ces tests doivent être exécutés par root ; ils ne prouvent pas une banque ni un fournisseur.

La recette Stripe TEST doit payer un Checkout TEST admis, constater le transfert vers le bon compte TEST et attendre la contribution `available` de son paiement destination. Elle doit observer un payout TEST unique, sa réception webhook et le passage PAYE, y compris réponse perdue/reprise avec même ID, sans charge ni transfert supplémentaires. Les deux interfaces doivent distinguer transfert et versement bancaire, sur les cinq formats, avec reload. Aucun effet LIVE ne fait partie de cette recette.

Le supplément staging actuel n'autorise que REFUND et interdit TRANSFER. Il ne faut ni le détourner ni reclasser les acteurs TEST. Un raccord séparé est requis : capacité serveur TEST bornée au run/SHA/expiration/acteurs/pièces/compte/charge/transfert exacts, droit explicite `transfers_allowed` puis `payouts_allowed`, signatures de RPC TEST distinctes et refus ancré sur production. Le consumer standard doit alors réutiliser les mêmes validations source et le même ledger via cet adaptateur borné ; aucune ouverture générale ou suppression de l'exclusion TEST. Cette proposition est distincte du code de production présent et n'est pas une capacité allouée ni un test exécuté.

Références : [payouts manuels](https://docs.stripe.com/connect/manual-payouts), [objet Transfer et paiement destination](https://docs.stripe.com/api/transfers/object), [RLS et privilèges Supabase](https://supabase.com/docs/guides/database/postgres/row-level-security).
