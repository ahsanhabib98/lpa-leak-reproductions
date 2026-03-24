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

### Run the Reproduction Script
---

```bash
chmod +x reproducer.sh && ./reproducer.sh
```

### Monitoring Log
During execution, the script records server log:

```bash
fake_server.log
```

