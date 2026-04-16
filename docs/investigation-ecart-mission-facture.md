# Investigation — Écart missions.net_a_payer vs factures_honoraires.montant_ht

> Date : 2026-04-16
> Déclencheur : vérification post-CP4 montrant des écarts de 3€ à 303€

## 1. Tableau complet des 10 factures

### Factures avec écart NON-NUL (6 — toutes seeded)

| # | Numéro | Mission | Écart | % | Template | Seeded? |
|---|---|---|---|---|---|---|
| 1 | FH-2026-04-0001 | e...101 | +3.00 | +0.8% | v1 | **OUI** |
| 2 | FH-2026-04-0005 | e...107 | -32.00 | -11.8% | v1 | **OUI** |
| 3 | FH-2026-04-0002 | e...102 | -68.40 | -16.0% | v1 | **OUI** |
| 4 | FH-2026-04-0003 | e...103 | +36.00 | +17.6% | v1 | **OUI** |
| 5 | FH-2026-04-0006 | e...108 | -303.00 | -45.7% | v1 | **OUI** |
| 6 | FH-2026-04-0004 | e...104 | +13.65 | +7.0% | v1 | **OUI** |

### Factures avec écart NUL (4 — toutes générées par le vrai flow)

| # | Numéro | Mission | Écart | Template | Seeded? |
|---|---|---|---|---|---|
| 7 | FH-2026-04-0007 | 0b48bb29... | 0.00 | v1 | Non |
| 8 | FH-2026-04-0008 | e...120 | 0.00 | v1 | Non (ID seeded, facture réelle) |
| 9 | JOL-98765432-2026-00001 | 61e7425d... | 0.00 | v2_facturx | Non |
| 10 | JOL-98765432-2026-00002 | 457b65da... | 0.00 | v2_facturx | Non |

## 2. Code de generate-invoice — calcul de montant_ht

**Fichier** : `supabase/functions/generate-invoice/index.ts`, ligne 470

```typescript
const amountHt = Number(mission.net_a_payer) || Number(mission.total_brut) || 0;
```

**La facture utilise `mission.net_a_payer` directement comme `montant_ht`.**

Il n'y a aucun recalcul indépendant. Le montant_ht de la facture est exactement `net_a_payer` au moment de la génération. Pas de logique divergente, pas de formule alternative.

Les 4 factures générées par le vrai flow (FH-0007, FH-0008, JOL-00001, JOL-00002) le confirment : **écart = 0.00 pour chacune**.

## 3. Diagnostic par facture en écart

### Cause unique : données seeded par Lovable avec des valeurs arbitraires

Les 6 factures en écart ont toutes :
- `facture.id` en pattern `f1000000-...` (UUID seeded)
- `mission.id` en pattern `e0000000-...` (UUID seeded)
- `template_version = 'v1'`
- `pdf_s3_key = null` (aucun PDF réel généré)

Ces factures ont été INSERTées directement par les scripts de seed Lovable, **pas générées par generate-invoice**. Les montant_ht ont été fixés manuellement et ne correspondent pas aux missions associées.

### Preuves : incohérence INTERNE des missions seeded

Les missions seeded ont elles-mêmes des valeurs financières incohérentes :

| Mission | total_brut actuel | total_brut attendu (taux×duree+majorations) | Écart interne |
|---|---|---|---|
| e...101 | 300.00 | 300.00 | 0 ✓ |
| e...102 | 300.00 | 356.25 | **-56.25** (majorations non incluses) |
| e...103 | 200.00 | 300.00 | **-100.00** (majorations non incluses) |
| e...104 | 175.00 | 175.00 | 0 ✓ |
| e...107 | 200.00 | 200.00 | 0 ✓ |
| e...108 | 300.00 | 606.25 | **-306.25** (majorations non incluses) |
| e...120 | 200.00 | 200.00 | 0 ✓ |

**Pattern** : les missions seeded avec des majorations (nuit, dimanche, férié) ont un `total_brut` qui N'INCLUT PAS les majorations. Le seed Lovable a probablement INSERTé `total_brut = taux × duree` sans passer par le trigger `fn_calculer_financier_mission`. Les majorations ont été ajoutées séparément.

Conséquence en cascade : `net_a_payer = total_brut + IFM + ICP` est aussi faux (basé sur le total_brut tronqué). Donc même si generate-invoice utilisait `net_a_payer`, le montant serait erroné.

## 4. Catégorisation

| Catégorie | Nombre | Cause |
|---|---|---|
| Données seeded — montant_ht arbitraire dans facture | 6 | Script seed Lovable a INSERTé les factures sans passer par generate-invoice |
| Données seeded — mission financièrement incohérente | 3 sur 6 | Script seed a INSERTé les missions sans passer par fn_calculer_financier_mission |
| Factures générées par le vrai flow | 4 | **Écart = 0 pour toutes** |

**Il y a UNE seule cause : les données de test seeded par Lovable sont incohérentes.**

## 5. Code en cause

Aucun bug dans le code de production.

- `generate-invoice/index.ts:470` : `amountHt = Number(mission.net_a_payer)` — **correct**
- `fn_calculer_financier_mission` : calcule total_brut = base + majorations — **correct**
- Les écarts viennent du **seed data**, pas des triggers ni de l'edge function

## 6. Hypothèse de correction

### Pas de correction code nécessaire

Le flow `generate-invoice` est correct :
1. Il lit `mission.net_a_payer` au moment de la génération
2. Il le stocke comme `factures_honoraires.montant_ht`
3. Le résultat est montant_ht = net_a_payer au moment T de la génération

### Action recommandée : purge des données seeded

Les 6 factures seeded (`f1000000-...`) et les missions associées seront purgées par le script `purge-test-data.ts` (CP6) avant le go-live.

### Pas de ticket tech-debt supplémentaire

L'écart "missions vs factures" documenté dans tech-debt.md peut être reclassifié de "bug potentiel" à "artefact de données de test". En production, avec des données créées via le flow normal (RPC → trigger → generate-invoice), les montants sont cohérents.

## 7. Étendue du seeding incohérent

### missions (268 total)

| Origine | Total | total_brut incohérent | Pattern |
|---|---|---|---|
| Batch 2026-03-25 | 204 | **204 (100%)** | total_brut = base SANS majorations |
| Batch 2026-03-11 | 30 | 12 (40%) | Idem |
| Seeded 2026-04-09 (e-pattern) | 17 | 7 (41%) | Idem |
| **Organic (via UI/RPC, post 2026-03-16)** | **17** | **0 (0%)** | **Tous cohérents** |

**223/268 missions incohérentes — toutes issues de seed batches.** Les 17 missions créées via le flow normal (RPC → triggers) sont 100% cohérentes.

Le pattern d'incohérence est unique : `total_brut = taux_effectif × duree_heures` SANS inclure les majorations (nuit, dimanche, férié). Les majorations sont stockées mais pas additionnées dans total_brut. Cause : les seeds INSERTent en bypassant `fn_calculer_financier_mission`.

### factures (commissions Jolene) — 10 rows

Toutes non-seeded (UUIDs organiques). Pas d'incohérence vérifiable sans le détail des calculs de commission mensuelle. À purger avec les missions associées.

### factures_honoraires — 10 rows

6 seeded (f1000000 pattern) avec écarts 3€–303€. 4 organic avec 0 écart. Déjà analysé en §1-6.

### stripe_transfers — 6 rows

| Type | Total | montant_soignant = net_a_payer | montant_commission = commission_ttc |
|---|---|---|---|
| Seeded missions | 4 | 3/4 ✓ | 1/4 ✓ (écarts commission 3€–23€) |
| Organic missions | 2 | **2/2 ✓** | **2/2 ✓ (exact)** |

Les 2 real stripe_transfers (missions créées via le flow) ont des montants parfaitement cohérents.

### factor_advances — 2 rows, paiements_mission — 4 rows, cotisations_sociales — 6 rows

Tous avec UUIDs organiques. À vérifier lors de la purge.

### Synthèse : combien de rows à purger au go-live ?

| Table | Total | Seeded/incohérent | À purger |
|---|---|---|---|
| missions | 268 | ~251 | Oui (toutes les missions test) |
| mission_creneaux | 265 | ~248 | Cascade (ON DELETE CASCADE) |
| mission_series | 1 | 1 (SERIE_DEMO_001) | Oui |
| factures_honoraires | 10 | 6 | Oui (les 6 seeded + les 4 de test) |
| factures | 10 | ~10 | Oui |
| stripe_transfers | 6 | 4 | Oui (probablement toutes — données test) |
| factor_advances | 2 | 0 | Oui (test) |
| paiements_mission | 4 | 0 | Oui (test) |
| cotisations_sociales | 6 | 0 | Oui (test) |

**Estimation : ~600 rows à purger au total, répartis sur ~10 tables.** Toutes sont des données de test. Le script `purge-test-data.ts` (CP6) gérera ça.

## 8. Risque résiduel

Un risque théorique existe si `mission.net_a_payer` est modifié APRÈS la génération de la facture (ex: un trigger recalcule les financials suite à une modification). Dans ce cas, `missions.net_a_payer ≠ factures_honoraires.montant_ht`.

**Mitigation existante** : le trigger `trg_protect_creneaux_facture` empêche la modification des créneaux sur les missions facturées. De plus, les protecteurs (`dec_proteger_mission_soignant`) empêchent la modification des financials par des non-admin.

Le seul scénario qui crée un écart post-facturation : un admin modifie `taux_horaire_base` ou `taux_commission` sur une mission TERMINEE déjà facturée. Ce scénario est volontaire (correction admin) et ne constitue pas un bug.
