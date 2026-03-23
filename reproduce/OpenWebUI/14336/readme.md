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

### Preparing Test File

To reproduce the issue, prepare a large file (~2 GB). You can use any file type.

### Configuration

Before running the script, update the openai api key and file path in `reproducer.sh`:

```bash
OPENAI_API_KEY="sk-xxxx"
TEST_FILE="./test_file.zip"
```

### Run the Reproduction Script
---

```bash
chmod +x reproducer.sh && ./reproducer.sh
```

### Monitoring Memory Usage
During execution, the script records container memory usage in:

```bash
memory_log.csv
```

