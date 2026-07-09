# Flux monétaire — Paiement rapide (escrow 7b-D)

> Décrit le circuit RÉEL des fonds (code prod, validé recette run #12). Sert de
> **référence pour le gate CGU §4.6** (localisation exacte des fonds pendant la
> rétention). À recroiser avec le draft CGU avant toute mise en ligne.

## 1. Circuit technique (destination charge Stripe)

Acteurs : **établissement** (payeur, mandat SEPA), **Jolene** (plateforme Stripe
Connect, mandataire), **soignant** (compte Stripe Connect Custom, `payouts.schedule
= manual`).

1. **Débit** (`escrow-debit-echeance`, à échéance) : `PaymentIntent` de type
   destination charge —
   - `amount` = `montant_total_cents` (honoraires + commission)
   - `customer` = étab, `payment_method` = mandat SEPA de l'étab, `off_session`
   - `mandate_data: {customer_acceptance: {type: "offline"}}`, **pas de
     `on_behalf_of`** (le mandat SEPA nomme Jolene comme créancier)
   - `application_fee_amount` = `commission_cents` (part Jolene)
   - `transfer_data.destination` = compte connecté du **soignant**
   → marchand du débit = **Jolene** ; à l'issue du settlement, **les honoraires
     arrivent sur le solde du compte connecté du soignant**, la **commission** sur
     le solde plateforme Jolene.
2. **Settlement SEPA** (J+quelques jours) : `payment_intent.succeeded` → escrow
   `INITIE → DEBITE`. Les honoraires sont **`pending` puis `available` sur le
   solde connecté du soignant** ; le **payout est bloqué** (`manual`).
3. **Libération** (`escrow-release`, après validation des présences + fonds
   `available`) : `payouts.create` **manuel** sur le compte connecté → virement
   vers le compte bancaire du soignant. Escrow → `PAYE`.

**Invariant vérifié (recette)** : les honoraires ne **STATIONNENT jamais** sur le
solde plateforme de Jolene — seule la commission (application fee) y reste.

### 1 bis. « Ne stationne jamais » ≠ « ne transite jamais » (distinction exacte)

Formulation **précise**, car la mécanique d'une *destination charge* l'impose :

- **Transiter** : à l'instant du settlement, la charge est portée par le compte
  **plateforme** Jolene (Jolene = **merchant of record**, cf. mandat SEPA qui la
  nomme créancier, `on_behalf_of` retiré v15). Stripe crée **simultanément** le
  transfer vers le compte connecté du soignant (`transfer_data.destination`).
  → Les honoraires **transitent** donc le temps d'un battement comptable par la
  plateforme (inhérent aux destination charges).
- **Stationner** : **jamais**. Aucun solde d'honoraires ne *reste* / ne *repose* sur
  le compte Jolene : le transfer part avec la charge, le net plateforme = la seule
  application fee. **Ni cantonnement, ni détention prolongée** côté Jolene.

→ **Wording CGU/produit correct** : « les honoraires ne **stationnent** jamais sur
un compte Jolene ; ils sont **détenus par Stripe** sur le compte connecté du
soignant, payout **manuel** contrôlé par Jolene ». **Ne pas** écrire « ne transitent
jamais » (techniquement faux) — écrire « ne stationnent jamais ».

## 2. Rétention — où sont les fonds ? (question pour le gate CGU)

Pendant la rétention (entre settlement et libération), les honoraires sont sur le
**solde du compte connecté Stripe du soignant** (statut `available`, payout
`manual` contrôlé par Jolene). Ce ne sont donc **pas** des fonds sur un compte
Jolene, mais des fonds **détenus dans l'écosystème Stripe sur le compte du
soignant**, dont **Jolene contrôle la libération** (déclenchement du payout après
validation des présences).

**À trancher pour la CGU** (formulation « conservé par Stripe jusqu'à sa
libération ») :
- Techniquement exact : les fonds sont chez Stripe, pas chez Jolene.
- Nuance à qualifier : ils sont sur le compte connecté **du soignant**, la
  libération étant conditionnée (validation présences + encaissement effectif) et
  déclenchée par Jolene (mandataire). Vérifier que « conservé par Stripe » ne
  laisse pas entendre une détention par Jolene ni une propriété acquise du
  soignant avant libération.
- **DSP2 art. 3, b)** (exemption agent commercial) + transposition CMF : à
  documenter ici pour porter l'analyse (L521-1 seul ne suffit pas).

## 3. Notes produit associées (hors CGU)

- **Indemnité d'annulation tardive côté soignant** : décision **future
  (Lot 13/16)**. À ce jour, aucune indemnité ; la clause CGU §4.6 « en cas
  d'annulation avant le début, restitution à l'établissement » **reste fidèle au
  code existant** (`fn_escrow_rembourser` sur annulation). Ne rien promettre
  d'autre tant que le mécanisme n'existe pas.
- **Surplus heures sup** (effectif > prévisionnel) : non couvert, débit
  complémentaire à venir (Lot 13 déclencheur / Lot 14 mécanique), cf.
  `docs/SPEC_ESCROW_REVENUS_SOIGNANT.md` §9.3.
