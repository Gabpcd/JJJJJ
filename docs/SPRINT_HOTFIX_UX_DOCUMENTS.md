# Sprint Hotfix UX Documents — matrice profession + statut REJETE

Corrige 2 bugs UX découverts en test prod (Gabrielle, aide-soignante salariée).

## Bug 1 — Documents non pertinents selon profession + exercice

### Symptôme
Profil AS salariée → proposait RPPS_ADELI + RCP_ASSURANCE (or AS n'a ni Ordre ni exercice libéral). Pharmacien voyait RCP. Libéraux voyaient KBIS.

### Cause
- Table `documents_requis_par_profession` non alignée avec les règles métier
- Filtre frontend ne tenait compte que de la profession, pas du `type_exercice`

### Fix (PR 1 + PR 2)
1. **Migration** `20260527155700` : colonne `type_exercice_requis` (`SALARIE_ONLY`/`LIBERAL_ONLY`/`TOUS`) + re-seed complet + retrait KBIS
2. **Frontend** `DocumentsSoignant.tsx` : filtrage par profession ET type_exercice

### Matrice CEO (référence)

| Profession | Documents |
|---|---|
| AS, AES, PREPARATEUR_PHARMA | CNI + DIPLOME |
| PHARMACIEN, MANIPULATEUR_RADIO | + RPPS/ADELI (TOUS) |
| IDE, IBODE, IADE, SAGE_FEMME, MEDECIN, KINE | RPPS (TOUS) + RCP/RIB/URSSAF (LIBERAL_ONLY) |
| ORTHOPHONISTE, ERGO, PSYCHOMOT, DIETETICIEN | ADELI (TOUS) + RCP/RIB/URSSAF (LIBERAL_ONLY) |

Filtre : LIBERAL/MIXTE inclut LIBERAL_ONLY ; SALARIE/CDD l'exclut.

### Décision CEO — pas de casier judiciaire
Jolene ne demande PAS de B2/B3 :
- Pros à Ordre : vérif RPPS prouve que l'Ordre a déjà contrôlé le B2
- Pros sans Ordre (AS/AES) : l'établissement employeur fait son B3 à l'embauche
- Jolene = mise en relation, pas employeur

## Bug 2 — Statut REJETE affiché "Expiré"

### Symptôme
Un document rejeté par l'IA affichait "Expiré" au lieu de "Rejeté".

### Cause
`DocumentsSoignant.tsx` testait `estExpire` avant `estRejete`. Un doc REJETE dont l'IA avait extrait une `date_expiration` passée (du **mauvais** fichier uploadé) déclenchait `estExpire=true` → affichait "Expiré".

### Fix (PR 3)
1. **Frontend** : `estExpire` gated par `!estRejete` + ordre de rendu `estRejete` avant `estExpire`
2. **Edge function** `verify-document` : ne PAS écrire `valide_depuis`/`valide_jusqua` quand verdict=REJETE
3. **Cleanup données** : `UPDATE documents_soignants SET valide_jusqua=NULL, valide_depuis=NULL WHERE statut_verification='REJETE'` (5 docs)
4. **UX** : BadgeY2K distincts — REJETE `error` (rouge), EXPIRE `warning` (orange)

## RPPS vs ADELI

Le `type_document` reste `RPPS_ADELI` (enum unique). La distinction est portée par la `description` (RPPS pour IDE/médecin/pharmacien…, ADELI pour manip radio/orthophoniste/ergo…). La vérification Annuaire Santé (verify-rpps) accepte les 2 numéros.

## Tests E2E anti-régression

- `e2e/flows/documents-par-profession.spec.ts` : matrice par profil (AS, IDE salariée, IDE libérale, pharmacien, orthophoniste, manip radio…) + invariants (KBIS retiré, tous critique)
- `e2e/flows/document-statut-rejete.spec.ts` : invariant "aucun REJETE ne porte valide_jusqua" + test bout-en-bout verify-document REJETE → valide_jusqua NULL

## PRs livrées

| PR | # | Chantier |
|---|---|---|
| 1 | #354 | Migration matrice + type_exercice_requis |
| 2 | #355 | Filtrage frontend profession + exercice |
| 3 | #356 | Bug 2 précédence + verify-document + cleanup |
| 4 | this | Tests E2E + documentation |
