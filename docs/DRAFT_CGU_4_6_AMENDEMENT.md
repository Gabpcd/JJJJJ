# DRAFT — Amendement CGU §4.6 « Paiement rapide ⚡ »

> **Statut : brouillon, hors code.** À valider par la fondatrice, puis relecture
> avocat avant soumission/publication. Ne PAS pousser en prod tant que non validé.
> Référence : `src/pages/PageCGU.tsx:112-113` (texte actuel).

## Texte actuel (§4.6)

> Pour les missions éligibles au paiement rapide, tes honoraires sont encaissés
> sur ton compte de paiement (Stripe) dès la confirmation de la mission, et
> libérés vers ton compte bancaire après la validation de tes présences par
> l'établissement — au plus tard 72 heures après la fin de la mission
> (validation automatique en l'absence de réponse de l'établissement). En cas
> d'annulation de la mission avant son début, les sommes sont restituées à
> l'établissement.

## Manques identifiés (investigation code, §9 de la spec)

1. Le montant réservé = celui de la confirmation (prévisionnel). Le texte ne dit
   pas qu'il est **garanti comme plancher** même si moins d'heures sont
   validées (règle rémunération `GREATEST`, tâche #11).
2. Rien sur le cas **heures supplémentaires validées** (surplus) → débit
   complémentaire à venir (Lot 13/14).
3. Rien sur le **comportement en cas d'échec du prélèvement** de l'établissement.

## Proposition d'amendement (à faire relire)

> **4.6 — Paiement rapide ⚡**
>
> Pour les missions éligibles, le montant de tes honoraires **tel qu'établi à la
> confirmation de la mission** (« montant réservé ») est encaissé sur ton compte
> de paiement (Stripe) et libéré vers ton compte bancaire après validation de
> tes présences par l'établissement — au plus tard 72 heures après la fin de la
> mission (validation automatique en l'absence de réponse).
>
> **Montant réservé — plancher.** Le montant réservé correspond aux heures
> prévues à la confirmation. Si les heures effectivement réalisées sont
> **inférieures** aux heures prévues, tu perçois néanmoins le montant réservé,
> sauf litige dûment constaté et résolu selon l'article [litiges]. Aucune
> réduction n'est appliquée de façon automatique.
>
> **Heures supplémentaires.** Si des heures réalisées **au-delà** des heures
> prévues sont validées par l'établissement, elles font l'objet d'un **règlement
> complémentaire** distinct (débit complémentaire sur le mandat de
> l'établissement), au même barème (honoraires + majorations éventuelles).
>
> **Échec de prélèvement.** Le versement de tes honoraires est conditionné à
> l'encaissement effectif auprès de l'établissement. En cas d'échec du
> prélèvement, le versement est **suspendu le temps de la régularisation** ; tu
> en es informé, et Jolene relance l'établissement. Le montant réservé n'est pas
> définitivement acquis tant que l'encaissement n'a pas eu lieu.
>
> En cas d'annulation de la mission avant son début, les sommes sont restituées
> à l'établissement.

## Points d'attention pour l'avocat

- « montant réservé » vs « garanti » : cohérence avec la réalité technique
  (l'encaissement peut échouer — état `ECHOUE`) → ne pas promettre un absolu.
- Articulation avec la clause litige (seule voie de réduction).
- Le règlement complémentaire des heures sup n'est pas encore implémenté
  (Lot 13/14) — ne publier cette clause qu'une fois la mécanique livrée, ou la
  formuler au conditionnel/à venir.
