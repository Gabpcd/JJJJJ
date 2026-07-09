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

if [ "$FAIL" -ne 0 ]; then
  echo "✗ guards.sh : au moins un garde-fou a échoué (voir ci-dessus)."
  exit 1
fi
echo "✓ guards.sh : les 3 garde-fous passent."
