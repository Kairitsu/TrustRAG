# Issues #18 & #19 修复计划

> 创建时间: 2026-06-01
> 状态: 待开始

---

## Issue #18 — 客户端版本号硬编码，显示 v0.2.2

**问题**: `main.dart` 中 `const appVersion = '0.2.2'` 硬编码未随版本发布更新，导致关于页、更新检测均显示旧版本号。

### 任务清单

- [ ] **18.1** 引入 `package_info_plus` 依赖
  - 在 `pubspec.yaml` 添加 `package_info_plus`
  - 该插件可在运行时读取 pubspec.yaml 中的版本号，彻底消除硬编码

- [ ] **18.2** 创建全局版本号 Provider
  - 新建 `lib/core/providers/app_version_provider.dart`
  - 使用 `PackageInfo.fromPlatform()` 获取版本号
  - 提供 `appVersionProvider` (Riverpod FutureProvider)

- [ ] **18.3** 替换 `main.dart` 中的硬编码常量
  - 删除 `const appVersion = '0.2.2'`
  - 启动时的更新检查改为从 provider 获取版本号

- [ ] **18.4** 更新 Dashboard 页面版本号显示
  - `dashboard_page.dart` 中关于页面、检查更新处，改读 `appVersionProvider`
  - 加载中显示 "..." 或 skeleton，避免闪烁

- [ ] **18.5** 更新 UpdateDialog 和 UpdateChecker
  - 确保 `checkForUpdate()` 接收的 `currentVersion` 来自运行时而非常量

- [ ] **18.6** 测试验证
  - 本地构建后确认关于页显示正确版本号
  - 确认更新检测使用正确版本号比较

---

## Issue #19 — 多账户切换失败与登录状态紊乱

**问题**: 账号切换后丢失登录状态，local 默认账号不透明，退出清除数据无效。涉及前后端状态同步、token 管理、数据目录切换等多个层面。

### 一、Token 存储与账号绑定修复

- [ ] **19.1** 修复 `saveToken()` 的绑定时序
  - `auth_provider.dart` 中：确保 `setActiveAccount(email)` 在 `saveToken(token)` **之前**调用
  - 避免 token 被关联到旧账号

- [ ] **19.2** 增强 `switchToAccount()` 事务式回滚
  - 切换前保存原账号状态（email + token + dataDir）
  - 如果 `BackendManager.restart()` 失败，回滚到原账号
  - 如果目标账号无 token，不直接 logout，而是提示用户重新输入密码
  - 返回详细的切换结果（成功/需要重新登录/失败已回滚）

- [ ] **19.3** `switchToAccount` 等待后端就绪
  - `restart()` 内部的 `start()` 已有 `_readyCompleter`
  - 在 `switchToAccount` 中 `await BackendManager().ready` 确保后端完全启动后再返回

### 二、Dashboard 账号切换 UI 改进

- [ ] **19.4** 改进切换失败处理
  - 当前逻辑：无 token → logout → 跳转登录页（丢失原账号）
  - 改为：无 token → 弹出密码输入框让用户登录目标账号
  - 切换失败 → 保持原账号，显示错误提示

- [ ] **19.5** 账号状态区分显示
  - 账号列表中区分：当前账号（绿色）、可切换（有 token）、需重新登录（无 token/已过期）
  - local@trustrag.desktop 标注为「本地模式」而非普通邮箱账号

- [ ] **19.6** 支持从账号列表删除失效账号
  - 账号卡片添加删除按钮（长按或滑动删除）
  - 删除时调用 `ApiClient.removeAccount()` + `BackendManager().deleteAccountData()`
  - 当前账号不可删除

### 三、Local 默认账号体验优化

- [ ] **19.7** 重新设计 local 账号展示
  - 登录页不再显示 `local@trustrag.desktop` 为普通账号
  - 改为「进入本地模式」按钮，点击后自动使用本地账号登录
  - 或在账号列表中标注「本地默认」标签，自动登录无需密码

- [ ] **19.8** 自动登录守卫
  - `DesktopAutoSetup.ensureSetup()` 应尊重用户当前已登录的其他账号
  - 仅在无任何有效 token 时才自动登录 local 账号
  - 不应覆盖用户主动选择的账号

### 四、退出与数据清理

- [ ] **19.9** 完善「退出并清除数据」功能
  - 停止本地后端
  - 删除当前账号数据目录 (`BackendManager().deleteAccountData()`)
  - 清除当前账号 token
  - 从账号列表移除
  - 清除 activeAccount
  - 显示操作结果（成功/失败及原因）

- [ ] **19.10** 添加「重置本地数据」入口
  - 设置页增加「账号与数据管理」区域
  - 提供：重置登录状态、清除所有账号、重建本地默认账号
  - 操作前二次确认

### 五、错误提示优化

- [ ] **19.11** 区分桌面端错误类型
  - `Cannot connect to server` → 桌面端改为「本地后端未启动或启动失败」
  - `Invalid email or password` → 检查是否是数据目录不匹配导致
  - 网络错误 → 区分本地后端 vs 远程服务器

- [ ] **19.12** 后端健康检查增强
  - 切换账号后自动执行健康检查 (`/health`)
  - 失败时自动重试一次
  - 仍然失败则给出明确诊断信息

### 六、测试与验证

- [ ] **19.13** 完整测试场景
  - 注册多个账号 → 切换 → 验证状态保持
  - 切换到无 token 账号 → 验证密码输入流程
  - 退出并清除数据 → 验证目录被删除
  - 重启应用 → 验证不被 local 自动登录覆盖
  - 边界场景：后端未启动时切换、同时注册多个账号

- [ ] **19.14** 提交与发布
  - 代码提交到 master 分支
  - 在 Issue #18、#19 中添加修复说明
  - 发布新版本

---

## 优先级与依赖

| 阶段 | 任务 | 优先级 | 依赖 |
|------|------|--------|------|
| Phase 1 | #18 全部 (18.1-18.6) | P0 | 无 |
| Phase 2 | #19.1-19.3 (Token/后端) | P0 | 无 |
| Phase 3 | #19.4-19.6 (切换 UI) | P0 | 19.1-19.3 |
| Phase 4 | #19.7-19.8 (Local 账号) | P1 | 19.4 |
| Phase 5 | #19.9-19.10 (数据清理) | P1 | 19.2 |
| Phase 6 | #19.11-19.12 (错误提示) | P2 | 19.3 |
| Phase 7 | #19.13-19.14 (测试发布) | P0 | 全部 |

**预估工作量**: Issue #18 约 1 小时，Issue #19 约 4-6 小时
