# Module bulletin de paie SALARIE Jolene — art. R3243-1 CTW

Date : 2026-04-28

## Cadre légal

Pour les soignants en exercice **SALARIE** ou **MIXTE**, Jolene SAS génère
les bulletins de paie en lieu et place de l'établissement client. C'est
un différenciateur métier : Jolene s'occupe de la paie de bout en bout.

Articles applicables :
- **Art. R3243-1 CTW** : mentions obligatoires sur le bulletin (identité
  employeur + salarié, période, brut, cotisations détaillées, net, etc.).
- **Art. L3243-2 CTW** : remise du bulletin au salarié à chaque paie.
- **Art. L3243-4 CTW** : conservation 5 ans minimum par l'employeur (le
  salarié conserve indéfiniment).
- **Art. L1243-8 CTW** : IFM 10% pour CDDU.
- **Art. L3141-22 CTW** : ICP 10% pour CDDU.
- **Art. L3245-1 CTW** : prescription 3 ans pour réclamation salaire.

Pour les soignants **LIBERAL purs**, pas de bulletin : la rémunération
passe par le module facturation (cf. `docs/module-facturation.md`).

## Architecture

### Tables

| Table | Rôle |
|---|---|
| `cotisations_sociales` | Détail des montants par cotisation (CSG, CRDS, SS, retraite T1/T2, CEG, IFM, ICP, salariales, patronales). Une row par mission. **Pré-existant**. |
| `bulletins_paie` | Document bulletin avec numéro séquentiel immutable (`BP-{SIRET8}-{ANNEE}-{SEQ5}`), période, totaux dénormalisés, statut, lien Storage. **Cette session**. |

### RPC SQL

| Fonction | Rôle | Source |
|---|---|---|
| `fn_calculer_cotisations(p_mission_id)` | Calcul brut → net + cotisations détaillées + IFM/ICP. Peuple `cotisations_sociales`. | Pré-existant |
| `fn_next_bulletin_paie_number(p_soignant_id)` | Génère un numéro séquentiel `BP-{SIRET8}-{ANNEE}-{SEQ5}` avec advisory lock anti-collision. | Cette session |
| `fn_creer_bulletin_paie(p_mission_id)` | Idempotent. Vérifie mission TERMINEE + soignant non-LIBERAL, calcule cotisations si besoin, INSERT bulletin avec audit. | Cette session |
| `fn_mes_bulletins_paie()` | Liste bulletins du soignant connecté avec joins établissement + mission. | Cette session |

### Trigger automatique

**`trg_auto_creer_bulletin_paie`** sur `missions` AFTER UPDATE OF statut :
- Quand `statut` passe à `TERMINEE`,
- ET le soignant n'est pas LIBERAL,
- alors `fn_creer_bulletin_paie(NEW.id)` est appelé.

Best-effort : si la création échoue (mission incomplète, etc.), le passage
en TERMINEE n'est pas bloqué (RAISE WARNING + EXCEPTION WHEN OTHERS).

### Triggers d'immutabilité

- **`trg_bp_immutability`** (BEFORE UPDATE) : verrouille `numero_bulletin`,
  `salaire_brut`, `total_cotisations_salariales`, `net_avant_impot`,
  `periode_*`, `soignant_id`, `mission_id`, `etablissement_id`,
  `date_emission` quand `statut IN ('EMIS','PAYE')`. Bypass service_role
  + admin.
- **`trg_bp_no_delete`** (BEFORE DELETE) : RAISE EXCEPTION sauf
  service_role + admin.

### RLS

- `bp_select_own` : `soignant_id = auth.uid() OR etablissement_id =
  mon_etablissement_id() OR est_admin()`.
- Pas de policy INSERT/UPDATE/DELETE pour `authenticated` : seules les
  RPC `SECURITY DEFINER` peuvent écrire.
- GRANT SELECT sur la table + GRANT EXECUTE sur les RPC.

## Constantes cotisations 2026

Source unique côté DB : `fn_calculer_cotisations`. Réplique côté client
dans `src/lib/cotisations-2026.ts` pour affichage des taux dans le PDF.

| Cotisation | Assiette | Taux salarial | Taux patronal |
|---|---|---|---|
| PMSS 2026 | — | — | 3 864 € |
| CSG déductible | 98.25 % du brut | 6.80 % | — |
| CSG non déductible | 98.25 % du brut | 2.40 % | — |
| CRDS | 98.25 % du brut | 0.50 % | — |
| SS Vieillesse plafonnée | min(brut, PMSS) | 6.90 % | 6.01 % (retraite) |
| SS Vieillesse déplafonnée | brut total | 0.40 % | — |
| Retraite T1 (AGIRC-ARRCO) | min(brut, PMSS) | 3.86 % | 6.01 % |
| Retraite T2 | brut – PMSS (si > 0) | 10.21 % | — |
| CEG | min(brut, PMSS) | 0.86 % | — |
| SS maladie | brut | 0 % (depuis 2018) | 13.05 % |
| Allocations familiales | brut | — | 5.25 % |
| Accident du travail | brut | — | 1.00 % |
| Chômage | brut | 0 % (depuis 2018) | 4.05 % |
| FNAL | brut | — | 0.50 % |
| Formation pro | brut | — | 0.55 % |
| Transport | brut | — | 1.75 % |
| **CDDU IFM** | brut hors IFM/ICP | 10 % (à payer) | — |
| **CDDU ICP** | brut + IFM | 10 % (à payer) | — |

## Workflow

### 1. Mission TERMINEE
Quand un établissement passe une mission en `TERMINEE` (ou via cron auto)
pour un soignant SALARIE/MIXTE :
1. Le trigger `trg_auto_creer_bulletin_paie` se déclenche.
2. Il appelle `fn_creer_bulletin_paie(mission_id)`.
3. La RPC vérifie que mission TERMINEE + soignant non-LIBERAL.
4. Si pas déjà fait, `fn_calculer_cotisations` est appelée et peuple
   `cotisations_sociales`.
5. Un numéro séquentiel `BP-{SIRET8}-{ANNEE}-{SEQ5}` est généré.
6. INSERT dans `bulletins_paie` (statut=EMIS).
7. Audit `BULLETIN_PAIE_EMIS` dans `journaux_audit` via
   `fn_ecrire_audit_safe`.

### 2. Affichage / téléchargement
Le soignant accède à `/soignant/bulletins-paie` :
- Liste de ses bulletins (RPC `fn_mes_bulletins_paie`).
- Filtres période (année) + statut.
- KPI : Brut total, Net total, Cotisations totales (sur la liste filtrée).
- Bouton « PDF » par ligne → `telechargerBulletinPaiePdf(id)`.

Le PDF est généré côté client (jsPDF) à la demande, à partir des données
de :
- `bulletins_paie` (totaux + identifiants),
- `cotisations_sociales` (détail par cotisation),
- `soignants`, `etablissements`, `missions` (identités + prestation).

Aucune génération côté serveur n'est nécessaire pour l'affichage. Un
upload Storage pourra être ajouté plus tard pour archivage signé.

### 3. Paiement
Hors scope de cette session. Le statut `PAYE` sera mis à jour quand
l'établissement aura confirmé le virement net au soignant via Stripe
Connect (cf. `paiements_soignant`). Lien à wirer : trigger sur
`paiements_soignant` qui flippe `bulletins_paie.statut = 'PAYE'` quand
le paiement est `CONFIRME` pour la même mission.

## Tests SQL bout-en-bout (28/04/2026)

Tests via MCP avec compte audit-as.

| # | Cas | Résultat |
|---|---|---|
| 1 | `fn_next_bulletin_paie_number` retourne `BP-e0640515-2026-00001` | ✅ PASS |
| 2 | `fn_creer_bulletin_paie('00000000-...')` mission inexistante | ✅ PASS — `{success:false, error:"Mission introuvable"}` |
| 3 | Mission audit-as TERMINEE → bulletin émis : brut 160€, cotisations 34.49€, net 125.51€, statut EMIS | ✅ PASS |
| 4 | UPDATE `bulletins_paie` en role authenticated | ✅ PASS — `permission denied` (pas de GRANT UPDATE, pas de policy UPDATE) |
| 5 | Trigger `trg_bp_immutability` (cohérent avec `trg_fh_immutability` factures, déjà testé) | ✅ Code revue + transitif |

## Fichiers source

### Frontend
- `src/lib/cotisations-2026.ts` — Constantes cotisations (réplique des taux DB).
- `src/lib/bulletin-paie-pdf.ts` — Génération PDF (jsPDF) conforme R3243-1.
- `src/pages/BulletinsPaie.tsx` — Page liste bulletins + filtres.
- `src/App.tsx` — Route `/soignant/bulletins-paie`.

### Backend (DB)
- `supabase/migrations/20260428210000_bulletins_paie_schema.sql` —
  Table + RPC + triggers + RLS.

### Pré-existant
- `cotisations_sociales` (calcul) — migration historique.
- `fn_calculer_cotisations` — calculateur brut→net.

## Limitations connues

**Tickets traités le 28/04/2026 (session "corrige tous les tickets") :**
- ✅ **N° Sécurité sociale** : colonne `soignants.numero_securite_sociale`
  ajoutée (CHECK 13/15 chiffres). RPC `fn_modifier_mon_nir(p_nir)` avec
  audit. Champ exposé dans `/soignant/profil` (bloc "Paie et facturation").
- ✅ **Convention collective** : colonne
  `etablissements.convention_collective` ajoutée. Le PDF utilise la
  valeur si renseignée, sinon placeholder "CCN établissements de santé
  applicable". Saisie via dashboard Supabase admin pour MVP, UI dédiée
  à venir.
- ✅ **Statut PAYE auto** : trigger `trg_bp_passage_paye` sur
  `paiements_soignant` flippe `bulletins_paie.statut='PAYE'` quand
  `confirme_par_soignant` devient true (ou statut='CONFIRME').
- ✅ **Cumul annuel** : RPC `fn_cumul_annuel_paie(p_soignant_id, p_annee,
  p_jusqu_au)` retourne brut/cotisations/net cumulés. Section "CUMUL
  ANNUEL" affichée dans le PDF entre le NET A PAYER et les mentions
  légales.

**Restant (P2) :**
- **PDF côté serveur** : actuellement client-only. Pour archivage signé
  Storage, prévoir une edge function future qui upload sur
  `bulletins-paie/{soignant_id}/{numero}.pdf` et met à jour
  `bulletins_paie.pdf_s3_key`.
- **UI Convention collective** : champ à exposer dans
  `ProfilEtablissement` (admin peut l'éditer via dashboard SQL pour MVP).

## Déploiement

- DB : migration appliquée via MCP `apply_migration`.
- Frontend : push main → Vercel auto-deploy.
- Pas d'edge function modifiée → pas de redéploiement nécessaire.
