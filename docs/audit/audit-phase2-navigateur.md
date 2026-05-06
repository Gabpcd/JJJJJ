# Audit fonctionnel hybride — Phase 2 : test navigateur Playwright

> **Date** : 2026-04-27 · **Branche** : `audit/phase-2`
> **Méthodo** : Playwright 1.58 (chromium 1194 pré-installé) sur localhost:8080.
> **Périmètre** : 5 scénarios principaux + 3 bonus.

## Sommaire

- [Setup](#setup)
- [⚠️ Limitation environnement](#limitation-environnement)
- [Scénarios](#scenarios)
- [Synthèse Phase 2](#synthese-phase-2)
- [Combinaison Phase 1 + Phase 2](#combinaison-phase-1--phase-2)

## Setup

| Élément | État |
|---|---|
| `npm install` | ✅ 712 packages (offline) |
| `npm run dev` (Vite) | ⚠️ vite.config.ts a `host: "::"` (IPv6) — sandbox sans IPv6 → erreur `EAFNOSUPPORT`. Workaround : `npx vite --host 127.0.0.1 --port 8080`. **Ticket P2** : forcer `host: "0.0.0.0"` pour compatibilité multi-env. |
| Playwright | 1.58.2 installé |
| Chromium | Pré-installé `/opt/pw-browsers/chromium-1194/chrome-linux/chrome` (download 1208 bloqué par sandbox) |
| HTTP localhost:8080 | 200 OK |

## ⚠️ Limitation environnement

**Sandbox réseau bloque les requêtes outbound HTTPS vers `flripxtsyegjshnhzjkz.supabase.co`** :
- `ERR_CERT_AUTHORITY_INVALID` sur tous les appels Supabase
- 503 sur les fonctions edge

**Conséquence directe** sur Phase 2 :
- ❌ `signUp` / `signInWithPassword` ne fonctionnent pas → inscriptions ne peuvent pas finaliser, login impossible
- ❌ Edge function `verify-rpps` injoignable → aucun badge "RPPS Vérifié" ne peut s'afficher
- ❌ `register-soignant` injoignable → bouton "Créer mon compte" reste disabled (validation côté front qui attend la réponse RPPS)

**Conséquence pour le rapport** :
- ✅ **Le rendu UI statique et la logique conditionnelle sont validés** par captures d'écran (page chargée, formulaire correct, champs cachés/affichés selon profession).
- ❌ **Les flows end-to-end nécessitant Supabase ne sont pas validés en navigateur** dans cet environnement.
- ✅ **Les flows Supabase sont déjà couverts par Phase 1** (tests SQL via MCP, edge functions inspectées, RPCs reproduites).

**À faire en environnement avec accès réseau** : rejouer `node audit-phase2.mjs` chez Gabrielle (qui a accès supabase.co) pour valider les bouts manquants.

## Scénarios

### S1 — Inscription IDE complète

**Statut** : ⚠️ **PARTIAL** (UI OK, submit bloqué par sandbox).

**Étapes traversées** : 5/8 (étape 1 OK, étape 2 OK jusqu'à RPPS, soumission impossible).

**Screenshots** :
- `s1-01-page.png` à `s1-06-after-submit.png` (6 captures)
- `s1-04-profession-IDE-types.png` confirme : **3 cases CDDU/VACATION/LIBERAL** affichées pour IDE ✅
- `s1-05-rpps-verifie.png` montre formulaire rempli ; badge "RPPS Vérifié" non visible (edge fn bloquée par sandbox)

**Bugs détectés** : aucun bug applicatif. Les 3 erreurs P1 listées dans `results.json` sont toutes des conséquences directes du blocage sandbox (impossible de vérifier le RPPS → bouton submit reste désactivé → click timeout).

**Confirmations positives** :
- ✅ Page charge sans erreur JS bloquante
- ✅ Étape 1 + Étape 2 nominales
- ✅ Filtre CDDU/VACATION/LIBERAL visible pour IDE (cohérent avec PROFESSIONS_NON_LIBERAL)

### S2 — Inscription AS sans RPPS

**Statut** : ⚠️ **PARTIAL** (UI confirme R3.4 + R3.5, submit bloqué).

**Screenshots** : `s2-01-as-selectionne.png` montre :
- ✅ **Pas de champ RPPS** (R3.4)
- ✅ **Pas de checkbox LIBERAL** (R3.4)
- ✅ **Pas de checkbox VACATION** (R3.4)
- ✅ Seuls "CDD d'usage (CDDU)" et "Salarié" présents

**Bugs détectés** : 1 P1 = submit timeout (conséquence sandbox, pas un bug applicatif).

**Confirmations positives** :
- ✅ Logique R3.4 (filtres profession-aware) **vérifiée visuellement** sur page rendue.

### S3 — Inscription Médecin avec spécialité

**Statut** : ⏭️ **SKIP**.
**Raison** : `rpps_test` ne contient que IDE (`00000000001`) et stubs Pharmacien/AS. Pas de RPPS test médecin → impossible de tester l'extraction de spécialité depuis l'API ANS dans cet env. Phase 1 a inspecté le code (verify-rpps remonte `specialite_code` + `specialite_label` depuis FHIR — confirmé).

### S4 — Inscription Étab + publication mission

**Statut** : ⚠️ **PARTIAL** (formulaire rendu, étapes suivantes nécessitent SIRET valide INSEE).
**Screenshots** : `s4-01-page.png` à `s4-03-etape2.png`.
**Bugs détectés** : aucun bug applicatif. Pas de continuation pour ne pas créer de fausses entreprises avec SIRET réels.

### S5 — Candidature complète

**Statut** : ⏭️ **SKIP**.
**Raison** : dépend de S1 + S4 finalisés. Logique candidature/acceptation déjà validée Phase 1 par tests SQL reproductibles (cf. `docs/audit/audit-fonctionnel-etab.md`).

### Bonus 1 — Régression P1-A (matching IDE/IBODE)

**Statut** : ⏭️ **SKIP**.
**Raison** : test SQL Phase 1 a confirmé reproductibilité (audit-ibode → mission IDE refusé strict). Comportement UI identique attendu — pas de gain à retester en navigateur.

### Bonus 2 — Profil AS, vérifier section RPPS absente

**Statut** : ❌ **FAIL** (sandbox).
**Raison** : login `audit-as@jolene-test.dev` échoue avec `TypeError: Failed to fetch` sur `signInWithPassword`. URL reste sur `/connexion`.
**Confirmation indirecte (Phase 1)** : la logique de masquage est dans `SectionProfilPrincipal.tsx:325-340` (carte "Identification professionnelle" si `PROFESSIONS_SANS_RPPS.includes(profession)`).

### Bonus 3 — Pharmacie crée mission, vérifier filtre profession

**Statut** : ❌ **FAIL** (sandbox).
**Raison** : login `audit-pharmacie@jolene-test.dev` échoue. Page `/etablissement/missions/creer` redirige vers `/connexion`. Combobox profession introuvable car page protégée.
**Confirmation indirecte (Phase 1)** :
- Frontend : `FormulaireMission.tsx:413` filtre `PROFESSIONS_PHARMACIE`.
- Backend : `fn_creer_mission` retourne `"Une pharmacie d'officine ne peut publier que des missions pour pharmacien ou préparateur."` (confirmé SQL Phase 1).

## Synthèse Phase 2

| Statut | Compte |
|---|---|
| ✅ PASS | 0 |
| ⚠️ PARTIAL | 3 (S1, S2, S4) |
| ⏭️ SKIP | 3 (S3, S5, Bonus 1) |
| ❌ FAIL (sandbox) | 2 (Bonus 2, Bonus 3) |

**Bugs P0/P1/P2 nouveaux trouvés en Phase 2** : **0** bug applicatif réel.

**Nouveau ticket cosmétique trouvé** :
- **P2** : `vite.config.ts` utilise `host: "::"` (IPv6 only). Empêche le démarrage dans des sandboxes sans IPv6 (cas de Claude). Recommandation : `host: "0.0.0.0"` ou `host: true`.

**Confirmations positives Phase 2** (par captures d'écran) :
- ✅ Page d'inscription soignant rendue sans erreur JS
- ✅ Logique conditionnelle AS : RPPS + LIBERAL + VACATION cachés (R3.4)
- ✅ Logique conditionnelle IDE : 3 contrats CDDU/VACATION/LIBERAL affichés
- ✅ Page d'inscription étab rendue sans erreur JS
- ✅ Page de connexion rendue sans erreur JS
- ✅ Cookies popup affiché (consentement OK)

## Combinaison Phase 1 + Phase 2

Tickets consolidés triés par priorité :

| ID | Sévérité | Source | Description | Reproductibilité |
|---|---|---|---|---|
| P1-A | P1 | Phase 1 SQL | Hiérarchie pro ignorée (IBODE/IADE → IDE refusé même avec accepte_non_specialises=true) | SQL reproductible |
| P1-B | P1 | Phase 1 SQL | Match spécialité médicale absent (généraliste accepte mission cardio) | SQL reproductible |
| P1-C | P1 | Phase 1 code | Helper completion : item RPPS marqué `obligatoire: false` pour les 13 professions avec RPPS — dissonance UX | Code reading |
| P2-A | P2 | Phase 1 code | KINE : seuil "3 200h" hard-codé alors que `regleInstallation.heures_requises = 2240` | Code reading |
| P2-B | P2 | Phase 1 SQL | `fn_creer_mission` : 3 overloads coexistent (10/11/12 args) | SQL meta |
| P2-C | P2 | Phase 2 | `vite.config.ts` : `host: "::"` empêche démarrage IPv4-only | Phase 2 reproductible |

**Total** : 0 P0 · 3 P1 · 3 P2.

### Recommandation suite

**Avant de fixer** : décider si Phase 2 doit être rejouée par Gabrielle dans son env (avec accès supabase.co) pour confirmer les flows bloqués ici (Bonus 2, Bonus 3, S1/S2 jusqu'au submit). Le code est prêt à tester — `audit-phase2.mjs` à la racine est rejouable tel quel chez elle.

**Ordre suggéré pour fix** :
1. **P1-A & P1-B** ensemble : refactor `fn_postuler_mission` pour accepter hiérarchie pro + match spécialité (1 migration SQL, 1 commit)
2. **P1-C** : correction helper `obligatoire: profession dans !PROFESSIONS_SANS_RPPS` (1 commit frontend)
3. **P2-A** : remplacer texte hard-codé KINE par template (1 commit frontend, trivial)
4. **P2-B** : DROP des 2 anciennes signatures `fn_creer_mission` (1 migration)
5. **P2-C** : `vite.config.ts` `host: "0.0.0.0"` (1 commit, trivial — débloque Phase 2 dans sandbox)

Total estimé : **3 commits frontend + 2 migrations**, ~1h30 de travail.
