# Open WebUI Reranker Download Memory Leak / Lock-Up Reproducer

This guide reproduces the behavior described in GitHub Discussion **([#3047](https://github.com/open-webui/open-webui/issues/3047))**.

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

### Run the Reproduction Script
---

```bash
chmod +x reproducer.sh && ./reproducer.sh
```