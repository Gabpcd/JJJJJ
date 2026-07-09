# Spec — Visibilité escrow ⚡ côté soignant (revenus)

> Point 1 du chantier post-flip. Spec légère (pas de maquette pixel).
> Objectif : rendre lisible le cycle de paiement escrow dans « Mes gains »,
> côté soignant uniquement (jamais la mécanique établissement).

## 1. États côté soignant (wording exact)

Mapping depuis `paiements_escrow.statut` + validation des présences. On ne montre
JAMAIS le débit SEPA de l'établissement, ni la commission : seul l'honoraire du
soignant (`honoraires_cents`) est affiché.

| Priorité | Condition (backend réel) | État affiché | Icône | Date |
|---|---|---|---|---|
| 1 | `statut = PAYE` | **Versé le JJ/MM** | ✅ | `paye_le` |
| 2 | `statut = REMBOURSE` | **Paiement annulé** | ❌ | — (lien détail mission) |
| 3 | `statut = DISPUTE` | **Paiement en litige** | ⏸️ | — (lien détail mission) |
| 4 | `statut = ECHOUE` | **Paiement retardé** | ⚠️ | — (« nous relançons le règlement ») |
| 5 | in-flight¹ ET présences validées² | **Versement en cours** | 💸 | « estimé le JJ/MM » **si** date réelle dispo, sinon aucune date |
| 6 | in-flight¹ ET mission travaillée³ non validée | **En attente de validation des heures** | ⏳ | — |
| 7 | in-flight¹ sinon (mission pas encore effectuée) | **Paiement sécurisé** | 🔒 | — (« montant garanti dès la confirmation ») |

¹ in-flight = `statut ∈ {INITIE, DEBITE, DISPONIBLE, RELEASE_PLANIFIE}`
² présences validées = `presences.valide_par_etablissement = true` (aucune présence bloquante)
³ mission travaillée = `presences.pointage_depart_le IS NOT NULL`

**Principe** : l'état est fonction de DEUX axes indépendants — l'avancement
escrow (piloté par le SEPA/settlement, invisible au soignant) ET la validation
des heures. Un paiement peut être « débité côté étab » mais rester « En attente
de validation des heures » tant que l'établissement n'a pas validé.

## 2. Logique de dates (jamais de promesse en dur)

- **Versé** : `paye_le` (date réelle).
- **Versement en cours** : date estimée = `COALESCE(release_planifie_le, disponible_le)`.
  Ces deux champs ne sont peuplés que lorsque les fonds sont réellement settled
  côté Stripe. **Si aucun des deux n'est peuplé → on n'affiche AUCUNE date**,
  juste « Versement en cours ». On n'invente pas de délai « 24-72 h ».
- **Paiement retardé** (`ECHOUE`) : pas de date exposée (la `relance_prevue_le`
  est de la mécanique interne).
- Aucune date « 24-72 h » ni « J+2 » écrite en dur nulle part dans l'écran.
  Le wording du badge ⚡ sera recalibré après la mission témoin (hors salve).

## 3. Montants

- Afficher **uniquement** `honoraires_cents` (part soignant). Jamais
  `montant_total_cents` (inclut la commission = mécanique étab), jamais
  `commission_cents`.
- Conversion centimes → euros : `honoraires_cents / 100`, formaté 2 décimales,
  séparateur FR (ex. `255,00 €`). Vigilance centimes/euros (règle CLAUDE.md :
  ne jamais mélanger les deux unités dans un même calcul).
- Scénario témoin (run #12) : `honoraires_cents = 25500` → **255,00 €** visible
  soignant (la commission 43,20 € et le total 298,20 € ne sont PAS montrés).

## 4. Vocabulaire tranché (anti-confusion)

- **⚡ = exclusivement le cycle escrow** (cette vue). Libellé produit :
  « Paiement rapide ⚡ ».
- **Affacturage Defacto** (onglet « Avances » de MesGains) = renommé
  **« Avance de trésorerie »**, icône distincte (pas ⚡), vocabulaire séparé.
  Vérifier que cet onglet reste **derrière son feature flag** tant que le
  service n'est pas actif (règle des récompenses fantômes — un service inactif
  ne doit pas afficher de promesse).

## 5. Backend — fonctions SQL

- **Nouvelle** `fn_mes_paiements_escrow()` : liste par mission des escrows du
  soignant courant (`auth.uid()`), `SECURITY DEFINER`, retourne pour chaque
  ligne : `mission_id`, `mission_intitule`, `etablissement_nom`, `honoraires_cents`,
  `etat` (une des 7 valeurs ci-dessus, calculée en SQL), `date_affichee` (timestamptz
  nullable), `mission_date`. Tri : in-flight/attente d'abord, versés ensuite.
- **Enrichir** `fn_mes_revenus_connect` : les compteurs `total` (versés) et
  `en_attente` (in-flight) doivent inclure l'escrow (`paiements_escrow`), pas
  seulement `stripe_transfers`. **Sans double-comptage** : escrow et
  `stripe_transfers` couvrent des missions disjointes (l'escrow remplace le
  transfer direct quand ⚡ actif). L'ancien modèle `stripe_transfers` continue
  d'afficher correctement pour les missions pré-flip.

## 6. Frontend

- Nouvelle section « Paiement rapide ⚡ » dans **MesGains** (onglet Aperçu ou
  sous-section dédiée), affichant la liste `fn_mes_paiements_escrow` sous forme
  de lignes-timeline compactes (état + montant + date estimée/réelle). Masquée
  si la liste est vide (pas de récompense fantôme).
- Réutiliser les composants existants (CarteKPIY2K, BadgeY2K) ; état visuel par
  couleur sémantique (versé = success, en cours = info, retardé/litige = warning,
  annulé = neutre/error).

## 7. Fix REJETE (PageStripeConnect)

- Ajouter `REJETE` à l'union `ConnectStatut` (aujourd'hui 5/6 → écran vide
  possible).
- Bloc UI dédié : **raison affichée** (depuis `stripe-connect-status`
  `disabled_reason` / `requirements`) + **chemin de remédiation** :
  bouton « Reprendre / corriger mon inscription » (relance `stripe-connect-onboard`)
  + lien support. Pas seulement un libellé d'état.

## 8. Tests

- **`fn_mes_paiements_escrow`** testée avec le scénario exact du run #12
  (débit 298,20 € → 255 € soignant + 43,20 € commission) : le soignant ne voit
  que 255,00 €, l'état reflète le statut escrow, la date suit `paye_le`/estimée.
- **`fn_mes_revenus_connect`** : les missions escrow PAYE alimentent `total`,
  les in-flight alimentent `en_attente`, **et** l'ancien modèle `stripe_transfers`
  continue d'afficher correctement (non-régression, pas de double-comptage).
- Vigilance centimes/euros sur tous les calculs.
- `verify-recette` sur la page Revenus en **390 × 844** (iPhone) : rendu correct
  de la nouvelle section, états vides gérés.

## Hors salve (follow-up)

- Notification push à la transition « Versé » (matrice B8). Non inclus ici.
