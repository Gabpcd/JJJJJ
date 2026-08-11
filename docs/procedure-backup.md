# Procédure de backup et reprise — Jolene

Date : 28 avril 2026

## Backups Supabase (managé)

Supabase Pro tier : **PITR (Point-In-Time Recovery)** activé par défaut.

### Configuration actuelle (à confirmer dashboard)

| Paramètre | Valeur Pro tier |
|---|---|
| Backup quotidien | Oui, automatique 00:00 UTC |
| Rétention | 7 jours (Pro) ou 30 jours (Team) |
| PITR | 7 jours (Pro), résolution seconde |
| Région | Irlande (eu-west-1) |
| Chiffrement at rest | AES-256 (RDS-géré) |

### Action manuelle Gabrielle

1. Dashboard Supabase → Project Settings → **Backups**
2. Confirmer que la formule est **Pro** (≥ 25 $/mois) — sinon les backups sont
   limités à 7 jours en Free tier ou inexistants.
3. Confirmer **PITR enabled** dans Settings → Add-ons.
4. Tester un point-in-time recovery (PITR) sur un projet **clone/staging**
   trimestriellement (procédure : `Settings → Backups → Restore to new project`).

## RPO / RTO

| Métrique | Cible | Justification |
|---|---|---|
| **RPO** (Recovery Point Objective) | 5 minutes | PITR Supabase Pro, granularité seconde mais 5 min en pratique pour les WAL log shipping |
| **RTO** (Recovery Time Objective) | 4 heures | Restore Supabase + redéploiement edge functions + tests fumée |

## Procédure de recovery — perte totale base

1. **T+0** : alerte Sentry / monitoring détecte indisponibilité.
2. **T+15 min** : Gabrielle confirme l'incident, contacte support Supabase
   (chat dashboard, escalade priorité).
3. **T+30 min** : décision restore depuis backup (point dans le temps choisi
   AVANT l'incident, idéalement < 24h).
4. **T+60 min** : Supabase procède au restore. Le projet repart avec un nouvel
   ID (anciennes URL réécrites).
5. **T+90 min** : Gabrielle pointe le DNS Vercel sur le nouveau projet
   (mise à jour `VITE_SUPABASE_URL` et `VITE_SUPABASE_ANON_KEY`).
6. **T+120 min** : redéploiement Vercel (auto-trigger après update env).
7. **T+180 min** : tests fumée (login, création mission, génération facture,
   upload document) avec 1 compte audit-* par rôle.
8. **T+240 min** : annonce utilisateurs (banner in-app + email Resend).

## Procédure de recovery — corruption partielle

Cas : table `factures_honoraires` corrompue par migration accidentelle.

1. Identifier le timestamp T0 avant corruption.
2. Restaurer un **clone temporaire** du projet à T0 (Supabase: Branches feature).
3. Connecter en service_role.
4. Comparer les diffs sur la table impactée :
   ```sql
   -- côté clone
   COPY (SELECT * FROM factures_honoraires WHERE cree_le >= T0) TO '/tmp/diff.csv';
   ```
5. Importer côté prod :
   ```sql
   -- côté prod, dans une transaction
   BEGIN;
   COPY tmp_restore FROM '/tmp/diff.csv';
   -- merge logique
   ROLLBACK; -- ou COMMIT après validation
   ```
6. Audit `journaux_audit` : enregistrer l'opération avec action `ADMIN_ACTION`
   et raison.

## Backups complémentaires

### Storage (S3-compatible Supabase)

- Bucket `jolene-documents` (PDF factures, documents soignants, mandats).
- **Réplication** : pas de réplication automatique. Pour pilotes, configurer
  un cron `rclone` mensuel vers un bucket S3 de secours (action manuelle Gabrielle).
- **Critique** : les factures de soignants LIBERAL (preuves fiscales) sont
  également régénérables depuis `factures_honoraires` (XML Factur-X immutable
  + numéro séquentiel) → la perte d'un PDF n'est pas catastrophique tant que
  la row DB est intacte.

### Edge functions

- Toutes versionnées dans `supabase/functions/` (git).
- Re-déploiement via MCP `deploy_edge_function` ou CLI `supabase functions deploy`.

### Secrets Supabase

| Secret | Source | Comment recréer |
|---|---|---|
| `STRIPE_SECRET_KEY` | Stripe dashboard | Régénérer + redéployer |
| `RESEND_API_KEY` | Resend dashboard | Régénérer |
| `TWILIO_AUTH_TOKEN` | Twilio dashboard | Régénérer |
| `TURNSTILE_SECRET_KEY` | Cloudflare dashboard | Régénérer |
| `YOUSIGN_API_KEY` | YouSign dashboard | Régénérer |
| `DEFACTO_API_KEY` | Defacto dashboard | Régénérer |
| `CHORUS_PISTE_KEY` | PISTE dashboard | Régénérer |
| `ADMIN_INVOKE_SALT` | n'importe quelle phrase | Recréer + invalider tous les hash X-Admin-Confirm |
| `OPS_TEST_ADMIN_PASSWORD` | mot de passe fort 20+ chars | Recréer + UPDATE auth.users |

⚠️ Ces secrets ne sont pas backupés Supabase. Tenir un coffre 1Password
partagé entre Gabrielle et le co-fondateur technique.

## Tests de recovery (planning)

| Fréquence | Action | Owner |
|---|---|---|
| Trimestriel | Restore PITR sur clone, vérification 10 tables critiques | Gabrielle |
| Annuel | Drill complet : simulation perte projet, restore + DNS + tests fumée < 4h | Gabrielle + co-fondateur |
| Avant pilotes | Confirmer Pro tier + PITR activé + premier test PITR | Gabrielle (avant ouverture) |

## Cron de purge / anonymisation

Pour cohérence avec la politique de rétention (`docs/retention-policy.md`),
configurer dans dashboard Supabase → Database → Cron :

```sql
-- Hebdomadaire : purge admin_invocations selon catégorie
SELECT cron.schedule('purge_admin_invocations', '0 3 * * 0',
  $$SELECT public.fn_admin_invocations_purge();$$);

-- Hebdomadaire : anonymisation GPS > 90 jours
SELECT cron.schedule('anonymiser_gps', '0 4 * * 0',
  $$SELECT public.fn_anonymiser_gps_anciennes();$$);

-- Mensuel : purge comptes inactifs > 2 ans
SELECT cron.schedule('purge_inactifs', '0 5 1 * *',
  $$SELECT public.fn_rgpd_purge_automatique_inactifs();$$);
```

## Contacts urgence

- **Supabase Support** : dashboard chat (Pro tier = SLA 24h, Team = 4h).
- **Vercel Support** : dashboard chat (Pro tier).
- **Stripe Support** : 24/7 dashboard.
- **DPO Jolene** : dpo@jolene.app (Gabrielle).
