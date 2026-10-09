#!/usr/bin/env bash
# =============================================================================
# Vérifie que la passerelle répond pour chaque usage de l'app.
#
#   AI_API_KEY=sk-... ./scripts/smoke-test.sh [GATEWAY_URL]
#
# Sans AI_API_KEY, utilise la LITELLM_MASTER_KEY du fichier .env.
# =============================================================================
set -uo pipefail

cd "$(dirname "$0")/.."

GATEWAY_URL="${1:-${GATEWAY_URL:-http://localhost:4000}}"
KEY="${AI_API_KEY:-}"
if [[ -z "$KEY" && -f .env ]]; then
  KEY="$(grep -E '^LITELLM_MASTER_KEY=' .env | cut -d= -f2-)"
fi
: "${KEY:?Définir AI_API_KEY ou remplir .env}"

FAILED=0

check() {
  local name="$1" path="$2" body="$3" extract="$4"
  local start end out
  start=$(date +%s%N)
  out=$(curl -sS --max-time 120 "$GATEWAY_URL$path" \
    -H "Authorization: Bearer $KEY" \
    -H "Content-Type: application/json" \
    -d "$body" 2>&1)
  end=$(date +%s%N)
  local ms=$(( (end - start) / 1000000 ))
  local result
  if result=$(printf '%s' "$out" | python3 -c "$extract" 2>/dev/null); then
    printf '✅ %-16s %6d ms  %s\n' "$name" "$ms" "$result"
  else
    printf '❌ %-16s %6d ms  %s\n' "$name" "$ms" "$(printf '%s' "$out" | head -c 300)"
    FAILED=1
  fi
}

CHAT='import json,sys; d=json.load(sys.stdin); print(d["choices"][0]["message"]["content"].strip().replace("\n"," ")[:80])'
JSON_CHECK='import json,sys; d=json.load(sys.stdin); c=d["choices"][0]["message"]["content"]; json.loads(c[c.index("{"):c.rindex("}")+1]); print("JSON valide", "(" + str(d["usage"]["completion_tokens"]) + " tokens)")'

echo "Passerelle : $GATEWAY_URL"
echo

check "notitia-fast" /v1/chat/completions \
  '{"model":"notitia-fast","messages":[{"role":"user","content":"Corrige : je suis aller au marcher hier"}],"max_tokens":60}' \
  "$CHAT"

check "notitia-smart" /v1/chat/completions \
  '{"model":"notitia-smart","messages":[{"role":"system","content":"Réponds uniquement en JSON."},{"role":"user","content":"Donne {\"titre\": ..., \"points\": [...]} pour une réunion sur le budget 2027."}],"response_format":{"type":"json_object"},"max_tokens":400}' \
  "$JSON_CHECK"

check "notitia-premium" /v1/chat/completions \
  '{"model":"notitia-premium","messages":[{"role":"system","content":"Réponds uniquement en JSON."},{"role":"user","content":"Donne {\"root\": {\"label\": ..., \"children\": [...]}} pour une mind map sur le télétravail, 3 enfants."}],"response_format":{"type":"json_object"},"max_tokens":800}' \
  "$JSON_CHECK"

check "notitia-embed" /v1/embeddings \
  '{"model":"notitia-embed","input":"Réunion budget 2027","dimensions":1024}' \
  'import json,sys; d=json.load(sys.stdin); print(len(d["data"][0]["embedding"]), "dimensions")'

check "brave-search" /v1/search/brave-search \
  '{"query":"intelligence artificielle open source","max_results":2}' \
  'import json,sys; d=json.load(sys.stdin); r=d["results"]; assert r; print(len(r), "résultats —", r[0]["url"][:60])'

echo
if [[ $FAILED -eq 0 ]]; then echo "Tout est OK 🎉"; else echo "Au moins un test a échoué."; fi
exit $FAILED
