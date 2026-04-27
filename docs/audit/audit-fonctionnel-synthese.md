# Audit fonctionnel hybride — Phase 1 : synthèse + tickets

> **Date** : 2026-04-27 · **Branche** : `audit/phase-1`
> **Périmètre Phase 1** : lecture de code + tests SQL via MCP Supabase. Pas de test navigateur.
> **Phase 2 prévue** : Playwright (déjà installé, `npm run test:e2e`).

## Sommaire

- [Récap](#recap)
- [Tickets P0](#tickets-p0)
- [Tickets P1](#tickets-p1)
- [Tickets P2](#tickets-p2)
- [Bugs déjà connus & corrigés](#bugs-deja-connus--corriges)
- [Recommandations Phase 2](#recommandations-phase-2)
- [Comptes test à nettoyer](#comptes-test-a-nettoyer)

## Récap

| Catégorie | Cas testés | Bugs trouvés |
|---|---|---|
| Soignant — 15 professions × 6 flows | 90 micro-audits | 1 P2 + edge cases |
| Étab — 4 types × 8 flows | 32 micro-audits | 0 bugs |
| Cross-matching — 8 scénarios SQL | 8 reproductibles | 3 P1 + 1 P2 |
| **Total** | **130 cas** | **0 P0 · 3 P1 · 2 P2** |

Aucun bug bloquant (P0). Pas de fuite de données identifiée. Le système est globalement cohérent — les 3 P1 sont des manques de logique métier (matching avancé) plutôt que des régressions.

## Tickets P0

**Aucun.**

## Tickets P1

### P1-A — Hiérarchie professionnelle ignorée par `fn_postuler_mission`

**Symptôme** : un IBODE ne peut pas candidater à une mission IDE, même quand `accepte_non_specialises=true` côté mission.

**Cause** : ligne `IF v_soignant.profession != v_mission.profession_requise THEN RETURN error` fait un match strict sans hiérarchie. Le flag `accepte_non_specialises` stocké côté `missions` n'est jamais lu.

**Reproduction SQL** :
```sql
-- audit-ibode@jolene-test.dev tente candidature mission IDE
SELECT fn_postuler_mission('<mission_ide_id>'::uuid, NULL);
-- → {"error":"Cette mission requiert un(e) IDE."}
```

**Impact métier** : significatif. IBODE/IADE perdent l'accès à des missions IDE qui devraient leur être ouvertes ; les étabs IBODE qui cochent `accepte_non_specialises` ne reçoivent jamais de candidatures IDE.

**Recommandation fix** : implémenter une table de hiérarchie ou un mapping (IBODE ⊃ IDE, IADE ⊃ IDE) consulté quand le flag `accepte_non_specialises=true`.

### P1-B — Match spécialité médicale absent

**Symptôme** : un MEDECIN généraliste passe la validation profession sur une mission MEDECIN spécialité cardio (`SM48`), même si `accepte_non_specialises=false`.

**Cause** : `mission.specialite_medicale_requise` est stockée mais jamais comparée à `soignant.specialite_medicale` par `fn_postuler_mission`.

**Reproduction SQL** :
```sql
-- audit-medecin@jolene-test.dev (sans spécialité) sur mission cardio
SELECT fn_postuler_mission('<mission_medecin_cardio_id>'::uuid, NULL);
-- → bloque uniquement sur RCP, pas sur spécialité
```

**Impact métier** : significatif. Étabs reçoivent candidatures de médecins généralistes pour postes spécialisés, doivent filtrer manuellement à l'acceptation.

**Recommandation fix** : ajouter dans `fn_postuler_mission` :
```sql
IF v_mission.specialite_medicale_requise IS NOT NULL
   AND COALESCE(v_mission.accepte_non_specialises, true) = false
   AND COALESCE(v_soignant.specialite_medicale, '') != v_mission.specialite_medicale_requise THEN
  RETURN jsonb_build_object('error', 'Spécialité requise : ' || v_mission.specialite_medicale_requise);
END IF;
```

### P1-C — Profession `obligatoire: false` dans helper completion

**Symptôme** : un soignant peut atteindre 100% de complétion de profil sans avoir vérifié son RPPS, ce qui crée une dissonance entre l'UX (profil "complet") et la candidature (refusée parce que profession=null).

**Cause** : `src/lib/profil-soignant.ts` marque l'item `rpps` avec `obligatoire: false`. Pour les 13 professions avec RPPS, la vérification est en pratique requise pour candidater.

**Recommandation fix** : passer `obligatoire: true` pour cet item quand profession dans `!PROFESSIONS_SANS_RPPS`. Cela rendra l'item rouge dans le bandeau, et `peut_candidater` retournera false.

## Tickets P2

### P2-A — KINE : seuil "3 200h" hard-codé dans le profil

**Fichier** : `src/components/profil-soignant/SectionProfilPrincipal.tsx:382`.
**Symptôme** : le texte "Passage en libéral disponible à 3 200h — actuellement Xh/3 200h" s'affiche tel quel pour KINE alors que le seuil réel est 2240h.
**Recommandation** : lire `regleInstallation.heures_requises` et formater dynamiquement.

### P2-B — `fn_creer_mission` 3 overloads

**Symptôme** : 3 signatures coexistent (10, 11, 12 args). Pas de bug en pratique car le frontend appelle la signature 12-args avec named params, mais surface technique inutile.
**Recommandation** : DROP des 2 anciennes signatures dans une migration de nettoyage.

## Bugs déjà connus & corrigés

| Référence | Bug | Statut |
|---|---|---|
| R3.5 | Mentions ADELI obsolète | ✅ corrigé |
| R3.4 | register-soignant 500 (gen_random_bytes) | ✅ corrigé |
| R3.4 | fn_types_exercice_autorises 401 anonyme | ✅ corrigé |
| R3.4 | Inscription AS/AES — RPPS + LIBERAL incohérents | ✅ corrigé |
| R3.3 | fn_modifier_mon_profil 400 (action audit enum) | ✅ corrigé |
| R3.3 | 4 .single() résiduels sur soignants → 406 | ✅ corrigé |
| R3.2 | Triplon "Compléter profil" Dashboard | ✅ corrigé |
| R2.5 | Seuil 800h hard-codé sur Dashboard | ✅ corrigé |
| R2.5 | type_contrat vs type_exercice incohérence rappels fiscaux | ✅ corrigé |

## Recommandations Phase 2

| Sujet | Tester en navigateur ? | Pourquoi |
|---|---|---|
| Inscription AS, AES, IDE, MEDECIN bout-en-bout | **OUI** | Vérifier que la sérialisation JSON et les hooks fonctionnent réellement avec un user newly-signed-up |
| Vérification RPPS inline depuis Profil | **OUI** | Edge function verify-rpps + UPSERT côté DB — chaîne complète à valider en navigateur |
| Création mission par PHARMACIE → vérifier UI restreint à PHARMACIEN/PREPARATEUR | **OUI** | Filtre client + backend déjà testés en SQL ; reste à confirmer en UI réelle |
| Candidature IDE → mission IDE → acceptation par étab → contrat signé | **OUI** | Flow critique end-to-end ; bcc test des emails et notifs |
| Bandeau completion : transitions warning ↔ destructive ↔ success selon items remplis | **OUI** | UX states pas testables en SQL pur |
| P1-A IBODE → IDE | **OUI** (après fix) | Régression candidate |
| P1-B Spécialité | **OUI** (après fix) | Régression candidate |

**Priorité Phase 2** : commencer par les inscriptions des 4 profils-types (IDE, AS, MEDECIN, PHARMACIEN) car couvre les 4 catégories de règles (avec/sans RPPS, avec/sans libéral). Si tout passe, étendre.

## Comptes test à nettoyer

Pour cleanup après Phase 2 :

```sql
-- Soignants test
DELETE FROM soignants WHERE email LIKE 'audit-%@jolene-test.dev';
DELETE FROM auth.users WHERE email LIKE 'audit-%@jolene-test.dev';

-- Etabs test
DELETE FROM etablissements WHERE email_contact LIKE 'audit-%@jolene-test.dev';

-- Missions de test
DELETE FROM missions WHERE intitule LIKE 'AUDIT TEST%';

-- Exclusion test
DELETE FROM exclusions WHERE motif = 'audit test';
```

19 comptes créés (15 soignants + 4 étabs), tous email `audit-{role}@jolene-test.dev`, mot de passe `auditTest2026!`. Les soignants ont profession + nom/prénom mais sans RCP ni documents validés (volontaire pour cibler le flow vide).
