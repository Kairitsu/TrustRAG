# Issues #20-#25 增强建议 TODO List

> 创建时间: 2026-06-02
> 提出者: Kairitsu (Issues #20-#25 中的建议部分)
> 前置: 所有核心 Bug 已修复并提交（见 issues-20-25-todo.md）
> 本文档覆盖: 各 Issue 中提出但尚未实现的**增强建议**
> 协议: RIPER-5

---

## 总览

| 优先级 | ID | 来源 | 标题 | 类型 | 难度 | 预估 |
|--------|-----|------|------|------|------|------|
| P0 | E-24.1 | #24 | 聊天「停止生成」按钮 | 前端 | 低 | 30min |
| P0 | E-24.2 | #24 | 首 token 超时检测 (30s) | 前端 | 低 | 30min |
| P0 | E-23.1 | #23 | 文档「重新处理」按钮 | 前后端 | 中 | 1h |
| P1 | E-24.3 | #24 | 后端 SSE 增加 retrieval_started/finished 事件 | 后端 | 中 | 1.5h |
| P1 | E-24.4 | #24 | 前端消费 SSE 阶段事件并展示 | 前端 | 中 | 1h |
| P1 | E-23.2 | #23 | 后端文档处理进度字段 (chunks_total/done) | 后端 | 中 | 1.5h |
| P1 | E-23.3 | #23 | 前端文档列表显示处理进度 | 前端 | 低 | 45min |
| P1 | E-25.1 | #25 | 资料库文档列表显示图谱生成状态 badge | 前后端 | 中 | 1.5h |
| P1 | E-25.2 | #25 | 图层过滤为空时的友好提示 | 前端 | 低 | 30min |
| P2 | E-22.1 | #22 | OCR 安装改为异步任务模式 (task_id + 轮询) | 后端 | 中高 | 2h |
| P2 | E-22.2 | #22 | OCR 安装「取消」按钮 | 前后端 | 中 | 1h |
| P2 | E-23.4 | #23 | 后端文档处理任务队列 (并发控制) | 后端 | 高 | 3h |
| P2 | E-24.5 | #24 | 「复制诊断信息」按钮 | 前端 | 低 | 30min |
| P3 | E-25.3 | #25 | 知识图谱生成历史和诊断记录 | 前后端 | 中高 | 2h |
| P3 | E-22.3 | #22 | Windows UAC 提权安装 (ShellExecute RunAs) | 后端 | 高 | 2h |
| P3 | E-23.5 | #23 | 大文件 chunking 性能 benchmark | 后端 | 中 | 1h |

---

## P0 级 — 必做（用户体验关键缺失）

### E-24.1 聊天「停止生成」按钮
**来源**: Issue #24 第五部分
**现状**: 用户发送消息后无法中断生成，只能等待完成或手动刷新
**方案**:
- 在 AI 气泡底部或输入框旁添加「停止生成」按钮（`_isSending == true` 时显示）
- 点击后关闭 SSE 连接 (`_httpClient.close()` 或取消 `StreamSubscription`)
- 将已接收的内容作为不完整回复保留（标记 `is_truncated`）
- 停止后显示「回答已中断」标记
**文件**:
- `apps/client/lib/features/chat/pages/chat_page.dart`

### E-24.2 首 token 超时检测
**来源**: Issue #24 第四部分
**现状**: 发送后如果后端无响应，前端会永远显示 loading，无超时保护
**方案**:
- 发送消息后启动 30 秒定时器
- 收到第一个 `text_delta` 事件后取消定时器
- 超时未收到 token → 在 AI 气泡中显示「后端响应超时，请检查 LLM 配置或重试」
- 提供「重新发送」按钮
**文件**:
- `apps/client/lib/features/chat/pages/chat_page.dart`

### E-23.1 文档「重新处理」按钮
**来源**: Issue #23 第六、八部分
**现状**: 文档处理卡住后，用户只能删除重新上传
**方案**:
- 后端新增 `POST /documents/{id}/reprocess` 端点
  - 将文档状态重置为 `pending`，清除旧 chunks 和 embeddings
  - 重新触发文档处理流水线
- 前端文档列表中，对 `isStale` 或 `failed` 文档显示「重新处理」按钮
- 增加「取消处理」选项（将状态设为 `cancelled`）
**文件**:
- `backend/src/api/documents.rs` (新增 reprocess 端点)
- `apps/client/lib/features/documents/pages/documents_page.dart`

---

## P1 级 — 重要增强

### E-24.3 后端 SSE 增加 retrieval/LLM 阶段事件
**来源**: Issue #24 第二、六部分
**现状**: SSE 流只有 `message_start`、`text_delta`、`citation`、`message_end`、`error`，缺少检索阶段事件
**方案**:
- 在 RAG 管线中关键节点插入 SSE 事件:
  - `retrieval_started` — embedding 检索开始
  - `retrieval_finished { sources_count, elapsed_ms }` — 检索完成
  - `llm_started` — LLM 调用开始
- 前端相应消费这些事件更新 `_streamingPhase`
**文件**:
- `backend/src/api/chat.rs` 或 `backend/src/services/chat.rs` (SSE 事件发送)
- `apps/client/lib/features/chat/pages/chat_page.dart` (事件消费)

### E-24.4 前端消费 SSE 阶段事件
**来源**: Issue #24 第二部分
**依赖**: E-24.3
**方案**:
- 解析 `retrieval_started` → 显示 "正在检索资料库..."
- 解析 `retrieval_finished` → 显示 "已检索到 N 条相关资料"
- 解析 `llm_started` → 显示 "正在生成回答..."
- 当前的硬编码阶段文案改为事件驱动

### E-23.2 后端文档处理进度字段
**来源**: Issue #23 第一、二部分
**现状**: 后端只更新 `processing_status`，没有进度数值
**方案**:
- 在 `documents` 表增加字段:
  - `chunks_total INTEGER DEFAULT NULL`
  - `chunks_done INTEGER DEFAULT NULL`
  - `embedding_batches_total INTEGER DEFAULT NULL`
  - `embedding_batches_done INTEGER DEFAULT NULL`
- `document.rs` 处理流程中每完成一个 batch 更新进度
- 文档列表 API 返回这些字段
**文件**:
- `backend/migrations_sqlite/init.sql` (schema)
- `backend/src/services/document.rs` (进度更新)
- `backend/src/api/documents.rs` (返回进度)

### E-23.3 前端文档列表显示处理进度
**来源**: Issue #23 第八部分
**依赖**: E-23.2
**方案**:
- `Document` model 增加 `chunksTotal`/`chunksDone`/`embeddingBatchesTotal`/`embeddingBatchesDone`
- 文档处理中时，显示进度条或文字: "分块中 120/380" 或 "向量化 12/38"
- 替代当前的纯文字状态 chip
**文件**:
- `apps/client/lib/features/documents/providers/document_provider.dart`
- `apps/client/lib/features/documents/pages/documents_page.dart`

### E-25.1 资料库文档列表显示图谱 badge
**来源**: Issue #25 第四部分
**现状**: 资料库文档列表不显示图谱生成状态
**方案**:
- 后端文档列表 API 增加派生字段:
  - `graph_status`: not_generated / generated / generating
  - `graph_entities_count`
  - `graph_relations_count`
  - 通过 LEFT JOIN entities/entity_relations 按 document_id 聚合
- 前端文档 card 上显示图谱状态 badge:
  - 未生成: 灰色 "无图谱"
  - 已生成: 绿色 "图谱 12实体/5关系"
  - 生成中: 蓝色动画
**文件**:
- `backend/src/api/documents.rs` (聚合查询)
- `apps/client/lib/features/documents/providers/document_provider.dart`
- `apps/client/lib/features/documents/pages/documents_page.dart`

### E-25.2 图层过滤为空时的友好提示
**来源**: Issue #25 第六部分
**现状**: 图层过滤后如果无数据，可能显示空白或"暂无图谱"
**方案**:
- 当图谱总数据不为空但当前过滤后为空时，显示:
  "当前图层没有数据。可切换到「全部图层」或选择其他图层。"
- 图层过滤控件旁显示每个图层的数据数量
- 添加「全部图层」快捷按钮
**文件**:
- `apps/client/lib/features/search/pages/knowledge_graph_page.dart`

---

## P2 级 — 有价值的增强

### E-22.1 OCR 安装改为异步任务模式
**来源**: Issue #22 第二部分
**现状**: OCR 安装是同步 HTTP 请求（最长 10 分钟），前端 Dio 等待
**方案**:
- 后端改为:
  - `POST /system/ocr-install/start` → 返回 `task_id`，后台执行
  - `GET /system/ocr-install/status/{task_id}` → 返回状态、日志、进度
- 前端轮询 status 端点，实时更新日志
- 好处: 不再依赖超长 HTTP timeout，断线可重连查看状态
**文件**:
- `backend/src/api/system.rs`
- `apps/client/lib/features/settings/pages/ocr_settings_page.dart`

### E-22.2 OCR 安装「取消」按钮
**来源**: Issue #22 第三部分
**依赖**: E-22.1
**方案**:
- `POST /system/ocr-install/cancel/{task_id}` → kill 安装子进程
- 前端安装过程中显示「取消安装」按钮
**文件**:
- `backend/src/api/system.rs`
- `apps/client/lib/features/settings/pages/ocr_settings_page.dart`

### E-23.4 后端文档处理任务队列
**来源**: Issue #23 第九部分
**现状**: 每个文档上传后直接 spawn 后台任务处理，无并发控制
**方案**:
- 使用 `tokio::sync::Semaphore` 限制同时处理的文档数（默认 2）
- 超出并发限制的文档排队等待
- 应用重启后检测 processing 状态文档，重新入队
**文件**:
- `backend/src/services/document.rs`
- `backend/src/main.rs` (启动时恢复)

### E-24.5 聊天「复制诊断信息」按钮
**来源**: Issue #24 第五部分
**方案**:
- 长按或右键 AI 消息，增加「复制诊断信息」选项
- 诊断信息包含: workspace_id, conversation_id, model_config, embedding provider, retrieval sources 数量等
**文件**:
- `apps/client/lib/features/chat/pages/chat_page.dart`

---

## P3 级 — 后期优化

### E-25.3 知识图谱生成历史
**来源**: Issue #25 第九部分
**方案**: 新建 `graph_generation_tasks` 表记录每次生成的文档、模型、实体数、关系数、耗时、错误等

### E-22.3 Windows UAC 提权安装
**来源**: Issue #22 第一部分
**方案**: 使用 PowerShell `Start-Process -Verb RunAs` 或平台通道 `ShellExecute RunAs` 实现

### E-23.5 大文件 chunking 性能 benchmark
**来源**: Issue #23 第三部分
**方案**: 对 100KB/500KB/1MB Markdown 文件编写 benchmark，确保分块在数秒内完成

---

## 执行策略

### 第一轮: P0 必做项 (约 2h)
```
E-24.1 停止生成按钮 → E-24.2 首token超时 → E-23.1 重新处理按钮
```
完成后提交，这三个直接解决最影响用户体验的交互缺失。

### 第二轮: P1 重要增强 (约 6h)
```
E-24.3 后端SSE事件 → E-24.4 前端消费事件
→ E-23.2 进度字段 → E-23.3 前端进度展示
→ E-25.1 图谱badge → E-25.2 图层提示
```
每完成一个功能块后提交。

### 第三轮: P2 有价值增强 (约 5h)
```
E-22.1 OCR异步任务 → E-22.2 取消按钮
→ E-23.4 任务队列 → E-24.5 诊断信息
```

### 第四轮: P3 后期优化 (视需要)
低优先级，可留到下一轮迭代。

---

## 与已完成修复的关系

| 核心修复 (已完成) | 本文档增强项 |
|---|---|
| #20 Rerank PUT 500 修复 | 无增强需求 (Issue #20 建议已全部覆盖) |
| #21 多账号切换 Cannot connect | 无增强需求 (Issue #21 核心问题已解决) |
| #22 OCR 安装体验 | E-22.1 异步任务 / E-22.2 取消 / E-22.3 UAC |
| #23 大文档分块卡住 | E-23.1 重新处理 / E-23.2 进度 / E-23.3 前端进度 / E-23.4 队列 / E-23.5 benchmark |
| #24 聊天无回复 | E-24.1 停止 / E-24.2 超时 / E-24.3 SSE事件 / E-24.4 事件消费 / E-24.5 诊断 |
| #25 知识图谱状态 | E-25.1 图谱badge / E-25.2 图层提示 / E-25.3 生成历史 |
