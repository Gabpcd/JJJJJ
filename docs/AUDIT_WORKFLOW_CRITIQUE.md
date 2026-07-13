# Audit workflow critique Jolene — pré-lancement commercial

> **Date** : 12 mai 2026
> **Périmètre** : workflow critique CA (inscription étab → création mission → inscription soignant → candidature → confirmation → contrat + signature → DPAE → pointage → validation → facture → paiement → reversement → notifications).
> **Méthode** : audit code + audit base de données live (MCP Supabase) + audit logs prod 24h + revue advisors sécurité. Pas de test runtime e2e (sandbox bloque l'egress vers `*.supabase.co`, pas de browser, pas de comptes Stripe test ici).
> **Convention** : `VÉRIFIÉ DB/LOG/CODE` = constaté en live. `À VALIDER` = trouvaille agent à confirmer manuellement. Sévérité : P0 (bloquant lancement) / P1 (gênant en prod) / P2 (cosmétique ou edge case). Effort : XS (<1h), S (1-4h), M (4-8h), L (1-2j), XL (>2j).

---

## TL;DR — Ce qu'il faut absolument fixer avant lancement

| # | Finding | Sévérité | Effort | Statut |
|---|---|---|---|---|
| 1 | `fn_pointer_depart` plante : colonne `depart_modele_terminal` absente | **P0** | XS | VÉRIFIÉ DB |
| 2 | `fn_purger_gps_ancien` + `fn_supprimer_mon_compte` plantent (même colonne manquante) | **P0** | XS | VÉRIFIÉ DB |
| 3 | `health-check` retourne 401 systématique : pas de support `?secret=` query param | **P0** | XS | VÉRIFIÉ LOG |
| 4 | `service_role` manque le grant `DELETE` sur `tokens_push` → cleanup tokens expirés impossible | **P0** | XS | VÉRIFIÉ DB |
| 5 | `verify-rpps` 401 récurrent (avant PR #68 — à confirmer en prod) | **P0** | S | À RE-VÉRIFIER |
| 6 | `type_exercice` soignant non collecté à l'inscription → soignant LIBERAL devient SALARIE → candidatures LIBERAL refusées | **P0** | M | VÉRIFIÉ CODE |
| 7 | Soignant MIXTE candidatant sur mission `TOUS` : `type_contrat_choisi` non collecté → erreur E16 à l'acceptation | **P0** | M | À VALIDER |
| 8 | `verify-siret` retourne encore l'ancien format `{ error: "..." }` (non aligné PR #66) | **P1** | S | VÉRIFIÉ CODE |
| 9 | Yousign : pas d'edge function `yousign-callback` → statut contrat reste `EN_ATTENTE_SIGNATURES` à jamais après signature | **P0** | L | VÉRIFIÉ CODE |
| 10 | Stripe `balance_insufficient` non mappé dans `_shared/stripe-errors.ts` → transfer silently fail | **P1** | S | À VALIDER |
| 11 | DPAE : aucune génération auto pour les missions CDDU (RPC `fn_confirmer_dpae` est purement manuelle) | **P0** | M | VÉRIFIÉ DB |
| 12 | Aucun email `CONTRAT_A_SIGNER` envoyé au soignant après acceptation candidature → friction UX | **P1** | S | À VALIDER |
| 13 | Aucun email `CANDIDATURE_RECUE` envoyé à l'étab à dépôt de candidature | **P2** | S | À VALIDER |
| 14 | 15 établissements `statut_verification = VERIFIE` mais **0** signature dans `contrats_service_signatures` → soit le contrat-cadre Jolene n'est pas bloquant, soit la table a été désynchronisée d'un refactor | **P1** | M | VÉRIFIÉ DB |

**Effort total des P0 vérifiés** : ~3 jours de dev concentré (1 dev senior).

---

## Section 1 — Findings VÉRIFIÉS DB / LOG (haute confiance)

### F-1 [P0 — XS — VÉRIFIÉ DB] `fn_pointer_depart` plante : colonne `depart_modele_terminal` absente

**Cause** : La RPC `fn_pointer_depart` exécute :
```sql
UPDATE presences SET
    pointage_depart_le = NOW(),
    depart_lat = p_lat, depart_lng = p_lng,
    depart_precision_gps_m = p_precision,
    depart_id_terminal = p_terminal_id,
    depart_modele_terminal = p_modele,    -- ← colonne inexistante
    methode_pointage_depart = ...
WHERE id = p_presence_id;
```
Le schéma de `presences` a `arrivee_modele_terminal` mais pas son équivalent côté départ (asymétrie). Erreur Postgres confirmée en logs prod 24h : `column "depart_modele_terminal" of relation "presences" does not exist`.

**Symptôme utilisateur** : un soignant qui pointe son départ en mode GPS standard reçoit une erreur sortie. Le mode CODE de secours (`fn_pointer_depart_code`) marche.

**Impact CA** : workflow critique cassé dès qu'un soignant termine sa première mission en mode GPS. Aucune presence en prod actuellement (0 rows), donc bug latent — mais explose au premier vrai pointage.

**Appelants** :
- `src/pages/PresencesSoignant.tsx:344` (page pointage principal)
- `src/components/SyncHorsLigne.tsx:30` (sync offline)

**Fix** : migration SQL `ALTER TABLE presences ADD COLUMN depart_modele_terminal text;` (symétrie avec `arrivee_modele_terminal`). Une seule ligne, pas de data migration.

---

### F-2 [P0 — XS — VÉRIFIÉ DB] `fn_purger_gps_ancien` et `fn_supprimer_mon_compte` plantent (même colonne)

**Cause** : Les deux RPCs font `UPDATE presences SET … depart_modele_terminal = NULL` → même erreur que F-1.

- `fn_purger_gps_ancien` : cron `jobid 3` dimanche 3h. Plante en silence chaque semaine — données GPS jamais anonymisées → **non-conformité RGPD Art. 5(1)e (limitation conservation)**.
- `fn_supprimer_mon_compte` : RPC déclenchée par l'utilisateur via UI suppression compte. Plante → user voit erreur. **Non-conformité RGPD Art. 17 (droit à l'effacement)**.

**Fix** : même `ALTER TABLE` que F-1 répare les 3 RPCs.

---

### F-3 [P0 — XS — CORRIGÉ] `health-check` retournait 401 systématiquement

**Cause historique** : le monitoring externe envoyait son secret dans la query string, qui est journalisée par les proxies, tandis que la fonction exigeait un Bearer.

**Symptôme** : monitoring aveugle — toutes les sondes échouent, aucun reporting de uptime fiable. Logs confirment ~12 hits 401 par heure (1 toutes les 5 min).

**Fix appliqué** : `HEAD` est une sonde publique superficielle qui ne touche pas la base et ne renvoie aucun diagnostic. Les diagnostics complets `GET`/`POST` exigent un administrateur AAL2 ou un appel interne. Aucun secret n'est accepté dans l'URL.

---

### F-4 [P0 — XS — VÉRIFIÉ DB] `service_role` n'a pas le grant DELETE sur `tokens_push`

**Cause** : query DB confirmée :
- `authenticated` : SELECT, INSERT, UPDATE, DELETE
- `service_role` : SELECT, INSERT, UPDATE (**pas DELETE**)
- `postgres` : tout

L'edge fn `send-push/index.ts:147-151` exécute `supabaseAdmin.from("tokens_push").delete().eq(...)` avec service-role → `permission denied for table tokens_push` (vu en logs Postgres).

**Symptôme** : tokens push expirés (404/410) jamais nettoyés → table grossit indéfiniment, retries inutiles sur tokens morts.

**Fix** : migration `GRANT DELETE ON public.tokens_push TO service_role;`. Effort XS.

**Note** : il existe aussi une policy RLS `pol_token_delete TO authenticated USING (utilisateur_id = auth.uid())`. Comme `send-push` est invoqué par cron en service-role, l'absence de policy `service_role` côté DELETE n'est pas le blocant — c'est le GRANT manquant qui l'est. Une fois le GRANT ajouté, la RLS n'est pas évaluée pour service_role (par défaut bypass).

---

### F-5 [P0 — S — VÉRIFIÉ LOG (24h)] `verify-rpps` 401 résiduels

**Cause** : avant le merge de PR #68 (12 mai 09:53 UTC), `verify-rpps` exigeait une session auth → 401 systématique pour la vérif temps réel pendant l'inscription. Vu un 401 dans les logs récents (timestamp 1778578655, soit ~09:37 UTC, avant le merge).

**Statut** : **présumé résolu par PR #68** mais pas vérifié runtime (sandbox bloque). À tester par Gabrielle :
- Aller sur `app.jolene.app/inscription/soignant`, étape 2
- Taper RPPS `99999999999`
- Confirmer qu'un bandeau rouge "❌ RPPS non trouvé" apparaît sous le champ

Si encore 401 → vérifier que la version v450+ de `verify-rpps` est bien déployée par le workflow `deploy-supabase` (current logs show v449).

---

### F-6 [P0 — M — VÉRIFIÉ CODE] `type_exercice` soignant jamais persisté

**Cause** : `InscriptionSoignant.tsx` collecte un booléen `estSalarieEtablissement` mais le payload envoyé à `register-soignant` (`AuthContext.inscriptionSoignant`) **ne contient pas** `type_exercice`. Côté serveur `register-soignant/index.ts:169-179` insère :
```ts
const insertPayload = { id, prenom, nom, email, telephone, date_naissance, profession,
  type_contrat: contrats[0], types_contrat_acceptes: ...,
  numero_rpps, rpps_verifie, rayon_deplacement_km, adresse_lat, adresse_lng,
};
```
Pas de `type_exercice`. La colonne en DB a un default (`SALARIE` selon migration `20260319093935`), donc tous les nouveaux soignants finissent en SALARIE même s'ils se déclarent libéraux dans l'UI.

**Symptôme** : un médecin/IDE libéral qui se déclare libéral à l'inscription voit ses candidatures sur missions `LIBERAL` refusées car son `soignants.type_exercice = SALARIE` côté DB → incompatible.

**Impact CA majeur** : empêche la moitié du marché cible (libéraux remplaçants) d'utiliser la plateforme.

**Fix** :
1. Ajouter param `type_exercice` (`SALARIE` | `LIBERAL` | `MIXTE`) au body de `register-soignant`
2. Le dériver côté frontend depuis `estSalarieEtablissement` + `typesContrat` (si `LIBERAL` coché et pas SALARIE → `LIBERAL`, etc.)
3. Persister dans l'INSERT
4. Migration pour corriger les soignants existants : `UPDATE soignants SET type_exercice = 'LIBERAL' WHERE 'LIBERAL' = ANY(types_contrat_acceptes::text[]::text[]) ...` (à ajuster)

---

### F-7 [P0 — XS — VÉRIFIÉ DB] 15 établissements vérifiés / **0** signature contrat de service Jolene

**Cause** : query `SELECT COUNT(*) FROM contrats_service_signatures = 0` malgré 15 établissements `statut_verification = VERIFIE` et 8 avec `peut_publier_missions = true`.

**Hypothèse** : soit
- (A) la table `contrats_service_signatures` n'est plus utilisée (refactor vers `templates_contrat` ?)
- (B) le flag `peut_publier_missions` est mis à `true` directement par `register-etablissement` (vérifié dans `register-etablissement/index.ts:195` : `peut_publier_missions: autoVerifie || false` → mis à true dès que la vérif SIRET passe, **sans exiger signature contrat-cadre**)

**Impact légal** : un établissement peut publier des missions sans avoir signé le contrat de service Jolene (mandataire 289 I-2 + responsabilités). Risque juridique en cas de litige.

**Fix** :
1. Confirmer avec Gabrielle si la signature contrat de service est censée être bloquante ou non
2. Si bloquante : ajouter constraint trigger `BEFORE UPDATE OR INSERT ON missions` qui vérifie `EXISTS (SELECT 1 FROM contrats_service_signatures WHERE etablissement_id = NEW.etablissement_id AND statut = 'SIGNE')`

---

### F-8 [P1 — VÉRIFIÉ DB] 1 candidature ACCEPTEE / **0** `contrats_mission` généré

**Cause** : query DB : `SELECT COUNT(*) FROM candidatures WHERE statut = 'ACCEPTEE'` retourne 1, mais `contrats_mission` est à 0. La logique métier veut qu'à chaque acceptation, un contrat soit généré.

**Hypothèses** :
- `fn_traiter_candidature` (migration `20260420161000`) crée la row contrat mais une exception silencieuse est levée
- OU la candidature acceptée date d'avant l'ajout de la génération de contrat
- OU le test E16 (orphelin MIXTE/TOUS) bloque

**À investiguer** : query SQL : `SELECT * FROM candidatures WHERE statut='ACCEPTEE'` puis tracer ce qui s'est passé (audit log) pour cette candidature précise.

---

### F-9 [P2 — VÉRIFIÉ DB] 4 RPCs anon SECURITY DEFINER exposées

**Liste** :
- `fn_inscrire_liste_attente_prevoyance`
- `fn_missions_publiques_recherche`
- `fn_rechercher_aide`
- `fn_types_exercice_autorises`

Toutes 4 semblent intentionnelles pour la landing publique (preview missions sans login, recherche aide, etc.). À documenter dans `DECISIONS.md` ou commentaire SECURITY DEFINER pour éviter qu'un audit externe les flag. **Pas de fix code requis** sauf décision contraire de Gabrielle.

---

### F-10 [P2 — VÉRIFIÉ DB] RLS policy `prevoyance_liste_attente / pol_prev_la_insert WITH CHECK (true)`

**Cause** : INSERT autorisé pour tout rôle sans restriction. Probablement intentionnel pour la waitlist publique. La table doit alors avoir des contraintes UNIQUE sur email + un rate-limit IP côté edge function pour éviter le flood.

**À vérifier** : `SELECT * FROM information_schema.table_constraints WHERE table_name = 'prevoyance_liste_attente'`. Si UNIQUE(email) absent → flood possible. Si présent → finding cosmétique.

---

## Section 2 — Findings VÉRIFIÉS CODE

### F-11 [P0 — L — VÉRIFIÉ CODE] Yousign : pas d'edge function `yousign-callback`

**Cause** : `supabase/functions/` contient `yousign-create` mais pas `yousign-callback`. Le webhook Yousign signature_request.done n'est pas reçu côté Jolene → `contrats_mission.statut` ne passe jamais de `EN_ATTENTE_SIGNATURES` à `SIGNE_COMPLET`.

**Impact** : sans `SIGNE_COMPLET`, le pointage est bloqué (cf `fn_pointer_arrivee` ligne `IF v_contrat IS NULL THEN RETURN 'Le contrat doit être signé avant le pointage'`). Workflow gelé.

**Fix** : créer l'edge function `yousign-callback` qui :
- Valide le HMAC du webhook Yousign (header `X-Yousign-Signature`)
- Update `contrats_mission` : `statut = SIGNE_COMPLET, signature_soignant_le, signature_etablissement_le`
- Idempotent (un même signature_request_id n'update qu'une fois)

Configurer dans le dashboard Yousign : `POST https://flripxtsyegjshnhzjkz.supabase.co/functions/v1/yousign-callback` comme endpoint webhook.

---

### F-12 [P0 — M — VÉRIFIÉ DB] DPAE : aucune génération auto pour les missions CDDU

**Cause** : seule RPC trouvée est `fn_confirmer_dpae` (SECURITY DEFINER). Lecture de `confirm-dpae/index.ts` : c'est purement une fonction de **confirmation manuelle** (l'utilisateur clique "j'ai fait la DPAE"). Pas de trigger auto qui appelle l'API URSSAF.

**Symptôme** : un étab privé qui crée une mission CDDU n'a pas de DPAE générée — il doit la faire manuellement chez URSSAF puis confirmer dans Jolene. Si l'étab oublie, **infraction URSSAF**.

**Décision à valider avec Gabrielle** : Jolene s'est-il engagé à automatiser la DPAE ? Si oui, ouvrir un chantier dédié (intégration API URSSAF + stockage `dpae_numero` sur `contrats_mission`). Si non : juste **ajouter un rappel mail/SMS** à l'établissement après acceptation candidature pour qu'il pense à faire sa DPAE — rappel J+1 jusqu'au début de mission.

---

### F-13 [P1 — S — VÉRIFIÉ CODE] `verify-siret` retourne encore l'ancien format `{ error }`

**Cause** : Lecture de `supabase/functions/verify-siret/index.ts` (PR #66 ne l'a pas touché). 4 occurrences de `return new Response(JSON.stringify({ error: "..." }))` aux lignes ~122, 133, 147, 215.

**Impact** : si le flow `register-etablissement → call verify-siret` rencontre une erreur, le frontend ne peut pas mapper proprement (pas de `code`).

**Fix** : appliquer le même pattern que `register-soignant` post-PR #66 (importer `errorResponse`, remplacer les 4 retours). Effort S.

---

### F-14 [P1 — S — VÉRIFIÉ DB] `fn_annuler_contrat` / `fn_revoquer_contrat` n'existent pas

**Cause** : query DB confirme l'absence (seul `fn_revoquer_contrat_service` existe — pour le contrat-cadre, pas le contrat mission).

**Impact** : si un étab/soignant veut annuler un contrat mission après génération (mais avant signature), il n'y a pas de RPC dédiée. Probablement les triggers existants (cf `dec_annuler_contrat_si_mission_annulee`) couvrent le cas "mission annulée → contrat annulé", mais pas l'annulation directe.

**À valider** : Gabrielle a-t-elle besoin de pouvoir annuler manuellement un contrat ? Si oui ajouter `fn_annuler_contrat_mission(p_contrat_id, p_motif)`. Sinon : pas bloquant.

---

### F-15 [P1 — S — À VALIDER] Stripe : `balance_insufficient` non mappé

**Cause (rapport agent)** : `supabase/functions/_shared/stripe-errors.ts` mappe les `StripeCardError`, `StripeRateLimitError`, etc. mais pas le code `balance_insufficient` retourné par `stripe.transfers.create()` quand le compte plateforme n'a pas le solde (mode test).

**Impact** : en mode test, les transferts plateforme→soignant peuvent échouer silencieusement. Webhook reçoit `transfer.failed` mais l'utilisateur final ne sait pas pourquoi.

**Fix** : ajouter case explicite dans `mapStripeError` :
```ts
if (raw?.code === 'balance_insufficient') {
  return { code: 'STRIPE_BALANCE_INSUFFICIENT', userMessage: 'Le compte plateforme manque de fonds. Contactez le support.', status: 503, logLevel: 'error' };
}
```

À vérifier dans le code actuel — l'agent n'a peut-être pas lu la dernière version.

---

### F-16 [P1 — S — VÉRIFIÉ CODE] Email `CONTRAT_A_SIGNER` non envoyé après acceptation candidature

**Cause** : `fn_traiter_candidature` (RPC SQL) INSERT le row `contrats_mission` mais ne déclenche pas d'appel à `send-email` avec type `CONTRAT_A_SIGNER`. Le soignant doit aller manuellement sur son dashboard pour voir "vous avez un contrat à signer".

**Fix** : ajouter trigger AFTER INSERT ON `contrats_mission` qui invoke `send-email` (via `net.http_post` ou via cron qui scanne les contrats sans email envoyé). Préférer trigger pour la temps-réel.

---

### F-17 [P2 — S — À VALIDER (rapport agent)] Mention 289 I-2 toujours injectée dans Factur-X

**Cause (rapport agent)** : `generate-invoice/index.ts:76-81` injecte la mention mandataire art. 289 I-2 CGI dans **toutes** les factures Factur-X générées, même celles qui ne concernent pas un soignant libéral.

**Impact** : facture commission étab "salarié" reçoit une mention "Jolene mandataire de M. X" qui n'a pas lieu d'être → confusion comptable.

**Fix** : conditionner `buildSubrogationMention()` à `soignant.type_exercice IN ('LIBERAL', 'MIXTE')` ET `facture.type = 'HONORAIRES'`.

---

### F-18 [P2 — XS — À VALIDER (rapport agent)] SMS coût hardcodé 0.07€

**Cause** : `send-sms/index.ts:220` insère `cout_eur: twilioData.price ? Math.abs(parseFloat(twilioData.price)) : 0.07`. Si Twilio ne retourne pas `price`, fallback 0.07€ — invalide pour SMS hors France (ex. Finlande 0.15€).

**Impact** : reporting de coût SMS imprécis. Pas bloquant pour le launch France-only mais à corriger avant l'international.

---

### F-19 [P2 — S — VÉRIFIÉ CODE] Templates email existant mais non invoqués

**Cause** : Plusieurs templates dans `send-email/index.ts` allowlist (ex. `CANDIDATURE_RECUE`, `MISSION_ACCEPTEE_ETABLISSEMENT`) mais aucun call-site `invoke('send-email', { type: 'CANDIDATURE_RECUE' })` trouvé dans le code.

**Impact UX** : l'établissement ne reçoit pas d'email quand un soignant candidate à sa mission — il doit checker manuellement son dashboard.

**Fix** : ajouter dans `fn_postuler_mission` (ou via trigger AFTER INSERT) un appel `send-email` type `CANDIDATURE_RECUE` au destinataire = `mission.etablissement_id`.

---

### F-20 [P2 — XS — À VALIDER (rapport agent)] Cron secrets auth fragile

**Cause** : `email-cron/index.ts` accepte un Bearer token issu de plusieurs sources (env, vault, ...). Si toutes sont vides, accepte string vide → auth bypass.

**Fix** : require au moins une source non-vide, sinon 401.

---

## Section 3 — Faux positifs des agents (déjà OK)

### FP-1 ~~RLS missions trop permissive~~ — **EN FAIT STRICTE**

Agent 1 a regardé une vieille migration `20260311115120`. La policy actuelle est :
```sql
pol_mission_insert : est_admin() OR (est_admin_etablissement() AND etablissement_id = mon_etablissement_id())
```
Soignant lambda ne peut pas spoofer un étab. Pas de fix nécessaire.

### FP-2 ~~`fn_generer_numero_contrat` manquante~~ — **EXISTE EN DB**

Agent 2 a regardé `supabase/migrations/` qui ne contient peut-être pas toutes les définitions. Query DB confirme l'existence de `fn_generer_numero_contrat`, `fn_generer_numero_contrat_safe`, `fn_generer_numero_facture`.

### FP-3 ~~Validation J+72h non automatique~~ — **CRON EXISTE**

Cron `jobid 8` schedule `0 6 * * *` exécute `fn_auto_valider_presences_72h()` chaque jour à 6h UTC. OK.

### FP-4 ~~Migration `scans_pointage` vs `presences` incomplète~~ — **À VALIDER MANUELLEMENT**

Le rapport agent indique un système double. Je n'ai pas eu le temps de valider — à investiguer mais probablement plus de friction que de bug bloquant.

---

## Section 4 — Findings agent NON-vérifiés (à valider manuellement)

Liste brute des findings que les agents Explore ont rapportés mais que je n'ai pas eu le temps de re-confirmer via DB/code direct. Sévérité indicative.

### Sécurité / validation backend (Agent 1)
- [P1] `register-etablissement` : email/téléphone non validés côté serveur (regex)
- [P1] `type_contrat_recherche` mission : pas de CHECK constraint enum
- [P1] SIRET pas re-validé en RPC création mission
- [P1] `date_naissance` soignant : pas de CHECK constraint DB (juste validé en edge function)
- [P2] Type établissement non énuméré
- [P2] Taux horaire mission sans bornes min/max

### Contrats / paiements (Agent 2 + 3)
- [P1] `contrats_mission.statut` pas de CHECK constraint enum
- [P1] Yousign : conversion HTML→PDF naïve (TextEncoder raw bytes) — document signé serait illisible
- [P1] Stripe Connect : webhook `account.updated` peut retarder la mise à jour `statut=COMPLET` → user voit "compte pas actif"
- [P2] `montant_commission_ttc` immuable post-création mission (si tarif change, split obsolète)
- [P2] Stripe `payout.paid` match imparfait sur stripe_payout_id
- [P2] Chorus Pro pré-dépôt sans tracking statut (mode simulation)

### UX / notifs (Agent 3)
- [P1] `send-email/index.ts` : aucun import Resend SDK visible — implémentation provider à clarifier. **Vraiment à investiguer** : si Resend n'est pas appelé, aucun email ne part en prod.

---

## Section 5 — Recommandation d'ordre des fixes

Ordre proposé par valeur produit / effort :

### Sprint 0 — quick wins (1 journée)
1. F-1 + F-2 : `ALTER TABLE presences ADD COLUMN depart_modele_terminal text;` (15 min)
2. F-3 : ajouter support `?secret=` dans health-check (30 min)
3. F-4 : `GRANT DELETE ON tokens_push TO service_role;` (5 min)
4. F-13 : aligner verify-siret sur format PR #66 (1h)
5. F-15 : ajouter mapping `balance_insufficient` dans stripe-errors (15 min)
6. F-20 : durcir auth crons (30 min)

### Sprint 1 — bloquants fonctionnels (2-3 jours)
7. F-6 + F-7 (workflow soignant) : `type_exercice` collecté + persisté à inscription ; `type_contrat_choisi` collecté à candidature MIXTE
8. F-11 : créer `yousign-callback` edge function
9. F-12 : DPAE — décider auto vs rappel manuel et l'implémenter
10. F-16 : email `CONTRAT_A_SIGNER` automatique après acceptation candidature

### Sprint 2 — robustesse (3-5 jours)
11. F-8 : investiguer pourquoi la candidature ACCEPTEE n'a pas généré de contrat
12. F-19 : email `CANDIDATURE_RECUE` automatique à candidature
13. F-7 (suite) : décider si contrat-cadre Jolene est bloquant pour publication
14. F-17 : conditionner mention 289 I-2 selon type soignant
15. F-14 : `fn_annuler_contrat_mission` si besoin métier
16. Validations backend manquantes (F-non vérifiés Agent 1)

### Pre-launch sanity check
- Re-vérifier F-5 (verify-rpps 401) après déploiement PR #68
- Faire un vrai test end-to-end Cas 1 (libéral / privé / Stripe Connect) avec un compte test une fois F-1 et F-6 corrigés
- Pull Sentry filtré sur tag `type:inscription_soignant` post-fix pour confirmer drop des erreurs

---

## Section 6 — Statistiques prod actuelles (référence)

Query DB live :

| Métrique | Valeur |
|---|---|
| `auth.users` | 45 |
| `soignants` | 26 |
| `etablissements` | 21 |
| `missions` totales | 8 |
| missions `OUVERTE` | 4 |
| missions `ASSIGNEE` | 0 |
| missions `EN_COURS` | 0 |
| missions `TERMINEE` | 1 |
| `candidatures` totales | 5 |
| `candidatures` `ACCEPTEE` | 1 |
| `contrats_mission` | **0** ← anomalie F-8 |
| `presences` | 0 |
| `factures` | 0 |
| `factures` `PAYEE` | 0 |
| `contrats_service_signatures` | **0** ← anomalie F-7 |
| `contrats_travail_uploades` | 0 |

**Lecture** : la plateforme n'a **jamais** exécuté le workflow critique bout-en-bout (0 contrat, 0 presence, 0 facture). Le lancement commercial sera la première vraie mise à l'épreuve. Les P0 latents (F-1, F-11, F-12) doivent être corrigés AVANT le premier utilisateur réel.

---

## Annexe A — Couverture audit

| Étape workflow | Couverture |
|---|---|
| 1. Inscription étab | ✅ code + DB |
| 2. Création mission | ✅ code + DB (RLS) |
| 3. Inscription soignant | ✅ code (post-PR #66/#67/#68) |
| 4. Candidature soignant | ⚠️ code partiel + RPC `fn_postuler_mission` |
| 5. Confirmation par étab | ✅ RPC `fn_traiter_candidature` |
| 6. Génération contrat | ✅ via RPC `fn_generer_numero_contrat` + `fn_traiter_candidature` |
| 6b. Signature Yousign | ❌ callback manquant (F-11) |
| 7. DPAE | ⚠️ uniquement manuelle (F-12) |
| 8. Pointage GPS | ❌ `fn_pointer_depart` cassée (F-1) |
| 9. Validation présence | ✅ RPC + cron auto J+72h |
| 10. Facturation | ✅ Factur-X EN16931 BASIC, à valider mention 289 (F-17) |
| 11a. Paiement Stripe Connect | ✅ stripe-webhook robuste, balance_insufficient à mapper (F-15) |
| 11b. Paiement Chorus Pro | ✅ pré-dépôt en mode simulation OK |
| 12. Reversement soignant | ✅ webhook gère transfer + paiements_soignant |
| 13. Notifications | ⚠️ provider Resend à confirmer (F-20 du rapport agent) |

---

**Fin du rapport.** Aucun fix n'a été appliqué — uniquement diagnostic et listing. Attendre validation Gabrielle sur la priorisation avant d'ouvrir les PRs.
