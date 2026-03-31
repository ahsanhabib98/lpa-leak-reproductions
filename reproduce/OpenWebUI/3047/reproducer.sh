#!/usr/bin/env bash

set -euo pipefail

BASE_URL="http://localhost:3000"
EMAIL="admin@example.com"
PASSWORD="ChangeMe123!"
RERANKER_MODEL="BAAI/bge-reranker-v2-m3"

print_step() {
  echo
  echo "=================================================="
  echo "$1"
  echo "=================================================="
}

wait_for_webui() {
  for i in {1..120}; do
    if curl -fsS "$BASE_URL/health" >/dev/null 2>&1; then
      echo "Open WebUI is ready"
      return 0
    fi
    sleep 2
  done
  echo "ERROR: Open WebUI not ready"
  exit 1
}

print_step "Step 1: Start containers"
docker compose down -v || true
docker compose up -d

print_step "Step 2: Wait for Open WebUI"
wait_for_webui

print_step "Step 3: Start docker stats logging"
STATS_LOG="docker_stats.log"
(
  while true; do
    {
      echo "----- $(date) -----"
      docker stats --no-stream
      echo
    } >> "$STATS_LOG"
    sleep 5
  done
) &
STATS_PID=$!

echo "Logging docker stats to $STATS_LOG (PID=$STATS_PID)"

print_step "Step 4: Create user (ignore if exists)"
SIGNUP_RESPONSE=$(curl -sS -X POST "$BASE_URL/api/v1/auths/signup" \
  -H "Content-Type: application/json" \
  -d "{\"name\":\"admin\",\"email\":\"$EMAIL\",\"password\":\"$PASSWORD\"}" || true)
echo "$SIGNUP_RESPONSE"

print_step "Step 5: Login"
LOGIN_RESPONSE=$(curl -sS -X POST "$BASE_URL/api/v1/auths/signin" \
  -H "Content-Type: application/json" \
  -d "{\"email\":\"$EMAIL\",\"password\":\"$PASSWORD\"}")

echo "$LOGIN_RESPONSE"

TOKEN=$(python3 - <<'PY' "$LOGIN_RESPONSE"
import json, sys
data = json.loads(sys.argv[1])
print(data.get("token") or data.get("access_token") or "")
PY
)

if [ -z "$TOKEN" ]; then
  echo "ERROR: Failed to get token"
  exit 1
fi

print_step "Step 6: Enable Hybrid Search"
QUERY_SETTINGS_RESPONSE=$(curl -sS -X POST "$BASE_URL/rag/api/v1/query/settings/update" \
  -H "Authorization: Bearer $TOKEN" \
  -H "Content-Type: application/json" \
  -d '{
    "hybrid": true,
    "k": 5,
    "r": 0,
    "status": true,
    "template": "Use the following context as your learned knowledge, inside <context></context> XML tags.\n<context>\n [context]\n</context>\n\nWhen answer to user:\n- If you don'\''t know, just say that you don'\''t know.\n- If you don'\''t know when you are not sure, ask for clarification.\nAvoid mentioning that you obtained the information from the context.\nAnd answer according to the language of the user'\''s question.\n\nGiven the context information, answer the query.\nQuery: [query]"
  }')

echo "$QUERY_SETTINGS_RESPONSE"

print_step "Step 7: Set reranker model"
RERANK_RESPONSE=$(curl -sS -X POST "$BASE_URL/rag/api/v1/reranking/update" \
  -H "Authorization: Bearer $TOKEN" \
  -H "Content-Type: application/json" \
  -d "{\"reranking_model\":\"$RERANKER_MODEL\"}")

echo "$RERANK_RESPONSE"

print_step "Step 8: Monitor memory snapshot"
docker stats --no-stream