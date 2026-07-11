---
name: verify-recette
description: >-
  Protocole de preuve de recette pour Jolene. À utiliser pour recetter tout
  écran (UI) ou toute règle métier avant de déclarer une PR « livrée ». Remplace
  l'exigence historique de « screenshots » par des ASSERTIONS : la preuve machine
  est une assertion sur le texte/état exact rendu (test unitaire sur fonction
  pure, ou assertion Playwright sur le DOM/texte/état), jamais une image. Les
  images ne sont que des artefacts optionnels pour l'humain. Déclenche sur :
  « recetter », « recette », « verify-recette », « preuve », « valider un écran »,
  « double viewport établissement ».
---

# verify-recette — Protocole de preuve par assertions

> **Principe fondateur.** La preuve machine d'une recette = **des assertions,
> jamais des images.** Une capture d'écran ne prouve rien de reproductible : elle
> ne casse pas la CI quand le rendu régresse, et elle n'est pas relisible par une
> machine. Toute vérification visuelle exigée par une recette devient une
> **assertion sur le texte/état exact rendu**.

## Ordre du protocole (à suivre dans cet ordre exact)

1. **Assertions** (la seule preuve qui compte)
2. **Dump ARIA/texte** avant/après (relisible sans ouvrir l'app)
3. **Artefacts si l'environnement le permet** (screenshots headless commités — artefacts, jamais preuve)
4. **Passe humaine sur la preview Vercel** (vérification visuelle finale)

---

## 1. Assertions — la preuve machine

Toute vérification visuelle exigée par une recette devient une **assertion sur le
texte/état exact rendu** :

- **Valeur calculable → test unitaire sur une fonction pure.** Dès qu'un montant,
  une durée, une majoration, un statut dérivé est le résultat d'une fonction, on
  teste la fonction directement (entrée connue → sortie exacte attendue). Pas
  besoin de navigateur pour prouver que `heures_facturees = GREATEST(prévu,
  effectif)` hors pause.
- **Rendu non calculable → assertion Playwright sur le texte/DOM/état exact.**
  `await expect(page.getByText('255,00 €')).toBeVisible()`,
  `await expect(locator).toHaveText(...)`, assertions sur les classes/attributs
  d'état (badge, `aria-*`, `disabled`), un rendu testé **par état** (chaque état
  distinct d'un écran a son assertion).
- Une assertion vague (« la page charge ») ne prouve rien : on assert le **texte
  exact**, le **montant exact**, l'**état exact**.

## 2. Dump ARIA/texte lisible avant/après

Chaque écran recetté produit un **snapshot ARIA/texte** collé dans la description
de la PR — relisible sans ouvrir l'app, diffable d'une recette à l'autre :

```ts
// Playwright — snapshot ARIA de référence (échoue si l'arbre régresse)
await expect(page.locator('main')).toMatchAriaSnapshot(`
  - heading "Mes revenus" [level=1]
  - text: "255,00 €"
  ...
`);

// ou capture brute à coller dans la PR :
const dump = await page.locator('main').ariaSnapshot();
console.log(dump);
```

Coller le dump **avant/après** dans le corps de la PR : c'est la trace lisible du
changement, sans image.

## 3. Artefacts optionnels (screenshots headless)

Si l'environnement le permet, produire des captures **headless** vers
`recette/AAAA-MM-JJ/<ecran>.png`, commitées. Ce sont des **artefacts pour
Gabrielle**, **JAMAIS la preuve** — la preuve reste les assertions du point 1.

```ts
await page.screenshot({ path: `recette/${date}/${ecran}.png`, fullPage: true });
```

Installation du navigateur : tenter **une fois** `npx playwright install chromium`.
Si indisponible (réseau/sandbox), le **noter** dans le rapport/PR et **continuer
sans** — l'absence d'artefact ne bloque jamais la recette (les assertions et le
dump ARIA suffisent comme preuve).

## 4. Vérification visuelle finale = humaine

Chaque PR **UI** se termine par :

- son **URL de preview Vercel** ;
- la **liste des écrans à regarder** et **quoi y vérifier** — **3 lignes max par
  écran**.

**Le merge d'une PR UI attend cette passe humaine.** Les assertions garantissent
le comportement ; l'œil humain sur la preview garantit le rendu (alignement,
couleur, débordement) que les assertions ne couvrent pas.

---

## Double viewport établissement — RÈGLE CRITIQUE

Les écrans **établissement** se vérifient sur **DEUX** tailles :

- **390 × 844** (mobile, iPhone)
- **1440 × 900** (desktop)

> Le bug **période → jours travaillés → horaires** du formulaire « Publier » a
> survécu à toutes les recettes précédentes parce qu'elles étaient calibrées
> **mobile uniquement**. Le comportement cassé n'apparaissait qu'en desktop.

**Toute recette d'un écran établissement DOIT couvrir les deux tailles** —
assertions ET dump ARIA ET (si dispo) artefacts, pour chacun des deux viewports.

```ts
for (const vp of [{ width: 390, height: 844 }, { width: 1440, height: 900 }]) {
  await page.setViewportSize(vp);
  // assertions + ariaSnapshot + screenshot par viewport
}
```

---

## 5. Recette d'une règle backend (SQL) = INSERT/RPC RÉEL, pas la lecture d'une migration

Une fonction SQL, un trigger, une RLS, un CHECK ne sont **jamais** prouvés en lisant
le fichier de migration (il peut être obsolète vs la déf LIVE) : on les prouve par
un **INSERT ou un appel RPC réel** contre la base, en **assertant l'état exact**
produit. Voir `tests/invoicing/{grants,rls,immutability,numbering,mandate}.test.ts`
(connexion `pg`, INSERT/RPC réel + assertion).

- **En test** : INSERT/RPC réel dans une base de test, assertion sur les colonnes
  résultantes, cleanup/rollback après.
- **En prod (recette one-shot)** : `BEGIN; … ROLLBACK;` via SQL direct — **sans
  `RAISE EXCEPTION` final** (le `RAISE` fait rollback du DDL/DML dans une requête
  MCP enveloppée en transaction ; utiliser un `SELECT` de vérification puis
  `ROLLBACK`). Toujours partir de la **définition LIVE** (`pg_get_functiondef`),
  jamais du fichier repo.
- **RLS/GRANT** : une fonction SECURITY DEFINER neuve n'hérite d'AUCUN grant →
  `42501` muet. Asserter `has_function_privilege('authenticated', oid, 'EXECUTE')`.
- **`journaux_audit` est IMMUABLE** : toute assertion sur un compteur d'audit est
  **relative** (`n_avant + 1`), jamais absolue.

## Invariants métier — à asserter, jamais à supposer

Aucune recette d'un écran argent/mission n'est « livrée » sans une assertion sur
ces invariants (source : CLAUDE.md + `tests/non-regression/guards.sh`) :

- **Plancher escrow inviolable** : `paiements_escrow.honoraires_cents` est figé à la
  confirmation (net prévisionnel) et **jamais recalculé** par la validation des
  présences. Heures validées < publiées → le soignant touche **tout l'escrow**.
  Seule voie de réduction = litige (`DISPUTE` → `fn_escrow_rembourser`).
- **Heures facturées** = `GREATEST(prévisionnel hors pause, effectif hors pause)`
  (pauses toujours exclues). Testable en fonction pure.
- **Régime affiché** = `missions.type_contrat_applique` (figé à l'assignation),
  **jamais** `soignants.type_exercice` (un libéral peut faire une mission CDD).
- **Jamais `on_behalf_of`** sur un PaymentIntent escrow (mandat SEPA nomme Jolene
  créancier). **Audit escrow = insert DIRECT** en table (jamais
  `fn_ecrire_audit_safe`). **Passage `→ DEBITE`** doit enfiler la release.
- **⚡ Paiement rapide** : flag établissement, badge côté soignant — asserter le
  badge sur une mission `paiement_rapide=true` et son absence sinon.
- **Zéro donnée de santé** : aucun upload `ARRET_MALADIE`/vaccins ; documents requis
  filtrés par `profession` ET `type_exercice`.

## Parcours critiques à recetter (les deux interfaces)

- **Soignant** : swipe → **candidature/match** ; **Revenus escrow** (bloc « À venir »,
  plancher affiché) ; bulletin/facture honoraires.
- **Établissement** : **publier** (formulaire à état dérivé — double viewport) →
  **valider les présences** (72h auto + validation manuelle) → **facturation**
  (émise seulement **après** validation des présences) → **notation** (double-aveugle,
  publication à réciprocité sinon J+7).
- **Deep links** (pattern n°4 CLAUDE.md) : chaque lien profond (deep link argent,
  notif → écran) est **testé au clic** — la route cible rend l'écran attendu, pas
  un 404/écran vide.

## Checklist de clôture d'une recette

- [ ] Assertions écrites (unit test si calculable, sinon Playwright texte/DOM/état)
- [ ] Règle backend → INSERT/RPC **réel** + assertion d'état (jamais lecture de migration) ; GRANT vérifié
- [ ] Invariants argent/régime concernés **assertés** (plancher, GREATEST, type_contrat, on_behalf_of…)
- [ ] Un rendu testé **par état**
- [ ] Dump ARIA/texte avant/après collé dans la PR
- [ ] Écran établissement → **390 × 844 ET 1440 × 900**
- [ ] Deep links du parcours testés au clic (route cible rendue)
- [ ] Artefacts headless commités si `playwright install` a réussi (sinon noté)
- [ ] PR UI : URL preview Vercel + écrans à regarder (≤ 3 lignes/écran)
- [ ] Merge UI en attente de la passe humaine sur preview
