# Changelog / 更新日志

All notable changes to this project will be documented in this file.

本文件记录项目的所有重要更改。

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.0.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

**How to release / 如何发布：**
1. Add a new `## [x.y.z] - YYYY-MM-DD` section at the top (below this header)
2. List changes under: Added, Changed, Fixed, Removed, Infrastructure, Security
3. `git tag vx.y.z && git push origin vx.y.z`

---

## [0.2.5-beta.3] - 2026-05-25

### Fixed / 修复
- 🐛 **Windows 版启动 panic 修复** — `evidence.rs` 和 `answer_status.rs` 路由使用了 Axum 0.7 的旧格式 `:message_id`，导致 Axum 0.8 启动时 panic，后端无法监听端口，前端无法连接。已全部修正为 `{message_id}` 格式。（Issue #10）

---

## [0.2.5-beta.2] - 2026-05-24

### Fixed / 修复
- 🐛 **SQLite 桌面模式启动失败** — `migrations_sqlite/init.sql` 只覆盖了 0001-0006 的表定义，缺少 0007-0017 的所有新增表（audit_trail, retrieval_traces, answer_versions, claim_reviews, answer_reviews, document_metadata, review_tasks, review_comments, source_reviews 等），导致嵌入式后端无法初始化数据库。
- 🧪 **测试** — desktop feature 编译通过，251 个测试全部 OK。

---

## [0.2.5-beta.1] - 2026-05-24

### Added / 新增
- 🔍 **Fuzzy Search 模式** — 新增 `SearchMode::Fuzzy`，使用 pg_trgm `word_similarity()` 实现容错搜索，非 PG 环境自动回退。
- 📋 **QueryPlan 扩展** — 新增 `RetrievalStrategy` 枚举（SingleMode/HybridFusion/CascadeFallback/MultiQueryMerge），`metadata_filters`、`query_variants`、`preferred_document_types` 字段。
- 📊 **RetrievalTrace 扩展** — 分离 dense/sparse/fuzzy/fused 结果，新增 `query_plan`、`claim_checks`、`final_context` 字段，`RetrievalTimings` 增加细分计时。
- 📄 **document_metadata 独立表** — 30+ typed columns 覆盖法律（jurisdiction, regulation_id）、金融（ticker_symbol, fiscal_year）、医学（doi, pmid, clinical_trial_id）等多领域。
- ⚡ **ReRankMethod 扩展** — 新增 `CrossEncoderHttp`、`LocalFastEmbed`、`ExternalApi` 重排方法。
- 🐛 **Debug API** — 新增 `GET /retrieval-traces/:id`、`GET /workspaces/:id/retrieval-traces`、`GET /messages/:id/retrieval-trace` 调试接口。
- ✅ **Review Workflow 表** — 新增 `review_tasks`（可分配、状态/优先级/标签）、`review_comments`（线程式评论）、`source_reviews`（来源多维评分）三张表。
- 🧪 **测试** — 新增 43 个单元测试，总计 240 个通过。

### Infrastructure / 基础设施
- 新增 3 个数据库迁移（0015~0017）

---

## [0.2.4] - 2026-05-22

### Added / 新增
- 👥 **团队协作** — 全新的团队工作区机制：创建/加入团队、邀请码系统、角色权限（owner/admin/editor/viewer）、成员管理。（Issue #7.5）
- 🔗 **内联可点击引用链接** — AI 回答正文中的引用标记 `[1]` `[9]` 渲染为可点击链接，直接打开右侧详情面板。无效引用编号自动过滤。（Issue #7.1）
- 🔽 **引用来源默认折叠** — 回答下方的引用来源区域改为 ExpansionTile 默认折叠，减少屏幕空间占用。（Issue #7.2）
- 📐 **侧栏宽度调整与折叠** — 左侧导航栏支持拖拽调整宽度（72~360px），一键折叠为图标模式，偏好持久化保存。（Issue #7.6）
- 🇰🇷 **韩语 UI** — 新增韩语（ko）完整本地化，覆盖全部 UI 文案。
- 🏢 **团队管理页** — 专属团队设置页面：邀请码管理、成员角色调整、所有权转让、团队解散。
- 🗄️ **后端团队 API** — 新增 `/workspaces/join`、`/regenerate-invite-code`、`/transfer-ownership` 接口，DB migration 新增 `type`/`invite_code` 字段。

### Changed / 变更
- 🔒 **权限中间件增强** — 团队工作区的模型配置操作限制为 admin 以上角色。
- 📖 **GitHub Pages 文档更新** — 新增团队协作指南、更新引用系统文档、API 参考和首页特性介绍。

### Fixed / 修复
- 🐛 修复后端 `workspaces.rs` 中 SQL 查询元组类型不匹配（invite_code/updated_at 类型位置互换）导致的编译错误。
- 🌐 修复引用相关硬编码中文文案，替换为 i18n 国际化版本。

---

## [0.2.2] - 2026-05-22

### Added / 新增
- 🌐 **多语言 UI（i18n）** — 完整的三语支持（中文/英文/日语），基于 Flutter 官方 l10n 框架，涵盖全部界面文本。
- 📄 **原生 PDF 解析** — 桌面/移动端使用 Rust 原生 PDF 解析器，无需依赖 Python 文档处理服务。（Issue #4.1）
- 🔄 **应用内更新检查** — 启动时自动检查 GitHub Releases 最新版本，支持跳过版本、稍后提醒，6 小时缓存避免频繁请求。
- 📊 **审核报告导出** — 审核记录页新增报告按钮，展示审核统计指标（通过率、总数等），支持 Markdown 格式导出。
- 🕸️ **知识图谱可视化** — 新增知识图谱页面，使用自定义力导向图（CustomPainter + InteractiveViewer），支持节点交互、图例、实体搜索。

### Changed / 变更
- 🎨 **全新应用图标** — 更换为蓝色六边形 TrustRAG 图标，覆盖 Android（5 密度 + 自适应）、iOS、macOS、Windows、Web 全平台。
- 🖼️ **README 横幅更新** — 所有语言版本的 README（EN/ZH/JA/TW）换用新设计的 banner 图。
- 📖 **GitHub Pages 文档大更新** — 新增审核报告、知识图谱、i18n 等功能的指南和 API 参考页面，同步中英文内容。

### Infrastructure / 基础设施
- 🔧 **VitePress 站点更新** — 新增 favicon、导航栏 logo、多语言文档页面。

---

## [0.2.1] - 2026-05-21

### Added / 新增
- 📋 **审核记录面板** — 全局审核记录列表页面，含状态统计卡片（通过/拒绝/存疑/待定），后端新增 `GET /reviews` 分页接口。（Issue #4.2）
- 📌 **引用右侧常驻面板** — 宽屏模式下引用详情显示在右侧面板（而非对话框），紧凑模式使用 BottomSheet。（Issue #4.3）
- 🔍 **调试日志完善** — Dio 拦截器记录所有 API 请求/响应/错误，后端管理器记录启动/健康检查，文档和聊天模块记录关键事件。（Issue #4.6）
- ↔️ **侧边栏宽度可拖拽** — 会话列表（180-400px）和引用面板（180-500px）支持拖拽调整宽度，宽度通过 SharedPreferences 持久化。（Issue #4.4）
- 📁 **资料库文件夹管理** — 基于 tags 的虚拟文件夹系统，支持创建文件夹、移动文档、按文件夹筛选，后端新增 PATCH 更新文档标签接口。（Issue #4.5）
- 👥 **团队协作成员管理** — 完整的 WorkspaceMembersPage：邀请成员（邮箱）、修改角色（owner/editor/viewer）、移除成员，权限控制。（Issue #4.7）
- 🧪 **测试** — 新增 48 个测试覆盖调试日志、侧边栏持久化、文件夹管理、成员权限逻辑。

---

## [0.2.0] - 2026-05-21

### Added / 新增
- 📱 **Android responsive layout / Android 响应式布局** — Chat page auto-switches between single-column (Drawer + AppBar) for screens <600px and dual-column for wider screens. SafeArea wrapping prevents status bar conflicts. (Issue #6)
- 📱 **Android 响应式布局** — 聊天页面自动在单栏（抽屉 + AppBar，<600px）和双栏（>=600px）之间切换。SafeArea 处理状态栏冲突。（Issue #6）
- 💾 **Workspace state persistence / 工作区状态持久化** — Automatically saves and restores last selected workspace across app restarts via SharedPreferences. (Issue #6)
- 💾 **工作区状态持久化** — 通过 SharedPreferences 自动保存和恢复上次选择的工作区。（Issue #6）
- 📄 **Desktop document format guidance / 桌面端文档格式引导** — Desktop mode now clearly indicates supported formats (TXT/MD/HTML) and guides users to server mode for PDF/DOCX parsing. File picker is restricted accordingly. (Issue #4)
- 📄 **桌面端文档格式引导** — 桌面模式明确提示支持格式（TXT/MD/HTML），引导用户使用服务器模式解析 PDF/DOCX。文件选择器相应限制。（Issue #4）
- 🧪 **Widget tests / Widget 测试** — Added 18 widget and unit tests covering responsive layout, workspace persistence, and document format validation.
- 🧪 **Widget 测试** — 新增 18 个测试覆盖响应式布局、工作区持久化和文档格式验证。
- 📋 **Development roadmap v3 / 开发路线图 v3** — Issue-driven iteration plan (v0.2.0–v0.5.0) with prioritized tasks and milestones.
- 📋 **开发路线图 v3** — Issue 驱动的迭代计划（v0.2.0–v0.5.0），含优先级排序和里程碑。

---

## [0.1.2] - 2026-05-19

### Fixed / 修复
- 🐛 **Android native library extraction / Android 原生库解压** — Add `android:extractNativeLibs="true"` to AndroidManifest.xml so the embedded Rust backend binary is properly extracted to `nativeLibraryDir` on install. Without this, Android 6+ keeps `.so` files compressed inside the APK, making them inaccessible to `Process.start()`. (Closes #5)
- 🐛 **Android 原生库解压** — 在 AndroidManifest.xml 中添加 `android:extractNativeLibs="true"`，确保嵌入式 Rust 后端二进制文件在安装时正确解压到 `nativeLibraryDir`。缺少此设置时，Android 6+ 会将 `.so` 文件压缩保存在 APK 内，导致 `Process.start()` 无法访问。（修复 #5）
- 🐛 **Improved error reporting / 改进错误提示** — Login and register now show actionable error messages (e.g. "Cannot connect to backend") instead of generic "Login failed" / "Registration failed" when the embedded backend is unavailable.
- 🐛 **改进错误提示** — 登录和注册在嵌入式后端不可用时，显示可操作的错误信息（如"无法连接到后端"），而非泛化的"登录失败"/"注册失败"。
- 🐛 **Backend health check / 后端健康检查** — BackendManager now performs HTTP health checks after startup to verify the backend is actually responding, with retry logic.
- 🐛 **后端健康检查** — BackendManager 启动后执行 HTTP 健康检查验证后端是否正常响应，支持重试逻辑。

---

## [0.1.1] - 2026-05-16

### Added / 新增
- 🎨 **AI provider icons / AI 提供商图标** — Model config and chat messages now show provider-specific icons (OpenAI, Claude, Gemini, etc.) instead of generic placeholders
- 🎨 **AI 提供商图标** — 模型配置和聊天消息现在显示提供商专属图标（OpenAI、Claude、Gemini 等），替代通用占位符
- 📋 **Message action bar / 消息操作栏** — Copy, retry, and edit buttons for AI responses
- 📋 **消息操作栏** — AI 回复支持复制、重试和编辑按钮

### Fixed / 修复
- 🐛 Fix double message sending on Enter key press / 修复按回车键重复发送消息
- 🐛 Fix Windows installer referencing wrong executable name / 修复 Windows 安装包引用错误的可执行文件名
- 🐛 Fix macOS bundle path from client.app to TrustRAG.app / 修复 macOS 应用包路径
- 🐛 Fix app title from "client" to "TrustRAG" across all platforms / 修复全平台应用标题
- 🐛 Remove unused import in desktop_auto_setup.dart / 移除未使用的导入

### Changed / 变更
- 🔧 Implement Issue #2 improvements + developer mode / 实现 Issue #2 改进 + 开发者模式

### Infrastructure / 基础设施
- 📚 Add VitePress documentation site with bilingual content / 添加 VitePress 双语文档站
- 📚 Overhaul README with modern layout and separate language files / 重构 README
- 📚 Add documentation site links to all README files / 添加文档站链接
- 📄 Replace abbreviated LICENSE with full Apache 2.0 text / 替换完整 Apache 2.0 许可证
- 🔧 Add test-build workflow for test branch validation / 添加 test 分支测试构建
- 🔧 Refactor release workflow with auto-generated notes from CHANGELOG / 重构发布流程

---

## [0.1.0] - 2026-05-15

### 🎉 Initial Release / 首次发布

TrustRAG is an AI-powered document Q&A system with built-in citation verification and trust scoring.

TrustRAG 是一个 AI 驱动的文档问答系统，内置引用验证和信任评分机制。

### Added / 新增
- 🖥️ **Multi-platform desktop app / 多平台桌面应用** — Windows, macOS, Linux, Android, iOS, Web all built from a single codebase
- 🖥️ **多平台桌面应用** — Windows、macOS、Linux、Android、iOS、Web 全平台一套代码构建
- 📦 **Self-contained desktop mode / 桌面端自包含模式** — Embedded SQLite backend with automatic local user setup, no external database required
- 📦 **桌面端自包含模式** — 内嵌 SQLite 后端，自动创建本地用户，无需外部数据库
- 🤖 **RAG pipeline / RAG 管线** — Retrieval-Augmented Generation with document-grounded answers and configurable LLM/Embedding providers
- 🤖 **RAG 管线** — 基于文档的检索增强生成，可配置 LLM/Embedding 提供商
- 📎 **Citation tracking / 引用追踪** — Every AI response includes traceable source citations with document, chunk, and page references
- 📎 **引用追踪** — 每条 AI 回复都包含可追溯的来源引用（文档、分块、页码）
- ✅ **Citation review / 引用审核** — Approve, reject, or flag citations for accuracy with review history
- ✅ **引用审核** — 通过、拒绝或标记引用的准确性，支持审核历史记录
- 🔍 **Full-text search / 全文搜索** — FTS5-powered search across all uploaded documents
- 🔍 **全文搜索** — 基于 FTS5 的全文档搜索
- 🪟 **Windows installer / Windows 安装包** — One-click Inno Setup `.exe` installer plus portable zip
- 🪟 **Windows 安装包** — Inno Setup 一键安装包 + 便携压缩版
- 🧠 **Knowledge graph / 知识图谱** — Entity and relation extraction with graph API
- 🧠 **知识图谱** — 实体与关系提取，提供图谱 API
- 🔌 **Plugin system / 插件系统** — Dynamic provider registry for LLM and Embedding management
- 🔌 **插件系统** — 动态提供商注册，管理 LLM 和 Embedding
- 👥 **Workspace collaboration / 工作区协作** — Multi-user workspace with member management
- 👥 **工作区协作** — 多用户工作区与成员管理
- 🌐 **Multilingual / 多语言支持** — Chinese and English interface with multilingual README
- 🌐 **多语言支持** — 中英文界面与多语言 README

### Infrastructure / 基础设施
- 🔧 GitHub Actions CI/CD with tag-triggered multi-platform builds and automated GitHub Release
- 🔧 GitHub Actions CI/CD，tag 触发多平台构建与自动 GitHub Release 发布
- 🔧 Dual-database architecture: PostgreSQL (server mode) and SQLite (desktop mode) via feature flags
- 🔧 双数据库架构：PostgreSQL（服务器模式）和 SQLite（桌面模式）通过 feature flag 切换
- 🔧 Embedded Rust backend bundled with Flutter desktop app
- 🔧 Rust 后端内嵌于 Flutter 桌面应用中
- 🔧 Automated release notes generation from CHANGELOG.md
- 🔧 从 CHANGELOG.md 自动生成 Release Notes
