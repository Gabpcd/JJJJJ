# Stratégie produit & acquisition — « niveau Uber/Doctolib » (12/06/2026)

> Réponse à trois questions de Gabrielle : (1) les interfaces soignant/établissement
> sont-elles trop denses, pas assez intuitives ? (2) que changer pour devenir un géant
> type Uber/Doctolib ? (3) quelles stratégies de notoriété et d'acquisition ?
>
> Base factuelle : audit UX multi-agents (12 lots, ~30 pages lues intégralement,
> verdicts cités fichier:ligne) + métriques réelles de la base de prod + inventaire
> de l'existant growth (STRATEGIE_GROWTH_SERIE_A.md).

## 0. La réalité chiffrée (prod, 12/06/2026)

| Funnel soignant | n | Funnel établissement | n |
|---|---|---|---|
| Inscrits | 27 | Inscrits | 21 |
| Ont téléversé ≥1 document | 6 | Vérifiés (peuvent publier) | 9 |
| Onboarding terminé | 2 | Ont publié ≥1 mission | **2** |
| **Tous documents valides** | **1** | Missions ouvertes aujourd'hui | **0** |

- 21/27 soignants n'ont téléversé **aucun** document : le mur est à l'entrée de l'effort documentaire, pas au milieu.
- 100 % des inscrits sont en acquisition « DIRECT » : aucune campagne mesurée n'a encore tourné.
- Deux clusters géographiques réels : **Paris/92** (16 soignants, 13 étabs) et **Lorient/56** (6 étabs).
- Une partie des comptes sont des comptes de test — les vrais volumes sont encore plus faibles.

**Conséquence stratégique : le problème n°1 n'est pas le polish UI, c'est (a) un funnel
d'activation qui fuit aux deux extrémités et (b) une marketplace vide (0 mission).**
Uber et Doctolib ont gagné par la densité d'offre locale et l'obsession du temps-vers-
la-valeur — le design n'est que le véhicule. Tout ce qui suit sert ces deux priorités.

## 1. Verdict UX : trop dense aux endroits décisifs, sur-fragmenté partout

### Ce qui est déjà au niveau (à ne pas casser)
- Formulaires d'inscription : 2 étapes soignant (~3-4 min), 3 étapes étab (~2 min) — standard Uber driver.
- SwipeMissions : exemplaire (2 blocs, une action par écran, zéro scroll).
- ListeMissions étab : sobre. Design system Y2K cohérent, mobile-first acquis (Sprints 8-12).
- Briques de confiance présentes : score fiabilité, vérification IA des documents, signature électronique, pointage anti-triche.

### Les 5 maladies identifiées par l'audit

1. **Dashboards-sapins de Noël.** DashboardSoignant : jusqu'à 13 bandeaux/sections
   avant les onglets ; DashboardEtablissement : jusqu'à 22 blocs dont 6 banners
   concurrents. L'action n°1 se noie. Standard Uber : UNE carte « à faire maintenant ».
2. **La valeur jamais montrée avant l'effort.** À aucun moment de l'inscription le
   soignant ne voit une mission, un taux, une preuve sociale ; la page succès consacre
   50 % de sa hauteur à un avertissement anti-spam ; puis modal d'onboarding de
   7 slides (jargon DPAE/NIR/RGPD) avant tout usage. Uber affiche « Gagnez jusqu'à
   X €/sem dans votre ville » avant de demander le permis.
3. **Parcours sur-fragmentés.** 3 pages vivantes de découverte de missions
   (missions / recherche-missions / swipe-missions), 4 pages « argent » (gains,
   factures, bulletins, avances), 2 hubs paramètres, 2 pages d'activation étab
   (finaliser-inscription + verification), onglet Obligations miroir de Facturation,
   DashboardRH ≡ Analytics. ~90 routes utilisateur là où Doctolib pro en expose ~12.
4. **États vides qui constatent au lieu de recruter.** « Aucune mission disponible.
   Revenez bientôt ! » — alors que le cas réel est 0 mission. Aucun « préviens-moi »,
   aucun « 21 établissements inscrits dans votre zone ». Le deal implicite devient
   « téléversez 3 documents pour postuler à zéro mission » : cause rationnelle des
   26/27 abandons.
5. **Frictions dures sur le chemin payant.** RPPS introuvable = bouton grisé sans
   issue (InscriptionSoignant.tsx:191) ; saisie manuelle de dates que l'IA extrait
   déjà (ModalTeleversement.tsx:186-199) ; net estimé absent au moment de la décision
   de candidater ; deep-links facturation étab cassés ; « Planning équipes » pointe
   sur une table DEPRECATED.

Vérifications contradictoires faites : la conversion HEIC fonctionne depuis le
14/05 (#271) et `fn_postuler_mission` notifie bien l'établissement — deux alertes
de l'audit invalidées en prod. Le reste est confirmé dans le code.

## 2. Les 7 principes « géant » à installer

1. **Une action par écran.** Chaque écran répond à « qu'est-ce que JE fais
   maintenant » (déjà le principe directeur de STRATEGIE_UX_REFONTE — il reste à
   l'appliquer aux dashboards user).
2. **La valeur avant l'effort.** Aperçu missions/taux dès la profession+ville
   connues ; documents demandés après le premier désir, pas avant.
3. **Le temps de réponse est sacré.** Une candidature traitée en <24 h ou le
   candidat part : badge « X candidatures à traiter », horodatage, relance à 24 h,
   missions à candidats en tête de liste.
4. **L'argent limpide.** Net estimé en gros au moment de candidater ; « quand
   suis-je payé » visible partout ; un seul hub gains.
5. **Les états vides recrutent.** 0 mission → « 🔔 Me prévenir » + élargir le rayon
   + preuve sociale de la zone. 0 candidat → « booster » + partage.
6. **Densité avant étendue.** Saturer 1-2 zones (Paris/92, Lorient/56) avant
   d'élargir — déjà la règle d'or de la stratégie growth, à appliquer aussi au
   produit (tous les compteurs « dans votre zone »).
7. **Demander au bon moment.** Push après la 1re candidature réussie (pas à 5 s),
   PWA à la 2e session, géoloc avec son bénéfice affiché, jamais 2 bandeaux à la fois.

## 3. Roadmap produit — 3 sessions d'exécution

### Session E — Activation soignant (attaque le 27→1) — la plus rentable
| # | Chantier | Effort |
|---|---|---|
| E1 | Bloc unique « À faire maintenant » sur DashboardSoignant : checklist persistante ① Identité ② Documents (3 min, photo suffit) ③ Postuler — absorbe OnboardingGuide (7 slides supprimées), BandeauGraceDocuments, BandeauCompletionProfil, encart documents | M |
| E2 | Valeur avant effort : aperçu « N missions [profession] dans votre rayon · taux moyen » à l'étape 2 d'inscription + page succès (remplace le pavé anti-spam, conservé pour Outlook seulement) | M |
| E3 | Documents caméra-first : liste des manquants en tête avec gros bouton photo, attestation santé déplacée en fin, suppression des dates manuelles (l'IA les extrait), verdict IA inline sur la carte (spinner ~30 s → Vérifié ✓ avec confetti) au lieu d'un toast | M |
| E4 | Débloquer RPPS introuvable : « Continuer — vérification manuelle sous 24 h » (mécanisme fhir_indisponible existant à généraliser) | S |
| E5 | États vides qui recrutent : SwipeMissions + RechercheMissions + dashboard → « 🔔 Me prévenir dès qu'une mission tombe » (alerte push/email branchée sur les filtres sauvegardés existants) + étabs inscrits dans la zone | S/M |
| E6 | Checkout candidature : net estimé en gros dans DecompositionFinanciere + CTA sticky bottom mobile (pattern réservation Airbnb) + post-candidature « Validez vos documents (2 min) » | M |
| E7 | Harmoniser les 2 flows d'inscription (email vs PSC) : stepper honnête 4 étapes, mêmes champs, géoloc demandée AVEC son bénéfice | S |

### Session F — Activation établissement + boucle de matching (attaque le 21→2 et le temps de réponse)
| # | Chantier | Effort |
|---|---|---|
| F1 | Mode « première mission » du dashboard étab : 0 mission publiée → hero unique « Publiez votre première mission — 2 minutes » + checklist d'activation ; les 22 blocs n'apparaissent qu'après | M |
| F2 | Fusion finaliser-inscription + verification en UNE page « Activer mon établissement » (checklist Contrat → Vérification → RIB), RIB différé à la 1re facturation (just-in-time, standard Stripe) | M |
| F3 | « Republier » 1 clic : bottom-sheet « mêmes paramètres, nouvelles dates » depuis toute mission TERMINEE + dashboard | M |
| F4 | Boucle candidatures : badge « 🔔 X candidatures » sur les cartes mission + tri candidats-d'abord + horodatage « reçue il y a 2 h » + relance étab à 24 h si EN_ATTENTE | S |
| F5 | Assistance prix : « taux conseillé [profession] dans votre zone : X-Y €/h » sous le champ (grille statique au lancement) | S |
| F6 | Bloc « À faire maintenant » étab (fusion des 6 banners) + CTA « Publier » permanent en sidebar desktop | M |
| F7 | Facturation limpide : réparer les deep-links ?tab=, CTA « Activer le prélèvement automatique » au lieu de l'IBAN à recopier, retirer « Planning équipes » (table DEPRECATED) et l'onglet Obligations (miroir) | M |

### Session G — Consolidation navigation (la dé-fragmentation)
| # | Chantier | Effort |
|---|---|---|
| G1 | UNE page « Trouver une mission » : liste par défaut + toggle Swipe + filtres en bottom sheet ; /soignant/missions et /recherche-missions redirigent | M/L |
| G2 | UN hub argent : MesGains absorbe factures/bulletins/avances (une avance = un état de facture) avec « prochain paiement attendu » en tête | L |
| G3 | UN hub compte : suppression de PageParametres (redirect mon-compte), profil = identité publique + documents (plan Session B), parrainage sur sa seule page | M |
| G4 | Nettoyage routes : tableau-de-bord vs dashboard, fiabilite vs score, MissionPublique vs DetailMissionSoignant, doublons dashboard (mesMissions ×2, onglet Gains vs page) | M |
| G5 | Sollicitations séquencées : push après 1er succès, PWA à la 2e session, aide en variante discrète (le FAB primaire = Publier/Postuler) | S |

## 4. Stratégie de notoriété & d'acquisition

### Phase 0 — Colmater avant de remplir (Session E/F d'abord)
Pousser du trafic sur le funnel actuel = payer pour des comptes qui n'activent pas
(27→1). La Session E est le levier d'acquisition n°1 : chaque point d'activation
gagné multiplie le rendement de TOUT le marketing à venir. En parallèle, 0 € :
- Brancher l'attribution (100 % « DIRECT » aujourd'hui = aveugle) : vérifier la
  capture UTM sur tous les liens sortants déjà émis (SEO, digest, posts).
- Nettoyer les comptes de test de la base pour des métriques fiables.

### Phase 1 — Densifier 2 zones (0-3 mois, budget ~0 €, outils déjà livrés)
La machine existe déjà (STRATEGIE_GROWTH_SERIE_A) — il faut l'**exécuter** :
1. **Boucle fondatrice quotidienne (45 min/j)** : 10 appels EHPAD/cliniques du 75/92
   et du 56 via Admin → Sales → Prospection (FINESS, bouton Appeler) ; objectif
   30 étabs actifs par zone. C'est le déclencheur de TOUT : les missions créent
   l'offre qui active les soignants.
2. **Première mission concierge** : pour les 10 premiers étabs, Gabrielle publie la
   mission AVEC eux au téléphone (white-glove à la Airbnb 2009). Objectif : passer
   de 0 à 10-15 missions ouvertes en 2 semaines — la vitrine cesse d'être vide.
3. **Side de l'offre** : posts hebdo générés (outil livré) dans les 231 groupes
   sourcés, ciblés AS/IDE (profil dominant des inscrits) sur les 2 zones.
4. **IFSI/IFAS** (playbook existant) : QR codes à la remise des diplômes de juin-
   juillet — le timing est MAINTENANT.
5. **Google for Jobs** (livré) : chaque mission publiée = annonce indexée gratuite ;
   raison de plus pour la densité de missions.
6. **Parrainage** (livré) : activer la prime à la 1re mission terminée, pas avant —
   un parrainé qui arrive sur une app vide brûle le canal.

### Phase 2 — Amplifier ce qui marche (3-6 mois, premier budget)
1. **Meta/TikTok ads géo-ciblées AS/IDE** sur les 2 zones uniquement (les AS/IDE
   sont massivement sur TikTok/Insta ; créa = preuve de paiement rapide + vraie
   mission locale). Budget test 500-1 000 €/mois, CAC mesuré via l'attribution.
2. **Contenu organique fondatrice** : la construction de Jolene en public
   (LinkedIn pour les directions d'étabs, TikTok/Insta pour les soignants) — le
   canal n°1 des marketplaces early-stage, gratuit, incopiable.
3. **SEO programmatique** (livré : 138 URL villes/métiers) : enrichir avec du
   contenu réel (témoignages, taux observés) dès qu'il existe.
4. **Partenariats** : ordres/syndicats locaux, groupes d'EHPAD régionaux (le CRM
   contient déjà les sièges) — offre « flotte » top-down.
5. **PR locale** : presse régionale Bretagne/IDF (« la plateforme qui paie les
   soignants en 24 h ») au moment où les chiffres d'une zone deviennent racontables.

### Phase 3 — Échelle (6-18 mois, post-traction)
Ouverture zone par zone (jamais nationale d'un coup), équipe ops par zone,
programme ambassadeurs soignants rémunérés, intégrations plannings/paie étabs
(levier de rétention B2B), app stores (Capacitor déjà préparé).

### Les 4 métriques North Star (à afficher en tête du Cockpit)
1. **Missions pourvues / semaine** (la liquidité — LA métrique).
2. **Activation soignant à 7 j** (inscrit → documents validés) — aujourd'hui ~4 %.
3. **Time-to-first-mission étab** (inscription → 1re publication) — aujourd'hui ∞ pour 19/21.
4. **Temps de réponse médian aux candidatures** (<24 h).

## 5. Séquence recommandée

1. **Session E** (activation soignant) — le multiplicateur de tout le reste.
2. **Phase 1 acquisition en parallèle** (humain, pas du dev : appels + concierge).
3. **Session F** (activation étab + matching) dès les premiers étabs actifs.
4. **Session G** (consolidation nav) ensuite — important mais pas bloquant.
5. **Phase 2 acquisition** quand activation >30 % et ≥10 missions ouvertes en continu.

L'audit UX complet (12 lots, verdicts détaillés fichier:ligne) est archivé pour
alimenter les Sessions E/F/G : `/tmp/audit_ux_se.json` de la session du 12/06 +
synthèse dans ce document.
