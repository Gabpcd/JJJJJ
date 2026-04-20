# Tests CP-C-3 — Blocage auto étab + unfreeze (E1 + E7 + E9)

Scope : `fn_gerer_blocage_etabs` + bandeau UI + intégration cron.

## Pré-requis

- Migrations appliquées :
  - `20260420180000_cp_c_3_a_blocage_auto_etab` (DDL + fn_creer_mission check)
  - `20260420181000_cp_c_3_c_gerer_blocage_etabs` (fonction + alter cron)
  - `20260420182000_cp_c_3_d_email_queue_statut_mon_etab` (enum statut + fn_mon_etab extended)
- Edge function `send-email` déployée avec `PUBLICATION_REACTIVEE`
- Frontend déployé : `BandeauBlocageAuto.tsx` + Dashboard étab

## Tests SQL

```bash
psql "$DB_URL" -f tests/paiements/cp-c-3.test.sql
```

Couvre 7 scénarios (BEGIN/ROLLBACK + bypass triggers via session_replication_role=replica) :
- [1] Signature retour jsonb contient `blocages` + `deblocages`
- [2] Blocage mission SALARIE TERMINEE >45j non déclarée → 4 effets (bloque_auto_le, raisons, historique BLOCAGE, email queued)
- [3] Blocage facture commission >45j impayée
- [4] Idempotence étab déjà bloqué → 0 double action
- [5] Déblocage auto après régularisation (étab bloqué + 0 retard effectif → unfreeze + email PUBLICATION_REACTIVEE)
- [6] Étab SUSPENDU manuel → non traité par blocage auto (filtre VERIFIE only)
- [7] fn_creer_mission refuse si bloqué — validation en M3 (contexte JWT requis)

## Checklist manuelle E2E

### M1 — UI BandeauBlocageAuto affiché

**Étapes** :
1. Sur un étab de test Gabrielle utilise quotidiennement :
   ```sql
   UPDATE public.etablissements
   SET bloque_auto_le = NOW(),
       bloque_auto_raisons = '{
         "paiements_retard_nb": 2,
         "paiements_retard_montant": 450,
         "factures_retard_nb": 1,
         "factures_retard_montant": 1200,
         "seuil_jours": 45
       }'::jsonb
   WHERE id = '<etab_test_id>';
   ```
2. Refresh `jolene.app/etablissement/dashboard`

**Vérifications** :
- [ ] Bandeau rouge destructive visible en haut du dashboard
- [ ] Icône Ban + titre "Publication de missions suspendue"
- [ ] Date "Depuis le X avril 2026"
- [ ] Ligne 1 : "2 paiement(s) soignant(s) en retard — 450,00 €"
- [ ] Ligne 2 : "1 facture(s) commission impayée(s) — 1 200,00 €"
- [ ] Total dû : 1 650,00 €
- [ ] Mention "réactivé automatiquement dès régularisation"
- [ ] Bouton "Déclarer paiements soignants" → navigate `/etablissement/obligations-financieres`
- [ ] Bouton "Payer factures commission" → navigate `/etablissement/facturation`
- [ ] Bandeau vérification "en cours de vérification" **PAS affiché** (priorité au BandeauBlocageAuto)

### M2 — Déblocage en live

**Étapes** :
```sql
UPDATE public.etablissements SET bloque_auto_le=NULL, bloque_auto_raisons=NULL
WHERE id = '<etab_test_id>';
```

**Vérifications** :
- [ ] Refresh : BandeauBlocageAuto disparaît
- [ ] Dashboard normal visible

### M3 — fn_creer_mission refuse si bloqué

**Étapes** :
1. Re-bloquer l'étab : `UPDATE etablissements SET bloque_auto_le=NOW() WHERE id=...`
2. Tenter création mission via UI ou RPC directe :
   ```sql
   SELECT public.fn_creer_mission(
     p_intitule := 'Test M3',
     p_profession_requise := 'IDE',
     p_debut_le := NOW() + INTERVAL '2 days',
     p_fin_le := NOW() + INTERVAL '2 days 8 hours',
     p_taux_horaire_base := 25
   );
   ```

**Vérifications** :
- [ ] Retour : `{ error: 'PUBLICATION_SUSPENDUE', message, bloque_auto_le, raisons }`
- [ ] Mission **non créée** dans la table missions

### M4 — Email PUBLICATION_SUSPENDUE rendering

**Étapes** :
```sql
INSERT INTO email_queue (type, destinataire_email, data, statut)
VALUES (
  'PUBLICATION_SUSPENDUE',
  '<email_test>',
  jsonb_build_object(
    'etablissement_nom', 'Clinique Test',
    'obligations_en_cours', '2 paiement(s) soignant(s) en retard (450 EUR)<br/>1 facture(s) commission en retard (1200 EUR)',
    'total_montant_du', '1650,00',
    'date_blocage', '20/04/2026'
  ),
  'EN_ATTENTE'
);
```
Attendre cron ou déclencher manuellement `email-cron`.

**Vérifications** :
- [ ] Email reçu
- [ ] Subject : `❌ Publication de missions suspendue — Clinique Test`
- [ ] Liste obligations + total + date blocage
- [ ] Mention déblocage auto
- [ ] Mention légale L8222-1

### M5 — Email PUBLICATION_REACTIVEE rendering

**Étapes** :
```sql
INSERT INTO email_queue (type, destinataire_email, data, statut)
VALUES (
  'PUBLICATION_REACTIVEE',
  '<email_test>',
  jsonb_build_object(
    'etablissement_nom', 'Clinique Test',
    'debloque_le', '20/04/2026 15:30'
  ),
  'EN_ATTENTE'
);
```

**Vérifications** :
- [ ] Subject : `✅ Publication de missions réactivée`
- [ ] Remerciement régularisation
- [ ] Rappel seuils J+7/J+21/J+45
- [ ] CTA vers dashboard

### M6 — Cycle complet blocage → déblocage

**Étapes** :
1. Créer mission SALARIE sur étab test (date début dans 2j) → passer en TERMINEE via pointage normal
2. Backdater :
   ```sql
   UPDATE missions SET fin_le = NOW() - INTERVAL '46 days', debut_le = NOW() - INTERVAL '47 days'
   WHERE id = '<mission_id>';
   ```
3. Exécuter cron manuellement :
   ```sql
   SELECT public.fn_gerer_blocage_etabs();
   ```
4. **Vérifier** : étab bloqué, email queued, historique BLOCAGE
5. UI : bandeau visible
6. Déclarer paiement via UI ObligationsFinancieres (CP-C-1)
7. Re-exécuter :
   ```sql
   SELECT public.fn_gerer_blocage_etabs();
   ```
8. **Vérifier** : étab débloqué, email PUBLICATION_REACTIVEE queued, historique DEBLOCAGE

### M7 — Vérification cron schedule

```sql
SELECT jobid, jobname, schedule, command FROM cron.job WHERE jobid=11;
```

**Attendu** :
- `jobname` = 'alerter-paiements-retard'
- `schedule` = `0 8 * * *`
- `command` = `SELECT fn_alerter_paiements_retard(); SELECT fn_gerer_blocage_etabs();`

## Vérifications post-prod

```sql
-- Étabs bloqués actuellement
SELECT id, nom, bloque_auto_le, bloque_auto_raisons
FROM public.etablissements
WHERE bloque_auto_le IS NOT NULL
ORDER BY bloque_auto_le;

-- Historique blocages/déblocages 30 derniers jours
SELECT e.nom, h.action, h.cree_le, h.raisons
FROM public.historique_blocages_etablissements h
JOIN public.etablissements e ON e.id = h.etablissement_id
WHERE h.cree_le > NOW() - INTERVAL '30 days'
ORDER BY h.cree_le DESC;

-- Emails PUBLICATION_* queued/envoyés
SELECT type, statut, COUNT(*)
FROM public.email_queue
WHERE type IN ('PUBLICATION_SUSPENDUE','PUBLICATION_REACTIVEE')
GROUP BY type, statut;
```

## Tickets clôturés

- **E1** (P0, 6h → ~5h) : logique de blocage unifiée (OR paiement soignant >45j OR facture commission >45j) via fn_gerer_blocage_etabs → **RÉSOLU**
- **E7** (P1, 6h → ~3h) : unfreeze automatique via boucle B (re-check 0 retard effectif) → **RÉSOLU**
- **E9** (P2, 6h → ~2h) : colonnes bloque_auto_le + bloque_auto_raisons + table historique_blocages_etablissements → **RÉSOLU**

## Décisions architecturales

1. **Fonction dédiée** (Option B) : `fn_gerer_blocage_etabs` séparée de `fn_alerter_paiements_retard` pour lisibilité et testabilité.
2. **Table historique séparée** (vs JSONB[]) : audit propre, queries temporelles faciles.
3. **Colonnes distinctes** `bloque_auto_le` vs `peut_publier_missions` : respect du flag admin manuel existant (7 étabs legacy préservés).
4. **email_queue.statut enum** : introduit en C3-D (ANNULE/ERREUR distincts d'ENVOYE). Ancienne colonne `envoye` conservée pour compat mais marquée deprecated.
5. **Filtre `statut_verification='VERIFIE'`** sur blocage : évite d'affecter les comptes EN_ATTENTE/SUSPENDU qui ont leur propre logique admin.
6. **Cron jobid 11 altéré** pour enchaîner les 2 fonctions dans un même run 8h quotidien.
