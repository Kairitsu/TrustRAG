import { defineConfig } from 'vitepress'

export default defineConfig({
  title: 'TrustRAG',
  description: 'Trustworthy RAG Knowledge Workbench — Verifiable Answers, Precise Citations, Document-Grounded Review',
  base: '/TrustRAG/',
  head: [
    ['meta', { property: 'og:title', content: 'TrustRAG — Trustworthy RAG Knowledge Workbench' }],
    ['meta', { property: 'og:description', content: 'Multi-platform RAG workbench with citation tracking, review workflows, and self-contained desktop mode.' }],
    ['meta', { name: 'twitter:card', content: 'summary_large_image' }],
    ['script', {}, `
      (function() {
        if (typeof window === 'undefined') return;
        var p = window.location.pathname;
        if (p.includes('/zh/')) return;
        if (sessionStorage.getItem('lang-detected')) return;
        sessionStorage.setItem('lang-detected', '1');
        var lang = navigator.language || navigator.userLanguage || '';
        if (lang.startsWith('zh')) {
          window.location.replace(window.location.pathname.replace(/\\/TrustRAG\\//, '/TrustRAG/zh/'));
        }
      })();
    `],
  ],
  locales: {
    root: {
      label: 'English',
      lang: 'en-US',
      themeConfig: {
        nav: [
          { text: 'Guide', link: '/guide/getting-started' },
          { text: 'Architecture', link: '/architecture/overview' },
          { text: 'API Reference', link: '/api/overview' },
          { text: 'Development', link: '/development/setup' },
          {
            text: 'v0.2.1',
            items: [
              { text: 'Changelog', link: 'https://github.com/XimilalaXiang/TrustRAG/blob/master/CHANGELOG.md' },
              { text: 'Download', link: 'https://github.com/XimilalaXiang/TrustRAG/releases/latest' },
            ],
          },
        ],
        sidebar: {
          '/guide/': [
            {
              text: 'Introduction',
              items: [
                { text: 'What is TrustRAG?', link: '/guide/what-is-trustrag' },
                { text: 'Getting Started', link: '/guide/getting-started' },
              ],
            },
            {
              text: 'Usage',
              items: [
                { text: 'Desktop Mode', link: '/guide/desktop-mode' },
                { text: 'Server Mode', link: '/guide/server-mode' },
                { text: 'RAG Chat', link: '/guide/rag-chat' },
                { text: 'Citations & Review', link: '/guide/citations' },
                { text: 'Review Reports', link: '/guide/review-reports' },
                { text: 'Knowledge Graph', link: '/guide/knowledge-graph' },
                { text: 'Multi-Language (i18n)', link: '/guide/i18n' },
              ],
            },
          ],
          '/architecture/': [
            {
              text: 'Architecture',
              items: [
                { text: 'System Overview', link: '/architecture/overview' },
                { text: 'Dual-Database Design', link: '/architecture/dual-database' },
                { text: 'RAG Pipeline', link: '/architecture/rag-pipeline' },
                { text: 'Citation System', link: '/architecture/citations' },
              ],
            },
          ],
          '/api/': [
            {
              text: 'API Reference',
              items: [
                { text: 'Overview', link: '/api/overview' },
                { text: 'Authentication', link: '/api/authentication' },
                { text: 'Workspaces', link: '/api/workspaces' },
                { text: 'Documents', link: '/api/documents' },
                { text: 'Chat & Messages', link: '/api/chat' },
                { text: 'Citations & Reviews', link: '/api/citations' },
                { text: 'Review Reports', link: '/api/review-reports' },
                { text: 'Knowledge Graph', link: '/api/knowledge-graph' },
              ],
            },
          ],
          '/development/': [
            {
              text: 'Development',
              items: [
                { text: 'Dev Setup', link: '/development/setup' },
                { text: 'Project Structure', link: '/development/structure' },
                { text: 'Build & Release', link: '/development/build' },
              ],
            },
          ],
        },
      },
    },
    zh: {
      label: '简体中文',
      lang: 'zh-CN',
      link: '/zh/',
      themeConfig: {
        nav: [
          { text: '指南', link: '/zh/guide/getting-started' },
          { text: '架构', link: '/zh/architecture/overview' },
          { text: 'API 参考', link: '/zh/api/overview' },
          { text: '开发', link: '/zh/development/setup' },
          {
            text: 'v0.2.1',
            items: [
              { text: '更新日志', link: 'https://github.com/XimilalaXiang/TrustRAG/blob/master/CHANGELOG.md' },
              { text: '下载', link: 'https://github.com/XimilalaXiang/TrustRAG/releases/latest' },
            ],
          },
        ],
        sidebar: {
          '/zh/guide/': [
            {
              text: '介绍',
              items: [
                { text: '什么是 TrustRAG？', link: '/zh/guide/what-is-trustrag' },
                { text: '快速开始', link: '/zh/guide/getting-started' },
              ],
            },
            {
              text: '使用',
              items: [
                { text: '桌面模式', link: '/zh/guide/desktop-mode' },
                { text: '服务器模式', link: '/zh/guide/server-mode' },
                { text: 'RAG 对话', link: '/zh/guide/rag-chat' },
                { text: '引用与审核', link: '/zh/guide/citations' },
                { text: '审核报告', link: '/zh/guide/review-reports' },
                { text: '知识图谱', link: '/zh/guide/knowledge-graph' },
                { text: '多语言 (i18n)', link: '/zh/guide/i18n' },
              ],
            },
          ],
          '/zh/architecture/': [
            {
              text: '架构',
              items: [
                { text: '系统概览', link: '/zh/architecture/overview' },
                { text: '双数据库设计', link: '/zh/architecture/dual-database' },
                { text: 'RAG 管线', link: '/zh/architecture/rag-pipeline' },
                { text: '引用系统', link: '/zh/architecture/citations' },
              ],
            },
          ],
          '/zh/api/': [
            {
              text: 'API 参考',
              items: [
                { text: '概览', link: '/zh/api/overview' },
                { text: '认证', link: '/zh/api/authentication' },
                { text: '工作区', link: '/zh/api/workspaces' },
                { text: '文档', link: '/zh/api/documents' },
                { text: '对话与消息', link: '/zh/api/chat' },
                { text: '引用与审核', link: '/zh/api/citations' },
                { text: '审核报告', link: '/zh/api/review-reports' },
                { text: '知识图谱', link: '/zh/api/knowledge-graph' },
              ],
            },
          ],
          '/zh/development/': [
            {
              text: '开发',
              items: [
                { text: '开发环境', link: '/zh/development/setup' },
                { text: '项目结构', link: '/zh/development/structure' },
                { text: '构建与发布', link: '/zh/development/build' },
              ],
            },
          ],
        },
      },
    },
  },
  themeConfig: {
    socialLinks: [
      { icon: 'github', link: 'https://github.com/XimilalaXiang/TrustRAG' },
    ],
    footer: {
      message: 'Released under the Apache 2.0 License.',
      copyright: 'Copyright © 2025-present XimilalaXiang',
    },
    search: {
      provider: 'local',
    },
  },
})
