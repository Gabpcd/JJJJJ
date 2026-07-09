# Spec — Visibilité escrow ⚡ côté soignant (revenus)

> Point 1 du chantier post-flip. Spec légère (pas de maquette pixel).
> Objectif : rendre lisible le cycle de paiement escrow dans « Mes gains »,
> côté soignant uniquement (jamais la mécanique établissement).
> Cadrage validé (11 points, 09/07/2026).

## 0. Invariants (non négociables)

- **I1 — Plancher inviolable.** La validation des présences ne réduit JAMAIS
  l'escrow. `honoraires_cents` est figé à la confirmation (`net_a_payer`
  prévisionnel) et versé intégralement. Contester des heures = **litige**
  (gel `DISPUTE`), **seule** voie de réduction. Aucune « validation partielle »
  silencieuse. (Cf. règle rémunération CLAUDE.md, `GREATEST(prévisionnel,
  effectif)`.)
- **I2 — Jamais de fausse promesse.** Le mot « garanti » est **interdit** à
  l'écran : avant settlement le débit peut échouer (`ECHOUE`), et le plancher a
  l'exception litige. Wording : « **Réservé** » / « le montant de ta
  confirmation ». Montant affiché = `honoraires_cents` exact, jamais présenté
  comme absolu.
- **I3 — Part soignant seule.** On n'affiche que `honoraires_cents`. Jamais
  `montant_total_cents` (inclut la commission = mécanique étab), jamais
  `commission_cents`, jamais le débit SEPA de l'établissement.
- **I4 — Icônes lucide, jamais d'emoji** (pattern CLAUDE.md). Les 🔒⏳💸 de cette
  spec sont des placeholders sémantiques.
- **I5 — Pas de récompense fantôme.** Section masquée si vide ; un service
  inactif (ex. affacturage non branché) ne montre aucune promesse.

## 1. États côté soignant (wording exact + icône lucide + action)

Calculés depuis `paiements_escrow.statut` + validation des présences.

| # | Condition (backend réel) | Libellé écran | Icône lucide | Date | Ligne d'explication / action |
|---|---|---|---|---|---|
| 1 | in-flight¹ ET mission pas encore effectuée | **Réservé** | `ShieldCheck` | — | « le montant de ta confirmation, mis de côté » |
| 2 | in-flight¹ ET mission travaillée³ non validée | **En attente de validation des heures** | `Clock` | — | « l'établissement valide tes heures (auto sous 72 h) » |
| 3 | in-flight¹ ET présences validées² | **Versement en cours** | `Send` | « estimé le JJ/MM » si date réelle, sinon rien | « ton virement est en route » |
| 4 | `statut = PAYE` | **Versé le JJ/MM** | `CheckCircle2` | `paye_le` | — |
| 5 | `statut = ECHOUE` | **Paiement retardé** | `AlertTriangle` | — | « nouvelle tentative le JJ/MM » (si `relance_prevue_le`) ; sinon « nous relançons le règlement » |
| 6 | `statut = DISPUTE` | **Paiement en litige** | `PauseCircle` | — | lien → le litige de la mission |
| 7 | `statut = REMBOURSE` ET `paye_le` posé (absorption post-versement) | **Versé le JJ/MM** | `CheckCircle2` | `paye_le` | (le soignant a touché 100 % — la reprise est étab↔Jolene, invisible) |
| 8 | `statut = REMBOURSE` ET `paye_le` NULL (annulé avant versement) | **Paiement annulé** | `XCircle` | — | motif court (`p_motif`) + lien support |

¹ in-flight = `statut ∈ {INITIE, DEBITE, DISPONIBLE, RELEASE_PLANIFIE}`
² présences validées = `presences.valide_par_etablissement = true`, aucune présence bloquante
³ mission travaillée = `presences.pointage_depart_le IS NOT NULL`

**Principe** : l'état combine DEUX axes indépendants — l'avancement escrow
(piloté par le SEPA/settlement, invisible au soignant) ET la validation des
heures. Un paiement peut être « débité côté étab » (DEBITE) mais rester « En
attente de validation des heures ».

> **⚠️ « Versé partiellement » NON livrable (cf. §9.4).** Le backend n'a pas
> d'état « payé partiel » : un remboursement partiel passe tout l'escrow en
> `REMBOURSE`, et le reliquat pré-release n'est pas reversé (gap Lot 13). On
> n'affiche donc PAS « Versé partiellement (X sur Y) » tant que le backend ne
> le supporte pas honnêtement (I2). États 7/8 ci-dessus = comportement réel.

## 2. Logique de dates (jamais de promesse en dur)

- **Versé** : `paye_le` (réel).
- **Versement en cours** : `COALESCE(release_planifie_le, disponible_le)` —
  peuplés seulement quand les fonds sont réellement settled. **Aucun des deux →
  aucune date affichée**, juste « Versement en cours ». On n'invente pas de
  « 24-72 h » ni « J+2 ».
- **Paiement retardé** (`ECHOUE`) : `relance_prevue_le` si présente, sinon rien.
- Aucun délai en dur nulle part. Le wording du badge ⚡ sera recalibré après la
  mission témoin (hors salve).

## 3. Montants & vocabulaire

- Afficher **uniquement** `honoraires_cents / 100`, formaté FR 2 décimales
  (`255,00 €`). Vigilance centimes/euros (CLAUDE.md : ne jamais mélanger les
  unités dans un calcul). Témoin run #12 : `honoraires_cents = 25500` →
  **255,00 €** (commission 43,20 € et total 298,20 € JAMAIS montrés).
- **⚡ = exclusivement le cycle escrow.** « Paiement rapide ⚡ » = **badge par
  paiement éligible**, jamais un titre de section.
- **Affacturage Defacto** (onglet « Avances ») → renommé **« Avance de
  trésorerie »**, icône distincte (pas ⚡). Vérifier qu'il reste **derrière son
  feature flag** tant que le service n'est pas actif (I5).

## 4. Placement UI

- **Onglet Aperçu** de MesGains. Bloc **« À venir »** en HAUT, affiché seulement
  s'il existe ≥ 1 paiement en cours (états 1-3, 5 retardé, 6 litige). Même
  composant carte que l'historique. Badge ⚡ par ligne éligible.
- Historique (versés/annulés) dans le flux existant.
- Section entière masquée si aucun paiement escrow (I5).

## 5. Backend — fonctions SQL

- **Nouvelle** `fn_mes_paiements_escrow()` : `SECURITY DEFINER`, escrows du
  soignant `auth.uid()`. Par ligne : `mission_id`, `mission_intitule`,
  `etablissement_nom`, `honoraires_cents`, `etat` (1 des 8, calculé SQL depuis
  statut + présences + `paye_le`), `date_affichee` (nullable), `mission_date`,
  `relance_prevue_le`, `a_litige` (bool). Tri : en cours/attente d'abord.
- **Enrichir** `fn_mes_revenus_connect` : `total` (versés) et `en_attente`
  (in-flight) incluent l'escrow (`paiements_escrow`), pas seulement
  `stripe_transfers`. **Sans double-comptage** : escrow et `stripe_transfers`
  couvrent des missions disjointes (l'escrow remplace le transfer direct quand
  ⚡ actif). L'ancien modèle continue d'afficher pour les missions pré-flip.

## 6. Frontend

- Nouvelle sous-section « À venir » (Aperçu MesGains) rendant
  `fn_mes_paiements_escrow` en lignes-carte compactes (icône lucide + libellé +
  montant + date + ligne d'explication/action). Couleurs sémantiques
  (versé=success, en cours=info, retardé/litige=warning, annulé=neutre).
- Réutiliser CarteKPIY2K / BadgeY2K / composants existants.

## 7. Fix REJETE (PageStripeConnect)

- Ajouter `REJETE` à l'union `ConnectStatut` (aujourd'hui 5/6 → écran vide).
- Bloc dédié : **raison** (`disabled_reason` / `requirements` de
  `stripe-connect-status`) + **chemin de remédiation** : bouton « Reprendre /
  corriger mon inscription » (relance `stripe-connect-onboard`) + lien support.
  Pas seulement un libellé d'état.

## 8. Tests

- **`fn_mes_paiements_escrow`** avec le scénario run #12 (débit 298,20 € →
  255 € soignant + 43,20 € commission) : le soignant ne voit que **255,00 €**,
  l'état suit le statut escrow, la date suit `paye_le`/estimée.
- **Cas mixte** : un même soignant avec ancien modèle (`stripe_transfers`) ET
  escrow → totaux `fn_mes_revenus_connect` corrects, **sans double-comptage**.
- **Un rendu testé par état** : les 8 états (dont « versé partiellement » NON
  affiché — vérifier qu'un REMBOURSE post-PAYE tombe en « Versé » et non
  « Annulé »).
- **Non-régression** `stripe_transfers` (missions pré-flip inchangées).
- Vigilance centimes/euros partout.
- `verify-recette` sur la page Revenus en **390 × 844** (iPhone) : nouvelle
  section, états vides, badge ⚡ par ligne.

## 9. FAIT STRUCTURANT — heures validées vs publiées + remboursement partiel

> Investigation code prod (09/07/2026). Détermine le montant affiché, l'écran de
> validation (Lot 13) et le flux litige.

### 9.1 Le montant escrow est FIGÉ à la confirmation, jamais recalculé

`fn_trg_escrow_creer_a_confirmation` :
```
v_honoraires_c := ROUND(COALESCE(NEW.net_a_payer, 0) * 100)  -- prévisionnel
```
`honoraires_cents` = `missions.net_a_payer` **à la confirmation** (prévisionnel,
aucune heure faite). **Aucune fonction ne le met à jour après l'INITIE** (seules
`fn_escrow_rembourser` et `fn_trg_escrow_release_check` touchent la table, aucune
ne recalcule). Le release verse `honoraires_cents` **intégralement** — PAS
`heures_validées × taux`.

### 9.2 Heures validées < publiées

Aucune réduction automatique. **Plancher prévisionnel garanti** (`GREATEST`,
règle #11) : le soignant touche le prévisionnel = tout l'escrow figé, peu
importe la cause (étab ou soignant). Réduction possible **uniquement via litige**
(admin → `fn_escrow_rembourser`). Pas d'asymétrie codée.

### 9.3 Heures validées > publiées — SURPLUS (décision tranchée, NON implémentée)

Décision produit : le surplus (`effectif − prévisionnel > 0`) → **débit SEPA
complémentaire sur le même mandat** (delta × taux + majorations, commission
15 %), **déclenché par la validation explicite des heures sup par
l'établissement**, en **cycle escrow propre lié à la mission**. **Garde-fou 48 h**
sur les heures effectives : tout dépassement = **alerte**, jamais un paiement
silencieux. Aujourd'hui l'escrow ne couvre que le prévisionnel figé (aucun
top-up codé). **Ne rien implémenter dans cette salve** — TODO commentés tagués
`Lot 13` (déclencheur : flux de validation des présences) et `Lot 14`
(mécanique : edge functions escrow).

### 9.4 Remboursement partiel — sort du reliquat (gap à corriger)

`fn_escrow_rembourser(id, p_montant_honoraires_cts, p_annulation_totale, motif)`
accepte `0 < montant ≤ honoraires_cents`, MAIS :
- Il passe **tout** l'escrow en `REMBOURSE` (pas d'état « payé partiel »).
  `paiements_escrow` n'a **aucune** colonne montant_remboursé/reliquat ; le
  montant repris n'est traçable que via `stripe_refunds_queue.montant_cts −
  refund_application_fee_cts`.
- **Post-versement** (`paye_le` posé, `absorbe_plateforme=true`) : le soignant a
  déjà touché 100 %, Jolene absorbe la reprise → côté soignant = **Versé** (état
  7). Correct.
- **Pré-release** (`reverse_transfer=true`, jamais PAYE) : le payout n'a jamais
  lieu (release skippé dès REMBOURSE), la reprise partielle est prélevée sur le
  solde connecté → **le reliquat (`honoraires − repris`) reste bloqué sur le
  solde Stripe connecté, jamais reversé au soignant**. **GAP backend.**
- Conséquence UI (I2) : on n'affiche **pas** « Versé partiellement (X sur Y) » —
  ce serait faux (le reliquat n'a pas été versé). État 8 « Paiement annulé »
  pour le pré-release. **TODO `Lot 13`** : re-release du reliquat après
  remboursement partiel pré-release + colonne `montant_rembourse_cents` +
  état `PAYE_PARTIEL`, pour un vrai « Versé partiellement » honnête.

### 9.5 CGU / mandat

CGU **§4.6 « Paiement rapide ⚡ »** (`src/pages/PageCGU.tsx:112-113`) : encaissé
dès la confirmation, « libéré après validation des présences — au plus tard 72 h
après la fin (validation automatique en l'absence de réponse) », annulation
**avant début** → restitution étab. **Silencieuse** sur validées < publiées, sur
le surplus et sur le débit complémentaire → amendement à préparer (§10).

## 10. Amendement CGU §4.6 (draft — hors code, à valider + relecture avocat)

Voir `docs/DRAFT_CGU_4_6_AMENDEMENT.md`. Trois ajouts : plancher explicite
(montant de la confirmation garanti hors litige), débit complémentaire des
heures sup validées, comportement en cas d'échec de débit.

## Hors salve (follow-up)

- Notification push à la transition « Versé » (matrice B8).
- Backend surplus (Lot 13/14) + re-release reliquat + état PAYE_PARTIEL (Lot 13).
