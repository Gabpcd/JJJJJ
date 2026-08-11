# DRAFT — Amendement CGU §4.6 « Paiement des honoraires (missions libérales) »

> **Statut : brouillon, hors code.** Protocole : **Gabrielle valide** chaque draft
> avant mise en ligne. Relu 09/07/2026 (3 corrections bloquantes + ajustements
> intégrés). **GATE FINAL avant mise en ligne** : recroiser la localisation des
> fonds (§ chapeau + clause plancher) avec `docs/flux-monetaire-escrow.md`.
> Référence code : `src/pages/PageCGU.tsx:112-113`.

## Vocabulaire BANNI (transversal)

- ❌ « **garantie** » (financière/intérim). ❌ « **service de paiement fourni par
  Jolene** ». ❌ toute promesse d'un délai que Jolene ne contrôle pas
  techniquement (le virement interbancaire).
- ✅ « **Jolene agit en qualité de mandataire de facturation et d'encaissement du
  soignant ; les fonds sont détenus par Stripe** ».

## Texte proposé — §4.6 (à intégrer dans PageCGU)

> **§4.6 — Paiement des honoraires (missions libérales)**
>
> Jolene agit en qualité de **mandataire de facturation et d'encaissement** du
> soignant. Les fonds sont **détenus par Stripe** (prestataire de services de
> paiement), jamais par Jolene.
> `<!-- mandat civil art. 1984 C. civ. ; hors monopole bancaire art. L521-1 CMF ;`
> `exemption d'agent commercial DSP2 art. 3, b) — transposition CMF à préciser`
> `dans docs/flux-monetaire-escrow.md (L521-1 seul ne porte pas l'analyse). -->`
>
> Pour les missions éligibles (dispositif commercial « Paiement rapide »), le
> montant de tes honoraires tel qu'établi à la confirmation (« montant réservé »)
> est **conservé par Stripe** et sa libération est déclenchée dès la validation de
> tes présences par l'établissement — automatique à défaut de réponse sous
> 72 heures après la fin de la mission —, **sous réserve de l'encaissement
> effectif des fonds auprès de l'établissement**. Le délai de réception sur ton
> compte bancaire dépend des délais d'exécution interbancaires et du prestataire
> de paiement ; il t'est indiqué, à titre estimatif, dans l'application.
> `<!-- art. 1103 C. civ. ; les 72 h qualifient la VALIDATION, jamais le virement`
> `— règle : aucune promesse d'un délai que Jolene ne contrôle pas. -->`
>
> **Montant réservé — plancher.** Le montant réservé correspond aux heures
> prévues à la confirmation. Si les heures réalisées sont **inférieures** aux
> heures prévues, tu perçois néanmoins le montant réservé, sauf litige constaté et
> résolu selon **l'article 9 (Droit applicable)**. Aucune réduction automatique.
> `<!-- art. 1103 C. civ. ; cohérent règle #11 (plancher GREATEST). -->`
>
> **Échec de prélèvement.** Le versement est conditionné à l'encaissement effectif
> auprès de l'établissement. En cas d'échec, il est **suspendu le temps de la
> régularisation** ; tu en es informé. Le montant réservé n'est pas définitivement
> acquis tant que l'encaissement n'a pas eu lieu.
> `<!-- condition suspensive art. 1304 C. civ. ; évite toute garantie de paiement. -->`
>
> En cas d'annulation **avant le début** de la mission, les sommes sont restituées
> à l'établissement.

## Clause « Attestation d'empêchement impérieux » (désistement soignant)

> **Attestation d'empêchement impérieux.** En cas de désistement d'une mission
> pour empêchement impérieux, le soignant peut le déclarer par une **attestation
> sur l'honneur** (engagement + dates d'indisponibilité). Aucun justificatif ni
> catégorie de motif n'est demandé ni conservé. **Toute fausse déclaration engage
> la responsabilité de l'utilisateur** et peut entraîner l'application de la
> pénalité de score et une revue de son compte.
> `<!-- art. 1103 C. civ. ; le motif générique (pas la nature santé/familial)`
> `évite une collecte de donnée de santé dans ce parcours. Anti-abus`
> `par compteur (fn_param_num) au-delà de N annulations justifiées/12 mois. -->`

## ⛔ Clause « Heures supplémentaires » — À NE PAS PUBLIER dans cet amendement

> **À PUBLIER AVEC LA LIVRAISON LOT 14 — mécanisme inexistant à ce jour.** Une CGU
> décrit le système qui existe. Texte conservé pour mémoire, à sortir seulement
> quand le débit complémentaire des heures sup sera livré :
>
> > « Les heures réalisées **au-delà** des heures prévues, une fois validées par
> > l'établissement, font l'objet d'un **règlement complémentaire** distinct
> > (débit complémentaire sur le mandat de l'établissement), au même barème. »
> > `<!-- art. 1103 C. civ. -->`

## Clause de modification des CGU (article dédié)

> Jolene peut modifier les présentes CGU. Toute modification substantielle est
> **notifiée par email avec un préavis d'au moins quinze (15) jours** avant son
> entrée en vigueur ; l'utilisateur qui la refuse peut résilier son compte avant
> cette date. La **version en vigueur, datée**, est affichée en permanence dans
> l'application. La poursuite de l'utilisation après l'entrée en vigueur vaut
> acceptation.
> `<!-- art. 1103 et 1193 C. civ. ; préavis 15 j = standard de loyauté aligné sur`
> `le règlement (UE) 2019/1150 (intermédiation B2B, hors champ ici). NE JAMAIS`
> `citer le C. conso ni RGPD art. 13 ici : utilisateurs professionnels. -->`

## Interdiction transit données patients (article données/usage)

> Il est **strictement interdit** de faire transiter, via la messagerie ou tout
> champ libre, des **données de santé ou identifiantes de patients**. La
> Plateforme n'est ni un dispositif de traitement de données de santé, ni
> hébergeur HDS. **Jolene se réserve le droit de retirer tout contenu
> contrevenant.** Tout manquement engage la responsabilité de l'utilisateur.
> `<!-- art. L1110-4 CSP (secret médical) ; RGPD art. 9 ; L1111-8 CSP (HDS, Jolene`
> `hors périmètre, cf. docs/CONFORMITE.md). -->`

## Finitions appliquées

- Placeholder `[litiges]` → **Article 9 (Droit applicable)** (`PageCGU.tsx:177`).
- Titre **sans emoji** ; « Paiement rapide » mentionné **une fois** comme nom
  commercial.
- Registre « tu » conservé pour §4.6 (cohérent avec §4.5) ; clause de
  modification en registre formel (utilisateurs professionnels).

## GATE avant mise en ligne

1. Recroiser « conservé par Stripe » (chapeau + plancher) avec
   `docs/flux-monetaire-escrow.md` (localisation exacte des fonds pendant la
   rétention). **Bloquant.**
2. Validation Gabrielle.
