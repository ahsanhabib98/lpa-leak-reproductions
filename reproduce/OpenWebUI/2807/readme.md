# Open WebUI Admin Chat Access / Privacy Issue Reproducer ([v0.2.4](https://github.com/open-webui/open-webui/tree/f28877f4db2a136f26c495e033f1d2b4ea1b405c))

This guide reproduces the behavior described in GitHub Discussion **([#2807](https://github.com/open-webui/open-webui/issues/2807))**.

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

### Run the Reproduction Script
---

```bash
chmod +x reproducer.sh && ./reproducer.sh
```