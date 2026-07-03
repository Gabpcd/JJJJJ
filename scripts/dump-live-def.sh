#!/usr/bin/env bash
# dump-live-def.sh — garde-fou 9.0 : TOUTE redéfinition d'un objet Postgres
# part de sa définition LIVE en prod, jamais d'un fichier de migration du repo
# (les fichiers repo peuvent être obsolètes — cf. incident enum du 02/07/2026).
#
# Usage :
#   SUPABASE_ACCESS_TOKEN=... SUPABASE_PROJECT_REF=flripxtsyegjshnhzjkz \
#     scripts/dump-live-def.sh fonction fn_traiter_candidature
#   scripts/dump-live-def.sh trigger missions          # triggers d'une table
#   scripts/dump-live-def.sh policy soignants          # policies d'une table
#
# Sans credentials : imprime la requête SQL à coller dans l'éditeur SQL
# Supabase (ou à exécuter via MCP execute_sql).
set -euo pipefail

TYPE="${1:-}"
NOM="${2:-}"
if [ -z "$TYPE" ] || [ -z "$NOM" ]; then
  echo "Usage: $0 <fonction|trigger|policy> <nom_objet|nom_table>" >&2
  exit 1
fi

case "$TYPE" in
  fonction)
    QUERY="SELECT pg_get_functiondef(p.oid) FROM pg_proc p JOIN pg_namespace n ON n.oid = p.pronamespace WHERE n.nspname = 'public' AND p.proname = '$NOM'"
    ;;
  trigger)
    QUERY="SELECT pg_get_triggerdef(t.oid) FROM pg_trigger t JOIN pg_class c ON c.oid = t.tgrelid JOIN pg_namespace n ON n.oid = c.relnamespace WHERE n.nspname = 'public' AND c.relname = '$NOM' AND NOT t.tgisinternal"
    ;;
  policy)
    QUERY="SELECT policyname, permissive, roles, cmd, qual, with_check FROM pg_policies WHERE schemaname = 'public' AND tablename = '$NOM'"
    ;;
  *)
    echo "Type inconnu : $TYPE (attendu : fonction|trigger|policy)" >&2
    exit 1
    ;;
esac

if [ -n "${SUPABASE_ACCESS_TOKEN:-}" ] && [ -n "${SUPABASE_PROJECT_REF:-}" ]; then
  # API Management (même chemin que le step Heal du deploy — marche partout).
  curl -sf -X POST "https://api.supabase.com/v1/projects/${SUPABASE_PROJECT_REF}/database/query" \
    -H "Authorization: Bearer ${SUPABASE_ACCESS_TOKEN}" \
    -H "Content-Type: application/json" \
    -d "$(jq -n --arg q "$QUERY" '{query: $q}')" | jq -r '.[] | to_entries[] | .value'
else
  echo "-- Credentials absents (SUPABASE_ACCESS_TOKEN / SUPABASE_PROJECT_REF)."
  echo "-- Requête à exécuter dans l'éditeur SQL Supabase ou via MCP execute_sql :"
  echo "$QUERY;"
fi
