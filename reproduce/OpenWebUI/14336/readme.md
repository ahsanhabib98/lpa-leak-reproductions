# Open WebUI Knowledge Upload Memory Leak Reproducer

This guide reproduces the behavior described in GitHub Issue **#14336**.

The issue states that **uploading large files or directories to the Knowledge feature in Open WebUI causes memory usage to continuously increase**, and memory does **not return to normal after processing**, potentially causing the system to freeze or run out of memory.

---

## Purpose

This reproduction demonstrates that:

- Uploading large documents to the **Knowledge** feature causes **continuous memory growth**.
- Memory usage increases during document processing and **remains high after upload finishes**.
- On systems with limited RAM, the **Open WebUI container or host machine may freeze or run out of memory**.

This experiment verifies the **memory leak behavior during Knowledge document ingestion**.

---

## What the Reproduction Does

The reproduction performs the following actions manually:

- Runs **Open WebUI** using Docker.
- Configures **document embedding** with a large embedding model.
- Creates a **Knowledge base**.
- Uploads a **large file (~1–2 GB)** to the Knowledge base.
- Monitors the **Open WebUI container memory usage** during ingestion.
- Confirms that memory **continues increasing and does not return to normal**.

---

## Instructions to Reproduction

### Run OpenWebUI with Docker

Run the container:

```bash
docker compose build --no-cache
docker compose up
```
Open the application:
```bash
http://localhost:3000
```
---
### Create a user account
```bash
name: user
email: user@example.org
password: userpassword
```
### Configure Embedding Settings
Open Admin Settings -> Documents.

Configure the following:
```bash
Embedding -> Embedding Model: text-embedding-3-large
Retrieval -> Hybrid Search: Enabled
```
### Prepare Large Test File
Create a large file (around 1–2 GB).
```bash
fallocate -l 2G large_test.pdf
```

### Create a Knowledge Base
Inside Open WebUI:
```bash
Workspace -> Knowledge
```
Click the + (Add) button.

Fill the fields:
```bash
Name: leak-test
Description: memory leak test
```
Click Create Knowledge.

### Prepare Large Test File

Open the created knowledge base.

Click the + (Add) button.

Choose:
```bash
Upload File
```
Select the large file:
```bash
large_test.pdf
```

### Monitor Memory Usage
Open a terminal and run:
```bash
docker stats open-webui
```

### Observed Behavior
During large file upload:
- Memory usage continuously increases
- System may become slow or freeze
- Memory does not decrease after upload completes

### Recovery
To recover memory:
```bash
docker restart open-webui
```
or
```bash
docker rm -f open-webui
```
