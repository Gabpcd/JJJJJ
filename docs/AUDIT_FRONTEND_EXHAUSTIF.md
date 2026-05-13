# AUDIT FRONTEND EXHAUSTIF — Sprint 5

> **Phase 1 — Diagnostic pur.** Aucun fix appliqué. Base de travail pour les Sprints 5.5 / 5.7 / 6 / 7.
> **Date :** 2026-05-13
> **Périmètre :** 103 pages, 209 composants (hors `ui/`), 369 RPCs, 27 pages admin, ~140 routes.
> **Méthode :** Lecture systématique du code + cross-référence RPCs définies vs utilisées en front. Pas de supposition, evidence au format `fichier:ligne`.

---

## Table des matières

1. [Tableau général synthétique (63 sections)](#section-1--tableau-général-synthétique)
2. [Détail par section](#section-2--détail-par-section)
3. [Synthèse priorisée (P0 / P1 / P2)](#section-3--synthèse-priorisée)
4. [Estimation d'effort & découpage en sprints](#section-4--estimation-deffort)
5. [Recommandations stratégiques](#section-5--recommandations-stratégiques)
6. [Annexes — RPCs orphelines, bugs critiques identifiés](#section-6--annexes)

---

## SECTION 1 — Tableau général synthétique

Légende : ✅ OK et intuitif (UX 4-5) · ⚠️ Friction (UX 2-3, fonctionnel mais améliorable) · ❌ Manquant, cassé, ou non intuitif

### Côté SOIGNANT

| # | Section | Verdict | Priorité fix |
|---|---|---|---|
| 1 | Inscription (RPPS temps réel, email/MDP, PSC) | ✅ (4/5) | P2 |
| 2 | Connexion / reset password / PSC login | ✅ (4.3/5) | P2 |
| 3 | Onboarding post-inscription | ⚠️ (3/5) | **P1** |
| 4 | Profil soignant (identité, docs, DPAE, préférences) | ✅ (4/5) | **P1** (NIR manquant) |
| 5 | Recherche missions (filtres, restrictions visibles) | ⚠️ (4/5) | P2 (Mediflash invisible) |
| 6 | Candidatures (annulation 30 min Sprint 3.5) | ❌ (2/5) | **P0** |
| 7 | Contrats (SignerContratOtp, certificat) | ✅ (4/5) | P2 |
| 8 | Pointage Sprint 4.5 (QR/GPS/Code) | ✅ (5/5) | P2 |
| 9 | Missions en cours | ⚠️ (3/5) | P2 |
| 10 | Missions terminées (évaluation post-mission) | ❌ (3/5) | **P1** |
| 11 | Évaluations reçues (page dédiée) | ❌ (2/5) | **P1** |
| 12 | Score Jolene Sprint 3.5 (3 composantes + réclamation) | ⚠️ (4/5) | **P0** (bug modale legacy) |
| 13 | Fiches de paie CDD | ✅ (5/5) | — |
| 14 | Factures libéral Factur-X | ✅ (5/5) | — |
| 15 | Versements perçus (factor Voie A) | ✅ (5/5) | — |
| 16 | DPAE (page dédiée, n° URSSAF) | ❌ (2/5) | **P1** |
| 17 | Messagerie | ✅ (5/5) | — |
| 18 | Litiges (FormulaireAccord Sprint 3.5) | ✅ (5/5) | — |
| 19 | Notifications (centre + préférences) | ✅ (4/5) | P2 |
| 20 | Paramètres (page unifiée, password) | ⚠️ (3/5) | **P0** |

### Côté ÉTABLISSEMENT

| # | Section | Verdict | Priorité fix |
|---|---|---|---|
| 21 | Inscription étab (SIRET + KBIS) | ⚠️ (3/5) | **P1** |
| 22 | Profil étab (tolérance GPS Sprint 4.5 éditable) | ❌ (4/5) | **P0** |
| 23 | Équipe étab multi-utilisateurs | ❌ (2/5) | **P0** |
| 24 | Dashboard étab | ✅ (4.5/5) | — |
| 25 | Création mission (récap, QR auto) | ⚠️ (3.5/5) | **P1** |
| 26 | Liste missions + annulation (4 buckets Sprint 3.5) | ⚠️ (4/5) | **P0** |
| 27 | Candidatures reçues (score breakdown) | ✅ (4/5) | P2 |
| 28 | Contrats (SignerContratOtp + DPAEStatus) | ✅ (4.5/5) | P1 (countdown 72h) |
| 29 | Pointage suivi (alertes Sprint 4.5) | ⚠️ (3.5/5) | **P1** |
| 30 | RH (mois courant/prévisionnel) | ✅ (4/5) | P2 |
| 31 | Facturation (Stripe + Chorus) | ✅ (4/5) | P2 |
| 32 | Obligations financières consolidées | ❌ (2/5) | **P0** |
| 33 | Évaluer soignants (étab → soignant) | ❌ (0/5) | **P0** |
| 34 | Litiges Sprint 3 + 3.5 | ⚠️ (3.5/5) | **P1** |
| 35 | Score étab Sprint 3.5 | ⚠️ (3.5/5) | **P1** |
| 36 | Préférences notifications, paramètres | ✅ (4/5) | P2 |

### Côté ADMIN JOLENE

| # | Section | Verdict | Priorité fix |
|---|---|---|---|
| 37 | Dashboard admin (KPIs + alertes Sprint 4.5) | ⚠️ (3/5) | **P1** |
| 38 | Utilisateurs (liste + suspension via détail) | ✅ (4/5) | P2 |
| 39 | Missions globales (peu d'actions) | ⚠️ (3/5) | P2 |
| 40 | Contrats consultation hash | ❌ (2/5) | **P0** |
| 41 | Litiges admin + médiation | ✅ (4.5/5) | P2 (AdminLitiges + AdminModeration doublon) |
| 42 | Factures/paiements | ✅ (4/5) | — |
| 43 | Réclamations score Sprint 3.5 | ✅ (4.5/5) | — |
| 44 | Externalisations actions Sprint 4 | ✅ (3.5/5) | — |
| 45 | Healthcheck (10 services) | ✅ (4.5/5) | — |
| 46 | Chorus Pro | ✅ (4/5) | — |
| 47 | Score management (page centralisée) | ⚠️ (3/5) | P2 |
| 48 | Journaux audit | ✅ (4/5) | P1 (alertes anti-triche pas remontées) |
| 49 | Audit RLS page admin | ❌ (0/5) | **P1** |
| 50 | Templates contrats UI admin | ❌ (1/5) | **P0** |
| 51 | Outils RGPD (admin batch) | ⚠️ (4.5/5) | P2 |
| 52 | Alertes pointage Sprint 4.5 | ❌ (2/5) | **P0** |
| 53 | Statistiques business | ✅ (4.5/5) | — |

### Workflows TRANSVERSAUX

| # | Section | Verdict | Priorité fix |
|---|---|---|---|
| 54 | Inscription multi-étapes (progression) | ✅ (4.5/5) | — |
| 55 | Vérification email + téléphone | ⚠️ (3.5/5) | **P1** (SMS OTP manquant) |
| 56 | Récupération mot de passe | ✅ (4.5/5) | P2 (resend email) |
| 57 | Onboarding premier login | ⚠️ (4/5) | P2 |
| 58 | Suppression compte RGPD | ✅ (4.5/5) | — |
| 59 | Export données RGPD (JSON/CSV) | ✅ (4.5/5) | — |
| 60 | Préférences notifications granulaires | ✅ (4.5/5) | — |
| 61 | Mode sombre / dark mode | ✅ (4.5/5) | — |
| 62 | Internationalisation (i18n) | ❌ (n/a) | P3 (français-only by design) |
| 63 | Accessibilité (RGAA 4.1 AA) | ✅ (4/5) | P2 (sous-titres vidéos tuto) |

### Synthèse globale

- **63 sections auditées**
- **40 sections ✅** (63%)
- **15 sections ⚠️** (24%)
- **8 sections ❌** (13%)
- **13 sections en priorité P0** (blocants workflow critique)
- **15 sections en priorité P1** (frictions importantes)
- **15 sections en priorité P2** (cosmétique / améliorations)

---

## SECTION 2 — Détail par section

### 1. Inscription soignant — ✅ (4/5)

- **Pages** : `src/pages/InscriptionSoignant.tsx` (545 l.), `InscriptionSoignantCompletion.tsx` (316 l.)
- **RPCs/edges** : `register-soignant`, `verify-rpps`, `psc-authorize`
- **Forces** :
  - RPPS validation temps réel via `verify-rpps` (`InscriptionSoignant.tsx:193-274`) avec FHIR (specialite_code, profession_api).
  - PSC bouton intégré (`L347-358`) avec ModalePscPreAuth.
  - Captcha Turnstile (`L517`), jauge force MDP, validation CGU.
  - Pré-remplissage prenom/nom si RPPS trouvé (`L251-256`).
- **Frictions** :
  - Documents (CNI, RPPS, justificatifs) **NON uploadés à l'inscription** — séparé dans `/soignant/documents` post-inscription.
  - Pas d'**OTP SMS** : téléphone validé par regex uniquement (`L430`).
  - Brouillon serveur absent (sessionStorage email seulement).
- **Priorité** : P2 (2j, OTP SMS optionnel)

### 2. Connexion / reset / PSC — ✅ (4.3/5)

- **Pages** : `PageConnexion.tsx`, `PageResetPassword.tsx`, `PscCallback.tsx`
- **RPCs** : `fn_get_my_role`, `fn_audit_connexion`, edges `psc-authorize` / `psc-callback` / `psc-logout`
- **Forces** :
  - Biométrie native (`L214-223`), Captcha (`L205`), fallback PSC e-CPS.
  - Password reset : détection `PASSWORD_RECOVERY` event (`L28`) + fallback hash (`L34`).
  - PSC callback pédagogique (`PscCallback.tsx:130-140`).
- **Frictions** : `ConfirmerEmail.tsx` statique — pas de bouton "Renvoyer email" (Supabase 24h expire).
- **Priorité** : P2 (1j resend email)

### 3. Onboarding post-inscription — ⚠️ (3/5)

- **Page** : `InscriptionSoignantCompletion.tsx` (316 l.)
- **Forces** : Stepper visuel 4 étapes, validation formValide robuste.
- **Frictions** :
  - **Aucun tutoriel / tour interactif**. Pas de tooltip d'aide sur champs critiques (rayon, types contrat).
  - **DPAE Sprint 2 absente de l'onboarding** (décalée vers `/profil` post-documents).
  - Double-acceptation CGU (déjà acceptée en inscription, `L289-300`).
- **Composant** `OnboardingGuide.tsx` existe avec `STORAGE_KEY='onboarding_complete'` (`L30`) mais semble peu utilisé.
- **Priorité** : **P1** (3-4j tutoriel + intégrer DPAE)

### 4. Profil soignant — ✅ (4/5)

- **Page** : `ProfilSoignant.tsx` (511 l.) avec 5 sections :
  - `SectionProfilPrincipal.tsx` (identité, RPPS, type exercice)
  - `SectionPaiements.tsx` (mandat facturation)
  - `SectionPreferences.tsx` (bio, spécialités, taux, rayon, pool urgence, **GPS toggle**, SMS toggle)
  - `SectionDpaeIdentite.tsx` (sexe, lieu naissance, nationalité Sprint 2)
  - `SectionConfidentialite.tsx` (suppression compte + export RGPD)
- **RPCs branchées** : `fn_modifier_mon_profil`, `fn_soignant_dpae_complet`, `fn_maj_infos_dpae`, `fn_supprimer_compte_rate_limited`, `fn_rgpd_exporter_rate_limited`
- **Frictions** :
  - **NIR (numéro sécurité sociale) absent du UI** alors qu'il est dans `listManquant()` (`SectionDpaeIdentite.tsx:226`). DPAE est listée incomplète mais on ne peut pas saisir le champ depuis le front.
  - **Mandat facturation** : statut affiché mais **aucun upload/signature UI**.
  - **Changement mot de passe** : aucune interface (manque P0 transversal).
  - Avatar : `AvatarUpload.tsx` présent mais à vérifier si exposé dans cette page.
- **Composant `ConsentementPingGps.tsx` (Sprint 4.5 PR 10) créé** mais non intégré dans SectionPreferences (le toggle GPS existant est plus simple — non lié au consentement ping background).
- **Priorité** : **P1** (1j NIR + 1.5j mandat upload)

### 5. Recherche missions — ✅ (4/5)

- **Page** : `RechercheMissions.tsx` (508 l.)
- **Composant** : `CarteMissionSoignant.tsx`
- **Filtres** : profession, type étab (hiérarchie), type contrat, distance/rayon, salaire min, dates, type exercice. Filtres sauvegardés (`L311-333`).
- **Frictions** :
  - **Restrictions Mediflash** : matrice `LIBERAL_COMPATIBILITY` (`constantes.ts:73-84`) appliquée backend mais **AUCUNE UI** explicative pour le soignant. Mission filtrée disparaît sans message.
  - **Travail de nuit + majoration CCN** : calculé backend, badges affichés mais montant majoré pas détaillé en liste.
- **Priorité** : P2 (2.5j Mediflash banner + majorations breakdown)

### 6. Candidatures + annulation — ❌ (2/5) **P0**

- **Page** : `DetailMissionSoignant.tsx` (735 l.)
- **RPC** : `fn_postuler_mission` (`L174`) ✅, `fn_annuler_candidature_soignant` **non branchée** côté UI.
- **Frictions CRITIQUES (Sprint 3.5)** :
  - **Fenêtre rétractation 30 min ABSENTE du front**. Aucun composant timer, aucun bouton "Annuler ma candidature".
  - **Conséquences score INVISIBLES**. Le brief annulation Sprint 3.5 grille soignant : 12-24h=-5, 1-12h=-10, ASAP<2h=-25 — aucun affichage front.
  - RPC backend `fn_annuler_candidature_soignant` existe mais **non utilisée en front** (cf. annexe RPCs orphelines).
- **Priorité** : **P0** (2j composant `AnnulationCandidatureTimer` + modale conséquences)

### 7. Contrats + signature OTP — ✅ (4/5)

- **Pages** : `ContratMission.tsx`, `CertificatSignaturePage.tsx`
- **Composants** : `SignerContratOtp.tsx` (294 l.), `DPAEStatus.tsx`, `BlocContratTravailMission.tsx`
- **Cross-référencé** : `SignerContratOtp` **EST** intégré dans `ContratMission.tsx:620-633` (la "dette critique Sprint 2" du brief est **résolue**).
- **Forces** :
  - RPCs `fn_envoyer_otp_signature`, `fn_signer_contrat_otp` branchées.
  - Anti-abus 3 SMS/24h, 5 tentatives OTP, expiration 10 min (backend).
  - Hash SHA-256 réel via Web Crypto API.
  - Certificat exportable PDF jsPDF (`CertificatSignaturePage.tsx:153`).
  - Audit trail IP/UA/hash/OTP/RPPS/PSC.
- **Frictions** :
  - Hash visuel partiel (8+4 chars) — manque copier-coller full hash.
  - Mode Yousign legacy encore exposé (`L634-644`) → confusion possible.
  - **Pas de countdown 72h** pour expiration signature.
- **Priorité** : **P1** (2j countdown 72h + désactiver Yousign legacy)

### 8. Pointage Sprint 4.5 — ✅ (5/5)

- **Page** : `PresencesSoignant.tsx`
- **Composants** : `CartePointage.tsx` (refondue PR 12), `ScannerQRPointageSoignant.tsx` (PR 6), `SaisieCodeSecours.tsx` (PR 9), `ConsentementPingGps.tsx` (PR 10), `BoutonPointage.tsx` (GPS legacy)
- **Hiérarchie respectée** :
  1. **QR (recommandé)** — bouton principal large 1 tap (`CartePointage.tsx:119-134`)
  2. **GPS + Code secours** — grille 50/50
  3. **Indicateur file offline** quand queue non vide
- **RPCs** : `fn_valider_scan_qr`, `fn_valider_code_secours`, `fn_pointer_arrivee`, `fn_pointer_depart`, `fn_consentir_gps`, `fn_enregistrer_pings_gps`.
- **Frictions mineures** :
  - Modal `ConsentementPingGps` accessible mais non lié à un toggle visible dans `SectionPreferences` (le toggle GPS actuel est différent du ping background Sprint 4.5).
  - Tolerance GPS affichée fixe (500m feedback) mais valeur réelle dépend de `etablissements.tolerance_gps_metres` (variable).
- **Priorité** : P2 (1j wiring consentement ping GPS dans paramètres soignant)

### 9. Missions en cours — ⚠️ (3/5)

- **Page** : `MissionsSoignant.tsx` (onglet "Mes missions" + `PresencesSoignant.tsx`)
- **Frictions** :
  - **Pas d'action "Ouvrir litige" sur missions en cours** (uniquement en historique).
  - **Statut paiement non affiché** en cours (pas de net estimé visible).
- **Priorité** : P2 (1.5j)

### 10. Missions terminées + évaluation — ❌ (3/5) **P1**

- **Page** : `HistoriqueMissions.tsx`
- **Frictions** :
  - **`BoutonNoterMission` existe mais jamais affiché dans HistoriqueMissions** — seulement dans le détail mission TERMINEE+ASSIGNE.
  - Litige depuis historique = simple navigation vers détail, **pas de wizard ouverture litige**.
- **Priorité** : **P1** (1.5j déplacer évaluation + 2j wizard litige)

### 11. Évaluations reçues — ❌ (2/5) **P1**

- **Composant** : `NotationsRecues.tsx` embarqué dans `ProfilSoignant.tsx:280-298` (top 5 seulement via `.slice(0,5)`).
- **Frictions** :
  - **Aucune page dédiée `/soignant/evaluations`**.
  - Pas de filtres (établissement, période, note min/max).
- **RPC** : `fn_mes_evaluations_recues` exposée mais limitée à 5 résultats côté UI.
- **Priorité** : **P1** (2j page dédiée + filtres)

### 12. Score Jolene Sprint 3.5 — ⚠️ (4/5) **P0 (bug)**

- **Page** : `PageScoreSoignant.tsx` (154 l.)
- **Composants** : `BreakdownScore.tsx` (6 composantes visibles ✅), `GraphiqueEvolutionScore.tsx`, `NotationsRecues.tsx`
- **Forces** :
  - 6 composantes pondérées affichées : notation 35% + présentéisme 20% + ponctualité 15% + réactivité 10% + ancienneté 10% + vous notez les étabs 10%.
  - Niveaux BRONZE/ARGENT/OR/PLATINE, période probatoire.
  - Bouton "Contester une pénalité" (`L128-130`).
- **BUG CRITIQUE P0** identifié :
  - `PageScoreSoignant.tsx:13` importe `ModalReclamationScore` (vieux composant) au lieu de `score/ModaleReclamationScore` (Sprint 3.5).
  - **Conséquence** : Le bouton "Contester" appelle l'ancien composant qui fait un `INSERT direct dans reclamations_scoring` (`ModalReclamationScore.tsx:74-81`), **PAS** la RPC `fn_creer_reclamation_score`. Le workflow admin Sprint 3.5 (`/admin/reclamations-score` PENDING/TRAITEE) est **contourné**.
- **Page "Mes réclamations"** :
  - Route `/soignant/reclamations` redirige vers `/soignant/litiges?tab=reclamations` (`App.tsx:214`).
  - Onglet `MesReclamations.tsx` appelle `fn_soumettre_reclamation` (legacy) — **incohérent** avec Sprint 3.5.
- **Priorité** : **P0** (0.5j fix import + 0.5j corriger MesReclamations pour utiliser RPCs Sprint 3.5)

### 13. Fiches de paie CDD — ✅ (5/5)

- **Page** : `BulletinsPaie.tsx` (250 l.) — RPC `fn_mes_bulletins_paie`, filtres statut/année, KPIs brut/net/cotisations, téléchargement PDF via `telechargerBulletinPaiePdf`.

### 14. Factures libéral Factur-X — ✅ (5/5)

- **Page** : `MesFacturesHonoraires.tsx` (296 l.)
- Téléchargement PDF Factur-X (`telechargerFactureHonorairesPDF`), filtres statut/année/mois, KPIs facturé/encaissé/attente, **ModalCessionCreance** factor Voie A intégrée, statut mandat facturation visible.

### 15. Versements factor Voie A — ✅ (5/5)

- **Page** : `MesAvances.tsx` (150 l.) — RPC `fn_mes_avances_factor`, statuts DEMANDEE/EN_ANALYSE/APPROUVEE/FINANCEE/RECOUVREE/REJETEE/IMPAYEE.

### 16. DPAE soignant — ❌ (2/5) **P1**

- **Friction** :
  - **Aucune page dédiée `/soignant/dpae`**.
  - `SectionDpaeIdentite.tsx` permet de remplir les champs identité DPAE mais ne montre PAS les DPAE générées (numéro URSSAF, date transmission, statut).
- **Composant DPAEStatus.tsx** existe mais réservé côté étab (`ContratMission.tsx:494`).
- **Priorité** : **P1** (2j page `/soignant/dpae` listant DPAE par mission + n° URSSAF)

### 17. Messagerie soignant — ✅ (5/5)

- **Page** : `PageMessagerie.tsx` (500+ l.) — conversations par mission, unread badge, realtime via Supabase channel.

### 18. Litiges Sprint 3 + 3.5 — ✅ (5/5)

- **Pages** : `LitigesSoignant.tsx` (282 l.) + `LitigesContestationsSoignant.tsx` (47 l., wrapper avec onglets)
- **Composants** : `FilDiscussionLitige.tsx`, `FormulaireAccord.tsx`, `TimelineLitige.tsx`, `BoutonsActionLitige.tsx`
- **FormulaireAccord** intègre 6 types modifications Sprint 3.5 : HORAIRES, MONTANT, ANNULATION_TOTALE, COMPENSATION_PARTIELLE, MIXTE, ACCORD_SANS_MODIFICATION.

### 19. Notifications soignant — ✅ (4/5)

- **Pages** : `PageNotifications.tsx` (142 l.), `PageParametresNotifications.tsx` (200+ l.)
- Centre in-app avec realtime, filtres (Toutes/Missions/Documents/Finance/Système), suppression lues, préférences par canal (EMAIL/SMS/PUSH/IN_APP) × type d'événement (12+ soignant, 8+ étab).
- **Push web FCM/APNS** Sprint 4 : géré côté backend via send-push + `tokens_push`, integration native via `pushNative.ts` (`isNative()`).
- **Priorité** : P2 (distinction visuelle types notifications dans fil)

### 20. Paramètres soignant — ⚠️ (3/5) **P0**

- **Frictions** :
  - **Aucune page parente `/soignant/parametres`** — uniquement sous-routes `/soignant/parametres/notifications`, `/soignant/parametres/recherches-sauvegardees`.
  - **Aucune interface changement mot de passe** (Supabase `updateUser({password})` doit être branchée).
  - **Toggle ping GPS background Sprint 4.5** non exposé en paramètres (consentement existe via `ConsentementPingGps` mais pas wired).
  - Sections paramètres éparpillées entre Profil/Préférences/Confidentialité.
- **Priorité** : **P0** (2j page unifiée + 1j changement password + 0.5j wiring ping GPS)

### 21. Inscription étab — ⚠️ (3/5) **P1**

- **Page** : `InscriptionEtablissement.tsx`
- **Forces** :
  - SIRET vérifié temps réel via `verify-siret` edge (`L90-94`) avec format `{statut: 'VERIFIE'|'ALERTE'|'INTROUVABLE', ...}` conforme Sprint 3.
  - Auto-remplissage raison sociale INSEE.
  - 3 scénarios badge VERIFIE/ALERTE/INTROUVABLE clairs.
- **Frictions** :
  - **KBIS upload absent de l'inscription** — déporté dans `FinaliserInscriptionEtab.tsx`.
  - Pas de spinner clair pendant `verify-siret` async.
- **Priorité** : **P1** (2j KBIS upload + spinner)

### 22. Profil étab — ❌ (4/5) **P0**

- **Page** : `ProfilEtablissement.tsx`
- **Forces** : SIRET read-only, NAF read-only, CCN dropdown 6 options, taux majoration nuit/dimanche/JF éditables, géoloc auto, mode de paiement commission (Stripe/SEPA/Facture/Chorus), couleur thème, contrat de service uploadable.
- **Frictions** :
  - **`tolerance_gps_metres` Sprint 4.5 NON ÉDITABLE EN UI** (champ DB existe avec range CHECK [30, 1000], DEFAULT 100). Aucun input/slider. Feature totalement invisible côté étab.
  - **RIB split entre 2 pages** : upload uniquement dans `FinaliserInscriptionEtab.tsx` (post-inscription), profil ne montre pas le statut RIB.
  - Workflow contrat de service dual (e-signature `FinaliserInscriptionEtab` + upload PDF dans Profil) → confusion.
- **Priorité** : **P0** (1.5j tolerance GPS slider + 1j RIB statut visible)

### 23. Équipe étab multi-utilisateurs — ❌ (2/5) **P0**

- **Page** : `MonGroupe.tsx` (130 l.)
- **Frictions** :
  - **Aucune gestion d'équipe** : pas d'invitation, pas de rôles (ADMIN_GROUPE, RH), pas de gestion permissions.
  - `MonGroupe` liste seulement les établissements du groupe sanitaire (parent), pas les membres du compte étab.
- **Priorité** : **P0** (8-12j feature complète invitations + rôles + permissions)

### 24. Dashboard étab — ✅ (4.5/5)

- **Page** : `DashboardEtablissement.tsx`
- KPI grid 4 colonnes (Ouvertes/Assignées/En cours/Terminées), bandeau candidatures + alertes, top soignants leaderboard, planning prochaines missions (30j window), commission palier visible, IndicateursAvancesEtab (turnover, taux remplissage, coût moyen), CardScoreQualiteEtab.

### 25. Création mission — ⚠️ (3.5/5) **P1**

- **Page** : `CreerMission.tsx` → `FormulaireMission.tsx`
- **Frictions** :
  - **Matrice Mediflash** : warning affiché si LIBERAL incompatible (`L329-330`) mais **radio button pas disabled** → user peut sélectionner quand même.
  - **Template contrat NON affiché** avant publication (le PDF est généré après par edge function `generate-contrat-mission-pdf`).
  - **Pas de modal récap** avant publication (submit direct).
  - **QR généré seulement au passage `SIGNE_COMPLET` du contrat** (trigger Sprint 4.5) — pas immédiatement à la publication mission.
  - Édition mission post-publication très restrictive (intitule/description/service seulement) sans label explicite des champs immuables.
- **Priorité** : **P1** (1j disable LIBERAL + 2j modal récap + 1j label immutables)

### 26. Liste missions + annulation — ⚠️ (4/5) **P0**

- **Pages** : `ListeMissions.tsx`, `ModifierMission.tsx`, `DetailMission.tsx`, `DashboardEtablissement.tsx`
- **Forces** : filtres statut/profession/dates, CarteMission avec actions (Voir, Dupliquer, Annuler, Republier), restriction édition aux missions OUVERTE.
- **Friction CRITIQUE (Sprint 3.5)** :
  - **Annulation mission ne montre AUCUNE conséquence financière en modale**. RPC `fn_annuler_mission_etablissement` appelée mais les 4 buckets :
    - OUVERTE = libre
    - ACCEPTEE sans contrat = -3 + indem zéro
    - CDD signé = -10 + **indemnité L1243-8**
    - Libéral signé = -10 + **clause pénale art.1231-5** (50/30/10%)
    - Après pointage = -20 + montant complet
    
    sont **invisibles avant clic confirmation**. Aucun code front trouvé pour `L1243-8` ou `1231-5`.
- **Priorité** : **P0** (3j modale décomposition coûts annulation + helpers calculs)

### 27. Candidatures reçues — ✅ (4/5)

- **Composant** : `ListeCandidatures.tsx` (intégré dans `DetailMission.tsx`)
- **Forces** :
  - Score soignant `score_fiabilite/100` affiché (`L224-227`) avec fallback "Pas encore d'évaluation" si <3 missions.
  - Note moyenne /5 + nb évaluations + années expérience + spécialités.
  - Workflow accepter/refuser avec paiement Stripe Connect (`accepterAvecPaiement`, `L104`).
  - Match badge professional (`L28-68`) : détection exact match, hiérarchie IDE/IBODE/IADE, spécialité manquante médecin.
- **Friction** : Score breakdown **non inline** — user doit naviguer vers `ProfilSoignantEtablissement.tsx` pour voir `DecompositionScore`.
- **Priorité** : P2 (1.5j tooltip breakdown inline)

### 28. Contrats étab — ✅ (4.5/5) **P1**

- **Pages** : `ListeContrats.tsx`, `ContratMission.tsx`
- `SignerContratOtp` intégré côté étab (mode OTP_SMS par défaut), `DPAEStatus.tsx` ✅ pré-remplit le payload net-entreprises.fr (Option A Sprint 2).
- **Frictions** :
  - **Pas de countdown 72h** signature contrat.
  - Yousign legacy encore affiché (déprécié non retiré).
- **Priorité** : **P1** (2j countdown + désactivation Yousign)

### 29. Pointage suivi étab — ⚠️ (3.5/5) **P1**

- **Page** : `PresencesEtablissement.tsx` (305 l.)
- **Composants** : `CarteValidation.tsx`, `DetailPresencesMission.tsx`, `QRPointageEtab.tsx`
- **Forces** :
  - QRPointageEtab : QR 240×240, plein écran, **impression A4**, régénération.
  - Validation 72h auto + bouton "Tout valider" pour batch.
  - Alertes `perimetre_gps_valide` + `alerte_teleportation` visibles dans tab "alertes" et CarteValidation.
- **Frictions** :
  - **Alertes cohérence Sprint 4.5 ABSENTES côté étab** (les 7 codes incidents `ARRIVEE_TROP_PRECOCE`, `ARRIVEE_APRES_FIN`, `DEPART_AVANT_ARRIVEE`, etc. ne sont pas affichés dans `coherence_incidents` jsonb).
  - **Code secours non "visible une fois"** : reste affiché côté étab après consultation (Sprint 4.5 spec demande affichage unique).
  - **Mock GPS detection** : flag `arrivee_mock_detected` / `depart_mock_detected` en DB mais **pas remonté visuellement**.
- **Priorité** : **P1** (2.5j alertes cohérence + 0.5j visible-once code + 1j mock GPS badge)

### 30. RH étab — ✅ (4/5)

- **Pages** : `DashboardRH.tsx` (411 l.), `AnalyticsEtablissement.tsx`, `MesFavorisEtablissement.tsx`
- KPI 4 colonnes (mois précédent/courant/prévisionnel/coût/h), top soignants leaderboard, génération PDF rapport mensuel, RPC `fn_stats_rh_etablissement`.
- **Friction** : pas de drill-down sur graphiques.
- **Priorité** : P2 (1.5j interactive charts)

### 31. Facturation étab — ✅ (4/5)

- **Page** : `FacturationEtablissement.tsx` (1315 l.)
- Sections Collapsible (missions à payer, missions payées, historique), distinction CDD/SALARIE (virement bulletin) vs LIBERAL (Stripe Connect / déclaration / Chorus), commissions visibles, mandat SEPA, paliers.
- **Friction** : RIB soignant non exposé (sauf via PDF facture honoraires) — possible volonté de confidentialité.

### 32. Obligations financières — ❌ (2/5) **P0**

- **Route** : `/etablissement/obligations` **redirige vers `/etablissement/facturation`** (`App.tsx:263`). Pas de page consolidée.
- RPC `fn_obligations_financieres` est référencée dans `FacturationEtablissement.tsx:104` mais **pas dans une page dédiée**.
- **Priorité** : **P0** (2j page dédiée `ObligationsEtablissement.tsx`)

### 33. Évaluer soignants (étab → soignant) — ❌ (0/5) **P0**

- **Pas de page côté étab**, **pas de modale** pour évaluer un soignant post-mission.
- Le composant `BoutonNoterMission.tsx` existe mais affiche l'**inverse** (soignant note étab).
- RPC `fn_evaluer_mission_etab_soignant` ou équivalent : à vérifier en backend (peut être `fn_noter_soignant`).
- **Priorité** : **P0** (4j page + modale + RPC `fn_mes_missions_a_evaluer_etab`)

### 34. Litiges étab Sprint 3 + 3.5 — ⚠️ (3.5/5) **P1**

- **Page** : `LitigesEtablissement.tsx`
- **Composants** : `FilDiscussionLitige.tsx`, `FormulaireAccord.tsx`, `TimelineLitige.tsx`, `BoutonsActionLitige.tsx`
- Statuts OUVERT/MEDIATION/ACTION_ATTENDUE/RESOLU/FERME, filtres, ouverture nouveau litige via dropdown missions sans litige.
- **Frictions** :
  - **Détail des modifications exécutées non affiché** dans la timeline (le payload `payload_modifications` Sprint 3.5 contient les détails mais reste invisible).
  - Tab "réclamations" présente mais RPC `fn_reclamations_etablissement` à vérifier.
  - Pas d'aide contextuelle sur les types d'accord (HORAIRES, MONTANT, COMPENSATION_PARTIELLE, MIXTE).
- **Priorité** : **P1** (2j payload visualization + 1j help context)

### 35. Score étab Sprint 3.5 — ⚠️ (3.5/5) **P1**

- **Page** : `PageScoreEtablissement.tsx`
- **Composants** : `BadgeNiveauV2.tsx`, `NotationsRecues.tsx`, `BreakdownScore.tsx`
- **Frictions** :
  - **Bouton "Contester événements" absent côté étab** (alors que le score étab Sprint 3.5 = note 40 + comportement 40 + délai paiement 20).
  - Pas de page historique événements impactants (notations, factures, litiges).
  - Pondération affichée parfois ambiguë (50% notation vs 40% brief — à vérifier).
- **Priorité** : **P1** (3j page historique événements + modale contestation)

### 36. Préférences notifications étab + paramètres — ✅ (4/5)

- `Parametres.tsx` (78 l.) : 5 onglets (profil/groupe/contrats/config/exclusions). `PageParametresNotifications.tsx` partagé soignant/étab.

### 37. Dashboard admin — ⚠️ (3/5) **P1**

- **Page** : `AdminDashboard.tsx` (581 l.)
- **Forces** : KPI utilisateurs, CA, GMV, Stripe Connect stats, rentabilité SASU estimée, graphique CA mensuel, alertes litiges ouverts + factures impayées cliquables.
- **Frictions CRITIQUES** :
  - **Aucune alerte Sprint 4.5 anti-triche** affichée :
    - Pas de KPI "Pointages incohérents" (`POINTAGE_INCOHERENT`)
    - Pas de KPI "Téléportations détectées"
    - Pas de KPI "Mock GPS suspect"
  - Les données existent en DB (`alertes_systeme`, colonnes `alerte_teleportation`, `coherence_incidents` jsonb) mais **ne remontent pas au dashboard**.
- **Priorité** : **P1** (1.5j RPC summary + bandeau dashboard)

### 38. Utilisateurs admin — ✅ (4/5)

- **Pages** : `AdminUtilisateurs.tsx` (268 l.) + `AdminDetailUtilisateur.tsx`
- Liste soignants/étabs avec recherche, filtres EN_ATTENTE, actions valider/rejeter/suspendre.
- **Suspension/réactivation** ✅ via `AdminDetailUtilisateur.tsx` : RPC `fn_admin_suspendre_utilisateur` branchée, modale dédiée.
- **Friction** : action depuis la liste seulement via navigation détail (pas de context menu).
- **Priorité** : P2 (1j context menu)

### 39. Missions admin — ⚠️ (3/5)

- **Page** : `AdminMissions.tsx` (175 l.) — liste, filtres statut, support filtre groupe sanitaire.
- **Frictions** : pas d'affichage commission/GMV par mission, pas d'actions admin (modifier/marquer en arrêt/rembourser).
- **Priorité** : P2 (2j actions admin missions)

### 40. Contrats admin — ❌ (2/5) **P0**

- **AUCUNE page admin** dédiée pour consultation contrats avec hash + certificat + audit trail.
- Pas de page d'édition des **14 templates contrats Sprint 2** (voir section 50).
- **Priorité** : **P0** (3j AdminContrats consultation hash/certificat + audit trail)

### 41. Litiges admin — ✅ (4.5/5)

- **Pages** : `AdminLitiges.tsx` (105 l.) + `AdminModeration.tsx` (425 l., plus complet)
- **Composants** : `src/components/admin/litiges/` (9 fichiers) — `LitigeResolutionModal`, `LitigePreuvesPanel`, etc.
- RPCs : `fn_admin_trancher_litige`, `fn_admin_resoudre_litige`, `fn_admin_modifier_gel_scope_litige`, `fn_admin_moderer_evaluation`, `fn_admin_moderer_document`, `fn_admin_incoherences_identite`.
- **Friction** : doublon AdminLitiges + AdminModeration (deux entry points) — fusionner.
- **Priorité** : P2 (1j fusion)

### 42. Factures admin — ✅ (4/5)

- **Pages** : `AdminFacturation.tsx`, `AdminImpayees.tsx`, `AdminFinances.tsx`
- Marquer en retard, CA par étab, trésorerie. **Friction** : pas de bulk adjustment.

### 43. Réclamations score Sprint 3.5 — ✅ (4.5/5)

- **Page** : `AdminReclamationsScore.tsx` (200+ l.)
- Filtres PENDING/TREATED, temps d'attente rouge si >7j, actions MAINTENIR/REDUIRE/ANNULER via modale.
- **À noter** : seules les réclamations créées via `fn_creer_reclamation_score` arrivent ici. Le bug P0 section 12 (legacy modale soignant) **contourne ce workflow**.

### 44. Externalisations Sprint 4 — ✅ (3.5/5)

- **Page** : `AdminExternalisationsActions.tsx` — RPCs `fn_admin_lister_externalisations`, `fn_admin_externalisation_retry`, `fn_admin_externalisation_cancel`.

### 45. Healthcheck — ✅ (4.5/5)

- **Page** : `AdminHealthcheck.tsx` — 10 services (Supabase DB/Auth, Edges, Stripe, Twilio, Document AI, Resend, PSC, Chorus, RPPS). Test SMS manuel.

### 46. Chorus Pro — ✅ (4/5)

- **Page** : `AdminChorusPro.tsx` — RPCs `fn_admin_chorus_stats`, `fn_admin_chorus_config_toggle`, `fn_admin_chorus_submission_reset`.

### 47. Score management admin — ⚠️ (3/5)

- **Pas de page centralisée** "scores par seuil" (warnings <50 pts).
- Scores visibles uniquement individuellement via `AdminDetailUtilisateur`.
- **Priorité** : P2 (1.5j `AdminScoreTriage`)

### 48. Journaux audit admin — ✅ (4/5)

- **Page** : `AdminAuditLogs.tsx` (150+ l.) — filtres action, type_acteur (SOIGNANT/ADMIN_ETABLISSEMENT/ADMIN_PLATEFORME/SYSTEME), recherche, pagination 50/page.
- **Friction** : alertes anti-triche Sprint 4.5 ne sont pas explicitement filtrables (les actions GPS_*, TELEPORTATION ne sont pas dans la liste des filtres).
- **Priorité** : P1 (0.5j ajouter filtres anti-triche)

### 49. Audit RLS — ❌ (0/5) **P1**

- **Aucune page UI** pour la fonction RPC `fn_audit_rls_strict` (Sprint 3).
- **Priorité** : **P1** (2-3j `AdminAuditRLS.tsx` avec rapport tableau)

### 50. Templates contrats — ❌ (1/5) **P0**

- **AUCUNE page admin** pour gérer les 14 templates contrats Sprint 2 (CDD master 18 professions + REMPLACEMENT_LIBERAL master + 12 LIBERAL_*).
- Les templates existent en table `templates_contrat` mais **invisibles côté UI admin**.
- L'admin ne peut pas éditer/dupliquer/activer/désactiver.
- **Priorité** : **P0** (3j `AdminTemplatesContrats.tsx` CRUD complet)

### 51. Outils RGPD admin — ⚠️ (4.5/5)

- Suppression compte + export ✅ exposés côté utilisateur (`SectionConfidentialite.tsx`).
- **Friction admin** : pas d'interface admin pour forcer suppression compte (batch admin).
- **Priorité** : P2 (1j AdminRGPDTools)

### 52. Alertes pointage Sprint 4.5 — ❌ (2/5) **P0**

- **AUCUNE page dédiée** `/admin/alertes-pointage`.
- Détection BDD existe (`alertes_systeme`, `alerte_teleportation`, `coherence_incidents`, `*_mock_detected`) mais **invisible côté UI admin**.
- Seul `AdminModeration.tsx` charge `fn_admin_incoherences_identite` (cohérence identité, **différent** de cohérence temporelle pointage).
- **Priorité** : **P0** (3j `AdminAlertesPointage.tsx` + RPC summary)

### 53. Statistiques business — ✅ (4.5/5)

- Croissance/CA/GMV/Stripe Connect/cohort economics couverts via `AdminDashboard.tsx`, `AdminCohortEconomics.tsx`, `AdminFinances.tsx`.

### 54. Inscription multi-étapes (transversal) — ✅ (4.5/5)

- Soignant : stepper 2-step (identifiants → profil pro).
- Étab : stepper 2-step (identifiants → établissement).
- Progression visuelle, validation incrémentale, messages erreur inline.

### 55. Vérification email + téléphone — ⚠️ (3.5/5) **P1**

- **Email** : ✅ via Supabase signUp + lien confirmation (`ConfirmerEmail.tsx`).
- **Téléphone** : ❌ **pattern regex seulement, pas d'OTP SMS**.
- **Priorité** : **P1** (2j integration Twilio + flow OTP)

### 56. Récupération mot de passe — ✅ (4.5/5)

- `PageResetPassword.tsx` clean, gestion `PASSWORD_RECOVERY` event + fallback hash.

### 57. Onboarding premier login — ⚠️ (4/5)

- `InscriptionSoignantCompletion.tsx` redirige post-inscription, formulaire complet. **Friction** : pas de tutoriel interactif (cf. section 3).

### 58. Suppression compte RGPD — ✅ (4.5/5)

- `SectionConfidentialite.tsx:146` (soignant) + `ProfilEtablissement.tsx:688` (étab). Modal confirmation typing "SUPPRIMER", RPCs `fn_supprimer_compte_rate_limited` / `fn_supprimer_compte_etablissement_rate_limited`. Audit trail.

### 59. Export données RGPD — ✅ (4.5/5)

- Boutons "Exporter JSON" + "Exporter CSV" dans `SectionConfidentialite.tsx`, audit `RGPD_EXPORT_DONNEES`.

### 60. Préférences notifications granulaires — ✅ (4.5/5)

- `PageParametresNotifications.tsx` : 4 canaux (EMAIL/SMS/PUSH/IN_APP) × 12+ événements soignant + 8+ étab. Toggle SMS d'alerte granulaire pour pool urgence.

### 61. Mode sombre — ✅ (4.5/5)

- `useTheme.ts` : toggle, localStorage persistance, meta `theme-color` dynamique, Capacitor StatusBar Android, respect `prefers-color-scheme`. Classes `dark:` Tailwind utilisées partout.

### 62. Internationalisation — ❌ (n/a)

- **Aucune librairie i18n** (i18next, react-i18next). Français hardcodé partout. Acceptable si cible = France uniquement.
- **Priorité** : P3 (future expansion, ~15j de refacto si nécessaire)

### 63. Accessibilité (WCAG/RGAA 4.1 AA) — ✅ (4/5)

- `PageAccessibilite.tsx` (134 l.) — déclaration honnête.
- Mesures : lien "Aller au contenu", `lang="fr"`, labels associées, focus visibles, notifications `role="alert"`/`status`, ARIA labels icons, touch targets 44px, `prefers-reduced-motion`, hiérarchie sémantique, contraste ≥4.5:1.
- Audit axe-core en Playwright (cf. `e2e/a11y.spec.ts`).
- **Non-conformités déclarées** : animations tierces, vidéos tuto sans sous-titres.
- **Priorité** : P2 (sous-titres vidéos)

---

## SECTION 3 — Synthèse priorisée

### 🔴 P0 — Bloquants workflow critique (13 items)

Ces items empêchent un workflow critique de fonctionner correctement ou exposent un bug qui contourne la sécurité Sprint 3.5/4.5.

> **MISE À JOUR Sprint 5.5** : 8 items sur 13 ont été résolus. Voir la colonne "Statut".

| # | Section | Item | Justification | Statut |
|---|---|---|---|---|
| P0-1 | **§12** | Bug `PageScoreSoignant` utilise legacy `ModalReclamationScore` au lieu de `score/ModaleReclamationScore` Sprint 3.5 | Contourne `fn_creer_reclamation_score` → workflow admin `/admin/reclamations-score` court-circuité (insert direct dans `reclamations_scoring` legacy) | ✅ **RÉSOLU Hotfix #133** + nettoyage #144 |
| P0-2 | **§6** | Fenêtre annulation candidature 30 min absente + conséquences score invisibles | Sprint 3.5 grille annulation soignant inapplicable côté UI | ✅ **RÉSOLU Sprint 5.5 #134** + tests #135 |
| P0-3 | **§20** | Pas de page parente `/soignant/parametres` + changement password absent | Friction majeure paramètres soignant | ✅ **RÉSOLU Sprint 5.5 #138 + #139 + #140** |
| P0-4 | **§22** | `tolerance_gps_metres` Sprint 4.5 non éditable côté étab | Feature Sprint 4.5 invisible — étab ne peut pas régler 30-1000m | ✅ **RÉSOLU Sprint 5.5 #141** |
| P0-5 | **§23** | Gestion équipe étab (ADMIN_GROUPE/RH) absente | Impossible de manager rôles/permissions multi-utilisateurs | ✅ **RÉSOLU Sprint 5.7** (#147+#148+#149) |
| P0-6 | **§26** | Modale conséquences annulation mission étab (4 buckets) absente | Étab ne voit pas indem L1243-8 / clause pénale 1231-5 avant clic | ✅ **RÉSOLU Sprint 5.5 #136** + tests #137 |
| P0-7 | **§32** | Page `/etablissement/obligations` redirige (pas de consolidation) | Brief section 32 non couvert | ✅ **RÉSOLU Sprint 5.5 #142** |
| P0-8 | **§33** | Évaluation étab → soignant absente | Pas de note étab donnée au soignant | ✅ **RÉSOLU Sprint 5.7** (#151+#152) |
| P0-9 | **§40** | Pas de page admin consultation contrats hash/certificat/audit | Audit légal contrats impossible côté admin | ✅ **RÉSOLU Sprint 5.7** (#153) |
| P0-10 | **§50** | Pas de page admin pour 14 templates contrats Sprint 2 | Templates invisibles, non éditables | ✅ **RÉSOLU Sprint 5.7** (#154 → direct push) |
| P0-11 | **§52** | Pas de page admin pour alertes anti-triche Sprint 4.5 | Téléportation, mock GPS, cohérence temporelle non remontés | ✅ **RÉSOLU Sprint 5.7** (#155+#156 → direct push) |
| P0-12 | **§16** | Soignant pas de page DPAE (n° URSSAF non visible) | Sprint 2 visibilité DPAE générées manquante | ✅ **RÉSOLU Sprint 5.5 #143** |
| P0-13 | **§4** | NIR (numéro sécu) absent du UI DPAE soignant | Sprint 2 "DPAE complète" incomplète (NIR dans listManquant mais pas dans formulaire) | ✅ **RÉSOLU Sprint 5.5 #143** |

### 📊 Bilan Sprint 5.5 + 5.7 (13/13 P0 résolus ✅)

| Résolus Sprint 5.5 | Résolus Sprint 5.7 |
|---|---|
| P0-1, P0-2, P0-3, P0-4, P0-6, P0-7, P0-12, P0-13 | P0-5, P0-8, P0-9, P0-10, P0-11 |

**Tous les P0 audit Sprint 5 sont désormais résolus.** Place aux P1/P2 sur Sprint 6.

### 🟡 P1 — Frictions importantes (15 items)

> **MISE À JOUR Sprint 6** : 12 items sur 15 ont été résolus. Voir colonne "Statut".

| # | Section | Item | Impact UX | Statut |
|---|---|---|---|---|
| P1-1 | §3 | Onboarding sans tutoriel/aide contextuelle + DPAE exilée | Abandon possible inscription | ✅ **RÉSOLU Sprint 6 PR 5** |
| P1-2 | §10 | Évaluation post-mission soignant absente d'historique | Action critique cachée | ✅ **RÉSOLU Sprint 6 PR 2** |
| P1-3 | §11 | Pas de page évaluations reçues dédiée (top 5 dans Profil) | Pas d'accès historique complet | ✅ **RÉSOLU Sprint 6 PR 1** |
| P1-4 | §25 | Pas de modal récap mission avant publication + radio LIBERAL non disabled | Risque erreur publication | ✅ **RÉSOLU Sprint 7 PR 1** (#173) |
| P1-5 | §27 | Score breakdown soignant non inline dans ListeCandidatures | Navigation supplémentaire | ✅ **RÉSOLU Sprint 7 PR 2** (#172) |
| P1-6 | §28 | Pas de countdown 72h signature contrat | Risque expiration silencieuse | ✅ **RÉSOLU Sprint 6 PR 3** |
| P1-7 | §29 | Alertes cohérence Sprint 4.5 absentes côté étab | Détection fraude incomplète | ✅ **RÉSOLU Sprint 6 PR 11** |
| P1-8 | §34 | Détail payload accord exécuté non affiché timeline litige | Opacité résolution | ✅ **RÉSOLU Sprint 6 PR 8** |
| P1-9 | §35 | Pas de contestation événements score côté étab | Score étab non contestable | ✅ **RÉSOLU Sprint 6 PR 4** |
| P1-10 | §37 | Dashboard admin sans alertes Sprint 4.5 | Admin aveugle aux fraudes | ✅ **RÉSOLU Sprint 6 PR 6** |
| P1-11 | §49 | Page admin RLS audit manquante | `fn_audit_rls_strict` non exposée | ✅ **RÉSOLU Sprint 7 PR 3** (#174) |
| P1-12 | §55 | Pas d'OTP SMS téléphone (juste regex) | Vérif téléphone faible | ✅ **RÉSOLU Sprint 6 PR 9** |
| P1-13 | §4 | Mandat facturation upload/signature UI absent | Workflow Voie A factor incomplet | ✅ **RÉSOLU Sprint 6 PR 10** (workflow déjà complet — banner ajouté) |
| P1-14 | §21 | KBIS upload séparé de l'inscription | Friction inscription étab | ✅ **RÉSOLU Sprint 6 PR 12** |
| P1-15 | §48 | Filtres anti-triche absents `AdminAuditLogs` | Recherche alertes difficile | ✅ **RÉSOLU Sprint 6 PR 7** |

### 📊 Bilan Sprint 6 (12/15 P1 résolus ✅)

| Résolus Sprint 6 | Reportés Sprint 7 |
|---|---|
| P1-1, P1-2, P1-3, P1-6, P1-7, P1-8, P1-9, P1-10, P1-12, P1-13, P1-14, P1-15 | P1-4, P1-5, P1-11 |

**Cf. `docs/ONBOARDING_TUTORIEL.md`, `docs/EVALUATION_POST_MISSION_SOIGNANT.md`, `docs/SCORE_ETAB_CONTESTATION.md`, `docs/OTP_SMS_TELEPHONE.md`, `docs/MANDAT_FACTURATION_SOIGNANT.md` pour les détails Sprint 6.**

### 🟢 P2 — Cosmétique / améliorations futures (15 items)

- Mediflash banner explication côté soignant (§5)
- Majorations nuit/dimanche breakdown détaillé recherche (§5)
- Hash SHA-256 full + copier-coller (§7)
- Wiring `ConsentementPingGps` dans `SectionPreferences` (§8)
- Statut paiement net estimé en mission en cours (§9)
- Wizard ouverture litige depuis historique (§10)
- Resend email confirmation (§2)
- Distinction visuelle types notifications (§19)
- Drill-down graphiques RH (§30)
- Bulk adjustment admin facturation (§42)
- Fusion AdminLitiges + AdminModeration (§41)
- Page `AdminScoreTriage` (§47)
- Actions admin missions (modifier/rembourser) (§39)
- Context menu rapide utilisateurs admin (§38)
- Sous-titres vidéos tuto (§63)

### 🔵 P3 — Reportables (out of scope Sprint 5/5.5/5.7)

- Internationalisation i18n (§62) — uniquement si expansion internationale décidée

---

## SECTION 4 — Estimation d'effort

### Découpage proposé

#### **Sprint 5.5 — Fixes critiques P0** (15 jours-homme)

Focus : débloquer workflows critiques, fixer le bug score réclamations Sprint 3.5, exposer Sprint 4.5 admin.

| Item | Jours | Section |
|---|---|---|
| Fix import `ModaleReclamationScore` Sprint 3.5 + correction MesReclamations | 1j | P0-1 §12 |
| Composant `AnnulationCandidatureTimer` + modale conséquences score | 2j | P0-2 §6 |
| Page parente `/soignant/parametres` + changement mot de passe | 3j | P0-3 §20 |
| Slider `tolerance_gps_metres` Sprint 4.5 dans `Parametres.tsx` étab | 1.5j | P0-4 §22 |
| Modale conséquences annulation mission (4 buckets L1243-8 / 1231-5) | 3j | P0-6 §26 |
| Page `/etablissement/obligations` consolidée (RPC `fn_obligations_financieres`) | 2j | P0-7 §32 |
| Ajout champ NIR dans `SectionDpaeIdentite` + RPC | 0.5j | P0-13 §4 |
| Page `/soignant/dpae` listant DPAE + n° URSSAF | 2j | P0-12 §16 |

#### **Sprint 5.7 — Fixes P0 majeurs** (15 jours-homme)

Focus : équipe étab, évaluation, templates admin, alertes anti-triche.

| Item | Jours | Section |
|---|---|---|
| Gestion équipe étab (invitations, rôles ADMIN_GROUPE/RH, permissions) | 8j | P0-5 §23 |
| Page admin `AdminTemplatesContrats.tsx` CRUD 14 templates | 3j | P0-10 §50 |
| Page admin `AdminAlertesPointage.tsx` + RPC summary | 3j | P0-11 §52 |
| Page admin `AdminContrats.tsx` (consultation hash/certificat) | 1j | P0-9 §40 |

#### **Sprint 6 — Évaluations + frictions P1** (15 jours-homme)

Focus : évaluation reverse étab→soignant, scores, onboarding.

| Item | Jours | Section |
|---|---|---|
| Évaluer soignants côté étab (page + modale + RPC) | 4j | P0-8 §33 |
| Onboarding tutoriel interactif + intégration DPAE | 3j | P1-1 §3 |
| Évaluation post-mission soignant déplacée dans historique + wizard litige | 2j | P1-2 §10 |
| Page évaluations reçues dédiée soignant + filtres | 2j | P1-3 §11 |
| Modal récap mission avant publication + disable LIBERAL si incompatible | 2j | P1-4 §25 |
| Dashboard admin : bandeau alertes Sprint 4.5 (`fn_admin_alertes_pointage_resume`) | 1.5j | P1-10 §37 |
| Countdown 72h signature contrat + suppression Yousign legacy | 0.5j | P1-6 §28 |

#### **Sprint 7 — Frictions P1 + polish P2** (15 jours-homme)

Focus : litiges détail, accessibilité, score étab.

| Item | Jours | Section |
|---|---|---|
| Détail payload accord exécuté timeline litige + help context | 2.5j | P1-8 §34 |
| Contestation événements score étab + page historique | 3j | P1-9 §35 |
| Alertes cohérence pointage côté étab + code secours visible-once + mock GPS badge | 3j | P1-7 §29 |
| Page admin `AdminAuditRLS.tsx` | 2.5j | P1-11 §49 |
| OTP SMS téléphone (Twilio) | 2j | P1-12 §55 |
| Mandat facturation upload + signature électronique | 1.5j | P1-13 §4 |
| Filtres anti-triche `AdminAuditLogs` | 0.5j | P1-15 §48 |

#### **Sprint 8 — P2 polish** (10 jours-homme)

- Score breakdown inline candidatures
- Mediflash banner + majorations breakdown
- Hash SHA-256 full + copier-coller
- Drill-down graphiques RH
- Fusion AdminLitiges + Moderation
- AdminScoreTriage
- Actions admin missions
- Distinction visuelle types notifications
- Resend email confirmation
- Wiring `ConsentementPingGps` paramètres soignant
- Sous-titres vidéos tuto

### Effort total

| Sprint | Jours | Description |
|---|---|---|
| Sprint 5.5 | **15j** | Fixes critiques P0 (bug score, paramètres, GPS tolerance, annulation, DPAE soignant) |
| Sprint 5.7 | **15j** | P0 majeurs (équipe étab, templates admin, alertes pointage) |
| Sprint 6 | **15j** | Évaluation reverse, onboarding tutoriel, scores |
| Sprint 7 | **15j** | Frictions P1 (litiges détail, accessibilité, OTP SMS, mandat) |
| Sprint 8 | **10j** | Polish P2 |
| **TOTAL** | **~70j** | ~3-4 mois calendrier en mode parallélisable backend/frontend |

P0 : **30j** (Sprints 5.5 + 5.7)
P1 : **30j** (Sprints 6 + 7 partiels)
P2 : **10j** (Sprint 8)

---

## SECTION 5 — Recommandations stratégiques

### A. Workflows critiques non testables E2E à cause de la dette frontend

Les workflows suivants ont leur backend complet mais ne peuvent **pas être validés bout-en-bout** sans intervention manuelle ou bypass :

1. **Annulation candidature soignant avec impact score Sprint 3.5** — l'UI n'a pas de bouton ni de timer rétractation. La RPC `fn_annuler_candidature_soignant` existe mais n'est pas appelée. Workflow inopérant côté UX.
2. **Contestation pénalité Sprint 3.5** — bug d'import legacy contourne `fn_creer_reclamation_score`. Les réclamations soignant n'arrivent pas dans `/admin/reclamations-score`.
3. **Annulation mission étab avec indemnités L1243-8 / clause pénale 1231-5** — backend calcule les indemnités, mais aucune décomposition n'est montrée à l'étab avant clic. Risque de surprise et de contentieux.
4. **Alertes anti-triche Sprint 4.5 (téléportation, mock GPS, cohérence)** — détection BDD active, alertes créées dans `alertes_systeme`, mais aucune UI admin pour les consulter. Système anti-triche en place mais "boîte noire" côté équipe Jolene.
5. **Tolerance GPS adaptive Sprint 4.5** — feature livrée backend (CHECK range 30-1000m, DEFAULT 100) mais aucun étab ne peut la régler depuis l'UI. Configuration figée à la valeur par défaut.
6. **Templates contrats Sprint 2 (14 templates)** — bien que les contrats utilisent les bons templates côté backend (RPC `fn_resolve_template_contrat`), l'équipe admin ne peut pas éditer, dupliquer ou désactiver un template via UI.
7. **DPAE Sprint 2 visibilité côté soignant** — le soignant remplit les champs identité mais ne voit jamais le n° URSSAF retourné ni le statut des DPAE générées par l'étab pour ses missions.

### B. Écrans nécessitant une refonte complète vs ajustements

#### Refonte complète

- **`PageScoreSoignant.tsx`** : Corriger l'import modale + restructurer pour vraie UX Sprint 3.5 (lister événements impactants récents avec bouton "Contester" par événement).
- **Page `/soignant/parametres`** : Créer page parente unifiée consolidant Profil, Préférences, Confidentialité (actuellement éparpillé dans `ProfilSoignant.tsx`).
- **Modale annulation mission étab** : Ajouter décomposition 4 buckets avec articles de loi cités.
- **Gestion équipe étab** : feature complète à designer + implémenter (mobile-first, invitations email, rôles).

#### Ajustements ciblés

- `CartePointage.tsx` (déjà bien fait Sprint 4.5 PR 12).
- `RechercheMissions.tsx` (ajouter badges Mediflash + majorations).
- `DetailMissionSoignant.tsx` (ajouter timer rétractation candidature).
- `AdminDashboard.tsx` (bandeau alertes Sprint 4.5).
- `Parametres.tsx` étab (ajouter slider tolerance GPS).

### C. Fonctionnalités backend totalement invisibles côté UI

Cf. **annexe RPCs orphelines** ci-dessous. Highlights :

- **Anti-triche pointage Sprint 4.5** : `fn_evaluer_coherence_pointage`, `fn_verifier_pointages_incoherents`, `fn_purger_pings_gps_anciens` — backend opérationnel, aucune UI admin.
- **Annulation Sprint 3.5** : `fn_annuler_candidature_soignant`, `fn_annuler_mission_complete`, `fn_calculer_indemnite_annulation_etab`, `fn_calculer_penalite_annulation_soignant` — fonctions backend complètes, helpers `fn_dans_fenetre_retractation` non utilisées en UI.
- **Litiges** : `fn_creer_litige`, `fn_cloturer_litige`, `fn_cloturer_litige_mutuel`, `fn_demander_mediation_admin` — soignant et étab peuvent ouvrir litige mais flow d'urgence/escalade pas exposé.
- **Score** : `fn_recalculer_score_fiabilite_soignant`, `fn_calculer_score_etablissement`, `fn_mon_score`, `fn_mes_evenements_score` — les pages score affichent un score précalculé (snapshot) mais les RPCs de recalcul/breakdown ne sont pas branchées à un bouton "Recalculer mon score".
- **Pointage code Sprint 3 legacy** : `fn_pointer_arrivee_code`, `fn_pointer_depart_code` — remplacées par Sprint 4.5 `fn_valider_code_secours`, mais legacy encore référencé dans `CartePointage.tsx:103` (lignes commentées récemment).

### D. Bugs critiques identifiés

#### Bug P0-1 : Bug de réclamation score soignant (Sprint 3.5)

**Localisation** : `src/pages/PageScoreSoignant.tsx:13`
```tsx
import { ModalReclamationScore } from '@/components/ModalReclamationScore';
```

**Problème** : Le composant legacy `src/components/ModalReclamationScore.tsx:74-81` fait un `INSERT` direct dans `reclamations_scoring` (table legacy) :
```tsx
const { error } = await supabase.from('reclamations_scoring').insert({...});
```

Alors que le nouveau composant `src/components/score/ModaleReclamationScore.tsx:80` appelle la RPC Sprint 3.5 :
```tsx
const { data, error } = await supabase.rpc('fn_creer_reclamation_score' as any, {...});
```

**Conséquence** : Toutes les réclamations soignant ouvertes depuis `/soignant/score` **n'arrivent jamais** dans `/admin/reclamations-score` (qui appelle `fn_admin_lister_reclamations` listant `reclamations_score`, pas `reclamations_scoring`). Workflow Sprint 3.5 PENDING/TRAITEE → MAINTENIR/REDUIRE/ANNULER **complètement court-circuité**.

**Fix** : Remplacer l'import par `import { ModaleReclamationScore } from '@/components/score/ModaleReclamationScore';` et ajuster props.

#### Bug P0-2 : `FiabiliteSoignant.tsx` utilise aussi le legacy

Même problème dans la page legacy `src/pages/FiabiliteSoignant.tsx:10` (redirige depuis `/soignant/fiabilite` vers `/soignant/score`). À nettoyer/supprimer.

### E. Stratégie de validation post-fixes

1. **Tests E2E Playwright** à ajouter pour les workflows P0 :
   - Annulation candidature 30 min (avec mock timer)
   - Réclamation score Sprint 3.5 → admin trancher → notification
   - Annulation mission étab avec affichage 4 buckets
   - Templates contrats admin CRUD
   - Tolerance GPS éditable + propagation au scan QR
2. **Audit visuel** : screenshot regression sur écrans refondus.
3. **Audit accessibilité axe-core** : maintenir le niveau RGAA AA actuel.
4. **Smoke tests RPCs orphelines** : vérifier que chaque RPC backend mature a au moins un test E2E qui la déclenche via UI.

---

## SECTION 6 — Annexes

### Annexe A — RPCs orphelines critiques

Sur **369 RPCs définies en backend, 209 ne sont jamais appelées** depuis le front (cf. `grep -rhoE "rpc\(['\"\`]fn_[a-z_0-9]+" src/`).

Une partie est attendue (triggers, helpers internes `_trg`, fonctions purement backend). Mais certaines représentent une dette UI directe :

| RPC | Domaine | Action attendue UI |
|---|---|---|
| `fn_annuler_candidature_soignant` | Sprint 3.5 | Bouton annuler candidature soignant |
| `fn_annuler_mission_complete` | Sprint 3.5 | Modale annulation étab avec calculs |
| `fn_calculer_indemnite_annulation_etab` | Sprint 3.5 | Affichage indem L1243-8 / 1231-5 |
| `fn_calculer_penalite_annulation_soignant` | Sprint 3.5 | Affichage points soignant |
| `fn_dans_fenetre_retractation` | Sprint 3.5 | Timer rétractation 30 min |
| `fn_creer_litige` | Litiges | Wizard ouverture litige |
| `fn_cloturer_litige_mutuel` | Litiges | Bouton clôture accord |
| `fn_demander_mediation_admin` | Litiges | Bouton escalade admin |
| `fn_admin_resoudre_litige` | Litiges admin | Bouton résoudre (admin) |
| `fn_admin_lever_suspension` | Admin | Bouton réactiver compte |
| `fn_admin_marquer_absence_sans_prevenir` | Admin | Action sur mission no-show |
| `fn_admin_masquer_notation` | Admin | Modération évaluations |
| `fn_admin_creer_litige_force` | Admin | Création litige admin |
| `fn_admin_modifier_gel_scope_litige` | Admin | Gestion gel trésorerie |
| `fn_mon_score` | Score soignant | Recalcul on-demand |
| `fn_mes_evenements_score` | Score soignant | Liste événements impactants |
| `fn_mes_reclamations` | Réclamations soignant | Liste réclamations |
| `fn_pointer_arrivee_code` | Sprint 3 legacy | Remplacé par Sprint 4.5 (à supprimer) |
| `fn_pointer_depart_code` | Sprint 3 legacy | Remplacé par Sprint 4.5 (à supprimer) |
| `fn_regenerer_qr_mission` | Sprint 4.5 | Bouton régénération QR — vérifier wire |
| `fn_verifier_pointages_incoherents` | Sprint 4.5 | Worker cron (admin-only OK) |
| `fn_modifier_horaires_presence` | Sprint 3 | Édition horaires admin |
| `fn_souscrire_prevoyance` | Prévoyance soignant | Souscription prévoyance |
| `fn_resolve_template_contrat` | Sprint 2 | Page admin templates (P0-10) |
| `fn_supprimer_mon_compte` | RGPD | Remplacée par `*_rate_limited` |

Cette liste n'est pas exhaustive — voir `/tmp/unused_rpcs.txt` pour les 209 RPCs orphelines (généré lors de l'audit).

### Annexe B — Discrepancies sub-agents

Lors de l'audit, deux discrepancies ont été détectées entre les rapports des sub-agents et la vérification directe du code par l'auditeur principal :

1. **Agent §11-20 a indiqué que `PageScoreSoignant` utilise `ModaleReclamationScore` correctement** → vérification directe : faux, c'est `ModalReclamationScore` legacy. Bug P0-1 confirmé.
2. **Agent §37-53 a indiqué que `AdminUtilisateurs` n'expose pas la suspension** → vérification directe : la suspension EST exposée mais via `AdminDetailUtilisateur.tsx` (navigation depuis liste). Donc moins grave (juste pas de context menu direct dans liste).

### Annexe C — Liens vers les rapports détaillés des sub-agents

Les 6 rapports d'agents détaillés (consolidés dans ce document) sont disponibles dans :

- `/tmp/claude-0/-home-user-Jolene/d5543e28-e6ad-4c57-a555-8911e8a82867/tasks/a0687fb2594fdd664.output` (soignant inscription/profil)
- `/tmp/claude-0/-home-user-Jolene/d5543e28-e6ad-4c57-a555-8911e8a82867/tasks/a376c3959333c01e7.output` (soignant missions/pointage)
- `/tmp/claude-0/-home-user-Jolene/d5543e28-e6ad-4c57-a555-8911e8a82867/tasks/a942c4a37aedea054.output` (soignant finance/score/litiges)
- `/tmp/claude-0/-home-user-Jolene/d5543e28-e6ad-4c57-a555-8911e8a82867/tasks/ac3f9f8cfd410830a.output` (étab insc/mission/cand)
- `/tmp/claude-0/-home-user-Jolene/d5543e28-e6ad-4c57-a555-8911e8a82867/tasks/a4f6cbcc99104c8e1.output` (étab pointage/contrats/factures/litiges)
- `/tmp/claude-0/-home-user-Jolene/d5543e28-e6ad-4c57-a555-8911e8a82867/tasks/a7c5752a58505f027.output` (admin + transversaux)

---

## Conclusion exécutive

**État global frontend Jolene après Sprint 4.5 : 75% complet, UX moyenne 3.9/5.**

- **Forces** : Sprint 4.5 anti-triche pointage (QR + GPS + code secours + offline queue + consent RGPD) est **excellent**. Sprint 2 contrats + signature OTP solidement intégré. Sprint 3.5 score breakdown bien affiché côté soignant. Dashboard étab et admin riches en KPIs.
- **Faiblesses critiques** :
  1. **Bug critique réclamation score Sprint 3.5** côté soignant (contournement workflow admin).
  2. **Sprint 4.5 anti-triche côté admin INVISIBLE** (alertes téléportation/mock GPS/cohérence pas remontées).
  3. **Annulation Sprint 3.5** : grille soignant 30 min + grille étab 4 buckets totalement absentes du UI.
  4. **Tolerance GPS adaptive** étab non éditable.
  5. **Gestion équipe étab** absente.
  6. **Évaluation reverse étab → soignant** absente.
  7. **Templates contrats admin** absents (14 templates Sprint 2 non gérables).

**Recommandation** : prioriser Sprint 5.5 (15j) pour débloquer le bug score + tolérance GPS + DPAE soignant + paramètres unifiés, puis Sprint 5.7 (15j) pour les pages admin manquantes (templates, alertes anti-triche, équipe étab). L'évaluation reverse et l'onboarding tutoriel peuvent attendre Sprint 6.

Le backend Jolene est en avance significative sur le frontend. **L'effort de rattrapage frontend est de ~30j (P0) + ~30j (P1) + 10j (P2) = ~70j-homme**, parallélisables sur 3-4 mois calendrier.

---

*Audit réalisé par Claude Code en mode multi-agents — 6 sub-agents Explore en parallèle pour audit par domaine, consolidation centrale. Evidence-based, lectures de code intégrales. Aucun fix appliqué.*
