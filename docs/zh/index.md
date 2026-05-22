---
layout: home
hero:
  name: TrustRAG
  text: 可信赖的 RAG 知识工作台
  tagline: 上传文档、提出问题，每个回答都可追溯到原始来源——引用验证、审核流程、桌面端自包含。
  actions:
    - theme: brand
      text: 下载 v0.2.4
      link: https://github.com/XimilalaXiang/TrustRAG/releases/latest
    - theme: alt
      text: 快速开始 →
      link: /zh/guide/getting-started
    - theme: alt
      text: API 参考
      link: /zh/api/overview
features:
  - icon: 📎
    title: 引用追踪
    details: 每条 AI 回复都包含可追溯的引用，关联到文档、分块、页码和标题。每个答案都可验证。
  - icon: ✅
    title: 引用审核与报告
    details: 通过、拒绝或标记引用的准确性。导出审核报告，含通过率、幻觉率、审核覆盖率等统计指标。
  - icon: 🖥️
    title: 多平台桌面
    details: Windows（.exe 安装包 + 便携版）、macOS、Linux、Android、iOS、Web，全平台一套 Flutter 代码，自适应布局。
  - icon: 📦
    title: 桌面端自包含
    details: 内嵌 SQLite + Rust 后端。桌面端原生 PDF 解析。无需外部数据库，无需服务器配置。
  - icon: 🤖
    title: RAG 管线
    details: 基于文档的检索增强生成，可配置 LLM 和 Embedding 提供商。混合搜索：向量 + 全文检索。
  - icon: 🧠
    title: 知识图谱
    details: 交互式图谱可视化，支持实体浏览和搜索。颜色编码节点、关系标签、跨文档探索。
  - icon: 🌐
    title: 多语言 (i18n)
    details: 完整的 UI 本地化，支持中文、英文、日文、韩文切换。语言偏好持久化保存。
  - icon: 👥
    title: 团队协作
    details: 创建或加入团队空间，通过邀请码协作。角色权限体系（所有者/管理员/编辑者/查看者），个人空间与团队空间数据隔离。
  - icon: 📄
    title: 审核报告
    details: 生成 Markdown 审核报告，含引用统计、幻觉率、通过率和详细审核记录。支持一键复制分享。
---

<style>
:root {
  --vp-home-hero-name-color: transparent;
  --vp-home-hero-name-background: -webkit-linear-gradient(120deg, #10b981 30%, #3b82f6);
  --vp-home-hero-image-background-image: linear-gradient(-45deg, #10b98140 50%, #3b82f640 50%);
  --vp-home-hero-image-filter: blur(44px);
}
</style>
