# TrustRAG Issue #12 - #17 开发 TODO List

> 创建时间: 2026-05-28
> 最后更新: 2026-05-29 (P3 批量完成)
> Issue 提交者: Kairitsu
> 审查方法: 逐文件代码审查 + GitHub Issue 原始需求对照

---

## 总览

| Issue | 标题 | 状态 | 完成度 | 关键遗留 |
|-------|------|------|--------|---------|
| #12 | Windows 端卸载/升级数据污染 | ✅ 完成 | 100% | — |
| #13 | 新增 Rerank 重排模型配置 | ✅ 完成 | 100% | — |
| #14 | 完善知识图谱功能 | 部分完成 | 75% | 三层图谱/人工编辑 |
| #15 | 优化引用编号视觉显示 | ✅ 完成 | 100% | — |
| #16 | 多账号数据隔离 | ✅ 完成 | 100% | — |
| #17 | 桌面端内置 PDF/DOCX 解析 | 部分完成 | 80% | 一键安装向导/OCR 集成 |

---

## Issue #12: Windows 端卸载/升级数据污染

### 已完成 ✅

- [x] **12.1 SQLite Schema Migration 机制**
  - `db/sqlite.rs`: `PRAGMA user_version` 管理 schema 版本
  - 完整迁移链: v1→v2→v3→v4→v5→v6
  - 后端启动自动检测并执行增量迁移
  - 新数据库自动初始化 (`migrations_sqlite/init.sql`)

- [x] **12.2 Token/用户一致性校验**
  - `system.rs`: `/system/validate-token` API
  - `sqlite.rs`: `validate_token_user()` 检查用户是否存在且 active
  - Token 有效但用户不存在时返回明确提示

- [x] **12.3 应用内数据管理入口**
  - `/system/db-info`: 查看 schema 版本、迁移状态
  - `/system/backup-db`: 一键备份数据库
  - `/system/reset-db`: 备份后清空所有表 + 提示重新注册
  - 前端 `DataManagementPage` 完整实现

### 未完成 ❌

- [x] **12.4 InnoSetup 卸载器改进** ✅ (2026-05-29)
  - **现状**: `apps/client/windows/installer.iss` 仍是默认模板，29 行，无任何 AppData 清理逻辑
  - **需要**: 在 `[UninstallDelete]` 或 `[Code]` 段中添加 AppData/LocalAppData 清理逻辑
  - **代码位置**: `apps/client/windows/installer.iss`

- [x] **12.5 卸载器界面增加数据保留/删除提示** ✅ (2026-05-29)
  - **现状**: 卸载器无自定义页面
  - **需要**: InnoSetup Pascal Script 中添加自定义对话框
  - 选项 1: 仅卸载应用，保留用户数据
  - 选项 2: 完全卸载，删除所有本地数据
  - 明确列出将被删除/保留的目录

- [x] **12.6 卸载程序命名优化** ✅ (2026-05-29)
  - **现状**: 默认 `unins000.exe`
  - **需要**: InnoSetup 中设置 `UninstallDisplayName` 等属性
  - **已完成**: 添加 AppId, AppVerName, AppSupportURL, AppUpdatesURL, UninstallFilesDir

### 优先级: P2（仅影响 Windows 安装包，不影响核心功能）

---

## Issue #13: 新增 Rerank 重排模型配置

### 已完成 ✅

- [x] **13.1 rerank_configs 数据表**
  - 字段: id, workspace_id, user_id, name, provider, api_base_url, api_key_enc, model_name, top_n, initial_recall_k, fallback_enabled, timeout_secs, is_default
  - SQLite migration v2→v3 创建表, v3→v4 添加扩展参数, v4→v5 添加 timeout_secs

- [x] **13.2 完整 CRUD API** (`api/rerank_configs.rs`)
  - `GET /rerank-configs`: 列出配置
  - `POST /rerank-configs`: 创建配置
  - `PUT /rerank-configs/{id}`: 更新配置
  - `DELETE /rerank-configs/{id}`: 删除配置
  - `POST /rerank-configs/{id}/test`: 测试连接
  - `PUT /rerank-configs/{id}/default`: 设为默认

- [x] **13.3 检索管线集成** (`services/retrieval_pipeline.rs`)
  - Embedding recall → Rerank precision 两阶段工作流
  - `run_with_reranker()` 接受可选的 RerankerProvider
  - 失败自动降级到 embedding-only（fallback_enabled 控制）
  - 降级时记录 `rerank_degraded: true` + `rerank_error`

- [x] **13.4 工作区级 Rerank 开关** (`api/workspaces.rs`)
  - `workspaces` 表新增 `rerank_enabled` 字段（migration v5→v6）
  - `chat.rs` 中根据 `ws_rerank_enabled` 决定是否加载 rerank

- [x] **13.5 Rerank 参数完整**
  - `top_n`: rerank 后保留数量（默认 5）
  - `initial_recall_k`: embedding 初始召回数量（默认 30）
  - `fallback_enabled`: 失败时是否自动降级（默认 true）
  - `timeout_secs`: rerank 请求超时时间（默认 30s）

- [x] **13.6 引用面板显示 Rerank 数据**
  - `ScoredChunkRef` 包含 `embedding_rank` 和 `rerank_score` 字段
  - 前端引用面板可展示排名变化

- [x] **13.7 嵌入模型误配置防护** (`api/embedding_configs.rs`)
  - `is_likely_rerank_model()`: 检测 rerank/re-rank/reranker 等模式
  - 创建时拦截 + 测试失败时二次提示

- [x] **13.8 `#[cfg(sqlite_mode)]` 正常工作**
  - `build.rs` 中: 当 `desktop` 或 `mobile` feature 启用时自动设置 `cfg(sqlite_mode)`
  - `updated_at` 更新逻辑在桌面构建中生效

- [x] **13.9 前端 Rerank 配置页面** (`settings/providers/rerank_config_provider.dart`)
  - 完整的配置管理 UI

### 未完成 ❌

- [x] **13.10 UI 内说明文档** ✅ (2026-05-29)
  - **已完成**: Rerank Tab 顶部添加可折叠说明卡片，包含两阶段检索架构、Embedding vs Rerank 区别、推荐配置

### 优先级: P3（功能基本完整，仅缺文档说明）

---

## Issue #14: 完善知识图谱功能

### 已完成 ✅

- [x] **14.1 LLM 驱动知识抽取** (`services/knowledge_extraction.rs`)
  - 从文档 chunk 中使用 LLM 抽取实体 + 关系
  - 结构化 JSON 输出（entity_type, relation_type, weight/置信度）

- [x] **14.2 异步图谱生成 + 进度轮询** (`api/knowledge_graph.rs`)
  - `POST /workspaces/{ws_id}/knowledge-graph/generate-all`: 全工作区生成
  - `POST /workspaces/{ws_id}/knowledge-graph/generate/{doc_id}`: 单文档生成
  - `GET /workspaces/{ws_id}/knowledge-graph/generation-status/{task_id}`: 状态轮询
  - 内存中 HashMap 存储任务状态（含 processed_documents/total/errors）

- [x] **14.3 图谱重置** (`DELETE /workspaces/{ws_id}/knowledge-graph/reset`)

- [x] **14.4 前端图谱可视化** (`knowledge_graph_page.dart`)
  - CustomPainter 绘制节点和边
  - InteractiveViewer 支持缩放和平移
  - 实体类型过滤
  - 节点点击显示详情（名称、类型、文档来源、关联关系）
  - 生成进度条 UI

- [x] **14.5 实体列表 Tab**
  - GET `/workspaces/{ws_id}/knowledge-graph/entities`
  - 按创建时间倒序，200 条限制

- [x] **14.6 LLM 返回置信度作为 weight**
  - `knowledge_extraction.rs` 中 LLM 返回的 confidence 直接用作 relation weight

### 未完成 ❌

- [ ] **14.7 三层图谱架构（核心需求）**
  - **现状**: 只实现了第三层（LLM 知识图谱）
  - **需要实现**:
    - 第一层: 基础文档网络（文档节点 + 标签节点 + 文件名/目录关联）
    - 第二层: 语义图谱（embedding 相似关系、chunk 相似性、related_to 弱语义关系）
    - 第三层: ✅ LLM 知识图谱（实体/关系/类型/证据）
  - **复杂度**: 高 — 需要新的图谱层级概念和后端数据模型

- [x] **14.8 节点拖拽功能** ✅ (2026-05-29)
  - **现状**: InteractiveViewer 只支持全局缩放/平移，无法拖拽单个节点重新布局
  - **需要**: GestureDetector + 自定义力导向布局算法或 onPanUpdate 绑定到特定节点
  - **复杂度**: 中 — 需要修改图谱渲染逻辑和交互检测

- [ ] **14.9 实体/关系人工编辑**
  - **现状**: 无任何编辑 API 和 UI
  - **需要后端 API**:
    - `PUT /entities/{id}`: 编辑实体名称/类型
    - `DELETE /entities/{id}`: 删除实体
    - `POST /entities`: 新增实体
    - `PUT /entity-relations/{id}`: 编辑关系
    - `DELETE /entity-relations/{id}`: 删除关系
    - `POST /entity-relations`: 新增关系
    - `POST /entities/merge`: 合并重复实体
  - **需要前端**: 编辑对话框、右键菜单、审核状态标记
  - **复杂度**: 高 — 需要大量后端 API + 前端 UI

- [x] **14.10 生成历史/错误日志持久化** ✅ (2026-05-29)
  - **现状**: 任务状态存在内存 HashMap 中，重启后丢失，无 UI 查看历史
  - **需要**: 持久化到 SQLite + 前端生成日志页面
  - **复杂度**: 中

- [x] **14.11 点击关系边查看来源证据** ✅ (2026-05-29)
  - **已完成**: 后端 GraphEdge 返回 description + source_document_id；前端 EdgeInfoCard 展示关系描述和来源文档

### 优先级: P1（图谱是核心差异化功能，但工作量大）

---

## Issue #15: 优化引用编号视觉突出

### 已完成 ✅

- [x] **15.1 引用编号加粗 + 颜色高亮**
  - `_injectCitationLinks()`: `[n]` → `[**\u2060[$num]**](#cite-$num)`
  - MarkdownStyleSheet 中 `a:` 设置 `fontWeight: w700`, `backgroundColor: primaryContainer.withAlpha(0.4)`

- [x] **15.2 底部引用 Chip 样式**
  - `_buildCitationChip()`: 圆角容器 + 编号 badge + 分数百分比 + 标题预览
  - `_buildCollapsibleCitations()`: 可折叠引用面板

- [x] **15.3 点击交互**
  - InkWell + borderRadius 提供 hover/tap 反馈
  - 点击引用编号 → 打开右侧/底部审核面板
  - 审核面板支持通过/错误/存疑操作

### 未完成 ❌

- [x] **15.4 暗色模式引用编号适配** ✅ (2026-05-29)
  - **已完成**: 引用 chip、引用面板、审核记录中的 Colors.grey.shade* 替换为 theme.colorScheme.onSurfaceVariant

### 优先级: P3（基本功能完整，暗色适配是锦上添花）

---

## Issue #16: 多账号数据隔离

### 已完成 ✅

- [x] **16.1 SQLite 数据库按账号物理隔离**
  - `BackendManager._getDataDir()`: `TrustRAG/accounts/$safeId/` 目录
  - 每个账号独立 `trustrag.db`

- [x] **16.2 后端重启切换数据目录**
  - `BackendManager.restart()`: stop → reset → start(accountId)
  - 新端口 + 新数据目录 + 新 JWT secret

- [x] **16.3 Per-account Token 存储**
  - `ApiClient`: `_accountTokenKey` = `token_$email`
  - `switchToAccount()`: 保存当前 token → 恢复目标账号 token → restart 后端

- [x] **16.4 SharedPreferences 状态隔离**
  - `workspace_provider.dart`: `_accountWorkspaceKey` = `last_workspace_$email`
  - 不同账号记住各自最后选中的工作区

- [x] **16.5 退出登录 + 清除数据**
  - Dashboard 中「退出并清除数据」按钮
  - `authProvider.logout(clearData: true)` 调用 `BackendManager.deleteAccountData()`
  - 物理删除账号数据目录

- [x] **16.6 账号切换 UI**
  - Sidebar 账号菜单 (`_AccountSwitcher`)
  - 显示已保存的账号列表 + 切换按钮

### 未完成 ❌

- [x] **16.7 多账号同时在线列表优化** ✅ (2026-05-29)
  - **已完成**: 重新设计账号切换底部面板，彩色头像、当前账号高亮卡片、主题自适应颜色

### 优先级: P3（核心隔离机制完整，UI 打磨为锦上添花）

---

## Issue #17: 桌面端内置 PDF/DOCX 解析 + OCR

### 已完成 ✅

- [x] **17.1 本地 PDF 文本解析**
  - `local_doc_processor.rs`: `parse_pdf()` 使用 lopdf 提取文本
  - Feature gate: `local-pdf` (desktop feature 包含)
  - 支持多页 PDF、按页标记

- [x] **17.2 本地 DOCX 文本解析**
  - `parse_docx_fallback()`: ZIP 解压 → 读取 `word/document.xml` → XML 文本提取
  - 支持段落、制表符、换行符、多 `<w:r>` 节点
  - 输出 Markdown 格式 + 自动检测标题

- [x] **17.3 TXT/MD/HTML 本地解析**
  - `parse_text()`: 直接读取
  - `parse_html()`: 正则去标签 + 提取 `<title>`

- [x] **17.4 扫描版 PDF 检测**
  - 后端: 文本为空时返回英文提示 "may be scanned/image-based"
  - 包含页数信息

- [x] **17.5 OCR 状态检测 API** (`system.rs`)
  - `GET /system/ocr-status`: 检测 tesseract 和 paddleocr 是否可用
  - 返回: any_available, tools[], recommendation（安装命令）

- [x] **17.6 OCR 组件管理页面** (`ocr_settings_page.dart`)
  - 展示 OCR 工具检测状态
  - 各工具名称、是否可用、版本号
  - 安装指导（复制命令）
  - 刷新状态按钮

### 未完成 ❌

- [x] **17.7 OCR bin_path 动态查找** ✅ (2026-05-29)
  - **现状**: `system.rs` 第 194 行 `let bin_path = None;` 硬编码
  - **需要**: 集成 `which` crate，动态查找 OCR 二进制路径
  - **修复步骤**:
    1. `Cargo.toml` 添加 `which = "7"` 依赖
    2. `system.rs` 中用 `which::which("tesseract")` 替换 `None`
  - **复杂度**: 低 — 预计 30 分钟

- [x] **17.8 扫描版 PDF 中文提示** ✅ (2026-05-29)
  - **现状**: 后端返回英文提示 "This PDF contains no extractable text (may be scanned/image-based)"
  - **需要**: 改为中文或双语提示，前端也应在 UI 层显示明确提示
  - **复杂度**: 低

- [ ] **17.9 一键 OCR 安装向导**
  - **现状**: 只有状态检测 + 安装命令文本提示
  - **Issue 原始需求**: 用户点击「安装并启用」→ 应用自动下载/安装/配置 OCR 引擎
  - **需要**:
    - OCR 组件选择面板（PaddleOCR/RapidOCR/Tesseract + 推荐标识）
    - 自动下载 + 解压 + 写入配置
    - 安装进度展示
    - 安装后自动测试
    - 离线安装包导入
  - **复杂度**: 高 — 涉及跨平台包管理、下载器、解压器、环境检测
  - **建议**: 分阶段实现，先做 Tesseract 的自动检测 + 手动安装指导增强

- [ ] **17.10 OCR 实际集成到文档处理管线**
  - **现状**: OCR 工具检测和状态展示已有，但 OCR 未实际集成到文档上传处理流程
  - **需要**: 扫描版 PDF 上传时自动调用本地 OCR → 提取文本 → 进入正常 chunking/embedding 流程
  - **复杂度**: 高

---

## 开发优先级建议

### P1 — 建议立即修复

| 编号 | 内容 | 预估工时 | Issue |
|------|------|---------|-------|
| 17.7 | OCR bin_path 动态查找（集成 which crate） | 0.5h | #17 |
| 17.8 | 扫描版 PDF 中文提示 | 0.5h | #17 |

### P2 — 建议近期完成

| 编号 | 内容 | 预估工时 | Issue |
|------|------|---------|-------|
| 12.4 | InnoSetup 卸载器 AppData 清理 | 2h | #12 |
| 12.5 | 卸载器数据保留/删除选项 UI | 2h | #12 |
| 14.8 | 图谱节点拖拽 | 4h | #14 |
| 14.10 | 生成历史/错误日志持久化 | 3h | #14 |

### P3 — 已完成 ✅

| 编号 | 内容 | 状态 | Issue |
|------|------|------|-------|
| 13.10 | Rerank 配置页 UI 说明文档 | ✅ 已完成 | #13 |
| 14.11 | 点击关系边查看来源证据 | ✅ 已完成 | #14 |
| 15.4 | 暗色模式引用编号适配 | ✅ 已完成 | #15 |
| 16.7 | 多账号切换 UI 优化 | ✅ 已完成 | #16 |
| 12.6 | 卸载程序命名优化 | ✅ 已完成 | #12 |

### P4 — 大型功能（待规划）

| 编号 | 内容 | 预估工时 | Issue |
|------|------|---------|-------|
| 14.7 | 三层图谱架构 | 16h+ | #14 |
| 14.9 | 实体/关系人工编辑 | 12h+ | #14 |
| 17.9 | 一键 OCR 安装向导 | 16h+ | #17 |
| 17.10 | OCR 集成到文档处理管线 | 8h+ | #17 |

---

## 关键代码位置参考

| 功能 | 文件路径 |
|------|---------|
| Schema Migration | `backend/src/db/sqlite.rs` |
| System APIs | `backend/src/api/system.rs` |
| Rerank Configs | `backend/src/api/rerank_configs.rs` |
| Rerank Service | `backend/src/services/reranker.rs` |
| Retrieval Pipeline | `backend/src/services/retrieval_pipeline.rs` |
| Chat (rerank integration) | `backend/src/api/chat.rs` |
| Knowledge Extraction | `backend/src/services/knowledge_extraction.rs` |
| Knowledge Graph API | `backend/src/api/knowledge_graph.rs` |
| Embedding Configs | `backend/src/api/embedding_configs.rs` |
| Local Doc Processor | `backend/src/services/local_doc_processor.rs` |
| Backend Manager | `apps/client/lib/core/services/backend_manager.dart` |
| API Client | `apps/client/lib/core/api/api_client.dart` |
| Chat Page | `apps/client/lib/features/chat/pages/chat_page.dart` |
| Knowledge Graph Page | `apps/client/lib/features/search/pages/knowledge_graph_page.dart` |
| OCR Settings Page | `apps/client/lib/features/settings/pages/ocr_settings_page.dart` |
| Data Management Page | `apps/client/lib/features/settings/pages/data_management_page.dart` |
| Dashboard (account UI) | `apps/client/lib/features/dashboard/pages/dashboard_page.dart` |
| InnoSetup Installer | `apps/client/windows/installer.iss` |
| build.rs (sqlite_mode) | `backend/build.rs` |
