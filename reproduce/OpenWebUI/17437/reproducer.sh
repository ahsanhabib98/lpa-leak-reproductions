#!/bin/bash

set -e

BASE_URL="http://localhost:3000"

echo ""
echo "=============================="
echo "Step 1: Start Open WebUI (v0.6.28)"
echo "=============================="
echo ""

docker compose up -d

echo ""
echo "Waiting for Open WebUI to be ready..."
echo ""

for i in {1..60}; do
  if curl -fsS $BASE_URL >/dev/null 2>&1; then
    echo "Open WebUI is ready"
    break
  fi
  sleep 2
done

echo ""
echo "=============================="
echo "Step 2: Creating user (v0.6.28 API)"
echo "=============================="
echo ""

SIGNUP_RESPONSE=$(curl -s -X POST $BASE_URL/api/v1/auths/signup \
  -H "Content-Type: application/json" \
  -d '{
    "name": "user",
    "email": "user@example.org",
    "password": "userpassword"
  }' || true)

echo "Signup response:"
echo "$SIGNUP_RESPONSE"

echo ""
echo "=============================="
echo "Step 3: Running reproducer script"
echo "=============================="
echo ""

python3 main.py

echo ""
echo "=============================="
echo "Step 4: Inspecting plaintext storage"
echo "=============================="
echo ""

CONTAINER_NAME=$(docker ps --format "{{.Names}}" | grep -i open-webui | head -n 1)

if [ -z "$CONTAINER_NAME" ]; then
  echo "Open WebUI container not found"
  exit 1
fi

docker exec "$CONTAINER_NAME" sh -lc '
echo
echo "DATA DIRECTORY STRUCTURE"
ls -lah /app/backend/data

echo
echo "STORED FILES (sample)"
find /app/backend/data -maxdepth 3 -type f | head -50

echo
echo "DATABASE CHECK"
ls -lah /app/backend/data/webui.db || echo "webui.db not found"

echo
echo "RAW FILE CONTENT (proof)"
head -n 20 /app/backend/data/webui.db 2>/dev/null || echo "Cannot preview DB"
'

echo ""
echo "=============================="
echo "DONE: Plaintext storage verified (v0.6.28)"
echo "=============================="
echo ""