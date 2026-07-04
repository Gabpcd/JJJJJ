-- ============================================================
-- BUG-UI-OBLIG-1 — Cleanup stripe_transfers orphelins EN_ATTENTE
-- ============================================================
-- Contexte : avant Fix#2 (stripe-connect-pay-mission, fenêtre 15 min),
-- des transfers Checkout orphelins restaient EN_ATTENTE indéfiniment
-- (session abandonnée, webhook jamais reçu), bloquant toute re-tentative
-- de paiement côté étab.
--
-- Fix#2 déployé le 22/04/2026 auto-cleanup désormais les orphelins
-- > 15 min lors d'un retry. Ce script one-shot nettoie les orphelins
-- accumulés AVANT le fix.
--
-- Idempotent : la condition `statut = 'EN_ATTENTE' AND cree_le < NOW() -
-- INTERVAL '15 min'` devient toujours vide une fois Fix#2 actif.
-- ============================================================

UPDATE stripe_transfers
SET statut = 'ECHOUE',
    erreur = 'Cleanup orphelins BUG-UI-OBLIG-1 le 22/04/2026 (aucun webhook Stripe reçu > 15 min)'
WHERE statut = 'EN_ATTENTE'
  AND cree_le < NOW() - INTERVAL '15 minutes';
