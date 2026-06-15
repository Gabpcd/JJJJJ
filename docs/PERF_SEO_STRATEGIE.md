# Stratégie Performance & SEO — Jolene

> Audit honnête + roadmap priorisée. Mis à jour 2026-06-15.

## Constat : la fondation est déjà solide

Contrairement à ce qu'on pourrait croire, le gros du travail SEO/perf structurel **est déjà en place** :

| Domaine | État |
|---|---|
| Code-splitting | ✅ 149 routes en `React.lazy` (bundle initial minimal) |
| SEO meta/OG/Twitter | ✅ `index.html` + composant `SEOHead` (title/description/canonical/OG/Twitter par page) |
| Données structurées | ✅ JSON-LD `Organization` (accueil) + **`JobPosting` complet** sur les pages missions publiques (`/mission/:id`) → éligibles **Google for Jobs** |
| Sitemap | ✅ `sitemap.xml` (128 URLs) + sitemap dynamique missions (edge function) |
| PWA / manifest | ✅ manifest, icônes, theme-color |
| Images | ✅ composant `ImageOptimisee` |

**Le vrai bug perf récent** (recherche prospection seq-scan) a été corrigé via index trigram (#587).

## Wave 1 — appliqué (cette PR)

1. **Police Inter** : `@import` CSS render-blocking → `<link>` + **preconnect** dans `index.html`. Gain direct FCP/LCP (la police ne dépend plus du download+parse de tout le CSS).
2. **Preconnect** aux origines critiques : `fonts.googleapis.com`, `fonts.gstatic.com`, **API Supabase** (`*.supabase.co`). Ouvre les handshakes TLS au plus tôt → premier appel auth/data plus rapide.

## Wave 2 — recommandé (à planifier)

| Levier | Impact | Effort | Note |
|---|---|---|---|
| **Prérendu des pages publiques** (accueil, tarifs, à propos, CGU, missions) | 🔥 Élevé (SEO) | Moyen | C'est LA limite d'un SPA : Google rend le JS mais lentement/incomplet. `vite-plugin-prerender` ou prerender à build → HTML statique crawlable. Le plus gros levier SEO restant. |
| **Backlinks + contenu** | 🔥 Élevé (SEO) | Continu | Off-platform : annuaires santé, presse, partenariats. Le SEO technique est fait ; il manque l'autorité de domaine. |
| **Self-host de la police** (woff2 local) | Moyen (perf) | Faible | Supprime la dépendance réseau Google Fonts (1 origine de moins). |
| **`AdminSales` `select('*')`** sur `sales_contacts` | Faible (admin) | Faible | Paginer quand la table grossit (sourcing en masse). |
| **Lighthouse mobile absolu** sur preview Vercel | Mesure | Faible | Valider score réel (le CI vérifie un budget, pas le score absolu). |

## Wave 3 — quand le volume montera

- Index DB supplémentaires selon les requêtes lentes réelles (`pg_stat_statements`).
- Cache CDN/edge des pages publiques.
- `auth_rls_initplan` : wrapper `auth.uid()` en `(select auth.uid())` sur les policies des grosses tables (advisor Supabase) — gain marginal aujourd'hui, utile à l'échelle.

## Ce qu'on NE fait PAS (et pourquoi)

- Pas de sur-optimisation prématurée : la fondation tient, inutile d'ajouter de la complexité (SSR complet) avant d'avoir du trafic.
- Pas de « hacks SEO » (cloaking, keyword stuffing) : risque de pénalité Google, comme pour la délivrabilité email.
