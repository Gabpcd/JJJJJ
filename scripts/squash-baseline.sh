#!/usr/bin/env bash
# squash-baseline.sh — Squash baseline 9.0, ÉTAPE 0 (file-ops pures).
#
# Ne touche AUCUNE base de données. Produit localement le squash :
#   - supabase/migrations/00000000000000_baseline_prod.sql  (= dump prod versionné)
#   - db/migrations_archive/  (les 645 patchs historiques déplacés)
#
# À lancer depuis la racine du repo. Suivre ensuite docs/SQUASH_BASELINE_RUNBOOK.md
# (validation sur base neuve AVANT toute action sur la prod).
set -euo pipefail

ROOT="$(git rev-parse --show-toplevel)"
cd "$ROOT"

BASELINE_SRC="supabase/schema/public.sql"
BASELINE_DST="supabase/migrations/00000000000000_baseline_prod.sql"
ARCHIVE_DIR="db/migrations_archive"

if [ ! -f "$BASELINE_SRC" ]; then
  echo "ERREUR : $BASELINE_SRC introuvable (la baseline #800 doit être sur main)." >&2
  exit 1
fi

if [ -f "$BASELINE_DST" ]; then
  echo "ERREUR : $BASELINE_DST existe déjà — squash déjà produit ?" >&2
  exit 1
fi

mkdir -p "$ARCHIVE_DIR"

# 1. Archiver tous les patchs existants (git mv pour préserver l'historique).
count=0
for f in supabase/migrations/*.sql; do
  [ -e "$f" ] || continue
  git mv "$f" "$ARCHIVE_DIR/$(basename "$f")"
  count=$((count + 1))
done
echo "Archivé $count migration(s) → $ARCHIVE_DIR/"

# 2. Créer la migration initiale = dump prod.
cp "$BASELINE_SRC" "$BASELINE_DST"
git add "$BASELINE_DST"
echo "Créé $BASELINE_DST ($(wc -l < "$BASELINE_DST") lignes)"

# 3. README d'archive.
cat > "$ARCHIVE_DIR/README.md" <<'EOF'
# Archive des migrations historiques (pré-squash 9.0)

Ces fichiers étaient les 645 migrations de `supabase/migrations/` avant le squash
baseline (docs/SQUASH_BASELINE_RUNBOOK.md). Ils sont conservés pour l'archéologie
et le rollback (les noms de fichiers = les versions de `schema_migrations`).

Ils ne sont PLUS appliqués : la migration initiale
`supabase/migrations/00000000000000_baseline_prod.sql` (= dump prod) reconstruit
désormais le schéma complet depuis zéro. Toute nouvelle migration part de là.
EOF
git add "$ARCHIVE_DIR/README.md"

echo "OK. Squash produit localement. NE PAS committer/merger sans suivre"
echo "docs/SQUASH_BASELINE_RUNBOOK.md (validation base neuve + réparation registre prod)."
