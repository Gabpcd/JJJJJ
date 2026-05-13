# Mandat de facturation soignant (Sprint 6)

> P1-13 audit Sprint 5 (scope ajusté). Workflow **déjà complet** sur `/soignant/mandat-facturation` — Sprint 6 ajoute un banner statut visible ailleurs.

## État existant (avant Sprint 6)

La page `/soignant/mandat-facturation` (`MandatFacturation.tsx`, 394 lignes) implémente déjà :

- Affichage du texte légal du mandat (markdown rendu HTML)
- Checkbox d'acceptation
- Bouton "Signer" → `fn_signer_mandat_facturation(p_version, p_ip, p_user_agent, p_contenu_hash)`
- Hash SHA-256 du texte du mandat (`hashMandatTexte`)
- Audit IP + user agent
- Téléchargement PDF signé (`telechargerMandatFacturationPdf`)
- Bouton "Résilier" → `fn_revoquer_mandat_facturation(p_motif)`
- Détection version obsolète → re-signature requise

L'audit P1-13 ("aucun upload/signature UI") était **incorrect** : le workflow est entièrement opérationnel.

## Ajout Sprint 6 PR 10

**`BannerMandatFacturation`** (nouveau composant) — bannière compacte du statut mandat, embarquable n'importe où :

```tsx
import { BannerMandatFacturation } from '@/components/BannerMandatFacturation';

// Dans DashboardSoignant, ProfilSoignant, PageParametresSoignant, etc.
<BannerMandatFacturation />
```

Trois états :
- **NON_SIGNÉ** → bannière warning + CTA "Signer maintenant"
- **SIGNÉ** → bannière success + date signature + version + CTA "Télécharger PDF / Résilier"
- **VERSION_OBSOLETE** → version < version courante → CTA "Re-signer"

## Workflow utilisateur

```
Soignant clique Banner ou navigate "/soignant/mandat-facturation"
  ↓
Lecture du mandat (texte légal markdown)
  ↓
Cocher "J'accepte les termes du mandat"
  ↓
Cliquer "Signer le mandat"
  ↓
hash = SHA-256(texte_mandat)
  ↓
fn_signer_mandat_facturation(version, navigator.userAgent, hash)
  → INSERT mandats_facturation_signatures
  → soignants.mandat_facturation_signe = true
  → audit trail
  ↓
Page affiche "Signé le XX/YY/ZZZZ" + lien téléchargement PDF + bouton "Résilier"
```

## Résiliation

`fn_revoquer_mandat_facturation(p_motif text)` :
- Marque `mandat_facturation_signe = false`
- Garde l'historique des signatures
- Audit trail avec motif optionnel
- Pas de suppression données : conformité RGPD légale 5 ans

## Voie A factor

Le mandat est requis pour activer le **factor Voie A** (avances rapides sur factures honoraires libéral) :

- Sans mandat signé → bouton "Demander une avance" désactivé
- Avec mandat signé → workflow `MesAvances` accessible
