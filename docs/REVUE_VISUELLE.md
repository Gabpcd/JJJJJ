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

## 5. Sidebar admin — 5 domaines (Lot 20)

**Écran** : toute page `/admin/*` (sidebar desktop `LayoutAdmin`, 1440×900) + regroupement mobile 390×844 (bottom bar + « Plus »).
**Preuve machine** : `e2e/flows/admin-recherche-globale.spec.ts` (recherche unique → soignant + étab + mission) + `git grep` zéro libellé anglais dans la nav + redirect `/admin/healthcheck`→`/admin/status`.
**À vérifier (desktop 1440)** — connecté admin :
- Sidebar = **5 domaines** dans l'ordre : **Opérations · Argent · Croissance · Conformité & légal · Système** (plus de « Pilotage / Utilisateurs / Finances »).
- Labels français : **Prospection** (ex « Sales / Sourcing »), **Cohortes & économie** (ex « economics »), plus de **Healthcheck** (fusionné dans « Statut système »).
- Ouvrir `/admin/healthcheck` → redirige vers **Statut système** (`/admin/status`).
- ⌘K : taper 2+ caractères → résultats mêlés soignants / établissements / missions / factures.
- Chaque ancienne destination a exactement une entrée (Cockpit fondateur dans **Croissance**, Vérif. établissements unique dans **Opérations**).

## 6. Statut système — fusion des diagnostics Healthcheck (Lot 21-1)

**Écran** : `/admin/status` (« État du système »). L'ancienne page `/admin/healthcheck` est supprimée (redirige ici depuis Lot 20).
**Preuve machine** : `tsc -b` vert + suppression de la page + composant `PanneauxHealthcheck` monté dans `AdminStatus`.
**À vérifier (desktop 1440)** — connecté admin, en bas de « État du système » :
- Section **« Vérification des services (warm pings) »** : grille de ~11 services (PostgreSQL, Auth, Edge, Stripe, Twilio, Document AI, Resend, **Pro Santé Connect**, **Chorus Pro/PISTE**, **Annuaire RPPS**) + bouton « Revérifier ».
- Carte **« Pro Santé Connect »** avec bouton « Vérifier connexion PSC » (secrets / discovery OIDC / endpoints).
- Carte **« SMS Twilio »** avec champ téléphone préchargé + bouton « Tester SMS ».
- Ouvrir `/admin/healthcheck` → redirige vers `/admin/status` et **tous ces outils sont présents** (plus de perte fonctionnelle).

## 7. Suspension d'un compte — motif obligatoire (Lot 21-2)

**Écrans** : `/admin/utilisateurs` (cartes/table) + `/admin/utilisateurs/:id` (détail).
**Preuve machine** : `e2e/flows/admin-suspension-motif.spec.ts` (refus sans motif ; succès + motif dans `journaux_audit` ; réactivation cleanup) + assertions tx-live prod (migration `20260712140000`).
**À vérifier (desktop 1440)** — connecté admin :
- Bouton **« Suspendre »** rétrogradé en **secondaire** (plus en rouge/destructif proéminent) ; « Détails » reste accessible.
- Cliquer « Suspendre » → **modale avec champ Motif obligatoire** ; le bouton « Suspendre le compte » est **désactivé tant que le motif est vide**.
- Idem sur la page détail (`ModalActionAvecRaison`) ; la réactivation reste une simple confirmation (sans motif).
- Après suspension : toast « Utilisateur suspendu », le badge passe à suspendu, « Réactiver » apparaît.

---

_Mettre à jour ce fichier à chaque PR UI (écran + preuve + états à vérifier ≤ 3 lignes)._
