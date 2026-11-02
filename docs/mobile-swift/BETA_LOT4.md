# Bêta externe — lot 4

> Squelette créé le 2026-11-02 par la tranche T0 (`docs/mobile-swift/LOT4_PLAN.md` §3 T0), tenu à jour pendant
> la bêta et clos en T15. Critères du plan §5 « Lot 4 » (l.208, l.210) tels qu'amendés par
> `docs/mobile-swift/DECISIONS_LOT4.md` (D21) : crash-free sessions ≥ 99,5 % sur 14 jours de bêta et aucun
> retour bêta bloquant ouvert. La mesure chiffrée finale est reportée dans `docs/mobile-swift/PORTE_LOT4.md`
> (T15). Aucune donnée personnelle de testeur n'est collée ici (identifiants TestFlight anonymisés).

## 0. Build et cohorte

| Élément | Valeur | Date |
|---|---|---|
| Build TestFlight externe fonctionnellement complet (T3b à T13) | — | — |
| Release Sentry exacte du build | — | — |
| Groupes TestFlight externes (taille) | — (Gabrielle, `DECISIONS_LOT4.md` « En attente » n°7) | — |

## 1. Beta App Review

| Version / build | Soumis le | Verdict Apple | Remarques |
|---|---|---|---|
| — | — | — | chaque nouvelle version repasse en Beta App Review ; numéros de build croissants (`CURRENT_PROJECT_VERSION`) |

## 2. Retours triés (bloquant / non bloquant)

Un retour est **bloquant** s'il casse l'un des onze parcours cœur (`PARITE_SOIGNANT.md`, section lot 4), fait
perdre une donnée, affiche un texte juridique non verbatim (HARD STOP n°4) ou provoque un crash reproductible ;
sinon il est **non bloquant**. L'arbitrage final appartient à Gabrielle.

| # | Date | Source (TestFlight, Sentry, support) | Description | Classement (bloquant / non bloquant) | Statut | Décision Gabrielle |
|---|---|---|---|---|---|---|
| — | — | — | — | — | — | — |

## 3. Mesure crash-free (D21)

- Fenêtre de **14 jours** sur le build ci-dessus, release Sentry exacte, **au moins 400 sessions** ; en dessous,
  le critère est « non mesurable » et le lot n'est pas clos.
- Seuil : crash-free sessions **≥ 99,5 %**.
- Un build correctif publié pendant la fenêtre est agrégé s'il ne corrige qu'un défaut sans crash ; **toute
  correction de crash redémarre la fenêtre** sur la nouvelle release.

| Release | Début | Fin | Sessions | Crash-free | Lien Sentry |
|---|---|---|---|---|---|
| — | — | — | — | — | — |

## 4. Clôture

| Critère | Valeur |
|---|---|
| Retours bloquants ouverts | — |
| Crash-free sur 14 jours (≥ 400 sessions) | — |
| Verdict Gabrielle (date) | — |
