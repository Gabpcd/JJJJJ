-- Sprint 15 PR 2 — Suppression Flow B DPAE (raccourci sans preuve)
--
-- Le Flow B (RPC fn_confirmer_dpae + bouton "J'ai effectué la DPAE")
-- permettait à un établissement de marquer la DPAE comme effectuée
-- sans saisir le numéro URSSAF retourné. Aucune preuve traçable, faille
-- en cas de contrôle URSSAF.
--
-- Seul subsiste le Flow A : fn_generer_donnees_dpae (payload pré-rempli)
-- + fn_enregistrer_numero_dpae (saisie du n° URSSAF = preuve légale).
--
-- Le seul appelant (BandeauRappelDPAE.tsx) est mis à jour dans la même
-- PR : le bouton "J'ai effectué la DPAE" est retiré ; le bandeau devient
-- purement informatif et renvoie vers la section DPAEStatus pour saisir
-- le numéro URSSAF.
--
-- Aucune autre dépendance backend audit confirmé :
--   grep -rn "fn_confirmer_dpae" supabase/ → 0 résultat hors la migration
--   d'origine 20260411 (création initiale).

DROP FUNCTION IF EXISTS public.fn_confirmer_dpae(uuid);
