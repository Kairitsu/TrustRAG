# TrustRAG P4 大型功能拆分 TODO List

> 创建时间: 2026-05-29
> 最后更新: 2026-05-29
> 状态: **全部完成** ✅
> 基于: issues-12-17-todo.md 中 P4 剩余任务的深度拆分

---

## 总览

| 编号 | 功能 | Issue | 子任务数 | 预估总工时 | 优先级 |
|------|------|-------|---------|-----------|--------|
| 14.9 | 实体/关系人工编辑 | #14 | 8 | 14h | 1 |
| 14.7 | 三层图谱架构 | #14 | 7 | 18h | 2 |
| 17.10 | OCR 集成到文档处理管线 | #17 | 6 | 10h | 3 |
| 17.9 | 一键 OCR 安装向导 | #17 | 5 | 18h | 4 |

---

## 14.9 实体/关系人工编辑

> **目标**: 用户可以在知识图谱页面手动编辑实体和关系
> **依赖**: 无（可独立开发）

### 子任务

- [x] **14.9.1 后端: 实体 CRUD API** (2h)
  - `PUT /workspaces/{ws_id}/knowledge-graph/entities/{id}` — 编辑实体名称/类型
  - `DELETE /workspaces/{ws_id}/knowledge-graph/entities/{id}` — 删除实体（级联删除关联关系）
  - `POST /workspaces/{ws_id}/knowledge-graph/entities` — 新增实体
  - 文件: `backend/src/api/knowledge_graph.rs`

- [x] **14.9.2 后端: 关系 CRUD API** (2h)
  - `PUT /workspaces/{ws_id}/knowledge-graph/relations/{id}` — 编辑关系类型/权重/描述
  - `DELETE /workspaces/{ws_id}/knowledge-graph/relations/{id}` — 删除关系
  - `POST /workspaces/{ws_id}/knowledge-graph/relations` — 新增关系（指定源/目标实体）
  - 文件: `backend/src/api/knowledge_graph.rs`

- [x] **14.9.3 后端: 实体合并 API** (1.5h)
  - `POST /workspaces/{ws_id}/knowledge-graph/entities/merge` — 合并重复实体
  - 逻辑: 选择保留的实体 → 将被合并实体的所有关系转移 → 删除被合并实体
  - 需要事务保证一致性
  - 文件: `backend/src/api/knowledge_graph.rs`

- [x] **14.9.4 前端: KnowledgeGraphService 扩展** (1h)
  - 在 `knowledge_graph_provider.dart` 中添加 CRUD 方法
  - `createEntity()`, `updateEntity()`, `deleteEntity()`
  - `createRelation()`, `updateRelation()`, `deleteRelation()`
  - `mergeEntities()`

- [x] **14.9.5 前端: 实体编辑对话框** (2h)
  - 编辑名称、类型（下拉选择预定义类型 + 自定义输入）
  - 从 NodeInfoCard 的"编辑"按钮触发
  - 删除确认对话框（提示将删除多少条关联关系）
  - 文件: `knowledge_graph_page.dart`

- [x] **14.9.6 前端: 关系编辑对话框** (2h)
  - 编辑关系类型、权重/置信度（滑块 0-100%）、描述
  - 从 EdgeInfoCard 的"编辑"按钮触发
  - 新增关系: 选择源实体 + 目标实体（搜索选择器）
  - 文件: `knowledge_graph_page.dart`

- [x] **14.9.7 前端: 新增实体入口** (1.5h)
  - 图谱页面 toolbar 添加"新增实体"按钮
  - 对话框: 名称、类型、可选关联文档
  - 新实体创建后自动刷新图谱
  - 文件: `knowledge_graph_page.dart`

- [x] **14.9.8 后端+前端测试** (2h)
  - 后端: 实体/关系 CRUD 单元测试
  - 前端: 编辑对话框基础验证
  - 编译检查 `cargo check` + `flutter analyze`

---

## 14.7 三层图谱架构

> **目标**: 实现文档网络层 + 语义图谱层 + LLM 知识图谱层的分层架构
> **依赖**: 14.9（编辑功能先完成可以方便测试三层图谱数据）

### 子任务

- [x] **14.7.1 数据模型: graph_layer 字段** (1h)
  - `entities` 表新增 `graph_layer TEXT NOT NULL DEFAULT 'knowledge'`
  - `entity_relations` 表新增 `graph_layer TEXT NOT NULL DEFAULT 'knowledge'`
  - 层级值: `'document'`(文档网络), `'semantic'`(语义图谱), `'knowledge'`(LLM知识)
  - SQLite migration v7→v8
  - 文件: `backend/src/db/sqlite.rs`, `backend/migrations_sqlite/init.sql`

- [x] **14.7.2 第一层: 文档网络图谱** (4h)
  - 自动生成: 文档上传/处理完成时创建文档节点
  - 文档节点: entity_type='document', name=文档标题
  - 标签节点: entity_type='tag', 从文档 tags 字段提取
  - 关系: document→tag (belongs_to), document→document (同目录 co_located)
  - 触发时机: 文档处理完成时在 chunking/embedding 之后自动生成
  - 文件: `backend/src/services/knowledge_extraction.rs` 新增 `build_document_layer()`

- [x] **14.7.3 第二层: 语义图谱** (4h)
  - 基于 embedding 相似度自动生成实体间语义关系
  - chunk 级别: 同一文档内相似 chunk 关系 (相似度 > 0.85)
  - 文档级别: 不同文档间相似关系 (平均 chunk 相似度 > 0.7)
  - 关系类型: `semantically_similar`, `related_to`
  - 异步任务: `POST /workspaces/{ws_id}/knowledge-graph/build-semantic-layer`
  - 文件: `backend/src/services/knowledge_extraction.rs` 新增 `build_semantic_layer()`

- [x] **14.7.4 后端: 图谱层级过滤 API** (2h)
  - `GET /workspaces/{ws_id}/knowledge-graph?layers=document,semantic,knowledge`
  - 支持按层级筛选返回的节点和边
  - 默认返回所有层（向后兼容）
  - 文件: `backend/src/api/knowledge_graph.rs`

- [x] **14.7.5 前端: 层级切换 UI** (3h)
  - 图谱视图 toolbar 添加三个层级 Toggle 按钮
  - 文档网络层 (蓝色) / 语义图谱层 (绿色) / LLM 知识层 (紫色)
  - 每层可独立开关显示
  - 不同层级的节点/边使用不同视觉样式（颜色、虚线/实线、透明度）
  - 文件: `knowledge_graph_page.dart`, `knowledge_graph_provider.dart`

- [x] **14.7.6 前端: 层级统计展示** (2h)
  - 图谱统计面板显示各层节点数/关系数
  - 生成操作区分层级: "生成文档网络" / "生成语义图谱" / "生成知识图谱"
  - 文件: `knowledge_graph_page.dart`

- [x] **14.7.7 测试与集成** (2h)
  - migration 测试（v7→v8）
  - 文档网络层生成测试
  - 层级过滤 API 测试
  - 编译检查

---

## 17.10 OCR 集成到文档处理管线

> **目标**: 扫描版 PDF 上传时自动调用本地 OCR 提取文本
> **依赖**: 无（可独立开发）

### 子任务

- [x] **17.10.1 后端: OCR 执行器模块** (2h)
  - 新建 `backend/src/services/ocr_executor.rs`
  - `async fn run_tesseract(image_path: &Path, lang: &str) -> Result<String>`
  - `async fn run_paddleocr(image_path: &Path) -> Result<String>`
  - `async fn detect_available_ocr() -> OcrBackend` (优先级: PaddleOCR > Tesseract)
  - 文件: `backend/src/services/ocr_executor.rs`

- [x] **17.10.2 后端: PDF 页面转图片** (2h)
  - 在 `local_doc_processor.rs` 中添加 PDF→图片转换逻辑
  - 使用 `pdfium-render` 或 `pdf-extract` 的图像提取
  - 备选方案: 调用系统 `pdftoppm` / `ghostscript` 将每页转为 PNG
  - 临时图片存储到 temp 目录，OCR 完成后清理
  - Feature gate: `#[cfg(feature = "desktop")]`

- [x] **17.10.3 后端: 集成到文档处理流程** (2h)
  - 在 `parse_local()` 中: PDF 文本为空 → 检测 OCR 可用性 → 调用 OCR
  - OCR 结果替换空白文本，继续正常 chunking/embedding 流程
  - 处理状态增加 `ocr_processing` 状态
  - 元数据记录: `ocr_used: true`, `ocr_backend: "tesseract"`, `ocr_pages: N`
  - 文件: `backend/src/services/local_doc_processor.rs`

- [x] **17.10.4 前端: OCR 处理进度展示** (1.5h)
  - 文档上传时如果触发 OCR，显示 "正在 OCR 识别..." 进度
  - 处理完成后显示 OCR 元数据（使用了哪个 OCR 引擎、处理了多少页）
  - 文件: 文档上传相关 UI

- [x] **17.10.5 后端: OCR 配置项** (1h)
  - 系统设置中添加 OCR 自动启用开关
  - OCR 语言配置（默认 chi_sim+eng）
  - 最大 OCR 页数限制（避免超大文件阻塞）
  - 文件: `backend/src/api/system.rs`

- [x] **17.10.6 测试** (1.5h)
  - OCR 执行器单元测试（mock）
  - PDF→图片转换测试
  - 编译检查 `cargo check --features desktop`

---

## 17.9 一键 OCR 安装向导

> **目标**: 用户在 OCR 设置页面一键安装 OCR 引擎
> **依赖**: 17.10（先完成管线集成，确保 OCR 安装后能实际工作）

### 子任务

- [x] **17.9.1 后端: 平台检测与安装命令** (2h)
  - `GET /system/ocr-install-options` — 返回当前平台推荐的 OCR 安装方式
  - 检测 OS (Windows/macOS/Linux) + 包管理器 (brew/apt/choco/winget)
  - 返回: 可用的安装方式列表 + 推荐安装方式 + 安装命令
  - 文件: `backend/src/api/system.rs`

- [x] **17.9.2 后端: 自动安装执行** (4h)
  - `POST /system/ocr-install` — 执行 OCR 安装
  - 支持模式: `package_manager`(调用 apt/brew/choco) / `download`(下载预编译二进制)
  - 安装过程: 异步任务 + WebSocket 或轮询进度
  - 安装步骤: 下载 → 解压 → 验证 → 配置 PATH
  - Tesseract 自动安装:
    - macOS: `brew install tesseract tesseract-lang`
    - Ubuntu: `apt install tesseract-ocr tesseract-ocr-chi-sim`
    - Windows: 下载 UB-Mannheim 安装包 + 自动安装
  - 文件: `backend/src/api/system.rs`

- [x] **17.9.3 前端: OCR 安装向导 UI** (4h)
  - 重新设计 `ocr_settings_page.dart`
  - Step 1: 检测当前状态（已安装/未安装/版本过旧）
  - Step 2: 选择 OCR 引擎（Tesseract 推荐 / PaddleOCR / RapidOCR）
  - Step 3: 选择安装方式（自动安装 / 手动安装指导 / 离线包导入）
  - Step 4: 安装进度条 + 实时日志
  - Step 5: 安装完成验证（自动测试一张图片）
  - 文件: `apps/client/lib/features/settings/pages/ocr_settings_page.dart`

- [x] **17.9.4 前端: 离线安装包导入** (4h)
  - 文件选择器: 选择本地 Tesseract .exe / .tar.gz / .deb 安装包
  - 自动解压 + 配置
  - 语言包管理: 检测已安装语言 + 下载/导入额外语言包
  - 文件: `ocr_settings_page.dart`

- [x] **17.9.5 测试** (4h)
  - 平台检测逻辑测试
  - 安装命令生成测试
  - 前端向导流程测试
  - 编译检查

---

## 执行顺序建议

```
Phase 1 (可并行):
  14.9.1 → 14.9.2 → 14.9.3 → 14.9.4 → 14.9.5 → 14.9.6 → 14.9.7 → 14.9.8
  17.10.1 → 17.10.2 → 17.10.3 → 17.10.4 → 17.10.5 → 17.10.6

Phase 2 (依赖 Phase 1):
  14.7.1 → 14.7.2 → 14.7.3 → 14.7.4 → 14.7.5 → 14.7.6 → 14.7.7

Phase 3 (依赖 17.10):
  17.9.1 → 17.9.2 → 17.9.3 → 17.9.4 → 17.9.5
```

---

## 关键技术决策

### 14.7 三层图谱
- `graph_layer` 字段使用 TEXT 而非 INTEGER，方便扩展
- 第一层（文档网络）在文档处理完成时自动生成，无需用户手动触发
- 第二层（语义图谱）需要用户手动触发，因为需要计算 embedding 相似度（资源密集）

### 14.9 实体编辑
- 合并实体时使用数据库事务确保一致性
- 删除实体时级联删除所有关联关系（已通过 FOREIGN KEY ON DELETE CASCADE 保证）

### 17.10 OCR 管线
- OCR 仅在桌面端 `#[cfg(feature = "desktop")]` 下启用
- 优先使用 PaddleOCR（中文效果更好），Tesseract 作为备选
- PDF→图片转换优先调用系统工具（pdftoppm），避免引入重量级 Rust 依赖

### 17.9 OCR 安装向导
- 自动安装需要系统权限（sudo/管理员），前端需明确提示
- Windows 安装 Tesseract 最复杂，需要下载 .exe 安装包并自动执行
- 离线安装是企业环境必需功能
