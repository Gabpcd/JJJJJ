# Cron litiges — déploiement et fonctionnement

## Vue d'ensemble

Deux edge functions assurent le fonctionnement asynchrone du système de litiges :

| Edge function              | Fréquence    | État     | Rôle                                                 |
| -------------------------- | ------------ | -------- | ---------------------------------------------------- |
| `litige-escalation-cron`   | Quotidien    | Actif    | Escalade auto + auto-création + rappels + alertes   |
| `process-stripe-refunds`   | Toutes 30min | Squelette (T13) | Remboursements Stripe async sur avoirs AUTO_STRIPE |

## litige-escalation-cron

### Pipeline d'exécution

Appelle en séquence les 4 RPCs `SECURITY DEFINER` :

1. **`fn_auto_creation_litiges_presence()`** — scan des présences marquées `ABSENT` (heures réelles nulles + motif_litige renseigné) validées étab depuis plus de 48h sans litige existant. Crée un litige `ABSENCE_SOIGNANT` initié par l'étab, statut `OUVERT`.

2. **`fn_envoyer_rappels_litiges()`** — pour chaque litige `OUVERT` ou `EN_DISCUSSION` sans réponse :
   - À J+1h : rappel court "1 jour"
   - À J+72h : rappel "3 jours"
   - À J+120h : rappel final "5 jours — dernière relance avant escalade"
   Idempotence via le champ `litiges.derniers_rappels_envoyes` (jsonb).

3. **`fn_litiges_escalader_auto()`** — escalade les litiges `OUVERT`/`EN_DISCUSSION` sans réponse au-delà du délai :
   - Soignant **libéral** : 72h calendaires
   - Soignant **salarié** : 5 jours ouvrés (via `fn_ajouter_jours_ouvres`, CP-LITIGES-2)
   Statut → `EN_MEDIATION`, champs `escalade_auto_le` + `escalade_auto_motif` renseignés.
   Notifications admin (in-app + email).

4. **`fn_alerter_mediation_prioritaire()`** — pour tout litige `EN_MEDIATION` sans action admin depuis plus de 7 jours, pousse une alerte prioritaire à tous les `ADMIN_PLATEFORME`.

### Auth

`Authorization: Bearer <SUPABASE_SERVICE_ROLE_KEY>` — aucune autre source acceptée.

### Déploiement

> **Statut prod au 2026-04-20** : edge function `litige-escalation-cron` **NON déployée** sur le projet Jolene (`flripxtsyegjshnhzjkz`). Source présente dans `/supabase/functions/litige-escalation-cron/`, migrations CP-LITIGES-1→7b appliquées. Action manuelle Gabrielle requise (§ *Actions manuelles Gabrielle* dans `/docs/sub-pr-2-quater-recap.md`).

1. **Déployer la function** :
   ```bash
   supabase functions deploy litige-escalation-cron
   ```

2. **Configurer le schedule** (deux options équivalentes) :

   **Option A — Dashboard** (Supabase → *Project Settings* → *Edge Functions* → *Schedules*) :
   - **Name** : `litige-escalation-cron-daily`
   - **Cron** : `0 8 * * *` (08h UTC = 09h Paris en hiver, 10h en été)
   - **Function** : `litige-escalation-cron`
   - **HTTP Method** : `POST`
   - **Payload** : `{}`

   **Option B — SQL via `cron.schedule`** (même pattern que `email-cron-daily`, jobid=4) :
   ```sql
   SELECT cron.schedule(
     'litige-escalation-cron-daily',
     '0 8 * * *',
     $$
     SELECT net.http_post(
       url := current_setting('app.settings.supabase_url') || '/functions/v1/litige-escalation-cron',
       headers := jsonb_build_object(
         'Content-Type', 'application/json',
         'Authorization', 'Bearer ' || current_setting('app.settings.service_role_key', true)
       ),
       body := '{}'::jsonb
     );
     $$
   );
   ```

3. **Secrets requis** (déjà présents si email-cron déployé) :
   - `SUPABASE_URL`
   - `SUPABASE_SERVICE_ROLE_KEY`

### Observabilité

Chaque exécution log en JSON :
```json
{
  "duration_ms": 1234,
  "results": {
    "auto_creation": { "litiges_crees": 0 },
    "rappels": { "rappels_envoyes": 5 },
    "escalade": { "escalades": 1 },
    "mediation_prioritaire": { "alertes_mediation": 0 }
  }
}
```

Les erreurs par RPC sont capturées individuellement (ne stoppent pas le pipeline). Clés `*_error` dans la réponse si une RPC échoue.

### Paramètres (table `parametres_litiges`)

| Clé                                     | Défaut | Impact                                    |
| --------------------------------------- | ------ | ----------------------------------------- |
| `delai_escalade_liberal_h`              | 72     | Délai avant escalade soignant libéral     |
| `delai_escalade_salarie_jours_ouvres`   | 5      | Délai avant escalade soignant salarié     |
| `delai_mediation_alerte_prioritaire_j`  | 7      | Délai avant alerte EN_MEDIATION prolongée |
| `delai_contestation_pointage_h`         | 48     | Fenêtre avant auto-création absence       |

Modifiables uniquement par admin via `UPDATE parametres_litiges`.

## process-stripe-refunds (squelette)

### État actuel

- **Auth** : idem cron — Bearer service_role.
- **Action** : lit simplement `stripe_refunds_queue WHERE statut = 'EN_ATTENTE'` et log le count. Ne fait AUCUN appel Stripe.
- **Log** : `{ timestamp, pending_count, status: "SKELETON_NOT_PROCESSING", next_step: "T13" }`.

### Prérequis avant activation complète (T13)

1. **T12** doit être fermé (câblage `stripe_payment_intent_id` sur `factures_honoraires` via webhook Stripe).
2. Ajout dans la function : appel `stripe.refunds.create({ payment_intent, amount, metadata: { avoir_id } })`.
3. UPDATE queue : `statut='TRAITE' | 'ECHEC'`, `stripe_refund_id`, `tentatives++`.
4. UPDATE facture avoir : `statut='REMBOURSE'`, `date_remboursement`, `reference_remboursement = stripe_refund_id`.

### Déploiement (recommandé : après T12+T13)

```bash
supabase functions deploy process-stripe-refunds
```

Schedule Supabase Dashboard :
- **Name** : `process-stripe-refunds-30min`
- **Cron** : `*/30 * * * *`
- **Function** : `process-stripe-refunds`

Pour l'instant, la function peut être déployée sans schedule — appelable manuellement pour monitoring.

## Tests

- **SQL metadata + comportemental** : `tests/litiges/cp4-cron.test.sql`
- **End-to-end** (scénarios complets) : prévus en CP-LITIGES-8 (vitest, contexte admin simulé).

## Timezone — convention Europe/Paris (CP-LITIGES-7a FIX 10)

La base Supabase stocke toutes les dates en **TIMESTAMPTZ UTC canonique**.
Les règles métiers Jolene s'expriment en heure **Europe/Paris** (DST incluse).

| Type de calcul                      | TZ à utiliser          | Pourquoi                        |
|-------------------------------------|------------------------|----------------------------------|
| Durées absolues (délai N heures)    | UTC (NOW() - INTERVAL) | Indépendant du fuseau, OK       |
| Calculs calendaires (DOW, DATE)     | `AT TIME ZONE 'Europe/Paris'` | Évite les glissements à minuit Paris |
| Jours ouvrés / jours fériés         | `AT TIME ZONE 'Europe/Paris'` | `jours_feries_fr` utilise des dates civiles Paris |
| Arithmétique « ajouter N jours »    | Wall time Paris (TIMESTAMP puis reconversion) | Préserve l'heure affichée à travers DST |

La fonction `fn_ajouter_jours_ouvres(TIMESTAMPTZ, INTEGER)` applique cette
convention : bascule interne en `TIMESTAMP Europe/Paris`, arithmétique
en jour civil, reconversion en `TIMESTAMPTZ`. Elle est utilisée par
`fn_litiges_escalader_auto` (délai salarié 5 jours ouvrés).

Les crons Supabase sont déclenchés en UTC. Un cron « 8h UTC » tourne donc
à **10h Paris en été** (CEST) et **9h Paris en hiver** (CET). Les RPCs
qui filtrent sur `cree_le < NOW() - INTERVAL 'N hours'` restent correctes
car la durée absolue est indépendante du fuseau.

## Regen PDF immédiat — pg_net (CP-LITIGES-7a FIX 18)

Pour les factures flag `pdf_a_regenerer=TRUE` issues de `fn_admin_resoudre_litige`,
la regen PDF/XML est déclenchée **immédiatement** via `pg_net.http_post` (fire-and-forget,
async) depuis la fonction SQL. Le cron ci-dessus reste filet de sécurité pour les appels
échoués (filtre `modifie_le < NOW() - INTERVAL '1 hour'`).

### Pré-requis

1. **Extension pg_net** : installée par la migration FIX 18 (`CREATE EXTENSION IF NOT EXISTS pg_net WITH SCHEMA extensions`).
2. **URL edge function** : seedée automatiquement dans `parametres_litiges.generate_invoice_url`
   (valeur par défaut : `https://<project-ref>.supabase.co/functions/v1/generate-invoice`).
   Admin peut la mettre à jour via `UPDATE parametres_litiges SET valeur = '...' WHERE cle = 'generate_invoice_url'`.
3. **Vault secret `service_role_key`** : à créer **manuellement** par Gabrielle dans
   Supabase Dashboard → *Project Settings* → *Vault* → *New Secret* :
   - **Name** : `service_role_key`
   - **Secret** : valeur de `SUPABASE_SERVICE_ROLE_KEY`
   La fonction `fn_trigger_regen_pdf_immediate` lit ce secret via
   `vault.decrypted_secrets`. Si absent : retour `NULL` (pas d'appel immédiat,
   le cron reprendra la main).

### Dégradation gracieuse

Si l'URL ou le secret manque, `fn_trigger_regen_pdf_immediate` retourne `NULL` silencieusement.
Le flag `pdf_a_regenerer=TRUE` reste posé ; le cron `litige-escalation-cron`
réémettra l'appel au prochain run (filtre 1h permet la fenêtre de retry pg_net).

### Observabilité

Chaque appel `net.http_post` retourne un `request_id BIGINT`. Les IDs sont
consignés dans le JSONB `details.regen_pdf_request_ids` de l'audit RGPD
(table `journal_audit`, action `LITIGE_RESOLU`).

Consultation du statut d'une requête pg_net :
```sql
SELECT * FROM net._http_response WHERE id = <request_id>;
```

## Rollback

En cas de problème en prod :
1. **Désactiver le schedule** dans Supabase Dashboard (ne pas supprimer la function).
2. **Ré-activer** après correction via la même interface.

La migration SQL ne rollback pas automatiquement : pour supprimer les RPCs, exécuter manuellement :

```sql
DROP FUNCTION IF EXISTS public.fn_alerter_mediation_prioritaire();
DROP FUNCTION IF EXISTS public.fn_envoyer_rappels_litiges();
DROP FUNCTION IF EXISTS public.fn_auto_creation_litiges_presence();
DROP FUNCTION IF EXISTS public.fn_litiges_escalader_auto();
DROP FUNCTION IF EXISTS public.fn_litige_push_notification(UUID, TEXT, TEXT, TEXT, TEXT, UUID, JSONB);
DROP FUNCTION IF EXISTS public.fn_list_admin_user_ids();
```
