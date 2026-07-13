# Store readiness — préparation App Store et Play Store

État au 13/07/2026. « Build validé » ne signifie pas « publiable » : les
éléments de signature, consoles et recette sur appareils restent externes au
repo.

## Vérifié dans le repo

| Élément | État | Preuve |
|---|---|---|
| Build web production | ✅ | `npm run build` |
| Synchronisation Capacitor | ✅ | 15 plugins iOS et Android, sans géolocalisation de fond |
| Build iOS Xcode 26 | ✅ archive App Store | Xcode 26.5, SDK iOS 26.5, archive Release `1.0 (4)` validée |
| Distribution iOS | ✅ uploadée | IPA **Jolene** signée avec l'équipe Apple `FPQ78HDF4Y`, upload App Store Connect accepté le 13/07/2026 |
| Rendu iPhone 6,9 pouces | ✅ simulateur | barre d'état lisible et capture native `1320 × 2868` validée sur iPhone 17 Pro Max |
| Privacy manifest iOS | ✅ | membre de la cible et présent à la racine de `App.app` |
| Permissions GPS | ✅ minimisées | When In Use/foreground : pointage ou action volontaire « me localiser » du profil/adresse |
| QR natif | ✅ | `@capacitor/barcode-scanner`, QR-only |
| Universal Links iOS | ✅ repo | AASA valide pour reset, PSC, invitation et missions |
| Lint Android Release | ✅ | SDK 36, Gradle 8.14.5, `:app:lintRelease` : 0 erreur |
| App Links Android | ✅ artefact généré | `assetlinks.json` contient l'empreinte Play App Signing `18:6E:1F:3A:56:5D:DC:F0:88:0D:DD:58:EB:AF:D9:79:6C:88:7E:E9:61:81:0E:70:A8:3C:78:C3:0A:E8:EE:06` |
| Signature Android | ✅ locale | clé d'upload Jolene (`SHA-256 4B:43:18:5D:0F:67:C3:1F:A7:E9:0D:69:7D:5B:AF:D0:D6:DE:95:8C:66:27:8B:5D:22:79:66:31:6D:5D:69:B2`) et `keystore.properties` gitignorés ; AAB Release signé |
| Firebase Android | ✅ configuré localement | application `app.jolene` créée dans `jolene-app-d91fd`, certificats SHA-1/SHA-256 enregistrés et `google-services.json` officiel gitignoré |
| Bundle Android | ✅ | `lintRelease` et `bundleRelease` passent ; AAB signé `1.0` (`versionCode 2`) généré |
| Suppression de compte in-app | ✅ | écran confidentialité + garde-fous serveur |
| Signalement et blocage UGC | ✅ | UI et contrôles serveur |

## À faire avant toute soumission

### Apple Developer / App Store Connect

- [x] Générer automatiquement le profil App Store de **Jolene** pour l'équipe
  `FPQ78HDF4Y` et `app.jolene`, avec Push Notifications et Associated Domains.
- [x] Archiver, exporter et uploader `Jolene 1.0 (4)` vers App Store Connect ;
  le purpose string `NSLocationAlwaysAndWhenInUseUsageDescription` demandé par
  Apple après le build 3 est présent dans le binaire.
- [x] Vérifier la présence côté Supabase de `APNS_KEY_P8`, `APNS_KEY_ID`,
  `APNS_TEAM_ID`, `APNS_BUNDLE_ID` et `APNS_ENVIRONMENT`.
- [ ] Après traitement App Store Connect, installer le build TestFlight et
  valider un push réel (la présence des secrets ne valide pas leurs valeurs).
- [x] Déployer l'AASA avec `Content-Type: application/json`, sans redirection,
  puis vérifier sa propagation sur le CDN Apple pour l'équipe `FPQ78HDF4Y`.
- [ ] Reporter exactement les catégories de `PrivacyInfo.xcprivacy` dans App
  Privacy, avec GPS lié au compte, limité au pointage et à la localisation
  volontaire du profil/adresse, jamais en continu.
- [ ] Compléter âge, URL de confidentialité, CGU, contact review, notes de
  review et identifiants du compte démo.
- [ ] Produire les captures iPhone/iPad et vérifier le parcours complet sur un
  appareil réel.

### Google Play

- [x] Installer Android SDK 36 et exécuter `:app:lintRelease` (0 erreur).
- [x] Retrouver et configurer hors Git le keystore d'upload et
  `keystore.properties` ; Gradle reconnaît désormais la signature release.
- [x] Créer l'app Firebase Android `app.jolene` dans `jolene-app-d91fd`, y
  enregistrer les certificats SHA-1/SHA-256 et déposer le
  `google-services.json` officiel dans `android/app/` (fichier local
  gitignoré). Le secret serveur
  `FIREBASE_SERVICE_ACCOUNT_JSON` est déjà présent dans Supabase ; il ne
  remplace pas la configuration Firebase du client Android.
- [x] Renseigner l'empreinte SHA-256 de Play App Signing et régénérer
  `assetlinks.json`.
- [ ] Déployer l'`assetlinks.json` régénéré, puis vérifier App Links après une
  installation depuis Google Play.
- [x] Exécuter `lintRelease` et `bundleRelease` : l'AAB signé `1.0`
  (`versionCode 2`) est généré.
- [ ] Uploader cet AAB en piste Internal, le tester, puis compléter Data
  safety, Content rating, accès au compte démo et fiche store.

### Recette commune

- [ ] Reset password depuis un email, retour natif compris.
- [ ] Callback Pro Santé Connect, invitation établissement et mission publique.
- [ ] Scan QR, pointage GPS, mode hors-ligne puis resynchronisation.
- [ ] Push au premier plan/arrière-plan/app tuée avec routage par rôle.
- [ ] Paiement réel à faible montant, remboursement et suppression de compte.
- [ ] Accessibilité, petits/grands écrans, réseau lent et absence de réseau.

## Données de démonstration

Ne pas masquer ni purger les données de démonstration avant les captures stores
et la review. Conserver en particulier les comptes de review et leurs scénarios
préparés ; toute purge ultérieure doit être explicitement demandée et ne doit
jamais toucher les données réelles ou de prospection.

## Décision produit

Sign in with Apple n'est pas requis tant que Jolene propose seulement
email/mot de passe et aucun login social tiers. L'ajout futur de Google,
Facebook ou équivalent impose de réévaluer cette obligation avant release.
