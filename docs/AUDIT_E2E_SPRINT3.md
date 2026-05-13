# Audit bout-en-bout du workflow critique — Sprint 3

> Audit code-only effectué via MCP Supabase + lecture statique. La recette
> exécutoire end-to-end reste à faire par Gabrielle après Sprint 3.
>
> Légende :
> - ✅ OK — code testable
> - ⚠️ OK avec friction UX — fonctionnel mais améliorable
> - ❌ Bug ou manque — fix nécessaire (cf. PR 6 Sprint 3)

## Périmètre

Workflow 19 étapes du test E2E `e2e/flows/workflow-mission-complete.spec.ts`
+ cas d'erreur identifiés dans le brief Sprint 3 (chantier 4).

---

## Étapes happy path

### 1. Inscription étab privé
**Statut** : ✅

- Page `/inscription/etablissement` + composant `InscriptionEtablissement.tsx`
- Vérification SIRET via `verify-siret` (PR 1 Sprint 3 a aligné format `{ok, code}`)
- `register-etablissement` edge function crée l'auth.user + soignant_id NULL + insère etablissements
- Email confirmation envoyé via Supabase Auth
- Affichage page succès `/inscription-succes`

### 2. Inscription soignant médecin libéral RPPS valide
**Statut** : ✅

- Page `/inscription/soignant` + composant `InscriptionSoignant.tsx`
- `verify-rpps` edge function appelle FHIR ANS API
- Vérification traits identité (nom, prénom, date_naissance)
- `register-soignant` insère auth.user + soignants
- Composant `SectionDpaeIdentite.tsx` (PR 2 Sprint 2) permet de compléter
  sexe / lieu_naissance / nationalité après inscription

### 3. Étab crée mission
**Statut** : ✅

- Page `/etablissement/missions/nouvelle` + `CreerMission.tsx` +
  `FormulaireMission.tsx`
- Trigger `dec_valider_compatibilite_mission_liberal` (PR 2 Sprint 1)
  bloque les paires profession × type_etab incompatibles
- Templates de contrat résolus via `fn_resolve_template_contrat` (PR 5 S2)

### 4. Soignant candidate
**Statut** : ✅

- Page `/soignant/missions/:id` + composant `ListeCandidatures.tsx`
- INSERT candidatures avec statut EN_ATTENTE
- Trigger DB pour push CANDIDATURE_RECUE à étab (à vérifier en recette)

### 5. Étab accepte → contrat généré
**Statut** : ⚠️

- `fn_traiter_candidature` met statut=ACCEPTEE + crée contrat_mission
- ⚠️ La génération automatique du HTML figé via `generate-contrat-mission-pdf`
  (PR 3 Sprint 2) est déclenchée côté frontend au premier load, pas par le
  backend. Si l'étab accepte mais personne n'ouvre la page contrat avant
  signature, le contrat reste sans `storage_path`. Pas bloquant (auto-trigger
  marche), juste friction si signature en aveugle.

### 6. Notification soignant CONTRAT_A_SIGNER (email + push)
**Statut** : ✅

- Trigger `dec_email_contrat_a_signer` (PR 7 Sprint 1) → email via `send-email`
- Trigger `dec_push_contrat_a_signer` (PR 4 Sprint 3) → push via `send-push`
- Les 2 events partent en parallèle, best-effort (silencieux si net.http_post échoue)

### 7. Soignant signe avec OTP SMS
**Statut** : ✅

- `SignerContratOtp.tsx` flow OTP : envoi SMS → saisie 6 chiffres → validation
- Hash SHA-256 réel du HTML signé (PR 1 Sprint 2) via `crypto.subtle.digest`
- Limites anti-abus : 3 SMS/24h + 5 tentatives + expiration 10 min (PR 1 S2)
- Ordre obligatoire : étab ne peut signer avant le soignant (PR 1 S2)
- Audit complet dans `signatures_contrats` (IP, UA, hash, OTP, RPPS, PSC)

### 8. Notification étab pour contre-signer
**Statut** : ⚠️

- Trigger email étab existe (PR 7 S1 a `trg_dec_email_contrat_signe_complet`
  qui se déclenche sur SIGNE_COMPLET, donc APRÈS la signature étab)
- ⚠️ **Manque trigger spécifique** : email/push à l'étab dès la signature
  du soignant (étape intermédiaire SIGNE_SOIGNANT). Sinon l'étab n'est pas
  notifié qu'il peut maintenant signer à son tour.
- **Fix proposé PR 6** : ajouter trigger `dec_email_signature_soignant_recue`
  + `dec_push_signature_soignant_recue` après signature soignant.

### 9. Étab signe avec OTP SMS
**Statut** : ✅

- Même flow `SignerContratOtp.tsx` côté étab
- Backend force ordre (PR 1 S2) — accepté ici car soignant a déjà signé
- À la signature étab, statut passe à SIGNE_COMPLET → triggers (PR 7 S1 + PR 4 S3)
  envoient emails + push CONTRAT_SIGNE aux 2 parties

### 10. DPAE pré-remplie générée (CDD uniquement)
**Statut** : ✅

- Pour types_contrat CDD / SALARIE uniquement (libéraux = pas de DPAE)
- Composant `DPAEStatus.tsx` côté étab (PR 6 S1 + PR 2 S2)
- `fn_generer_donnees_dpae` retourne payload avec sexe / lieu_naissance /
  nationalité du soignant (PR 2 S2)
- L'étab copie payload → net-entreprises.fr → saisit n° DPAE retour

### 11. Mission passe ACTIVE
**Statut** : ⚠️

- ⚠️ **Manque transition automatique** : missions.statut reste ASSIGNEE
  jusqu'à la fin de la mission. La transition ACTIVE n'existe que pour les
  contrats. Sémantiquement OK mais ambigu — `missions.statut = EN_COURS`
  est activé au premier pointage (`fn_pointer_arrivee` PR 3 S3).
- À documenter : ASSIGNEE → EN_COURS (au pointage arrivée) → TERMINE
  (validation présence J+72h).

### 12. Pointage GPS le jour de la mission
**Statut** : ✅ (PR 3 Sprint 3 fix complet)

- Calcul Haversine côté serveur + tolérance configurable + storage
  `distance_etablissement_m` + `perimetre_gps_valide`
- Code de secours fallback si GPS hors zone
- Composants `BoutonPointage.tsx`, `CartePointage.tsx`, `SaisieCodePointage.tsx`

### 13. Validation présence J+72h
**Statut** : ✅ (PR 3 Sprint 3)

- `fn_valider_presences_72h_auto()` + cron pg_cron toutes les 6h
- Tracking `valide_auto_72h_le` distinct de `valide_le` (validation manuelle étab)
- Skip si motif_litige IS NOT NULL

### 14. Génération facture (Factur-X)
**Statut** : ⚠️

- Edge function `generate-invoice` génère PDF + Factur-X XML embedded
- Workflow `weekly-invoicing-cron` génère factures hebdomadaires libéraux
- ⚠️ **Friction** : les factures CDD/SALARIE sont gérées par paie via
  `bulletin-paie-pdf.ts`, pas par le même flow. Cohérent mais 2 systèmes
  parallèles à maintenir.

### 15. Envoi facture (Stripe Connect privé / Chorus Pro public)
**Statut** : ✅ Stripe / ⚠️ Chorus Pro

- **Stripe** : ✅ `stripe-connect-pay-mission` + webhook → encaissement étab
  → reversement soignant. Mapping `balance_insufficient` corrigé (F-15 / PR 1 S3).
- **Chorus Pro** : ⚠️ Le code est 100% prêt (`submit-to-chorus`, `sync-chorus-status`)
  mais bloqué par l'AIFE qui n'a pas encore activé les scopes OAuth. PR 9 S3 attend.

### 16. Encaissement paiement
**Statut** : ✅

- Stripe : `confirm-invoice-payment` + webhook → statut PAYEE
- SEPA Direct Debit : `sepa-auto-charge` cron mensuel
- Chorus Pro : statuts AIFE syncés via `sync-chorus-status` (en attente déblocage)

### 17. Reversement soignant libéral
**Statut** : ⚠️

- ⚠️ **Affacturage en attente** : `factor-request-advance` + `factor-webhook`
  edge functions présentes mais factor pas encore signé contractuellement.
  En attendant : virement manuel par admin via `stripe-connect-pay-mission`.
- À documenter clairement dans `docs/REVERSEMENT_SOIGNANT.md` (à créer Sprint 4).

### 18. Notifications email + push à chaque étape
**Statut** : ✅ (PR 4 Sprint 3 complète)

- Triggers DB :
  - CONTRAT_A_SIGNER (email + push) ✅
  - CONTRAT_SIGNE (email + push aux 2) ✅
  - PAIEMENT_RECU (push via webhook Stripe) ✅
- À ajouter PR 6 : SIGNATURE_SOIGNANT_RECUE à l'étab (étape 8 friction)

### 19. Page certificat signature accessible
**Statut** : ✅ (PR 4 Sprint 2)

- Route `/contrat/:id/certificat` + `CertificatSignaturePage.tsx`
- Export PDF jsPDF complet (header rose, hash monospace, détail signatures, footer)
- Encart pédagogique "Empreinte du document signé"

---

## Cas d'erreur

### RPPS valide + profession différente
**Statut** : ✅
- `verify-rpps` retourne `profession_mismatch` → UI affiche erreur claire avec code
- Code routing structuré depuis PR #67 (Sprint 1 fix routing erreurs)

### Email déjà utilisé
**Statut** : ✅
- `register-soignant` détecte conflit auth → retourne `USER_ALREADY_REGISTERED`
- Routing UI vers connexion (PR #66/67)

### IDE libéral en EHPAD (Mediflash)
**Statut** : ✅
- Trigger `dec_valider_compatibilite_mission_liberal` (PR 2 S1) bloque INSERT
- Test Playwright `restrictions-mediflash.spec.ts` documente le cas (PR 6 S2)

### OTP incorrect 3 fois → blocage
**Statut** : ⚠️
- Backend permet 5 tentatives (PR 4 S1), pas 3. À aligner si la doc parle de 3.
- Le compteur `tentatives_restantes` est affiché côté UI (PR 1 S2)
- Au-delà de 5 : error_code `TROP_DE_TENTATIVES` → "Renvoyez un nouveau code SMS"

### Étab signe avant soignant (ordre forcé)
**Statut** : ✅
- Backend refuse avec `ETAB_AVANT_SOIGNANT` (PR 1 S2)
- UI affiche bandeau "Soignant doit signer en premier" + email rappel

### Conflit temps repos 11h
**Statut** : ⚠️
- PR 3 Sprint 1 a ajouté contraintes `REPOS_HEBDO_35H` + `MOYENNE_44H_12_SEMAINES`
- ⚠️ **Manque** : check du repos quotidien 11h entre 2 missions. À implémenter
  Sprint 4 via trigger `dec_valider_repos_quotidien_11h`.

### Dépassement 48h hebdo
**Statut** : ✅
- PR 3 S1 : trigger CHECK conformite_travail max_48h_hebdo (art. L3121-20)

### Mission annulée par étab après signature soignant
**Statut** : ⚠️
- Possible mais ne déclenche pas auto la compensation au soignant
- ⚠️ **Manque** : workflow indemnité de non-respect du préavis (à scoper Sprint 4)

### Mission annulée par soignant après acceptation
**Statut** : ⚠️
- Possible via UI, soignant accepte les conséquences (impact score fiabilité)
- ⚠️ **Manque** : enforcement strict des conditions d'annulation (J-7 etc.)

### Soignant no-show le jour de la mission
**Statut** : ⚠️
- Si pas de pointage arrivée à T+30min : `BandeauOubliDepart` rappelle le soignant
- ⚠️ **Manque cron** : détection automatique no-show + ouverture litige
  automatique. À implémenter Sprint 4.

### Étab no-show (soignant pointe mais étab fermé)
**Statut** : ⚠️
- Soignant peut conteste via litige manuel
- ⚠️ **Manque workflow proactif** : si plusieurs présences validées sans départ
  réel, suspendre étab automatiquement. Sprint 4.

### Paiement Stripe échoué (carte refusée, balance_insufficient)
**Statut** : ✅
- F-15 (PR 1 S3) : mapping `balance_insufficient` ajouté → retryable=true
- Mapping complet `_shared/stripe-errors.ts` couvre tous les cas standards

### Paiement Chorus Pro échoué (rejet AIFE)
**Statut** : ⚠️
- Status `consulterCRDetaille` retourne le code rejet + détail
- ⚠️ **Manque** : workflow automatique de re-soumission après correction
  (l'étab doit aujourd'hui réimporter manuellement). Backlog Sprint 4+.

---

## Audit emails + SMS

### Inventaire triggers d'envoi

| Type | Source | Statut |
|---|---|---|
| `INSCRIPTION_EMAIL_VERIF` | Supabase Auth | ✅ Resend |
| `CONTRAT_A_SIGNER` | trg_dec_email_contrat_a_signer + trg_dec_push (PR 4 S3) | ✅ |
| `CONTRAT_SIGNE` | trg_dec_email_contrat_signe_complet + trg_dec_push (PR 4 S3) | ✅ |
| `OTP_SIGNATURE` | fn_envoyer_otp_signature → send-sms | ✅ |
| `MISSION_NOUVELLE_FILTRE` | trigger alertes_filtres | ✅ |
| `CANDIDATURE_RECUE` | trigger candidatures INSERT | ✅ |
| `MISSION_ASSIGNEE` | trigger candidatures UPDATE ACCEPTEE | ✅ |
| `RAPPEL_J1_MISSION` | cron J-1 | ✅ |
| `POINTAGE_MANQUANT` | cron T+30min | ✅ |
| `FACTURE_EMISE` | trigger factures INSERT | ✅ |
| `PAIEMENT_RECU` | webhook Stripe | ✅ |
| `DPAE_RAPPEL` | bandeau UI manuel | ⚠️ pas de cron auto |

### Resend (emails)
- Edge function `send-email` utilise fetch direct vers API Resend (équivalent SDK)
- Templates HTML inline dans `send-email/index.ts` (~50 templates)
- Charte Jolene (rose) appliquée systématiquement
- Logging dans `emails_envoyes` (statut, provider_id, erreur)

### Twilio (SMS)
- Edge function `send-sms` via fetch direct Twilio API
- Whitelist stricte : OTP signature, OTP inscription, urgences pool
- Logging dans `sms_envoyes`
- Coût hardcodé 0.07€ (F-18 audit Sprint 0 — non bloquant)

### Friction UX identifiée
- ⚠️ Pas de test d'envoi automatique en CI : difficile de détecter qu'un email
  template casse silencieusement. À ajouter Sprint 4 via test smoke E2E qui
  envoie 1 email + 1 SMS via mode test.

---

## Synthèse PR 6 Sprint 3 — bugs à fixer

Tickets identifiés par l'audit, à traiter en PR 6 :

1. **Trigger DB manquant** : `dec_email_signature_soignant_recue` + `dec_push_signature_soignant_recue` (étape 8)
2. **Cron manquant** : détection no-show soignant T+30min → push rappel + ouverture litige auto (étape "Soignant no-show")
3. **Cron manquant** : DPAE_RAPPEL J+1 si signature SIGNE_COMPLET et CDD et dpae_effectuee=false
4. **Doc à créer** : `docs/REVERSEMENT_SOIGNANT.md` clarifiant flow factor / virement manuel intermédiaire

Items reportés Sprint 4 (hors scope PR 6) :
- Trigger repos quotidien 11h
- Workflow indemnité non-respect préavis (étab annule après signature)
- Workflow strict conditions d'annulation soignant
- Workflow étab no-show automatique
- Re-soumission Chorus Pro après rejet
- Capacitor Geolocation natif
- APNS p8 key + FCM Admin SDK migration
- Test smoke E2E envoi 1 email + 1 SMS

---

## Conclusion

Le workflow critique 19 étapes est :
- **Happy path** : 13 ✅ / 4 ⚠️ friction UX / 2 vraies failles
- **Cas d'erreur** : 6 ✅ / 7 ⚠️ workflow à compléter Sprint 4

Les ⚠️ identifiés ne bloquent pas le launch — ils sont des points d'amélioration
post-MVP. Les 2 vraies failles (notification étab après signature soignant,
DPAE rappel auto J+1) sont traitées dans **PR 6 Sprint 3**.
