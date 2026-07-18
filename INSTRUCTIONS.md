# Instructions Claude Code — Jolene

Ce fichier contient les règles et patterns à appliquer 
systématiquement lors des sessions de développement Jolene.

## Source de vérité stack & outils

Avant d'ajouter un nouvel outil ou service, consulter 
`docs/audit-stack-existante.md` qui inventorie les 14 outils 
opérationnels (Sentry, Resend, Twilio, Stripe, Stripe Connect, 
YouSign, Chorus-Pro, Piste, Defacto, ProSantéConnect, Web Push 
VAPID, Capacitor, Vercel, Supabase Auth) et les secrets déjà 
configurés. Ne pas réinventer ce qui existe.

## Principe de travail

**Pas de tickets ni backlog.** Tout bug ou amélioration 
identifié pendant une session est traité dans la session 
courante. Pas de "TODO plus tard".

## Stack technique

- Frontend : React + TypeScript + Vite + Tailwind + 
  shadcn/ui + Capacitor (mobile)
- Backend : Supabase (PostgreSQL + Edge Functions Deno)
- Paiements : Stripe Connect
- Email : Resend
- SMS : Twilio
- Project Supabase ID : flripxtsyegjshnhzjkz

## Pattern push main après chaque batch

Après CHAQUE batch de commits :
1. Commit sur branche feature
2. git merge --ff-only sur main
3. git push origin main
4. Vérifier déploiement Vercel READY

Sans ce pattern, Vercel ne déploie pas et les 
modifications ne sont pas visibles. Bug récurrent à 
éviter.

## Pattern migrations DB — préservation des privilèges

Toute migration qui fait DROP FUNCTION suivi de 
CREATE FUNCTION (au lieu de CREATE OR REPLACE) 
RÉINITIALISE les ACL/GRANTs. Tout authenticated=X 
est effacé. PostgREST retourne alors 403 sur les appels.

Pattern OBLIGATOIRE :

```sql
DROP FUNCTION IF EXISTS public.fn_xxx(ancienne_signature);

CREATE OR REPLACE FUNCTION public.fn_xxx(nouvelle_signature)
RETURNS ...
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, extensions
AS $$
  -- code
$$;

-- TOUJOURS re-GRANT après DROP + CREATE
GRANT EXECUTE ON FUNCTION 
  public.fn_xxx(nouvelle_signature) 
  TO authenticated;
-- + anon si applicable (cas inscription)

NOTIFY pgrst, 'reload schema';
```

Vérification finale :

```sql
SELECT proname, proacl, prosecdef
FROM pg_proc 
WHERE proname = 'fn_modifiee';
-- proacl doit contenir authenticated=X
-- prosecdef doit être true (SECURITY DEFINER)
```

Si la vérification échoue, AJOUTER le GRANT manquant 
dans la même migration.

## Pattern extensions Postgres

Toute fonction utilisant gen_random_bytes(), crypt(), 
digest(), ou autre fonction de pgcrypto/extensions doit 
déclarer :

```sql
SET search_path = public, extensions
```

Sans cela, le trigger plante avec function 
gen_random_bytes does not exist et l'INSERT échoue 
silencieusement (rollback transaction → 500).

## Pattern audit

Toujours utiliser fn_ecrire_audit_safe (wrapper avec 
EXCEPTION WHEN OTHERS THEN NULL) pour que l'audit ne 
bloque jamais une opération métier.

Vérifier les CHECK constraints sur journaux_audit 
(journaux_audit_action_check, journaux_audit_type_acteur) 
quand on ajoute de nouveaux types d'actions.

## Pattern PostgREST

Après chaque migration qui modifie le schéma : NOTIFY 
pgrst, 'reload schema'; à la fin pour forcer le reload 
du cache PostgREST.

## Pattern soignants .single() vs .maybeSingle()

Utiliser TOUJOURS .maybeSingle() au lieu de .single() 
sur la table soignants car certains comptes auth.users 
n'ont pas de row soignants (signup interrompu, etc.) 
et .single() crash avec 406.

## Constantes métier 2026

Voir src/lib/constantes.ts pour :
- PROFESSIONS (15 valeurs)
- PROFESSIONS_NON_LIBERAL (5 valeurs)
- PROFESSIONS_SANS_RPPS (AS, AES uniquement)
- Cotisations sociales 2026

ADELI est OBSOLÈTE depuis 2024 (basculé RPPS). Ne plus 
proposer de saisie ADELI dans les nouveaux UIs. AS/AES 
n'ont jamais eu d'ADELI : leur identification se fait 
par diplôme + CNI uniquement.

## Captcha Turnstile (anti-bot)

Cloudflare Turnstile est intégré sur :

- Inscription Soignant (`InscriptionSoignant`)
- Inscription Établissement (`InscriptionEtablissement`)
- Wizard RPPS (`SectionProfilPrincipal` → `RppsVerifierInline`)
- Formulaires de contact publics

Il est volontairement absent de la connexion et du mot de passe oublié :
Supabase applique ses propres limites de tentatives et un CAPTCHA Web ne doit
jamais rendre l'authentification indisponible. Il est également désactivé dans
les builds Capacitor iOS/Android (`VITE_NATIVE_BUILD=true`).

Côté backend, le helper `supabase/functions/_shared/verify-turnstile.ts`
valide le token via l'API Cloudflare et reste fail-closed. Le seul bypass
possible exige explicitement `TURNSTILE_ALLOW_DEV_BYPASS=true` avec une origine
HTTP locale. Côté frontend, sans `VITE_TURNSTILE_SITE_KEY`, ou dans une app
native, le widget `<CaptchaTurnstile />` ne rend rien et appelle `onVerify('')`
immédiatement.

Variables à configurer pour activer en prod :

| Variable                      | Où                  | Valeur                |
| ----------------------------- | ------------------- | --------------------- |
| `VITE_TURNSTILE_SITE_KEY`     | Vercel (prod+preview) | Site key Turnstile  |
| `TURNSTILE_SECRET_KEY`        | Supabase secrets    | Secret key Turnstile  |

Création des clés : 
[dash.cloudflare.com → Turnstile](https://dash.cloudflare.com/?to=/:account/turnstile).

Bypass interne : la fonction `verify-rpps` accepte 3 types 
d'auth (service_role, anon key, user JWT). Le captcha est 
demandé uniquement quand un utilisateur authentifié appelle 
avec `soignant_id` (cas wizard profil). Les pré-checks pendant 
l'inscription (anon key sans `soignant_id`) sont exemptés pour 
ne pas bloquer la frappe en temps réel.

## Source maps Sentry

Le plugin `@sentry/vite-plugin` upload les source maps à chaque 
build prod si `SENTRY_AUTH_TOKEN` est présente. À ajouter dans 
les env vars Vercel.

| Variable             | Où     | Valeur                                                           |
| -------------------- | ------ | ---------------------------------------------------------------- |
| `SENTRY_AUTH_TOKEN`  | Vercel | Sentry → Settings → Account → API → Auth tokens (scope project)  |
| `SENTRY_ORG`         | Vercel | `jolene` (par défaut)                                            |
| `SENTRY_PROJECT`     | Vercel | `jolene-frontend` (par défaut)                                   |

Sans token, le build se fait normalement, juste sans upload des 
source maps. Les stacks production restent illisibles tant que 
le token n'est pas configuré.

## Comptes test audit

Préfixe email : audit-{profession}@jolene-test.dev
Mot de passe : auditTest2026!
À ne pas supprimer (utilisés pour tests SQL futurs).

## RPPS test (mode hybride dev)

L'edge function `verify-rpps` détecte les RPPS commençant 
par `00100` et les résout depuis la table `rpps_test` au 
lieu d'appeler l'API ANS. Activé hors production (gardé 
par `Deno.env.get('ENVIRONMENT') !== 'production'`).

Justification du préfixe : aucun vrai RPPS ne commence 
par `00100` (IDE → 1, médecins → 8, etc.), donc aucune 
collision possible.

RPPS test disponibles :

| RPPS          | Prénom   | Nom              | Profession    | Spécialité |
|---------------|----------|------------------|---------------|------------|
| 00100000001   | Marie    | TEST-IDE         | IDE           | —          |
| 00100000002   | Pierre   | TEST-MED-GEN     | MEDECIN       | —          |
| 00100000003   | Sophie   | TEST-MED-CARDIO  | MEDECIN       | SM48       |
| 00100000004   | Lucas    | TEST-KINE        | KINE          | —          |
| 00100000005   | Camille  | TEST-SF          | SAGE_FEMME    | —          |
| 00100000006   | Théo     | TEST-ORTHO       | ORTHOPHONISTE | —          |

Legacy (rétrocompat) : `00000000001` (PICARD Gabrielle, 
IDE) reste hardcodé dans la fonction.

Pour activer/désactiver : variable `ENVIRONMENT` dans 
les secrets Supabase. Default = `development` (test 
mode actif). Mettre à `production` pour bloquer le 
préfixe `00100` et forcer 100% API ANS.

Ajouter un nouveau RPPS test :

```sql
INSERT INTO public.rpps_test (rpps, prenom, nom, profession, specialite_medicale)
VALUES ('00100000007', 'Prenom', 'NOM', 'PROFESSION', NULL);
```
