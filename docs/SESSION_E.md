# Session E — Activation soignant (12/06/2026)

> Exécution du volet « Session E » de [STRATEGIE_PRODUIT_ACQUISITION.md](STRATEGIE_PRODUIT_ACQUISITION.md).
> Cible : le funnel réel mesuré en prod — 27 soignants inscrits → 21 sans aucun
> document → 1 seul activé. Chaque écran du parcours d'activation doit montrer
> la valeur avant l'effort et répondre à « qu'est-ce que JE fais maintenant ».

## PRs livrées

| Lot | PR | Contenu |
|---|---|---|
| E-1 | #559 | Inscription : déblocage RPPS introuvable (« vérification manuelle sous 24 h »), stepper honnête 4 étapes, géolocalisation opt-in avec bénéfice, harmonisation flow email/PSC |
| E-2 | #560 | Valeur avant l'effort : RPC publique `fn_apercu_marche_profession` (agrégats anon : missions/taux/établissements, bornés au rayon) + `ApercuMarche` à l'étape 2 et sur la page succès ; pavé anti-spam réservé aux domaines Microsoft ; CTA orientés valeur |
| E-3/4/5/6 | #561 | Dashboard checklist d'activation unique (absorbe la modal 7 slides + 3 bandeaux) ; états vides recruteurs + alerte 1-tap (filtres sauvegardés IMMEDIATE) ; documents caméra-first avec verdict IA inline ; checkout candidature (net estimé en gros + sticky mobile) |
| E-7 | (cette PR) | Documentation de session |

## Décisions structurantes

- **Une seule rampe d'activation** : `ChecklistActivation` (①Identité ②Documents
  ③Candidater) remplace 4 mécanismes concurrents (OnboardingGuide 7 slides,
  BandeauGraceDocuments, BandeauCompletionProfil, encart documents). Les bandeaux
  historiques ne reviennent qu'une fois l'activation terminée.
- **La valeur avant l'effort** : l'aperçu marché (`fn_apercu_marche_profession`,
  GRANT anon — agrégats uniquement, zéro PII) s'affiche dès la profession choisie,
  avant toute demande de document. Marché vide → preuve sociale de repli
  (« N établissements inscrits — soyez prévenu·e en premier »).
- **Les états vides recrutent** : « 🔔 Me prévenir » crée en un tap un filtre
  sauvegardé `alerte_active=true, IMMEDIATE` via les RPCs existantes du module
  filtres/alertes (idempotent). Aucun backend neuf.
- **Documents = photo + IA, zéro saisie** : champs dates supprimés du modal
  (l'edge `verify-document` les extrait), verdict inline sur la carte avec motif
  de rejet et « Réessayer », enchaînement automatique vers le document suivant.
- **Le RPPS ne tue plus l'inscription** : un numéro introuvable dans l'annuaire
  public passe en vérification manuelle sous 24 h (même chemin backend que
  `fhir_indisponible`) au lieu d'un bouton grisé définitif.

## Corrections de bugs au passage

- Filtre rayon de RechercheMissions inerte sans ville saisie (contrôle mensonger) → actif dès que la position est connue.
- `ModalDetailMissionSwipe` (231 lignes) écrite en Sprint 13 mais jamais branchée → câblée (tap card + bouton « Voir le détail »).
- « 20 Mo max » affiché vs 10 Mo réel dans le modal de téléversement → aligné.
- Spinner infini possible après « Recharger » sur le swipe → CTA retiré au profit des états vides honnêtes.

## Risques assumés (à surveiller en prod)

- Le rayon actif réduit les résultats pour les petits rayons (récupération : « Élargir le rayon »).
- Plus de saisie manuelle de dates : si l'extraction IA échoue, dates null jusqu'à revue admin (comportement inchangé par rapport au flux IA existant).
- La barre sticky ajoute un second bouton « Postuler » dans le DOM mobile (`md:hidden` — E2E desktop non affectés).

## Reste à faire (Sessions F et G — cf. stratégie)

- Session F : activation établissement + boucle de matching (mode « première
  mission », fusion des 2 pages d'activation, Republier 1 clic, badge
  candidatures + relance 24 h, taux conseillé).
- Session G : consolidation navigation (1 page missions, 1 hub argent,
  1 hub compte, nettoyage des routes doublonnées).
