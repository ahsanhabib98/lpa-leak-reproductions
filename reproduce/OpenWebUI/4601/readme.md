# Open WebUI Cross-User File Leakage Reproducer ([v0.3.12](https://github.com/open-webui/open-webui/tree/c869652ef4907dd123a140d9a08a0c239e690b08))

This guide reproduces the behavior described in GitHub Issue **([#4601](https://github.com/open-webui/open-webui/issues/4601))**.

The issue states that **when a user uploads an empty file (no extractable content), Open WebUI may return a previously uploaded file from another user**, resulting in **cross-user data leakage**.

---

## Purpose

This reproduction demonstrates that:

- Uploading an **empty document** triggers a backend error.
- Instead of returning no data, the system **reuses a previously processed document**.
- This leads to **data from one user being exposed to another user**.
- This behavior represents a **serious security vulnerability in multi-user environments**.

---

## What the Reproduction Does

The reproduction performs the following actions manually:

- Runs **Open WebUI** using Docker.
- Uses **multiple users** in the same instance.
- Uploads a **valid document (User1)**.
- Uploads an **empty document (User2)**.
- Queries both documents via chat.
- Observes that **User2 receives User1’s document content**.

---

## Instructions to Reproduce

### Run the Reproduction Script
---

```bash
chmod +x reproducer.sh && ./reproducer.sh
```