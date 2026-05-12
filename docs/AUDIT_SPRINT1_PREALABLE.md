# Audit préalable Sprint 1 — Terminologie + restrictions + signature + DPAE + templates + cohérence frontend

> **Date** : 12 mai 2026
> **Périmètre** : audit en amont des PR 1-7 du Sprint 1 révisé. Pas de code. État des lieux pour permettre à Gabrielle de calibrer la séquence.
> **Méthode** : revue code + queries DB live (MCP Supabase) + lecture des migrations + audit des composants frontend.

---

## TL;DR — Ce qui existe déjà vs ce qui reste à construire

| Axe | État actuel | À faire | Effort |
|---|---|---|---|
| **0.1 Compatibilité prof × exercice × type étab** | `missionCompatibleContrat()` ne connaît que contrat ; rien sur type_etab | matrice complète à créer + ajout types CABINET_* | **L** |
| **0.2 Temps de travail** | REPOS_11H + PLAFOND_48H_HEBDO + MOYENNE_44H : foundation en place via triggers + composants UI | REPOS_HEBDO_35H absent ; travail nuit majorations absent ; UX messages à harmoniser | **M** |
| **0.3 CDDU → CDD** | 65 fichiers (.ts/.tsx/.sql/.md) + 2 valeurs enum DB (`CDDU`, `CDDU_USAGE`) + 1 template DB | refactor mécanique mais large | **L** |
| **0.4 Signature électronique** | Yousign + manuscrite canvas image, RPCs `fn_signer_contrat_*` existent ; **pas d'OTP** ; **pas de `yousign-callback`** | module signature avec OTP SMS à construire ex nihilo | **XL** |
| **0.5 DPAE** | Purement manuelle (`confirm-dpae` = bouton "c'est fait") | générer PDF pré-rempli + lien Net-Entreprises | **M** |
| **0.6 Templates contrats** | 2 templates HTML générique en DB (`CDDU` + `REMPLACEMENT_LIBERAL`), pas de différenciation profession ni type étab, pas de dossier markdown | ~25-30 templates markdown à rédiger | **XL** (rédaction) |
| **0.7 Conventions collectives** | Colonne `etablissements.convention_collective text` existe mais non pré-remplie ni utilisée par les templates | mapping `type_etab → CCN par défaut` + injection dans templates | **S** |

**Estimation globale Sprint 1 (PR 1 à 7)** : ~2-3 semaines de dev concentré.

---

## 0.1 — Compatibilité exercice × profession × type établissement

### État actuel

**`src/lib/constantes.ts`** :
- `PROFESSIONS` (15) : IDE, AS, AES, IBODE, IADE, SAGE_FEMME, KINE, MEDECIN, PHARMACIEN, MANIPULATEUR_RADIO, PREPARATEUR_PHARMA, DIETETICIEN, ERGOTHERAPEUTE, PSYCHOMOTRICIEN, ORTHOPHONISTE. **Manque** : DENTISTE (à ajouter), AUXILIAIRE_PUERICULTURE (à confirmer si scope).
- `CONTRATS` (4) : CDDU, VACATION, LIBERAL, SALARIE.
- `TYPES_ETABLISSEMENT` (11 côté front, 12 côté DB) : HOPITAL_PUBLIC, CLINIQUE_PRIVEE, EHPAD, SSIAD, HAD, CENTRE_SANTE, LABO, IME, MAS, FAM, PHARMACIE_OFFICINE. DB a `ESPIC` en plus. **Manque** : CABINET_MEDICAL, CABINET_DENTAIRE, CABINET_IDEL, CABINET_SAGE_FEMME, CABINET_KINE.
- `PROFESSIONS_NON_LIBERAL` : PHARMACIEN, PREPARATEUR_PHARMA, AS, AES, MANIPULATEUR_RADIO. **Manque IBODE, IADE, DIETETICIEN, ERGOTHERAPEUTE, PSYCHOMOTRICIEN** (les agents libéraux sont des sous-ensembles très spécifiques pour ces métiers — à confirmer).

**`missionCompatibleContrat(pref, typesContratSoignant)`** (ligne 106) :
```ts
if (pref === 'LIBERAL') return typesContratSoignant.includes('LIBERAL');
if (pref === 'SALARIE') return typesContratSoignant.some(t => ['CDDU', 'CDDU_USAGE', 'VACATION', 'SALARIE'].includes(t));
```
→ ne tient PAS compte du type_etablissement, ni de la profession. Un IDE libéral verrait techniquement toutes les missions LIBERAL.

**RPC `fn_soignant_compatible_mission`** existe (DB) — mirror dans `src/lib/profession-hierarchy.ts`. Audite la **profession** (matching hiérarchique : un IDE peut prendre une mission IDE, IBODE peut prendre une mission IDE, etc.). Ne tient PAS compte du type_etablissement.

**`etablissements.type`** est un enum DB. **`soignants.type_exercice`** est un text default `SALARIE` (cf finding F-6 de l'audit précédent : non persisté par `register-soignant`).

**Aucune fonction `peut_exercer(profession, type_exercice, type_etablissement)`** n'existe — ni côté DB ni côté front. La matrice à 3 dimensions n'est pas modélisée.

### Conclusion 0.1

- ❌ **Le piège Mediflash est ouvert** : un IDE qui se déclare libéral peut techniquement candidater à une mission `LIBERAL` en EHPAD privé ou clinique privée, ce qui est juridiquement requalifiable en salariat déguisé (Conseil d'État 11/02/2025).
- ❌ **5 nouveaux types d'établissement** à créer (CABINET_*).
- ❌ **Le `type_exercice` du soignant n'est pas collecté à l'inscription** (déjà signalé F-6) — sans cette donnée, aucune matrice ne sera applicable.
- ✅ Foundation de **profession hierarchy** + `missionCompatibleContrat` réutilisable.

---

## 0.2 — Temps de travail légal

### État actuel

**Table `conformite_travail`** existe avec colonnes `type_controle`, `resultat`, `details_violation jsonb`, `derogation_par`, `motif_derogation`. RLS : INSERT/UPDATE/DELETE deny pour anon et authenticated → uniquement triggers internes peuvent écrire.

**Triggers SQL existants** (migrations `20260317183608` puis `20260416190300_cp5b_triggers_effectif_previsionnel.sql`) :
- `dec_verifier_plafond_48h` : INSERT row `PLAFOND_48H_HEBDO` (VIOLATION_BLOQUEE ou CONFORME) à chaque assignation
- `dec_verifier_repos_11h` : idem pour `REPOS_11H`

**`type_controle` connus** :
- `REPOS_11H` ✅ — couvert
- `PLAFOND_48H_HEBDO` ✅ — couvert
- `MOYENNE_44H_12_SEMAINES` — apparaît dans `CarteConformite.tsx` (UI) **mais aucun trigger SQL trouvé** qui calcule la moyenne glissante 12 semaines. **À implémenter**.
- `REPOS_HEBDO_35H` ❌ — non trouvé
- Travail de nuit + majorations ❌ — non trouvé

**Composants frontend UX existants** :
- `BlocConformite.tsx` : affiche statut repos 11h + plafond 48h temps réel avant candidature
- `CompteurHebdomadaire.tsx` : compteur hebdo (X / 48h)
- `CarteConformite.tsx` : labels FR pour les 3 type_controle
- `ConformiteSoignant.tsx` : page dashboard conformité
- `BandeauRappelDPAE.tsx` : rappel DPAE étab (cf 0.5)

**RPC `fn_postuler_mission`** : à vérifier si elle invoque les triggers ou si elle a ses propres checks. Probablement les triggers `dec_verifier_*` se déclenchent à l'UPDATE missions (assignation), donc déjà en place.

### Conclusion 0.2

- ✅ Foundation solide : 80% du chantier est déjà fait (REPOS_11H + PLAFOND_48H_HEBDO côté backend + UI).
- ⚠️ **MOYENNE_44H_12_SEMAINES** : libellé UI existe mais pas de trigger DB qui le calcule — à implémenter ou retirer du UI.
- ❌ **REPOS_HEBDO_35H** : absent — à ajouter.
- ❌ **Travail de nuit + majorations conventionnelles** : absent — à câbler via CCN (cf 0.7).
- ⚠️ Le brief Sprint 1 PR 3 voulait aussi "affichage agrégé côté étab" — pas trouvé, à construire ou rejeter le scope.

---

## 0.3 — Terminologie CDDU

### État actuel

**65 fichiers** contiennent les chaînes `CDDU` ou `cddu` :
- Code TS/TSX : ~30 (composants, pages, lib utilitaires : `constantes.ts`, `bulletin-paie-pdf.ts`, `cotisations-2026.ts`, `mock-data.ts`, `blog-data.ts`, FacturationEtablissement, ProfilSoignant, DetailMission, etc.)
- Migrations SQL : ~20
- Tests : `src/lib/__tests__/constantes.test.ts`
- Articles d'aide (migration `20260429170000_j22b_articles_aide_17_articles.sql`)
- Types Supabase générés : `src/integrations/supabase/types.ts`

**Enum DB `type_contrat`** : 5 valeurs `CDDU, CDDU_USAGE, VACATION, LIBERAL, SALARIE`. La valeur `CDDU_USAGE` semble legacy (vu une seule fois dans `missionCompatibleContrat`).

**Données live `templates_contrat`** :
- 1 template `type_contrat = 'CDDU'` (3259 chars HTML, h1 "CONTRAT DE TRAVAIL À DURÉE DÉTERMINÉE D'USAGE")
- 1 template `type_contrat = 'REMPLACEMENT_LIBERAL'` (2075 chars HTML)

**Données live `soignants.type_contrat`** : default `CDDU` côté DB. Les 26 soignants existants ont probablement tous `CDDU` par défaut.

**Données live `missions.type_contrat_applique`** : à vérifier — probablement majoritairement `CDDU` aussi.

### Effort refactor

Migration enum Postgres (renommage `CDDU` → `CDD`) :
- `ALTER TYPE type_contrat RENAME VALUE 'CDDU' TO 'CDD'` (PG 12+)
- Idem `CDDU_USAGE` → `CDD` ? Ou drop + remap ? Décision : **drop CDDU_USAGE** (legacy, 0 ou peu de rows à vérifier) **et renommer CDDU → CDD**
- Migrer `soignants.types_contrat_acceptes` (jsonb array) : `UPDATE soignants SET types_contrat_acceptes = replace(types_contrat_acceptes::text, '"CDDU"', '"CDD"')::jsonb`
- Migrer le template DB : update `type_contrat` à `CDD` + renommer dans le HTML "CDD d'Usage" → "CDD"

Refactor code :
- `constantes.ts` : `CDDU` → `CDD` dans `CONTRATS` (label "Contrat à Durée Déterminée (CDD)")
- `missionCompatibleContrat` : retirer `'CDDU', 'CDDU_USAGE'` et ajouter `'CDD'`
- 60+ fichiers à grep+replace mécanique (sed avec validation)
- Templates emails et SMS : check `send-email/index.ts` (no CDDU find vs mention)
- Articles blog/aide : 1 article migration `20260429170000` à patcher
- Mock data + tests : à mettre à jour

### Conclusion 0.3

- Refactor **L (1-2 jours)** mécanique mais large. Pas de surprise architecturale.
- ⚠️ Attention à `CDDU_USAGE` (enum value) : confirmer 0 row utilisateur avant drop, sinon plan de migration.
- Risque post-merge : oublier 1-2 endroits qui afficheront "CDD d'usage" — à valider via test unitaire + grep CI.

---

## 0.4 — Signature électronique

### État actuel

**Edge functions** :
- `yousign-create` : crée signature_request Yousign + ajoute signataires + activate
- **Pas de `yousign-callback`** (déjà signalé dans audit précédent F-11) → status `EN_ATTENTE_SIGNATURES` jamais mis à jour

**RPCs SQL existantes** :
- `fn_signer_contrat_soignant(p_contrat_id, p_signature_image)`
- `fn_signer_contrat_etablissement(p_contrat_id, p_signature_image)`
- `fn_signer_contrat_service(...)` — contrat-cadre Jolene étab

**Tables** :
- `contrats_mission` : colonnes `signature_soignant boolean`, `signature_soignant_le tz`, `signature_image_soignant text`, idem `_etablissement`, `signature_ip_soignant`, `signature_navigateur_soignant`, `mode_signature text`
- `signatures_yousign` : journal des signatures via Yousign
- `signatures_contrat_service` : signatures contrat-cadre Jolene étab (différent du contrat mission)
- **Pas de table `signatures_contrats` générique** avec OTP

**Frontend** :
- `src/pages/ContratMission.tsx` : flow dual = soit clic Yousign soit signature canvas image (`SignatureCanvas.tsx`)
- Composant `SignatureCanvas.tsx` : canvas tactile pour tracer signature → base64 image
- Composant `ChoixContratDialog.tsx` : dialog choix MIXTE (LIBERAL ou SALARIE) à candidature
- **Aucun composant OTP signature** existant

**OTP SMS** :
- `send-sms` existe (Twilio configuré)
- **Aucun flow OTP signature** : pas d'envoi OTP avant signature, pas de validation OTP au moment du signe

### Conclusion 0.4

- ❌ Le module signature actuel est **AES (signature avancée) faible** : juste un canvas image + IP + UA, sans 2FA. Pas conforme aux exigences eIDAS pour signature qualifiée mais OK pour signature simple/avancée v1.
- ❌ Yousign : créé mais callback manquant → contrats restent EN_ATTENTE_SIGNATURES à jamais (cf F-11 audit précédent).
- ✅ Stockage IP / UA / hash document : 80% en place via colonnes `contrats_mission.signature_ip_*` et `signature_navigateur_*`.
- ❌ **Hash SHA-256 du PDF au moment signature** : à vérifier — colonne `signature_image_*` stocke l'image mais pas un hash du document.

**Pour PR 4 (module signature OTP)** :
- Créer table `signatures_contrats` avec colonnes OTP (`otp_envoye_a, otp_valide_a, otp_code_hash`)
- Créer RPCs `fn_envoyer_otp_signature` + `fn_signer_contrat` (avec validation OTP)
- Créer edge fn `compute-document-hash` pour générer + hasher PDF
- Créer composant `<SignerContrat>` mutualisé soignant/étab
- Déprécier `yousign-create` (le garder fonctionnel pour contrats en cours seulement)

---

## 0.5 — DPAE

### État actuel

**Edge function** : `confirm-dpae` — endpoint POST manuel. L'établissement clique "j'ai fait la DPAE" → UPDATE `contrats_mission SET dpae_effectuee = true, dpae_effectuee_le = NOW()`.

**RPC SQL** : `fn_confirmer_dpae(p_contrat_id uuid)` (SECURITY DEFINER, confirmé en DB).

**Composants frontend** :
- `BandeauRappelDPAE.tsx` : affiche un rappel à l'étab dans le dashboard quand un contrat CDDU est signé sans DPAE confirmée

**Schéma `contrats_mission`** :
- `dpae_effectuee boolean`
- `dpae_effectuee_le tz`
- **Pas de colonne `dpae_numero text`** pour stocker le numéro retourné par URSSAF

**Aucune génération auto** :
- Pas d'appel API URSSAF / Net-Entreprises
- Pas de génération PDF DPAE pré-rempli
- Pas de stockage du formulaire DPAE en Supabase Storage
- Pas de mandat DPAE Jolene tracé (peut-être prévu dans le contrat-cadre Jolene étab mais à vérifier)

### Conclusion 0.5

- ❌ DPAE **purement déclarative** (l'étab confirme avoir fait → confiance aveugle). Risque URSSAF si étab oublie.
- Pour PR 6 (Option A pré-remplissage) :
  - Edge fn `dpae-auto` qui génère PDF DPAE pré-rempli (champs : SIRET étab, identifiants soignant, type contrat, dates, salaire)
  - Stockage Storage `dpae/{contrat_id}.pdf`
  - Lien copy-paste vers `net-entreprises.fr/dpae`
  - Ajouter colonne `contrats_mission.dpae_numero text`
- Option B (API URSSAF tiers déclarant) hors scope Sprint 1 — agrément long à obtenir.

---

## 0.6 — Templates contrats

### État actuel

**Stockage** : table DB `templates_contrat` avec colonnes :
- `id uuid pk`
- `type_contrat text` (CDDU / REMPLACEMENT_LIBERAL)
- `nom text` (libellé humain)
- `contenu_html text` (HTML avec placeholders mustache `{{etablissement_nom}}`)
- `variables jsonb` (liste des placeholders attendus)
- `version int`
- `est_actif boolean`

**Contenu actuel** :
- 1 template `CDDU` (3259 chars HTML, h1 "CONTRAT DE TRAVAIL À DURÉE DÉTERMINÉE D'USAGE")
- 1 template `REMPLACEMENT_LIBERAL` (2075 chars HTML, h1 "CONTRAT DE REMPLACEMENT LIBÉRAL")

**Génération** :
- Migration `20260420161000_e16_b_traiter_candidature.sql` : `SELECT contenu_html INTO v_html FROM templates_contrat WHERE type_contrat = ...` puis substitue les variables et insère dans `contrats_mission.contenu_html`
- 2 templates **génériques** — pas de variation par profession ni par type d'établissement

**Pas de dossier** `contrats-templates/` au filesystem — tout est en DB.

### Conclusion 0.6

- ⚠️ **2 templates trop génériques pour la conformité juridique**. Le brief Sprint 1 PR 5 demande ~25-30 templates (1 CDD par profession × 1 libéral par profession × type étab compatible).
- Migration approche markdown vs HTML :
  - **Option A** : garder DB `templates_contrat`, ajouter ~25 rows. Simple, déploiement via migration SQL.
  - **Option B** : dossier `contrats-templates/*.md` lu au build (Vite import.meta.glob) ou par une edge function `get-template`. Plus éditable mais nécessite refactor de `fn_traiter_candidature`.
- **Décision recommandée** : Option A (DB) à court terme = pas de refactor. Markdown converti en HTML au seed des templates via une migration.
- **Effort de rédaction** : très lourd. 25-30 templates × 800-2000 chars × défense juridique = **XL**. Acceptable pour Sprint 1 si Claude écrit les premières versions sans validation avocat (décision Gabrielle assumée).

---

## 0.7 — Conventions collectives

### État actuel

**Colonne `etablissements.convention_collective text`** : existe en DB.

**Pré-remplissage automatique selon `type_etablissement`** : **aucun trouvé**. Les 21 établissements actuels ont probablement tous `convention_collective = NULL`.

**Utilisation dans le code** :
- Référencée dans `src/lib/bulletin-paie-pdf.ts` (pour le bulletin de paie)
- `src/pages/ProfilEtablissement.tsx` : champ probablement éditable manuellement
- Migrations RPC `fn_mon_etablissement_complet_joins` la sélectionne

**Mapping standard `type_etab → CCN par défaut`** :
- HOPITAL_PUBLIC → FPH (Fonction Publique Hospitalière) — décret 91-155
- ESPIC, CLINIQUE_PRIVEE → FHP-CCN51 (Fédération Hospitalière Privée) ou CCN66 selon
- CLINIQUE_PRIVEE → CCN du 18/04/2002 (FHP)
- EHPAD privé non lucratif → CCN 1951 (FEHAP) ou CCN 66 (SYNEAS)
- EHPAD commercial → SYNERPA (CCN 26/08/2010)
- SSIAD, HAD → variable selon statut
- CENTRE_SANTE → CCN 23/03/1990

(Mapping indicatif — la liste exhaustive serait une table de référence à part).

### Conclusion 0.7

- ✅ Colonne en place — pas besoin de migration DDL.
- ❌ Pas de pré-remplissage automatique → toutes les conventions collectives sont vides en pratique.
- ❌ Pas d'injection dans les templates contrats (cf 0.6) — un CDD généré actuellement n'aura pas la CCN applicable, ce qui est **non conforme art. L1242-12** (mention obligatoire).
- Pour PR 5 (templates contrats) : il faut un mapping `type_etab → CCN par défaut` injecté dans le template CDD. L'étab pourra surcharger via son profil.

---

## Annexe — Types d'établissement DB vs Frontend (décalage)

| valeur | Frontend | DB enum |
|---|---|---|
| HOPITAL_PUBLIC | ✓ | ✓ |
| CLINIQUE_PRIVEE | ✓ | ✓ |
| EHPAD | ✓ | ✓ |
| SSIAD | ✓ | ✓ |
| HAD | ✓ | ✓ |
| CENTRE_SANTE | ✓ | ✓ |
| LABO | ✓ | ✓ |
| IME | ✓ | ✓ |
| MAS | ✓ | ✓ |
| FAM | ✓ | ✓ |
| PHARMACIE_OFFICINE | ✓ | ✓ |
| **ESPIC** | ❌ | ✓ |
| CABINET_MEDICAL | ❌ | ❌ |
| CABINET_DENTAIRE | ❌ | ❌ |
| CABINET_IDEL | ❌ | ❌ |
| CABINET_SAGE_FEMME | ❌ | ❌ |
| CABINET_KINE | ❌ | ❌ |

→ PR 2 doit ajouter les 5 CABINET_* aux 2 endroits + corriger l'oubli ESPIC frontend.

---

## Estimation effort PR 1-7

| PR | Description | Effort | Risque |
|----|---|---|---|
| **PR 1** | CDDU → CDD : refactor 65 fichiers + migration enum + migration data + tests | **L (1-2j)** | Faible (mécanique). Attention à `CDDU_USAGE` legacy à droper. |
| **PR 2** | Compatibilité prof × exercice × type_étab : 5 nouveaux types_etab + RPC `peut_exercer` + ajout DENTISTE profession + matrice + double frontend (UI désactivation + UI message) + checks RPCs `fn_publier_mission`, `fn_postuler_mission` | **L (1-2j)** | Moyen. Décisions juridiques à valider pour les cases borderline (orthophoniste libéral en cabinet ortho ?). |
| **PR 3** | Temps de travail : compléter `MOYENNE_44H_12_SEMAINES` (trigger SQL) + ajouter `REPOS_HEBDO_35H` + travail de nuit majorations selon CCN + double frontend (UI agrégé étab) | **M (4-8h)** | Faible. Foundation déjà solide. |
| **PR 4** | Module signature OTP : table `signatures_contrats`, RPCs `fn_envoyer_otp_signature` + `fn_signer_contrat`, edge fn `compute-document-hash`, composant `<SignerContrat>` (PDF + OTP + 2FA SMS), page admin `/admin/contrats/[id]/signatures`, déprécation Yousign | **XL (>2j)** | Élevé. Module ex nihilo. Validation flow E2E nécessaire. |
| **PR 5** | Templates contrats : ~25-30 templates markdown CDD par profession + libéral par profession × type étab compatible. Migration seed DB. | **XL (>2j)** | Moyen. Effort de rédaction juridique pur. Pas de validation avocat assumée. |
| **PR 6** | DPAE auto Option A : edge fn `dpae-auto`, PDF pré-rempli, stockage Storage, ajout colonne `dpae_numero`, composant UI étab "Télécharger DPAE pré-remplie + lien Net-Entreprises" | **M (4-8h)** | Faible. Mécanique. |
| **PR 7** | Workflow post-signature : `fn_accepter_candidature` enchaîne `peut_exercer` + conformité travail + génération contrat + emails CONTRAT_A_SIGNER + post-signature trigger DPAE | **M (4-8h)** | Moyen. C'est l'intégration des PR précédentes. |

**Total** : ~13-16 jours-dev concentré (≈3 semaines avec coordination, revue, tests).

---

## Plan de bataille proposé

### Phase A (semaine 1) — fondations
1. **PR 1** (CDDU → CDD) → préalable obligatoire car bloque migration enum DB et confond la terminologie partout
2. **PR 2** (compatibilité prof × exercice × type_étab) → débloque le piège Mediflash, mais dépend de F-6 audit précédent (collecte `type_exercice` à l'inscription) qu'il faut faire en même temps
3. **PR 3** (temps travail) → léger, peut se faire en parallèle PR 2

### Phase B (semaine 2) — signature + templates
4. **PR 4** (module signature OTP) → préalable pour PR 7
5. **PR 5** (templates contrats) → en parallèle de PR 4 (pas de dépendance technique)

### Phase C (semaine 3) — intégration
6. **PR 6** (DPAE auto Option A) → léger
7. **PR 7** (workflow post-signature) → intégration finale, nécessite PR 1-6 mergées

### Recommandations transverses

- **Pré-merge PR 1** : confirmer avec Gabrielle qu'aucun client / partenaire externe n'a hard-codé "CDDU" dans une intégration (Defacto, Stripe metadata, Chorus, etc.) — risque rupture API
- **Pré-merge PR 2** : décider du sort des soignants existants avec `type_exercice = 'SALARIE'` par défaut (forcer re-confirmation à la prochaine connexion ? laisser tel quel ?)
- **PR 4** : décider du provider OTP (Twilio existant) vs un service dédié (Telesign, Sinch) — Twilio suffit
- **PR 5** : prévoir une réserve "validation avocat" budget 2k€ post-launch quand traction démontrée

---

## À valider par Gabrielle avant de lancer PR 1

1. **Périmètre PROFESSIONS** : ajouter `DENTISTE` ? `AUXILIAIRE_PUERICULTURE` ?
2. **Sort de `CDDU_USAGE`** : si 0 rows en utilisation → drop. Confirmer.
3. **Matrice 0.1** : les cases borderline (orthophoniste libéral, ergothérapeute libéral, psychomotricien libéral) à inclure ou non dans PR 2 v1 ? Recommandation : exclure de v1, ajouter dans Sprint 2.
4. **Mapping CCN par défaut** : valider la table type_etab → CCN proposée (cf 0.7) ou fournir une table autoritaire.
5. **Validation juridique templates** : Claude rédige les v1 sans avocat. Confirmer.
6. **Yousign legacy** : combien de contrats sont actuellement EN_ATTENTE_SIGNATURES via Yousign en prod ? Query DB confirme **0 contrat tout court** actuellement → on peut sereinement déprécier Yousign sans migration.

---

**Fin de l'audit.** Attente du feu vert Gabrielle pour démarrer PR 1.
