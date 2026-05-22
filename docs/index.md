---
layout: home
hero:
  name: TrustRAG
  text: Trustworthy RAG Knowledge Workbench
  tagline: Upload documents. Ask questions. Trace every answer back to its source — with verifiable citations, review workflows, and a self-contained desktop app.
  actions:
    - theme: brand
      text: Download v0.2.1
      link: https://github.com/XimilalaXiang/TrustRAG/releases/latest
    - theme: alt
      text: Get Started →
      link: /guide/getting-started
    - theme: alt
      text: API Reference
      link: /api/overview
features:
  - icon: 📎
    title: Citation Tracking
    details: Every AI response includes traceable citations linked to document, chunk, page, and heading. Never trust an answer blindly — verify it.
  - icon: ✅
    title: Citation Review & Reports
    details: Approve, reject, or flag citations. Export review reports with approval rates, hallucination metrics, and review coverage statistics.
  - icon: 🖥️
    title: Multi-Platform Desktop
    details: Windows (.exe installer + portable), macOS, Linux, Android, iOS, and Web — all from a single Flutter codebase with responsive layouts.
  - icon: 📦
    title: Self-Contained Desktop
    details: Embedded SQLite + Rust backend inside the app. Native PDF parsing on desktop. No external database, no server setup.
  - icon: 🤖
    title: RAG Pipeline
    details: Document-grounded retrieval-augmented generation with configurable LLM and embedding providers. Hybrid search with vector + full-text retrieval.
  - icon: 🧠
    title: Knowledge Graph
    details: Interactive graph visualization with entity browsing and search. Color-coded nodes, relationship labels, and cross-document exploration.
  - icon: 🌐
    title: Multi-Language (i18n)
    details: Full UI localization with Chinese, English, and Japanese support. Language switching with persistent preferences.
  - icon: 📄
    title: Review Reports
    details: Generate Markdown reports with citation statistics, hallucination rate, approval rate, and detailed review records. Copy or share reports.
---

<style>
:root {
  --vp-home-hero-name-color: transparent;
  --vp-home-hero-name-background: -webkit-linear-gradient(120deg, #10b981 30%, #3b82f6);
  --vp-home-hero-image-background-image: linear-gradient(-45deg, #10b98140 50%, #3b82f640 50%);
  --vp-home-hero-image-filter: blur(44px);
}
</style>
