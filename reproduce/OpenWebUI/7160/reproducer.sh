#!/bin/bash

set -e

echo "=================================================="
echo "Step 1: Start containers"
echo "=================================================="

docker compose down -v || true
docker compose up -d

echo ""
echo "=================================================="
echo "Step 2: Wait for containers to be ready"
echo "=================================================="

# Wait for LDAP
echo "Waiting for LDAP..."
until docker exec ldap ldapwhoami -x -D "cn=admin,dc=example,dc=org" -w "admin" >/dev/null 2>&1; do
  sleep 2
done
echo "LDAP is ready"

# Wait for Open WebUI
echo "Waiting for Open WebUI..."
until curl -s http://localhost:3000 >/dev/null 2>&1; do
  sleep 2
done
echo "Open WebUI is ready"

echo ""
echo "=================================================="
echo "Step 3: Install Python dependencies (if needed)"
echo "=================================================="

python3 - <<EOF
import importlib
try:
    importlib.import_module("requests")
except ImportError:
    import subprocess
    subprocess.check_call(["pip3", "install", "requests"])
EOF

echo ""
echo "=================================================="
echo "Step 4: Run main.py"
echo "=================================================="

python3 main.py

echo ""
echo "=================================================="
echo "Done"
echo "=================================================="