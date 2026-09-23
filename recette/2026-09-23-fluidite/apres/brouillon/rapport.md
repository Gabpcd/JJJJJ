# Vérification ciblée — reprise de brouillon après profil établissement

Le rouge CI iOS sur PR970 (HEAD eaf006a) venait d'une assertion de texte devenue obsolète. L'introduction affiche désormais « Brouillon repris — Renfort IDE — audit inscription » dans un seul paragraphe, alors que le scénario recherchait un élément dont le texte exact était seulement « Brouillon repris ».

L'artefact CI 10763678052, fichier data/0a9d0096c25f1fe3e30c1ca7fdbb0a52e7cbf1ea.md, confirme déjà la restauration effective : intitulé, première/dernière date du 30 septembre 2026, créneau 07:00–19:00 et total de 12 heures. Aucun correctif produit nécessaire.

Changement : assertion exacte alignée sur le libellé complet, nouvelle vérification explicite du titre après entrée normale. Toutes les assertions de date et d'horaires sont conservées.

Test complémentaire : compte et backend en mémoire ; création rapide, saisie réelle des champs, enregistrement du brouillon à l'action Publier, simulation de rattachement complet, entrée normale sans paramètre inscription, assertions de l'introduction et de chaque champ restauré. Aucune publication de mission, aucun compte réel créé. Le test ne remplace pas la recette de l'Edge Function d'inscription : celle-ci reste dans la CI réelle.

Résultats : 3 tests passés, 0 échec (iPhone 13 WebKit 390×844 ; Pixel 7 Chromium ; ordinateur Chromium 1440×900). Chaque résultat inclut capture et arbre ARIA, avec absence d'exception JavaScript et de mutation métier.

Artefacts : results.json et sous-dossiers iphone-webkit/, android-pixel/, desktop-1440/.
