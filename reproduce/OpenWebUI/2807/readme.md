# Open WebUI Admin Chat Access / Privacy Issue Reproducer

This guide reproduces the behavior described in GitHub Discussion **#2807**.

The discussion highlights that **admin users may be able to view other users' conversations**, raising a potential privacy concern.

---

## Purpose

This reproduction demonstrates that:

- Open WebUI allows creation of multiple users (admin + normal users).
- Admin users may have access to user management features.
- Under certain versions/commits, admins may:
  - **view other users' conversations**
  - **access chat history not belonging to them**
- This behavior may represent a **privacy concern in multi-user deployments**.

---

## What the Reproduction Does

The reproduction performs the following actions manually:

- Runs **Open WebUI + Ollama** using Docker.
- Creates **admin and normal user accounts**.
- Generates identifiable chat messages from a normal user.
- Logs in as admin and attempts to access those chats.
- Verifies whether **chat data is exposed to admin users**.

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
Admin:
email: admin@example.com
password: ...........

User:
email: user@example.com
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

### Generate User Chat Data

Login as normal user:

```bash
user@example.com
```

Create multiple chats and send messages:

```bash
PRIVATE TEST CHAT 1
PRIVATE TEST CHAT 2
```
Logout after creating chats.

### Access as Admin

Login as admin:

```bash
admin@example.com
```
Navigate:

```bash
Admin Panel -> Users -> View Chats
```