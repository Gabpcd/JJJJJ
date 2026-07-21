# Stratégie Growth Série A — Jolene leader du staffing santé

> Objectif : maximiser soignants actifs + revenus, avec des outils 1-clic dans l'admin.
> Principe directeur : un marketplace gagne par la LIQUIDITÉ (offre × demande au même
> endroit, au même moment). Tout ce qui suit sert la liquidité ou la monétisation.

## 1. Moteur de croissance — état des outils admin

| Levier | Outil dans l'admin | Statut |
|---|---|---|
| Sourcing soignants (groupes FB/Insta/TikTok, 231 canaux) | Sales → Groupes (liens cliquables, favoris, templates) | ✅ livré |
| Prospection B2B nationale (FINESS ~70k étabs, tél direct) | Sales → Prospection (national, favoris, Appeler/Email 1-clic) | ✅ livré |
| Outreach email 1-clic (Resend, passage auto en CONTACTÉ) | Sales → Prospection → « Via Jolene » | ✅ livré |
| Pipeline CRM (statuts, archive douce, relance auto J+7) | Sales → Étab./Soignants sourcés + cron 8h | ✅ livré |
| Attribution acquisition (UTM/referrer/parrainage → CAC réel) | Fondateur → Acquisition | ✅ livré |
| Radar de demande (France Travail, FINESS, BMO, liquidité locale) | Fondateur → Acquisition | ✅ livré, API FT à habiliter |
| Comptes ancres, récurrence, groupes, écoles, reverse marketplace | Fondateur → Acquisition → Recommandations | ✅ livré en brouillons internes |
| Simulateur levée + stratégie d'allocation | Fondateur → Levée | ✅ livré |
| Parrainage viral (prime cash soignant, crédits étab) | en prod (Sprint J5) | ✅ existant |

## 2. Playbook commercial (utiliser les outils ci-dessus)

**Boucle quotidienne fondatrice (45 min/j)**
1. Prospection → filtre EHPAD + ton département → 10 appels (bouton Appeler).
2. Chaque intéressé → Pipeline ; chaque email connu → « Via Jolene » (1 clic).
3. Le cron relance marque RELANCE à J+7 → rappeler la liste RELANCE d'abord.
4. Groupes favoris (⭐) → 1 post/jour avec le template (copier-coller).

**Règle d'or marketplace** : densité avant étendue. Saturer UN département
(ex. 75/92) — 30 étabs actifs + 300 soignants — avant d'élargir. Un marché
dense convertit mieux et crée le bouche-à-oreille.

## 3. Leviers — état d'avancement

1. **SEO programmatique** ✅ livré : `/emploi-soignant/[ville]` (**100 villes**) et
   `/metier/[profession]` (**15 métiers**) routées + section « missions réelles en
   direct » (RPC publique) + CTA UTM `seo-ville-*` / `seo-metier-*`. Sitemap
   régénéré (138 URLs, slugs `ibode`/`iade` corrigés).
2. **Boucle de réactivation** ✅ livré : cron hebdo (lundi 10h) → edge
   `relance-inactifs` → email Resend aux inscrits >3j sans candidature
   (max 1 relance/14j, journal `relances_soignants`, UTM `reactivation`).
3. **Import CSV en masse** ✅ livré : bouton « Importer CSV » sur Groupes
   (`nom;url;profession;region`) et Contacts (`nom;tel;email;ville;profession`).
4. **Referral au moment du paiement** ✅ livré : bannière parrainage sur
   Mes Gains → /soignant/parrainage (prime cash existante).
5. **Intégrations établissements** (export planning/paie) : à construire.
6. **Partenariats écoles IFSI/IFAS** : playbook manuel ci-dessous.
7. **Google for Jobs** ✅ livré : page publique `/mission/:id` (JSON-LD
   `JobPosting` : titre, lieu, salaire horaire EUR, dates, employeur) via RPC anon
   `fn_mission_publique` + sitemap dynamique edge `sitemap-missions`
   (missions OUVERTES, max 2000) référencé dans `robots.txt`. Chaque mission
   publiée devient une annonce indexable gratuitement par Google — CTA inscription
   UTM `google-jobs`.
8. **Générateur de posts hebdo** ✅ livré : onglet « Posts de la semaine » dans
   Admin → Sales (RPC `fn_admin_generer_posts`) — textes prêts-à-coller par
   profession (nb missions réelles, taux max, villes) + post global, UTM
   `post-hebdo`, bouton copier. À coller dans les groupes de l'onglet Groupes.
9. **Digest hebdo soignants** ✅ livré : cron jeudi 9h UTC → edge `digest-hebdo`
   → email Resend à chaque soignant dont la profession a ≥1 mission ouverte
   (nb + meilleur taux, UTM `digest-hebdo`, max 500/run). Crée l'habitude de
   revenir = rétention.
10. **Avis Google + parrainage post-mission** ✅ livré : cron quotidien 11h UTC
    → edge `avis-parrainage` → après chaque mission TERMINEE, email de merci au
    soignant avec lien avis Google (configurable dans l'onglet Posts —
    `growth_config.lien_avis_google`, bloc omis tant que vide) + son code
    parrainage (UTM `parrainage-post-mission`). Dédupliqué par mission
    (`emails_post_mission`).
11. **Radar de demande et comptes ancres** ✅ livré : rapproche les signaux
    publics, missions, disponibilité à J+14 et soignants vérifiés par département
    et profession demandée. Les stratégies `COMPTE_ANCRE`, `RENFORCER_VIVIER`,
    `REVERSE_MARKETPLACE`, `RECURRENCE`, `CIBLER_GROUPE` et
    `PARTENARIAT_ECOLE` sont préparées en brouillons, jamais envoyées.

> Pré-lancement : `automatisations_marketing_actives=false`. Les crons de
> réactivation, digest et avis n'envoient rien ; le sourcing et le radar restent
> actifs car ils n'effectuent aucun contact. Toute prospection reste déclenchée
> manuellement depuis l'admin.

### Playbook IFSI/IFAS (manuel, 0 dev)
- Cible : 10 IFSI/IFAS du département de densification (annuaire ARS public).
- Pitch direction : « plateforme gratuite pour vos diplômés, missions vérifiées,
  paiement rapide » + affiche A4 avec QR `jolene.app?utm_source=ifsi&utm_campaign=[ecole]`.
- Moment clé : remise des diplômes (juin/juillet) et rentrées (septembre).
- Mesure : dashboard Acquisition (canal CAMPAGNE, campagne par école).

## 4. Monétisation (rappel des fondamentaux en place)

- Commission sur missions (taux par palier, BFA groupes) ✅
- Premium soignant/étab ✅ — pousser l'upsell au moment des succès (mission
  terminée, paiement reçu).
- Affacturage (avance de trésorerie) ✅ — marge financière additionnelle.
- À l'échelle : offre « flotte » multi-étabs pour groupes (EMEIS, Korian…)
  négociée top-down — le CRM Prospection contient déjà leurs sièges.

## 5. Conformité growth (à respecter)

- Emails B2B de prospection : licites vers adresses professionnelles
  génériques/fonction (opt-out mentionné dans chaque email — fait).
- Pas de scraping de membres de groupes FB (interdit Meta, risque ban).
- Publication assistée (copier-coller) uniquement — pas d'auto-post.
- RGPD : données prospects = données pro publiques (FINESS open data, licence ouverte).
