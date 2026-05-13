# Onboarding tutoriel premier login (Sprint 6)

> Fix **P1-1** audit Sprint 5. Tutoriel interactif 7 étapes pour soignant et étab au premier login, avec persistance DB.

## Composants

- **`OnboardingGuide`** (étendu Sprint 6 PR 5) — modale fullscreen 7 étapes par rôle.
- **`TooltipAide`** — info-bulle accessible (clic / focus clavier) pour champs critiques.
- **`BoutonResetOnboarding`** — "Refaire le tutoriel" dans paramètres.

## Étapes soignant (7)

1. **Bienvenue** — intro générale Jolene
2. **Profil** — RPPS, identité, profession (→ `/soignant/profil`)
3. **Documents** — diplômes, pièce d'identité (→ `/soignant/mes-documents`)
4. **Recherche missions** — filtres + rayon + postuler (→ `/soignant/recherche-missions`)
5. **Pointage QR** — QR recommandé, GPS et code secours en backup
6. **Score Jolene + DPAE** — 6 composantes + encart DPAE complète pour CDD
7. **Paramètres & vie privée** — ping GPS, suppression compte

## Étapes étab (7)

1. **Bienvenue** — intro générale
2. **Profil étab** — adresse, SIRET, FINESS, contact
3. **Création mission** — formulaire + récap coûts (→ `/etablissement/missions/creer`)
4. **Candidatures** — score qualité + paiement Stripe Connect
5. **Signature contrat + DPAE** — workflow OTP SMS + pré-remplissage DPAE
6. **Affichage QR pointage** — impression A4 + suivi temps réel
7. **Facturation & obligations** — auto CDD/libéral + suivi obligations

## Persistance DB

Migration `20260515100000_pr5s6_onboarding_steps_persistence.sql` ajoute :

- `soignants.onboarding_etapes_completees jsonb` (default `'[]'`)
- `soignants.onboarding_termine_le timestamptz`
- Idem sur `etablissements`

### RPCs

| RPC | Description |
|---|---|
| `fn_marquer_etape_onboarding(p_etape_id, p_termine)` | Marque une étape complétée + flag terminé |
| `fn_reset_onboarding()` | Vide la progression — retutoriel au prochain login |
| `fn_etat_onboarding()` | Retourne `{role, etapes, termine_le}` |

Tous `SECURITY DEFINER` + `auth.uid()` check.

## Multi-device

L'OnboardingGuide vérifie d'abord `fn_etat_onboarding` (DB) puis fallback `localStorage`. Conséquence : un soignant qui termine le tutoriel sur web ne le re-verra pas sur mobile (ou inversement).

## Tooltips contextuels

Le composant `TooltipAide` peut être placé à côté de n'importe quel champ critique :

```tsx
<label>
  Rayon de recherche
  <TooltipAide contenu="Distance maximum entre votre adresse et les missions affichées (5-200 km)." />
</label>
```

Accessible : clic, focus clavier, Escape pour fermer, role="tooltip".

## Reset

Bouton "Refaire le tutoriel" dans `/soignant/parametres` ou `/etablissement/parametres` via composant `BoutonResetOnboarding` qui appelle `fn_reset_onboarding`.
