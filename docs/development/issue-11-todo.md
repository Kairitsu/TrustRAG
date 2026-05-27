# Issue #11 — Embedding 批处理限制修复 & 登录状态持久化

> **Issue**: https://github.com/XimilalaXiang/TrustRAG/issues/11
> **Branch**: `fix/issue-11-embedding-batch-login`
> **Created**: 2026-05-27

---

## Task List

### P0: Embedding batch_size 可配置 + 自动分批

- [x] **P0.1** `embedding.rs` — `OpenAIEmbeddingProvider` 新增 `batch_size` 字段和 `with_batch_size()` 构造函数，`embed_texts()` 使用 `self.batch_size` 替代硬编码 100
- [x] **P0.2** DB migration `0018_embedding_batch_size.sql` — `embedding_configs` 表新增 `batch_size INTEGER DEFAULT 10` 列
- [x] **P0.3** `embedding_configs.rs` API — create/update/reload/test 接口全部支持 `batch_size` 字段
- [x] **P0.4** 前端 `EmbeddingConfig` model 新增 `batchSize` 字段
- [x] **P0.5** 前端模型配置页新增 "批处理大小" 输入框（默认 10，范围 1–2048）
- [x] **P0.6** 测试：241 个单元测试全部通过，包含新增的 `test_provider_with_custom_batch_size`

### P1: Embedding 失败状态细分

- [x] **P1.1** `document.rs` — embedding 阶段失败时状态设为 `embedding_failed`（通过 `[embedding]` 前缀检测）
- [x] **P1.2** DB: PostgreSQL migration 和 SQLite init.sql 均添加 `embedding_failed` 到 CHECK 约束
- [x] **P1.3** 测试：编译通过，241 个测试 OK

### P3: 登录状态持久化

- [x] **P3.1** `users.rs` — JWT 过期时间从 24 小时延长至 168 小时（7 天）
- [x] **P3.2** 前端已有 `SharedPreferences` token 持久化，确认正常工作
- [x] **P3.3** 验证：token 过期从 1 天延长到 7 天，用户无需每天重新登录

---

## Progress Log

| Date | Task | Status | Notes |
|------|------|--------|-------|
| 2026-05-27 | P0.1-P0.6 | Done | batch_size 从硬编码 100 改为可配置（默认 10），全链路支持 |
| 2026-05-27 | P1.1-P1.3 | Done | embedding 失败使用独立状态 `embedding_failed` |
| 2026-05-27 | P3.1-P3.3 | Done | JWT 有效期 24h → 7 天 |
