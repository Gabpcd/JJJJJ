# Erreurs conservées dans les formulaires de paiement, litige et annulation

Périmètre : déclaration de paiement au soignant dans Facturation, contestation de facture dans le wizard de litige, annulation de mission. Les appels API, leurs paramètres, les montants, règles financières et textes juridiques restent inchangés. Aucune donnée distante ni fournisseur n’a été appelé dans cette recette.

## Reproduction avant correction

Preview compilée 18464, ordinateur, réponses synthétiques, aucun réseau extérieur autorisé. Les traces et captures sont conservées dans `/private/tmp/jolene-formulaires-inline-20260930/`.

- `initial-v2` : litige et annulation ferment et démontent le formulaire quand l’utilisateur ferme la notification d’erreur ; les saisies sont perdues. La déclaration de paiement affiche un toast Sonner derrière le voile de la modale : Playwright constate que le voile intercepte le clic de fermeture. Aucun clic forcé n’a été utilisé et aucune perte de saisie du paiement n’est revendiquée à partir de ce clic impossible.
- `initial` : première fixture incomplète pour deux assertions (traduction générique du message paiement ; libellé établissement « Annuler »). Le troisième scénario prouvait déjà la fermeture du wizard. Les gardes ont aussi détecté et bloqué le chargement Stripe JS. Le run suivant remplace explicitement ce script par un stub local, comme les recettes existantes. Les erreurs de console ne sont pas filtrées.
- Le wizard imposait un identifiant de titre incompatible avec le contrôle interne Radix ; la liaison automatique du titre et une description accessible sont désormais utilisées. La modale d’annulation a aussi une description accessible.

## Correctif

Chaque refus est annoncé par `role="alert"` dans le pied du dialogue, au-dessus des actions. La saisie et la sélection de facture restent en place. Les erreurs réseau ou de session retournées/rejetées sont traduites avec le helper existant. Une nouvelle tentative efface l’erreur précédente ; les confirmations décrivent uniquement le résultat enregistré.

Les actions et fermetures sont bloquées pendant la requête. Pour la déclaration d’honoraires, cela corrige également la comparaison incorrecte entre l’identifiant de facture en cours et l’identifiant de mission. Les champs paiement sont figés pendant l’envoi. Le wizard libère son état occupé même après une exception réseau.

La déclaration conserve ses trois RPC (facture, salarié v2, ancienne déclaration), l’information `use_stripe_connect` et l’email seulement après le chemin de succès existant. La réponse `{data,error}` de l’Edge et ses cas `success:false`, `skipped` et `pending` sont examinés : un échec email est journalisé sans identifiant personnel ; un envoi volontairement ignoré ne déclenche pas d’alerte. Aucun de ces cas ne relance la déclaration déjà réussie. Le message reste « Paiement déclaré — en attente de confirmation du soignant ». Le wizard confirme « Litige ouvert. Vous pouvez suivre son traitement dans l’app. », sans promettre une livraison email/support. La force majeure sur mission non ouverte conserve la demande de revue sans appeler l’annulation. Le litige conserve `DESACCORD_MONTANT_FACTURE` et `p_facture_id`.

La vérification visuelle a aussi relevé deux promesses de notification trop fortes. Le récapitulatif du wizard indique désormais « Le suivi du litige est disponible dans l’app. ». Pour une mission ouverte sans soignant, le bandeau d’annulation indique « La mission ne sera plus proposée aux soignants. » ; les autres annulations décrivent la consultation dans le suivi et la contestation du score. La branche force majeure, les délais de médiation et les règles restent inchangés. La recherche bornée dans les trois composants ne trouve plus de promesse d’email immédiat liée à ces actions.

## Vérifications

- 32 tests Vitest verts : 18 nouveaux comportementaux (11 paiement, 3 wizard, 4 annulation), 2 anciens annulation et 12 existants de périmètre financier.
- TypeScript applicatif et typecheck isolé de la simulation : verts.
- La simulation exécute refus, absence d’email sur refus, conservation des champs, réessai explicite, blocage pendant la requête, succès puis état simulé après rechargement. Les deux payloads doivent être identiques et exactement deux tentatives sont permises.
- `matrice-v1` : 10 succès paiement/litige, 5 échecs annulation après succès en revenant à la liste. La fixture exposait mal `Content-Range` à travers son port API distinct ; la garde de chargement des créneaux refusait `count:null`. Ajout d’un en-tête `Access-Control-Expose-Headers` à la réponse simulée bornée à une mission/un créneau, sans changer la garde produit. La passe ciblée ordinateur puis `etablissement-final` passent (15/15, 38,7 s).
- Parcours soignant ajouté à la demande de root : route canonique `/soignant/mes-gains?tab=factures`, parent `MesFacturesHonorairesContent`, action « Erreur » sur ordinateur/tablette ou « Signaler une erreur » sur mobile. Le parent recharge les factures après succès, contrairement au parent établissement qui recharge les obligations. `HistoriqueMissions` n’est plus directement routé dans l’application ; cette recette utilise le parent effectivement accessible. Premier essai ordinateur : vert.
- `etablissement-console-finale` : les 15 scénarios fonctionnels atteignent leur résultat, puis échouent sur les avertissements de Service Worker bloqué par Playwright. Leurs traces restent conservées. Les deux simulations déclarent ensuite explicitement un navigateur sans capacité Service Worker, en plus du blocage existant ; aucune erreur ou aucun avertissement n’est filtré. Ce périmètre ne valide donc pas la PWA ni le push.

### Preuve finale au 30 septembre 2026

Tous les formats sont couverts : iPhone, Android, iPad portrait/paysage et ordinateur. Les compteurs finaux correspondent à **15 parcours établissement + 5 parcours soignant + 10 parcours notation**, sans skip, retry ni flaky. Chaque scénario vérifie le refus, la conservation de la saisie, la reprise explicite, l’unicité de l’appel pendant l’envoi, le succès puis le rechargement. Les annexes JSON confirment deux tentatives identiques, sans requête inconnue/extérieure, erreur runtime, `console.error` ou `console.warn`.

| Preuve retenue | Preview | Début UTC | Résultat retenu |
| --- | --- | --- | --- |
| `etablissement-console-finale-v2` | 18466 | 15:48:18 | 5 paiements parmi 15 succès ; les 10 autres sont remplacés ci-dessous |
| `notation-console-finale` | 18466 | 15:49:39 | 10/10, 20,8 s |
| `annulation-texte-final` | 18467 | 15:56:22 | 5/5, 13,8 s |
| `wizard-texte-final` | 18467 | 15:56:58 | 10/10, 22,1 s : 5 établissement + 5 soignant |

Les derniers bandeaux concernent uniquement annulation et wizard : ces quinze cas sont rejoués après recompilation. Les sources paiement et notation sont identiques à celles vérifiées sur 18466. Leurs preuves restent valides sans nouvelle exécution. Les captures finales montrent l’erreur dans la modale, les textes factuels et l’état rechargé ; l’opacité du dialogue est attendue avant la capture, sans temporisation arbitraire.

Les preuves compactes (rapports complets, captures par format, compteurs, empreintes des sources, patch et manifeste SHA256) sont conservées dans `audits/2026-09-30-preparation-nationale/preuves/formulaires-erreurs-inline/` à la racine du workspace Jolene. Les traces initiales, tous les essais intermédiaires et leurs captures restent sous `/private/tmp/jolene-formulaires-inline-20260930/` ; aucune trace d’échec n’est supprimée ni recopiée massivement. Le fichier `validation.json` lie les preuves au commit final et distingue les sous-ensembles retenus.

Reproduction locale : utiliser la configuration autonome `e2e/playwright.recette-complete.config.ts`, `PLAYWRIGHT_BASE_URL` vers une preview compilée avec clés fictives et `RECETTE_RESULTS_DIR` propre. Lancer `recette-complete-formulaires-erreurs.spec.ts` pour les 20 cas, puis `recette-complete-notation-autorisation.spec.ts` pour les 10 cas ; pas de setup Auth distant.

Les tests sont des simulations frontend avec API et WebSockets interceptés, sur navigateurs émulés. Ils ne prouvent pas une déclaration persistée, une ouverture de litige réelle, une notification réellement envoyée, une annulation ou un mouvement d’argent chez un fournisseur, ni un résultat sur appareil physique. La revue croisée ne remplace pas la revue fraîche B8 exigée avant merge.
