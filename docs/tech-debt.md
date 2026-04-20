# Tech-debt consolidé — Jolene

**Dernière mise à jour** : 2026-04-20

## Contexte

Ce document centralise toute la dette technique identifiée sur Jolene à date, priorisée par impact et rattachée à une Sub-PR cible. Il remplace le précédent `tech-debt.md` (21 tickets épars) en consolidant :

- Les 21 tickets hérités (CP4, CP5a, CP5b, Sub-PR 2bis, T1→T15).
- Les fixes bonus et tickets résolus en **Sub-PR 2 quater** (T18, T19, T20, FIX 18 regen PDF immédiat, FIX bonus auto-création B/C + NULL values).
- Les **Audits 1→7** menés pendant la recette CP-LITIGES : (1) Crons, (2) Objets fantômes SQL / `types.ts`, (3) Templates email, (4) Flow paiement salarié, (5) Scoring soignant, (6) Statuts factures `REMPLACEE`, (7) Stripe Connect.
- **Audit 8 (RLS consolidation)** : en attente, sera intégré dans une version v2 du document.
- Les découvertes de migrations (orphan `20260417102123`, cohabitation signatures 5/6-arg `fn_admin_resoudre_litige`, 2/3-arg `fn_ouvrir_litige_rate_limited`, bug `gen_random_bytes`, trigger restrictif `fn_auto_code_parrainage`).
- Les findings smoke tests post-migration (18/21 PASS, 3 FAIL design : `FACTURE_COMPLEMENTAIRE` différé, colonnes `ajuster_*` absentes par design, `annulee_pour_litige_id` absent par design).

Sub-PR 2 quater est **mergée en prod** (29 migrations appliquées, zéro régression). Les tickets résolus sont conservés en fin de document pour traçabilité.

## Légende statuts

- 🔴 **OUVERT** — à traiter, non démarré
- 🟡 **EN COURS** — Sub-PR ouverte ou planifiée dans le sprint courant
- 🟢 **RÉSOLU** — traité et mergé en prod (conservé pour historique + lien migration)
- ⚪ **DIFFÉRÉ** — volontairement reporté post-lancement beta avec justification (retours terrain, métriques à collecter, dépendance externe)

## Légende priorités

- **P0** — Bloquant go-live public / sécurité / conformité RGPD
- **P1** — Bloquant sortie beta / acceptation clients multi-étabs
- **P2** — Amélioration notable, non bloquante
- **DIFFÉRÉ** — Dépend d'un module futur (Partie 2 litiges hebdo, planning, etc.)

## Statistiques globales (estimatif — à affiner section par section)

| Priorité              | Tickets | Sub-PR cible principale                     |
| --------------------- | ------- | ------------------------------------------- |
| 🔴 P0                 | ~10     | SP-stripe-connect-prod, SP-bugs-latents, SP-RLS (Audit 8) |
| 🟡 P1                 | ~14     | SP-templates-cablage, SP-paiement-salarie, SP-scoring-refonte, SP-crons-fixes |
| 🟢 P2                 | ~10     | SP-nettoyage-versions-rpcs, SP-phantom-objects-audit, SP-statuts-factures-remplacee |
| ⚪ DIFFÉRÉ            | ~6      | Partie 2 litiges hebdo, modules futurs      |
| ✅ RÉSOLU (Sub-PR 2q) | 4       | T18 / T19 / T20 / FIX 18 regen PDF immédiat |

**Sub-PR prévues** : **9** (crons-fixes, templates-cablage, statuts-factures-remplacee, paiement-salarie-refonte, scoring-refonte, stripe-connect-prod-ready, bugs-latents, RLS-consolidation après Audit 8, nettoyage-versions-rpcs) + intégration Sub-PR 3 (core consolidation) et Partie 2 (litiges hebdo).

**Estimation totale de travail** : **~12-16 semaines** ingénieur (hors validation juridique T1). Répartition indicative :
- P0 critique prod (Stripe Connect + bugs latents + RLS Audit 8) : ~4-5 semaines
- P1 refontes majeures (paiement salarié + scoring + templates) : ~5-6 semaines
- P2 nettoyage + audits (phantom objects + RPCs + statuts) : ~2-3 semaines
- DIFFÉRÉ Partie 2 litiges hebdo : hors scope (sprint dédié)
