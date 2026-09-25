# G09/G10 — récurrence établissement et voix de l’inscription

Recette du 25 septembre 2026, branche `fix/preparation-lancement-national`.

## Portée

G09 correspondait à une preuve absente : le test historique `e2e/non-regression/etablissement.spec.ts` était en `fixme`. Les nouveaux tests saisissent le formulaire réellement monté sur `/etablissement/missions/creer`, depuis une connexion simulée d’établissement vérifié. Le planning reste défini par les occurrences datées, sans ancien mode récurrent séparé.

Aucune règle de durée, de contrat ou d’autorisation n’est modifiée. Aucun défaut produit de calcul ou de restauration n’a été reproduit dans ces scénarios. Le premier diagnostic a corrigé uniquement le sélecteur de test : le bouton s’appelle « Publier la mission (6 créneaux) » quand le planning comprend plusieurs occurrences.

G10 : la complétion soignante associait le titre « Vos informations professionnelles » à « Ta profession » et « Vérifie ton numéro ». Les pronoms et conjugaisons sont harmonisés en **vous** dans l’inscription et ses composants. Le ton **tu** des espaces soignants reste conservé. Les conditions, exigences RPPS, règles étudiantes, consentements et délais préexistants ne sont pas changés.

## Assertions de navigateur

| Scénario | Assertions exactes |
|---|---|
| Six jours répétés | Saisie des six dates lundi–samedi, horaire 07:00–16:00 appliqué à chacune ; total **54 h**, une seule zone `role=alert`, un seul diagnostic chiffré 54/48, bouton désactivé, pas de récapitulatif ni de requête de création. Correction par saisie 07:00–15:00 et recopie : **48 h**, plus d’erreur, bouton activé, récapitulatif de **6 créneaux**, **48h00** et **1440.00 €** à 30 €/h. |
| Interruption / exception | 07:00–12:00 et 13:00–17:00 : **9 h**, **270.00 €**, deux créneaux ; l’heure d’interruption n’est pas comptée. Étendre la période au mardi conserve ces deux horaires et laisse la nouvelle date au repos. |
| Nuit dimanche–lundi | 22:00–06:00 ne devient valide qu’après sélection explicite « Lendemain ». Répartition **2 h** dans la semaine du 14/10 et **6 h** dans celle du 21/10 ; récapitulatif **8h00**, **240.00 €**, dates exactes et **8 h** de nuit estimées. |
| Duplication | Lecture préparée de trois créneaux : deux le lundi séparés par une interruption, une nuit mercredi–jeudi. Les paramètres d’enveloppe de l’URL ne remplacent pas le planning multi-créneaux. Le mardi reste au repos, les trois horaires et le lendemain sont restaurés ; **17 h**, **510.00 €**, aucune création. |
| Voix inscription | Création de compte par l’UI, accès volontaire au dossier depuis une mission, titre et indication de profession en « vous », erreur RPPS en « Vérifiez votre numéro ou votre profession », refus de finalisation conservé. Retour libre à l’accueil soignant avec son ton existant. |

Les quatre scénarios G09 s’arrêtent au récapitulatif avant confirmation finale. Ils assertent zéro appel de création/modification de mission, zéro endpoint inconnu, zéro écriture non préparée et zéro exception JavaScript. L’isolateur ferme les WebSockets, retire les hints réseau du document et interdit tout accès externe. La fixture de duplication n’accepte que les lectures GET/HEAD des deux tables explicites ; les mutations restent refusées par l’isolateur.

## Validation

**25/25 simulations vertes** : quatre scénarios G09 et un scénario G10, chacun sur cinq formats, sans nouvel essai automatique.

- iPad portrait 820 × 1180 et paysage 1180 × 820 sous WebKit.
- iPhone 390 × 844 sous WebKit ; Pixel 7 et ordinateur 1440 × 900 sous Chromium.
- `retries: 0`, un worker, bundle de production statique local sur le port 8902 ; toutes les API sont interceptées en mémoire.
- **26/26 tests unitaires** : FormulaireRecurrence (9), planning-derive (14), cohérence RPPS (3, enrichi avec les libellés de G10).
- TypeScript global (`tsc -b`), ESLint ciblé et `git diff --check` : verts.

Preuves : logs locaux `/private/tmp/jolene-g09-g10-final.log`, `/private/tmp/jolene-g09-g10-unites.log`, `/private/tmp/jolene-g09-g10-tsc.log`, `/private/tmp/jolene-g09-g10-lint.log`. Les dumps ARIA de tous les formats et captures iPad sont produits par chaque scénario ; une sélection est conservée dans `docs/recettes/assets/2026-09-25-recurrence`.

## Test historique et limites

Le `fixme` historique est remplacé par une saisie réelle 54 → 48 h, avec dates futures calculées, une erreur unique et le contrôle que la publication redevient possible à 48 h. Toute tentative de création est interceptée et rejetée. **Ce test contre un compte réel n’a pas été exécuté pendant ce lot** ; la preuve exécutée est la matrice isolée ci-dessus.

Cette recette démontre le comportement du frontend pour ces cas, pas les contraintes SQL en production ni un moteur de paie. La pause est représentée ici par un intervalle non travaillé entre deux créneaux prévisionnels ; aucun pointage de pause réel n’est créé. Les règles et cas de changement d’heure ont leurs unités existantes, mais ce lot n’ajoute pas de simulation navigateur DST.

G10 n’est pas un audit exhaustif d’accessibilité : noms accessibles et alertes sont exercés dans ces parcours, sans prétendre certifier tous les écrans, contrastes ou usages d’un lecteur d’écran. Les branches secondaires des textes harmonisés (PSC, étudiant, aperçu local) n’ont pas toutes été déclenchées par ce nouveau scénario. Il n’ajoute aucun engagement juridique ou délai de service.

## Relecture indépendante

Relecture par l’agent `native_fluidity_audit` : aucun défaut P1/P2 démontré dans ce delta. Le reviewer a contrôlé les seuils, le calcul des interruptions et de la nuit, la duplication, l’absence de publication et le caractère exclusivement grammatical des modifications produit. Il n’a pas réexécuté la matrice.
