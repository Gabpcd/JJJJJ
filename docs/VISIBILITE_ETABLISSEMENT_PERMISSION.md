# Visibilité établissement par permission — B5b (lot 5, B9, en attente de Gabrielle)

> Préparé le 2026-11-02 avec la PR B5b (branche `fix/visibilite-etablissement-par-permission`,
> migration `20261102210943_visibilite_etablissement_par_permission.sql`). Catégorie B9
> (fonctions `SECURITY DEFINER`) : **go explicite de Gabrielle avant merge**. Sauf mention,
> `l.N` renvoie à `supabase/schema/public.sql` (re-baseline du 01/11/2026). Rôles d'équipe et
> permissions : `fn_a_permission_etablissement` (l.4905-4934), lue par le web via
> `fn_mes_permissions_etab` (`src/hooks/useEtabPermissions.ts`).

## 1. Ce que ferme B5b (étage RPC seulement)

Les clés restent présentes dans la réponse et valent `null` ; les rôles habilités reçoivent
exactement la même réponse qu'avant (contrôlé par le banc PG17
`tests/security/visibilite-etablissement-permission-isolated.test.sql` : 11 acteurs × 5 lectures,
avant puis après la vraie migration, liste fermée des différences admises).

| RPC | Champ | Servi seulement avec | Rôles qui le perdent |
|---|---|---|---|
| `fn_etat_pointage_mission` | `code_pointage_actif` | `pointage` | `LECTURE_SEULE` |
| `fn_etat_pointage_mission` | réponse entière | lien avec la mission (un `NULL` dans la garde vaut refus) | soignant tiers, session sans identité ; sur une mission non affectée : soignant, membre d'un autre établissement, propriétaire historique d'un autre établissement |
| `fn_stats_dashboard_etablissement` | `commissions_cumulees`, `commissions_impayees` | `lecture_paiement` ∨ `paiement` | `RH`, `POINTAGE_ONLY` |
| `fn_stats_dashboard_etablissement` | `candidatures_recentes` (noms complets) | `lecture_candidatures` | `POINTAGE_ONLY` |
| `fn_mon_etablissement_complet` | `stripe_customer_id`, `stripe_account_id` | `paiement` | `RH`, `POINTAGE_ONLY`, `LECTURE_SEULE` |
| `fn_mon_etablissement_complet` | `iban_last4` | `lecture_paiement` ∨ `paiement` | `RH`, `POINTAGE_ONLY` |

Le verrou `NULL` de `fn_etat_pointage_mission` est le « constat voisin » n° 2 de
`docs/POINTAGE_CODE_ROTATIF_VISIBILITE.md` §4 (branche B1 `fix/scanner-code-sans-code-suivant`).

## 2. Écarts assumés avec le blueprint du lot 5 (§3 B5b)

1. **`iban_last4` sous `lecture_paiement` ∨ `paiement`** (le blueprint dit « sans `paiement` ») :
   l'onglet Paramètres › Facturation n'a pas de garde de permission (`src/pages/Parametres.tsx`
   l.125-126) et `src/pages/ProfilEtablissement.tsx` l.885 y affiche « RIB vérifié — IBAN se
   terminant par … » ; `LECTURE_SEULE` (lecture financière, `canReadFinance` du web) garde cet
   affichage. Les identifiants Stripe, qu'aucun écran ne lit, suivent le blueprint (`paiement`).
2. **`rib_s3_key` servi à tout membre** : le masquer ferait afficher « Aucun RIB fourni »
   (`ProfilEtablissement.tsx` l.884-890) à un établissement qui en a fourni un. Il reste lisible à
   l'étage RLS de toute façon (§4).
3. **`nb_factures_impayees` conservé pour tout membre** : compteur sans montant de la tuile
   « Règlements à effectuer » (`src/pages/DashboardEtablissement.tsx` l.854-858), conforme à D15
   (compteurs sans montant).

## 3. Surfaces web relues (avant merge)

- **Carte du code de pointage** (`src/components/pointage/AffichageCodeRotatifEtab.tsx`, montée par
  `DetailPresencesMission.tsx` l.494 et `DetailMission.tsx` l.1325) : réservée dans la même PR à
  la permission `pointage` de l'établissement de la mission (`useEtabPermissions`). Sans elle :
  « Le code de pointage est réservé aux membres disposant du droit de pointage pour cet
  établissement. », aucune lecture de `fn_etat_pointage_mission`, de planning ou de signature,
  aucun polling de 5 s. Sans ce changement, `LECTURE_SEULE` aurait lu « Code momentanément
  indisponible. Actualisez dans quelques secondes. » pendant toute la fenêtre de pointage, avec une
  relecture toutes les 5 s, et le code ne serait jamais apparu.
- **Accueil** : `candidatures_recentes` et `commissions_*` ne sont rendus nulle part ; leur lecture
  tolère `null` (`DashboardEtablissement.tsx` l.267 et l.274). Affichage inchangé pour tous les
  rôles.
- **Paramètres › Facturation** : `RH` et `POINTAGE_ONLY` lisent « RIB vérifié » sans suffixe ;
  `LECTURE_SEULE` et les rôles `paiement` sont inchangés.
- **Identifiants Stripe** : aucun lecteur de `fn_mon_etablissement_complet` ne les lit
  (`FacturationEtablissement.tsx`, `DetailFacture.tsx`, `FormulaireMission.tsx`,
  `TolerancePointageGps.tsx`, `DashboardEtablissement.tsx`, `ProfilEtablissement.tsx`).
- **App iOS native** : aucun lecteur aujourd'hui (`ios-native/rpc-contracts.json` :
  `fn_etat_pointage_mission` « à venir », lot 2).

## 4. Étage RLS / PostgREST resté ouvert — suivi « B5c » (B9, en attente de Gabrielle)

B5b ne filtre que les réponses des trois RPC. Le principe « filtre de visibilité centralisé » de
`CLAUDE.md` n'est donc pas encore tenu pour ces colonnes :

- **`etablissements`** : `GRANT SELECT ON TABLE` à `authenticated` (l.86012) et `pol_etab_select`
  (l.79167 : `id = mon_etablissement_id()` pour tout membre) → `stripe_customer_id`,
  `stripe_account_id`, `iban_last4` et `rib_s3_key` restent lisibles par tout membre en
  `GET /rest/v1/etablissements?select=…`.
- **`missions`** : `GRANT SELECT` à `authenticated` (l.86261) et `pol_mission_select` (l.79363 :
  membre avec `lecture_missions`, vrai pour tous les rôles) → `code_pointage_actif` reste lisible
  par `LECTURE_SEULE` en PostgREST direct. Le même trou pour le soignant assigné est instruit par
  « B1-ter » (`docs/POINTAGE_CODE_ROTATIF_VISIBILITE.md`, branche B1).
- **Realtime** : `docs/cp5b-creneaux-et-pointage.md` l.301 prévoyait un abonnement Realtime sur
  `missions` ; la relecture de production du 02/11 (B1-ter §2) ne trouve `missions` dans aucune
  publication. Realtime appliquant la RLS de SELECT, l'ajout de `missions` à une publication
  rouvrirait ce trou.

**Proposition B5c (non implémentée)** : un privilège de colonne ne distingue pas les rôles
d'équipe (tous les membres sont `authenticated`). La fermeture consiste donc à retirer ces colonnes
du SELECT de `authenticated` (REVOKE SELECT de table puis GRANT SELECT des autres colonnes, liste
calculée depuis `information_schema.columns`, modèle B1-ter §3) et à ne les servir que par les RPC
déjà filtrées (`fn_mon_etablissement_complet`, `fn_etat_pointage_mission`). Préalables : audit des
quatre étages (`pg_proc`, `pg_policy`, `git grep from('etablissements')` / `from('missions')` dans
`src/`, `ios-native/` et `supabase/functions/`, en particulier les `select('*')` et les écrans
admin) pour éviter des 42501 ; garde durable sur les colonnes interdites ; banc PG17 ; recette.
À coordonner avec B1-ter (mêmes GRANT sur `missions`).

## 5. Candidats additionnels du blueprint (§3 B5b, correction 17, D28)

| Point | État | Référence |
|---|---|---|
| `fn_declarer_fin_retroactive` ne renvoie plus `nouveau_code` / `nouveau_hmac` | couvert par la PR sœur B1 | branche `fix/scanner-code-sans-code-suivant`, migration `20261102205212_scanner_code_sans_code_suivant.sql` |
| `fn_declarer_fin_retroactive` refuse `p_heure_fin > now()` (D28) | **en attente** : aucune branche | PR B9 « B5d » à ouvrir après B1 (même fonction : partir de son corps LIVE après B1) |
| `fn_contester_presence` refuse une présence déjà validée (aucun contrôle, l.25822-25835) | **en attente** : aucune branche | PR B9 « B5e » (escrow : `motif_litige` bloque la libération, l.63177) |

La tranche T0 du lot 5 reporte ces deux points dans `docs/mobile-swift/DECISIONS_LOT5.md`, section
« En attente de Gabrielle », avec renvoi ici. D'ici là, le natif borne le sélecteur de clôture
rétroactive à [début du segment ouvert, maintenant] (D28).

## 6. Ordre de merge

Migrations du 02/11/2026 en attente de merge : `20261102204450` (drapeaux lots 2, 4 et 5,
`feat/drapeaux-ios-natif-lots-2-4-5`), `20261102204820` (`fix/score-matching-inconnu-null`),
`20261102205212` (B1, `fix/scanner-code-sans-code-suivant`), `20261102205808`
(`fix/contestation-paiement-soignant`), puis `20261102210943` (B5b). Dernière version en
production relevée par la revue fraîche du 02/11 : `20261102150000`.

**B5b se merge en dernier.** Merger B5b avant l'une de ces PR rendrait sa migration
out-of-order et ferait virer `deploy-supabase` au rouge (`CLAUDE.md`, règles migrations n° 2).
À défaut, re-horodater au merge : renommer le fichier et mettre à jour les trois `\ir` (un dans
`tests/security/visibilite-etablissement-permission-isolated.test.sql`, deux dans
`tests/security/visibilite-etablissement-permission-rejeu.test.sql`) ; le contrôle Node
`tests/node/visibilite-etablissement-permission.node.mjs` lit le nom du fichier et vérifie ces
trois inclusions. Vérifier `list_migrations` avant le push.

## 7. Recette

- **Fait** (simulation à réponses simulées, vitest,
  `src/components/pointage/AffichageCodeRotatifEtab.test.tsx`) : `PROPRIETAIRE`, `ADMIN_GROUPE`,
  `RH`, `POINTAGE_ONLY`, `ADMIN_PLATEFORME` voient le code et le QR ; `LECTURE_SEULE` et un compte
  sans rôle lisent le texte exact de la carte, sans aucun appel d'état ; vérification et erreur des
  droits ; `DetailPresencesMission.pointage.test.tsx` vérifie l'établissement transmis.
- **Préparé** (CI `validate-pr`, PostgreSQL 17 éphémère, exécuté à l'ouverture de la PR) : banc
  isolé par rôle et refus du rejeu. Hors CI, seuls la syntaxe (libpg_query 17) et le contrôle Node
  hors réseau ont été vérifiés.
- **Non fait** (hors du mandat des agents : aucun Playwright, aucune écriture STAGING) : recette
  dans l'interface pour `LECTURE_SEULE`, `RH` et `POINTAGE_ONLY` sur DetailPresencesMission,
  DetailMission, Accueil et Paramètres › Facturation, en 390 × 844 et 1440 × 900, avec preuves
  ARIA/texte. À faire avant le merge, sinon acceptation explicite de Gabrielle au go B9.
