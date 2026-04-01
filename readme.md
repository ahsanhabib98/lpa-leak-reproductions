# LPA Leaks

A collection of **leak issues found in open-source LLM powered applications (LPAs)**.

This repository documents cases where applications that use Large Language Models show problems such as memory leaks or information leaks.

The goal of this repository is to help developers and researchers understand these problems and reproduce them easily.

## What this repository contains

Each entry in the table includes:

- **LPA Name** – The open-source LLM powered application where the issue exists  
- **Issue Link** – Link to the original issue reported in the project repository  
- **Reproduce** – A folder in this repository that contains code or instructions to reproduce the issue

---

## Leak Catalog

| LPA Leak Code | Issue Link | Reproduce |
|---------------|------------|-----------|
| [OpenWebUI](https://github.com/open-webui/open-webui/tree/171021cfa4276f63fd9fd7f31fa0c904fb13c24c) | [17437](https://github.com/open-webui/open-webui/issues/17437) | [reproduce](./reproduce/OpenWebUI/17437/) |
| [OpenWebUI](https://github.com/open-webui/open-webui/tree/e6afa69f59295d2930ff57285d0933e207d8e4c3) | [14336](https://github.com/open-webui/open-webui/issues/14336) | [reproduce](./reproduce/OpenWebUI/14336/) |
| [OpenWebUI](https://github.com/open-webui/open-webui/tree/07d8460126a686de9a99e2662d06106e22c3f6b6) | [13482](https://github.com/open-webui/open-webui/discussions/13482) | [reproduce](./reproduce/OpenWebUI/13482/) |
| [OpenWebUI](https://github.com/open-webui/open-webui/tree/506dc0149ca973e20768fa3d6f171afac289f606) | [8829](https://github.com/open-webui/open-webui/discussions/8829) | [reproduce](./reproduce/OpenWebUI/8829/) |
| [OpenWebUI](https://github.com/open-webui/open-webui/tree/c4ea31357f49d08a14c86b2bd85fdcd489512e91) | [7160](https://github.com/open-webui/open-webui/discussions/7160) | [reproduce](./reproduce/OpenWebUI/7160/) |
| [OpenWebUI](https://github.com/open-webui/open-webui/tree/c869652ef4907dd123a140d9a08a0c239e690b08) | [4601](https://github.com/open-webui/open-webui/issues/4601) | [reproduce](./reproduce/OpenWebUI/4601/) |
| [OpenWebUI](https://github.com/open-webui/open-webui/tree/3933db2c91e635da52a28a9e7e2927f551b2fee6) | [3047](https://github.com/open-webui/open-webui/discussions/3047) | [reproduce](./reproduce/OpenWebUI/3047/) |
| [OpenWebUI](https://github.com/open-webui/open-webui/tree/f28877f4db2a136f26c495e033f1d2b4ea1b405c) | [2807](https://github.com/open-webui/open-webui/discussions/2807) | [reproduce](./reproduce/OpenWebUI/2807/) |
| [MetaGPT](https://github.com/FoundationAgents/MetaGPT/tree/ab77bde54cca20d7176e968c994331d1a7fefa3e) | [868](https://github.com/FoundationAgents/MetaGPT/issues/868) | [reproduce](./reproduce/OpenWebUI/868/) |


---

## Disclaimer

This repository is for **research and educational purposes only**.