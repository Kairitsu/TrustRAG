# TrustRAG Issue #12 - #17 深度分析与开发 TODO List

> 创建时间: 2026-05-28
> Issue 提交者: Kairitsu
> 协议: RIPER-5

---

## 总览

| Issue | 标题 | 优先级 | 复杂度 | 预估工时 |
|-------|------|--------|--------|----------|
| #12 | Windows 端卸载/升级数据污染 | P0 (阻断性) | 高 | 3-5天 |
| #13 | 新增 Rerank 重排模型配置 | P1 (功能增强) | 中高 | 3-4天 |
| #14 | 完善知识图谱功能 | P2 (大型功能) | 极高 | 2-3周 |
| #15 | 优化引用编号视觉显示 | P3 (UI优化) | 低 | 0.5天 |
| #16 | 多账号数据隔离 | P1 (重要) | 高 | 3-5天 |
| #17 | 桌面端内置 PDF/DOCX 解析 | P1 (重要) | 中高 | 2-3天 |

---

## Issue #12: Windows 端卸载/升级数据污染（P0 阻断性）

### 问题分析

**根因**: 旧版 SQLite 数据库 schema 与新版不兼容，卸载未清理 AppData，token/用户一致性未校验。

**现状评估**:
- 后端已有 `migrations_sqlite/init.sql` 但只有 `CREATE TABLE IF NOT EXISTS`，不支持增量迁移
- 桌面端使用 SQLite（`desktop` feature），无正式 schema version 管理
- 卸载器为 InnoSetup 默认生成的 `unins000.exe`，不处理 AppData 数据
- 启动时不校验 token 对应用户是否存在于当前数据库

### TODO

#### 12.1 SQLite Schema Migration 机制
- [ ] 12.1.1 在 SQLite DB 中增加 `schema_version` 表（或使用 `PRAGMA user_version`）
- [ ] 12.1.2 编写增量迁移脚本框架（从 v1 到当前版本的所有 ALTER TABLE）
- [ ] 12.1.3 后端启动时自动检测 schema 版本并执行增量迁移
- [ ] 12.1.4 迁移失败时返回明确错误信息而非 500
- [ ] 12.1.5 添加 "备份后重置数据库" 的 API 端点

#### 12.2 Token/用户一致性校验
- [ ] 12.2.1 后端启动时校验 JWT token 中的 user_id 是否存在于当前 SQLite 数据库
- [ ] 12.2.2 `/model-configs`、`/embedding-configs` 等 API 遇到外键错误时返回具体错误而非 500
- [ ] 12.2.3 前端收到 "用户不存在" 错误时自动清除 token 并跳转登录页

#### 12.3 Windows 卸载器改进
- [ ] 12.3.1 InnoSetup 脚本中增加卸载时的数据清理选项（保留 vs 完全删除）
- [ ] 12.3.2 明确列出要清理的目录（AppData/Local/TrustRAG, trustrag.db 等）
- [ ] 12.3.3 卸载器界面提示哪些数据会被保留/删除
- [ ] 12.3.4 将卸载器重命名为更明确的名称

#### 12.4 应用内数据重置入口
- [ ] 12.4.1 后端增加 `/system/reset-local-data` API
- [ ] 12.4.2 前端设置页增加 "重置本地数据 / 修复本地环境" 按钮
- [ ] 12.4.3 重置前弹确认对话框，支持备份当前数据库文件

---

## Issue #13: 新增 Rerank 重排模型配置（P1 功能增强）

### 问题分析

**现状评估**:
- 后端 `reranker.rs` 已有完整的 Rerank 基础设施：
  - `RerankerProvider` trait（支持 LLM scoring 和 cross-encoder）
  - `HttpRerankerProvider`（兼容 Jina/Cohere API）
  - `ReRankConfig`（enable/top_n/method）
  - `retrieval_pipeline.rs` 已集成 rerank 开关
- **缺失**: 没有独立的 rerank 模型配置表和 API，没有前端配置 UI
- 用户目前只能通过 domain profile YAML 启用 rerank，且只能用 LLM scoring 方式

### TODO

#### 13.1 后端：Rerank Config 数据持久化
- [ ] 13.1.1 新建 migration `0019_rerank_configs.sql`：创建 `rerank_configs` 表
  - 字段: id, workspace_id, name, provider_type (llm/jina/cohere/custom), api_base_url, api_key, model_name, is_default, created_at, updated_at
- [ ] 13.1.2 同步更新 `migrations_sqlite/init.sql`
- [ ] 13.1.3 新建 `backend/src/api/rerank_configs.rs`：CRUD API
  - POST /rerank-configs（创建）
  - GET /rerank-configs（列表）
  - PUT /rerank-configs/:id（更新）
  - DELETE /rerank-configs/:id（删除）
  - POST /rerank-configs/:id/test（测试连接）
  - PUT /rerank-configs/:id/default（设为默认）

#### 13.2 后端：Rerank 集成到检索流程
- [ ] 13.2.1 修改 `retrieval_pipeline.rs`：从数据库加载默认 rerank 配置
- [ ] 13.2.2 支持 workspace 级别的 rerank 开关和参数（初始召回数、rerank 保留数、超时、降级策略）
- [ ] 13.2.3 rerank 调用失败时自动降级到 embedding-only 检索，并记录日志
- [ ] 13.2.4 在检索结果中保留 rerank_score、原始排名、rerank 后排名等调试信息

#### 13.3 后端：模型类型校验
- [ ] 13.3.1 在 embedding config 的测试连接中，检测到明显 rerank 模型名称（qwen3-rerank、gte-rerank 等）时返回提示
- [ ] 13.3.2 将服务商返回的 "Unsupported model" 错误转换为更明确的用户提示

#### 13.4 前端：Rerank 配置 UI
- [ ] 13.4.1 在 `model_config_page.dart` 中新增 "重排模型" Tab 或分区
- [ ] 13.4.2 实现 rerank 配置的增删改查 UI
- [ ] 13.4.3 实现测试连接按钮
- [ ] 13.4.4 实现设为默认按钮
- [ ] 13.4.5 明确区分 embedding 模型和 rerank 模型，避免误配

#### 13.5 前端：工作区 Rerank 设置
- [ ] 13.5.1 在工作区设置或检索设置中增加 rerank 开关
- [ ] 13.5.2 配置项：是否启用、初始召回数、rerank 保留数、超时时间、失败时自动降级

---

## Issue #14: 完善知识图谱功能（P2 大型功能）

### 问题分析

**现状评估**:
- 后端 `knowledge_graph.rs` 已有 API 框架（get_graph, list_entities），能读取 entities 和 entity_relations 表
- 数据库已有 `entities` 和 `entity_relations` 表结构
- **核心缺失**: 没有从文档中抽取实体/关系的业务逻辑（数据生成链路完全缺失）
- 前端图谱页已有 UI 壳但永远显示 "暂无图谱数据"

### TODO（分三个层级实现）

#### 14.1 第一层：基础文档关联图（无需 LLM）
- [ ] 14.1.1 基于文档 metadata（标签、目录、文件名）生成文档节点和基础关联
- [ ] 14.1.2 前端图谱页展示文档间的基础网络（共同标签、同目录等关系）
- [ ] 14.1.3 前端增加 "生成图谱" / "重新生成图谱" 按钮（替代仅有的刷新按钮）

#### 14.2 第二层：LLM 驱动的实体/关系抽取
- [ ] 14.2.1 新建 `backend/src/services/knowledge_extraction.rs`：实体/关系抽取服务
- [ ] 14.2.2 实现基于 LLM 的 chunk 级实体抽取（prompt 模板 + 结构化输出解析）
- [ ] 14.2.3 实现基于 LLM 的关系抽取
- [ ] 14.2.4 实现实体去重与归一化逻辑
- [ ] 14.2.5 绑定来源证据（来源文档、来源 chunk、页码、原文片段）
- [ ] 14.2.6 写入 entities 和 entity_relations 表

#### 14.3 后端 API 扩展
- [ ] 14.3.1 新增 POST `/workspaces/:ws_id/knowledge-graph/generate` 触发图谱生成
- [ ] 14.3.2 新增 POST `/workspaces/:ws_id/knowledge-graph/generate/:doc_id` 对单个文档生成
- [ ] 14.3.3 新增 DELETE `/workspaces/:ws_id/knowledge-graph` 清空并重建
- [ ] 14.3.4 新增 GET `/workspaces/:ws_id/knowledge-graph/status` 图谱生成状态查询
- [ ] 14.3.5 图谱生成状态枚举：未生成/等待生成/实体抽取中/关系抽取中/归一化中/完成/失败

#### 14.4 前端图谱页改进（参考 Obsidian Graph View）
- [ ] 14.4.1 节点拖拽、缩放、平移交互
- [ ] 14.4.2 按实体类型、文档、标签过滤
- [ ] 14.4.3 节点大小根据连接数调整，按类型着色
- [ ] 14.4.4 点击节点显示详情（来源文档、关联实体、原文片段）
- [ ] 14.4.5 点击关系边显示关系说明和来源证据
- [ ] 14.4.6 局部邻域图 + 全局图谱视图
- [ ] 14.4.7 图谱生成状态 UI（进度条、错误提示、日志查看）

#### 14.5 模型配置扩展（可选，后期）
- [ ] 14.5.1 新增 "知识抽取模型" 配置分类
- [ ] 14.5.2 支持模式：LLM 抽取（默认）/ 专门 NER 模型 / 混合模式
- [ ] 14.5.3 未配置专门模型时默认使用已配置的 LLM

---

## Issue #15: 优化引用编号视觉显示（P3 UI优化）

### 问题分析

**现状评估**: 引用编号 [5][6] 可点击但与正文样式差异小，不易识别。

### TODO

#### 15.1 引用编号样式优化
- [ ] 15.1.1 在 chat 回答渲染中，将引用编号 `[N]` 渲染为 badge/chip 样式
  - 浅色圆角背景、主题色文字、适当 padding
- [ ] 15.1.2 hover 效果：背景变色、手型光标
- [ ] 15.1.3 确保暗色模式下的可读性
- [ ] 15.1.4 保持右侧审核面板的现有交互逻辑不变

---

## Issue #16: 多账号数据隔离（P1 重要）

### 问题分析

**现状评估**:
- 桌面端使用单一 SQLite 数据库（trustrag.db）
- 切换账号后继续复用同一数据库，但数据属于不同 user_id
- 后端 API 层面虽然通过 `owner_id` / `workspace_members` 做了权限过滤，但本地缓存和 UI 状态未隔离
- 前端 `SharedPreferences` 中只存一套 token，不区分账号

### TODO

#### 16.1 后端数据隔离方案
- [ ] 16.1.1 **方案评估**:
  - 方案A：按 user_id 分目录存储不同 SQLite DB（`user_data/{user_id}/trustrag.db`）
  - 方案B：单 DB 但所有查询严格按 user_id 过滤（已部分实现）
  - **推荐方案A**：物理隔离更彻底，避免旧数据泄露
- [ ] 16.1.2 实现按用户 ID 切换数据库路径的逻辑
- [ ] 16.1.3 用户首次登录时自动初始化专属数据库

#### 16.2 前端多账号支持
- [ ] 16.2.1 `SharedPreferences` 改为按账号 ID 存储 token 和配置
- [ ] 16.2.2 实现账号列表管理（已登录的账号记忆）
- [ ] 16.2.3 设置页或侧边栏增加账号切换入口
- [ ] 16.2.4 切换账号时完全重新加载对应账号的数据空间

#### 16.3 退出登录逻辑完善
- [ ] 16.3.1 区分 "退出登录但保留数据" 和 "退出登录并清除数据"
- [ ] 16.3.2 清除数据时删除该账号在本机的缓存、索引、数据库和敏感配置

---

## Issue #17: 桌面端内置 PDF/DOCX 解析（P1 重要）

### 问题分析

**现状评估**:
- 后端 `local_doc_processor.rs` 已有 `parse_pdf`（基于 lopdf）和 `parse_docx_fallback`
- `desktop` feature 已启用 `local-pdf`，**lopdf 已内置**
- `parse_local()` 函数支持 txt/md/html/pdf/docx
- **实际问题**：需要确认前端桌面模式是否正确调用了本地解析路径，还是直接提示"不支持"
- 当前 lopdf 只能解析文本型 PDF，不支持扫描版/图片型 PDF（需 OCR）

### TODO

#### 17.1 确认并修复桌面端 PDF/DOCX 解析链路
- [ ] 17.1.1 排查前端桌面模式上传 PDF 时的实际调用路径
- [ ] 17.1.2 确认后端 desktop build 是否正确启用了 `local-pdf` feature
- [ ] 17.1.3 如果是前端拦截了文件类型导致提示 "不支持"，移除该拦截
- [ ] 17.1.4 确保 `document.rs` 中的 `process_document_inner` 在桌面模式下正确走本地解析路径

#### 17.2 改进本地 PDF 解析质量
- [ ] 17.2.1 改进 `parse_pdf_with_lopdf` 的文本提取质量（当前可能丢失部分格式信息）
- [ ] 17.2.2 添加 PDF 解析失败时的详细错误信息
- [ ] 17.2.3 对于无法提取文本的 PDF（扫描版），返回明确提示而非空文本

#### 17.3 DOCX 解析改进
- [ ] 17.3.1 评估当前 `parse_docx_fallback` 的能力（可能只是基础 XML 提取）
- [ ] 17.3.2 考虑引入更完善的 docx 解析库（如 `docx-rs` 或自行解析 XML）
- [ ] 17.3.3 支持表格、列表等复杂格式的 Markdown 转换

#### 17.4 OCR 支持（后期，可作为 v0.3.x 规划）
- [ ] 17.4.1 设计本地 OCR 组件架构（插件式，支持多种 OCR 引擎）
- [ ] 17.4.2 实现向导式 OCR 组件安装流程
- [ ] 17.4.3 集成 PaddleOCR / RapidOCR / Tesseract 作为候选方案
- [ ] 17.4.4 OCR 配置页面（状态、引擎选择、测试、卸载）
- [ ] 17.4.5 自动检测文件是否需要 OCR 并提示用户

---

## 实施建议

### 优先级排序

```
第一批（紧急修复 + 快速见效）:
  #12（P0）→ 数据污染是阻断性问题，影响新用户体验
  #15（P3 但工时极低）→ 0.5天即可完成，快速提升体验
  #17.1（P1 部分）→ 确认并修复 PDF 链路，可能只需小改动

第二批（核心功能增强）:
  #13（P1）→ Rerank 配置，基础设施已就绪，主要是 API + UI
  #16（P1）→ 多账号隔离，涉及数据架构调整

第三批（大型功能迭代）:
  #14（P2）→ 知识图谱，建议分层级逐步实现
  #17.4（后期）→ OCR 支持作为未来版本规划
```

### 版本规划建议

```
v0.2.6-beta:
  - Issue #12（schema migration + token 校验 + 数据重置）
  - Issue #15（引用编号样式）
  - Issue #17.1-17.2（确认修复 PDF 链路）

v0.3.0:
  - Issue #13（Rerank 模型配置 + 两阶段检索）
  - Issue #16（多账号数据隔离）

v0.3.x / v0.4.0:
  - Issue #14（知识图谱分层实现）
  - Issue #17.4（OCR 支持）
```

---

## 与已有代码的关系

| Issue | 已有基础 | 需新增 |
|-------|---------|--------|
| #12 | `migrations_sqlite/init.sql`, InnoSetup 脚本 | schema version 管理、增量迁移、重置 API |
| #13 | `reranker.rs`(完整 trait+impl), `retrieval_pipeline.rs`(已集成开关) | rerank_configs 表/API/UI |
| #14 | `knowledge_graph.rs`(读取 API), entities/entity_relations 表 | 实体抽取服务、生成触发 API、图谱 UI |
| #15 | chat 回答渲染组件 | badge 样式 CSS/Widget |
| #16 | API 层 owner_id 权限过滤 | 物理数据隔离、多账号 UI |
| #17 | `local_doc_processor.rs`(lopdf+docx), `desktop` feature | 排查前端拦截、改进解析质量 |
