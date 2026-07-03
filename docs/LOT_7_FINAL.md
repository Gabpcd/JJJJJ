# Lot 7 v2 — Bilan final (session du 02/07/2026)

> 11 PRs mergées (#771 → #781, #777 fermée sans merge), 12 migrations prod,
> ~40 fichiers front. Méthode : cartographie de l'existant avant chaque
> chantier, branchement sur l'existant plutôt que réécriture.

## ⚠️ Note de correction — bonus parrainage +50 h

Le bilan de session et le corps de la PR #780 présentaient le retrait du bonus
« +50 h sur `heures_cumulees` » comme une décision du 02/07. **C'est inexact** :
le retrait date du **28/05/2026** (migration `20260528162230_supprimer_bonus_50h_parrainage.sql`),
pour le même motif (heures fictives dans le compteur 3 200 h à valeur légale).
La réécriture du trigger le 02/07 a *préservé* ce retrait — le comportement
prod sur ce point n'a pas changé depuis mai. L'erreur vient d'un raisonnement
sur un fichier repo obsolète (`20260528131400`, antérieur au retrait) au lieu
de la définition live — la même cause que l'incident enum ci-dessous.
**Décision confirmée 04/07 : le retrait est définitif ; `heures_cumulees` ne
bouge jamais hors missions réelles. Récompense de remplacement = boost de
candidature (monnaie pré-lancement, §11 Lot 7 v2).**

## 7a — Suppressions & reframes §7 (PR #771)

- Rist côté soignante : « ⚠️ plafonné » → « ✓ conforme » (warning conservé côté étab/admin).
- Parrainage : banner retiré de Revenus, carte discrète en bas d'Accueil ; entrée Compte + page conservées.
- Salarié pur : « Prélèvements estimés ~0 € » → « Brut total » (le reste était déjà gated Lot 6d).
- Recherches sauvegardées vide → ligne compacte.
- « Avance sous 48h » : déjà retiré au Lot 6 (vérifié, rien à faire).
- Échéances fiscales : `soignants.regime_fiscal` (micro-BNC défaut « à confirmer », question 1-tap
  dans Mes charges), copy « Déclaration de tes revenus N (formulaire X) », micro-BNC → 2042-C-PRO.
- Migration : `20260702150952`.

## 7b — Chaîne F1+F4 (PR #772)

Trois systèmes de pointage empilés découverts ; cible interne = code rotatif.
**Arbitrages produit (02/07)** : GPS soft (le code rotatif est la preuve de
présence, le GPS alerte sans bloquer) · validation des présences = gate de la
facture FINALE (manuelle 1 tap ou auto-72h ; présence contestée gèle finale ET
hebdo ; l'hebdo n'est pas gaté — cash-flow) · notation 1-tap (note globale
obligatoire, 4 critères optionnels).

- « Valider et noter » en un geste côté étab (+ mini-dialog dans la vue tableau).
- Sheet notation au check-out soignante (une fois par mission, skippable).
- Pont `evaluations` ↔ `notations_missions` dans le bandeau (pas de double sollicitation).
- Audit paiements §2.5 → `docs/AUDIT_PAIEMENTS_2_5.md` (7 trous escrow documentés).
- Migrations : `20260702154526` (gate), `20260702154904` (notation EN_COURS + départ pointé).

## 7c — Badge ⚡ + SEPA opt-out (PR #773)

- Infra ⚡ complète **derrière `feature_paiement_rapide_actif` = 0** (règle n°2 :
  pas de promesse 24-72 h sans escrow). Flip = paramètre admin, sans redéploiement.
- Gating 100 % serveur : mission LIBERAL + étab SEPA actif (`mode_paiement_commission='SEPA_DEBIT'`
  + `stripe_sepa_payment_method_id`). Exposé dans le payload swipe + `fn_etablissements_safe`.
- Étape 3 d'activation étab : « Paiement des commissions » — SEPA en opt-out
  (réutilise le flux SetupIntent existant de Paramètres → Profil), « passer cette étape » discret.
- `jour_paie_habituel` étab → « Salaire versé vers le X » sur missions salariées.
- Collisions réglées : ⚡ Urgent → 🔥 Urgent (swipe) ; affacturage « paiement rapide » → « avance de paiement ».
- Migration : `20260702161909`.

## 7d — Algorithmes A1-A4 (PRs #774, #775, #776)

- **Scoring v3** : tarif vs **médiane de marché** de la profession (90 j,
  `marche_taux_medians`), **pattern horaire appris** des swipes
  (`matching_preferences_soignant`, Laplace, sans ML), bonus « tu connais cet
  établissement » +8, ⚡ +5. Pondérations : tarif 20 · distance 20 · horaire 15 ·
  étab 15 · urgence 10 · fiabilité 10 · fraîcheur 5, cap 100. Fix label
  « Pourquoi 85 ? » (`fiabilite` → `soignant_fiabilite`).
- **Deck** : exploration 10-15 % (jitter 0-12 pts), cap 1 push MISSION_A_POURVOIR/20 h.
- **A3 vagues urgentes** (cron */15) : top 10 → top 30 (T+15) → top 60 (T+30),
  dédup par (soignante, mission), max 3 pushs urgents/24 h. Additif au pool opt-in.
- **A4 no-show** : confirmation J-1 en **push natif** + relance H-12 + alerte
  étab H-6 ; au no-show, **candidats non retenus recontactés en priorité**.
- **Cold start** : quiz 5 questions (première visite Explorer, zéro swipe en base,
  comptes E2E exclus) → filtres pré-remplis + `fn_initialiser_preferences_matching`
  (n'écrase jamais des préférences apprises).
- Migrations : `20260702164341`, `20260702165857`, `20260702170752`.

## 7e — Re-booking, score, anti-leak (PRs #778, #779 ; #777 fermée)

- **#777 fermée sur décision produit** : l'« option DUR » anti-leak reste (message
  refusé, pas masqué). #778 = compatible seulement : détection enrichie
  (« zéro six » en lettres, calendly/doctolib), **exemption post-confirmation**
  (mission ASSIGNEE/EN_COURS/TERMINEE = plus de blocage), compteur `recidive_n`.
- **F2** : modal re-book **pré-remplie** (mêmes horaires, J+7), « Reproposer une
  mission » sur le profil soignant, `fn_demander_a_retravailler` (« Redemander à
  travailler ici », dédup 7 j), colonne **`missions.mission_source`**
  (SWIPE/CANDIDATURE/REBOOK/PROPOSITION_DIRECTE/REMPLACEMENT) — North Star
  anti-fuite mesurable.
- **F3** : rien à coder — score déjà affiché partout côté étab (audit).
- Migration : `20260702174205`.

## 7f — Parrainage v1 (PRs #780, #781)

- 🐛 **Fix critique** : l'attribution soignante était morte depuis le Sprint 17-A
  (`?ref=` capté, `fn_appliquer_parrainage` jamais appelée). Fix :
  `useAppliquerParrainage` (1ʳᵉ session, fenêtre 30 j, alias `?parrain=`).
- Mécanique : 50+50 € à 100 € de commission → **25+25 € à 500 € de GMV encaissé**
  (`gmv_cumule_filleul` + trigger sur `factures_honoraires` PAYEES) avec double
  condition commission ≥ 4× prime = **cap ≤ 50 % garanti par construction**.
  Montants/seuil paramétrables (`prime_parrainage_eur`, `seuil_gmv_parrainage_eur`).
- Jauge « Plus que X € de missions avant vos primes » par filleul.
- Prompts aux **pics d'émotion** : post-note 4-5★, post-premier-paiement,
  throttle global 30 j.
- Conservé : anti-fraude MEME_IP, badge Ambassadeur, parrainage étab→étab.
- Migrations : `20260702175827`, `20260702180753`, hotfix `20260702181918`.

## 🔥 Incidents de session (résolus)

1. **Enum statut_mission (21 min, 17h58-18h19 UTC)** : trigger parrainage réécrit
   depuis un fichier repo obsolète → `COALESCE(OLD.statut, '')` sur l'enum →
   22P02 sur toute transition de statut mission. Hotfix `20260702181918`.
   Leçon (règle CLAUDE.md renforcée) : toute redéfinition part de
   `pg_get_functiondef`, jamais d'un fichier repo.
2. **Registre migrations** : l'enregistrement `20260702180753` a disparu du
   registre → `deploy-supabase` rouge (out-of-order). Réinséré manuellement.
   Ces deux incidents motivent le **Lot 9.0** (réconciliation repo ↔ prod).

## Reste à faire (repris au Lot 9)

- **7b-D escrow** → débloqué par la section 4 du Lot 9 (cadre PSP Stripe Connect,
  destination charges + payouts manuels, aucun fonds sur le solde plateforme).
- **7f-3** : paliers étab GMV (50 €/500 + 150 €/2000) + CTA « recommande ton
  cadre de santé » + RPPS unique → Lot 9 §2.6.
- **P2** (F5 calendrier dispos, F6 récap mensuel, F7 progression 3 200 h) →
  updates post-lancement.
- Hors code : one-pager « Ce que le direct vous coûte » (6.1), clauses CGV
  non-contournement + grille titularisation (6.2, rédaction avocat).
