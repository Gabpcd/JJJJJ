# Diagnostic du clic OTP iPad paysage et correction ciblée

Trace initiale conservée : `/private/tmp/jolene-contrats-ui-otp-regression/recette-complete-mission-s-5ebb0-prise-sans-double-signature-ipad-paysage/trace.zip`.

## Ce que montre la trace

- `call@276`, bouton « Signer », viewport 1180 × 820, point de clic (894, 684) : dans l’écran, élément visible, activé et stable, sans clic forcé.
- 8565,513 ms : contrôle de stabilité terminé ; 8569,555 ms : début du clic ; 8596,956 ms : fin du clic.
- Les frames aux temps 8529,593 / 8590,651 / 8644,960 ms montrent la notification d’erreur réseau précédente glissant depuis la droite, puis recouvrant le centre de « Signer ». Une notification de succès d’envoi OTP s’empile dessous.
- `NotificationContext.tsx` rend ces cartes en `pointer-events-auto`, position fixe, z-index 100. `index.css` applique `slideInRight` sur 300 ms, de translateX(100 %) à 0. Le message peut donc traverser le point entre la vérification d’interactivité et la fin du clic.
- Le journal contient trois demandes d’envoi OTP (session expirée, réseau en erreur, succès), **aucun appel de signature**, aucune erreur JS ni requête inconnue. Le champ contient bien `000000`, les actions sont activées. Aucune signature n’a été enregistrée.

La cause retenue est la superposition animée du message pendant le clic, par convergence de ces preuves visuelles, de la chronologie et de l’absence de RPC. La trace ne journalise pas le destinataire DOM de chaque mouseup ; elle ne permet donc pas de lui attribuer un événement DOM précis avec certitude. Ce n’est pas un rejet du nouveau garde documentaire, ni une réponse SQL/OTP ignorée, ni un bouton hors viewport. Le passage vert au rejeu ne suffisait pas à conclure à un simple défaut de fixture.

Frames extraites sans altérer la trace : `/private/tmp/jolene-otp-ipad-trace-inspection/9839.jpeg`, `9900.jpeg`, `9955.jpeg`, `0071.jpeg`.

## Correction

Les erreurs, confirmations d’envoi et succès de `SignerContratOtp` sont rendus dans le formulaire avec `role=alert` ou `role=status`. Ils ne sont plus envoyés au conteneur global superposé. Les textes d’erreur, la reprise, le nombre de tentatives, le timer et la protection contre les doubles RPC sont conservés. Le succès de la page après relecture du contrat porte aussi `role=status`.

Les messages occupent leur propre place dans la page : aucun clic ne traverse une notification pour signer en dessous. `NotificationContext` et ses boutons d’action/fermeture restent inchangés, ainsi que leur interception volontaire des clics. La correction ne prétend pas résoudre toutes les superpositions possibles des notifications globales dans d’autres parcours.

Le test OTP conserve le clic normal et toutes les erreurs/réessais. Il exige maintenant également le message accessible inline, l’absence de toast global OTP et une réponse effective à la première demande de signature. Ni attente arbitraire de disparition des messages, ni clic forcé, ni retrait d’assertion. Un test unitaire clique le message de confirmation alors qu’un code valide est saisi : aucune signature ne part ; seuls les clics explicites sur « Signer » peuvent produire une RPC, une seule malgré deux clics.

## Inventaire SECURITY DEFINER

Lecture catalogue LIVE : `fn_contrat_storage_path(uuid)`, OID 59151 ; catégorie `MIXTE_TENANT_ADMIN`, empreinte précédente `0d3bf0ce6fcea92df93c12a44080bd7f` identique au corps LIVE. L’inventaire ne contenait aucun autre état à reprendre.

La migration met à jour **cette seule signature**, avec l’empreinte littérale du corps revu `c57310a89e7a01f85849f648db433776` et la justification compte actif / tenant canonique / lecture_contrats / administrateur valide. La catégorie existante est conservée. Aucune capture globale de `pg_proc`.

Le test SQL exige une entrée de même catégorie et `definition_md5 = md5(pg_proc.prosrc)` pour l’OID résolu de cette seule fonction. Parsing SQL + PLpgSQL complet vert ; exécution réelle restant à obtenir dans la CI de l’intégration. Aucune mutation distante.

## Validation

- Tests unitaires : 8/8 (continuité OTP et page), dont succès accessible et double RPC empêchée.
- TypeScript `tsc -b` et build web : verts.
- Recette finale OTP cinq formats : **5/5 verts**, résultat consigné dans `/private/tmp/jolene-otp-inline-e2e-final.txt` et `/private/tmp/jolene-otp-inline-cinq-formats-final/results.json`.
- Premier passage du test renforcé : correction d’une assertion qui confondait le texte de l’alerte et le compteur de tentatives (deux éléments distincts déjà existants). Les deux assertions sont maintenant conservées séparément ; ces traces intermédiaires restent sous `/private/tmp/jolene-otp-inline-cinq-formats`.

Preuves locales uniquement : API et SMS simulés, aucun appareil physique ni validation réelle de SMS/Storage.
