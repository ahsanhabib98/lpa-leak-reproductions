# Open WebUI LDAP Authentication Password Storage Reproducer

This guide reproduces the behavior described in GitHub Issue **#7160**.

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

### Run OpenWebUI with Docker

Use this .env file

```bash
OPEN_WEBUI_PORT=3000
WEBUI_DOCKER_TAG=v0.4.7
OLLAMA_DOCKER_TAG=latest

WEBUI_SECRET_KEY=
ENABLE_PERSISTENT_CONFIG=False

ENABLE_SIGNUP=True
ENABLE_LDAP=True

LDAP_ORGANISATION="Example Inc"
LDAP_DOMAIN=example.org
LDAP_ADMIN_PASSWORD=admin
LDAP_TLS=false

LDAP_SERVER_LABEL=OpenLDAP
LDAP_SERVER_HOST=ldap
LDAP_SERVER_PORT=389
LDAP_USE_TLS=False
LDAP_VALIDATE_CERT=False
LDAP_APP_DN=cn=admin,dc=example,dc=org
LDAP_APP_PASSWORD=admin
LDAP_SEARCH_BASE=ou=users,dc=example,dc=org
LDAP_ATTRIBUTE_FOR_USERNAME=uid
LDAP_ATTRIBUTE_FOR_MAIL=mail
```

Use this docker compose file

```bash
services:
  ldap:
    image: osixia/openldap:1.5.0
    container_name: ldap
    environment:
      LDAP_ORGANISATION: ${LDAP_ORGANISATION}
      LDAP_DOMAIN: ${LDAP_DOMAIN}
      LDAP_ADMIN_PASSWORD: ${LDAP_ADMIN_PASSWORD}
      LDAP_TLS: ${LDAP_TLS}
    ports:
      - "389:389"

  ollama:
    image: ollama/ollama:${OLLAMA_DOCKER_TAG}
    container_name: ollama
    volumes:
      - ollama:/root/.ollama

  open-webui:
    image: ghcr.io/open-webui/open-webui:${WEBUI_DOCKER_TAG}
    container_name: open-webui
    depends_on:
      - ollama
      - ldap
    ports:
      - "${OPEN_WEBUI_PORT}:8080"
    volumes:
      - open-webui:/app/backend/data
    environment:
      - OLLAMA_BASE_URL=http://ollama:11434
      - WEBUI_SECRET_KEY=${WEBUI_SECRET_KEY}
      - ENABLE_PERSISTENT_CONFIG=${ENABLE_PERSISTENT_CONFIG}
      - ENABLE_SIGNUP=${ENABLE_SIGNUP}
      - ENABLE_LDAP=${ENABLE_LDAP}
      - LDAP_SERVER_LABEL=${LDAP_SERVER_LABEL}
      - LDAP_SERVER_HOST=${LDAP_SERVER_HOST}
      - LDAP_SERVER_PORT=${LDAP_SERVER_PORT}
      - LDAP_USE_TLS=${LDAP_USE_TLS}
      - LDAP_VALIDATE_CERT=${LDAP_VALIDATE_CERT}
      - LDAP_APP_DN=${LDAP_APP_DN}
      - LDAP_APP_PASSWORD=${LDAP_APP_PASSWORD}
      - LDAP_SEARCH_BASE=${LDAP_SEARCH_BASE}
      - LDAP_ATTRIBUTE_FOR_USERNAME=${LDAP_ATTRIBUTE_FOR_USERNAME}
      - LDAP_ATTRIBUTE_FOR_MAIL=${LDAP_ATTRIBUTE_FOR_MAIL}

volumes:
  ollama: {}
  open-webui: {}
```

Start the containers:

```bash
docker compose up
```

### Run the Reproduction Script
---
After OpenWebUI is running, execute the reproducer script:

```bash
python main.py
```