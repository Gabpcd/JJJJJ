# Sub-PR 2 quater — Récapitulatif CP-LITIGES

**Branche** : `claude/fix-merge-conflicts-2Y4ph`
**Période** : 2026-04-17 → 2026-04-20
**Scope** : livrer la Partie 1 (litiges sur missions ponctuelles) de CP-LITIGES : migrations 1→7b appliquées, durcies par FIX 1→19 + FIX T18/T19/T20 + FIX bonus, et couvertes par 17 scénarios end-to-end (CP8a T1→T7, CP8b T8→T17) + 3 tests dédiés aux fixes découverts pendant la recette.

---

## 1. Vue d'ensemble

CP-LITIGES Partie 1 concerne tout le cycle de vie d'un litige sur mission **ponctuelle** (non hebdomadaire) :

- Ouverture (rate-limitée, fenêtres de contestation F1/F2/F3 selon type et statut facture).
- Auto-création côté plateforme (présence ABSENT validée étab + > 48h sans litige).
- Gel des factures liées (granulaire pour les litiges FINANCIER ciblés sur une facture_id, mission-wide pour PRESENCE / CONDITIONS / COMPORTEMENT).
- Notifications asynchrones (push + email) pour les 2 parties + admin.
- Escalade automatique (72h libéral / 5 jours ouvrés salarié, avec respect jours fériés FR).
- Clôture amiable bilatérale (soignant + étab) → `RESOLU` sans passage admin.
- Résolution admin (`fn_admin_resoudre_litige`) : recalcul BROUILLON, annulation/réémission EMISE, AVOIR pour PAYEE, avec regen PDF immédiat via `pg_net.http_post` (fire-and-forget) et filet de sécurité cron.
- Recalcul de la commission plateforme post-litige (flag `commission_a_recalculer` + cron → AVOIR commission si delta).

Tout est piloté par une edge function quotidienne `litige-escalation-cron` (squelette `process-stripe-refunds` livré à part pour T13 futur).

---

## 2. Checkpoints livrés

### CP-LITIGES core (1 → 7b)

| CP    | Migration                                                     | Objet principal                                                         |
| ----- | ------------------------------------------------------------- | ----------------------------------------------------------------------- |
| 1     | `20260417130000_cp_litiges_1_ddl.sql`                         | Tables `litiges`, `litiges_messages`, enums, index, RLS.                |
| 2     | `20260417130100_cp_litiges_2_triggers_rpcs.sql`               | Triggers (gel facture, auto-création) + RPCs ouverture / clôture.        |
| 2-A   | `20260417130200_cp_litiges_2_fixes.sql`                       | Seeds `parametres_litiges`, rename `rate_limit_litiges_par_heure`.       |
| 3     | `20260417130300_cp_litiges_3_resolution_avoirs.sql`           | `fn_admin_resoudre_litige`, AVOIR Stripe / virement manuel.              |
| 4     | `20260417130400_cp_litiges_4_cron.sql`                        | RPCs cron : escalade, rappels, alerte médiation.                         |
| 5     | `20260417130500_cp_litiges_5_sms_extension.sql`               | Extension SMS optionnelle pour rappels critiques.                        |
| 6     | `20260417130600_cp_litiges_6_avoir_support.sql`               | Colonnes support AVOIR (`facture_precedente_id`, type_document, etc.).  |
| 7a    | 10 migrations `20260417130701..713` (FIX 1→15, hors 13/14)    | Durcissement RPCs, audit, timezone, pg_net regen PDF (FIX 18).           |
| 7b    | `20260417130717_cp7b1_rpcs_admin.sql` + `..718_cp7b3_*`       | RPCs admin moderation + recategorisation litige.                         |
| bloc4 | `20260417130716_bloc4_commission_ajustee_push.sql`            | Push `COMMISSION_AJUSTEE` après recalcul commission.                     |

### FIX bonus (découverts pendant la recette CP8)

| Fix                         | Migration                                                         | Motif                                                                                          |
| --------------------------- | ----------------------------------------------------------------- | ---------------------------------------------------------------------------------------------- |
| **T18 — fenêtre financier** | `20260417130721_fix_t18_fenetre_financier_facture_lookup.sql`     | F2/F3 ineffectives : `p_facture_id=NULL` toujours passé → lookup `factures_honoraires` ajouté. |
| **T19 — type_contrat**      | `20260417130722_fix_t19_escalade_type_contrat_applique.sql`       | Escalade + fenêtre utilisaient le flag global soignant → lecture `missions.type_contrat_applique`. |
| **T20 — audit clôture**     | `20260417130723_fix_t20_audit_cloture_amiable.sql`                | `fn_cloturer_litige_mutuel` ne loguait aucun `LITIGE_ACCORD_MUTUEL` / `LITIGE_CLOTURE_MUTUEL`. |
| **FIX bonus auto B/C**      | `20260417130719_fix_bonus_auto_creation_cas_b_c.sql`              | `fn_auto_creation_litiges_presence` ne couvrait que le cas A (ABSENT) → cas B (départ anticipé) + C (retard important) ajoutés. |
| **FIX bonus NULL values**   | `20260417130720_fix_bonus_resolution_null_values.sql`             | `fn_admin_resoudre_litige` crashait si `p_ajuster_heures`/`p_ajuster_taux` NULL → fallback sur valeurs d'origine. |

---

## 3. Tests livrés (CP8a + CP8b)

Tous les tests sont idempotents (`BEGIN … ROLLBACK`), isolés (`gen_random_uuid`), et documentent leur scénario en en-tête. Règle : 1 test par fichier, < 100 lignes (exceptions T5 < 120, T16 < 120).

### CP8a — Résolution + AVOIR (7 tests)

| Test | Fichier                                                  | Scénario                                                         |
| ---- | -------------------------------------------------------- | ----------------------------------------------------------------- |
| T1   | `cp8a-t1-absence-soignant.test.sql`                      | Auto-création ABSENCE_SOIGNANT à partir d'une présence ABSENT >48h. |
| T2   | `cp8a-t2-depart-anticipe.test.sql`                       | Auto-création cas B (départ anticipé > seuil).                    |
| T3   | `cp8a-t3-desaccord-heures.test.sql`                      | Flow manuel soignant DESACCORD_HEURES_POINTAGE.                    |
| T4   | `cp8a-t4-retard-important.test.sql`                      | Auto-création cas C (retard > seuil) initié étab.                  |
| T5   | `cp8a-t5-avoir-stripe-auto.test.sql`                     | Facture PAYEE < 120j → AVOIR Stripe auto, queue alimentée.         |
| T6   | `cp8a-t6-avoir-virement-manuel.test.sql`                 | Facture PAYEE > 120j → AVOIR VIREMENT_MANUEL.                      |
| T7   | `cp8a-t7-hors-fenetre-bypass.test.sql`                   | Hors fenêtre + bypass admin `fn_admin_creer_litige_force`.         |

### CP8b — Extensions + résolution avancée (10 tests)

| Test | Fichier                                                | Scénario                                                               |
| ---- | ------------------------------------------------------ | ----------------------------------------------------------------------- |
| T8   | `cp8b-t8-securite-danger.test.sql`                     | SECURITE_DANGER à 4 mois (fenêtre toujours ouverte).                    |
| T9   | `cp8b-t9-comportement-informatif.test.sql`             | COMPORTEMENT à 7 mois (`est_informatif=TRUE`, pas de blocage).          |
| T10  | `cp8b-t10-escalade-liberal.test.sql`                   | Escalade auto libéral 72h → EN_MEDIATION.                               |
| T11  | `cp8b-t11-escalade-salarie-ferie.test.sql`             | Escalade auto salarié 5 j.o. (respect jours fériés FR).                 |
| T12  | `cp8b-t12-cloture-amiable.test.sql`                    | Accord mutuel soignant + étab → RESOLU, + 2 audits.                     |
| T13  | `cp8b-t13-double-litige.test.sql`                      | 2 litiges concurrents types distincts sur même mission.                 |
| T14  | `cp8b-t14-facture-hebdo-intermediaire.test.sql`        | Gel granulaire FINANCIER sur S1 uniquement, S2 reste NORMAL.            |
| T15  | `cp8b-t15-rate-limit.test.sql`                         | Rate limit 3/h → 4e litige refusé avec message normalisé.               |
| T16  | `cp8b-t16-commission-recalculer.test.sql`              | Recalcul commission post-AVOIR → AVOIR commission 7.50€.                |
| T17  | `cp8b-t17-regen-pdf-immediat.test.sql`                 | Résolution FINANCIER → `pg_net.http_post` + `regen_pdf_request_ids`.    |

### Tests des FIX bonus découverts

| Fichier                                                     | Cible                                         |
| ----------------------------------------------------------- | --------------------------------------------- |
| `fix-t18-fenetre-financier.test.sql`                        | 5 scénarios fenêtres F2/F3 libéral/salarié.    |
| `fix-t19-escalade-type-contrat.test.sql`                    | 3 scénarios `type_contrat_applique`.           |
| `fix-t20-audit-cloture.test.sql`                            | 2 scénarios audit accord / clôture mutuelle.   |
| `fix-bonus-auto-creation-b-c.test.sql`                      | Cas B (départ anticipé) + C (retard).          |
| `fix-bonus-resolution-null-values.test.sql`                 | NULL `p_ajuster_heures` / `p_ajuster_taux`.    |

Total : **17 tests end-to-end + 5 tests FIX bonus = 22 nouveaux fichiers** sous `tests/litiges/`, tous en format `psql -f`.

---

## 4. Tickets tech-debt (docs/tech-debt.md)

### Résolus pendant Sub-PR 2 quater

- **T18** — fenêtres F2/F3 ineffectives → `20260417130721` (RÉSOLU).
- **T19** — flag global soignant au lieu du contrat figé → `20260417130722` (RÉSOLU).
- **T20** — `fn_cloturer_litige_mutuel` sans audit RGPD → `20260417130723` (RÉSOLU).
- **pg_net regen PDF immédiat** — passage du cron-only au fire-and-forget → FIX 18 (RÉSOLU, cron conservé en filet).

### Restant après Sub-PR 2 quater

- **T9** — gel facture granulaire par période pour PRESENCE / CONDITIONS / COMPORTEMENT (bloque sur colonnes `periode_debut`/`periode_fin` à livrer en Partie 2).
- **T10** — rate limit 3/h vs 3/24h : arbitrage à valider avec Gabrielle avant sortie de beta.
- **T13** — `process-stripe-refunds` reste squelette (appel Stripe réel à câbler après T12 webhook).
- **stripe_payment_intent_id** — propagation depuis `stripe_transfers` vers `factures_honoraires` à faire (bloque l'AVOIR auto-Stripe pour les factures historiques).
- **RELANCE_FACTURE** — normaliser sur `RAPPEL_FACTURE` (bug silencieux résolu post-CP7a).

---

## 5. Actions manuelles Gabrielle (prod Jolene)

Prérequis avant mise en route du cron en prod, par ordre de priorité :

1. **[P0] Déployer `litige-escalation-cron`** — non déployée sur `flripxtsyegjshnhzjkz` (vérifié 2026-04-20) :
   ```bash
   supabase functions deploy litige-escalation-cron --project-ref flripxtsyegjshnhzjkz
   ```
2. **[P0] Créer le schedule cron** — option dashboard ou SQL (cf. `/docs/cron-litiges.md` § *Déploiement*). Recommandation : `0 8 * * *` UTC = 09h Paris hiver / 10h Paris été.
3. **[P1] Vault secret `service_role_key`** — requis pour le regen PDF immédiat (FIX 18) :
   - Dashboard → *Project Settings* → *Vault* → *New Secret* : nom `service_role_key`, valeur = `SUPABASE_SERVICE_ROLE_KEY`.
   - Dégradation gracieuse si absent : `fn_trigger_regen_pdf_immediate` retourne `NULL`, le cron reprendra la main à l'itération suivante.
4. **[P2] Déployer `process-stripe-refunds`** — squelette, non bloquant, à déployer sans schedule jusqu'à T13 :
   ```bash
   supabase functions deploy process-stripe-refunds --project-ref flripxtsyegjshnhzjkz
   ```
5. **[P2] Contrôler les paramètres** `parametres_litiges` en prod (valeurs par défaut seedées par CP-LITIGES-2-A) :
   - `rate_limit_litiges_par_heure = 3`
   - `delai_escalade_liberal_h = 72`
   - `delai_escalade_salarie_jours_ouvres = 5`
   - `delai_contestation_pointage_h = 48`
   - `delai_mediation_alerte_prioritaire_j = 7`
   - `generate_invoice_url` : valeur auto-seedée `https://<project-ref>.supabase.co/functions/v1/generate-invoice`.

---

## 6. Prochaines étapes

### Partie 2 — litiges hebdomadaires libéraux (hors scope Sub-PR 2 quater)

- Ajouter `periode_debut` / `periode_fin` sur `factures_honoraires` (unlock T9 — gel granulaire non-FINANCIER).
- Étendre `trg_litige_gel_degel_facture` pour accepter une période (via champ explicite sur `litiges` ou déduction présence).
- Tests end-to-end dédiés (gel par semaine uniquement, factures S1 / S2 / S3 indépendantes).

### Durcissements restants

- T13 (`process-stripe-refunds`) : câblage réel `stripe.refunds.create` + update queue/facture.
- Propagation `stripe_payment_intent_id` dans `stripe-connect-pay-mission`.
- Migration documentation `RAPPEL_FACTURE` ↔ `RELANCE_FACTURE` côté UI admin impayées.

### Observabilité / sortie de beta

- Dashboards Supabase Logs sur `litige-escalation-cron` (durée, compteurs par RPC).
- Alerting sur taux d'échec `pg_net` > X%.
- Post-mortem T10 rate limit 3/h vs 3/24h (métriques réels 30 jours).

---

## 7. Statistiques Sub-PR 2 quater

| Métrique                                                   | Valeur |
| ---------------------------------------------------------- | ------ |
| Migrations CP-LITIGES (1 → 7b + bloc4 + FIX bonus + FIX T) | 24     |
| RPCs `SECURITY DEFINER` introduites / modifiées            | 18     |
| Tables créées / étendues                                   | 4      |
| Tests SQL end-to-end (CP8a + CP8b)                         | 17     |
| Tests SQL fixes découverts                                 | 5      |
| Lignes de tests ajoutées                                   | ~1850  |
| Tickets tech-debt résolus (T18/T19/T20 + FIX 18)           | 4      |
| Tickets tech-debt restants liés aux litiges                | 5      |

---

**Statut final** : Sub-PR 2 quater prête à merger côté code et migrations. Activation prod conditionnée aux étapes P0 de la § 5 ci-dessus.
