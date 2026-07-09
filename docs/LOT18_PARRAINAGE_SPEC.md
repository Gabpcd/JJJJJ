# Lot 18 — Parrainage auto-financé : spec d'activation (POST-LAUNCH)

> **Statut : SPEC, PAS UNE ACTIVATION.** Décision feuille de route (09/07/2026) :
> le Lot 18 est explicitement post-launch et **conditionné à la liquidité
> réelle**. Ce document fige l'état des lieux et la checklist d'activation pour
> que la décision se prenne en 10 minutes le jour venu.

## 1. État des lieux — la mécanique est DÉJÀ en prod

Le cœur du Lot 18 (« trigger = commission encaissée, prime ≤ 50 % de la
commission au trigger ») est livré depuis le 02-03/07/2026 :

| Brique | Où | Valeurs live |
|---|---|---|
| Parrainage soignant v1 auto-financé | `20260702175827_parrainage_v1_gmv_25_cap50.sql` (+ triggers `20260528131400`, worker `131500`) | prime `prime_parrainage_eur` = **25 €**, seuil `seuil_gmv_parrainage_eur` = **500 €** de GMV encaissé (factures honoraires PAYEES) |
| Garde-fou auto-financement | même migration | la prime exige **commission encaissée ≥ 4× la prime** (cap ≤ 50 % même avec les deux primes parrain+filleul) — jamais de prime à découvert |
| Progression GMV visible | `20260702180753_parrainage_rpc_progression_gmv.sql` | RPC de progression côté soignant |
| Parrainage étab paliers GMV | `20260703180000_parrainage_etab_paliers_gmv.sql` | palier 1 : **50 €** à 500 € GMV ; palier 2 : **150 €** à 2 000 € GMV (crédit commission, pas de cash) |
| Notifications | `notifications_type_check` | `PARRAINAGE`, `CREDIT_PARRAINAGE`, `PARRAINAGE_PRIME_VERSEE` |
| UI | Revenus (banner retiré 7a §7.2, niveau 2 d'architecture), articles d'aide soignant + étab | discret volontairement — pas de mise en avant pré-launch |

**Tout est paramétré** via `parametres_systeme` : activer/ajuster ne demande
aucune migration.

## 2. Condition d'activation — liquidité réelle

« Activer » = pousser le parrainage en avant (dashboard, onboarding, récap
mensuel), pas poser du code. Critère mesurable proposé, à valider par Gabrielle :

1. **Commission nette encaissée** (Stripe, hors escrow non libéré) sur 30 j
   glissants ≥ **20× la prime unitaire** (500 € au tarif actuel) ;
2. **Zéro incident escrow ouvert** (aucune ligne `paiements_escrow` en anomalie,
   drift-check vert) ;
3. Runway bancaire ≥ 3 mois après provision des primes théoriques maximales du
   mois (nb filleuls actifs × 2 × prime).

Le garde-fou structurel (commission ≥ 4× prime **par filleul**) reste la vraie
protection : même activé trop tôt, le système ne verse jamais plus de 50 % de
ce qu'il a encaissé sur le filleul concerné.

## 3. Reste à faire à l'activation (petit)

- **Mise en avant produit** : carte parrainage dans le dashboard soignant +
  écran de partage (le lien/code existe), mention dans l'email de bienvenue.
- **F6 — récap mensuel** (seul vrai manquant technique) : email/notification
  mensuel soignant « ton mois chez Jolene » (heures, gains, score, prime de
  parrainage éventuelle). Brique : cron mensuel + template Resend + RPC
  d'agrégation (les données existent toutes : `fn_calculer_montant_periode`,
  score, parrainages). Estimation : 1 PR.
- **Suivi** : KPI hebdo primes versées vs commission encaissée des filleuls
  (requête SQL simple sur `parrainages` + `factures_honoraires`).

## 4. Ce qu'on ne fait PAS

- Pas de prime à l'inscription (anti-fraude : la prime reste conditionnée au
  GMV encaissé du filleul).
- Pas d'augmentation de la prime sans re-vérifier le ratio 4× (le cap 50 %
  est une borne dure, le 4× garde la marge).
- F7 (progression 3200 h) : déjà couvert par `/soignant/passer-en-liberal`
  (page PasserEnLiberal) — rien à faire au titre du Lot 18.
