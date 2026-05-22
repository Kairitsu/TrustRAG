<div align="center">

<img src="assets/banner.png" alt="TrustRAG Banner" width="800" />

# TrustRAG

**信頼できる検索拡張生成ナレッジワークベンチ**

検証可能な回答 | 正確な引用 | ドキュメントに基づくレビュー

[English](./README.md) | [简体中文](./README_ZH.md) | [繁體中文](./README_TW.md) | 日本語

[![バージョン](https://img.shields.io/github/v/release/XimilalaXiang/TrustRAG?label=バージョン&color=blue)](https://github.com/XimilalaXiang/TrustRAG/releases)
[![ライセンス](https://img.shields.io/github/license/XimilalaXiang/TrustRAG?label=ライセンス&color=green)](https://github.com/XimilalaXiang/TrustRAG/blob/master/LICENSE)
[![ダウンロード](https://img.shields.io/github/downloads/XimilalaXiang/TrustRAG/total?label=ダウンロード&color=orange)](https://github.com/XimilalaXiang/TrustRAG/releases)
[![Stars](https://img.shields.io/github/stars/XimilalaXiang/TrustRAG?style=social)](https://github.com/XimilalaXiang/TrustRAG)

</div>

<div align="center">

⬇️ **[ダウンロード](https://github.com/XimilalaXiang/TrustRAG/releases/latest)** · 📖 **[ドキュメント](https://ximilalaxiang.github.io/TrustRAG/)** · 📋 **[変更履歴](./CHANGELOG.md)**

</div>

TrustRAG は完全にローカルで動作するマルチプラットフォーム RAG ナレッジワークベンチです。ドキュメントをアップロードし、質問すると、AI の回答はすべて元のソース（ドキュメント、ページ、見出し）まで追跡できます。

## 🎯 主な機能

- **マルチプラットフォーム** — Windows、macOS、Linux、Android、iOS、Web
- **自己完結型デスクトップ** — SQLite + Rust バックエンド内蔵、外部データベース不要
- **RAG パイプライン** — ドキュメントに基づく検索拡張生成
- **引用追跡** — すべての AI 回答にトレーサブルな引用を付与
- **引用レビュー** — 引用の承認・拒否・フラグ付けに対応
- **全文検索** — FTS5 による全ドキュメント検索
- **ナレッジグラフ** — エンティティと関係の抽出
- **ワークスペース** — マルチユーザーでのコラボレーション

## 📥 ダウンロード

| プラットフォーム | ファイル |
|----------------|---------|
| Windows | `.exe` インストーラー、ポータブル `.zip` |
| macOS | `.tar.gz` |
| Linux | `.tar.gz` (x64) |
| Android | `.apk` |
| iOS | `.tar.gz`（未署名） |
| Web | `.tar.gz`（静的ファイル） |

[Releases](https://github.com/XimilalaXiang/TrustRAG/releases/latest) からダウンロードしてください。

## 🚀 クイックスタート

### デスクトップアプリ（推奨）

1. プラットフォームに対応するインストーラーをダウンロード
2. TrustRAG をインストールして起動
3. ワークスペースを作成し、ドキュメントをアップロードして質問開始

### サーバーモード（Docker Compose）

```bash
cp .env.example .env
cd apps/client && flutter pub get && flutter build web --dart-define=API_BASE_URL=/api && cd ../..
cd infra && docker compose up --build
```

## ⚠️ 注意事項

- **Windows**: 初回起動時に SmartScreen 警告が表示される場合があります
- **macOS**: Apple 署名なし — 右クリックで「開く」を選択してください

## 📄 ライセンス

Apache License 2.0 — [LICENSE](LICENSE) を参照。

---

<div align="center">

**Made by [XimilalaXiang](https://github.com/XimilalaXiang)**

</div>
