# NextChat Fetch Proxy Memory Leak Reproducer

This tool reproduces the **NextChat fetch-proxy memory leak** described in GitHub Issue **#1598**.

## Purpose

This script reproduces the behavior where the NextChat proxy creates long-lived `fetch()` requests that are not aborted, causing memory growth when the upstream server does not close the connection.

## What the Script Does

1. Starts a **fake OpenAI-compatible upstream server** on `localhost:9000`.
2. The upstream server returns a **streaming SSE response that never closes**.
3. Sends many **concurrent streaming requests** to a running NextChat instance.
4. Periodically prints **memory and connection statistics** for the NextChat process.
5. Confirms whether the requests actually reach the upstream server.

---
## Instructions to Run NextChat

### Environment Configuration

Create a .env file and add the following environment variables.

```bash

# Your openai api key. (required)
OPENAI_API_KEY=sk-xxxx

# Access passsword, separated by comma. (optional)
CODE=your-password

# You can start service behind a proxy
PROXY_URL=http://localhost:7890

# Override openai api request base url. (optional)
# Default: https://api.openai.com
# Examples: http://your-openai-proxy.com
BASE_URL=http://host.docker.internal:9000

# Specify OpenAI organization ID.(optional)
# Default: Empty
# If you do not want users to input their own API key, set this value to 1.
OPENAI_ORG_ID=

# (optional)
# Default: Empty
# If you do not want users to input their own API key, set this value to 1.
HIDE_USER_API_KEY=

# (optional)
# Default: Empty
# If you do not want users to use GPT-4, set this value to 1.
DISABLE_GPT4=
```
---

### Run NextChat with Docker

Use the following docker-compose configuration.

```bash

services:
  chatgpt-next-web:
    profiles: ["no-proxy"]
    container_name: chatgpt-next-web
    image: yidadaa/chatgpt-next-web
    build: .
    ports:
      - 3000:3000
    extra_hosts:
      - "host.docker.internal:host-gateway"
    environment:
      - OPENAI_API_KEY=$OPENAI_API_KEY
      - CODE=$CODE
      - BASE_URL=$BASE_URL
      - OPENAI_ORG_ID=$OPENAI_ORG_ID
      - HIDE_USER_API_KEY=$HIDE_USER_API_KEY
      - DISABLE_GPT4=$DISABLE_GPT4

  chatgpt-next-web-proxy:
    profiles: ["proxy"]
    container_name: chatgpt-next-web-proxy
    image: yidadaa/chatgpt-next-web
    ports:
      - 3000:3000
    extra_hosts:
      - "host.docker.internal:host-gateway"
    environment:
      - OPENAI_API_KEY=$OPENAI_API_KEY
      - CODE=$CODE
      - PROXY_URL=$PROXY_URL
      - BASE_URL=$BASE_URL
      - OPENAI_ORG_ID=$OPENAI_ORG_ID
      - HIDE_USER_API_KEY=$HIDE_USER_API_KEY
      - DISABLE_GPT4=$DISABLE_GPT4
```
---

### Start the Service
Run the container:

```bash
docker compose --profile no-proxy build --no-cache
docker compose --profile no-proxy up
```
---
## Run the Reproduction Script

### Requirements

Install Python dependencies:

```bash
pip install requests psutil
```

---
After NextChat is running, execute the reproducer script:

```bash
python main.py
```