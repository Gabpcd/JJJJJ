# Jolene

Jolene est une plateforme française de mise en relation directe entre
établissements de santé et professionnels soignants. Elle couvre le cycle de
la mission : publication, candidature, contrat, pointage, facturation et
paiement.

Le produit comprend trois espaces distincts :

- **Soignant** : missions compatibles, candidatures, contrats, pointage,
  revenus et documents administratifs ;
- **Établissement** : publication et suivi des missions, candidatures,
  contrats, pointages, factures et équipe ;
- **Administration** : conformité, modération, pilotage, support et
  observabilité.

Jolene est un outil professionnel de staffing. Il ne fournit ni diagnostic ni
soin médical aux patients et ne collecte pas de données de santé.

## Stack

- React 18, TypeScript, Vite, Tailwind CSS et shadcn/ui ;
- Supabase (PostgreSQL, Auth, Storage, Realtime et Edge Functions) ;
- Capacitor 8 pour iOS et Android ;
- Stripe Connect, Yousign, Pro Santé Connect et Chorus Pro ;
- Vitest, Playwright, Lighthouse et GitHub Actions.

## Développement local

Prérequis : Node.js 24 et npm.

```bash
npm ci
npm run dev
```

Les variables Supabase et les secrets tiers ne sont jamais versionnés. Voir
[la procédure staging](docs/staging.md) pour la configuration des
environnements.

## Vérifications

```bash
npm run build
npm test
npm run test:guards
npm run test:regression
npm run test:e2e
```

## Applications natives

```bash
npx cap sync
npm run open:ios
npm run open:android
```

La préparation de production, les signatures et les hard stops sont décrits
dans :

- [Production Capacitor](docs/CAPACITOR_PRODUCTION.md)
- [Préparation App Store et Play Store](docs/store-readiness.md)
- [Push natif iOS et Android](docs/PUSH_NATIVE_FINAL.md)
- [Métadonnées stores fr-FR](docs/STORE_METADATA_FR.md)

## Sécurité et données

- Aucun secret, keystore ou fichier Firebase n'est accepté dans Git.
- Les tables exposées utilisent RLS et les opérations privilégiées passent par
  des fonctions serveur contrôlées.
- La politique de confidentialité publique est disponible sur
  [jolene.app/confidentialite](https://jolene.app/confidentialite).
- Les vulnérabilités ne doivent pas être publiées dans une issue publique ; le
  contact est `support@jolene.app`.

Projet propriétaire — Jolene SASU.
