# P2/P3 增强功能 TODO List

> 创建时间: 2026-06-02
> 前置: Issues #20-#25 核心修复 + P0/P1 增强全部完成 (v0.2.7-beta.2)
> 本文档覆盖: 剩余 P2/P3 增强建议的深入分析与实施计划
> 状态: **待执行**
> 协议: RIPER-5

---

## 总览

| 优先级 | ID | 来源 | 标题 | 类型 | 难度 | 预估 | 状态 |
|--------|-----|------|------|------|------|------|------|
| P2 | E-24.5 | #24 | 聊天「复制诊断信息」按钮 | 前端 | 低 | 30min | |
| P2 | E-22.1 | #22 | OCR 安装改为异步任务模式 | 前后端 | 中高 | 2h | |
| P2 | E-22.2 | #22 | OCR 安装「取消」按钮 | 前后端 | 中 | 30min | |
| P2 | E-23.4 | #23 | 后端文档处理任务队列 (并发控制) | 后端 | 中高 | 2h | |
| P3 | E-23.5 | #23 | 大文件 chunking 性能 benchmark | 后端 | 低 | 45min | |
| P3 | E-25.3 | #25 | 知识图谱生成历史和诊断记录 | 前后端 | 中 | 1.5h | |
| P3 | E-22.3 | #22 | Windows UAC 提权安装 | 后端 | 高 | 2h | |

**总预估工时**: ~9h

---

## P2 级 — 有价值的增强

---

### E-24.5 聊天「复制诊断信息」按钮

**来源**: Issue #24 第五部分
**难度**: 低 | **预估**: 30min | **依赖**: 无

#### 现状分析

当前 AI 消息气泡（`chat_page.dart`）只有基本的文本展示，没有任何交互菜单。当用户遇到问题需要反馈时，无法方便地提供诊断信息（如 workspace_id、model 配置、检索结果数量等）。

现有代码中 `PopupMenuButton` 仅用于工作区切换（第 560 行），AI 消息气泡区域没有长按/右键菜单。

#### 技术方案

**后端无需改动**，诊断信息可从前端现有 state 中收集。

**前端改动** (`chat_page.dart`):

1. **给 AI 消息气泡添加 `GestureDetector`**:
   ```dart
   GestureDetector(
     onLongPressStart: (details) => _showMessageMenu(context, details, message),
     child: existingBubbleWidget,
   )
   ```

2. **实现 `_showMessageMenu` 方法**:
   - 使用 `showMenu()` 显示弹出菜单
   - 菜单项:
     - 📋 复制文本 → `Clipboard.setData(ClipboardData(text: message.content))`
     - 🔍 复制诊断信息 → 收集并格式化诊断 JSON

3. **诊断信息收集**:
   ```dart
   Map<String, dynamic> diagnostics = {
     'workspace_id': currentWorkspaceId,
     'conversation_id': conversationId,
     'message_id': message.id,
     'timestamp': message.createdAt,
     'llm_provider': currentLlmConfig?.providerName,
     'llm_model': currentLlmConfig?.modelName,
     'embedding_provider': currentEmbeddingConfig?.providerName,
     'sources_count': message.citations?.length ?? 0,
     'rerank_enabled': currentRerankConfig?.enabled,
     'app_version': appVersion,
     'platform': Platform.operatingSystem,
   };
   ```

4. **格式化输出**:
   ```
   === TrustRAG 诊断信息 ===
   Workspace: {id}
   Conversation: {id}
   Message: {id}
   LLM: {provider}/{model}
   Embedding: {provider}
   Sources: {count}
   Rerank: {enabled}
   Version: {version}
   Platform: {os}
   Time: {timestamp}
   ========================
   ```

#### 影响文件

- `apps/client/lib/features/chat/pages/chat_page.dart` — 添加长按菜单和诊断信息收集

#### 验收标准

- [ ] AI 消息气泡长按弹出菜单
- [ ] "复制文本" 功能正常
- [ ] "复制诊断信息" 复制格式化的诊断 JSON/文本
- [ ] 复制后显示 SnackBar 确认
- [ ] `dart analyze` 无错误

---

### E-22.1 OCR 安装改为异步任务模式

**来源**: Issue #22 第二部分
**难度**: 中高 | **预估**: 2h | **依赖**: 无

#### 现状分析

**后端** (`backend/src/api/system.rs`):
- `ocr_install()` 函数是同步的: 收到 POST 请求 → `tokio::process::Command` 执行安装命令 → `tokio::time::timeout(600s)` 等待完成 → 返回 JSON 结果
- 安装超时上限 10 分钟，期间 HTTP 连接保持占用
- 安装结果一次性返回（success/fail + output + exit_code + message）

**前端** (`apps/client/lib/features/settings/pages/ocr_settings_page.dart`):
- `_startInstall()` 使用 `receiveTimeout: Duration(minutes: 11)` 的 Dio 请求
- 安装过程中用户只能看到 "安装中..." 的 loading 指示器
- 无实时日志输出，无进度反馈
- 超时后显示提示，但无法确认安装是否仍在后台运行

**核心问题**:
1. 长时间 HTTP 连接不稳定，移动端/弱网更明显
2. 前端无法展示实时安装日志
3. 断线后无法恢复查看状态
4. 安装中途无法取消

#### 技术方案

**后端改造** (`backend/src/api/system.rs`):

1. **定义任务状态结构**:
   ```rust
   #[derive(Clone, Serialize)]
   struct OcrInstallTask {
       task_id: String,
       engine: String,
       package_manager: String,
       status: OcrTaskStatus,    // pending / running / completed / failed / cancelled
       started_at: chrono::DateTime<Utc>,
       finished_at: Option<chrono::DateTime<Utc>>,
       exit_code: Option<i32>,
       log_lines: Vec<String>,   // 实时追加的日志行
       message: Option<String>,
       pid: Option<u32>,         // 子进程 PID，用于取消
   }

   #[derive(Clone, Serialize, PartialEq)]
   enum OcrTaskStatus {
       Pending, Running, Completed, Failed, Cancelled,
   }
   ```

2. **在 AppState 中添加任务存储**:
   ```rust
   pub struct AppState {
       // ... 现有字段
       pub ocr_tasks: Arc<Mutex<HashMap<String, OcrInstallTask>>>,
   }
   ```

3. **新增 3 个 API 端点**:

   **`POST /system/ocr-install/start`**:
   - 创建任务，设置 status = Running
   - `tokio::spawn` 后台执行安装命令
   - 使用 `Command::stdout(Stdio::piped()).stderr(Stdio::piped())` 捕获输出
   - 每读到一行 stdout/stderr → 追加到 `task.log_lines`
   - 完成后更新 status 和 exit_code
   - 立即返回 `{ task_id, status: "running" }`

   **`GET /system/ocr-install/status/{task_id}`**:
   - 返回完整任务状态（包括 log_lines）
   - 支持 `?since_line=N` 参数只返回第 N 行之后的新日志（减少传输量）

   **`POST /system/ocr-install/cancel/{task_id}`**:
   - 通过存储的 PID 发送 SIGTERM/TerminateProcess
   - 更新 status = Cancelled

4. **保留旧的 `POST /system/ocr-install` 端点**作为 fallback（兼容性）

**前端改造** (`apps/client/lib/features/settings/pages/ocr_settings_page.dart`):

1. **安装流程改为**:
   ```dart
   Future<void> _startInstall() async {
     // 1. 调用 start 端点获取 task_id
     final resp = await api.dio.post('/system/ocr-install/start', data: {...});
     final taskId = resp.data['task_id'];
     
     // 2. 启动轮询定时器
     _pollTimer = Timer.periodic(Duration(seconds: 2), (_) => _pollStatus(taskId));
   }
   ```

2. **轮询状态更新**:
   ```dart
   Future<void> _pollStatus(String taskId) async {
     final resp = await api.dio.get('/system/ocr-install/status/$taskId',
       queryParameters: {'since_line': _lastLogLine});
     
     setState(() {
       _taskStatus = resp.data['status'];
       _installLog += resp.data['new_lines'].join('\n');
       _lastLogLine = resp.data['total_lines'];
     });
     
     if (['completed', 'failed', 'cancelled'].contains(_taskStatus)) {
       _pollTimer?.cancel();
       // 处理最终结果
     }
   }
   ```

3. **UI 变更**:
   - 安装中显示实时日志 (ScrollView + 自动滚动到底部)
   - 安装中显示「取消安装」按钮
   - 断线重连后可恢复查看进度

#### 影响文件

- `backend/src/api/system.rs` — 新增 3 个端点，添加任务状态管理
- `backend/src/main.rs` — AppState 中添加 ocr_tasks 字段
- `apps/client/lib/features/settings/pages/ocr_settings_page.dart` — 重构安装流程为轮询模式

#### 验收标准

- [ ] 安装请求立即返回 task_id
- [ ] 前端每 2 秒轮询日志并实时展示
- [ ] 安装完成后正确显示结果（成功/失败）
- [ ] 取消按钮可终止安装进程
- [ ] 断线后重进页面能恢复查看进行中的任务
- [ ] 旧的同步安装端点仍然可用（向后兼容）
- [ ] `cargo check` + `dart analyze` 无错误

---

### E-22.2 OCR 安装「取消」按钮

**来源**: Issue #22 第三部分
**难度**: 中 | **预估**: 30min | **依赖**: E-22.1

随 E-22.1 一起实现。后端 cancel 端点通过 PID kill 子进程，前端安装中显示取消按钮调用 cancel 端点。

#### 验收标准

- [ ] 安装过程中显示「取消安装」按钮
- [ ] 点击后后端成功终止子进程
- [ ] 前端显示「安装已取消」状态
- [ ] 取消后可重新发起安装

---

### E-23.4 后端文档处理任务队列 (并发控制)

**来源**: Issue #23 第九部分
**难度**: 中高 | **预估**: 2h | **依赖**: 无

#### 现状分析

**后端** (`backend/src/api/documents.rs`):
- 文档上传 (`upload_document`, 第 328 行) 和重新处理 (`reprocess_document`, 第 463 行) 直接 `tokio::spawn(process_document(...))`
- **无并发限制**: 用户同时上传 10 个文档 → 10 个 tokio task 并行执行
- 每个 task 独立做: 解析 → 分块 → embedding API 调用

**问题**:
1. embedding API 可能有 rate limit（如 OpenAI 的 RPM/TPM 限制）
2. 大文件处理内存密集，多个同时处理可能 OOM
3. 无法控制资源使用优先级
4. 重启后 `processing` 状态的文档成为僵尸（不会自动恢复）

#### 技术方案

**方案 A: Semaphore 方案（推荐，最小改动）**:

1. **在 AppState 中添加 Semaphore**:
   ```rust
   pub struct AppState {
       // ... 现有字段
       pub doc_processing_semaphore: Arc<tokio::sync::Semaphore>,
   }
   ```
   初始化: `Semaphore::new(2)` (默认最多 2 个文档同时处理)

2. **修改 `process_document` 函数**:
   ```rust
   pub async fn process_document(
       pool: DbPool,
       storage: StorageService,
       doc_processor_url: String,
       embedding_provider: Option<Arc<dyn EmbeddingProvider>>,
       doc_id: Uuid,
       workspace_id: Uuid,
       semaphore: Arc<Semaphore>,  // 新增参数
   ) {
       let _permit = semaphore.acquire().await.unwrap();
       // 获取到 permit 后才开始处理
       if let Err(e) = process_document_inner(...).await {
           // 处理错误
       }
       // _permit drop 时自动释放
   }
   ```

3. **调用处传递 semaphore**:
   ```rust
   let semaphore = state.doc_processing_semaphore.clone();
   tokio::spawn(async move {
       process_document(pool, storage, ..., semaphore).await;
   });
   ```

4. **启动时恢复僵尸文档**:
   ```rust
   // main.rs 启动后
   async fn recover_stale_documents(state: &AppState) {
       let rows = sqlx::query(
           "SELECT id, workspace_id FROM documents WHERE processing_status IN ('processing', 'chunking', 'embedding')"
       ).fetch_all(&state.pool).await;
       
       for row in rows {
           // 重新入队处理
           let semaphore = state.doc_processing_semaphore.clone();
           tokio::spawn(async move { process_document(..., semaphore).await });
       }
   }
   ```

5. **可选: 配置化并发数**:
   - 环境变量 `TRUSTRAG_DOC_CONCURRENCY=2`
   - 或配置文件项

**方案 B: 基于 channel 的任务队列**（更复杂，但更灵活）:
- 使用 `mpsc::channel` 作为任务队列
- 独立的 worker 任务从 channel 消费
- 支持优先级（小文件优先）
- **暂不推荐**: 对当前需求来说 Semaphore 足够

#### 影响文件

- `backend/src/main.rs` — AppState 添加 semaphore，启动时调用 recover
- `backend/src/services/document.rs` — process_document 接受 semaphore 参数
- `backend/src/api/documents.rs` — 传递 semaphore 给 process_document
- `backend/Cargo.toml` — 无需新依赖（tokio::sync::Semaphore 已在 tokio 中）

#### 验收标准

- [ ] 同时上传 5 个文档，最多 2 个并行处理，其余排队
- [ ] 排队中的文档状态显示为 "pending"
- [ ] 处理完成后自动开始下一个
- [ ] 应用重启后 stale 文档自动恢复处理
- [ ] 并发数可通过环境变量配置
- [ ] `cargo check` 无错误

---

## P3 级 — 后期优化

---

### E-23.5 大文件 chunking 性能 benchmark

**来源**: Issue #23 第三部分
**难度**: 低 | **预估**: 45min | **依赖**: 无

#### 技术方案

1. **添加 `criterion` 依赖**:
   ```toml
   [dev-dependencies]
   criterion = { version = "0.5", features = ["html_reports"] }
   
   [[bench]]
   name = "chunking_bench"
   harness = false
   ```

2. **编写 benchmark** (`backend/benches/chunking_bench.rs`):
   ```rust
   use criterion::{criterion_group, criterion_main, Criterion, BenchmarkId};
   
   fn bench_chunk_markdown(c: &mut Criterion) {
       let sizes = [
           ("100KB", generate_markdown(100 * 1024)),
           ("500KB", generate_markdown(500 * 1024)),
           ("1MB", generate_markdown(1024 * 1024)),
       ];
       
       let mut group = c.benchmark_group("chunk_markdown");
       for (name, content) in &sizes {
           group.bench_with_input(
               BenchmarkId::new("chunk", name),
               content,
               |b, content| b.iter(|| chunk_markdown(content, 512, 50)),
           );
       }
       group.finish();
   }
   ```

3. **生成测试数据**:
   - 模拟真实文档结构: 标题、段落、代码块、列表
   - 含中文/英文混合内容

#### 影响文件

- `backend/Cargo.toml` — dev-dependencies 添加 criterion
- `backend/benches/chunking_bench.rs` — 新文件

#### 验收标准

- [ ] 100KB 文件分块 < 100ms
- [ ] 500KB 文件分块 < 500ms
- [ ] 1MB 文件分块 < 2s
- [ ] 生成 HTML 报告可查看性能曲线
- [ ] 如发现瓶颈，附带优化建议

---

### E-25.3 知识图谱生成历史和诊断记录

**来源**: Issue #25 第九部分
**难度**: 中 | **预估**: 1.5h | **依赖**: 无

#### 技术方案

1. **新建数据库表** `graph_generation_tasks`:
   ```sql
   CREATE TABLE graph_generation_tasks (
       id TEXT PRIMARY KEY,
       workspace_id TEXT NOT NULL REFERENCES workspaces(id),
       document_id TEXT REFERENCES documents(id),
       -- NULL 表示批量生成
       trigger_type TEXT NOT NULL CHECK (trigger_type IN ('manual_single', 'manual_batch', 'auto')),
       status TEXT NOT NULL DEFAULT 'running' CHECK (status IN ('running', 'completed', 'failed')),
       llm_provider TEXT,
       llm_model TEXT,
       entities_created INTEGER DEFAULT 0,
       relations_created INTEGER DEFAULT 0,
       chunks_processed INTEGER DEFAULT 0,
       error_message TEXT,
       started_at TEXT NOT NULL,
       finished_at TEXT,
       elapsed_ms INTEGER,
       created_by TEXT NOT NULL REFERENCES users(id)
   );
   ```

2. **后端改动**:
   - `knowledge_extraction.rs`: 在图谱生成前后插入/更新 `graph_generation_tasks` 记录
   - 新增 API: `GET /workspaces/{ws_id}/graph-tasks` — 返回生成历史列表
   - 新增 API: `GET /workspaces/{ws_id}/graph-tasks/{task_id}` — 返回单次详情

3. **前端改动**:
   - 知识图谱页面增加「生成历史」标签页或侧栏
   - 展示: 时间、文档名、耗时、实体/关系数、状态
   - 失败任务显示错误详情

#### 影响文件

- `backend/migrations/0024_graph_generation_tasks.sql` — PostgreSQL 迁移
- `backend/migrations_sqlite/init.sql` — SQLite schema 更新
- `backend/src/services/knowledge_extraction.rs` — 插入任务记录
- `backend/src/api/documents.rs` 或新文件 — 历史查询 API
- `apps/client/lib/features/search/pages/knowledge_graph_page.dart` — 历史 UI

#### 验收标准

- [ ] 每次图谱生成创建一条历史记录
- [ ] 历史列表按时间倒序展示
- [ ] 失败的任务显示错误信息
- [ ] 批量生成和单文档生成都有记录
- [ ] 前端能查看完整生成历史

---

### E-22.3 Windows UAC 提权安装

**来源**: Issue #22 第一部分
**难度**: 高 | **预估**: 2h | **依赖**: 无 | **ROI: 低** (仅影响 Windows 平台)

#### 技术方案

**方案 A: PowerShell 提权 (推荐)**:
```rust
// Windows 下执行安装命令时
#[cfg(target_os = "windows")]
fn run_elevated(command: &str, args: &[&str]) -> Result<Output> {
    let script = format!(
        "Start-Process -FilePath '{}' -ArgumentList '{}' -Verb RunAs -Wait -PassThru",
        command, args.join(" ")
    );
    Command::new("powershell")
        .args(&["-Command", &script])
        .output()
}
```

**方案 B: Flutter 平台通道 + Win32 API**:
- 通过 `MethodChannel` 调用原生 Dart → Win32 `ShellExecuteExW` with `runas` verb
- 更复杂，需要 Windows 原生代码

**推荐方案 A**: 简单、不需要额外的原生代码，PowerShell 在所有 Windows 10+ 上都可用。

#### 影响文件

- `backend/src/api/system.rs` — Windows 特定的提权执行逻辑

#### 验收标准

- [ ] Windows 上安装 OCR 时自动请求 UAC 提权
- [ ] 用户同意 UAC 后安装正常执行
- [ ] 用户拒绝 UAC 时返回明确错误
- [ ] macOS/Linux 不受影响

---

## 推荐执行顺序

```
第一轮: 快速出成果 (~1h)
├── E-24.5 聊天复制诊断信息 (30min)
└── E-23.5 大文件 chunking benchmark (45min)

第二轮: OCR 异步化 (~2.5h)
├── E-22.1 OCR 安装异步任务模式 (2h)
└── E-22.2 OCR 安装取消按钮 (30min, 随 E-22.1 一起)

第三轮: 文档处理并发控制 (~2h)
└── E-23.4 文档处理任务队列

第四轮: 知识图谱增强 (~1.5h)
└── E-25.3 图谱生成历史

第五轮: 平台特定优化 (可选)
└── E-22.3 Windows UAC 提权 (ROI 低，视需要)
```

每轮完成后: `cargo check` + `dart analyze` → 提交 → 继续下一轮

---

## 与已完成工作的关系

| 已完成 | 本轮增强 | 关系 |
|--------|---------|------|
| E-24.1 停止生成按钮 ✅ | E-24.5 诊断信息 | 同一 chat 页面，可复用 UI 模式 |
| E-24.2 首 token 超时 ✅ | E-24.5 诊断信息 | 超时时诊断信息特别有用 |
| E-23.1 重新处理按钮 ✅ | E-23.4 任务队列 | 重新处理也走队列 |
| E-23.2/3 处理进度 ✅ | E-23.4 任务队列 | 队列状态可在进度中展示 |
| OCR 安装基础功能 ✅ | E-22.1/2 异步+取消 | 在现有安装逻辑上改造 |
| E-25.1 图谱 badge ✅ | E-25.3 生成历史 | badge 展示当前状态，历史展示变更记录 |
