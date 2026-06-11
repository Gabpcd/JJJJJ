# Business Plan — Jolene SASU

> Prévisionnel financier 3 ans. Chiffres au 11/06/2026.
> Capital social : 1 000 €. Trésorerie à date : 1 000 €. CA réalisé : 0 €.

## 1. Hypothèses clés

| Paramètre | Valeur | Source |
|---|---|---|
| Commission moyenne | 15 % du brut mission | Palier Découverte (dégressif) |
| Panier moyen mission (brut) | 450 € (8h × 56 €/h) | Taux IDE moyen |
| Commission moyenne par mission | 67,50 € HT | 15 % × 450 € |
| Coût d'acquisition client | 0 € | Acquisition organique (SEO, base FINESS/CNAM, parrainage) |
| Charges sociales présidente SASU | ~82 % du net versé | Assimilée salariée |
| Charges fixes SaaS/mois | 73 € | Supabase 25 + Resend 20 + Lovable 20 + Apple Dev 8 |
| Stripe fees | 1,4 % + 0,25 € par paiement | Stripe Connect |

## 2. Plan de financement initial (J0)

| Besoins | Montant | Ressources | Montant |
|---|---|---|---|
| Trésorerie de démarrage | 5 000 € | Capital social | 1 000 € |
| Développement produit (déjà réalisé) | 0 € (en nature) | BFT Bpifrance (demandé) | 50 000 € |
| Programme R&D 12 mois (§4 dossier) | 105 000 € | Innov'up Faisabilité (demandé) | 30 000 € |
| BFR (avance soignants 1er mois) | 10 000 € | Prêt d'honneur PIE/RE (demandé) | 30 000 € |
| Imprévus (10 %) | 10 000 € | Fonds propres + CA | 19 000 € |
| **Total** | **130 000 €** | **Total** | **130 000 €** |

## 3. Compte de résultat prévisionnel (3 ans)

### Hypothèses de croissance

| | A1 (M1→M12) | A2 | A3 |
|---|---|---|---|
| Établissements actifs (fin d'année) | 15 | 60 | 200 |
| Missions terminées / mois (fin d'année) | 30 | 200 | 800 |
| Missions terminées cumulées sur l'année | 180 | 1 400 | 6 000 |

### Compte de résultat

| Poste | A1 | A2 | A3 |
|---|---|---|---|
| **Chiffre d'affaires (commissions HT)** | 12 150 € | 94 500 € | 405 000 € |
| | 180 missions × 67,50 € | 1 400 × 67,50 € | 6 000 × 67,50 € |
| Options premium (SaaS RH, boost) | 0 € | 5 000 € | 30 000 € |
| **CA total HT** | **12 150 €** | **99 500 €** | **435 000 €** |
| | | | |
| Salaire net présidente | 0 → 10 800 € | 26 400 € | 33 600 € |
| Charges sociales (~82 %) | 8 856 € | 21 648 € | 27 552 € |
| **Coût salarial total** | **19 656 €** | **48 048 €** | **61 152 €** |
| Charges fixes SaaS (× 12) | 876 € | 1 200 € | 2 400 € |
| Stripe fees (1,4 % CA + 0,25 €/tx) | 215 € | 1 743 € | 7 590 € |
| Inférence IA (vérification docs) | 500 € | 3 000 € | 10 000 € |
| Hébergement / infra (évolution) | 0 € | 1 200 € | 3 600 € |
| Frais de déplacement terrain | 2 000 € | 3 000 € | 5 000 € |
| Expert-comptable | 1 500 € | 2 400 € | 3 600 € |
| Assurance RC Pro | 500 € | 600 € | 800 € |
| Divers / imprévus | 1 000 € | 2 000 € | 5 000 € |
| **Total charges** | **26 247 €** | **63 191 €** | **99 142 €** |
| | | | |
| **Résultat avant impôt** | **-14 097 €** | **+36 309 €** | **+335 858 €** |
| IS (15 % puis 25 %) | 0 € | 5 446 € | 82 715 € |
| **Résultat net** | **-14 097 €** | **+30 863 €** | **+253 143 €** |

> A1 déficitaire = normal (pré-revenu + pilote). Rentabilité dès A2 grâce aux charges
> ultra-basses (solo founder, pas de locaux, acquisition organique). Marge nette A3 ~58 %
> typique d'un SaaS marketplace à commission.

## 4. Plan de trésorerie M1→M12 (Année 1)

| Mois | Encaissements | Décaissements | Solde fin de mois |
|---|---|---|---|
| M1 | 1 000 (capital) | 300 (charges fixes + EC) | 700 |
| M2 | 0 | 300 | 400 |
| M3 | 50 000 (BFT tranche 1, 70 %) | 300 | 50 100 |
| M4 | 30 000 (Innov'up) | 2 500 (terrain + infra) | 77 600 |
| M5 | 0 | 2 500 | 75 100 |
| M6 | 15 000 (prêt d'honneur) | 2 500 | 87 600 |
| M7 | 675 (10 missions × 67,50 €) | 5 900 (1er salaire 3 400 + charges) | 82 375 |
| M8 | 1 350 (20 missions) | 5 900 | 77 825 |
| M9 | 1 350 | 5 900 | 73 275 |
| M10 | 2 025 (30 missions) | 5 900 | 69 400 |
| M11 | 2 025 | 5 900 | 65 525 |
| M12 | 2 025 + 15 000 (BFT solde 30 %) | 5 900 | 76 650 |

> Trésorerie toujours positive. Le creux est absorbé par les subventions. Le salaire
> ne démarre qu'au M7 (après réception de la 1re tranche BFT + Innov'up).

## 5. Seuil de rentabilité

- Charges fixes mensuelles (avec salaire) : ~5 200 €/mois
- Commission moyenne par mission : 67,50 €
- **Point mort : 78 missions/mois** (~3,5 missions/jour ouvré)
- Atteint estimé : **M8-M10 de l'année 2** (avec 60 établissements actifs)

## 6. BFR (Besoin en Fonds de Roulement)

- Délai d'encaissement établissements : 30 jours (Stripe) à 60 jours (Chorus Pro public)
- Délai de paiement soignants : 7-14 jours (Stripe Connect) ou fin de mois (virement)
- **BFR estimé A2 : ~15 000 €** (1,5 mois de charges), couvert par le prêt d'honneur
