# Open WebUI Memory Sharing to External Provider Reproducer

This guide reproduces the behavior described in GitHub Discussion **#13482**.

The discussion states that **Open WebUI automatically injects user memories into prompts sent to models**, including **external providers** (e.g., OpenAI, OpenRouter).

---

## Purpose

This reproduction demonstrates that:

- Open WebUI allows users to store **personal memories**.
- When a request is sent to an **external OpenAI-compatible endpoint**, these memories are **automatically injected into the prompt**.
- The injected memory is visible in the outbound request payload.
- Open WebUI currently **does not provide a per-connection control to disable memory sharing**.

This experiment verifies that **user memory can be transmitted to external providers**.

---

## What the Script Does

The reproduction environment uses a **fake OpenAI-compatible server** to capture outbound requests from Open WebUI.

The script:

- Starts a **fake OpenAI API server**.
- Logs every request received at `/v1/chat/completions`.
- Prints the full JSON payload sent by Open WebUI.
- Shows that **saved user memory appears inside the system prompt**.

---

## Instructions to Reproduce

### Run OpenWebUI with Docker

Create .env file:
```env
OPENAI_API_KEY=sk-test
OPENAI_API_BASE_URL=http://host.docker.internal:8000/v1
```

Use this compose file:
```bash
services:
  ollama:
    volumes:
      - ollama:/root/.ollama
    container_name: ollama
    pull_policy: always
    tty: true
    restart: unless-stopped
    image: ollama/ollama:${OLLAMA_DOCKER_TAG-latest}

  open-webui:
    build:
      context: .
      args:
        OLLAMA_BASE_URL: "/ollama"
      dockerfile: Dockerfile
    image: ghcr.io/open-webui/open-webui:${WEBUI_DOCKER_TAG-main}
    container_name: open-webui
    volumes:
      - open-webui:/app/backend/data
    depends_on:
      - ollama
    ports:
      - "${OPEN_WEBUI_PORT-3000}:8080"
    environment:
      - OLLAMA_BASE_URL=http://ollama:11434
      - WEBUI_SECRET_KEY=
      - OPENAI_API_KEY=sk-test
      - OPENAI_API_BASE_URL=http://host.docker.internal:8000/v1
    extra_hosts:
      - "host.docker.internal:host-gateway"
    restart: unless-stopped

volumes:
  ollama: {}
  open-webui: {}
```

Run the container:

```bash
docker compose build --no-cache
docker compose up
```

### Start the fake OpenAI-compatible server on the host
```bash
pip install fastapi uvicorn
python main.py
```

### Open OpenWebUI

Go to:

```bash
http://localhost:3000
```
Create/login to your account.

### Enable memory

In Open WebUI:
```bash
go to Settings -> Personalization -> turn Memory ON -> click Save
```

Add this memory:
```bash
MY_SECRET_TEST_13482
```

### Start a new chat with the external model

Create a new chat and select:
```bash
gpt-4o
```

Send a test prompt
```bash
what do you know about me?
```

### Expected result

The fake server logs a request like this:
```bash
{
  "stream": true,
  "model": "gpt-4o",
  "messages": [
    {
      "role": "system",
      "content": "\n\nUser Context:\n1. [2026-03-13]. MY_SECRET_TEST_13482\n"
    },
    {
      "role": "user",
      "content": "what do you know about me?"
    }
  ]
}
```