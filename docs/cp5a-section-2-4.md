# CP5a — Sections 2.6 & 2.7 (compléments refonte triggers/taux)

> Sections 2.4/2.5 validées en chat → intégrées directement en SQL migration.

---

## 2.6 — Tests mentaux (7 scénarios)

### A. GEL normal
- OUVERTE → ASSIGNEE
- 8 champs `_fige` remplis depuis valeurs établissement
- `fige_le = now()`

### B. DEGEL
- ASSIGNEE → OUVERTE
- 8 champs `_fige` → NULL
- Insert `journaux_audit` avec type `DEGEL_APPLIED`

### C. PROTECTION sans bypass
- Mission gelée, `UPDATE taux_horaire_base` → `RAISE EXCEPTION`
- Message : « Champ protégé post-gel, utiliser override admin »

### D. PROTECTION avec bypass admin
- `SET LOCAL app.override_gel = 'true'`
- `UPDATE taux_horaire_base` → passe
- Insert `journaux_audit` avec type `OVERRIDE_CHAMP_POST_GEL`

### E. RE-GEL (gel A → dégel → gel B)
- Taux gel B = valeurs établissement **actuelles**, pas celles du gel A
- Vérifie que `_fige` reflète l'état live, pas un snapshot périmé

### F. Admin force ASSIGNEE → OUVERTE
- Transition admin directe → dégel normal appliqué
- Mêmes effets que scénario B (nullification `_fige`)

### G. Sync créneau sur mission gelée
- Créneau modifié alors que mission est ASSIGNEE
- Les 8 champs `_fige` restent inchangés (protégés par trigger)

---

## 2.7 — Risques identifiés

| ID | Risque | Mitigation |
|----|--------|------------|
| P4 | `est_urgente` modifié post-gel → SMS trigger fire | SMS trigger vérifié : ne fire que sur `statut = 'OUVERTE'`, pas de faux envoi |
| P5 | Transitions admin forcées (bypass statut) | Dégel normal appliqué, pas de traitement spécial nécessaire |
| P6 | OUVERTE → EN_COURS sans gel (admin bypass) | Fallback `COALESCE` sur valeurs établissement live — pas de NULL |
| P7 | Conflits d'ordre entre triggers | `trg_zz_geler_mission` en position 25 (dernier), aucun conflit détecté |

### Notes
- Position 25 = préfixe `zz_` garantit exécution après tous les autres triggers
- Le `COALESCE` dans les vues/requêtes protège contre tout scénario de `_fige` NULL inattendu
- Aucun risque bloquant identifié pour la migration
