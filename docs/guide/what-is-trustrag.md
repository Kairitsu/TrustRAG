# What is TrustRAG?

TrustRAG is a self-contained, multi-platform RAG (Retrieval-Augmented Generation) knowledge workbench. It helps you build a private knowledge base, upload documents, ask questions, and — most importantly — inspect the evidence behind each AI answer.

## Why TrustRAG?

Most RAG systems give you an AI-generated answer and maybe a list of "sources." TrustRAG goes further:

- **Every citation is traceable** — linked to a specific document, chunk, page number, and heading path
- **Citations are reviewable** — approve, reject, or flag each citation for accuracy
- **Review history is preserved** — full audit trail for accountability

## Two Modes

### Desktop Mode (Self-Contained)

Download and run. No servers, no databases to configure. TrustRAG bundles a Rust backend and SQLite database inside the app. Available on Windows, macOS, Linux, Android, and iOS.

### Server Mode (Full Stack)

For teams that need PostgreSQL vector search, Redis caching, and MinIO file storage. Deploy with Docker Compose.

## Key Features

| Feature | Description |
|---------|-------------|
| RAG Chat | Document-grounded Q&A with streaming responses |
| Citation Tracking | Every answer cites specific document chunks |
| Citation Review | Approve/reject/flag citations with full audit trail |
| Review Reports | Export Markdown reports with hallucination rate, approval rate, review coverage |
| Knowledge Graph | Interactive visualization with entity browsing, search, and color-coded graph |
| Full-Text Search | FTS5-powered search across all documents |
| Native PDF Parsing | Desktop builds parse PDF locally via Rust `lopdf` (no server needed) |
| Multi-Language (i18n) | Chinese, English, Japanese, Korean UI with persistent language preference |
| Team Collaboration | Personal & team workspaces, invite codes, role-based access (owner/admin/editor/viewer) |
| Resizable Sidebar | Drag to resize, one-click collapse to icon-only mode, persisted preferences |
| Multi-Platform | Windows, macOS, Linux, Android, iOS, Web |
