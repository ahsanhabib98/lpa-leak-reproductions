#!/bin/bash

set -e

BASE_URL="http://localhost:3000"

ADMIN_EMAIL="admin@example.com"
ADMIN_PASSWORD="password"

USER_EMAIL="user@example.com"
USER_PASSWORD="password"

MODEL_NAME="llama3.2:latest"
PROMPT="hello"

print_step () {
  echo
  echo "=================================================="
  echo "$1"
  echo "=================================================="
  echo
}

print_step "Step 1: Start containers"
docker compose up -d

print_step "Step 2: Wait for service"
sleep 10

print_step "Step 3: Pull Ollama model"
docker exec -i ollama ollama pull "$MODEL_NAME"

print_step "Step 4: Create admin"
ADMIN_SIGNUP_RESPONSE=$(curl -s -X POST "$BASE_URL/api/v1/auths/signup" \
  -H "Content-Type: application/json" \
  -d "{\"name\":\"admin\",\"email\":\"$ADMIN_EMAIL\",\"password\":\"$ADMIN_PASSWORD\"}")
echo "$ADMIN_SIGNUP_RESPONSE"

print_step "Step 5: Create user"
USER_SIGNUP_RESPONSE=$(curl -s -X POST "$BASE_URL/api/v1/auths/signup" \
  -H "Content-Type: application/json" \
  -d "{\"name\":\"user\",\"email\":\"$USER_EMAIL\",\"password\":\"$USER_PASSWORD\"}")
echo "$USER_SIGNUP_RESPONSE"

print_step "Step 6: Login admin"
ADMIN_LOGIN=$(curl -s -X POST "$BASE_URL/api/v1/auths/signin" \
  -H "Content-Type: application/json" \
  -d "{\"email\":\"$ADMIN_EMAIL\",\"password\":\"$ADMIN_PASSWORD\"}")
echo "$ADMIN_LOGIN"

ADMIN_TOKEN=$(echo "$ADMIN_LOGIN" | jq -r '.token // .access_token')

print_step "Step 7: Login user"
USER_LOGIN=$(curl -s -X POST "$BASE_URL/api/v1/auths/signin" \
  -H "Content-Type: application/json" \
  -d "{\"email\":\"$USER_EMAIL\",\"password\":\"$USER_PASSWORD\"}")
echo "$USER_LOGIN"

USER_TOKEN=$(echo "$USER_LOGIN" | jq -r '.token // .access_token')
USER_ID=$(echo "$USER_LOGIN" | jq -r '.id // .user.id')

print_step "Step 8: Approve user"
APPROVE_RESPONSE=$(curl -s -X POST "$BASE_URL/api/v1/users/update/role" \
  -H "Authorization: Bearer $ADMIN_TOKEN" \
  -H "Content-Type: application/json" \
  -d "{\"id\":\"$USER_ID\",\"role\":\"user\"}")
echo "$APPROVE_RESPONSE"

print_step "Step 9: User creates chat"
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

CREATE_CHAT_RESPONSE=$(curl -s -X POST "$BASE_URL/api/v1/chats/new" \
  -H "Authorization: Bearer $USER_TOKEN" \
  -H "Content-Type: application/json" \
  -d "{
    \"chat\": {
      \"history\": {
        \"currentId\": \"$ASSISTANT_MSG_ID\",
        \"messages\": {
          \"$USER_MSG_ID\": {
            \"childrenIds\": [\"$ASSISTANT_MSG_ID\"],
            \"content\": \"$PROMPT\",
            \"id\": \"$USER_MSG_ID\",
            \"models\": [\"$MODEL_NAME\"],
            \"parentId\": null,
            \"role\": \"user\",
            \"timestamp\": $TS
          },
          \"$ASSISTANT_MSG_ID\": {
            \"childrenIds\": [],
            \"content\": \"\",
            \"id\": \"$ASSISTANT_MSG_ID\",
            \"model\": \"$MODEL_NAME\",
            \"modelName\": \"$MODEL_NAME\",
            \"parentId\": \"$USER_MSG_ID\",
            \"role\": \"assistant\",
            \"timestamp\": $TS,
            \"userContext\": null
          }
        }
      },
      \"id\": \"\",
      \"messages\": [
        {
          \"childrenIds\": [\"$ASSISTANT_MSG_ID\"],
          \"content\": \"$PROMPT\",
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
          \"modelName\": \"$MODEL_NAME\",
          \"parentId\": \"$USER_MSG_ID\",
          \"role\": \"assistant\",
          \"timestamp\": $TS,
          \"userContext\": null
        }
      ],
      \"models\": [\"$MODEL_NAME\"],
      \"params\": {},
      \"tags\": [],
      \"timestamp\": $TS_MS,
      \"title\": \"PRIVATE TEST CHAT\"
    }
  }")
echo "$CREATE_CHAT_RESPONSE"

CHAT_ID=$(echo "$CREATE_CHAT_RESPONSE" | jq -r '.id')
CHAT_OBJ=$(echo "$CREATE_CHAT_RESPONSE" | jq -c '.chat')

print_step "Step 10: User waits for model response"
OLLAMA_RESPONSE=$(curl -sS -N -X POST "$BASE_URL/ollama/api/chat" \
  -H "Authorization: Bearer $USER_TOKEN" \
  -H "Content-Type: application/json" \
  -d "{
    \"chat_id\": \"$CHAT_ID\",
    \"id\": \"$ASSISTANT_MSG_ID\",
    \"messages\": [
      {
        \"content\": \"$PROMPT\",
        \"role\": \"user\"
      }
    ],
    \"model\": \"$MODEL_NAME\",
    \"options\": {},
    \"stream\": true
  }")

echo "$OLLAMA_RESPONSE"

ASSISTANT_CONTENT=$(echo "$OLLAMA_RESPONSE" | jq -rs '[ .[] | .message.content? // empty ] | join("")')
INFO=$(echo "$OLLAMA_RESPONSE" | jq -rs '
  [ .[] | select(.done == true) | {
      total_duration,
      load_duration,
      prompt_eval_count,
      prompt_eval_duration,
      eval_count,
      eval_duration
    } ] | last // null
')

print_step "Step 11: Save model response into chat"
UPDATED_CHAT=$(echo "$CHAT_OBJ" | jq -c \
  --arg amid "$ASSISTANT_MSG_ID" \
  --arg content "$ASSISTANT_CONTENT" \
  --argjson info "$INFO" '
  .history.messages[$amid].content = $content
  | .history.messages[$amid].done = true
  | .history.messages[$amid].info = $info
  | .messages |= map(
      if .id == $amid then
        .content = $content
        | .done = true
        | .info = $info
      else .
      end
    )
')

SAVE_RESPONSE=$(curl -s -X POST "$BASE_URL/api/v1/chats/$CHAT_ID" \
  -H "Authorization: Bearer $USER_TOKEN" \
  -H "Content-Type: application/json" \
  -d "{
    \"chat\": $UPDATED_CHAT
  }")
echo "$SAVE_RESPONSE"

print_step "Step 12: Admin accesses user chat list"
CHAT_LIST=$(curl -s "$BASE_URL/api/v1/chats/list/user/$USER_ID" \
  -H "Authorization: Bearer $ADMIN_TOKEN")
echo "$CHAT_LIST"

print_step "DONE"
echo "Shared URL: $BASE_URL/s/$CHAT_ID"