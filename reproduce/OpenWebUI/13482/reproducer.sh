#!/bin/bash

set -Eeuo pipefail

# ------------------------------------
# Hardcoded configuration
# ------------------------------------
BASE_URL="http://localhost:3000"
EMAIL="user@example.org"
PASSWORD="userpassword"
NAME="user"

FAKE_SERVER_SCRIPT="main.py"
SERVER_LOG="fake_server.log"
CONTAINER_NAME="open-webui"

MEMORY_VALUE="MY_SECRET_TEST_13482"
TEST_PROMPT="what do you know about me?"
MODEL_NAME="gpt-4o"

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

json_get () {
  python3 -c "import sys,json; data=json.load(sys.stdin); print($1)"
}

print_step "Step 0: Install fake server dependencies"
if ! python3 -m pip --version >/dev/null 2>&1; then
  echo "[*] python3 pip not found, installing..."
  sudo apt update
  sudo apt install -y python3-pip
fi
python3 -m pip install fastapi uvicorn

print_step "Step 1: Start fake OpenAI-compatible server"
pkill -f "$FAKE_SERVER_SCRIPT" >/dev/null 2>&1 || true
: > "$SERVER_LOG"
nohup python3 "$FAKE_SERVER_SCRIPT" > "$SERVER_LOG" 2>&1 &
sleep 3

print_step "Step 2: Start Open WebUI"
docker compose down -v || true
docker compose up -d

print_step "Step 3: Wait for Open WebUI"
for i in {1..120}; do
  if curl -fsS "$BASE_URL" >/dev/null 2>&1; then
    echo "Open WebUI is ready"
    break
  fi
  sleep 2
done

if ! curl -fsS "$BASE_URL" >/dev/null 2>&1; then
  echo "Open WebUI did not become ready in time"
  docker logs "$CONTAINER_NAME" --tail 100 || true
  exit 1
fi

print_step "Step 4: Create user"
SIGNUP_RESPONSE=$(curl -sS -X POST "$BASE_URL/api/v1/auths/signup" \
  -H "Content-Type: application/json" \
  -d "{\"name\":\"$NAME\",\"email\":\"$EMAIL\",\"password\":\"$PASSWORD\"}" || true)
echo "$SIGNUP_RESPONSE"

print_step "Step 5: Login"
TOKEN=$(curl -sS -X POST "$BASE_URL/api/v1/auths/signin" \
  -H "Content-Type: application/json" \
  -d "{\"email\":\"$EMAIL\",\"password\":\"$PASSWORD\"}" \
  | python3 -c 'import sys,json
try:
    print(json.load(sys.stdin).get("token",""))
except Exception:
    print("")
')

if [[ -z "$TOKEN" ]]; then
  echo "Failed to get auth token"
  exit 1
fi
echo "Token acquired"

print_step "Step 6: Enable memory"
SETTINGS_RESPONSE=$(curl -sS -X POST "$BASE_URL/api/v1/users/user/settings/update" \
  -H "Authorization: Bearer $TOKEN" \
  -H "Content-Type: application/json" \
  -d '{"ui":{"version":"0.6.5","memory":true}}')
echo "$SETTINGS_RESPONSE"

MEMORY_ENABLED=$(printf '%s' "$SETTINGS_RESPONSE" | python3 -c 'import sys,json
try:
    print(json.load(sys.stdin).get("ui",{}).get("memory",False))
except Exception:
    print("")
')

if [[ "$MEMORY_ENABLED" != "True" && "$MEMORY_ENABLED" != "true" ]]; then
  echo "Failed to enable memory"
  exit 1
fi

print_step "Step 7: Add memory"
MEMORY_RESPONSE=$(curl -sS -X POST "$BASE_URL/api/v1/memories/add" \
  -H "Authorization: Bearer $TOKEN" \
  -H "Content-Type: application/json" \
  -d "{\"content\":\"$MEMORY_VALUE\"}")
echo "$MEMORY_RESPONSE"

MEMORY_CONTENT=$(printf '%s' "$MEMORY_RESPONSE" | python3 -c 'import sys,json
try:
    print(json.load(sys.stdin).get("content",""))
except Exception:
    print("")
')

if [[ "$MEMORY_CONTENT" != "$MEMORY_VALUE" ]]; then
  echo "Failed to add memory"
  exit 1
fi

USER_MSG_ID=$(python3 - <<'PY'
import uuid
print(uuid.uuid4())
PY
)

ASSISTANT_MSG_ID=$(python3 - <<'PY'
import uuid
print(uuid.uuid4())
PY
)

TS=$(python3 - <<'PY'
import time
print(int(time.time()))
PY
)

TS_MS=$(python3 - <<'PY'
import time
print(int(time.time() * 1000))
PY
)

CURRENT_DATE=$(TZ=America/Chicago date +%F)
CURRENT_TIME=$(TZ=America/Chicago date +%T)
CURRENT_DATETIME=$(TZ=America/Chicago date '+%F %T')
CURRENT_WEEKDAY=$(TZ=America/Chicago date +%A)

print_step "Step 8: Create new chat"
CHAT_NEW_RESPONSE=$(curl -sS -X POST "$BASE_URL/api/v1/chats/new" \
  -H "Authorization: Bearer $TOKEN" \
  -H "Content-Type: application/json" \
  -d "{
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

CHAT_ID=$(printf '%s' "$CHAT_NEW_RESPONSE" | python3 -c 'import sys,json
try:
    print(json.load(sys.stdin).get("id",""))
except Exception:
    print("")
')

if [[ -z "$CHAT_ID" ]]; then
  echo "Failed to create chat"
  exit 1
fi
echo "Chat ID: $CHAT_ID"

print_step "Step 9: Update chat with assistant placeholder"
CHAT_UPDATE1_RESPONSE=$(curl -sS -X POST "$BASE_URL/api/v1/chats/$CHAT_ID" \
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
echo "$CHAT_UPDATE1_RESPONSE"

print_step "Step 10: Query memories"
MEM_QUERY_RESPONSE=$(curl -sS -X POST "$BASE_URL/api/v1/memories/query" \
  -H "Authorization: Bearer $TOKEN" \
  -H "Content-Type: application/json" \
  -d "{\"content\":\"$TEST_PROMPT\"}")
echo "$MEM_QUERY_RESPONSE"

if ! echo "$MEM_QUERY_RESPONSE" | grep -q "$MEMORY_VALUE"; then
  echo "Memory query did not return expected memory"
  exit 1
fi

print_step "Step 11: Call /api/chat/completions"
CHAT_COMPLETIONS_RESPONSE=$(curl -sS -N -X POST "$BASE_URL/api/chat/completions" \
  -H "Authorization: Bearer $TOKEN" \
  -H "Content-Type: application/json" \
  -d "{
    \"background_tasks\": {
      \"tags_generation\": true,
      \"title_generation\": true
    },
    \"chat_id\": \"$CHAT_ID\",
    \"features\": {
      \"code_interpreter\": false,
      \"image_generation\": false,
      \"web_search\": false
    },
    \"id\": \"$ASSISTANT_MSG_ID\",
    \"messages\": [
      {
        \"content\": \"\n\nUser Context:\n1. [$CURRENT_DATE]. $MEMORY_VALUE\n\",
        \"role\": \"system\"
      },
      {
        \"content\": \"$TEST_PROMPT\",
        \"role\": \"user\"
      }
    ],
    \"model\": \"$MODEL_NAME\",
    \"model_item\": {
      \"actions\": [],
      \"id\": \"$MODEL_NAME\",
      \"name\": \"$MODEL_NAME\",
      \"object\": \"model\",
      \"openai\": {
        \"id\": \"$MODEL_NAME\",
        \"object\": \"model\",
        \"owned_by\": \"openai\"
      },
      \"tags\": [],
      \"urlIdx\": 0
    },
    \"params\": {},
    \"session_id\": \"reproducer-session\",
    \"stream\": true,
    \"tool_servers\": [],
    \"variables\": {
      \"{{CURRENT_DATE}}\": \"$CURRENT_DATE\",
      \"{{CURRENT_DATETIME}}\": \"$CURRENT_DATETIME\",
      \"{{CURRENT_TIME}}\": \"$CURRENT_TIME\",
      \"{{CURRENT_TIMEZONE}}\": \"America/Chicago\",
      \"{{CURRENT_WEEKDAY}}\": \"$CURRENT_WEEKDAY\",
      \"{{USER_LANGUAGE}}\": \"en-US\",
      \"{{USER_LOCATION}}\": \"Unknown\",
      \"{{USER_NAME}}\": \"$NAME\"
    }
  }" || true)
echo "$CHAT_COMPLETIONS_RESPONSE"

print_step "Step 12: Call /api/chat/completed"
CHAT_COMPLETED_RESPONSE=$(curl -sS -X POST "$BASE_URL/api/chat/completed" \
  -H "Authorization: Bearer $TOKEN" \
  -H "Content-Type: application/json" \
  -d "{
    \"chat_id\": \"$CHAT_ID\",
    \"id\": \"$ASSISTANT_MSG_ID\",
    \"messages\": [
      {
        \"content\": \"$TEST_PROMPT\",
        \"id\": \"$USER_MSG_ID\",
        \"role\": \"user\",
        \"timestamp\": $TS
      },
      {
        \"content\": \"ok\",
        \"id\": \"$ASSISTANT_MSG_ID\",
        \"role\": \"assistant\",
        \"timestamp\": $TS
      }
    ],
    \"model\": \"$MODEL_NAME\",
    \"model_item\": {
      \"actions\": [],
      \"id\": \"$MODEL_NAME\",
      \"name\": \"$MODEL_NAME\",
      \"object\": \"model\",
      \"openai\": {
        \"id\": \"$MODEL_NAME\",
        \"object\": \"model\",
        \"owned_by\": \"openai\"
      },
      \"tags\": [],
      \"urlIdx\": 0
    },
    \"session_id\": \"reproducer-session\"
  }")
echo "$CHAT_COMPLETED_RESPONSE"

print_step "Step 13: Final chat update"
CHAT_UPDATE2_RESPONSE=$(curl -sS -X POST "$BASE_URL/api/v1/chats/$CHAT_ID" \
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
            \"content\": \"ok\",
            \"done\": true,
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
          \"content\": \"ok\",
          \"done\": true,
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
echo "$CHAT_UPDATE2_RESPONSE"

print_step "Step 14: Show fake server logs"
sleep 3
cat "$SERVER_LOG"

print_step "Step 15: Validate leakage"
if grep -q "$MEMORY_VALUE" "$SERVER_LOG"; then
  echo "[+] SUCCESS: memory was sent to external provider request"
else
  echo "[-] FAILED: memory not found in fake server log"
  echo
  echo "===== Last 100 Open WebUI log lines ====="
  docker logs --tail 100 "$CONTAINER_NAME" || true
  exit 1
fi

print_step "Done"
echo "Chat ID: $CHAT_ID"
echo "User message ID: $USER_MSG_ID"
echo "Assistant message ID: $ASSISTANT_MSG_ID"
echo "Memory value: $MEMORY_VALUE"
echo "Log file: $SERVER_LOG"