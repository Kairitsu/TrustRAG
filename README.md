<div align="center">

<img src="assets/logo-200.png" alt="TrustRAG Logo" width="120" />

# TrustRAG

**Trustworthy Retrieval-Augmented Generation Knowledge Workbench**

Verifiable Answers | Precise Citations | Document-Grounded Review

English | [简体中文](./README_ZH.md) | [繁體中文](./README_TW.md) | [日本語](./README_JA.md)

[![Version](https://img.shields.io/github/v/release/XimilalaXiang/TrustRAG?label=Version&color=blue)](https://github.com/XimilalaXiang/TrustRAG/releases)
[![License](https://img.shields.io/github/license/XimilalaXiang/TrustRAG?label=License&color=green)](https://github.com/XimilalaXiang/TrustRAG/blob/master/LICENSE)
[![Platform](https://img.shields.io/badge/Windows-0078D6?logo=windows&logoColor=white)](https://github.com/XimilalaXiang/TrustRAG/releases)
[![Platform](https://img.shields.io/badge/macOS-000000?logo=apple&logoColor=white)](https://github.com/XimilalaXiang/TrustRAG/releases)
[![Platform](https://img.shields.io/badge/Linux-FCC624?logo=linux&logoColor=black)](https://github.com/XimilalaXiang/TrustRAG/releases)
[![Platform](https://img.shields.io/badge/Android-3DDC84?logo=android&logoColor=white)](https://github.com/XimilalaXiang/TrustRAG/releases)
[![Platform](https://img.shields.io/badge/iOS-000000?logo=ios&logoColor=white)](https://github.com/XimilalaXiang/TrustRAG/releases)
[![Docs](https://img.shields.io/badge/Docs-VitePress-646CFF?logo=vitepress&logoColor=white)](https://ximilalaxiang.github.io/TrustRAG/)
[![Downloads](https://img.shields.io/github/downloads/XimilalaXiang/TrustRAG/total?label=Downloads&color=orange)](https://github.com/XimilalaXiang/TrustRAG/releases)
[![Stars](https://img.shields.io/github/stars/XimilalaXiang/TrustRAG?style=social)](https://github.com/XimilalaXiang/TrustRAG)
[![Ask DeepWiki](https://deepwiki.com/badge.svg)](https://deepwiki.com/XimilalaXiang/TrustRAG)

</div>

<div align="center">

⬇️ **[Download](https://github.com/XimilalaXiang/TrustRAG/releases/latest)** · 📖 **[Documentation](https://ximilalaxiang.github.io/TrustRAG/)** · 📋 **[Changelog](./CHANGELOG.md)**

</div>

TrustRAG is a self-contained, multi-platform RAG knowledge workbench that runs entirely on your device. Upload documents, ask questions, and inspect the evidence behind each AI answer — with every citation traceable to its original source, page, and heading.

## 🎯 Core Features

- **Multi-platform desktop** — Windows (.exe installer + portable), macOS, Linux, Android, iOS, Web — all from a single Flutter codebase
- **Self-contained desktop mode** — Embedded SQLite + Rust backend bundled inside the app; no external database, no server setup
- **RAG pipeline** — Document-grounded retrieval-augmented generation with configurable LLM and embedding providers
- **Citation tracking** — Every AI response includes traceable source citations linked to document, chunk, page, and heading
- **Citation review** — Approve, reject, or flag citations for accuracy with full review history
- **Full-text search** — FTS5-powered search across all uploaded documents
- **Knowledge graph** — Entity and relation extraction for cross-document exploration
- **Workspace collaboration** — Multi-user workspaces with role-based member management
- **Server mode** — Full-stack deployment with PostgreSQL + pgvector, Redis, MinIO, and Docker Compose

## 📥 Download

<div align="center">

[![Windows](https://img.shields.io/badge/Windows-Download-0078D6?style=for-the-badge&logo=windows&logoColor=white)](https://github.com/XimilalaXiang/TrustRAG/releases/latest)
[![macOS](https://img.shields.io/badge/macOS-Download-000000?style=for-the-badge&logo=apple&logoColor=white)](https://github.com/XimilalaXiang/TrustRAG/releases/latest)
[![Linux](https://img.shields.io/badge/Linux-Download-FCC624?style=for-the-badge&logo=linux&logoColor=black)](https://github.com/XimilalaXiang/TrustRAG/releases/latest)
[![Android](https://img.shields.io/badge/Android-Download-3DDC84?style=for-the-badge&logo=android&logoColor=white)](https://github.com/XimilalaXiang/TrustRAG/releases/latest)

</div>

| Platform | Files |
|----------|-------|
| Windows | `.exe` installer, portable `.zip` |
| macOS | `.tar.gz` (universal) |
| Linux | `.tar.gz` (x64) |
| Android | `.apk` |
| iOS | `.tar.gz` (unsigned) |
| Web | `.tar.gz` (static files) |

## 🏗 Architecture

TrustRAG operates in two modes:

### Desktop Mode (Self-Contained)

```text
Flutter Client (Windows / macOS / Linux / Android / iOS)
  └── HTTP/SSE
      └── Embedded Rust Backend (Axum)
          ├── Auth, workspace, document, search, chat, citation, review APIs
          ├── RAG orchestration and provider registry
          └── SQLite + FTS5 (embedded, zero config)
```

> **Note:** Desktop mode currently supports **TXT, Markdown, and HTML** documents. For PDF/DOCX parsing, please use Server Mode which includes the Python Document Processor.

### Server Mode (Full Stack)

```text
Flutter Client (Web / Desktop)
  └── HTTP/SSE
      └── Rust Backend (Axum)
          ├── Auth, workspace, document, search, chat, citation, review APIs
          ├── RAG orchestration and provider registry
          ├── PostgreSQL + pgvector / pg_trgm
          ├── Redis
          ├── MinIO / S3-compatible object storage
          └── Python Document Processor (FastAPI)
              ├── PDF parsing (PyMuPDF)
              ├── DOCX parsing (python-docx)
              ├── OCR (Tesseract)
              └── Format conversion (Pandoc)
```

## 📁 Project Structure

```text
TrustRAG/
├── apps/client/          # Flutter multi-platform client
├── backend/              # Rust Axum backend (dual-mode: postgres/desktop)
├── doc-processor/        # Python FastAPI document processing service
├── infra/                # Docker Compose, Caddy, PostgreSQL init scripts
├── scripts/              # Release notes generator
├── docs/                 # Product docs, API docs, roadmap
├── CHANGELOG.md          # Release changelog
└── .github/workflows/    # CI/CD: ci.yml, test-build.yml, release.yml
```

## 🔧 Tech Stack

| Layer | Technology |
|-------|------------|
| Client | Flutter, Dart, Riverpod, go_router, dio |
| Backend | Rust, Axum, tokio, SQLx, JWT, argon2, tracing |
| Document processor | Python, FastAPI, PyMuPDF, python-docx, pytesseract |
| Desktop data | SQLite + FTS5 |
| Server data | PostgreSQL 16, pgvector, pg_trgm, Redis 7, MinIO |
| CI/CD | GitHub Actions (ci + test-build + release) |

## 🚀 Quick Start

### Desktop App (Recommended)

1. Download the installer for your platform from [Releases](https://github.com/XimilalaXiang/TrustRAG/releases/latest)
2. Install and launch TrustRAG
3. Create a workspace, upload documents, start asking questions

### Server Mode (Docker Compose)

```bash
cp .env.example .env
cd apps/client && flutter pub get && flutter build web --dart-define=API_BASE_URL=/api && cd ../..
cd infra && docker compose up --build
```

Open <http://localhost> to access the web app.

### Development

```bash
# Backend
cd backend && cargo run

# Flutter client
cd apps/client && flutter run -d chrome --dart-define=API_BASE_URL=http://localhost:8080

# Document processor
cd doc-processor && pip install -r requirements.txt && uvicorn app.main:app --port 8081 --reload
```

## ⚠️ Notes

- **Windows**: May show SmartScreen warning on first launch — click **More info** → **Run anyway**
- **macOS**: App is unsigned — right-click and select "Open", or allow in System Settings > Privacy & Security
- **Desktop mode**: Uses SQLite with FTS5 for search; no external database needed
- **Server mode**: Requires Docker, PostgreSQL, Redis, and MinIO

## 📄 License

Apache License 2.0 — see [LICENSE](LICENSE).

## 🙏 Acknowledgments

- [LINUX.DO](https://linux.do) community

---

<div align="center">

**Made by [XimilalaXiang](https://github.com/XimilalaXiang)**

</div>
