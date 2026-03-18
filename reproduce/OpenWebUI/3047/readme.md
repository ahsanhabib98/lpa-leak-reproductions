# Open WebUI Reranker Download Memory Leak / Lock-Up Reproducer

This guide reproduces the behavior described in GitHub Discussion **#3047**.

The issue states that **downloading a reranker model (`BAAI/bge-reranker-v2-m3`) via the Hybrid Search settings can cause Open WebUI to consume excessive memory and potentially lock up**, especially when the model is not properly supported.

---

## Purpose

This reproduction demonstrates that:

- Enabling **Hybrid Search** and selecting a reranker model triggers a model download.
- Attempting to download **`BAAI/bge-reranker-v2-m3`** can cause abnormal behavior.
- The system may exhibit:
  - **rapid or sustained memory growth**
  - **UI slowdown or freeze**
  - **incomplete or stuck model download**
- This behavior may result in **container instability or lock-up**.

---

## What the Reproduction Does

The reproduction performs the following actions manually:

- Runs **Open WebUI + Ollama** using Docker.
- Enables **Hybrid Search** in settings.
- Sets an unsupported or problematic reranker model.
- Triggers the **Download / Pull** operation.
- Monitors system memory usage.
- Observes **memory spike and UI instability**.

---

## Instructions to Reproduce

### Run OpenWebUI with Docker

Create and start the environment:

```bash
mkdir openwebui
cd openwebui
```

Create docker-compose.yml:

```bash
services:
  ollama:
    image: ollama/ollama:0.1.42
    container_name: ollama
    restart: unless-stopped
    tty: true
    ports:
      - "11434:11434"
    volumes:
      - ollama:/root/.ollama

  open-webui:
    image: ghcr.io/open-webui/open-webui:v0.3.2
    container_name: open-webui
    restart: unless-stopped
    depends_on:
      - ollama
    ports:
      - "3000:8080"
    environment:
      - OLLAMA_BASE_URL=http://ollama:11434
    volumes:
      - open-webui:/app/backend/data

volumes:
  ollama: {}
  open-webui: {}
```

Start containers:
```bash
docker compose up
```

Open the application:
```bash
http://localhost:3000
```

### Create User Account

Register a user via the UI:

```bash
email: admin@example.com
password: ...........
```

### Monitor System

Open a terminal to monitor memory:

```bash
docker stats
```

### Enable Hybrid Search

In Open WebUI:
```bash
Settings -> Admin Settings -> Documents
```

Turn ON:
```bash
Hybrid Search
```

### Set Reranker Model

Enter: 
```bash
BAAI/bge-reranker-v2-m3
```

Trigger Download

```bash
Download / Pull
```

Keep monitoring:

```bash
docker stats
```
