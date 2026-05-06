# Tests CP-C-2 — Relances paiement J+7 / J+21 (E2 + E6 + E11)

Scope : refonte `fn_alerter_paiements_retard` + 3 templates email + colonnes relances factures/missions.

## Pré-requis

- Migrations appliquées :
  - `20260420170000_cp_c_2_a_colonnes_relances` (DDL + backfill)
  - `20260420171000_cp_c_2_c_refonte_alerter_paiements` (refonte fn jsonb)
- Edge function `send-email` déployée avec 3 nouveaux types (`RAPPEL_PAIEMENT_J7`, `PAIEMENT_RETARD_J21`, `PUBLICATION_SUSPENDUE`)
- Cron `jobid 11 alerter-paiements-retard` actif `@ 0 8 * * *` (UTC)

## Tests SQL automatisables

```bash
psql "$DB_URL" -f tests/paiements/cp-c-2.test.sql
```

Couvre 9 scénarios (voir détails tests/paiements/cp-c-2.test.sql) :
- [1] Signature jsonb retourne `emails_queued`
- [2] Mission J+8 non déclarée → `RAPPEL_PAIEMENT_J7` queued
- [3] Idempotence J+7 (déjà relancé → no-op)
- [4] Mission J+22 → `PAIEMENT_RETARD_J21` queued
- [5] Mission avec paiement `DECLARE` → aucune relance
- [6] Facture commission J+8 `EMISE` → `RAPPEL_PAIEMENT_J7` queued avec `type_obligation=FACTURE_COMMISSION`
- [7] Facture commission J+22 `EN_RETARD` → `PAIEMENT_RETARD_J21` queued
- [8] Facture `PAYEE` → aucune relance
- [9] Mission LIBERAL → aucune relance (filtre `type_contrat_applique='SALARIE'`)

Chaque scénario isolé via `BEGIN/ROLLBACK`.

## Scénarios manuels E2E

### M1 — Template RAPPEL_PAIEMENT_J7 (PAIEMENT_SOIGNANT)

**Étapes** :
1. Dans Supabase SQL Editor ou via psql, exécuter :
   ```sql
   INSERT INTO public.email_queue (type, destinataire_email, data)
   VALUES (
     'RAPPEL_PAIEMENT_J7',
     '<email_test_etab>',
     jsonb_build_object(
       'type_obligation', 'PAIEMENT_SOIGNANT',
       'mission_id', 'test-uuid',
       'mission_intitule', 'Mission Test CP-C-2',
       'soignant_prenom', 'Pierre',
       'soignant_nom', 'Martin',
       'montant_estime', 250.50,
       'date_fin_mission', '18/04/2026',
       'etablissement_nom', 'EHPAD Test'
     )
   );
   ```
2. Déclencher manuellement email-cron OU attendre 8h (cron jobid 4) :
   ```bash
   curl -X POST https://<PROJECT>.supabase.co/functions/v1/email-cron \
     -H "Authorization: Bearer <service_role_key>"
   ```

**Vérifications** :
- [ ] Email reçu dans inbox
- [ ] Subject : `Rappel : paiement de Pierre Martin à déclarer — 7 jours`
- [ ] Body : mention mission + montant + date fin
- [ ] Ton bienveillant, aucune mention de blocage
- [ ] Bouton CTA "Régulariser maintenant →" vers `/etablissement/obligations-financieres`
- [ ] `email_queue.envoye=TRUE`, `envoye_le` set

### M2 — Template RAPPEL_PAIEMENT_J7 (FACTURE_COMMISSION)

**Étapes** : idem M1 avec data :
```json
{
  "type_obligation": "FACTURE_COMMISSION",
  "numero_facture": "JC-2026-00042",
  "montant_ttc": 1200.00,
  "date_emission": "18/04/2026",
  "etablissement_nom": "EHPAD Test"
}
```

**Vérifications** :
- [ ] Subject : `Rappel : facture JC-2026-00042 à régler — 7 jours`
- [ ] Body : mention numéro + montant TTC + date émission
- [ ] Bouton CTA vers `/etablissement/facturation`

### M3 — Template PAIEMENT_RETARD_J21 (PAIEMENT_SOIGNANT)

Data identique à M1 mais type=`PAIEMENT_RETARD_J21` + ajout `jours_retard=21`, `jours_avant_blocage=24`.

**Vérifications** :
- [ ] Subject inclut "⚠️ ... 21 jours — action requise"
- [ ] Mention explicite "Sans régularisation sous 24 jours, la publication de nouvelles missions sera suspendue"
- [ ] Mention légale contextuelle : `L8222-1 Code du travail` (PAIEMENT_SOIGNANT)
- [ ] Bouton CTA "Régulariser immédiatement →"

### M4 — Template PAIEMENT_RETARD_J21 (FACTURE_COMMISSION)

**Vérifications** :
- [ ] Même structure avec mention légale `L441-10 Code de commerce`

### M5 — Template PUBLICATION_SUSPENDUE

**Étapes** : INSERT email_queue avec data :
```json
{
  "etablissement_nom": "EHPAD Test",
  "obligations_en_cours": "2 paiements soignants (450€)<br/>1 facture commission JC-2026-00042 (1200€)",
  "total_montant_du": "1650,00",
  "date_blocage": "20/04/2026"
}
```

**Vérifications** :
- [ ] Subject : `❌ Publication de missions suspendue — EHPAD Test`
- [ ] Mention déblocage auto + mention légale L8222-1

**Note** : ce template est créé en CP-C-2 mais sera déclenché par CP-C-3 (blocage auto @ J+45). Ce test manuel valide le rendu seulement.

### M6 — Flow complet simulation J+7

**Étapes** :
1. Créer mission SALARIE de test dans UI étab test
2. La passer TERMINEE via flow pointage normal
3. Via SQL :
   ```sql
   UPDATE public.missions
   SET fin_le = NOW() - INTERVAL '8 days',
       relance_paiement_1_le = NULL
   WHERE id = '<mission_id>';
   ```
4. Déclencher manuellement :
   ```sql
   SELECT public.fn_alerter_paiements_retard();
   ```

**Vérifications** :
- [ ] Retour jsonb : `missions_j7 >= 1`, `emails_queued >= 1`
- [ ] `SELECT * FROM public.email_queue WHERE data->>'mission_id'='<mission_id>'` → 1 ligne type `RAPPEL_PAIEMENT_J7`
- [ ] Email reçu (après run email-cron)
- [ ] `SELECT relance_paiement_1_le FROM public.missions WHERE id='<mission_id>'` → non NULL
- [ ] Notification in-app visible dans Dashboard étab

### M7 — Flow complet simulation J+21

**Étapes** : continuer M6 avec :
```sql
UPDATE public.missions
SET fin_le = NOW() - INTERVAL '22 days',
    relance_paiement_1_le = NOW() - INTERVAL '15 days',
    relance_paiement_2_le = NULL
WHERE id = '<mission_id>';
SELECT public.fn_alerter_paiements_retard();
```

**Vérifications** :
- [ ] Retour `missions_j21 >= 1`
- [ ] 2ème email reçu type `PAIEMENT_RETARD_J21`
- [ ] Mention 24j avant suspension
- [ ] `relance_paiement_2_le` set

### M8 — Vérification cron

**Étapes** :
```sql
SELECT jobid, jobname, schedule, active FROM cron.job WHERE jobid = 11;
SELECT * FROM cron.job_run_details WHERE jobid = 11 ORDER BY start_time DESC LIMIT 5;
```

**Vérifications** :
- [ ] jobid 11 `alerter-paiements-retard` actif
- [ ] Schedule `0 8 * * *`
- [ ] Dernières exécutions sans erreur (status='succeeded')

## Vérifications post-prod

```sql
-- Emails queued dans les 24h
SELECT type, COUNT(*) AS nb
FROM public.email_queue
WHERE type IN ('RAPPEL_PAIEMENT_J7','PAIEMENT_RETARD_J21')
AND cree_le > NOW() - INTERVAL '24 hours'
GROUP BY type;

-- Taux envoi (envoye/total)
SELECT
  SUM(CASE WHEN envoye THEN 1 ELSE 0 END)::FLOAT / NULLIF(COUNT(*), 0) AS taux_envoi,
  COUNT(*) AS total,
  COUNT(*) FILTER (WHERE erreur IS NOT NULL) AS erreurs
FROM public.email_queue
WHERE type IN ('RAPPEL_PAIEMENT_J7','PAIEMENT_RETARD_J21')
AND cree_le > NOW() - INTERVAL '7 days';

-- Missions relancées récemment
SELECT id, intitule, fin_le, relance_paiement_1_le, relance_paiement_2_le
FROM public.missions
WHERE statut='TERMINEE'
AND type_contrat_applique='SALARIE'
AND (relance_paiement_1_le > NOW() - INTERVAL '7 days'
     OR relance_paiement_2_le > NOW() - INTERVAL '7 days')
ORDER BY fin_le DESC;

-- Factures relancées récemment
SELECT id, numero_facture, date_emission, relance_1_le, relance_2_le
FROM public.factures
WHERE statut IN ('EMISE','EN_RETARD')
AND (relance_1_le > NOW() - INTERVAL '7 days'
     OR relance_2_le > NOW() - INTERVAL '7 days')
ORDER BY date_emission DESC;
```

## Tickets clôturés

- **E2** (P0, 8h → 7h) : 3 templates email RAPPEL_PAIEMENT_J7 + PAIEMENT_RETARD_J21 + PUBLICATION_SUSPENDUE → **RÉSOLU**
- **E6** (P1, 3h → 2h) : colonne `relance_2_le` désormais utilisée (sur missions + factures) → **RÉSOLU**
- **E11** (P0, 6h → 3h) : cron J+7 implémenté (refonte fn_alerter_paiements_retard + email_queue) → **RÉSOLU**

## Décisions architecturales

1. **Réutilisation cron existant** (jobid 11) plutôt que création nouveau cron — évite duplication + garantit run à 8h quotidien.
2. **Pattern email_queue + email-cron** préféré à invoke direct — aligne avec triggers email existants (fn_trg_email_*).
3. **Option A (colonnes missions)** validée pour tracer relances paiement soignant — plus simple + source de vérité claire (mission dicte l'obligation).
4. **Backfill anti-spam** : 185 missions + 4 factures pré-existantes ont relance_*_le backfillée à NOW() pour éviter spam de 189 emails au 1er run CP-C-2.
5. **Blocage auto @ J+60 supprimé** — sera déplacé à J+45 dans CP-C-3 avec mécanisme unifié (flag `etablissements.peut_publier_missions` + email PUBLICATION_SUSPENDUE).
