# Store readiness — préparation soumission App Store / Play Store

État au 11/07/2026 (Phase 2 MODE AUTONOME). « Soumettre ≠ publier » : publication
manuelle sur les deux stores après review.

## Fait dans le repo (vérifié)

| Item | État | Preuve / emplacement |
|---|---|---|
| Purpose strings iOS (FR) | ✅ | `ios/App/App/Info.plist` : Location (WhenInUse + AlwaysAndWhenInUse avec rétention 30j), Camera, PhotoLibrary (+Add), LocalNotification, FaceID — **tous en français** |
| `ITSAppUsesNonExemptEncryption` | ✅ | `Info.plist` = `false` (pas de chiffrement non-exempté → pas de déclaration export) |
| Région / langue | ✅ | `CFBundleDevelopmentRegion = fr` |
| Universal Links iOS (AASA) | ✅ | `public/.well-known/apple-app-site-association` : appID `5D9L5FQQ86.app.jolene`, paths soignant/étab/admin/missions + `webcredentials` |
| App Links Android | ⚠️ repo OK, **fingerprint hors-repo** | `public/.well-known/assetlinks.json` (placeholder) régénéré au build par `scripts/prepare-well-known.mjs` depuis l'env `ANDROID_SHA256_CERT_FINGERPRINTS` |
| Suppression de compte in-app | ✅ | `fn_supprimer_mon_compte` / `_etablissement` (+ wrappers rate-limited 1/jour). **Garde-fou métier** : refus si missions `ASSIGNEE`/`EN_COURS` à venir ; anonymise messages/GPS ; conserve les pièces légales (factures, paiements nulled). UI `SectionConfidentialite`, `AdminRGPDTools` |
| Signalement utilisateur (UGC) | ✅ | `fn_signaler_utilisateur` + `SignalerUtilisateur.tsx` (motif ≥ 10 car., 7 catégories) |
| **Blocage utilisateur (UGC)** | ✅ (cette salve) | `utilisateurs_bloques` + `fn_bloquer/debloquer/est_bloque` + `fn_envoyer_message` refuse si blocage bilatéral + `BloquerUtilisateur.tsx` câblé dans `ChatConversation` |
| Sign in with Apple | ✅ **N/A** | Jolene = **email/mot de passe uniquement**, aucun login social tiers (le seul OAuth = Chorus Pro, backend facturation). Apple ne l'exige pas (Guideline 4.8 conditionnée à la présence d'un login social tiers) |

## Actions HORS-REPO pour Gabrielle (checklist humaine)

### Apple Developer / App Store Connect
- [ ] **Associated Domains** : activer `applinks:` + `webcredentials:` pour le domaine `jolene.app` sur l'App ID `5D9L5FQQ86.app.jolene` (Certificates, Identifiers & Profiles).
- [ ] **Encryption compliance** : à la soumission, répondre « No » (cohérent avec `ITSAppUsesNonExemptEncryption=false`).
- [ ] **App Privacy (nutrition labels)** : déclarer les données collectées (localisation pour pointage, contact, documents). Cf. `docs/CONFORMITE.md`.
- [ ] **Age rating** + **Privacy Policy URL** (`jolene.app/confidentialite`) + **EULA/CGU** (`jolene.app/cgu`).
- [ ] **Compte démo Apple** : fournir des identifiants de test (compte démo, à NE PAS purger — cf. inventaire données phase 7).
- [ ] **Screenshots** stores (les écrans admin n'y figurent pas).

### Google Play
- [ ] **`ANDROID_SHA256_CERT_FINGERPRINTS`** : poser en variable/secret de build (empreinte SHA-256 du certificat d'upload Play App Signing) → `prepare-well-known.mjs` génère `assetlinks.json` au build. Sans ça, les App Links Android ne s'ouvrent pas dans l'app.
- [ ] **Data safety form** + **Content rating** + Privacy Policy.

### Général
- [ ] **Vérification visuelle** : cf. `docs/REVUE_VISUELLE.md` (passe globale TestFlight).
- [ ] **Mission témoin réelle** (premier euro contrôlé — tripwires Lot 19 en place) avant/juste après soumission.
- [ ] **Purge données de test** : uniquement catégorie (a) seed `[pw-test:*]`, sur demande explicite, **sauf compte démo Apple** (cf. inventaire données phase 7 — actifs de prospection JAMAIS touchés).

## Non requis / décisions

- **Sign in with Apple** : non implémenté car non requis (pas de login social tiers). Si un login Google/Facebook est ajouté un jour → Sign in with Apple devient obligatoire (Guideline 4.8).
