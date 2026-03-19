# Open WebUI Plaintext Data Storage Reproducer ([v0.6.28](https://github.com/open-webui/open-webui/tree/171021cfa4276f63fd9fd7f31fa0c904fb13c24c))

This guide reproduces the behavior described in GitHub Issue **[#17437](https://github.com/open-webui/open-webui/issues/17437)**.

The issue states that **Open WebUI stores all persistent data as plain files inside the `data/` directory** without application-level encryption.

---

## Purpose

This reproduction demonstrates that:

- Open WebUI stores its database, uploads, cache, and vector data inside the mounted `data/` directory.
- These files are stored **in plaintext**.
- Anyone with **host filesystem access (e.g., root access)** can read the data directly.

This experiment verifies the **absence of application-level encryption at rest**.

---

## What the Script Does

- Logs in to Open WebUI as a **normal user** using email and password.
- **Uploads a document** from a specified local file path to the Open WebUI server.
- Executes a command inside the **`open-webui` Docker container**.
- **Lists files in `/app/backend/data`**, showing uploaded files and the database (`webui.db`) stored in the container.

---
## Instructions to Reproduce

## Run the Reproduction Script
---

```bash
chmod +x reproducer.sh && ./reproducer.sh
```