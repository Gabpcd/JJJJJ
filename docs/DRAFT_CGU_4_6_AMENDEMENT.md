# DRAFT — Amendement CGU §4.6 « Paiement rapide ⚡ »

> **Statut : brouillon, hors code.** Protocole de validation : **Gabrielle valide
> chaque draft avant mise en ligne** (ce protocole tient lieu de relecture — pas
> de point avocat). Ne PAS publier tant que non validé.
> Référence : `src/pages/PageCGU.tsx:112-113` (texte actuel).

## Vocabulaire BANNI (transversal à toutes les clauses)

- ❌ « **garantie** » (au sens financier ou intérim) — Jolene ne garantit pas les
  fonds ; ils sont détenus par le prestataire de paiement.
- ❌ « **service de paiement fourni par Jolene** » — Jolene n'est pas
  établissement de paiement (agrément ACPR non détenu).
- ✅ **Formulation de référence** : « **Jolene agit en qualité de mandataire de
  facturation et d'encaissement du soignant ; les fonds sont détenus par
  Stripe** » (prestataire de services de paiement agréé).

## Texte actuel (§4.6)

> Pour les missions éligibles au paiement rapide, tes honoraires sont encaissés
> sur ton compte de paiement (Stripe) dès la confirmation de la mission […]

## Proposition d'amendement (chaque clause cite sa base légale)

> **4.6 — Paiement rapide ⚡**
>
> Jolene agit en qualité de **mandataire de facturation et d'encaissement** du
> soignant. Les fonds sont **détenus par Stripe** (prestataire de services de
> paiement), jamais par Jolene.
> <!-- base : mandat civil art. 1984 C. civ. ; Jolene hors monopole bancaire
>      art. L521-1 CMF (pas d'encaissement pour compte de tiers en propre —
>      c'est Stripe, agréé, qui détient les fonds). -->
>
> Pour les missions éligibles, le montant de tes honoraires **tel qu'établi à la
> confirmation** (« montant réservé ») est encaissé sur ton compte de paiement
> Stripe et libéré vers ton compte bancaire après validation de tes présences
> par l'établissement — au plus tard 72 heures après la fin de la mission
> (validation automatique à défaut de réponse).
> <!-- base : liberté contractuelle art. 1103 C. civ. ; le délai 72 h est un
>      engagement contractuel, pas une garantie financière. -->
>
> **Montant réservé — plancher.** Le montant réservé correspond aux heures
> prévues à la confirmation. Si les heures réalisées sont **inférieures** aux
> heures prévues, tu perçois néanmoins le montant réservé, sauf litige constaté
> et résolu selon l'article [litiges]. Aucune réduction automatique.
> <!-- base : art. 1103 C. civ. (force obligatoire du contrat) ; cohérent avec
>      la règle rémunération plancher (règle #11, GREATEST prévisionnel/effectif). -->
>
> **Heures supplémentaires.** Les heures réalisées **au-delà** des heures prévues,
> une fois validées par l'établissement, font l'objet d'un **règlement
> complémentaire** distinct (débit complémentaire sur le mandat de
> l'établissement), au même barème.
> <!-- base : art. 1103 C. civ. ; à ne publier qu'une fois la mécanique livrée
>      (Lot 13/14) ou à formuler au futur. -->
>
> **Échec de prélèvement.** Le versement est conditionné à l'encaissement effectif
> auprès de l'établissement. En cas d'échec, il est **suspendu le temps de la
> régularisation** ; tu en es informé. Le montant réservé n'est pas définitivement
> acquis tant que l'encaissement n'a pas eu lieu.
> <!-- base : condition suspensive art. 1304 C. civ. ; évite toute promesse de
>      garantie de paiement (interdit, cf. vocabulaire banni). -->
>
> En cas d'annulation **avant le début** de la mission, les sommes sont
> restituées à l'établissement.

## Clause de modification des CGU (nouvelle, transversale — article dédié)

> **Modification des CGU.** Jolene peut modifier les présentes CGU. Toute
> modification substantielle est **notifiée par email** aux utilisateurs
> concernés avant son entrée en vigueur. La **version en vigueur, datée**, est
> affichée en permanence dans l'application. La poursuite de l'utilisation vaut
> acceptation de la version en vigueur.
> <!-- base : art. L221-1 s. C. consommation (information précontractuelle) ;
>      RGPD art. 13 (information) ; loyauté contractuelle. Implémentation :
>      bandeau version datée + envoi email — à câbler (hors ce draft). -->

## Interdiction de transit de données patients (nouvelle — article données/usage)

> **Données de santé et de patients — interdiction.** Il est **strictement
> interdit** de faire transiter, via la messagerie ou tout champ libre de la
> Plateforme, des **données de santé ou identifiantes de patients** (nom, état
> de santé, données de soins). La Plateforme n'est pas un dispositif de
> traitement de données de santé et n'est pas hébergeur de données de santé
> (HDS). Tout manquement engage la responsabilité de l'utilisateur.
> <!-- base : art. L1110-4 CSP (secret médical) ; RGPD art. 9 (données
>      sensibles) ; art. L1111-8 CSP (HDS — Jolene HORS périmètre, cf.
>      docs/CONFORMITE.md). Implémentation : masquage/anti-fuite messagerie
>      (déjà partiel, cf. contact_leak_attempt) — renforcer côté champs libres. -->

## Validation

- **Gabrielle valide chaque draft** avant mise en ligne. Aucune publication
  automatique.
