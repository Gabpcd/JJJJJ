# Store readiness — préparation App Store et Play Store

## État réel au 10/08/2026

- Le web, iOS et Android sont configurés en version `1.0 (16)` ; le typecheck,
  le build web, les 1 214 tests unitaires et les prévols mobiles passent.
- Le dernier binaire iOS archivé (`1.0 (7)`) est obsolète. Aucune identité Apple
  Distribution valide n'est actuellement disponible dans le trousseau local :
  il faut rétablir la signature, reconstruire `1.0 (16)`, l'envoyer puis faire
  la recette TestFlight.
- L'AAB local `Jolene-1.0-16-release.aab` est matériellement présent et sa
  signature JAR est valide, mais il contient un frontend antérieur aux derniers
  correctifs. Il est signé par l'ancienne clé d'upload
  `4B:43:18:5D:0F:67:C3:1F:A7:E9:0D:69:7D:5B:AF:D0:D6:DE:95:8C:66:27:8B:5D:22:79:66:31:6D:5D:69:B2`,
  dont la clé privée n'est pas disponible dans l'environnement courant. La clé
  privée locale restante porte une autre empreinte ; ne pas reconstruire ni
  téléverser avec elle tant que Play Console n'a pas confirmé une réinitialisation
  de la clé d'upload.
- Les scripts de captures valident une configuration de 32 PNG App Store et
  24 PNG Google Play, iPad 13 pouces inclus. Les captures finales ne sont pas
  encore produites : elles exigent une authentification de démonstration stable
  sur la production.
- Les consoles App Store Connect et Play Console doivent encore être ouvertes
  dans une session authentifiée. Aucune soumission finale ne doit être déclenchée
  automatiquement.

Le tableau ci-dessous conserve les preuves historiques du 14/07/2026 ; elles ne
valent pas validation des binaires `1.0 (16)`. « Build validé » ne signifie pas
« publiable » : les éléments de signature, consoles et recette sur appareils
restent externes au repo.

## Vérifié dans le repo

| Élément | État | Preuve |
|---|---|---|
| Build web production | ✅ | `npm run build` |
| Synchronisation Capacitor | ✅ | 15 plugins iOS et Android, sans géolocalisation de fond |
| Build iOS Xcode 26 | ⚠️ archive historique seulement | `1.0 (7)` a été archivé et exporté le 14/07/2026, mais il est obsolète ; `1.0 (16)` doit être reconstruit après restauration d'une identité Apple Distribution valide |
| Distribution iOS | ⛔ bloquée | aucun binaire `1.0 (16)` signé n'est actuellement disponible ; upload et recette TestFlight restent à faire |
| Visuels Apple | ⚠️ configuration validée | les 32 emplacements PNG, dont iPad 13 pouces portrait/paysage, sont configurés ; les captures finales doivent être régénérées sur le build courant |
| Privacy manifest iOS | ✅ | membre de la cible et présent à la racine de `App.app` |
| Permissions GPS | ✅ minimisées | When In Use/foreground : pointage ou action volontaire « me localiser » du profil/adresse |
| QR natif | ✅ | `@capacitor/barcode-scanner`, QR-only |
| Universal Links iOS | ✅ repo | AASA valide pour reset, PSC, invitation et missions |
| Lint Android Release | ✅ | SDK 36, Gradle 8.14.5, `:app:lintRelease` : 0 erreur |
| App Links Android | ✅ artefact généré | `assetlinks.json` contient l'empreinte Play App Signing `18:6E:1F:3A:56:5D:DC:F0:88:0D:DD:58:EB:AF:D9:79:6C:88:7E:E9:61:81:0E:70:A8:3C:78:C3:0A:E8:EE:06` |
| Signature Android | ⛔ ancienne clé privée indisponible | l'AAB historique est bien signé par la clé d'upload Jolene (`SHA-256 4B:43:18:5D:0F:67:C3:1F:A7:E9:0D:69:7D:5B:AF:D0:D6:DE:95:8C:66:27:8B:5D:22:79:66:31:6D:5D:69:B2`), mais cette clé privée et `keystore.properties` ne sont pas disponibles dans l'environnement courant |
| Firebase Android | ✅ configuré localement | application `app.jolene` créée dans `jolene-app-d91fd`, certificats SHA-1/SHA-256 enregistrés et `google-services.json` officiel gitignoré |
| Bundle Android | ⚠️ artefact historique non final | l'AAB signé `1.0 (16)` présent localement contient un frontend antérieur ; ne pas l'envoyer avant reconstruction avec la clé d'upload autorisée |
| Pages mémoire Android 16 Ko | ✅ | les segments `LOAD` de toutes les bibliothèques arm64-v8a/x86_64 sont alignés sur `2**14` |
| Suppression de compte in-app | ✅ | écran confidentialité + garde-fous serveur |
| Signalement et blocage UGC | ✅ | UI et contrôles serveur |

## À faire avant toute soumission

### Apple Developer / App Store Connect

- [ ] Rétablir une identité Apple Distribution valide pour l'équipe
  `FPQ78HDF4Y` et `app.jolene`, puis vérifier Push Notifications et Associated
  Domains dans le profil généré.
- [ ] Archiver et exporter le build courant `Jolene 1.0 (16)` ; l'archive
  historique `1.0 (7)` ne doit pas être envoyée.
- [ ] Uploader le build 16 après le déploiement final, attendre son traitement,
  puis le sélectionner seulement après la recette TestFlight.
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
- [ ] Régénérer puis remplacer dans le brouillon les captures iPhone et iPad
  après le déploiement final, sans masquer les données de démonstration : les
  fichiers actuels précèdent les dernières corrections fonctionnelles.
- [ ] Vérifier le parcours complet sur un appareil réel.

### Google Play

- [x] Installer Android SDK 36 et exécuter `:app:lintRelease` (0 erreur).
- [ ] Retrouver la clé privée correspondant à l'ancienne empreinte d'upload ou
  confirmer dans Play Console la réinitialisation vers la clé locale restante ;
  seulement ensuite recréer `android/keystore.properties` hors Git.
- [x] Créer l'app Firebase Android `app.jolene` dans `jolene-app-d91fd`, y
  enregistrer les certificats SHA-1/SHA-256 et déposer le
  `google-services.json` officiel dans `android/app/` (fichier local
  gitignoré). Le secret serveur
  `FIREBASE_SERVICE_ACCOUNT_JSON` est déjà présent dans Supabase ; il ne
  remplace pas la configuration Firebase du client Android.
- [x] Renseigner l'empreinte SHA-256 de Play App Signing et régénérer
  `assetlinks.json`.
- [x] Déployer l'`assetlinks.json` régénéré et vérifier sa réponse publique.
- [ ] Vérifier App Links après une installation depuis Google Play.
- [ ] Après résolution de la clé, exécuter `lintRelease` et `bundleRelease` pour
  produire l'AAB final `1.0` (`versionCode 16`) avec le frontend courant.
- [x] Compléter Data safety, Content rating et l'accès au compte de revue dans
  Play Console.
- [ ] Régénérer puis remplacer dans le brouillon les 8 captures téléphone,
  tablette 7 pouces et tablette 10 pouces après le déploiement final, sans
  masquer les données de démonstration.
- [ ] Vérifier dans Play Console l'icône 512 × 512 et la feature graphic
  1024 × 500 ; aucune feature graphic dédiée n'est conservée dans le repo.
- [ ] Enregistrer les textes et visuels finaux de la fiche Play Store.
- [ ] Uploader l'AAB en piste Internal et le tester avant toute publication.

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
