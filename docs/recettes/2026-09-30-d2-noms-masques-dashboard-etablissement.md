# D2 : noms masqués et connexion établissement représentative

Le septième pilote `36750419176`, tête `a42954ce4d7e6262df08b88926d3d2ef851008f3`, termine en échec le 30 septembre 2026 à 17:20:24 UTC. Les deux soignants passent le formulaire, le lien SPA, le dépôt et le rechargement. Aucun événement navigateur en erreur n’est enregistré. Le parcours établissement valide les compteurs « Candidatures (2) » et « En attente (2) », puis expire sur `etablissement_nom_visible` après environ cinq secondes. Deux POST ont aussi été refusés au tableau de bord établissement.

## Confidentialité : le produit affiche correctement une initiale

La définition staging de `fn_soignant_pour_etablissement(uuid)` a l’empreinte `aea5e4220e1d98065cc007d3abd1cb06`. Sans rôle administrateur réel ni mission affectée établissant une relation contractuelle, elle renvoie le prénom, la première lettre du nom suivie d’un point et `nom_anonymise: true`. Le téléphone reste absent sans la relation prévue par cette fonction.

D2 crée deux candidatures, sans affectation ni contrat. Le test exigeait pourtant « Alice Recette D » et « Basile Recette D ». Le résultat attendu est « Alice R. » et « Basile R. ». Le mock local renvoyait lui aussi le nom complet, ce qui masquait le défaut du test. **Aucune règle produit d’anonymisation n’est modifiée.** Le matcher compare maintenant exactement le prénom et l’initiale, et les simulations refusent explicitement la présence des noms complets avant et après rechargement.

## Deux lectures du tableau de bord identifiées avant autorisation

Une reproduction locale avec formulaire établissement et garde inchangé identifie exactement deux refus : `fn_mon_score_etab` et `fn_bfa_info`, POST avec objet vide. Ils proviennent des cartes du tableau de bord montées hors de l’accordéon de statistiques. Ce sont des lectures, pas des opérations de score ou de versement.

La lecture indépendante du catalogue staging, sans appel de ces RPC, confirme :

| Fonction | Empreinte du corps | Propriétés vérifiées |
|---|---|---|
| `fn_mon_score_etab()` | `0d59470fc833e7a674cea2954cabbd73` | STABLE, SECURITY DEFINER, SELECT du tenant canonique ; aucun DML/audit/HTTP/queue |
| `fn_bfa_info(integer DEFAULT NULL)` | `0df489f34ded1546f01479f7595ef596` | STABLE, SECURITY DEFINER, lecture du groupe éventuel du tenant ; aucun DML/audit/HTTP/queue |

Les droits EXECUTE sont limités à authenticated/service_role, anon refusé. Les helpers de tenant et d’administrateur ont aussi été relus : lectures uniquement. La fixture D2 n’a aucun groupe, donc BFA non éligible. Le catalogue figé et les empreintes de fixture restent vérifiés.

Le garde ajoute ces deux seuls RPC, uniquement au slot établissement, POST avec objet exactement vide, sans query ni année fournie. Le preflight OPTIONS sans corps est borné au même slot. Les tests refusent soignants, autres méthodes, corps absent/null/tableau/arguments, autre origine et RPC de versement. Aucun budget d’écriture ni endpoint financier mutatif n’est ajouté.

## Recette corrigée et limites

Le scénario runner passe désormais par les **trois** formulaires de connexion simulés, dont l’établissement et son vrai tableau de bord. Il vérifie une connexion par rôle, une activité par soignant et une consultation établissement. Les gardes réseau et erreurs existants restent inchangés. Le helper partagé modélise les deux lectures auditées, les lectures existantes du dashboard, les filtres temporels bornés et la projection masquée des candidats ; la première reproduction locale avec deux éléments encore non modélisés reste conservée.

Les données Auth/API des simulations sont fictives. La preview réutilise le build compilé existant F1 corrigé du preload, sans nouvelle compilation ; aucun appel distant métier n’est réalisé par les tests locaux. La vérification du pilote staging n’est pas revendiquée verte et aucun nouveau run n’est lancé ici.

Validation locale du runner : **15/15 simulations** sur ordinateur, iPhone, Android, iPad portrait et paysage, zéro skip/retry/flaky ; **25/25 tests Node**, typecheck E2E ciblé, `tsc -b` et diff-check verts.

La spec partageant le helper a d’abord obtenu **10 succès et 5 échecs** : le scénario de panne attendait un texte réservé au mode DEV (`Erreur: …`). Les snapshots montrent le message PROD exact « Une erreur est survenue. Veuillez réessayer. », conforme au helper produit. Cet attendu a été corrigé sans toucher le produit, puis les **5/5 cas panne/réessai/planning périmé/recharge** ont été rejoués avec succès. Au total, les 30 cas distincts sont couverts ; les cinq échecs initiaux et leurs traces restent conservés, sans retry automatique. Les captures établissement inspectées montrent les deux initiales, les deux candidatures en attente et aucun soignant assigné. Une pause entre matrices a respecté le seuil disque de 150 MiB ; aucune preuve n’a été supprimée.

## Nettoyage indépendant du septième pilote

Après cleanup réussi, les SELECT des scripts existants confirment : zéro Auth/profil/établissement/mission/créneau/candidature/préférence/notification/limite/session/identité du lot ; six audits conservés (trois connexions, une consultation, deux reçus prepare/cleanup) ; reçu cleanup exact présent. Emails, tokens push et présences restent à zéro pour chaque slot. Les empreintes du catalogue sont inchangées, avec zéro cron actif et zéro FK audit ciblée. Les validateurs existants confirment ces résultats.

Preuves distantes filtrées : `/private/tmp/jolene-d2-36750419176-artifact/`. Diagnostic local, rapports et captures : `/private/tmp/jolene-d2-36750419176-diagnostic/`. Définition des deux lectures auditées : `/private/tmp/jolene-D2-rpc-dashboard-1728-20260930.json`. L’archive compacte durable et son manifeste se trouvent sous `audits/2026-09-30-preparation-nationale/preuves/d2-noms-masques-dashboard-etablissement/` du workspace Jolene. Les limites et premiers échecs sont conservés ; aucune preuve supprimée pour libérer le disque.
