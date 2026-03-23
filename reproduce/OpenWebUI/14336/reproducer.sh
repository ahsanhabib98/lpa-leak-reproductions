#!/bin/bash

set -Eeuo pipefail

# ------------------------------------
# Hardcoded configuration
# ------------------------------------
OPENAI_API_KEY="sk-xxxx"
BASE_URL="http://localhost:3000"
EMAIL="user@example.org"
PASSWORD="userpassword"
NAME="user"

KB_NAME="leak-test"
KB_DESC="memory leak test"

TEST_FILE="./test_file.zip"
CONTAINER_NAME="open-webui"

MEM_LOG="memory_log.csv"
POLL_INTERVAL=2
POST_INGEST_WAIT=120

OPENAI_URL="https://api.openai.com/v1"

print_step () {
  echo
  echo "=================================================="
  echo "$1"
  echo "=================================================="
  echo
}

cleanup () {
  if [[ -n "${STATS_PID:-}" ]]; then
    kill "$STATS_PID" >/dev/null 2>&1 || true
  fi
}
trap cleanup EXIT

require_cmd () {
  command -v "$1" >/dev/null 2>&1 || {
    echo "Missing required command: $1"
    exit 1
  }
}

require_cmd curl
require_cmd docker
require_cmd python3
require_cmd awk
require_cmd file

print_step "Step 1: Start Open WebUI"
docker compose up -d

print_step "Step 2: Wait for Open WebUI"
for i in {1..90}; do
  if curl -fsS "$BASE_URL" >/dev/null 2>&1; then
    echo "Open WebUI is ready"
    break
  fi
  sleep 2
done

if ! curl -fsS "$BASE_URL" >/dev/null 2>&1; then
  echo "Open WebUI did not become ready in time"
  exit 1
fi

print_step "Step 3: Create user"
SIGNUP_RESPONSE=$(curl -sS -X POST "$BASE_URL/api/v1/auths/signup" \
  -H "Content-Type: application/json" \
  -d "{\"name\":\"$NAME\",\"email\":\"$EMAIL\",\"password\":\"$PASSWORD\"}" || true)

echo "$SIGNUP_RESPONSE"

print_step "Step 4: Login"
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

print_step "Step 5: Configure embedding"
EMBED_RESPONSE=$(curl -sS -X POST "$BASE_URL/api/v1/retrieval/embedding/update" \
  -H "Authorization: Bearer $TOKEN" \
  -H "Content-Type: application/json" \
  -d "{
    \"embedding_engine\": \"openai\",
    \"embedding_model\": \"text-embedding-3-large\",
    \"embedding_batch_size\": 1,
    \"openai_config\": {
      \"url\": \"$OPENAI_URL\",
      \"key\": \"$OPENAI_API_KEY\"
    }
  }")

echo "$EMBED_RESPONSE"

print_step "Step 6: Enable Hybrid Search"
HYBRID_RESPONSE=$(curl -sS -X POST "$BASE_URL/api/v1/retrieval/config/update" \
  -H "Authorization: Bearer $TOKEN" \
  -H "Content-Type: application/json" \
  -d '{"ENABLE_RAG_HYBRID_SEARCH": true}')

echo "$HYBRID_RESPONSE"

print_step "Step 7: Create knowledge base"
KB_RESPONSE=$(curl -sS -X POST "$BASE_URL/api/v1/knowledge/create" \
  -H "Authorization: Bearer $TOKEN" \
  -H "Content-Type: application/json" \
  -d "{\"name\":\"$KB_NAME\",\"description\":\"$KB_DESC\"}")

echo "$KB_RESPONSE"

KB_ID=$(printf '%s' "$KB_RESPONSE" | python3 -c 'import sys,json
try:
    print(json.load(sys.stdin).get("id",""))
except Exception:
    print("")
')

if [[ -z "$KB_ID" ]]; then
  echo "Knowledge base creation failed"
  exit 1
fi

echo "Knowledge base ID: $KB_ID"

print_step "Step 8: Verify knowledge base details"
KB_DETAILS_RESPONSE=$(curl -sS -X GET "$BASE_URL/api/v1/knowledge/$KB_ID" \
  -H "Authorization: Bearer $TOKEN")

echo "$KB_DETAILS_RESPONSE"

print_step "Step 9: Validate input file"
if [[ ! -f "$TEST_FILE" ]]; then
  echo "File not found: $TEST_FILE"
  echo "Edit TEST_FILE inside the script and set it to your actual file path."
  exit 1
fi

ls -lh "$TEST_FILE"
file "$TEST_FILE" || true

print_step "Step 10: Start memory tracking"
echo "time,name,mem_usage,mem_percent" > "$MEM_LOG"

(
while true; do
  echo "$(date),$(docker stats --no-stream --format '{{.Name}},{{.MemUsage}},{{.MemPerc}}' | grep "$CONTAINER_NAME")" >> "$MEM_LOG"
  sleep "$POLL_INTERVAL"
done
) &

STATS_PID=$!

echo "Memory logging started: $MEM_LOG"

print_step "Step 11: Upload file"
BASENAME="$(basename "$TEST_FILE")"

UPLOAD_RESPONSE=$(curl -sS -X POST "$BASE_URL/api/v1/files/" \
  -H "Authorization: Bearer $TOKEN" \
  -H "Accept: application/json" \
  -F "file=@${TEST_FILE};filename=${BASENAME}")

echo "$UPLOAD_RESPONSE"

FILE_ID=$(printf '%s' "$UPLOAD_RESPONSE" | python3 -c 'import sys,json
try:
    print(json.load(sys.stdin).get("id",""))
except Exception:
    print("")
')

FILE_NAME=$(printf '%s' "$UPLOAD_RESPONSE" | python3 -c 'import sys,json
try:
    print(json.load(sys.stdin).get("filename",""))
except Exception:
    print("")
')

FILE_HASH=$(printf '%s' "$UPLOAD_RESPONSE" | python3 -c 'import sys,json
try:
    print(json.load(sys.stdin).get("hash",""))
except Exception:
    print("")
')

FILE_CONTENT_TYPE=$(printf '%s' "$UPLOAD_RESPONSE" | python3 -c 'import sys,json
try:
    print(json.load(sys.stdin).get("meta",{}).get("content_type",""))
except Exception:
    print("")
')

FILE_SIZE_BYTES=$(printf '%s' "$UPLOAD_RESPONSE" | python3 -c 'import sys,json
try:
    print(json.load(sys.stdin).get("meta",{}).get("size",""))
except Exception:
    print("")
')

UPLOAD_ERROR=$(printf '%s' "$UPLOAD_RESPONSE" | python3 -c 'import sys,json
try:
    print(json.load(sys.stdin).get("error",""))
except Exception:
    print("")
')

if [[ -n "$UPLOAD_ERROR" && "$UPLOAD_ERROR" != "None" ]]; then
  echo "Upload failed: $UPLOAD_ERROR"
  echo
  echo "===== Last 150 Open WebUI log lines ====="
  docker logs --tail 150 "$CONTAINER_NAME" || true
  exit 1
fi

if [[ -z "$FILE_ID" ]]; then
  echo "Upload failed: no file ID returned"
  echo
  echo "===== Last 150 Open WebUI log lines ====="
  docker logs --tail 150 "$CONTAINER_NAME" || true
  exit 1
fi

echo "Uploaded file ID: $FILE_ID"
echo "Uploaded filename: $FILE_NAME"
echo "File hash: $FILE_HASH"
echo "Content-Type: $FILE_CONTENT_TYPE"
echo "Size: $FILE_SIZE_BYTES bytes"

print_step "Step 12: Attach file to knowledge base"
ADD_RESPONSE=$(curl -sS -X POST "$BASE_URL/api/v1/knowledge/$KB_ID/file/add" \
  -H "Authorization: Bearer $TOKEN" \
  -H "Content-Type: application/json" \
  -d "{\"file_id\":\"$FILE_ID\"}")

echo "$ADD_RESPONSE"

ATTACHED_FILE_ID=$(printf '%s' "$ADD_RESPONSE" | python3 -c 'import sys,json
try:
    data=json.load(sys.stdin)
    files=data.get("files",[])
    if files:
        print(files[0].get("id",""))
    else:
        print("")
except Exception:
    print("")
')

ATTACHED_FILE_NAME=$(printf '%s' "$ADD_RESPONSE" | python3 -c 'import sys,json
try:
    data=json.load(sys.stdin)
    files=data.get("files",[])
    if files:
        print(files[0].get("meta",{}).get("name",""))
    else:
        print("")
except Exception:
    print("")
')

if [[ -z "$ATTACHED_FILE_ID" ]]; then
  echo "Failed to verify file attachment in knowledge base"
  echo
  echo "===== Last 150 Open WebUI log lines ====="
  docker logs --tail 150 "$CONTAINER_NAME" || true
  exit 1
fi

echo "Attached file ID in knowledge base: $ATTACHED_FILE_ID"
echo "Attached file name in knowledge base: $ATTACHED_FILE_NAME"

print_step "Step 13: List knowledge bases"
KB_LIST_RESPONSE=$(curl -sS -X GET "$BASE_URL/api/v1/knowledge/list" \
  -H "Authorization: Bearer $TOKEN" || true)

if [[ -z "$KB_LIST_RESPONSE" ]]; then
  KB_LIST_RESPONSE=$(curl -sS -X GET "$BASE_URL/api/v1/knowledge/" \
    -H "Authorization: Bearer $TOKEN" || true)
fi

echo "$KB_LIST_RESPONSE"

print_step "Step 14: Wait after ingestion"
sleep "$POST_INGEST_WAIT"

print_step "Step 15: Show memory samples"
tail -n 20 "$MEM_LOG" || true

print_step "Step 16: Inspect data directory"
docker exec "$CONTAINER_NAME" sh -lc '
echo "DATA DIRECTORY STRUCTURE"
ls -lah /app/backend/data || true

echo
echo "SAMPLE FILES"
find /app/backend/data -maxdepth 3 -type f | head -50 || true
'

print_step "Done"
echo "Knowledge base ID: $KB_ID"
echo "Uploaded file ID: $FILE_ID"
echo "Memory log: $MEM_LOG"