# Revue visuelle — passe humaine globale (TestFlight)

Liste **cumulée** des écrans UI modifiés depuis le début du MODE AUTONOME, pour la
passe visuelle globale unique de Gabrielle (les assertions garantissent le
comportement ; l'œil humain garantit le rendu). Cf. skill `verify-recette`.

Viewports : écrans **établissement** = **390×844 ET 1440×900** (règle critique).

---

## 1. Formulaire « Publier » — établissement (PR #839, mergé)

**Écran** : `/etablissement/missions/creer` — bloc « Jours et horaires ».
**Preuve machine** : `src/lib/planning-derive.test.ts` (11 tests) + e2e double viewport.
**À vérifier (desktop 1440 ET mobile 390)** — saisir Du 22/07/2026 → Au 29/07/2026 :
- « Horaires par jour » : 1ʳᵉ ligne = **Mer. 22/07** (plus Lundi) ; lundi en 6ᵉ, daté **Lun. 27/07**.
- Récap semaines : **Semaine du 20/07 : 60h** en rouge, Semaine du 27/07 : 36h vert ; bouton **Publier grisé**.

## 2. Badge score qualité établissement (PR #846, mergé)

**Écran** : `DetailMissionSoignant` → `BadgeScoreEtabPublic` (côté soignant).
**Preuve machine** : assertion SQL (étab seed 0 éval → score NULL).
**À vérifier** : un établissement sans ≥ 3 évaluations publiées affiche **« Nouveau »**, jamais un score chiffré (même s'il a une `note_moyenne` seed).

## 3. Blocage utilisateur — messagerie (Phase 2)

**Écran** : fil de discussion (`ChatConversation`, header) — soignant ↔ établissement.
**Preuve machine** : `fn_envoyer_message` refuse si blocage bilatéral (migration `20260711193000`).
**À vérifier** :
- Header du chat : lien **Bloquer** (puis confirmation « Confirmer / Annuler »).
- Après blocage : le lien devient **Débloquer** ; l'envoi d'un message renvoie « Vous ne pouvez plus échanger avec cet utilisateur (blocage actif) ».
- Débloquer : le lien redevient Bloquer, l'envoi refonctionne.

## 4. Cockpit fondateur à source unique — montants d'argent (Lot 19)

**Écrans** : `/admin` (`AdminDashboard`, « Tableau de bord ») + `/admin/cockpit-fondateur` (`AdminCockpitFondateur`).
**Preuve machine** : `e2e/flows/cockpit-metriques-argent.spec.ts` (gate admin, `etab_a_valider` == file, invariants HT/TTC, GMV/revenus identiques entre les 2 cockpits) + assertions tx-live prod (migration `20260712120000`).
**À vérifier (desktop 1440)** — connecté en admin, données de test présentes en base :
- KPI argent : **Commission Jolene ce mois (HT)**, **Encaissé (commission, HT)** avec « X TTC · sur compte », **GMV (volume brut transité)** — libellés HT/TTC explicites, valeurs = celles de la carte « Rentabilité » (même source).
- Bandeau **« Données de test présentes »** (icône fiole) au-dessus des KPI argent tant que des comptes test existent ; les montants affichés **excluent** les seeds.
- Alerte **« N établissements à valider »** = exactement le nombre de la page `/admin/verification-etablissements` (plus de 10 vs 6).
- Carte Stripe renommée **« Paiements Stripe (bruts, TTC) »** (plus de 2ᵉ « Encaissé ») ; carte Stripe Connect **sans** second « GMV ».

---

_Mettre à jour ce fichier à chaque PR UI (écran + preuve + états à vérifier ≤ 3 lignes)._
