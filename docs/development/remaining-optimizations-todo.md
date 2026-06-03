# 剩余优化项 TODO List

> 创建时间: 2026-06-03
> 来源: Issues #20-#25 深入分析后发现的 3 个未完成优化点
> 状态: 进行中
> 协议: RIPER-5

---

## 总览

| 序号 | ID | 来源 | 标题 | 类型 | 难度 | 预估 | 状态 |
|------|-----|------|------|------|------|------|------|
| 1 | OPT-1 | #22 | OCR 安装后自动验证 | 后端 | 低 | 20min | |
| 2 | OPT-2 | #23 | chunk 批量 INSERT 优化 | 后端 | 中 | 40min | |
| 3 | OPT-3 | #23 | processing_elapsed_ms 诊断字段 | 后端+前端 | 中 | 45min | |

**总预估工时**: ~1.5h

---

## OPT-1: OCR 安装后自动验证

**来源**: Issue #22 第四部分 — "安装后验证：自动检测 Tesseract 是否可用"
**现状**: 安装完成后只显示"安装成功！请刷新页面确认状态"，没有自动重新检测 OCR 可用性
**影响**: 用户需要手动刷新页面才能看到 OCR 状态更新

### 技术方案

**后端改动** (`backend/src/api/system.rs`):
1. 安装成功后（`OcrTaskStatus::Completed`），自动调用 `check_binary("tesseract", ...)` 验证
2. 将验证结果写入 `OcrInstallTask.message`，例如：
   - 验证成功: "tesseract 安装成功！版本: 5.3.x，路径: /usr/bin/tesseract"
   - 验证失败: "安装命令执行成功，但 tesseract 仍不可用。可能需要重启终端或将其添加到 PATH。"
3. 在 `OcrInstallStatusResponse` 中新增 `verified: Option<bool>` 字段

**前端改动** (`apps/client/lib/features/settings/pages/ocr_settings_page.dart`):
1. 安装完成后根据 `verified` 字段显示不同提示
2. 验证成功 → 自动刷新 OCR 检测状态（invalidate provider）
3. 验证失败 → 显示排查建议

---

## OPT-2: chunk 批量 INSERT 优化

**来源**: Issue #23 第四部分 — "使用批量插入，例如每批 100 或 200 个 chunk"
**现状**: 每个 chunk 单独执行一次 INSERT，大文档 500+ chunks 时产生 500+ 次数据库写入
**影响**: 大文档处理速度慢，主要瓶颈在 chunking 阶段的 DB 写入

### 技术方案

**后端改动** (`backend/src/services/document.rs`):
1. 将逐条 INSERT 改为批量 INSERT
2. 使用手动拼接多值 INSERT 语句: `INSERT INTO ... VALUES ($1,...), ($2,...), ...`
3. 每批 100 个 chunk，最后一批处理剩余
4. 保持进度更新逻辑（每批完成后更新 `chunks_done`）
5. 整个批量操作包裹在事务中

**实现细节**:
```rust
// 每批 100 个 chunk
const BATCH_SIZE: usize = 100;
for batch in chunks.chunks(BATCH_SIZE) {
    let mut query = String::from(
        "INSERT INTO document_chunks (id, document_id, chunk_index, heading_path, content, char_start, char_end, content_hash) VALUES "
    );
    // 动态拼接 ($1, $2, ...), ($9, $10, ...) ...
    // 绑定所有参数
    // 执行
}
```

**预期效果**: 大文档（500+ chunks）的 DB 写入时间减少 60-80%

---

## OPT-3: processing_elapsed_ms 诊断字段

**来源**: Issue #23 第二部分 — "processing_elapsed_ms / processing_started_at / processing_finished_at"
**现状**: documents 表有 `processing_status` 但无耗时统计，用户无法知道文档处理用了多长时间
**影响**: 无法诊断处理慢的原因（chunking 慢还是 embedding 慢）

### 技术方案

**数据库改动**:
1. SQLite `init.sql` 新增字段:
   - `processing_started_at TEXT` — 开始处理时间
   - `processing_finished_at TEXT` — 完成处理时间
   - `processing_elapsed_ms INTEGER` — 总耗时（毫秒）
2. PostgreSQL migration `0025_processing_elapsed.sql`

**后端改动** (`backend/src/services/document.rs`):
1. `process_document` 开始时记录 `started_at = Utc::now()`
2. 状态变为 `ready`/`failed` 时计算 `elapsed_ms` 并写入
3. 同时更新 `processing_started_at` 和 `processing_finished_at`

**后端改动** (`backend/src/api/documents.rs`):
1. 文档列表 API 返回这 3 个新字段

**前端改动** (`apps/client/lib/features/documents/`):
1. Document model 增加 `processingElapsedMs`、`processingStartedAt`、`processingFinishedAt`
2. 文档详情/列表中显示处理耗时（如 "处理用时: 12.3s"）

---

## 执行顺序

```
OPT-1 (最简单, 20min) → 测试 → 提交
OPT-2 (中等, 40min) → benchmark 对比 → 测试 → 提交
OPT-3 (中等, 45min) → 测试 → 提交
```

每个完成后写测试、验证、提交到 GitHub。
