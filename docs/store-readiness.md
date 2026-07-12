# Store readiness — préparation App Store et Play Store

État au 12/07/2026. « Build validé » ne signifie pas « publiable » : les
éléments de signature, consoles et recette sur appareils restent externes au
repo.

## Vérifié dans le repo

| Élément | État | Preuve |
|---|---|---|
| Build web production | ✅ | `npm run build` |
| Synchronisation Capacitor | ✅ | 15 plugins iOS et Android, sans géolocalisation de fond |
| Build iOS Xcode 26 | ✅ Debug simulateur | Xcode 26.5, SDK iOS Simulator 26.5, `BUILD SUCCEEDED` |
| Privacy manifest iOS | ✅ | membre de la cible et présent à la racine de `App.app` |
| Permissions GPS | ✅ minimisées | When In Use/foreground : pointage ou action volontaire « me localiser » du profil/adresse |
| QR natif | ✅ | `@capacitor/barcode-scanner`, QR-only |
| Universal Links iOS | ✅ repo | AASA valide pour reset, PSC, invitation et missions |
| App Links Android | ⛔ fingerprint externe | le build release refuse le placeholder actuel |
| Signature Android | ⛔ externe | le build release refuse l'absence de keystore |
| Firebase Android | ⛔ externe | `android/app/google-services.json` absent |
| Suppression de compte in-app | ✅ | écran confidentialité + garde-fous serveur |
| Signalement et blocage UGC | ✅ | UI et contrôles serveur |

## À faire avant toute soumission

### Apple Developer / App Store Connect

- [ ] Sélectionner l'équipe Apple et générer un profil App Store pour
  `app.jolene` contenant Push Notifications et Associated Domains.
- [ ] Configurer la clé APNs côté Supabase, puis valider un push sur TestFlight.
- [ ] Déployer l'AASA avec `Content-Type: application/json`, sans redirection,
  puis réinstaller l'app après propagation du CDN Apple.
- [ ] Reporter exactement les catégories de `PrivacyInfo.xcprivacy` dans App
  Privacy, avec GPS lié au compte, limité au pointage et à la localisation
  volontaire du profil/adresse, jamais en continu.
- [ ] Compléter âge, URL de confidentialité, CGU, contact review, notes de
  review et identifiants du compte démo.
- [ ] Produire les captures iPhone/iPad et vérifier le parcours complet sur un
  appareil réel.

### Google Play

- [ ] Installer Android SDK 36 et exécuter `./gradlew lintRelease`.
- [ ] Ajouter le keystore d'upload, `keystore.properties` et
  `google-services.json` hors Git.
- [ ] Renseigner l'empreinte SHA-256 de Play App Signing, régénérer puis
  déployer `assetlinks.json`, et vérifier App Links après installation Play.
- [ ] Exécuter `bundleRelease`, tester l'AAB en piste Internal, puis compléter
  Data safety, Content rating, accès au compte démo et fiche store.

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
