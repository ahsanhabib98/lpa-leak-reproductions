# MetaGPT Pandas `df.copy()` Memory Leak Reproducer ([v0.6.6](https://github.com/FoundationAgents/MetaGPT/tree/ab77bde54cca20d7176e968c994331d1a7fefa3e))

This guide reproduces the behavior described in GitHub Issue **([#868](https://github.com/FoundationAgents/MetaGPT/issues/868))**.

The issue states that **`pd.DataFrame.copy()` in pandas 2.0.3 causes gradual memory growth**, and when used repeatedly (as in MetaGPT workflows), memory usage **continuously increases and is not released**, potentially leading to **OOM or system crash**.

---

## Purpose

This reproduction demonstrates that:

- MetaGPT v0.6.6 uses **pandas 2.0.3** (affected version).
- Repeated calls to **`df.copy()` cause memory usage to increase over time**.
- Memory usage **does not stabilize or return to normal**.
- Long-running processes may lead to **container OOM or system freeze**.

This experiment verifies the **memory leak behavior caused by pandas within MetaGPT environment**.

---

## What the Reproduction Does

The reproduction performs the following actions:

- Clones MetaGPT repository.
- Checks out a **vulnerable commit**.
- Runs MetaGPT inside a Docker container.
- Executes a Python script that repeatedly calls `df.copy()`.
- Monitors container memory usage in real time.
- Confirms **continuous memory growth**.

---

## Instructions to Reproduce

### Run the Reproducer Script

```bash
chmod +x reproducer.sh && ./reproducer.sh