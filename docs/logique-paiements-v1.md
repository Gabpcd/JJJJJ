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

### 4.1. Calcul — définition EXACTE du brut

```
Commission = taux × Brut
```

Où `taux` est `mission.taux_commission_fige` (figé à l'assignation), **identique pour LIBERAL et SALARIE**.

**Définition EXACTE du `Brut` utilisé pour calculer la commission** :

| Type contrat | Brut = | Remarque |
|--------------|--------|----------|
| **LIBERAL** | `taux_horaire × heures + majorations` (= brut honoraires = ce que touche le soignant) | Pas de IFM/ICP en libéral |
| **SALARIE** | `(base + majorations) + IFM (10%) + ICP (10%)` = **brut salarial TOTAL** (AVANT déduction cotisations salariales) | Le brut de référence pour la commission inclut IFM + ICP |

**Exemple LIBERAL** :
- Honoraires : 250 €
- Commission 15 % × 250 € = **37,50 €** (facturée à l'étab EN PLUS des 250 € versés au soignant)
- Total étab : 250 + 37,50 = 287,50 €

**Exemple SALARIE** :
- Base : 360 € + IFM 36 € + ICP 39,60 € = **Brut 435,60 €**
- Commission 15 % × 435,60 € = **65,34 €** (facturée à l'étab EN PLUS du NET versé au soignant)
- Total étab : NET versé au soignant + cotisations patronales URSSAF + 65,34 € commission

> ⚠️ **Cette définition est IMMUABLE**. Toute modification future (taux différenciés LIBERAL/SALARIE, application sur base hors IFM/ICP, etc.) nécessite une **v2** du document et une migration de `mission.taux_commission_fige` existant.

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

### 5.5. Affichage commission côté soignant — Option A validée

Le soignant **ne voit JAMAIS rien** sur la commission Jolene, **nulle part** :

- ❌ Pas dans la fiche mission (`DetailMission` rôle SOIGNANT)
- ❌ Pas dans les emails reçus par le soignant (PAIEMENT_RAPIDE_RECU, MISSION_CONFIRMEE, etc.)
- ❌ Pas dans les notifications in-app soignant
- ❌ Pas dans le dashboard "Mes revenus" soignant
- ❌ Pas dans les exports PDF/CSV soignant (récap activité, attestations URSSAF)

**Raison** : la commission ne concerne pas comptablement le soignant (elle est payée **EN PLUS** par l'étab, **jamais déduite** de sa rémunération). La mentionner créerait de la confusion potentielle et pourrait faire croire à tort au soignant qu'il paye la commission.

**Le soignant voit uniquement** :
- **SALARIE** : brut (avec détail IFM + ICP), cotisations salariales, NET, statut paiement, bulletin de paie téléchargeable
- **LIBERAL** : honoraires (brut = net), statut paiement, facture honoraires PDF + XML Factur-X téléchargeables

**Côté ÉTAB par contre**, la commission est **TRÈS VISIBLE** :
- Section dédiée "Commissions Jolene" sur `/etablissement/obligations`
- Carte mission LIBERAL+Stripe : affichage "dont X € commission Jolene" (mode Cas A explicite)
- Factures commission séparées téléchargeables avec détail ligne par ligne
- Dashboard `/etablissement/facturation` avec historique + filtrage par statut
- Audit trail des paiements commission (transfert / virement SEPA / carte Stripe)

**Cette asymétrie est VOULUE** et cohérente avec le modèle économique : l'étab est le **payeur** de la commission, le soignant n'est **pas concerné** comptablement. Afficher la commission côté soignant ouvrirait la porte à :
- Confusion sur le montant réel à percevoir
- Présomption de marchandage (soignant pensant qu'il "paye" la commission)
- Risque URSSAF / requalification en portage

> **Règle invariant** : en cas de doute lors d'une PR, si un composant ou email côté soignant mentionne `montant_commission_*`, c'est un bug. Lecture seule de ce champ autorisée uniquement côté étab / admin plateforme.

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

## 7. Statuts mission et rémunération

Enum `statut_mission` (valeurs au 22/04/2026) :
`OUVERTE, ASSIGNEE, EN_COURS, TERMINEE, ANNULEE_PAR_ETABLISSEMENT, ANNULEE_PAR_SOIGNANT, ABSENCE, LITIGE, EXPIREE`.

Comportement attendu par statut :

| Statut | Mission effectuée ? | Rémunération due ? | Facture honoraires | Commission Jolene | Affichage UI |
|--------|---------------------|--------------------|--------------------|--------------------|-------------|
| `OUVERTE` | Non (pas encore assignée) | — | — | — | Fiche mission + carte "à attribuer" |
| `ASSIGNEE` | Pas encore | En attente | — | — | Décomposition prévisionnelle + bouton démarrer |
| `EN_COURS` | En cours | En attente | — | — | Décomposition prévisionnelle |
| `TERMINEE` | **Oui** | **Oui** | Générée | Facturée | Décomposition complète + workflow paiement |
| `ANNULEE_PAR_ETABLISSEMENT` | Non | **Non** | **Aucune** | **Aucune** | Bloc "Mission annulée — aucune rémunération" |
| `ANNULEE_PAR_SOIGNANT` | Non | **Non** | **Aucune** | **Aucune** | Bloc "Mission annulée — aucune rémunération" |
| `ABSENCE` | Non (no-show soignant) | **Non** | **Aucune** | **Aucune** | Bloc "Mission non honorée — absence" + recherche remplaçant |
| `LITIGE` | Oui (mais contestée) | En instance | Générée (éventuellement annulée/remplacée) | En instance | Décomposition + bandeau ⚖️ Litige |
| `EXPIREE` | Non (aucun soignant trouvé) | **Non** | **Aucune** | **Aucune** | Bloc "Mission expirée" |

**Règle d'or** : si la mission n'est pas `TERMINEE` ou `LITIGE`, **aucun flux financier** ne doit être déclenché. Les statuts `ABSENCE`/`ANNULEE_PAR_*`/`EXPIREE` sont strictement *non-rémunérés*.

### Gardes backend en place (défense en profondeur)

- **`supabase/functions/generate-invoice/index.ts`** (L695) : rejette si `mission.statut !== 'TERMINEE'`
- **`fn_declarer_paiement_soignant`** (2 overloads) : `IF v_mission.statut != 'TERMINEE' THEN error`
- **`supabase/functions/stripe-connect-pay-mission/index.ts`** (L97) : rejette si `mission.statut !== 'TERMINEE'`
- **`fn_auto_facturation_mensuelle`** (cron commission) : filtre `WHERE statut = 'TERMINEE'`
- **`fn_obligations_financieres`** : filtre `AND m.statut = 'TERMINEE'` sur toutes les sous-requêtes missions à payer

### Garde frontend (22/04/2026 — Bug 6)

- **`src/components/DecompositionFinanciere.tsx`** : early-return avec bloc dédié si `mission.statut ∈ {ABSENCE, ANNULEE_PAR_ETABLISSEMENT, ANNULEE_PAR_SOIGNANT, EXPIREE}`. Avant : affichait la décomposition complète comme si la mission était payable → risque de déclaration de paiement erronée par l'établissement.

---

## 8. Tests Stripe Connect — cartes test spécifiques

**Piège documenté le 22/04/2026** suite au diagnostic du paiement M2 bloqué.

En **mode TEST** Stripe Connect, les paiements carte **`4242 4242 4242 4242`** (carte "Visa OK" classique) créditent le solde **`pending`** de la plateforme et **PAS** le solde **`available`**. Or `stripe.transfers.create()` vers un compte Connect puise **uniquement dans `available`** — pas `pending`. Conséquence : chaque paiement Checkout Connect en test échoue côté webhook avec :

```
StripeInvalidRequestError: balance_insufficient — You have insufficient
available funds in your Stripe account. Try adding funds directly to your
available balance by creating Charges using the 4000000000000077 test card.
```

Côté Jolene, le webhook ne retourne jamais d'erreur user-visible (retour 200 normal pour respect Stripe retry logic), donc symptôme côté UI :
- Checkout "Payé" vert côté Stripe Dashboard
- Mission reste à payer à l'infini dans `ObligationsFinancieres`
- Boucle Payer → blocage → Refund → rebelote

### Cartes test à utiliser pour vérifier Stripe Connect

| Besoin | Carte test | Comportement |
|--------|-----------|--------------|
| **Tester Connect end-to-end** (transfer vers compte soignant) | `4000 0000 0000 0077` | Crédite `available` immédiatement → `transfers.create()` OK |
| Tester paiement échec | `4000 0000 0000 0002` | Décliné |
| Tester 3DS | `4000 0025 0000 3155` | 3DS required |
| Tester insufficient funds (hors Connect) | `4000 0000 0000 9995` | Refuse charge |

**Référence** : [stripe.com/docs/testing#available-balance](https://stripe.com/docs/testing#available-balance)

### En production

**Non concerné**. Les vrais paiements carte sont instantanément crédités sur `available` (hors cas spécifiques : SEPA, disputes). La bascule `pending → available` en test est un garde-fou Stripe pour éviter que des développeurs testent des transfers sans solde réel.

### Protection côté code (22/04/2026)

Le webhook `stripe-webhook/index.ts` contenait un catch cassé autour de `stripe.transfers.create()` qui tentait un UPDATE avec une colonne `modifie_le` inexistante dans `stripe_transfers` → UPDATE fail silencieux → row reste EN_ATTENTE + 0 audit. Fix 22/04 :

- Retrait de `modifie_le` (colonne inexistante)
- Remplissage `stripe_transfers.erreur` avec code + message Stripe
- Audit `FINANCE_TRANSFER_FAILED` systématique avec détails (code, message, type, montant, IDs)
- `console.error` explicite pour observabilité Supabase logs

---

## 9. Glossaire rapide

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

## 10. Références

- `supabase/migrations/20260421134646_fix_obligations_filtre_resolu.sql` — filtre paiements_soignant
- `supabase/migrations/20260421154817_obligations_filtre_stripe_transfers.sql` — filtre stripe_transfers (défense en profondeur)
- `supabase/migrations/20260422090000_fix_obligations_type_contrat_mission.sql` — expose type_contrat_applique dans fn_obligations_financieres
- E16 tickets inventaire (CP-C-1.5) — MIXTE×TOUS + figement type_contrat_applique
- Sub-PR D — Stripe Connect prod-ready (CP-STRIPE-1 à 6)
- CP-STRIPE-3 — compensation Checkout Session orpheline (H5 + H8)

---

**Fin du document v1**. Toute évolution (nouveau type de contrat, changement de règle commission, bascule Modèle B "Jolene URSSAF", etc.) → créer `logique-paiements-v2.md` et archiver v1.
