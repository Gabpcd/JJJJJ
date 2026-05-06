# Règles d'installation en libéral par profession

Synthèse des règles d'installation en exercice libéral des professionnels de santé
utilisés sur Jolene. Sert de référence pour `src/lib/regles-installation-liberal.ts`
et pour la page `/soignant/passer-en-liberal`.

**v1 — Session 1 Phase C (avril 2026)**

---

## Tableau synthèse

| Profession | Heures requises | Période | Caisse retraite | Conventionné CPAM | Notes |
|---|---|---|---|---|---|
| **IDE** | 3 200 h | 6 ans | CARPIMKO | Oui | Convention nationale infirmiers 2007, art. 5.2.2 |
| **IBODE** | 3 200 h | 6 ans | CARPIMKO | Oui | Mêmes règles IDE |
| **IADE** | 3 200 h | 6 ans | CARPIMKO | Oui | Mêmes règles IDE |
| **Kiné (MK)** | 2 240 h | 2 ans | CARPIMKO | Oui | Option zone sous-dotée alternative |
| **Sage-femme** | — | — | CARCDSF | Oui | Pas d'expérience requise |
| **Médecin** | — | — | CARMF | Oui | Choix de secteur conventionnel (1/2/3) |
| **Orthophoniste** | — | — | CARPIMKO | Oui | Pas d'expérience requise |
| **Orthoptiste** | — | — | CARPIMKO | Oui | Pas d'expérience requise |
| **Pédicure-podologue** | — | — | CARPIMKO | Oui | Pas d'expérience requise |
| **Ergothérapeute** | — | — | CIPAV | Non | Paiement patient direct |
| **Psychomotricien** | — | — | CIPAV | Non | Paiement patient direct |
| **Diététicien** | — | — | CIPAV | Non | Paiement patient direct |
| AS, AES, Manipulateur radio, Pharmacien, Préparateur pharma | — | — | — | — | **Non éligible** exercice libéral Jolene |

---

## Sources officielles

### Conventions nationales / CPAM

- **Convention IDE** : [ameli.fr — Infirmier(e) libéral(e)](https://www.ameli.fr/infirmier/exercice-liberal)
- **Convention Kiné** : [ameli.fr — Masseur-kinésithérapeute libéral](https://www.ameli.fr/masseur-kinesitherapeute/exercice-liberal)
- **Convention Sage-femme** : [ameli.fr — Sage-femme](https://www.ameli.fr/sage-femme)
- **Convention Médecin** : [ameli.fr — Médecin](https://www.ameli.fr/medecin)
- **Convention Orthophoniste** : [ameli.fr — Orthophoniste](https://www.ameli.fr/orthophoniste)
- **Convention Orthoptiste** : [ameli.fr — Orthoptiste](https://www.ameli.fr/orthoptiste)
- **Convention Pédicure-podologue** : [ameli.fr — Pédicure-podologue](https://www.ameli.fr/pedicure-podologue)

### Ordres professionnels

- **Infirmiers (IDE/IBODE/IADE)** : [Ordre National des Infirmiers](https://www.ordre-infirmiers.fr)
- **Kiné** : [Ordre des Masseurs-Kinésithérapeutes](https://www.ordremk.fr)
- **Sage-femme** : [Ordre des Sages-Femmes](https://www.ordre-sages-femmes.fr)
- **Médecin** : [Conseil National de l'Ordre des Médecins](https://www.conseil-national.medecin.fr)
- **Pédicure-podologue** : [Ordre National des Pédicures-Podologues](https://www.onpp.fr)
- **Orthophoniste** : [FNO — Fédération Nationale des Orthophonistes](https://fno.fr)
- **Ergothérapeute** : [ANFE — Association Nationale Française des Ergothérapeutes](https://anfe.fr)

### Caisses de retraite

- **CARPIMKO** : infirmiers, kinés, orthophonistes, orthoptistes, pédicures-podologues — <https://www.carpimko.com>
- **CARCDSF** : sages-femmes, chirurgiens-dentistes — <https://www.carcdsf.fr>
- **CARMF** : médecins — <https://www.carmf.fr>
- **CIPAV** : professions para-médicales non conventionnées CPAM — <https://www.lacipav.fr>

---

## Catégories d'installation (code TypeScript)

Le champ `categorie` du type `RegleInstallation` permet de router l'UI de la page
"Passer en libéral" vers le bon guide d'installation :

| Catégorie | Professions | Guide UI |
|---|---|---|
| `AVEC_HEURES_IDE` | IDE, IBODE, IADE | Jauge 3 200 h sur 6 ans + attestations |
| `AVEC_HEURES_KINE` | KINE | Jauge 2 240 h sur 2 ans OU option zone sous-dotée |
| `AVEC_HEURES_IPA` | IPA (futur) | 3 ans IDE + master |
| `SANS_HEURES_CPAM` | Médecin, sage-femme, orthophoniste, orthoptiste, pédicure-podologue | Installation directe conventionné |
| `SANS_HEURES_CIPAV` | Ergothérapeute, psychomotricien, diététicien | Installation directe non conventionné |
| `NON_ELIGIBLE` | AS, AES, Manipulateur radio, Pharmacien, Préparateur pharma | Page "Passer en libéral" masquée |

---

## Historique des versions

- **v1 — Avril 2026 (Session 1 Phase C)** : création initiale du fichier constantes
  `src/lib/regles-installation-liberal.ts`, table `specialites_medicales`,
  colonnes de matching sur `soignants` et `missions`. Nomenclature ANS à
  consolider en Session 2 (refacto `verify-rpps`).
