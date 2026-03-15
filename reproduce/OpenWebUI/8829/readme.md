# Open WebUI Autocomplete External Fallback Reproducer

This guide reproduces the behavior described in GitHub Discussion **#8829**.

The discussion states that when **Autocomplete is configured to use a local model**, but that local model becomes unavailable, Open WebUI may **silently fall back to the currently selected external chat model** instead of failing. This can cause user input to be sent to a remote API unexpectedly.

---

## Purpose

This reproduction demonstrates that:

- **Autocomplete** is configured to use a **local Ollama model**.
- The active **chat model** is configured as an **external model** through OpenRouter.
- When the **local model becomes unavailable**, Open WebUI still sends requests externally.
- User input may be transmitted to the external provider instead of failing locally.

This experiment verifies the **silent fallback behavior from local autocomplete to external model**.

---

## What the Reproduction Does

The reproduction performs the following actions manually:

- Runs **Open WebUI** with Docker.
- Runs **Ollama** as the local model provider.
- Configures an **external OpenRouter model**.
- Sets the **task model** to use the **local model**.
- Enables **Autocomplete Generation**.
- Stops the **Ollama** container.
- Sends a prompt in chat.
- Monitors outbound traffic from the Open WebUI container to **openrouter.ai**.

---

## Instructions to Reproduction

### Run OpenWebUI with Docker

Prepare .env File

```bash
OPENAI_API_KEY=<your_openrouter_api_key>
OPENAI_API_BASE_URL=https://openrouter.ai/api/v1
```

Use this docker compose file

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
    env_file:
      - .env
    build:
      context: .
      args:
        OLLAMA_BASE_URL: '/ollama'
      dockerfile: Dockerfile
    image: ghcr.io/open-webui/open-webui:${WEBUI_DOCKER_TAG-main}
    container_name: open-webui
    volumes:
      - open-webui:/app/backend/data
    depends_on:
      - ollama
    ports:
      - ${OPEN_WEBUI_PORT-3000}:8080
    environment:
      - OLLAMA_BASE_URL=http://ollama:11434
      - WEBUI_SECRET_KEY=
    extra_hosts:
      - host.docker.internal:host-gateway
    restart: unless-stopped

volumes:
  ollama: {}
  open-webui: {}
```

Run the containers:

```bash
docker compose build --no-cache
docker compose up
```
Open the application:
```bash
http://localhost:3000
```
---
### Create a user account
```bash
name: user
email: user@example.org
password: userpassword
```
### Pull a Local Model in Ollama
Open a terminal and run:
```bash
docker exec -it ollama ollama pull llama3
```

### Configure Task Model
Open Admin Panel.

Go to:

```bash
Settings -> Interface
```
Under Set Task Model, configure:
```bash
Local Models -> Current Model: llama3
External Models -> Current Model: Current Model
```
Click Save.

### Select an External Chat Model

Open a new chat.

From the model selector, choose any external OpenRouter model, for example:
```bash
meta-llama-3-8b-instruct
```

### Stop the Local Model Provider
Open a terminal and run:
```bash
docker stop ollama
```

### Send a Test Prompt
In the Open WebUI chat box, type a unique test string such as:
```bash
TEST_AUTOCOMPLETE_FALLBACK_123456
```
Then press Send.

### Monitor Network Traffic
Open another terminal and run:
```bash
sudo tcpdump -i any host openrouter.ai
```
