# TrustRAG 自动更新功能 — 实施计划

> 创建日期：2026-05-21
> 版本范围：v0.2.1（不发布 tag，同步到 test 分支构建）
> 策略：第一阶段 — 检查更新 + 提示下载

---

## 任务清单

### 1. 创建 UpdateChecker 服务
- 文件：`lib/core/services/update_checker.dart`
- 功能：
  - 调用 GitHub Releases API 获取最新版本
  - 解析版本号、release notes、各平台下载链接
  - 版本号对比逻辑
  - 缓存机制（24 小时内不重复检查）
  - 错误处理（网络失败静默处理）

### 2. 创建更新对话框 UI
- 文件：`lib/features/settings/widgets/update_dialog.dart`
- 功能：
  - 显示新版本号 + 当前版本号
  - 显示 Release Notes（Markdown 渲染）
  - "立即下载"按钮（打开浏览器跳转 GitHub Release）
  - "稍后提醒"按钮
  - "跳过此版本"按钮（记住跳过的版本）

### 3. 集成到 main.dart 启动流程
- 修改：`lib/main.dart`
- 功能：
  - App 启动后延迟 3 秒检查更新（非阻塞）
  - 有更新时通过全局 Key 弹出对话框

### 4. 设置页添加"检查更新"入口
- 修改：`lib/features/dashboard/pages/dashboard_page.dart`
- 功能：
  - 设置列表新增"检查更新"卡片
  - 显示当前版本号
  - 手动触发检查更新
  - 检查中显示 loading 状态

### 5. 添加 url_launcher 依赖
- 修改：`pubspec.yaml`
- 添加 url_launcher 用于打开浏览器

### 6. 编写测试
- 文件：`test/update_checker_test.dart`
- 测试：
  - 版本号对比逻辑
  - GitHub API 响应解析
  - 跳过版本逻辑
  - 缓存逻辑

### 7. 提交到 GitHub + 同步到 test 分支构建

---

## 技术细节

### GitHub Releases API
```
GET https://api.github.com/repos/XimilalaXiang/TrustRAG/releases/latest
```

### 版本号对比
使用 pubspec.yaml 中的 version 字段（如 0.2.1+5），与 GitHub Release tag（如 v0.2.1）对比。

### 各平台下载链接匹配
从 Release assets 中按文件名匹配：
- Windows: `trustrag-windows-x64-portable.zip` 或 `TrustRAG-Setup-Windows-x64.exe`
- macOS: `trustrag-macos.tar.gz`
- Linux: `trustrag-linux-x64.tar.gz`
- Android: `app-release.apk`
- iOS: 引导到 Release 页面
- Web: 无需更新
