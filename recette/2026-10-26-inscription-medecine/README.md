# Inscription étudiant en médecine — 26 octobre 2026

Signalement : sur l’application iPhone, le choix Médecin proposait toutes les filières de santé, omettait le troisième cycle et la saisie pouvait se déplacer.

## Correction bornée

- `MEDECIN` propose uniquement les trois cycles de médecine. L’internat est une déclaration conservée dans le brouillon et dans `etudiant_details`, sans inventer une année validée.
- Le troisième cycle ne consulte pas les équivalences temporaires aide-soignant. Les choix des premier/deuxième cycles conservent leurs règles existantes et la suggestion AS reste un choix explicite.
- Changer de formation efface l’année précédente ; changer de profession efface une formation devenue incompatible. Une ancienne réponse réseau ne se présente plus comme le résultat du nouveau choix ; une panne du référentiel n’est plus présentée comme une insuffisance d’études.
- La navigation Entrée relit les champs présents et visibles. L’aperçu asynchrone des missions se trouve après le formulaire ; il ne décale plus les champs actifs.
- L’interrupteur étudiant conserve une cible tactile de 48 × 48, un rail de 48 × 24 et un curseur contenu. La capture `avant/interrupteur-iphone.png` montre le défaut visuel constaté pendant la recette, après le premier correctif fonctionnel ; ce n’est pas une capture de la version App Store.

- Côté établissement, l’attestation d’emploi temporaire aide-soignant, son blocage et le motif envoyé sont réservés aux étudiants dont le profil est `AS`. Un interne `MEDECIN` n’est plus invité à confirmer ce cadre inadapté ; les gardes serveur restent inchangées.

## Vérifications effectuées

- 25 tests unitaires : 13 sur AuthLayout/clavier, aperçu marché et cohérence RPPS ; 12 sur les candidatures et les vues habilitées, dont l’attestation AS obligatoire et son absence pour un interne médecin.
- TypeScript et compilation web isolée réussis.
- 30 scénarios Playwright réussis, sans retry ni scénario ignoré : 4 parcours d’inscription et 2 parcours de candidature × iPhone/WebKit, iPad portrait/WebKit, iPad paysage/WebKit, Android/Chromium, ordinateur/Chromium. Résumés dans `resultats.json` et `resultats-candidatures.json`.
- Parcours : internat → saisie → sauvegarde → reprise via Candidater → rechargement → envoi du profil ; premier/deuxième cycles et choix AS explicite ; panne/réponse différée ; arrivée tardive de l’aperçu sans déplacement du prénom, de la profession ni du défilement.
- Candidatures côté établissement : étudiant AS salarié avec attestation obligatoire, interne médecin libéral sans attestation AS ; créneaux, motif RPC, assignation et conservation après rechargement vérifiés. Aucune signature, facture, notification ou transaction distante.
- Assertions complémentaires : focus des champs ajoutés dynamiquement, cible tactile et curseur, aucune RPC d’équivalence pour l’internat, aucune validation documentaire ajoutée, absence de débordement horizontal et d’erreur JS/requête inconnue.
- Dumps ARIA avant/après les transitions dans chaque sous-dossier. Capture iPhone corrigée dans `iphone/internat.png`, inspectée visuellement.
- Revue indépendante à contexte vierge : **CLÔTURABLE**, puis confirmations après l’ajustement de l’interrupteur et la correction de l’attestation des candidatures ; aucun P1/P2 identifié dans ce périmètre.

## Nature des preuves et limites

Les écrans et le code applicatif sont réels, mais Auth, Annuaire Santé, sauvegarde, finalisation et acceptation des candidatures sont intégralement simulés sur localhost. Aucun compte distant n’est créé. Cette recette ne constitue ni un test d’intégration ANS, ni une validation de licence de remplacement, ni un essai sur iPhone physique. Les règles serveur d’accès aux missions et les contrats ne sont pas modifiés.

Le troisième cycle seul n’établit pas le droit au remplacement : voir [CNOM, interne/docteur junior remplaçant](https://www.conseil-national.medecin.fr/etudiant-interne-docteur-junior/linterne-docteur-junior-remplacant) et [CSP L4131-2](https://www.legifrance.gouv.fr/codes/article_lc/LEGIARTI000021503653/). Les équivalences temporaires étudiantes relèvent d’un autre cadre : [arrêté du 3 février 2022, article 1](https://www.legifrance.gouv.fr/loda/article_lc/LEGIARTI000049404139). Aucune nouvelle règle d’habilitation n’est introduite par ce correctif déclaratif.

L’app Capacitor embarque `dist`. Le merge et le déploiement web ne remplacent pas son interface installée. La publication mobile est manuelle ; les gardes actuelles refusent l’OTA pour `auth`/`inscription`. Aucune livraison mobile, OTA ni soumission aux stores n’est déclenchée par cette correction.
