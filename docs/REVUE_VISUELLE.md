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

---

_Mettre à jour ce fichier à chaque PR UI (écran + preuve + états à vérifier ≤ 3 lignes)._
