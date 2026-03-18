# Open WebUI Cross-User File Leakage Reproducer

This guide reproduces the behavior described in GitHub Issue **#4601**.

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

### Run OpenWebUI with Docker

```bash
docker compose build
docker compose up
```
Open the application:

```bash
http://localhost:3000
```

### Create User Accounts

Create two users via the UI:

```bash
User1:
email: user1@example.com
password: ...........

User2:
email: user2@example.com
password: ...........
```

### Setup Ollama Model

Pull a model inside the container:

```bash
docker exec -it ollama ollama pull llama3.2:latest
```

Verify:

```bash
docker exec -it ollama ollama list
```

### Prepare Test Files

Create a file with content:

```bash
with_contents.docx
```

Create an empty file:

```bash
empty.docx
```

### User1 Upload (Valid File)

Login as User1:

```bash
Start a new chat
Upload with_contents.docx
```
Ask:

```bash
What is inside the file?
```

### User2 Upload (Empty File)

Login as User2:

```bash
Start a new chat
Upload empty.docx
```
Ask:

```bash
What is inside the file?
```

### Observed Behavior

👉 User2 receives User1’s file content