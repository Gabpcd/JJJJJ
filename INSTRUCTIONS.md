# Instructions Claude Code — Jolene

Ce fichier contient les règles et patterns à appliquer 
systématiquement lors des sessions de développement Jolene.

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

## Comptes test audit

Préfixe email : audit-{profession}@jolene-test.dev
Mot de passe : auditTest2026!
À ne pas supprimer (utilisés pour tests SQL futurs).
