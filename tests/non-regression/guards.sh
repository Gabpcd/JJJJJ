#!/usr/bin/env bash
# ═══════════════════════════════════════════════════════════════════════════
# Garde-fous non-régression — motifs interdits dans src/.
#
# Chaque violation s'affiche avec fichier:ligne ; sortie 1 si au moins une.
# Règle : on corrige le CODE qui viole un garde-fou, on n'affaiblit JAMAIS
# les motifs ci-dessous.
#
# Usage : npm run test:guards   (depuis la racine du repo)
# ═══════════════════════════════════════════════════════════════════════════
set -uo pipefail
cd "$(dirname "$0")/../.."

FAIL=0

echo "── Garde-fou 1 : zéro 100vh dans src/ (Safari iOS → toujours 100dvh)"
if grep -rn "100vh" src/ --include='*.ts' --include='*.tsx' --include='*.css'; then
  FAIL=1
else
  echo "   OK"
fi

echo "── Garde-fou 2 : zéro catch vide dans src/ (toujours logger ou commenter)"
# perl -0777 : détecte aussi les catch vides multi-lignes, ce que grep ligne
# à ligne raterait. Un catch { /* raison */ } documenté ne matche pas.
EMPTY_CATCH=$(find src -type f \( -name '*.ts' -o -name '*.tsx' \) \
  -exec perl -0777 -ne 'print "$ARGV\n" if /catch\s*(\([^)]*\))?\s*\{\s*\}/' {} +)
if [ -n "$EMPTY_CATCH" ]; then
  echo "$EMPTY_CATCH"
  FAIL=1
else
  echo "   OK"
fi

echo "── Garde-fou 3 : zéro seed/secret de test en dur dans src/"
# Les seeds vivent dans e2e/helpers/, les secrets côté serveur (vault/edge
# functions). Aucun identifiant de compte de test ni clé service_role ne doit
# jamais atteindre le bundle frontend.
if grep -rnE "playwright-soignant|playwright-etab|seed-matching|seedMission|seedSwipe|sb_secret_|SERVICE_ROLE" \
  src/ --include='*.ts' --include='*.tsx'; then
  FAIL=1
else
  echo "   OK"
fi

echo "── Garde-fou 4 : zéro on_behalf_of dans les edge functions escrow (v15)"
# Le mandat SEPA nomme JOLENE créancier → Jolene merchant of record. Remettre
# on_behalf_of casserait les débits (Stripe exigerait un mandat au nom du compte
# connecté — bug recette run #10). Les mentions en commentaire sont autorisées.
OBO=$(grep -rn "on_behalf_of" supabase/functions/escrow-* supabase/functions/stripe-webhook 2>/dev/null \
  | grep -vE ':[0-9]+:\s*(\*|//)' || true)
if [ -n "$OBO" ]; then
  echo "$OBO"
  FAIL=1
elif ! grep -q "mandate_data" supabase/functions/escrow-debit-echeance/index.ts; then
  echo "   mandate_data absent de escrow-debit-echeance (customer_acceptance offline requis)"
  FAIL=1
else
  echo "   OK"
fi

echo "── Garde-fou 5 : audit escrow DIRECT en table (jamais rpc fn_ecrire_audit_safe)"
# Bug binding uuid PostgREST 14.5 : un rpc fn_ecrire_audit_safe côté edge échoue
# (« invalid input syntax for type uuid: null ») → audits muets (bug recette).
# Les fonctions escrow écrivent via le helper auditEscrow (insert direct).
AUDIT_RPC=$(grep -rn "fn_ecrire_audit_safe" supabase/functions/escrow-debit-echeance supabase/functions/escrow-release 2>/dev/null \
  | grep -vE ':[0-9]+:\s*(\*|//)' || true)
if [ -n "$AUDIT_RPC" ]; then
  echo "$AUDIT_RPC"
  FAIL=1
else
  MISSING_AUDIT=0
  for f in escrow-debit-echeance escrow-release stripe-webhook; do
    if ! grep -q "auditEscrow" "supabase/functions/$f/index.ts"; then
      echo "   helper auditEscrow absent de $f"
      MISSING_AUDIT=1
    fi
  done
  if [ "$MISSING_AUDIT" -ne 0 ]; then FAIL=1; else echo "   OK"; fi
fi

echo "── Garde-fou 6 : trigger enqueue release au passage DEBITE présent"
# Sans fn_trg_escrow_enqueue_on_debite (migration 20260709130000), un escrow
# DEBITE n'est jamais enfilé dans escrow_release_queue → aucun versement ne part
# (bug recette : release jamais déclenché après settlement).
if ! grep -rlq "fn_trg_escrow_enqueue_on_debite" supabase/migrations/; then
  echo "   migration du trigger fn_trg_escrow_enqueue_on_debite introuvable"
  FAIL=1
else
  echo "   OK"
fi

echo "── Garde-fou 7 : régime affiché = contrat de la MISSION, jamais le profil"
# Bug Lot 11/14 : Facturation affichait le type_exercice du PROFIL soignant
# comme chip de régime → « Libéral » sur une mission CDD. Le seul champ qui
# fait foi sur une ligne financière est type_contrat_applique (mission).
if grep -n "soignant_type_exercice" src/pages/FacturationEtablissement.tsx; then
  echo "   soignant_type_exercice réintroduit dans la Facturation (chip régime profil interdit)"
  FAIL=1
else
  echo "   OK"
fi

echo "── Garde-fou 8 : zéro upload ARRET_MALADIE côté front (zéro donnée de santé)"
# Mini-PR empêchement impérieux (docs/CONFORMITE.md §1.4) : le certificat
# médical ne doit JAMAIS revenir — attestation sur l'honneur uniquement.
if grep -rn "type_document: 'ARRET_MALADIE'" src/; then
  echo "   upload ARRET_MALADIE réintroduit dans src/ (donnée de santé interdite)"
  FAIL=1
else
  echo "   OK"
fi

if [ "$FAIL" -ne 0 ]; then
  echo "✗ guards.sh : au moins un garde-fou a échoué (voir ci-dessus)."
  exit 1
fi
echo "✓ guards.sh : les 8 garde-fous passent."
