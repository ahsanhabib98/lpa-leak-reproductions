# Open WebUI LDAP Authentication Password Storage Reproducer ([v0.4.7](https://github.com/open-webui/open-webui/tree/c4ea31357f49d08a14c86b2bd85fdcd489512e91))

This guide reproduces the behavior described in GitHub Issue **([#7160](https://github.com/open-webui/open-webui/issues/7160))**.

The issue states that **LDAP authentication stores a password value in the local Open WebUI database (`auth.password`) for LDAP users**, which should not happen. LDAP authentication should rely on the external directory and **not persist any password locally**.

---

## Purpose

This reproduction demonstrates that:

- Open WebUI successfully authenticates a user using **LDAP credentials**.
- After authentication, Open WebUI **creates a local user entry**.
- A value is stored in the **`auth.password` field** for the LDAP user.
- This confirms that **LDAP users still receive a locally stored password entry**, which contradicts the expected behavior described in the issue.

---

## What the Reproduction Does

The reproduction performs the following actions:

- Runs **Open WebUI v0.4.7** using Docker.
- Starts a local **OpenLDAP server**.
- Creates an **LDAP user account**.
- Logs in to Open WebUI using **LDAP authentication**.
- Queries the **Open WebUI SQLite database**.
- Confirms that the LDAP user appears in the `auth` table with a stored password value.

---

## Instructions to Reproduce

### Run the Reproduction Script
---

```bash
chmod +x reproducer.sh && ./reproducer.sh
```