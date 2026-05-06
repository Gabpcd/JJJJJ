# Tests CP-C-4 — Statut EXPIREE + transition auto (E5 + E8 + E14)

Scope : enum EXPIREE + `fn_auto_transitions_missions` section 4 + frontend.

## Pré-requis

- Migrations appliquées :
  - `20260420190000_cp_c_4_a_expiree_enum` (ADD VALUE seul)
  - `20260420190001_cp_c_4_a_expiree_enum_fn` (refonte fn_auto_transitions_missions)
  - `20260420190002_cp_c_4_a2_notifications_type_mission_non_pourvue` (fix CHECK)
- Cron `jobid 13 auto-transitions-missions` @ `*/10 * * * *` actif

## Tests SQL

```bash
psql "$DB_URL" -f tests/missions/cp-c-4.test.sql
```

Couvre 4 scénarios :
- [1] Mission OUVERTE debut_le −2h → EXPIREE + candidature REFUSEE + notification
- [2] Mission OUVERTE debut_le futur → reste OUVERTE (seuil 1h pas atteint)
- [3] Mission ASSIGNEE fin passée → TERMINEE (pas EXPIREE, distinct)
- [4] Idempotence : mission déjà EXPIREE → aucune notif dupliquée

Tests exécutés via MCP : scénario 1 validé (3/3 effets OK).

## Checklist manuelle E2E

### M1 — Affichage EXPIREE dans ListeMissions étab

**Étapes** :
1. Créer mission test avec debut_le dans le passé (2h) via UI
2. Attendre cron `auto-transitions-missions` (max 10 min) ou déclencher manuellement :
   ```sql
   SELECT public.fn_auto_transitions_missions();
   ```

**Vérifications** :
- [ ] Mission apparaît avec badge **"Expirée (non pourvue)"** jaune/amber
- [ ] Filtre "Expirées" disponible dans ListeMissions étab
- [ ] Cliquer le filtre Expirées : mission visible
- [ ] Compteur filtre correct

### M2 — Candidatures auto REFUSEE

**Étapes** :
1. Créer mission OUVERTE avec candidatures EN_ATTENTE
2. Backdater `debut_le` à −2h
3. `SELECT public.fn_auto_transitions_missions();`

**Vérifications** :
- [ ] Candidatures passent à REFUSEE avec `motif_refus='Mission expiree (non pourvue)'`
- [ ] `traite_le` set sur candidatures

### M3 — Notification MISSION_NON_POURVUE reçue

**Vérifications** :
- [ ] Notification in-app côté étab : titre "Mission expirée (non pourvue)"
- [ ] Corps inclut intitulé + CTA "republier"
- [ ] Lien vers `/etablissement/missions/<id>`

### M4 — Cycle complet via cron

**Étapes** :
```sql
-- Vérifier schedule
SELECT jobid, schedule, command FROM cron.job WHERE jobid = 13;
-- Runs récents
SELECT * FROM cron.job_run_details WHERE jobid = 13 ORDER BY start_time DESC LIMIT 5;
```

**Vérifications** :
- [ ] jobid 13 active, schedule `*/10 * * * *`
- [ ] Dernières exécutions `succeeded`

## Vérifications post-prod

```sql
-- Distribution statuts missions
SELECT statut, COUNT(*) FROM public.missions GROUP BY statut ORDER BY COUNT(*) DESC;

-- Missions récemment expirées
SELECT id, intitule, debut_le, modifie_le
FROM public.missions
WHERE statut='EXPIREE' AND modifie_le > NOW() - INTERVAL '7 days'
ORDER BY modifie_le DESC;

-- Candidatures REFUSEE avec motif expiration
SELECT COUNT(*) FROM public.candidatures
WHERE statut='REFUSEE' AND motif_refus = 'Mission expiree (non pourvue)';
```

## Tickets clôturés

- **E5** (P1, 8h → 3h) : statut EXPIREE + transition auto via `fn_auto_transitions_missions` section 4 refondue → **RÉSOLU**
- **E8** (P2, 4h → 0h) : `paiements_soignant.echeance_le` déjà calculée par `fn_declarer_paiement_soignant` (CP-C-1), source de vérité OK → **RÉSOLU** (sans travail additionnel)
- **E14** (P1, 0h) : intégré à E5 → **RÉSOLU**

## Ticket émergent

- **UI-C4-email** (P2, 2h) : template email MISSION_EXPIREE pour étab. Notif in-app déjà OK, email optionnel nice-to-have. Sub-PR : SP-B-templates-email-critiques.

## Décisions architecturales

1. **Statut EXPIREE distinct d'ANNULEE_PAR_ETABLISSEMENT** : sémantique claire (non pourvue vs action volontaire) pour scoring/stats.
2. **Seuil 1h post `debut_le`** (vs 15 min historique) : plus tolérant pour cas où mission accepte une candidature au dernier moment.
3. **Candidatures EN_ATTENTE/PROPOSEE auto REFUSEE** avec motif explicite : pas d'orphelines, UX claire pour soignants.
4. **Pas de nouvelle colonne `missions.paiement_echeance_le`** : `fn_declarer_paiement_soignant` (CP-C-1) calcule déjà `paiements_soignant.echeance_le = CURRENT_DATE + delai_paiement_jours`.
5. **Seuils relances/blocage (CP-C-2/C-3) conservés sur `fin_le + X days`** : uniformité produit, pas de variance par étab.
6. **44 missions ANNULEE_PAR_ETABLISSEMENT legacy conservées** (Option A) : cohérence historique.
7. **CHECK `notifications.type` étendu** : ajout MISSION_NON_POURVUE (bug existant résolu).
