#!/bin/bash

set -Eeuo pipefail

# ------------------------------------
# Hardcoded configuration
# ------------------------------------
BASE_URL="http://localhost:3000"
EMAIL="user@example.org"
PASSWORD="userpassword"
NAME="user"

OPENWEBUI_CONTAINER="open-webui"
OLLAMA_CONTAINER="ollama"

MODEL_NAME="gpt-5.4-mini"
LOCAL_TASK_MODEL="llama3:latest"
TEST_PROMPT="TEST_AUTOCOMPLETE_FALLBACK_123456"

TCPDUMP_LOG="tcpdump_openai.log"
WEBUI_LOG="openwebui_runtime.log"

print_step () {
  echo
  echo "=================================================="
  echo "$1"
  echo "=================================================="
  echo
}

require_cmd () {
  command -v "$1" >/dev/null 2>&1 || {
    echo "Missing required command: $1"
    exit 1
  }
}

require_cmd curl
require_cmd docker
require_cmd python3
require_cmd tcpdump

cleanup () {
  set +e
  if [[ -n "${TCPDUMP_PID:-}" ]]; then
    sudo kill "$TCPDUMP_PID" >/dev/null 2>&1 || true
  fi
}
trap cleanup EXIT

uuid_gen () {
  python3 - <<'PY'
import uuid
print(uuid.uuid4())
PY
}

now_ms () {
  python3 - <<'PY'
import time
print(int(time.time() * 1000))
PY
}

now_s () {
  python3 - <<'PY'
import time
print(int(time.time()))
PY
}

print_step "Step 1: Start Open WebUI"
docker compose up -d

print_step "Step 2: Wait for Open WebUI"
for i in {1..120}; do
  if curl -fsS "$BASE_URL" >/dev/null 2>&1; then
    echo "Open WebUI is ready"
    break
  fi
  sleep 2
done

if ! curl -fsS "$BASE_URL" >/dev/null 2>&1; then
  echo "Open WebUI did not become ready in time"
  docker logs "$OPENWEBUI_CONTAINER" --tail 100 || true
  exit 1
fi

print_step "Step 3: Save current Open WebUI logs"
docker logs "$OPENWEBUI_CONTAINER" > "$WEBUI_LOG" 2>&1 || true

print_step "Step 4: Create user"
SIGNUP_RESPONSE=$(curl -sS -X POST "$BASE_URL/api/v1/auths/signup" \
  -H "Content-Type: application/json" \
  -d "{\"name\":\"$NAME\",\"email\":\"$EMAIL\",\"password\":\"$PASSWORD\"}" || true)
echo "$SIGNUP_RESPONSE"

print_step "Step 5: Login"
LOGIN_RESPONSE=$(curl -sS -X POST "$BASE_URL/api/v1/auths/signin" \
  -H "Content-Type: application/json" \
  -d "{\"email\":\"$EMAIL\",\"password\":\"$PASSWORD\"}")

echo "$LOGIN_RESPONSE"

TOKEN=$(printf '%s' "$LOGIN_RESPONSE" | python3 -c 'import sys,json
try:
    print(json.load(sys.stdin).get("token",""))
except Exception:
    print("")
')

USER_ID=$(printf '%s' "$LOGIN_RESPONSE" | python3 -c 'import sys,json
try:
    print(json.load(sys.stdin).get("id",""))
except Exception:
    print("")
')

if [[ -z "$TOKEN" || -z "$USER_ID" ]]; then
  echo "Failed to get auth token or user id"
  exit 1
fi

print_step "Step 6: Wait for Ollama"
for i in {1..120}; do
  if docker exec "$OLLAMA_CONTAINER" ollama list >/dev/null 2>&1; then
    echo "Ollama is ready"
    break
  fi
  sleep 2
done

if ! docker exec "$OLLAMA_CONTAINER" ollama list >/dev/null 2>&1; then
  echo "Ollama did not become ready in time"
  docker logs "$OLLAMA_CONTAINER" --tail 100 || true
  exit 1
fi

print_step "Step 7: Pull local model"
docker exec -it "$OLLAMA_CONTAINER" ollama pull llama3

print_step "Step 8: Update task config"
TASK_CONFIG_RESPONSE=$(curl -sS -X POST "$BASE_URL/api/v1/tasks/config/update" \
  -H "Authorization: Bearer $TOKEN" \
  -H "Content-Type: application/json" \
  -d "{
    \"AUTOCOMPLETE_GENERATION_INPUT_MAX_LENGTH\": -1,
    \"ENABLE_AUTOCOMPLETE_GENERATION\": true,
    \"ENABLE_RETRIEVAL_QUERY_GENERATION\": true,
    \"ENABLE_SEARCH_QUERY_GENERATION\": true,
    \"ENABLE_TAGS_GENERATION\": true,
    \"QUERY_GENERATION_PROMPT_TEMPLATE\": \"\",
    \"TAGS_GENERATION_PROMPT_TEMPLATE\": \"\",
    \"TASK_MODEL\": \"${LOCAL_TASK_MODEL}\",
    \"TASK_MODEL_EXTERNAL\": \"\",
    \"TITLE_GENERATION_PROMPT_TEMPLATE\": \"\",
    \"TOOLS_FUNCTION_CALLING_PROMPT_TEMPLATE\": \"\"
  }")
echo "$TASK_CONFIG_RESPONSE"

print_step "Step 9: Start tcpdump"
: > "$TCPDUMP_LOG"
sudo tcpdump -i any host api.openai.com > "$TCPDUMP_LOG" 2>&1 &
TCPDUMP_PID=$!
sleep 3

print_step "Step 10: Stop Ollama"
docker stop "$OLLAMA_CONTAINER"
sleep 5

print_step "Step 11: Trigger autocomplete"
AUTO_COMPLETIONS_RESPONSE=$(curl -sS -X POST "$BASE_URL/api/v1/tasks/auto/completions" \
  -H "Authorization: Bearer $TOKEN" \
  -H "Content-Type: application/json" \
  -d "{
    \"model\": \"${MODEL_NAME}\",
    \"prompt\": \"${TEST_PROMPT}\",
    \"stream\": false,
    \"type\": \"search query\"
  }" || true)
echo "$AUTO_COMPLETIONS_RESPONSE"

USER_MSG_ID=$(uuid_gen)
ASSISTANT_MSG_ID=$(uuid_gen)
CHAT_ID=$(uuid_gen)
TS=$(now_s)
TS_MS=$(now_ms)

print_step "Step 12: Create new chat"
CHAT_NEW_RESPONSE=$(curl -sS -X POST "$BASE_URL/api/v1/chats/new" \
  -H "Authorization: Bearer $TOKEN" \
  -H "Content-Type: application/json" \
  -d "{
    \"id\": \"$CHAT_ID\",
    \"user_id\": \"$USER_ID\",
    \"title\": \"New Chat\",
    \"chat\": {
      \"history\": {
        \"currentId\": \"$USER_MSG_ID\",
        \"messages\": {
          \"$USER_MSG_ID\": {
            \"childrenIds\": [],
            \"content\": \"$TEST_PROMPT\",
            \"id\": \"$USER_MSG_ID\",
            \"models\": [\"$MODEL_NAME\"],
            \"parentId\": null,
            \"role\": \"user\",
            \"timestamp\": $TS
          }
        }
      },
      \"id\": \"\",
      \"messages\": [
        {
          \"childrenIds\": [],
          \"content\": \"$TEST_PROMPT\",
          \"id\": \"$USER_MSG_ID\",
          \"models\": [\"$MODEL_NAME\"],
          \"parentId\": null,
          \"role\": \"user\",
          \"timestamp\": $TS
        }
      ],
      \"models\": [\"$MODEL_NAME\"],
      \"params\": {},
      \"tags\": [],
      \"timestamp\": $TS_MS,
      \"title\": \"New Chat\"
    }
  }")
echo "$CHAT_NEW_RESPONSE"

REAL_CHAT_ID=$(printf '%s' "$CHAT_NEW_RESPONSE" | python3 -c 'import sys,json
try:
    print(json.load(sys.stdin).get("id",""))
except Exception:
    print("")
')

if [[ -z "$REAL_CHAT_ID" ]]; then
  echo "Failed to create chat"
  exit 1
fi
echo "Chat ID: $REAL_CHAT_ID"

print_step "Step 13: Update chat with assistant placeholder"
CHAT_UPDATE_RESPONSE=$(curl -sS -X POST "$BASE_URL/api/v1/chats/$REAL_CHAT_ID" \
  -H "Authorization: Bearer $TOKEN" \
  -H "Content-Type: application/json" \
  -d "{
    \"chat\": {
      \"files\": [],
      \"history\": {
        \"currentId\": \"$ASSISTANT_MSG_ID\",
        \"messages\": {
          \"$ASSISTANT_MSG_ID\": {
            \"childrenIds\": [],
            \"content\": \"\",
            \"id\": \"$ASSISTANT_MSG_ID\",
            \"model\": \"$MODEL_NAME\",
            \"modelIdx\": 0,
            \"modelName\": \"$MODEL_NAME\",
            \"parentId\": \"$USER_MSG_ID\",
            \"role\": \"assistant\",
            \"timestamp\": $TS,
            \"userContext\": null
          },
          \"$USER_MSG_ID\": {
            \"childrenIds\": [\"$ASSISTANT_MSG_ID\"],
            \"content\": \"$TEST_PROMPT\",
            \"id\": \"$USER_MSG_ID\",
            \"models\": [\"$MODEL_NAME\"],
            \"parentId\": null,
            \"role\": \"user\",
            \"timestamp\": $TS
          }
        }
      },
      \"messages\": [
        {
          \"childrenIds\": [\"$ASSISTANT_MSG_ID\"],
          \"content\": \"$TEST_PROMPT\",
          \"id\": \"$USER_MSG_ID\",
          \"models\": [\"$MODEL_NAME\"],
          \"parentId\": null,
          \"role\": \"user\",
          \"timestamp\": $TS
        },
        {
          \"childrenIds\": [],
          \"content\": \"\",
          \"id\": \"$ASSISTANT_MSG_ID\",
          \"model\": \"$MODEL_NAME\",
          \"modelIdx\": 0,
          \"modelName\": \"$MODEL_NAME\",
          \"parentId\": \"$USER_MSG_ID\",
          \"role\": \"assistant\",
          \"timestamp\": $TS,
          \"userContext\": null
        }
      ],
      \"models\": [\"$MODEL_NAME\"],
      \"params\": {}
    }
  }")
echo "$CHAT_UPDATE_RESPONSE"

print_step "Step 14: Call /api/chat/completions"
CHAT_COMPLETIONS_RESPONSE=$(curl -sS -X POST "$BASE_URL/api/chat/completions" \
  -H "Authorization: Bearer $TOKEN" \
  -H "Content-Type: application/json" \
  -d "{
    \"chat_id\": \"$REAL_CHAT_ID\",
    \"id\": \"$ASSISTANT_MSG_ID\",
    \"messages\": [
      {
        \"content\": \"$TEST_PROMPT\",
        \"role\": \"user\"
      }
    ],
    \"model\": \"$MODEL_NAME\",
    \"params\": {},
    \"stream\": true
  }" || true)
echo "$CHAT_COMPLETIONS_RESPONSE"

print_step "Step 15: Stop tcpdump"
sleep 8
sudo kill "$TCPDUMP_PID" >/dev/null 2>&1 || true
unset TCPDUMP_PID

print_step "Step 16: Show Open WebUI logs"
docker logs "$OPENWEBUI_CONTAINER" --tail 300 | tee -a "$WEBUI_LOG"

print_step "Step 17: Show tcpdump output"
cat "$TCPDUMP_LOG"

print_step "Step 18: Validate fallback"
AUTO_MATCH=0
NET_MATCH=0

if grep -q "/api/v1/tasks/auto/completions" "$WEBUI_LOG"; then
  AUTO_MATCH=1
fi

if grep -q "POST /api/chat/completions" "$WEBUI_LOG"; then
  CHAT_MATCH=1
else
  CHAT_MATCH=0
fi

if grep -q "172\." "$TCPDUMP_LOG"; then
  NET_MATCH=1
fi

if [[ "$AUTO_MATCH" -eq 1 && "$CHAT_MATCH" -eq 1 && "$NET_MATCH" -eq 1 ]]; then
  echo "[+] SUCCESS: autocomplete and chat triggered external traffic after local model became unavailable"
else
  echo "[-] FAILED: could not confirm autocomplete/chat trigger with external traffic"
  echo
  echo "===== Last 100 Open WebUI log lines ====="
  docker logs --tail 100 "$OPENWEBUI_CONTAINER" || true
  exit 1
fi

print_step "Done"
echo "Chat ID: $REAL_CHAT_ID"
echo "User message ID: $USER_MSG_ID"
echo "Assistant message ID: $ASSISTANT_MSG_ID"
echo "TCP dump log: $TCPDUMP_LOG"
echo "Open WebUI log: $WEBUI_LOG"