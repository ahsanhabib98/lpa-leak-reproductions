# Open WebUI Autocomplete External Fallback Reproducer ([v0.5.4](https://github.com/open-webui/open-webui/tree/506dc0149ca973e20768fa3d6f171afac289f606))

This guide reproduces the behavior described in GitHub Discussion **([#8829](https://github.com/open-webui/open-webui/issues/8829))**.

The discussion states that when **Autocomplete is configured to use a local model**, but that local model becomes unavailable, Open WebUI may **silently fall back to the currently selected external chat model** instead of failing. This can cause user input to be sent to a remote API unexpectedly.

---

## Purpose

This reproduction demonstrates that:

- **Autocomplete** is configured to use a **local Ollama model**.
- The active **chat model** is configured as an **external model** through OpenAI.
- When the **local model becomes unavailable**, Open WebUI still sends requests externally.
- User input may be transmitted to the external provider instead of failing locally.

This experiment verifies the **silent fallback behavior from local autocomplete to external model**.

---

## What the Reproduction Does

The reproduction performs the following actions manually:

- Runs **Open WebUI** with Docker.
- Runs **Ollama** as the local model provider.
- Configures an **external OpenAI model**.
- Sets the **task model** to use the **local model**.
- Enables **Autocomplete Generation**.
- Stops the **Ollama** container.
- Sends a prompt in chat.
- Monitors outbound traffic from the Open WebUI container to **api.openai.com**.

---

## Instructions to Reproduction

### Run the Reproduction Script
---

```bash
chmod +x reproducer.sh && ./reproducer.sh
```
