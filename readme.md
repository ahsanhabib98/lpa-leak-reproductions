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
| [NextChat](https://github.com/ChatGPTNextWeb/NextChat/tree/38bffd423c7e2fd0210ecb768a33785c97ab2961) | [1598](https://github.com/ChatGPTNextWeb/NextChat/issues/1598) | [reproduce](./reproduce/NextChat/1598/) |


---

## Disclaimer

This repository is for **research and educational purposes only**.