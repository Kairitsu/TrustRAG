# Issues #26-#27 修复计划 + Open Issues 综合分析

> 创建时间: 2026-06-03
> 提出者: Kairitsu (Windows 桌面端测试反馈)
> 状态: **全部完成** ✅
> 完成时间: 2026-06-03
> 版本: v0.2.7-beta.4
> 协议: RIPER-5
> 关联: Issues #20-#25 核心修复已完成，增强项 P0+P1 已完成

---

## 当前 Open Issues 状态总览

| Issue | 标题 | 紧急程度 | 修复状态 | 备注 |
|-------|------|----------|----------|------|
| #27 | 后端启动 panic (axum 路由参数) | **P0 阻断** | ✅ 已修复 | v0.2.7-beta.4, commit 34e6c5a |
| #26 | Windows 卸载未清理本地数据 | P2 | ✅ 已修复 | v0.2.7-beta.4, commit 0c43008 |
| #20 | Rerank 配置保存 PUT 500 | P0 | ✅ 已提交修复 | 但 issue 仍 open，可能需验证 |
| #21 | 多账号切换 Cannot connect | P1 | ✅ 已提交修复 | 同上 |
| #22 | OCR 安装体验优化 | P3 | ✅ 核心+P0/P1增强已完成 | P2/P3 增强待做 |
| #23 | 大文档分块卡住 | P1 | ✅ 已提交修复+增强 | 同上 |
| #24 | 聊天无回复 | P1 | ✅ 已提交修复+增强 | 同上 |
| #25 | 知识图谱状态不一致 | P1 | ✅ 已提交修复+增强 | 同上 |

### 关键判断

**#20-#25 的核心 Bug 已在 v0.2.7-beta.1~beta.3 中修复并提交**（见 `issues-20-25-todo.md` 和 `issues-20-25-enhancements-todo.md`），增强项 P0+P1 也已完成。这些 issue 仍为 open 可能是因为：
1. 用户 Kairitsu 还未验证最新版本
2. 修复可能不完整，需要用户反馈确认

**#27 和 #26 是全新的 issue**，需要立即处理。

---

## Issue #27: 后端启动 panic (axum 0.8 路由参数) — **P0 阻断性**

### 问题描述
`backend/src/api/system.rs` 第 33-34 行使用了旧式 axum 路由参数 `:task_id`，axum 0.8 不再支持，要求使用 `{task_id}`。后端在路由注册阶段 panic，导致 Windows 本地模式完全不可用。

### 根因分析
```
system.rs:33: .route("/system/ocr-install/status/:task_id", ...)  ← PANIC
system.rs:34: .route("/system/ocr-install/cancel/:task_id", ...)  ← PANIC
```

全局搜索确认：**仅 `system.rs` 中存在旧式参数写法**，其他文件（`rerank_configs.rs`, `knowledge_graph.rs`, `embedding_configs.rs`, `documents.rs`, `evidence.rs`, `answer_status.rs`, `chat.rs`, `retrieval_traces.rs`, `domain_profiles.rs`, `models.rs`, `workspace_members.rs`, `reviews.rs`, `search.rs`, `citations.rs`）均已使用 `{param}` 新语法。

### 修复方案

- [ ] **27.1** 修复 `backend/src/api/system.rs` 路由参数
  ```
  - .route("/system/ocr-install/status/:task_id", get(ocr_install_status))
  + .route("/system/ocr-install/status/{task_id}", get(ocr_install_status))
  - .route("/system/ocr-install/cancel/:task_id", post(ocr_install_cancel))
  + .route("/system/ocr-install/cancel/{task_id}", post(ocr_install_cancel))
  ```

- [ ] **27.2** 全局验证 — 再次搜索 backend 中所有 `.route(` 调用，确认无遗漏
  ```bash
  grep -rn ':[\w]\+' backend/src/api/ | grep '\.route('
  ```

- [ ] **27.3** 后端启动失败时前端错误展示增强（Issue #27 第六部分建议）
  - `BackendManager.start()` 捕获 `trustrag-backend.exe` 的 stderr
  - 短时间内退出（<5s）记录退出码和 stderr 最后一段
  - UI 显示真实错误而非泛化的"本地后端未启动"
  - **文件**: `apps/client/lib/core/services/backend_manager.dart`

- [ ] **27.4** `cargo test` 验证通过
- [ ] **27.5** desktop feature 构建验证通过
- [ ] **27.6** 提交代码 + 回复 Issue #27

### 预估工时: 30min（路由修复本身极简单，前端错误展示增强约 1h）

---

## Issue #26: Windows 卸载程序未能彻底清理本地数据 — P2

### 问题描述
用户卸载 TrustRAG 时选择"删除所有本地数据"，但重装后旧账户和数据库仍然残留。

### 根因分析

**路径不匹配**是核心问题：

| 组件 | 数据目录 | Windows 路径示例 |
|------|----------|-----------------|
| Rust 后端 (`config.rs`) | `ProjectDirs::from("com", "trustrag", "TrustRAG").data_dir()` | `C:\Users\<user>\AppData\Local\com.trustrag.TrustRAG\data` |
| Flutter 前端 (`backend_manager.dart`) | `getApplicationSupportDirectory()` + `TrustRAG` | `C:\Users\<user>\AppData\Roaming\com.example\TrustRAG` 或类似 |
| InnoSetup 卸载脚本 (`installer.iss`) | `{localappdata}\TrustRAG` | `C:\Users\<user>\AppData\Local\TrustRAG` |
| InnoSetup 卸载脚本 | `{userappdata}\TrustRAG` | `C:\Users\<user>\AppData\Roaming\TrustRAG` |

**结论**: 卸载脚本清理的是 `...\TrustRAG\`，但实际数据存储在 `...\com.trustrag.TrustRAG\` 或其他路径下，完全不匹配。

### 修复方案

- [ ] **26.1** 确认实际 Windows 数据路径
  - 确认 Rust `directories::ProjectDirs::from("com", "trustrag", "TrustRAG")` 在 Windows 的完整路径
  - 确认 Flutter `getApplicationSupportDirectory()` 在 Windows 的完整路径
  - 确认是否存在多账号隔离后的子目录结构

- [ ] **26.2** 更新 `installer.iss` 卸载脚本
  - 添加所有可能的数据目录到清理列表：
    ```pascal
    // Rust backend data (directories crate)
    LocalAppDataDir1 := ExpandConstant('{localappdata}\com.trustrag.TrustRAG');
    // Flutter app support
    RoamingAppDataDir1 := ExpandConstant('{userappdata}\com.example\TrustRAG');
    // Legacy paths
    LocalAppDataDir2 := ExpandConstant('{localappdata}\TrustRAG');
    RoamingAppDataDir2 := ExpandConstant('{userappdata}\TrustRAG');
    // Temp backend data
    TempDir := ExpandConstant('{tmp}\trustrag-backend');
    ```
  - 列出所有实际存在的目录给用户确认
  - 逐一清理

- [ ] **26.3** 统一数据目录
  - 长期方案：让 Rust 后端和 Flutter 前端使用相同的基础目录
  - 或在 `backend_manager.dart` 中通过环境变量 `TRUSTRAG__DATA_DIR` 强制指定
  - 确保 installer 清理路径与实际路径一致

- [ ] **26.4** 测试验证
  - 安装 → 使用 → 卸载（选择删除数据）→ 检查所有目录是否已清理
  - 重装 → 确认无旧数据残留

- [ ] **26.5** 提交代码 + 回复 Issue #26

### 预估工时: 1.5h

---

## 已完成 Issues (#20-#25) 回顾与待办

以下修复已提交到 master，对应 v0.2.7-beta.1~beta.3 的发布内容。

### 需要关闭的 Issues（已有修复代码）

| Issue | 修复 commit 范围 | 状态 |
|-------|-----------------|------|
| #20 | `fix(#20): rerank config PUT 500` | 需回复 issue 确认关闭 |
| #21 | `fix(#21): properly wire account switching` | 需回复 issue 确认关闭 |
| #22 | `fix(#22): improve OCR install flow` + OPT-1 | 核心修复完成，P2/P3 增强待做 |
| #23 | `fix(#23): improve large document processing` + OPT-2/OPT-3 | 核心修复完成 |
| #24 | `fix(#24): show AI loading bubble` + E-24.1~E-24.4 | 核心修复+增强完成 |
| #25 | `fix(#25): knowledge graph status mismatch` + E-25.1~E-25.3 | 核心修复+增强完成 |

### 建议操作
- [ ] 在每个已修复 issue 下添加 comment 说明修复内容和版本号
- [ ] 等用户 Kairitsu 验证后关闭（或直接关闭附带说明）

---

## 未完成的增强项 (来自 issues-20-25-enhancements-todo.md)

| 优先级 | ID | 标题 | 状态 |
|--------|-----|------|------|
| P2 | E-22.1 | OCR 安装改为异步任务模式 | ⏳ 已有后端支持(start/status/cancel)，但路由有 bug(#27) |
| P2 | E-22.2 | OCR 安装「取消」按钮 | ⏳ 同上 |
| P2 | E-23.4 | 后端文档处理任务队列 (并发控制) | ✅ 已完成 (semaphore) |
| P2 | E-24.5 | 「复制诊断信息」按钮 | ✅ 已完成 |
| P3 | E-25.3 | 知识图谱生成历史和诊断记录 | ✅ 已完成 |
| P3 | E-22.3 | Windows UAC 提权安装 | ✅ 已完成 |
| P3 | E-23.5 | 大文件 chunking 性能 benchmark | ✅ 已完成 |

---

## 执行计划

### 第一步: 修复 #27 (P0 阻断) — 预估 30min
```
27.1 修复路由参数 → 27.2 全局验证 → 27.4 cargo test → 27.5 构建验证 → 27.6 提交
```
路由修复极其简单（改两行），但必须优先做，因为它阻断了所有 Windows 用户。

### 第二步: 前端错误展示增强 (27.3) — 预估 1h
```
27.3 BackendManager stderr 捕获 + 真实错误展示
```
提升用户诊断体验，避免未来类似问题被泛化错误信息掩盖。

### 第三步: 修复 #26 卸载清理 — 预估 1.5h
```
26.1 确认实际路径 → 26.2 更新 installer.iss → 26.3 统一数据目录 → 26.4 测试
```

### 第四步: 回复已修复的 Issues (#20-#25)
```
在每个 issue 下添加修复说明 comment
```

### 第五步: 版本发布
```
bump version → 更新 CHANGELOG → git tag → push → CI 构建发布
```

---

## 技术债务记录

1. **数据目录碎片化**: Rust 后端使用 `directories::ProjectDirs`，Flutter 前端使用 `getApplicationSupportDirectory()`，InnoSetup 使用 `{localappdata}`，三者路径不统一。需要长期方案统一。

2. **axum 0.8 迁移不完整**: `system.rs` 是后来新增的文件（v0.2.6 周期），开发时未注意 axum 0.8 的路由参数语法变更。建议添加 CI lint 检查。

3. **Issue 关闭流程**: #20-#25 的修复代码已合入 master 并发布了 beta 版本，但 issue 仍 open。需要建立"修复后主动回复+关闭"的流程。

---

## 相关文档索引

| 文档 | 内容 |
|------|------|
| `issues-20-25-todo.md` | #20-#25 核心 Bug 修复计划（已完成）|
| `issues-20-25-enhancements-todo.md` | #20-#25 增强建议（P0+P1 已完成）|
| `remaining-optimizations-todo.md` | 3 个剩余优化项（已完成）|
| `issues-18-19-todo.md` | #18-#19 修复（已完成）|
| `issues-12-17-todo.md` | #12-#17 修复（已完成）|
| `issue-11-todo.md` | #11 修复（已完成）|
| **本文档** | **#26-#27 修复 + 综合分析（待执行）**|
