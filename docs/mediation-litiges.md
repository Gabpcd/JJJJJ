# Médiation des litiges — Workflow Refonte.D.1 + E.1

Date : 2026-05-03 (Refonte.D.1, UI : Refonte.E.1, fix prod : Refonte.E.4)

## 1. Objectif

Avant Refonte.D : workflow simple **OUVERT → MEDIATION → FERME** (admin tranche dès l'ouverture s'il le souhaite).

Après Refonte.D : workflow **médiation amiable 7j** entre les parties avant escalade admin :
1. Ouverture litige (existant)
2. **Discussion 7 jours via messagerie litige**
3. **Médiation amiable** : une partie propose un accord
4. **Confirmation accord** : la 2e partie confirme → résolution sans pénalité scoring
5. **Si pas d'accord à J+7** : cron → `REVUE_ADMIN`
6. **Admin tranche** : `FAVEUR_SOIGNANT` / `FAVEUR_ETAB` / `PARTAGE` avec malus scoring approprié

## 2. Statuts (14 au total)

### Anciens statuts (conservés pour rétro-compat)

| Statut | Description |
|---|---|
| `OUVERT` | Litige ouvert, pas encore traité |
| `EN_DISCUSSION` | Échanges en cours via messagerie |
| `EN_MEDIATION` | Ancien statut "demande médiation" (legacy, déprécié) |
| `RESOLU_SOIGNANT` | Ancien : résolu en faveur soignant |
| `RESOLU_ETABLISSEMENT` | Ancien : résolu en faveur étab |
| `RESOLU_ADMIN` | Ancien : résolu admin sans détail |
| `FERME` | Fermé sans résolution explicite |

### Nouveaux statuts (Refonte.D.1)

| Statut | Description |
|---|---|
| `MEDIATION_EN_COURS` | Une partie a proposé un accord → fenêtre 7j |
| `RESOLU_ACCORD_PARTIES` | Les 2 parties ont confirmé → résolu amiablement (0 pénalité) |
| `REVUE_ADMIN` | Délai 7j expiré sans accord → admin doit trancher |
| `RESOLU_FAVEUR_SOIGNANT` | Admin a tranché en faveur soignant (pénalité étab) |
| `RESOLU_FAVEUR_ETAB` | Admin a tranché en faveur étab (pénalité soignant) |
| `RESOLU_PARTAGE` | Admin a tranché : décision partagée (0 pénalité) |

### Mapping anciens vs nouveaux

| Ancien | Équivalent nouveau | Migration auto ? |
|---|---|---|
| `EN_MEDIATION` | (ne plus émettre) | Non — anciens conservés tels quels |
| `RESOLU_SOIGNANT` | `RESOLU_FAVEUR_SOIGNANT` | Non — historique conservé |
| `RESOLU_ETABLISSEMENT` | `RESOLU_FAVEUR_ETAB` | Non |
| `RESOLU_ADMIN` | `RESOLU_PARTAGE` | Non |

Le code UI (`statutBadgeV2` dans `src/lib/statutLitige.ts`) gère les 14 statuts en 5 groupes sémantiques : `OUVERT`, `MEDIATION`, `ACTION_ATTENDUE`, `RESOLU_ACCORD`, `RESOLU_DECISION`, `FERME`.

## 3. RPCs nouveaux (Refonte.D.1)

### `fn_proposer_accord_partie(p_litige_id)`

- Auth : soignant OU étab partie au litige
- Vérifie statut ∈ `(OUVERT, EN_DISCUSSION, EN_MEDIATION)` (sinon : "déjà en médiation ou résolu")
- Bascule statut → `MEDIATION_EN_COURS`
- Audit `MEDIATION_OUVERTE`
- Notifie l'autre partie (`LITIGE_MEDIATION` "Médiation litige proposée. Vous avez 7 jours...")

### `fn_confirmer_accord_partie(p_litige_id)`

- Auth : soignant OU étab partie au litige (ou admin)
- Vérifie statut ∈ `(OUVERT, EN_DISCUSSION, EN_MEDIATION, MEDIATION_EN_COURS)`
- Set `accord_soignant_le = NOW()` ou `accord_etablissement_le = NOW()` selon partie
- **Trigger `trg_litige_accord_mutuel`** sur la table `litiges` :
  - Si les 2 timestamps sont set ET statut ∈ médiation → bascule auto à `RESOLU_ACCORD_PARTIES` + `resolu_le = NOW()`
- Audit `MEDIATION_ACCORD_PARTIES` + détails sur la partie ayant confirmé
- Si résolu → 2 notifications "Litige résolu par accord mutuel. Aucune pénalité scoring."

### `fn_admin_trancher_litige(p_litige_id, p_decision, p_motif?)`

- Auth : `est_admin()` uniquement (sinon "Seul l'administrateur peut trancher")
- `p_decision` ∈ `('FAVEUR_SOIGNANT', 'FAVEUR_ETAB', 'PARTAGE')`
- Bascule statut → `RESOLU_FAVEUR_*` ou `RESOLU_PARTAGE`
- Set `resolution = p_motif` (visible aux 2 parties), `resolu_par = uid`, `resolu_le = NOW()`
- 2 notifications : titre adapté selon décision (faveur perçue par chaque partie)
- Audit `LITIGE_ADMIN_TRANCHE` (action ajoutée par migration `20260429430000_refonte_e_4_fix_litige_admin_tranche.sql` — bug fix prod-critique trouvé en E2E)

### `fn_basculer_litiges_revue_admin_timeout()` — cron

- Auth : `est_admin()` OU `service_role` (cron)
- SELECT litiges `MEDIATION_EN_COURS` AVEC `cree_le < NOW() - 7 days` ET au moins un accord_le manquant
- Bascule chacun → `REVUE_ADMIN`
- 2 notifications "Litige basculé en revue admin. Un administrateur va trancher."
- Audit `MEDIATION_REVUE_ADMIN_DEMANDEE` avec raison `timeout_7_jours_sans_accord`
- Retourne `{success: true, count: N}`

## 4. Cron 7j (intégration email-cron-daily)

`supabase/functions/email-cron/index.ts` (Refonte.E.2) inclut désormais :

```typescript
const { data: medRes } = await sb.rpc('fn_basculer_litiges_revue_admin_timeout');
results.litiges_basculer_revue_admin = (medRes as any)?.count ?? 0;
```

Schedule : 1×/jour 6h UTC (existant).

## 5. Pénalités scoring selon résolution

| Statut final | Malus soignant | Malus étab |
|---|---|---|
| `RESOLU_ACCORD_PARTIES` | **0** (accord mutuel) | **0** |
| `RESOLU_FAVEUR_SOIGNANT` | 0 | -10 (soignant favorisé → étab pénalisé) |
| `RESOLU_FAVEUR_ETAB` | -10 | 0 |
| `RESOLU_PARTAGE` | 0 | 0 (décision partagée → pas de pénalité) |
| `RESOLU_ETABLISSEMENT` (ancien) | -10 | 0 |
| `RESOLU_SOIGNANT` (ancien) | 0 | -10 |
| `RESOLU_ADMIN` (ancien) | 0 | 0 |
| `FERME` (ancien) | 0 | 0 |

Détail dans `fn_calculer_score_fiabilite_v2` :

```sql
SELECT LEAST(2, COUNT(*)) * 10
FROM litiges
WHERE soignant_id = p_soignant_id
  AND statut IN ('RESOLU_ETABLISSEMENT', 'RESOLU_FAVEUR_ETAB')
  AND COALESCE(resolu_le, NOW()) >= v_since;
```

Cap : -20 (max 2 litiges sur 12 mois).

## 6. UI (Refonte.E.1)

### Composants partagés (`src/components/litige/`)

| Composant | Rôle |
|---|---|
| `TimelineLitige.tsx` | 4 étapes (Ouvert → Discussion → Médiation → Résolution), badge "(admin)" si décision admin vs accord mutuel |
| `CompteARebours7j.tsx` | Live countdown (refresh 60s), urgent <24h, "Délai expiré" si négatif |
| `BoutonsActionLitige.tsx` | Actions selon état + role : Proposer médiation / Confirmer accord (soignant/etab) ou Trancher (admin) |

### Helper (`src/lib/statutLitige.ts`)

```typescript
statutBadgeV2(statut) → { label, icon, classes, groupe }
estResolu(statut) → boolean
peutProposerMediation(statut) → boolean
peutConfirmerAccord(statut) → boolean
heuresRestantes7j(creeLe) → number  // négatif si expiré
```

### Pages

- `/soignant/litiges` (`LitigesSoignant.tsx`) — Liste + filtres groupes + Timeline + countdown + actions
- `/etablissement/litiges` (`LitigesEtablissement.tsx`) — Idem côté étab
- `/admin/litiges` (`AdminLitiges.tsx`) — **Nouvelle page** : focus REVUE_ADMIN, filtres "À trancher / En médiation / Tous ouverts", radio décision + motif min 50 chars

## 7. Tests E2E (Refonte.E.4)

| # | Scénario | Résultat |
|---|---|---|
| S11 | Cron 7j MEDIATION_EN_COURS → REVUE_ADMIN | ✅ statut bascule + audit + 2 notifs |
| S18 | 2 accords → trigger bascule auto RESOLU_ACCORD_PARTIES, 0 pénalité | ✅ |
| S19 | Admin tranche RESOLU_FAVEUR_ETAB + malus -10 | ✅ après fix migration |

**Bug prod-critique trouvé en S19** : `fn_admin_trancher_litige` utilisait `p_action='MISSION_LITIGE'` non présent dans `journaux_audit_action_check`. Fix dans `20260429430000_refonte_e_4_fix_litige_admin_tranche.sql` :
1. Ajout action `LITIGE_ADMIN_TRANCHE` au check constraint
2. Patch RPC pour utiliser cette action

## 8. Notes tech-debt

| Item | Priorité | Cible |
|---|---|---|
| **Suppression statuts legacy** : `EN_MEDIATION`, `RESOLU_SOIGNANT`, `RESOLU_ETABLISSEMENT`, `RESOLU_ADMIN`. À retirer du `litiges_statut_check` après migration des litiges historiques. | P3 | Novembre 2026 |
| **Modération messages litige** : pas encore d'outil admin pour masquer un message inapproprié dans `messages_litige`. | P2 | Q3 2026 |
| **RPC fn_demander_mediation_litige + fn_cloturer_litige (legacy)** : ces RPCs anciennes existent encore. Plus appelées par UI Refonte.E.1, mais conservées pour rétro-compat. À supprimer dans 6 mois. | P3 | Novembre 2026 |
| **Email admin "litige basculé revue"** : actuellement seules les parties sont notifiées. Pas d'email à l'admin. À ajouter si besoin. | P2 | Selon usage |
