# Logique paiements v1 — Référence métier Jolene

**Statut** : Validé Gabrielle le 22/04/2026
**Dernière mise à jour** : 22/04/2026
**Auteurs** : Gabrielle (produit) + Claude (rédaction)
**Portée** : sert de source de vérité pour tous les développements paiement (fn SQL, edge functions, UI étab, UI soignant, factures, bulletins, commission).

> ⚠️ **À consulter obligatoirement** avant toute modification touchant :
> - `fn_declarer_paiement_soignant`, `fn_obligations_financieres`, `fn_creer_facture_honoraires`, `fn_creer_facture_commission_*`
> - Edge functions `generate-invoice`, `stripe-connect-pay-mission`, `stripe-webhook`, `create-invoice-payment`
> - Composants UI `DecompositionFinanciere`, `ObligationsFinancieres`, `DetailMission`, `FacturationEtablissement`

---

## 1. Statut juridique Jolene (cadre général)

Jolene **n'emploie pas** le soignant. Jolene n'est **pas une entreprise d'intérim** ni un **portage salarial**. Le rôle de Jolene est double selon le type de contrat :

| Type contrat mission | Rôle Jolene |
|----------------------|-------------|
| LIBERAL | **Mandataire de facturation** au sens art. 289 I-2 du CGI. Jolene émet les notes d'honoraires au nom et pour le compte du soignant libéral. |
| SALARIE (CDDU) | **Prestataire de service bulletin de paie**. L'établissement est l'**employeur URSSAF** ; Jolene génère le bulletin comme prestataire RH. |

**Conséquences strictes** :
- Jolene **ne verse jamais** d'argent au soignant directement (hors Stripe Connect qui est un flow Stripe, pas un versement Jolene).
- Jolene **ne déclare jamais** à l'URSSAF à la place de l'étab (éviterait le risque de requalification en intérim illégal).
- Jolene **n'encaisse pas** le brut soignant puis ne redistribue pas (éviterait le statut de marchandage).

---

## 2. Type de contrat LIBERAL

Le soignant libéral exerce en tant que profession libérale. Il facture ses honoraires à l'établissement.

### 2.1. Calcul financier

```
Brut_honoraires = taux_horaire × heures_effectuées
                + majorations (nuit / dimanche / férié)
```

**Aucun** des éléments suivants n'existe en LIBERAL :
- ❌ IFM (indemnité de fin de mission)
- ❌ ICP (indemnité compensatrice de congés payés)
- ❌ Cotisations salariales / patronales
- ❌ Super brut

Le libéral gère ses propres cotisations (URSSAF libérale, CARPIMKO/CIPAV selon profession).

### 2.2. Commission Jolene en LIBERAL

```
Commission = % × Brut_honoraires
(taux stocké dans mission.taux_commission_fige)
```

**Facturée EN PLUS** à l'établissement. **Jamais déduite** du brut soignant. Le soignant reçoit **100%** de son brut honoraires.

### 2.3. Flow paiement — Cas A : Stripe Connect actif

Prérequis : soignant a complété l'onboarding Stripe Connect (`stripe_connect_onboarding.statut = 'COMPLET'`).

Séquence :
1. L'étab clique "Payer via Stripe" sur la carte mission.
2. Frontend invoke `stripe-connect-pay-mission` → génère facture honoraires si absente (voir Flow FIX 3), crée Checkout Session Stripe avec `amount = brut_soignant + commission`.
3. Étab saisit sa carte côté Stripe → paiement unique débité.
4. Stripe webhook `checkout.session.completed` branche `CONNECT_MISSION_PAYMENT` :
   - `stripe.transfers.create()` vers compte Stripe Connect du soignant (`amount = brut_soignant`).
   - La commission reste sur le compte Jolene (reçue du charge, pas transférée).
   - UPDATE `stripe_transfers.statut = TRANSFERE`, `factures_honoraires.statut = PAYEE`, INSERT `paiements_soignant.statut = CONFIRME`.

**Étab voit** : un seul débit carte ; la mission disparaît de "Missions à payer" ; une facture commission n'est PAS émise (la commission a été capturée à la source).

**Soignant voit** : virement Stripe Connect sur son compte bancaire dans 2-3 jours ouvrés ; facture honoraires marquée PAYEE.

### 2.4. Flow paiement — Cas B : Sans Stripe Connect (virement SEPA classique)

Le soignant n'est pas onboardé Stripe Connect (ou l'onboarding n'est pas COMPLET).

Séquence :
1. L'étab reçoit le RIB du soignant (affiché sur la fiche mission + dans le dialog "Déclarer un paiement").
2. L'étab effectue un virement SEPA classique du `brut_honoraires` au soignant.
3. L'étab revient sur la page, clique "Déclarer un paiement", remplit méthode `VIREMENT` + référence virement + montant.
4. INSERT `paiements_soignant.statut = DECLARE`.
5. Le soignant reçoit le virement, confirme côté son compte → `paiements_soignant.statut = CONFIRME`.

**Commission Jolene** : facturée séparément via `factures.statut IN (EMISE, EN_RETARD)` dans la section "Commissions Jolene" de la page `ObligationsFinancieres`. Payable par carte (Stripe Checkout) ou virement bancaire Jolene.

---

## 3. Type de contrat SALARIE (Modèle A, CDDU)

Le soignant est en CDDU (contrat à durée déterminée d'usage). L'établissement est l'**employeur URSSAF**.

### 3.1. Calcul financier complet

```
Base        = taux_horaire × heures + majorations (nuit/dimanche/férié)
Brut        = Base + IFM (10%) + ICP (10%)
Cotisations = ~22% × Brut (cotisations salariales à la charge du soignant)
NET         = Brut - Cotisations
```

L'étab paye en plus :
- **Cotisations patronales** (~42% du brut) directement à l'URSSAF
- **Super brut** = Brut + Cotisations patronales (pour info comptable)

### 3.2. Flow paiement (Modèle A)

**Principe fondamental** : l'étab verse **uniquement le NET** au soignant. Le circuit URSSAF est géré par l'étab directement, **sans intermédiaire Jolene**.

Séquence :
1. **Virement NET** : l'étab vire le NET au soignant (RIB + référence virement, flow identique à LIBERAL Cas B).
2. **Déclaration URSSAF** : l'étab déclare et paye les cotisations (salariales + patronales) à l'URSSAF, sur son espace employeur (DSN mensuelle ou à la mission). Jolene n'intervient pas.
3. **Bulletin de paie** : Jolene génère le bulletin de paie (service de prestation RH) avec toutes les lignes obligatoires (brut, IFM, ICP, cotisations détaillées, net). Le bulletin est téléchargeable par le soignant et l'étab.
4. INSERT `paiements_soignant` (méthode `BULLETIN_PAIE` ou `VIREMENT`, référence du virement SEPA) → statut DECLARE → CONFIRME après confirmation soignant.

**Commission Jolene** : séparée, même modèle que LIBERAL Cas B (voir §4).

### 3.3. Affichage étab (rules UX stricte)

Sur la **carte mission** dans `ObligationsFinancieres` :
- ✅ Afficher **montant NET en évidence** (ex: `339,77 €`)
- ✅ Label explicite : "À verser au soignant par virement SEPA"
- ✅ Bouton "Déclarer un paiement" avec le montant NET pré-rempli
- ❌ **Ne pas afficher** : super brut, brut, cotisations salariales/patronales, IFM/ICP en détail
- ❌ **Ne pas afficher** la commission Jolene ("+ X € com.") sur la carte mission — risque addition mentale par l'étab = **surpaiement**

Sur la **fiche mission détaillée** (`DetailMission`) :
- Section "Rémunération" : montant NET (mise en avant)
- Section "Informations comptables" (accordéon ou en bas) : détail brut + IFM/ICP + cotisations + super brut pour transparence URSSAF
- Section "Commission Jolene" : distincte, avec lien vers la facture commission correspondante

### 3.4. Jolene et URSSAF (règle de sécurité juridique)

- Jolene ne collecte pas de cotisations URSSAF.
- Jolene ne verse pas de cotisations URSSAF.
- Jolene **ne doit jamais afficher** un message type "Vous allez payer X € de cotisations via Jolene" — ce serait une présomption de portage/intérim.
- Le bulletin de paie généré par Jolene mentionne explicitement : "Employeur : [établissement]. Bulletin prestation Jolene."

---

## 4. Commission Jolene (unifiée)

### 4.1. Calcul

```
Commission = % × Brut
```

Où `%` est `mission.taux_commission_fige` (figé à l'assignation) et `Brut` est :
- Brut honoraires si LIBERAL
- Brut salarial (hors IFM/ICP/cotisations) si SALARIE — **à confirmer/documenter précisément selon version actuelle, historiquement le taux a pu s'appliquer sur net_a_payer**

### 4.2. Facturation

| Cas | Canal facture commission | Mode paiement étab |
|-----|--------------------------|--------------------|
| LIBERAL + Stripe Connect | **Pas de facture commission séparée** — capturée à la source via `application_fee_amount` ou split via `stripe.transfers.create(brut)` laissant commission sur compte Jolene | 1 seul débit carte via Checkout Session |
| LIBERAL sans Stripe | Facture commission **séparée** (groupée mensuelle ou par mission) | Virement SEPA OU carte via Stripe Checkout facture |
| SALARIE | Facture commission **séparée** (groupée mensuelle ou par mission) | Virement SEPA OU carte via Stripe Checkout facture |

### 4.3. Règle invariant

Commission = **toujours payée EN PLUS** par l'étab. Elle **ne diminue jamais** le montant net reçu par le soignant.

---

## 5. Type de contrat MIXTE (choix du soignant)

Un soignant a `type_exercice = MIXTE` s'il exerce à la fois en libéral (RPPS + SIRET actif) et peut accepter des missions SALARIE.

### 5.1. Règles d'application

Documentées et déployées via **E16** (CP-C-1.5) :
- Une mission `type_contrat_recherche = TOUS` + soignant MIXTE exige un **choix explicite** à l'acceptation (dialog frontend).
- Le choix est stocké dans `missions.choix_contrat_soignant` (`SALARIE` ou `LIBERAL`).
- À l'assignation, `missions.type_contrat_applique` est figé sur la base de `choix_contrat_soignant`.
- Les règles **§2 (LIBERAL)** ou **§3 (SALARIE)** s'appliquent ensuite **strictement selon `type_contrat_applique`**.

### 5.2. Invariant post-figement

Une fois `type_contrat_applique` figé, il **ne change plus** pour la durée de la mission. Toute incohérence ultérieure (paiement NOTE_HONORAIRES sur mission SALARIE par exemple) est un bug côté code à corriger, jamais côté data.

---

## 6. Bugs connus à corriger — post-doc v1

Issus du diagnostic des sessions 21-22/04/2026 :

| # | Bug | Emplacement | Priorité | Notes |
|---|-----|-------------|----------|-------|
| A | Composant `DecompositionFinanciere` affiche IFM/ICP/cotisations pour LIBERAL (alors que ces lignes n'existent pas en libéral) | `src/components/DecompositionFinanciere.tsx` | P1 | Conditionner par `type_contrat_applique` : branche LIBERAL = brut + commission séparée, branche SALARIE = NET + accordéon détail |
| B | Carte mission dans `ObligationsFinancieres` affichait "+ X € com." qui pouvait induire addition mentale par l'étab → risque surpaiement | `src/pages/ObligationsFinancieres.tsx` | ✅ Partiellement fixé (CRITIQUE 1 de la session) — **à vérifier** que la commission n'apparaît pas sur les cartes SALARIE et LIBERAL-sans-Stripe |
| C | Fiche mission SALARIE affiche "Super brut" en évidence → l'étab pourrait virer le super brut au lieu du NET → surpaiement massif (+65% !) | `src/pages/DetailMission.tsx` + `DecompositionFinanciere.tsx` | P0 | Inverser la hiérarchie : NET en gros, super brut dans accordéon "Détail comptable" repliable |
| D | Webhook Stripe branche `CONNECT_MISSION_PAYMENT` jamais atteinte en prod (0 audit `FINANCE_TRANSFER_CONNECT` dans les 3 derniers jours) | Investigation webhook | P0 | Cause à identifier : event pas reçu ? signature invalide ? metadata manquante ? Test avec session réelle + logs verbose |
| E | `factures_honoraires` créées pour missions SALARIE (5 rows étab test observés) | `supabase/functions/generate-invoice/index.ts` | P1 | Ajouter garde 400 `CONTRAT_NON_LIBERAL` si `mission.type_contrat_applique != 'LIBERAL'` |
| F | `paiements_soignant.methode = NOTE_HONORAIRES` accepté sur mission `type_contrat_applique = SALARIE` (et inverse) | `fn_declarer_paiement_soignant` | P1 | RAISE EXCEPTION si mismatch ; méthodes autorisées : SALARIE → VIREMENT/CHEQUE/BULLETIN_PAIE, LIBERAL → VIREMENT/CHEQUE/NOTE_HONORAIRES |

### 6.1. Ordre d'attaque recommandé

1. **D** (webhook) — bloquant pour tout flow Stripe Connect réel
2. **C** (affichage NET SALARIE) — risque surpaiement massif si étab se trompe
3. **E** + **F** (gardes backend generate-invoice + fn_declarer_paiement_soignant) — empêche futures incohérences
4. **A** (DecompositionFinanciere) — affichage correct LIBERAL
5. Cleanup data existantes (5 factures_honoraires SALARIE à ANNULER, 1 paiement_soignant incohérent Vaccination grippe à corriger)

---

## 7. Glossaire rapide

| Terme | Définition |
|-------|-----------|
| **IFM** | Indemnité de fin de mission (10% du brut) — CDDU uniquement |
| **ICP** | Indemnité compensatrice de congés payés (10% du brut) — CDDU uniquement |
| **Super brut** | Brut + cotisations patronales (~42% du brut). Coût total employeur. |
| **Brut** | Base rémunération avant cotisations salariales |
| **NET** | Ce que le soignant touche réellement (Brut - cotisations salariales) |
| **Brut honoraires** | Équivalent libéral du brut salarié (pas de cotisations à retrancher). |
| **CDDU** | Contrat à durée déterminée d'usage (secteur santé, hôtellerie, spectacle). |
| **Mandat facturation** | Art. 289 I-2 CGI : Jolene émet les factures honoraires au nom du soignant libéral avec son consentement. |
| **Stripe Connect** | Produit Stripe permettant de splitter un paiement entre plusieurs comptes (plateforme + destinataire). |
| **application_fee_amount** | Part commission Jolene retenue sur le charge avant transfer vers le compte Connect du soignant. |

---

## 8. Références

- `supabase/migrations/20260421134646_fix_obligations_filtre_resolu.sql` — filtre paiements_soignant
- `supabase/migrations/20260421154817_obligations_filtre_stripe_transfers.sql` — filtre stripe_transfers (défense en profondeur)
- `supabase/migrations/20260422090000_fix_obligations_type_contrat_mission.sql` — expose type_contrat_applique dans fn_obligations_financieres
- E16 tickets inventaire (CP-C-1.5) — MIXTE×TOUS + figement type_contrat_applique
- Sub-PR D — Stripe Connect prod-ready (CP-STRIPE-1 à 6)
- CP-STRIPE-3 — compensation Checkout Session orpheline (H5 + H8)

---

**Fin du document v1**. Toute évolution (nouveau type de contrat, changement de règle commission, bascule Modèle B "Jolene URSSAF", etc.) → créer `logique-paiements-v2.md` et archiver v1.
