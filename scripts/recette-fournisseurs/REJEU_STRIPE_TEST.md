# Rejouer un événement TEST existant

Le workflow manuel `resend-stripe-test-event.yml` fonctionne uniquement sur
`main`, avec le secret GitHub existant `STRIPE_TEST_SECRET_KEY`. Il ne crée
aucun paiement/remboursement et ne déploie aucune fonction. Un seul événement
est renvoyé par exécution, vers l'endpoint staging constant
`we_1UKmSiEVhQ7cb53WAuAljU47` du compte TEST `acct_1T9pt0EVhQ7cb53W`.

Ordre des trois exécutions, avec vérification après chacune :

1. `evt_3UKvRlEVhQ7cb53W0Ani5a0O` — `charge.pending`.
2. `evt_3UKvRlEVhQ7cb53W0GdDVERo` — `transfer.created`.
3. `evt_3UKvRlEVhQ7cb53W0fm2OFrt` — `transfer.reversed`.

**Ne jamais rejouer `evt_3UKvRlEVhQ7cb53W0HppECKN` (`charge.refunded`).**
Il est déjà traité ; le script le refuse avant toute requête réseau.

## Contrat du transport

Le script Python utilise uniquement la bibliothèque standard, sans installation
de CLI ni dépendance réseau. La route `POST /v1/events/{event}/retry` et son
paramètre `webhook_endpoint` sont ceux de la commande officielle
[`stripe events resend`, source 1.52.1](https://github.com/stripe/stripe-cli/blob/v1.52.1/pkg/cmd/resource/events_resend.go).
La [documentation Stripe](https://docs.stripe.com/cli/events/resend) limite le
rejeu aux événements de moins de 30 jours. La clé reste dans l'environnement du
runner ; aucun login, signing secret ou secret Supabase n'est nécessaire.

Quatre GET vérifient compte, mode, endpoint et événement avant l'unique POST.
Hôte/routes fixes, redirections interdites, aucun retry automatique, aucune
écriture sur les ressources charge/refund/transfer. La clé d'idempotence est
stable par événement et endpoint ; une réponse ambiguë impose une relecture
des preuves avant toute nouvelle exécution, même après 24 heures.

Le rapport expurgé `stripe-test-event-replay.json` contient seulement les
identités autorisées et le résultat de la demande : `RETRY_REQUESTED` ne prouve
pas la livraison ni la fin du traitement. `RETRY_UNCONFIRMED` signale qu'un
POST a été tenté sans résultat confirmable. Les payloads et erreurs Stripe ne
sont jamais imprimés. Les [retries automatiques Stripe](https://docs.stripe.com/webhooks#manual-retries)
peuvent encore survenir ; le handler conserve son idempotence par event ID.

## Précontrôle SQL du coordinateur, en lecture seule

Exécuter uniquement sur **`mejpriaetwgtcstbgfid`** et conserver les résultats
horodatés avant de cocher `sql_precheck_confirmed`. Cette case est une
attestation de l'opérateur, pas une preuve SQL produite par le workflow.

```sql
WITH escrow AS (
 SELECT id,mission_id,statut,montant_total_cents,honoraires_cents,
        commission_cents,stripe_payment_intent_id,stripe_charge_id
 FROM public.paiements_escrow
 WHERE id='d499ffe9-ef3f-4f4a-afe0-2f6de44af8d2'
), refunds AS (
 SELECT id,paiement_escrow_id,statut,stripe_payment_intent_id,stripe_refund_id,
        montant_cts,reverse_transfer,absorbe_plateforme,refund_application_fee_cts
 FROM public.stripe_refunds_queue
 WHERE paiement_escrow_id='d499ffe9-ef3f-4f4a-afe0-2f6de44af8d2'
    OR stripe_payment_intent_id='pi_3UKvRlEVhQ7cb53W0uXPCBVW'
    OR id='63476147-acbf-437d-b6e8-957e8acf160f'
), events AS (
 SELECT event_id,event_type,source_webhook,livemode,traite_le,
        traitement_commence_le,tentatives,(erreur IS NULL) AS erreur_absente
 FROM public.stripe_webhook_events
 WHERE event_id IN ('evt_3UKvRlEVhQ7cb53W0Ani5a0O',
  'evt_3UKvRlEVhQ7cb53W0GdDVERo','evt_3UKvRlEVhQ7cb53W0fm2OFrt',
  'evt_3UKvRlEVhQ7cb53W0HppECKN')
), audits AS (
 SELECT action,count(*) AS nombre FROM public.journaux_audit
 WHERE action IN ('FINANCE_CHARGE_PENDING','FINANCE_TRANSFER_CREATED',
  'FINANCE_TRANSFER_REVERSED') AND
  (details->>'stripe_charge_id'='py_3UKvRlEVhQ7cb53W0inCeFyg' OR
   details->>'stripe_transfer_id'='tr_3UKvRlEVhQ7cb53W0Fz396PB')
 GROUP BY action
)
SELECT jsonb_build_object(
 'capture_le',clock_timestamp(),
 'escrow',(SELECT coalesce(jsonb_agg(to_jsonb(e)), '[]') FROM escrow e),
 'refunds',(SELECT coalesce(jsonb_agg(to_jsonb(r) ORDER BY r.id), '[]') FROM refunds r),
 'events',(SELECT coalesce(jsonb_agg(to_jsonb(e) ORDER BY e.event_id), '[]') FROM events e),
 'audits',(SELECT coalesce(jsonb_agg(to_jsonb(a) ORDER BY a.action), '[]') FROM audits a),
 'bindings',(SELECT count(*) FROM public.stripe_transfers
  WHERE stripe_transfer_id='tr_3UKvRlEVhQ7cb53W0Fz396PB'),
 'crons_actifs',(SELECT count(*) FROM cron.job WHERE active),
 'releases_actives',(SELECT count(*) FROM public.escrow_release_queue
  WHERE statut IN ('EN_ATTENTE','EN_COURS')),
 'refunds_actifs',(SELECT count(*) FROM public.stripe_refunds_queue
  WHERE statut IN ('EN_ATTENTE','EN_COURS'))
) AS comparaison;
```

Avant chaque run, exiger : événement ciblé non traité et sans lease, source
PLATFORM/TEST, audit correspondant absent ; `charge.refunded` traité ; escrow
REMBOURSE **28356** centimes (24000 + 4356), exactement une queue TRAITE avec refund
`pyr_1UL0FKEVhQ7cb53W1ses2PZD`, montant 28356, reverse_transfer vrai,
absorbe_plateforme faux, fee 4356 ; zéro binding, cron ou file active.
Toute divergence arrête la séquence ; ne pas effacer un audit/claim pour forcer
un rejeu. Relire aussi le handler déployé : pending/created sont audit seuls,
et le fallback destination charge de reversed vérifie la chaîne puis audite,
sans mouvement financier. Si le bundle change, refaire cette revue.

## Après chaque run puis contrôle d'interface

Relire le même SELECT : event traité, erreur/lease NULL, audit attendu
présent, états/montants financiers inchangés et aucun binding/file apparu.
Relire chez Stripe TEST le même refund (succeeded, 28356) et le même transfert
(reversed, 28356/28356, une reversal) ; aucune nouvelle opération attendue.
Conserver la preuve de livraison au bon endpoint lorsqu'elle est accessible.
Un `pending_webhooks=0` global ne prouve pas à lui seul cet endpoint.

Recharger les écrans établissement et soignant de la mission
`17710768-4877-4e67-ba8d-80a3c5f7770d` : le remboursement reste affiché et
aucun paiement en attente ne réapparaît. Conserver les assertions frontend
et distinguer simulation UI, intégration Stripe TEST et production.

Tests locaux sans réseau ni secret :

```sh
python3 -m unittest discover -s tests/python -p 'test_resend_stripe_test_event.py' -v
```
