<div align="center">

<img src="assets/logo-200.png" alt="TrustRAG Logo" width="120" />

# TrustRAG

**可信賴的檢索增強生成知識工作台**

可驗證回答 | 精確引用 | 文件溯源審核

[English](./README.md) | [简体中文](./README_ZH.md) | 繁體中文 | [日本語](./README_JA.md)

[![版本](https://img.shields.io/github/v/release/XimilalaXiang/TrustRAG?label=版本&color=blue)](https://github.com/XimilalaXiang/TrustRAG/releases)
[![授權](https://img.shields.io/github/license/XimilalaXiang/TrustRAG?label=授權&color=green)](https://github.com/XimilalaXiang/TrustRAG/blob/master/LICENSE)
[![下載](https://img.shields.io/github/downloads/XimilalaXiang/TrustRAG/total?label=下載&color=orange)](https://github.com/XimilalaXiang/TrustRAG/releases)
[![Stars](https://img.shields.io/github/stars/XimilalaXiang/TrustRAG?style=social)](https://github.com/XimilalaXiang/TrustRAG)

</div>

<div align="center">

⬇️ **[下載](https://github.com/XimilalaXiang/TrustRAG/releases/latest)** · 📖 **[文件站](https://ximilalaxiang.github.io/TrustRAG/)** · 📋 **[更新日誌](./CHANGELOG.md)**

</div>

TrustRAG 是一個完全本機運行的多平台 RAG 知識工作台。上傳文件、提出問題，每個 AI 回答都可追溯到原始來源——文件、頁碼和章節標題。

## 🎯 核心功能

- **多平台桌面應用** — Windows（.exe 安裝包 + 便攜版）、macOS、Linux、Android、iOS、Web
- **桌面端自包含模式** — 內嵌 SQLite + Rust 後端，無需外部資料庫、無需伺服器設定
- **RAG 管線** — 基於文件的檢索增強生成，可設定 LLM 和 Embedding 提供商
- **引用追蹤** — 每條 AI 回覆都包含可追溯的引用，關聯到文件、分塊、頁碼和標題
- **引用審核** — 通過、拒絕或標記引用的準確性，支援完整審核歷史
- **全文搜尋** — 基於 FTS5 的全文件搜尋
- **知識圖譜** — 實體與關係提取，支援跨文件探索
- **工作區協作** — 多使用者工作區，基於角色的成員管理
- **伺服器模式** — 支援 PostgreSQL + pgvector、Redis、MinIO 的完整部署

## 📥 下載

| 平台 | 檔案 |
|------|------|
| Windows | `.exe` 安裝包、便攜 `.zip` |
| macOS | `.tar.gz` |
| Linux | `.tar.gz` (x64) |
| Android | `.apk` |
| iOS | `.tar.gz`（未簽名） |
| Web | `.tar.gz`（靜態檔案） |

從 [Releases](https://github.com/XimilalaXiang/TrustRAG/releases/latest) 下載。

## 🚀 快速開始

### 桌面應用（推薦）

1. 下載對應平台安裝包
2. 安裝並啟動 TrustRAG
3. 建立工作區，上傳文件，開始提問

### 伺服器模式（Docker Compose）

```bash
cp .env.example .env
cd apps/client && flutter pub get && flutter build web --dart-define=API_BASE_URL=/api && cd ../..
cd infra && docker compose up --build
```

## ⚠️ 注意事項

- **Windows**：首次啟動可能彈出 SmartScreen 警告
- **macOS**：應用未經 Apple 簽名，右鍵選擇「打開」

## 📄 授權

Apache License 2.0 — 詳見 [LICENSE](LICENSE)。

---

<div align="center">

**Made by [XimilalaXiang](https://github.com/XimilalaXiang)**

</div>
