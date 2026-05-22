<div align="center">

<img src="assets/logo-200.png" alt="TrustRAG Logo" width="120" />

# TrustRAG

**可信赖的检索增强生成知识工作台**

可验证回答 | 精确引用 | 文档溯源审核

[English](./README.md) | 简体中文 | [繁體中文](./README_TW.md) | [日本語](./README_JA.md)

[![版本](https://img.shields.io/github/v/release/XimilalaXiang/TrustRAG?label=版本&color=blue)](https://github.com/XimilalaXiang/TrustRAG/releases)
[![许可证](https://img.shields.io/github/license/XimilalaXiang/TrustRAG?label=许可证&color=green)](https://github.com/XimilalaXiang/TrustRAG/blob/master/LICENSE)
[![下载](https://img.shields.io/github/downloads/XimilalaXiang/TrustRAG/total?label=下载&color=orange)](https://github.com/XimilalaXiang/TrustRAG/releases)
[![Stars](https://img.shields.io/github/stars/XimilalaXiang/TrustRAG?style=social)](https://github.com/XimilalaXiang/TrustRAG)
[![Ask DeepWiki](https://deepwiki.com/badge.svg)](https://deepwiki.com/XimilalaXiang/TrustRAG)

</div>

<div align="center">

⬇️ **[下载](https://github.com/XimilalaXiang/TrustRAG/releases/latest)** · 📖 **[文档站](https://ximilalaxiang.github.io/TrustRAG/zh/)** · 📋 **[更新日志](./CHANGELOG.md)**

</div>

TrustRAG 是一个完全本地运行的多平台 RAG 知识工作台。上传文档、提出问题，每个 AI 回答都可追溯到原始来源——文档、页码和章节标题。

## 🎯 核心功能

- **多平台桌面应用** — Windows（.exe 安装包 + 便携版）、macOS、Linux、Android、iOS、Web，全平台一套 Flutter 代码
- **桌面端自包含模式** — 内嵌 SQLite + Rust 后端，无需外部数据库、无需服务器配置
- **RAG 管线** — 基于文档的检索增强生成，可配置 LLM 和 Embedding 提供商
- **引用追踪** — 每条 AI 回复都包含可追溯的引用，关联到文档、分块、页码和标题
- **引用审核** — 通过、拒绝或标记引用的准确性，支持完整审核历史
- **全文搜索** — 基于 FTS5 的全文档搜索
- **知识图谱** — 实体与关系提取，支持跨文档探索
- **工作区协作** — 多用户工作区，基于角色的成员管理
- **服务器模式** — 支持 PostgreSQL + pgvector、Redis、MinIO 的完整部署

## 📥 下载

<div align="center">

[![Windows](https://img.shields.io/badge/Windows-下载-0078D6?style=for-the-badge&logo=windows&logoColor=white)](https://github.com/XimilalaXiang/TrustRAG/releases/latest)
[![macOS](https://img.shields.io/badge/macOS-下载-000000?style=for-the-badge&logo=apple&logoColor=white)](https://github.com/XimilalaXiang/TrustRAG/releases/latest)
[![Linux](https://img.shields.io/badge/Linux-下载-FCC624?style=for-the-badge&logo=linux&logoColor=black)](https://github.com/XimilalaXiang/TrustRAG/releases/latest)
[![Android](https://img.shields.io/badge/Android-下载-3DDC84?style=for-the-badge&logo=android&logoColor=white)](https://github.com/XimilalaXiang/TrustRAG/releases/latest)

</div>

| 平台 | 文件 |
|------|------|
| Windows | `.exe` 安装包、便携 `.zip` |
| macOS | `.tar.gz` |
| Linux | `.tar.gz` (x64) |
| Android | `.apk` |
| iOS | `.tar.gz`（未签名） |
| Web | `.tar.gz`（静态文件） |

## 🏗 架构

TrustRAG 支持两种运行模式：

### 桌面模式（自包含）

```text
Flutter 客户端 (Windows / macOS / Linux / Android / iOS)
  └── HTTP/SSE
      └── 内嵌 Rust 后端 (Axum)
          ├── 认证、工作区、文档、搜索、聊天、引用、审核 API
          ├── RAG 编排与 Provider 管理
          └── SQLite + FTS5（内嵌，零配置）
```

> **注意：** 桌面模式目前支持 **TXT、Markdown、HTML** 格式文档。如需解析 PDF/DOCX，请使用服务器模式（包含 Python 文档处理器）。

### 服务器模式（完整部署）

```text
Flutter 客户端 (Web / Desktop)
  └── HTTP/SSE
      └── Rust 后端 (Axum)
          ├── 认证、工作区、文档、搜索、聊天、引用、审核 API
          ├── RAG 编排与 Provider 管理
          ├── PostgreSQL + pgvector / pg_trgm
          ├── Redis
          ├── MinIO / S3 兼容对象存储
          └── Python 文档处理服务 (FastAPI)
```

## 📁 项目结构

```text
TrustRAG/
├── apps/client/          # Flutter 多平台客户端
├── backend/              # Rust Axum 后端（双模式：postgres/desktop）
├── doc-processor/        # Python FastAPI 文档处理服务
├── infra/                # Docker Compose、Caddy、PostgreSQL 初始化
├── scripts/              # Release Notes 生成脚本
├── docs/                 # 产品文档、API 文档、路线图
├── CHANGELOG.md          # 版本更新日志
└── .github/workflows/    # CI/CD: ci.yml, test-build.yml, release.yml
```

## 🔧 技术栈

| 层级 | 技术 |
|------|------|
| 客户端 | Flutter、Dart、Riverpod、go_router、dio |
| 后端 | Rust、Axum、tokio、SQLx、JWT、argon2、tracing |
| 文档处理 | Python、FastAPI、PyMuPDF、python-docx、pytesseract |
| 桌面数据 | SQLite + FTS5 |
| 服务器数据 | PostgreSQL 16、pgvector、pg_trgm、Redis 7、MinIO |
| CI/CD | GitHub Actions（ci + test-build + release） |

## 🚀 快速开始

### 桌面应用（推荐）

1. 从 [Releases](https://github.com/XimilalaXiang/TrustRAG/releases/latest) 下载对应平台安装包
2. 安装并启动 TrustRAG
3. 创建工作区，上传文档，开始提问

### 服务器模式（Docker Compose）

```bash
cp .env.example .env
cd apps/client && flutter pub get && flutter build web --dart-define=API_BASE_URL=/api && cd ../..
cd infra && docker compose up --build
```

访问 <http://localhost> 使用 Web 应用。

### 开发环境

```bash
# 后端
cd backend && cargo run

# Flutter 客户端
cd apps/client && flutter run -d chrome --dart-define=API_BASE_URL=http://localhost:8080

# 文档处理服务
cd doc-processor && pip install -r requirements.txt && uvicorn app.main:app --port 8081 --reload
```

## ⚠️ 注意事项

- **Windows**：首次启动可能弹出 SmartScreen 警告，点击「更多信息」→「仍要运行」
- **macOS**：应用未经 Apple 签名，右键选择「打开」，或在「系统设置 > 隐私与安全性」中允许运行
- **桌面模式**：使用 SQLite + FTS5 搜索，无需外部数据库
- **服务器模式**：需要 Docker、PostgreSQL、Redis 和 MinIO

## 📄 许可证

Apache License 2.0 — 详见 [LICENSE](LICENSE)。

---

<div align="center">

**Made by [XimilalaXiang](https://github.com/XimilalaXiang)**

</div>
