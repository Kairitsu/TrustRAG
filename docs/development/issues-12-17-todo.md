# TrustRAG Issue #12 - #17 开发 TODO List

> 创建时间: 2026-05-28
> 最后更新: 2026-05-28 (深入审查后更新)
> Issue 提交者: Kairitsu
> 审查状态: 逐文件、逐需求点深入审查完成

---

## 总览

| Issue | 标题 | 状态 | 完成度 |
|-------|------|------|--------|
| #12 | Windows 端卸载/升级数据污染 | 大部分完成 | 85% |
| #13 | 新增 Rerank 重排模型配置 | 大部分完成 | 90% |
| #14 | 完善知识图谱功能 | 大部分完成 | 80% |
| #15 | 优化引用编号视觉显示 | ✅ 完成 | 100% |
| #16 | 多账号数据隔离 | 部分完成 | 40% |
| #17 | 桌面端内置 PDF/DOCX 解析 | 大部分完成 | 85% |

---

## Issue #12: Windows 端卸载/升级数据污染

### 已完成 ✅

- [x] **12.1 SQLite Schema Migration**
  - `migrations_sqlite/init.sql` 使用 `PRAGMA user_version` 做增量迁移
  - 后端启动时自动检测并执行迁移
- [x] **12.2 Token/用户一致性校验**
  - 后端 `system.rs` 新增 `/system/validate-token` 端点
  - 错误处理改进，返回明确提示而非 500
- [x] **12.3 应用内数据管理**
  - 后端 `/system/db-info`、`/system/backup-db`、`/system/reset-db` API
  - 前端 `DataManagementPage` 实现 + 导航集成到设置页

### 剩余缺口 ❌

- [ ] **12.4** InnoSetup 卸载器改进（卸载时清理 AppData 选项）
- [ ] **12.5** 卸载器界面增加数据保留/删除提示

---

## Issue #13: 新增 Rerank 重排模型配置

### 已完成 ✅

- [x] **13.1 后端 rerank_configs CRUD**
  - 文件: `backend/src/api/rerank_configs.rs`
  - 完整 API: create/list/update/delete/test-connection/set-default
  - 数据库: PostgreSQL migration `0019_rerank_configs.sql` + `0020_rerank_extra_params.sql`
  - SQLite: `init.sql` 同步更新
- [x] **13.2 后端 Reranker 服务**
  - 文件: `backend/src/services/reranker.rs`
  - `RerankerProvider` trait + `HttpRerankerProvider`（兼容 Jina/Cohere）
  - LLM scoring 重排备选方案
  - 完整单元测试（8个测试用例）
- [x] **13.3 检索管线集成**
  - 文件: `backend/src/services/retrieval_pipeline.rs`
  - `run_with_reranker()` 完整实现
  - 自动降级: rerank 失败时回退 embedding-only + 记录 `rerank_degraded`/`rerank_error`
  - Trace 数据: `embedding_rank` + `rerank_score` 保留在 `ScoredChunkRef`
- [x] **13.4 Chat API 集成**
  - 文件: `backend/src/api/chat.rs`
  - `load_default_rerank()` 从 DB 自动加载默认 rerank 配置
  - 流式和非流式响应均传递 `embedding_rank` + `rerank_score`
- [x] **13.5 模型类型校验**
  - 文件: `backend/src/api/embedding_configs.rs` 第146行
  - `is_likely_rerank_model()` 函数: 检测 rerank/re-rank/reranker/bge-reranker/jina-reranker 等模式
  - 创建 embedding 配置时拦截 + 测试连接失败时智能提示
- [x] **13.6 前端模型配置 UI**
  - 文件: `apps/client/lib/features/settings/pages/model_config_page.dart`
  - 3个Tab: LLM 模型 / 嵌入模型 / Rerank 模型
  - Rerank 完整 CRUD 对话框（provider/model/endpoint/key/topN/recallK/fallback）
  - 测试连接 + 设为默认 + 详细错误弹窗
- [x] **13.7 前端 Rerank Provider**
  - 文件: `apps/client/lib/features/settings/providers/rerank_config_provider.dart`
  - 完整状态管理: load/create/update/delete/testConnection/setDefault
- [x] **13.8 引用面板展示 Rerank 信息**
  - 前端 `Citation` 类新增 `embeddingRank` + `rerankScore` 字段
  - `_CitationPanel` 展示 embedding 排名和 rerank 分数

### 剩余缺口 ❌

- [ ] **13.9** Rerank 配置中添加 `timeout` 参数（issue 明确提到"rerank 超时时间"）
  - 涉及: `rerank_configs.rs` + `reranker.rs` + 前端对话框 + DB migration
- [ ] **13.10** `rerank_configs.rs` 第241行 `#[cfg(sqlite_mode)]` 条件编译可能未在 Cargo.toml 定义
  - 需要确认 `updated_at` 自动更新是否在 SQLite 模式下正常工作
- [ ] **13.11** 工作区级别的 rerank 开关（目前只有用户全局默认，不能按工作区独立配置启用/禁用）

---

## Issue #14: 完善知识图谱功能

### 已完成 ✅

- [x] **14.1 后端知识抽取服务**
  - 文件: `backend/src/services/knowledge_extraction.rs`
  - LLM 驱动的实体/关系抽取（chunk 级处理）
  - 实体去重归一化（LOWER(name) 匹配）
  - 来源文档/chunk 绑定
  - 单元测试（5个测试用例）
- [x] **14.2 后端 API**
  - 文件: `backend/src/api/knowledge_graph.rs`
  - `GET /workspaces/{ws_id}/knowledge-graph` 获取图谱
  - `GET /workspaces/{ws_id}/knowledge-graph/entities` 实体列表
  - `POST /workspaces/{ws_id}/knowledge-graph/generate/{doc_id}` 单文档生成
  - `POST /workspaces/{ws_id}/knowledge-graph/generate-all` 全部文档生成
  - `DELETE /workspaces/{ws_id}/knowledge-graph/reset` 清空图谱
  - `GET /workspaces/{ws_id}/knowledge-graph/stats` 统计信息
- [x] **14.3 前端图谱页面**
  - 文件: `apps/client/lib/features/search/pages/knowledge_graph_page.dart`
  - 交互式力导向图（`_InteractiveGraph` + `_GraphPainter`）
  - `_FilterableLegend`: 按实体类型过滤
  - `_NodeInfoCard`: 节点详情（类型徽章、入/出/总连接数、关联实体列表+滚动）
  - `_EdgeInfoCard`: 关系详情（源/目标节点、关系类型、置信度进度条）
  - 边点击检测（`_pointToSegmentDistance` 算法）
- [x] **14.4 图谱操作菜单**
  - PopupMenuButton: 「生成知识图谱」/「刷新图谱」/「清空图谱」
  - `_generateAll()`: 全局生成 + 进度指示 `_isGenerating`
  - `_resetGraph()`: 确认弹窗 + 清空
- [x] **14.5 空状态引导**
  - 无图谱数据时显示「生成知识图谱」FilledButton + 进度动画
  - 文案提示需要配置 LLM 模型
- [x] **14.6 错误状态**
  - loading 状态: CircularProgressIndicator
  - error 状态: 错误图标 + 错误信息展示
- [x] **14.7 单文档生成**
  - 文件: `apps/client/lib/features/documents/pages/documents_page.dart`
  - 文档 PopupMenuButton 添加「生成知识图谱」选项
  - `_generateGraphForDoc()` API 调用 + 进度反馈

### 剩余缺口 ❌

- [ ] **14.8** 图谱生成是同步阻塞的，大文档/多文档场景会 HTTP 超时
  - 应改为后台任务 + 进度轮询（需要 generation status table 或 SSE 推送）
- [ ] **14.9** `entity_relations` 的 `weight` 固定写入 1.0（`knowledge_extraction.rs` 第167行）
  - 应让 LLM 在抽取时输出 confidence，写入 weight 字段
- [ ] **14.10** 生成历史/错误日志不可查看（无持久化生成记录）
  - issue 建议: 查看图谱生成状态和错误日志
- [ ] **14.11** 节点拖拽功能未实现（issue 建议参考 Obsidian Graph View 的可拖拽布局）
  - 当前布局是静态计算的力导向位置
- [ ] **14.12** issue 建议的三层图谱（基础文档网络/语义图谱/知识图谱）只实现了第三层
  - 第一层（基于 metadata 的文档网络）未实现
  - 第二层（基于 embedding 的语义相似图）未实现
- [ ] **14.13** 实体/关系人工编辑功能未实现（新增/删除/合并/修改/审核标记）

---

## Issue #15: 优化引用编号视觉显示 ✅ 完成

- [x] 引用编号 `[N]` 渲染为 badge 样式（浅色背景 + 主题色文字 + 圆角）
- [x] 暗色模式适配
- [x] 保持原有交互逻辑

---

## Issue #16: 多账号数据隔离

### 已完成 ✅

- [x] **16.1 按账号 Token 存储**
  - 文件: `apps/client/lib/core/api/api_client.dart`
  - `_accountTokenKey(String email)`: per-account token key
  - `saveToken()`: 同时写入通用 key 和账号专属 key
  - `switchToAccount()`: 保存当前 token → 切换账号 → 恢复目标账号 token
  - `removeAccount()`: 清除账号专属 token
- [x] **16.2 账号列表管理**
  - `_accountListKey`: 已登录账号列表持久化
  - `setActiveAccount()` / `getActiveAccount()` / `getSavedAccounts()`
- [x] **16.3 账号切换 UI**
  - 文件: `apps/client/lib/features/dashboard/pages/dashboard_page.dart`
  - `_AccountMenuSheet`: 底部菜单展示已登录账号列表
  - 切换账号后 `checkAuthStatus()` 验证

### 核心缺口 ❌ (P0 高优先级)

- [ ] **16.4** 本地 SQLite 数据库未按账号隔离（**Issue 核心需求**）
  - 当前: 所有账号共用同一个 `trustrag.db` 文件
  - 期望: `user_data/{account_id}/trustrag.db` 物理隔离
  - 涉及文件: `backend/src/main.rs` + `apps/client/lib/core/services/backend_manager.dart`
  - 需要: 切换账号时重启/重连嵌入式后端（使用新 DB 路径）
- [ ] **16.5** 退出登录时缺少「清除本账号本地数据」选项
  - issue 明确要求区分:
    1. "退出登录但保留本账号本地数据"
    2. "退出登录并清除本账号本地数据"
- [ ] **16.6** 切换账号后 `BackendManager` 未重新初始化
  - 当前切换只替换了 token，数据库连接仍指向旧文件
  - 需要: 停止旧后端进程 → 启动新后端（指向新账号 DB）
- [ ] **16.7** 本地缓存/工作区状态/UI 状态未按账号隔离
  - `SharedPreferences` 中的 `selected_workspace_id` 等状态是全局共享的

---

## Issue #17: 桌面端内置 PDF/DOCX 解析

### 已完成 ✅

- [x] **17.1** DOCX 本地解析（`zip` crate 解析 word/document.xml 提取文本）
- [x] **17.2** PDF 本地解析（`lopdf` crate 内置）
- [x] **17.3** 桌面模式 feature flag 正确启用 `local-pdf`
- [x] **17.4** 后端 OCR 状态检测端点 `/system/ocr-status`
  - 文件: `backend/src/api/system.rs`
  - 检测 Tesseract 和 PaddleOCR 安装状态
  - 返回版本信息和安装建议
- [x] **17.5** 前端 OCR 组件管理页面
  - 文件: `apps/client/lib/features/settings/pages/ocr_settings_page.dart`
  - 状态横幅 + 工具卡片 + 平台安装指南
  - 导航已集成到设置页

### 剩余缺口 ❌

- [ ] **17.6** 扫描版 PDF 无法提取文本时缺少明确提示
  - lopdf 只能解析文本型 PDF，对扫描版应提示"需安装 OCR 组件"
- [ ] **17.7** `system.rs` 中 OCR 检测的 `bin_path` 字段固定为 `None`
  - 原计划使用 `which` crate，但未作为依赖添加

---

## 优先级排序（剩余工作）

```
P0 紧急: ✅ 全部完成
  #16.4-16.7  本地 SQLite 按账号物理隔离 + 后端重连（Issue #16 核心需求）

P1 重要: ✅ 全部完成
  #14.8     图谱生成异步化（大文档会超时）
  #14.9     置信度 weight 应由 LLM 输出

P2 增强: ✅ 全部完成
  #13.9     Rerank timeout 参数
  #13.11    工作区级 rerank 开关
  #16.5     退出登录清除数据选项（已在 P0 阶段一并完成）

P3 后期（待做）:
  #12.4-12.5  InnoSetup 卸载器改进
  #14.10-11   生成日志 + 节点拖拽
  #14.12-13   三层图谱 + 实体编辑
  #17.6-17.7  OCR 提示 + bin_path
```

---

## 文件索引

| 功能模块 | 关键文件 |
|---------|---------|
| Rerank 后端 | `backend/src/api/rerank_configs.rs`, `backend/src/services/reranker.rs` |
| Rerank 前端 | `apps/client/lib/features/settings/providers/rerank_config_provider.dart`, `model_config_page.dart` |
| 检索管线 | `backend/src/services/retrieval_pipeline.rs`, `backend/src/api/chat.rs` |
| 知识图谱后端 | `backend/src/api/knowledge_graph.rs`, `backend/src/services/knowledge_extraction.rs` |
| 知识图谱前端 | `apps/client/lib/features/search/pages/knowledge_graph_page.dart` |
| 多账号隔离 | `apps/client/lib/core/api/api_client.dart`, `dashboard_page.dart` |
| 数据管理 | `backend/src/api/system.rs`, `apps/client/lib/features/settings/pages/data_management_page.dart` |
| OCR 管理 | `backend/src/api/system.rs`, `apps/client/lib/features/settings/pages/ocr_settings_page.dart` |
| Embedding 校验 | `backend/src/api/embedding_configs.rs` (is_likely_rerank_model) |
| DB Migration | `backend/migrations_sqlite/init.sql`, `backend/migrations/0019_rerank_configs.sql` |
