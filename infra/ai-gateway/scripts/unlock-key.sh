#!/usr/bin/env bash
# =============================================================================
# Donne à une clé existante l'accès à TOUS les modèles de la passerelle
# (utile pour les clés créées avant l'ajout de notitia-transcribe).
# Le budget et la limite de requêtes de la clé ne changent pas.
#
#   ./scripts/unlock-key.sh sk-xxxxxxxx
#
# Variables : GATEWAY_URL (défaut http://localhost:4000), LITELLM_MASTER_KEY
# (lue depuis ../.env si absente).
# =============================================================================
set -euo pipefail

cd "$(dirname "$0")/.."

KEY="${1:?Usage: $0 <clé sk-...>}"
GATEWAY_URL="${GATEWAY_URL:-http://localhost:4000}"

if [[ -z "${LITELLM_MASTER_KEY:-}" && -f .env ]]; then
  LITELLM_MASTER_KEY="$(grep -E '^LITELLM_MASTER_KEY=' .env | cut -d= -f2-)"
fi
: "${LITELLM_MASTER_KEY:?LITELLM_MASTER_KEY manquante}"

curl -sS --fail-with-body "$GATEWAY_URL/key/update" \
  -H "Authorization: Bearer $LITELLM_MASTER_KEY" \
  -H "Content-Type: application/json" \
  -d "{\"key\": \"$KEY\", \"models\": []}" >/dev/null

echo "✅ Clé débloquée : accès à tous les modèles (budget inchangé)."
