#!/usr/bin/env bash
# =============================================================================
# Crée une clé virtuelle LiteLLM plafonnée.
#
#   ./scripts/create-key.sh <alias> [budget_usd_par_mois] [requetes_par_minute]
#
#   ./scripts/create-key.sh app-demo 3 30      # clé de l'app Flutter
#   ./scripts/create-key.sh dev-alexandre 2 60 # clé perso d'un membre
#
# Variables : GATEWAY_URL (défaut http://localhost:4000), LITELLM_MASTER_KEY
# (lue depuis ../.env si absente).
# =============================================================================
set -euo pipefail

cd "$(dirname "$0")/.."

ALIAS="${1:?Usage: $0 <alias> [budget_usd] [rpm]}"
BUDGET="${2:-3}"
RPM="${3:-30}"
GATEWAY_URL="${GATEWAY_URL:-http://localhost:4000}"

if [[ -z "${LITELLM_MASTER_KEY:-}" && -f .env ]]; then
  LITELLM_MASTER_KEY="$(grep -E '^LITELLM_MASTER_KEY=' .env | cut -d= -f2-)"
fi
: "${LITELLM_MASTER_KEY:?LITELLM_MASTER_KEY manquante}"

curl -sS --fail-with-body "$GATEWAY_URL/key/generate" \
  -H "Authorization: Bearer $LITELLM_MASTER_KEY" \
  -H "Content-Type: application/json" \
  -d @- <<JSON | python3 -c 'import json,sys; d=json.load(sys.stdin); print("Clé créée pour", d.get("key_alias"), ":\n\n  " + d["key"] + "\n\nBudget:", d.get("max_budget"), "$ /", d.get("budget_duration"))'
{
  "key_alias": "$ALIAS",
  "max_budget": $BUDGET,
  "budget_duration": "30d",
  "rpm_limit": $RPM,
  "models": ["notitia-fast", "notitia-smart", "notitia-premium", "notitia-fallback", "notitia-embed"]
}
JSON
