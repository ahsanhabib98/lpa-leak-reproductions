#!/usr/bin/env bash

set -euo pipefail

REPO_URL="git@github.com:FoundationAgents/MetaGPT.git"
COMMIT="ab77bde54cca20d7176e968c994331d1a7fefa3e"
REPO_DIR="MetaGPT"
CONTAINER_NAME="metagpt-v066"

echo "=================================================="
echo "Step 1: Clone MetaGPT"
echo "=================================================="
if [ -d "$REPO_DIR" ]; then
  echo "Directory $REPO_DIR already exists, skipping clone"
else
  git clone "$REPO_URL"
fi

cd "$REPO_DIR"

echo
echo "=================================================="
echo "Step 2: Checkout vulnerable commit"
echo "=================================================="
git fetch --all --tags
git checkout "$COMMIT"

echo
echo "=================================================="
echo "Step 3: Create reproduce.py"
echo "=================================================="
cat > reproduce.py <<'PY'
import pandas as pd
import numpy as np
from uuid import uuid4

index_length = 10_000
column_length = 100

index = list(range(index_length))
columns = [uuid4() for _ in range(column_length)]
data = np.random.random((index_length, column_length))

df = pd.DataFrame(data=data, index=index, columns=columns)

while True:
    df2 = df.copy()
PY

echo
echo "=================================================="
echo "Step 4: Create docker-compose.yml"
echo "=================================================="
cat > docker-compose.yml <<'YAML'
services:
  metagpt:
    image: nikolaik/python-nodejs:python3.9-nodejs20-bullseye
    container_name: metagpt-v066
    working_dir: /app/metagpt
    stdin_open: true
    tty: true
    restart: unless-stopped
    volumes:
      - ./:/app/metagpt
      - ./artifacts:/app/metagpt/artifacts
    command: >
      sh -c "
      apt-get update &&
      apt-get install -y --no-install-recommends
      libgomp1
      git
      chromium
      fonts-ipafont-gothic
      fonts-wqy-zenhei
      fonts-thai-tlwg
      fonts-kacst
      fonts-freefont-ttf
      libxss1 &&
      npm install -g @mermaid-js/mermaid-cli &&
      mkdir -p workspace &&
      pip install --no-cache-dir -r requirements.txt &&
      pip install -e . &&
      tail -f /dev/null
      "
    environment:
      CHROME_BIN: /usr/bin/chromium
      PUPPETEER_CONFIG: /app/metagpt/config/puppeteer-config.json
      PUPPETEER_SKIP_CHROMIUM_DOWNLOAD: "true"
YAML

mkdir -p artifacts

echo
echo "=================================================="
echo "Step 5: Start container"
echo "=================================================="
docker compose up -d

echo
echo "=================================================="
echo "Step 6: Wait for container to be fully ready"
echo "=================================================="
until docker exec "$CONTAINER_NAME" sh -c "python -c 'import pandas, numpy; print(pandas.__version__)'" >/dev/null 2>&1; do
  echo "Waiting for dependencies to finish installing..."
  sleep 10
done
echo "Container is ready"

echo
echo "=================================================="
echo "Step 7: Show pandas version"
echo "=================================================="
docker exec "$CONTAINER_NAME" python -c "import pandas as pd; print(pd.__version__)"

echo
echo "=================================================="
echo "Step 8: Run reproduce.py in background"
echo "=================================================="
docker exec -d "$CONTAINER_NAME" sh -c "python /app/metagpt/reproduce.py > /app/metagpt/artifacts/reproduce.log 2>&1"

sleep 5

echo
echo "=================================================="
echo "Step 9: Show running python process"
echo "=================================================="
docker exec "$CONTAINER_NAME" sh -c "ps aux | grep reproduce.py | grep -v grep"

echo
echo "=================================================="
echo "Step 10: Show live container memory usage"
echo "=================================================="
echo "Press Ctrl+C to stop monitoring"
docker stats "$CONTAINER_NAME"