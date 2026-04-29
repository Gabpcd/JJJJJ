# Module facturation hebdomadaire libérale — Partie 2

Date : 29 avril 2026

## Décisions produit

| # | Décision |
|---|---|
| D1 | Semaines ISO 8601 (lundi-dimanche) |
| D2 | Stratégie hybride : ≤ 7j → finale unique, > 7j → hebdo + finale |
| D3 | Cron quotidien 6h Europe/Paris |
| D4 | Stripe Connect : split auto par facture |
| D5 | Mandat v1.2 avec mention hebdo, re-signature au prochain login |
| D6 | Commission Jolene : par facture (avec Connect) |
| D7 | Salarié CDDU inchangé (bulletin de paie, pas facture) |
| D8 | Stratégie figée à l'assignation (colonne missions.strategie_facturation enum) |
| D9 | Garde-fou absence : pointage existant → plancher prévisionnel ; ni l'un ni l'autre → skip |
| D10 | Defacto opt-in global (soignants.defacto_opt_in) : auto-cession à passage EMISE |
| D11 | Statut intermédiaire EN_GENERATION → EMISE (ou ERREUR_GENERATION après 3 retries) |

## Architecture

### Schema DB (migration `20260429090000_partie2_fondations_facturation_hebdo.sql`)

**factures_honoraires** — colonnes ajoutées :
- `periode_debut date NOT NULL` — début période facturée
- `periode_fin date NOT NULL` — fin période facturée (inclusive)
- `numero_semaine_iso smallint` — semaine ISO (1-53), NULL pour finale unique
- `annee_iso smallint` — année ISO, NULL pour finale unique
- `est_facture_finale_mission boolean NOT NULL DEFAULT true` — false pour hebdo intermédiaire
- `facture_precedente_id uuid` — chaînage hebdo (existait déjà)
- Statuts ajoutés : `EN_GENERATION`, `ERREUR_GENERATION`

**missions** — colonne ajoutée :
- `strategie_facturation strategie_facturation NOT NULL DEFAULT 'FINALE_UNIQUE'`
  - Enum : `FINALE_UNIQUE` / `HEBDO_ET_FINALE`
  - Figée par `fn_geler_mission_a_assignation` au passage OUVERTE → ASSIGNEE
  - Calcul : `(fin_le::date - debut_le::date) > 7` → `HEBDO_ET_FINALE`

**soignants** — colonne ajoutée :
- `defacto_opt_in boolean NOT NULL DEFAULT false`

**Index** :
- `idx_fh_mission_periode_fin (mission_id, periode_fin DESC)`
- `idx_fh_soignant_iso (soignant_id, annee_iso, numero_semaine_iso) WHERE annee_iso IS NOT NULL`
- `idx_missions_statut_fin_le (statut, fin_le) WHERE statut IN ('EN_COURS','TERMINEE','ASSIGNEE')`

**Contrainte unique partielle** (anti-doublon hebdo) :
- `uniq_fh_mission_semaine_active (mission_id, annee_iso, numero_semaine_iso, type_document)`
  `WHERE est_facture_finale_mission = false AND statut NOT IN ('ANNULEE','REMPLACEE','ERREUR_GENERATION')`

### RPC SQL

| Fonction | Rôle |
|---|---|
| `fn_lister_missions_a_facturer(p_today date)` | Liste JSONB {finales[], hebdo[], total} des missions à facturer pour le jour donné. Mode FINALE pour missions TERMINEE non facturées LIBERAL. Mode HEBDO pour HEBDO_ET_FINALE avec semaines ISO closes. Skip ABSENCE/SALARIE/sans mandat/sans pointage. |
| `fn_verifier_pre_facturation(mission_id, p_periode_debut?, p_periode_fin?)` | Garde-fou pré-facturation. Étendu pour vérifier sur période (créneaux ouverts, écart > 10%, aucun créneau). Retourne source ∈ {EFFECTIF, PREVISIONNEL_PLANCHER, PREVISIONNEL}. |
| `fn_calculer_montant_periode(mission_id, p_periode_debut?, p_periode_fin?)` | Montant HT pondéré : total × (durée_période / durée_totale). |
| `fn_cumul_factures_mission(mission_id, p_jusqu_au?)` | Cumul HT/TTC des factures non-annulées jusqu'à date. |

### Triggers

| Trigger | Table | Événement | Fonction |
|---|---|---|---|
| `trg_zz_geler_mission` | missions | BEFORE UPDATE | Fige `strategie_facturation` au passage OUVERTE → ASSIGNEE |
| `trg_defacto_auto_cession` | factures_honoraires | AFTER UPDATE OF statut | Si EMISE + defacto_opt_in → INSERT cessions_creance auto |

### Edge functions

| Fonction | Auth | Rôle |
|---|---|---|
| `generate-invoice` (modifié) | JWT ou service_role | Accepte `periode_debut`, `periode_fin`, `numero_semaine_iso`, `annee_iso`, `est_facture_finale_mission` en input. Statut EN_GENERATION → EMISE après upload, ou ERREUR_GENERATION si échec. Mention cumul mission dans le PDF. |
| `weekly-invoicing-cron` (nouveau) | service_role only | Appelle fn_lister_missions_a_facturer puis generate-invoice par mission. 3 retries max. Idempotent. Audit admin si échec définitif. |

## Workflow facturation

### Mission ≤ 7 jours (FINALE_UNIQUE)

1. Mission TERMINEE (le soignant a pointé, l'étab a validé)
2. Cron 6h : `fn_lister_missions_a_facturer` retourne la mission en mode FINALE
3. Cron appelle `generate-invoice(mission_id)` (sans période → facture mission entière)
4. Facture EMISE (est_facture_finale_mission=true)
5. Si defacto_opt_in → trigger auto-cession Defacto

### Mission > 7 jours (HEBDO_ET_FINALE)

1. Mission EN_COURS, semaine S1 close (dimanche < today)
2. Cron 6h : `fn_lister_missions_a_facturer` retourne la mission en mode HEBDO pour S1
3. Cron appelle `generate-invoice(mission_id, periode_debut=lundi_S1, periode_fin=dimanche_S1, numero_semaine_iso, annee_iso, est_facture_finale_mission=false)`
4. Facture EMISE pour S1 (est_facture_finale_mission=false)
5. Si defacto_opt_in → auto-cession Defacto
6. S2 close → même cycle
7. Mission TERMINEE milieu S3 → cron retourne en mode FINALE pour la période restante S3
8. Facture finale partielle EMISE (est_facture_finale_mission=true, periode_debut=lundi_S3, periode_fin=fin_mission)

## T9 vrai débloqué

La version intermédiaire T9 (livrée le 28/04) offrait 3 scopes de gel : MISSION_ENTIERE, FACTURE_UNIQUE, AUCUN. Avec Partie 2, une 4ème valeur est ajoutée :

- **PERIODE_LITIGIEUSE** : le litige porte sur une période donnée (litiges.periode_debut / periode_fin). Seules les factures dont `[periode_debut, periode_fin]` chevauche la période litigieuse sont gelées. Les autres factures de la mission continuent normalement.

Exemple : mission 3 semaines, litige sur S2 uniquement. Seule la facture S2 est gelée. S1 et S3 sont payées normalement.

## Mandat v1.2

Article 2 enrichi : mention facturation hebdomadaire selon durée de mission.
Version bumped 1.1 → 1.2, date 29 avril 2026.

Bandeau re-signature : les soignants ayant signé v1.1 voient un bandeau warning "Mandat mis à jour — re-signature requise" avec le formulaire de signature en dessous.

## Defacto opt-in

- Colonne `soignants.defacto_opt_in` (boolean, default false)
- UI toggle dans le bloc "Paie et facturation" du profil soignant (LIBERAL/MIXTE)
- Trigger `trg_defacto_auto_cession` : à chaque passage statut → EMISE, si opt_in=true → INSERT automatique dans `cessions_creance` + `factor_assigned=true`
- Le webhook `factor-webhook` continue de gérer les mises à jour de statut Defacto

## Actions manuelles Gabrielle

1. **Scheduling cron** dans dashboard Supabase → Database → Cron :
   ```sql
   SELECT cron.schedule('weekly_invoicing', '0 4 * * *',
     $$SELECT net.http_post(
       url := 'https://flripxtsyegjshnhzjkz.supabase.co/functions/v1/weekly-invoicing-cron',
       headers := '{"Authorization": "Bearer <SERVICE_ROLE_KEY>"}'::jsonb
     )$$);
   ```
   (4h UTC = 6h Europe/Paris)

2. **Redéployer generate-invoice** via dashboard Supabase → Edge Functions → generate-invoice → Deploy (le code source est à jour sur main dans `supabase/functions/generate-invoice/index.ts`).

## Tests

Tests SQL exécutés via BEGIN + `session_replication_role=replica` + ROLLBACK.

| # | Test | Résultat |
|---|---|---|
| 1 | Mission 5j TERMINEE LIBERAL → FINALE mode dans fn_lister | ✓ |
| 2 | Mission 14j EN_COURS HEBDO_ET_FINALE → 2 HEBDO dans fn_lister | ✓ |
| 3 | Mission EN_COURS FINALE_UNIQUE → skip | ✓ |
| 4 | Mission ABSENCE → skip | ✓ |
| 5 | Mission SALARIE → skip | ✓ |
| 6 | Mission sans créneau → skip (D9) | ✓ |
| 7 | fn_verifier_pre_facturation avec période → durées correctes | ✓ |
| 8 | fn_calculer_montant_periode S15 de 14j → 50% du total | ✓ |
| 9 | Doublon hebdo INSERT → contrainte unique partielle bloque | ✓ |
| 10 | Logique CASE stratégie : 0j→FINALE, 7j→FINALE, 8j→HEBDO, 14j→HEBDO | ✓ |
