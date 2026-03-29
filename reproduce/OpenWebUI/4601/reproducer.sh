#!/bin/bash

set -Eeuo pipefail

BASE_URL="http://localhost:3000"

USER1_EMAIL="user1@example.com"
USER1_PASSWORD="user1password"
USER1_NAME="user1"

USER2_EMAIL="user2@example.com"
USER2_PASSWORD="user2password"
USER2_NAME="user2"

OLLAMA_CONTAINER="ollama"
MODEL_NAME="llama3.2:latest"

VALID_FILE="./with_contents.docx"
EMPTY_FILE="./empty.docx"

PROMPT="what is this?"

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
require_cmd jq

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

process_doc () {
  local token="$1"
  local file_id="$2"

  curl -sS -X POST "$BASE_URL/rag/api/v1/process/doc" \
    -H "Authorization: Bearer $token" \
    -H "Content-Type: application/json" \
    -d "{\"file_id\":\"$file_id\"}"
}

print_step "Step 1: Start containers"
docker compose up -d

print_step "Step 2: Wait for Open WebUI"
for i in {1..120}; do
  if curl -fsS "$BASE_URL" >/dev/null 2>&1; then
    echo "Open WebUI is ready"
    break
  fi
  sleep 2
done

print_step "Step 3: Wait for Ollama"
for i in {1..120}; do
  if docker exec "$OLLAMA_CONTAINER" ollama list >/dev/null 2>&1; then
    echo "Ollama is ready"
    break
  fi
  sleep 2
done

print_step "Step 4: Pull model"
docker exec -i "$OLLAMA_CONTAINER" ollama pull "$MODEL_NAME"

print_step "Step 5: Check test files"
ls -lh "$VALID_FILE" "$EMPTY_FILE"

print_step "Step 6: Create User1"
USER1_SIGNUP_RESPONSE=$(curl -sS -X POST "$BASE_URL/api/v1/auths/signup" \
  -H "Content-Type: application/json" \
  -d "{\"name\":\"$USER1_NAME\",\"email\":\"$USER1_EMAIL\",\"password\":\"$USER1_PASSWORD\"}" || true)
echo "$USER1_SIGNUP_RESPONSE"

print_step "Step 7: Create User2"
USER2_SIGNUP_RESPONSE=$(curl -sS -X POST "$BASE_URL/api/v1/auths/signup" \
  -H "Content-Type: application/json" \
  -d "{\"name\":\"$USER2_NAME\",\"email\":\"$USER2_EMAIL\",\"password\":\"$USER2_PASSWORD\"}" || true)
echo "$USER2_SIGNUP_RESPONSE"

print_step "Step 8: Login User1"
USER1_LOGIN_RESPONSE=$(curl -sS -X POST "$BASE_URL/api/v1/auths/signin" \
  -H "Content-Type: application/json" \
  -d "{\"email\":\"$USER1_EMAIL\",\"password\":\"$USER1_PASSWORD\"}")
echo "$USER1_LOGIN_RESPONSE"

USER1_TOKEN=$(echo "$USER1_LOGIN_RESPONSE" | jq -r '.token')
USER1_ID=$(echo "$USER1_LOGIN_RESPONSE" | jq -r '.id')

print_step "Step 9: Login User2"
USER2_LOGIN_RESPONSE=$(curl -sS -X POST "$BASE_URL/api/v1/auths/signin" \
  -H "Content-Type: application/json" \
  -d "{\"email\":\"$USER2_EMAIL\",\"password\":\"$USER2_PASSWORD\"}")
echo "$USER2_LOGIN_RESPONSE"

USER2_TOKEN=$(echo "$USER2_LOGIN_RESPONSE" | jq -r '.token')
USER2_ID=$(echo "$USER2_LOGIN_RESPONSE" | jq -r '.id')

print_step "Step 10: Approve User2 via API"
USER2_APPROVE_RESPONSE=$(curl -sS -X POST "$BASE_URL/api/v1/users/update/role" \
  -H "Authorization: Bearer $USER1_TOKEN" \
  -H "Content-Type: application/json" \
  -d "{\"id\":\"$USER2_ID\",\"role\":\"user\"}")
echo "$USER2_APPROVE_RESPONSE"

print_step "Step 11: Login User2 again"
USER2_LOGIN_RESPONSE=$(curl -sS -X POST "$BASE_URL/api/v1/auths/signin" \
  -H "Content-Type: application/json" \
  -d "{\"email\":\"$USER2_EMAIL\",\"password\":\"$USER2_PASSWORD\"}")
echo "$USER2_LOGIN_RESPONSE"

USER2_TOKEN=$(echo "$USER2_LOGIN_RESPONSE" | jq -r '.token')
USER2_ID=$(echo "$USER2_LOGIN_RESPONSE" | jq -r '.id')

print_step "Step 12: User1 uploads valid file"
USER1_UPLOAD_RESPONSE=$(curl -sS -X POST "$BASE_URL/api/v1/files/" \
  -H "Authorization: Bearer $USER1_TOKEN" \
  -F "file=@$VALID_FILE")
echo "$USER1_UPLOAD_RESPONSE"

USER1_FILE_ID=$(echo "$USER1_UPLOAD_RESPONSE" | jq -r '.id')

print_step "Step 12.1: Process User1 document"
USER1_PROCESS_RESPONSE=$(process_doc "$USER1_TOKEN" "$USER1_FILE_ID")
echo "$USER1_PROCESS_RESPONSE"

USER1_COLLECTION_NAME=$(echo "$USER1_PROCESS_RESPONSE" | jq -r '.collection_name // ""')

USER1_FILE_OBJ=$(echo "$USER1_UPLOAD_RESPONSE" | jq -c --arg cn "$USER1_COLLECTION_NAME" '
{
  type: "file",
  id: .id,
  url: ("/api/v1/files/" + .id),
  file: .,
  name: .meta.name,
  collection_name: $cn,
  status: "processed",
  size: .meta.size,
  error: ""
}')

print_step "Step 13: User1 create new chat"
USER1_USER_MSG_ID=$(uuid_gen)
USER1_ASSISTANT_MSG_ID=$(uuid_gen)
USER1_TS=$(now_s)
USER1_TS_MS=$(now_ms)

USER1_CHAT_NEW_RESPONSE=$(curl -sS -X POST "$BASE_URL/api/v1/chats/new" \
  -H "Authorization: Bearer $USER1_TOKEN" \
  -H "Content-Type: application/json" \
  -d "{
    \"chat\": {
      \"history\": {
        \"currentId\": \"$USER1_ASSISTANT_MSG_ID\",
        \"messages\": {
          \"$USER1_USER_MSG_ID\": {
            \"childrenIds\": [\"$USER1_ASSISTANT_MSG_ID\"],
            \"content\": \"$PROMPT\",
            \"files\": [$USER1_FILE_OBJ],
            \"id\": \"$USER1_USER_MSG_ID\",
            \"models\": [\"$MODEL_NAME\"],
            \"parentId\": null,
            \"role\": \"user\",
            \"timestamp\": $USER1_TS
          },
          \"$USER1_ASSISTANT_MSG_ID\": {
            \"childrenIds\": [],
            \"content\": \"\",
            \"id\": \"$USER1_ASSISTANT_MSG_ID\",
            \"model\": \"$MODEL_NAME\",
            \"modelName\": \"$MODEL_NAME\",
            \"parentId\": \"$USER1_USER_MSG_ID\",
            \"role\": \"assistant\",
            \"timestamp\": $USER1_TS,
            \"userContext\": null
          }
        }
      },
      \"id\": \"\",
      \"messages\": [
        {
          \"childrenIds\": [\"$USER1_ASSISTANT_MSG_ID\"],
          \"content\": \"$PROMPT\",
          \"files\": [$USER1_FILE_OBJ],
          \"id\": \"$USER1_USER_MSG_ID\",
          \"models\": [\"$MODEL_NAME\"],
          \"parentId\": null,
          \"role\": \"user\",
          \"timestamp\": $USER1_TS
        },
        {
          \"childrenIds\": [],
          \"content\": \"\",
          \"id\": \"$USER1_ASSISTANT_MSG_ID\",
          \"model\": \"$MODEL_NAME\",
          \"modelName\": \"$MODEL_NAME\",
          \"parentId\": \"$USER1_USER_MSG_ID\",
          \"role\": \"assistant\",
          \"timestamp\": $USER1_TS,
          \"userContext\": null
        }
      ],
      \"models\": [\"$MODEL_NAME\"],
      \"params\": {},
      \"tags\": [],
      \"timestamp\": $USER1_TS_MS,
      \"title\": \"New Chat\"
    }
  }")
echo "$USER1_CHAT_NEW_RESPONSE"

REAL_USER1_CHAT_ID=$(echo "$USER1_CHAT_NEW_RESPONSE" | jq -r '.id')
USER1_CHAT_OBJ=$(echo "$USER1_CHAT_NEW_RESPONSE" | jq -c '.chat')

print_step "Step 14: User1 ollama chat"
USER1_OLLAMA_RESPONSE=$(curl -sS -N -X POST "$BASE_URL/ollama/api/chat" \
  -H "Authorization: Bearer $USER1_TOKEN" \
  -H "Content-Type: application/json" \
  -d "{
    \"chat_id\": \"$REAL_USER1_CHAT_ID\",
    \"files\": [$USER1_FILE_OBJ, $USER1_FILE_OBJ],
    \"id\": \"$USER1_ASSISTANT_MSG_ID\",
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

USER1_ASSISTANT_CONTENT=$(echo "$USER1_OLLAMA_RESPONSE" | jq -rs '[ .[] | .message.content? // empty ] | join("")')
USER1_INFO=$(echo "$USER1_OLLAMA_RESPONSE" | jq -rs '
  [ .[] | select(.done == true) | {
      total_duration,
      load_duration,
      prompt_eval_count,
      prompt_eval_duration,
      eval_count,
      eval_duration
    } ] | last // null
')
USER1_CITATIONS=$(echo "$USER1_OLLAMA_RESPONSE" | jq -rs '
  [ .[] | .citations? // empty ] | map(select(. != null)) | last // null
')

echo "$USER1_ASSISTANT_CONTENT"

print_step "Step 15: Save User1 chat"
USER1_UPDATED_CHAT=$(echo "$USER1_CHAT_OBJ" | jq -c \
  --arg amid "$USER1_ASSISTANT_MSG_ID" \
  --arg content "$USER1_ASSISTANT_CONTENT" \
  --argjson info "$USER1_INFO" \
  --argjson cits "$USER1_CITATIONS" '
  .history.messages[$amid].content = $content
  | .history.messages[$amid].done = true
  | .history.messages[$amid].info = $info
  | .history.messages[$amid].citations = $cits
  | .messages |= map(
      if .id == $amid then
        .content = $content
        | .done = true
        | .info = $info
        | .citations = $cits
      else .
      end
    )
')

curl -sS -X POST "$BASE_URL/api/v1/chats/$REAL_USER1_CHAT_ID" \
  -H "Authorization: Bearer $USER1_TOKEN" \
  -H "Content-Type: application/json" \
  -d "{
    \"chat\": $USER1_UPDATED_CHAT,
    \"files\": [$USER1_FILE_OBJ]
  }" > /dev/null

print_step "Step 16: User2 uploads empty file"
USER2_UPLOAD_RESPONSE=$(curl -sS -X POST "$BASE_URL/api/v1/files/" \
  -H "Authorization: Bearer $USER2_TOKEN" \
  -F "file=@$EMPTY_FILE")
echo "$USER2_UPLOAD_RESPONSE"

USER2_FILE_ID=$(echo "$USER2_UPLOAD_RESPONSE" | jq -r '.id')

print_step "Step 16.1: Process User2 document"
USER2_PROCESS_RESPONSE=$(process_doc "$USER2_TOKEN" "$USER2_FILE_ID")
echo "$USER2_PROCESS_RESPONSE"

USER2_COLLECTION_NAME=$(echo "$USER2_PROCESS_RESPONSE" | jq -r '.collection_name // ""')

USER2_FILE_OBJ=$(echo "$USER2_UPLOAD_RESPONSE" | jq -c --arg cn "$USER2_COLLECTION_NAME" '
{
  type: "file",
  id: .id,
  url: ("/api/v1/files/" + .id),
  file: .,
  name: .meta.name,
  collection_name: $cn,
  status: "processed",
  size: .meta.size,
  error: ""
}')

print_step "Step 17: User2 create new chat"
USER2_USER_MSG_ID=$(uuid_gen)
USER2_ASSISTANT_MSG_ID=$(uuid_gen)
USER2_TS=$(now_s)
USER2_TS_MS=$(now_ms)

USER2_CHAT_NEW_RESPONSE=$(curl -sS -X POST "$BASE_URL/api/v1/chats/new" \
  -H "Authorization: Bearer $USER2_TOKEN" \
  -H "Content-Type: application/json" \
  -d "{
    \"chat\": {
      \"history\": {
        \"currentId\": \"$USER2_ASSISTANT_MSG_ID\",
        \"messages\": {
          \"$USER2_USER_MSG_ID\": {
            \"childrenIds\": [\"$USER2_ASSISTANT_MSG_ID\"],
            \"content\": \"$PROMPT\",
            \"files\": [$USER2_FILE_OBJ],
            \"id\": \"$USER2_USER_MSG_ID\",
            \"models\": [\"$MODEL_NAME\"],
            \"parentId\": null,
            \"role\": \"user\",
            \"timestamp\": $USER2_TS
          },
          \"$USER2_ASSISTANT_MSG_ID\": {
            \"childrenIds\": [],
            \"content\": \"\",
            \"id\": \"$USER2_ASSISTANT_MSG_ID\",
            \"model\": \"$MODEL_NAME\",
            \"modelName\": \"$MODEL_NAME\",
            \"parentId\": \"$USER2_USER_MSG_ID\",
            \"role\": \"assistant\",
            \"timestamp\": $USER2_TS,
            \"userContext\": null
          }
        }
      },
      \"id\": \"\",
      \"messages\": [
        {
          \"childrenIds\": [\"$USER2_ASSISTANT_MSG_ID\"],
          \"content\": \"$PROMPT\",
          \"files\": [$USER2_FILE_OBJ],
          \"id\": \"$USER2_USER_MSG_ID\",
          \"models\": [\"$MODEL_NAME\"],
          \"parentId\": null,
          \"role\": \"user\",
          \"timestamp\": $USER2_TS
        },
        {
          \"childrenIds\": [],
          \"content\": \"\",
          \"id\": \"$USER2_ASSISTANT_MSG_ID\",
          \"model\": \"$MODEL_NAME\",
          \"modelName\": \"$MODEL_NAME\",
          \"parentId\": \"$USER2_USER_MSG_ID\",
          \"role\": \"assistant\",
          \"timestamp\": $USER2_TS,
          \"userContext\": null
        }
      ],
      \"models\": [\"$MODEL_NAME\"],
      \"params\": {},
      \"tags\": [],
      \"timestamp\": $USER2_TS_MS,
      \"title\": \"New Chat\"
    }
  }")
echo "$USER2_CHAT_NEW_RESPONSE"

REAL_USER2_CHAT_ID=$(echo "$USER2_CHAT_NEW_RESPONSE" | jq -r '.id')
USER2_CHAT_OBJ=$(echo "$USER2_CHAT_NEW_RESPONSE" | jq -c '.chat')

print_step "Step 18: User2 ollama chat"
USER2_OLLAMA_RESPONSE=$(curl -sS -N -X POST "$BASE_URL/ollama/api/chat" \
  -H "Authorization: Bearer $USER2_TOKEN" \
  -H "Content-Type: application/json" \
  -d "{
    \"chat_id\": \"$REAL_USER2_CHAT_ID\",
    \"files\": [$USER2_FILE_OBJ, $USER2_FILE_OBJ],
    \"id\": \"$USER2_ASSISTANT_MSG_ID\",
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

USER2_ASSISTANT_CONTENT=$(echo "$USER2_OLLAMA_RESPONSE" | jq -rs '[ .[] | .message.content? // empty ] | join("")')
USER2_INFO=$(echo "$USER2_OLLAMA_RESPONSE" | jq -rs '
  [ .[] | select(.done == true) | {
      total_duration,
      load_duration,
      prompt_eval_count,
      prompt_eval_duration,
      eval_count,
      eval_duration
    } ] | last // null
')
USER2_CITATIONS=$(echo "$USER2_OLLAMA_RESPONSE" | jq -rs '
  [ .[] | .citations? // empty ] | map(select(. != null)) | last // null
')

echo "$USER2_ASSISTANT_CONTENT"

print_step "Step 19: Save User2 chat"
USER2_UPDATED_CHAT=$(echo "$USER2_CHAT_OBJ" | jq -c \
  --arg amid "$USER2_ASSISTANT_MSG_ID" \
  --arg content "$USER2_ASSISTANT_CONTENT" \
  --argjson info "$USER2_INFO" \
  --argjson cits "$USER2_CITATIONS" '
  .history.messages[$amid].content = $content
  | .history.messages[$amid].done = true
  | .history.messages[$amid].info = $info
  | .history.messages[$amid].citations = $cits
  | .messages |= map(
      if .id == $amid then
        .content = $content
        | .done = true
        | .info = $info
        | .citations = $cits
      else .
      end
    )
')

curl -sS -X POST "$BASE_URL/api/v1/chats/$REAL_USER2_CHAT_ID" \
  -H "Authorization: Bearer $USER2_TOKEN" \
  -H "Content-Type: application/json" \
  -d "{
    \"chat\": $USER2_UPDATED_CHAT,
    \"files\": [$USER2_FILE_OBJ]
  }" > /dev/null

print_step "Step 20: Show only User2 citation"
USER2_FINAL_CHAT=$(curl -sS "$BASE_URL/api/v1/chats/$REAL_USER2_CHAT_ID" \
  -H "Authorization: Bearer $USER2_TOKEN")

echo "$USER2_FINAL_CHAT" | jq -r '
  .chat.history.messages[]?
  | select(.role=="assistant")
  | .citations[]?.document[]?
'