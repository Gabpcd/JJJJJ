# Annulation mission — règles légales et impact score

> Sprint 3.5 PR 4-5. Grille validée par Gabrielle. Aucune pénalité
> financière côté soignant. Aucune suspension automatique. Réclamation
> admin possible sur chaque ajustement.

## Fenêtre de rétractation

**30 minutes** après acceptation : annulation libre sans impact score
(soignant et étab). Au-delà, la grille s'applique.

Stockage : `candidatures.acceptee_a` (trigger auto BEFORE UPDATE statut).
Helper : `fn_dans_fenetre_retractation(candidature_id)`.

## Grille soignant

| Délai avant mission | Mission ASAP | Points score |
|---|---|---|
| **Fenêtre 30 min** (toutes missions) | — | 0 (libre) |
| **> 24h** | non | 0 (neutre) |
| **12-24h** | non | **-5** (`ANNULATION_12_24H`) |
| **1-12h** | non | **-10** (`ANNULATION_1_12H`) |
| **< 1h ou no-show** | non | **-30** (`NO_SHOW`) + signalement admin |
| **< 2h** | **oui** | **-25** (`ASAP_ANNULEE_APRES_FENETRE`) |

**Aucune pénalité financière soignant**. Tous les events sont
**contestables** via la réclamation admin (PR 7-8 Sprint 3.5).

## Grille étab + indemnités

| Statut mission | Points score étab | Indemnité due au soignant |
|---|---|---|
| **OUVERTE** (pas encore acceptée) | 0 (libre) | — |
| **ACCEPTEE, < 30 min après accept** | 0 (libre) | — |
| **ACCEPTEE, contrat non signé** | **-3** | — |
| **CDD signé avant pointage** | **-10** | `duree × taux × 1.10` (art. L1243-8) |
| **LIBERAL signé < 24h avant** | **-10** | **50% montant total** (art. 1231-5) |
| **LIBERAL signé 24-48h** | **-10** | **30%** |
| **LIBERAL signé > 48h** | **-10** | **10%** |
| **Après pointage commencé** | **-20** | **100% (montant complet dû)** |

Indemnité versée via Stripe Connect transfer (enqueué dans
`externalisation_actions`). Avoir PDF généré pour traçabilité comptable.

## Workflows annulation

### Soignant : `fn_annuler_candidature_soignant`

```
1. Vérif auth (soignant_id = auth.uid())
2. Validation motif catégorie obligatoire (URGENCE_PERSONNELLE,
   URGENCE_MEDICALE, DEUIL, PROBLEME_TRANSPORT, CHANGEMENT_AVIS, AUTRE)
3. Texte libre min 10 chars
4. Calcul pénalité via fn_calculer_penalite_annulation_soignant
5. Si EN_ATTENTE : annulation libre, 0 pt
6. Si ACCEPTEE :
   - candidatures.statut = ANNULEE_SOIGNANT
   - mission repasse OUVERTE pour nouvelles candidatures
   - Si contrat existant : contrat.statut = RUPTURE_SOIGNANT
   - Si CDD signé : enqueue DPAE_ANNULATION (URSSAF 48h)
   - INSERT evenement_score_soignant (contestable=true)
   - Notification étab email + push
   - Si no-show : ALERTE_ADMIN_NO_SHOW dans audit (PAS suspension auto)
```

### Étab : `fn_annuler_mission_etab`

```
1. Vérif auth (mon_etablissement_id = mission.etablissement_id)
2. Validation motif catégorie (BESOIN_DISPARU, BUDGET_REVU,
   REMPLACEMENT_INTERNE, CHANGEMENT_PLANNING, CAS_FORCE_MAJEURE, AUTRE)
3. Texte libre min 10 chars
4. 4 cas distincts :
   - OUVERTE → libre, 0 pt
   - Pointage commencé → -20 pts + salaires/honoraires COMPLETS
   - Contrat signé → -10 pts + indemnité légale (Code travail/civil)
   - ACCEPTEE sans contrat → -3 pts, pas d'indemnité
5. Mission statut = ANNULEE_ETAB
6. Si CDD signé : enqueue DPAE_ANNULATION
7. Enqueue STRIPE_REFUND_PARTIEL pour verser indemnité au soignant
8. Enqueue AVOIR_PDF_GENERATION
9. Notif soignant email + push avec montant indemnité
10. INSERT evenement_score_etab (contestable=true)
```

## Principes Sprint 3.5

- ✅ Aucune pénalité financière soignant
- ✅ Indemnités légales étab (Code travail L1243-8 + Code civil 1231-5)
- ✅ Aucune suspension automatique
- ✅ Toute pénalité score est contestable (réclamation admin)
- ✅ Signalement admin sur cas suspect (no-show) **sans action auto**

## Notifications

Toutes via `externalisation_actions` (queue async) :
- `CANDIDATURE_ANNULEE_SOIGNANT` → étab (email + push)
- `MISSION_ANNULEE_ETAB` → soignant (email + push avec montant indemnité)
- `RECLAMATION_SCORE_DECISION` → user (email + push après décision admin)
