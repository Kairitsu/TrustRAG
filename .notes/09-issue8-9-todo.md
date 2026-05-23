# Issue #8 & #9 开发计划 TODO List

> 创建时间: 2026-05-23
> 最后更新: 2026-05-23
> 关联 Issue: [#8](https://github.com/XimilalaXiang/TrustRAG/issues/8) [#9](https://github.com/XimilalaXiang/TrustRAG/issues/9)

## 执行顺序

1. ~~Issue #8 Phase A+B (用户体验改善，复杂度低)~~ ✅
2. ~~Issue #9 Phase 1-8 (核心检索架构升级)~~ ✅
3. ~~Issue #8 Phase C (服务器配置)~~ ✅

---

## Issue #8: 个人空间与团队空间边界不清

### Phase A: 前端空间隔离 ✅ 已完成

- [x] A1-A4: 工作区数据流分离、离线模式、UI 区分

### Phase B: 错误处理与提示优化 ✅ 已完成

- [x] B1-B4: 用户友好错误提示、重试按钮、离线切换、多语言

### Phase C: 服务器配置 ✅ 已完成

- [x] C1. 设置页面添加"服务器地址"配置项
  - 新增 `server_config_provider.dart` 状态管理（ServerMode, ServerConfig, SharedPreferences 持久化）
  - 新增 `server_config_page.dart` 独立配置页面
- [x] C2. 内置默认官方服务器地址（`https://api.trustrag.app`）
  - ApiClient 支持从 SharedPreferences 加载自定义服务器 URL
  - main.dart 启动时预加载服务器配置
- [x] C3. 添加服务器连接状态指示器
  - 4 种连接状态：unknown/checking/connected/disconnected
  - 实时 HTTP /health 端点检测
  - 状态图标显示在设置页和服务器配置页
- [x] C4. 支持"官方服务 / 自定义服务器"切换开关
  - 卡片式单选切换（官方服务 vs 自定义服务器）
  - 自定义 URL 输入框 + 保存 + 连接测试
  - 四语言 i18n（中/英/日/韩）完整支持

---

## Issue #9: 架构升级为生产级人机协同知识工作台

### Phase 1: 统一检索链路 ✅ 已完成

- [x] 新增 `retrieval_pipeline.rs` 统一模块
- [x] `RetrievalPipelineConfig` + `RetrievalPipelineOutput`
- [x] streaming/non-streaming 路径共用 `retrieval_pipeline::run()`
- [x] 消除 chat.rs SSE 端点重复检索逻辑
- [x] `RetrievalTrace` 可观测性结构

### Phase 2: 升级检索能力 ✅ 已完成

- [x] Migration 0008: `tsv` tsvector 列 + GIN 索引 + 自动更新触发器
- [x] `sparse_search()` 基于 `ts_rank_cd` 的 tsvector 搜索
- [x] `SearchMode::Sparse` 新变体
- [x] Hybrid 模式自动使用 tsvector（Postgres）/ FTS5（SQLite）
- [x] `build_tsquery()` 自然语言转 tsquery
- [x] pg_trgm fallback 保留

### Phase 3: 升级 Reranker ✅ 已完成

- [x] `RerankerProvider` async trait（score + name）
- [x] `ReRankMethod::CrossEncoder` 变体
- [x] `HttpRerankerProvider` 兼容 Jina/Cohere API
- [x] `rerank_with_provider()` 支持可选外部 provider
- [x] `retrieval_pipeline::run_with_reranker()` pipeline 级别集成
- [x] 无 provider 时 graceful fallback 到 LLM scoring

### Phase 4: 自动 Metadata + Domain Profile ✅ 已完成

- [x] Migration 0009: `metadata` JSONB → documents, `domain_profile` JSONB → workspaces
- [x] `metadata.rs`: LLM 驱动的文档元数据自动提取
- [x] `DocumentMetadata`: keywords, topics, language, domain, entity_types, summary
- [x] `DomainProfile`: 工作区级别领域画像（频率分析聚合）
- [x] CRUD helpers: save/load metadata, save domain profile

### Phase 5: Query Planner ✅ 已完成

- [x] `query_planner.rs`: 基于 intent + domain profile + corpus size 的自适应策略
- [x] `QueryPlan`: search_mode, top_k, expansion, rerank, context_chars
- [x] Intent-specific tuning (Chitchat/Factual/Exploratory/Comparison/Summary)
- [x] Corpus-aware scaling (>100 chunks 启用 rerank)

### Phase 6: Claim-level Evidence Verification ✅ 已完成

- [x] `evidence.rs`: 将 LLM 答案拆分为独立 claim 并逐一验证
- [x] Text-based 验证（CJK-aware Jaccard similarity）
- [x] LLM-based 深度语义验证（可选）
- [x] `EvidenceStatus`: Supported/Contradicted/Unsupported/Partial
- [x] `VerificationReport` + overall trust score
- [x] Filler sentence 过滤

### Phase 7: Human Review + Audit Trail ✅ 已完成

- [x] Migration 0010: `audit_trail` 表 + `evidence_report` JSONB → messages
- [x] `audit.rs`: 15 种审计动作类型，灵活查询/计数 API
- [x] `AuditAction` + `EntityType` 枚举

### Phase 8: API/UI/测试更新 ✅ 已完成

- [x] `api/audit.rs`: GET /audit 端点（带分页和过滤）
- [x] `api/evidence.rs`: GET /messages/:id/evidence 端点
- [x] 路由注册到 main.rs
- [x] **测试汇总**: 132 个单元测试全部通过

---

## Issue #9 增强型需求 (Round 2)

### 增强 1: Evidence 三种模式 off/warn/strict ✅ 已完成

- [x] E1. 添加 `VerificationMode` 枚举 (Off/Warn/Strict)
- [x] E2. 在 evidence.rs 中集成模式控制（build_report 支持 warnings + should_block）
- [x] E3. 单元测试覆盖三种模式（137 测试通过）

### 增强 2: SearchResult 多阶段分数结构 ✅ 已完成

- [x] E4. SearchResult 添加 dense_score/sparse_score/fusion_score/rerank_score 字段
- [x] E5. 各搜索函数填充对应分数（vector→dense, fulltext/sparse→sparse, RRF→fusion+dense+sparse, rerank→rerank_score）
- [x] E6. 单元测试验证（序列化省略 None、分数捕获、仅向量路径测试，140 测试通过）

### 增强 3: Domain Profile YAML 配置文件系统 ✅ 已完成

- [x] E7. 创建 `configs/domain_profiles/` 目录
- [x] E8. 添加 general/legal/finance/accounting/audit/compliance YAML 文件
- [x] E9. Rust 端 `domain_profile.rs` 加载和解析 YAML（DomainProfileRegistry）
- [x] E10. 11 个单元测试覆盖所有 profile + registry（151 测试通过）

### 增强 4: Answer Versioning + Review Status 状态机 ✅ 已完成

- [x] E11. Migration 0011: messages 表添加 answer_status 字段 (draft/needs_review/verified/rejected/published)
- [x] E12. `answer_status.rs` 状态机 + API 端点 GET/PUT /messages/:id/status
- [x] E13. 11 个单元测试覆盖状态转换、生命周期、序列化（162 测试通过）

### 增强 5: API Response 增强 ✅ 已完成

- [x] E14. Chat response 添加 retrieval_trace_id
- [x] E15. Chat response 添加 verification_warnings
- [x] E16. Chat response 添加 answer_status + MessageResponse 包含 answer_status

### 增强 6: SSE 增强事件 ✅ 已完成

- [x] E17. SSE 发送 retrieval_started / retrieval_finished 事件
- [x] E18. verification_warning 事件结构体已就绪

---

## Issue #9 补充 Gap 修复

### Gap-1: MetadataFilter 结构化检索过滤 ✅ 已完成

- [x] `MetadataFilter` 结构体（domains, languages, topics, keywords）
- [x] `to_sql_conditions()` 生成 PostgreSQL JSONB 过滤 SQL
- [x] 集成到 `SearchConfig`
- [x] 5 个单元测试覆盖（167 测试通过）

### Gap-2: Domain Profile 集成到运行时 ✅ 已完成

- [x] `DomainProfileRegistry` 添加到 `AppState`
- [x] `main.rs` 启动时加载 profiles 目录
- [x] `RetrievalPipelineConfig::apply_domain_profile()` 方法
- [x] API 端点 `GET /domain-profiles` + `GET /domain-profiles/{name}`
- [x] 4 个新单元测试（profile 应用、参数覆盖、propagation）
- [x] 171 测试全部通过

### Gap-3: RetrievalTrace 持久化 ✅ 已完成

- [x] Migration 0012: `retrieval_traces` 表（JSONB 存储 search_results, reranked_results, timings）
- [x] `retrieval_trace_store.rs` 实现 save/get/list/get_by_message
- [x] 6 个单元测试（177 测试通过）

### Gap-4: answer_versions 表 ✅ 已完成

- [x] Migration 0013: `answer_versions` 表（version_number 自增, status, reviewer, trace 关联）
- [x] `answer_versions.rs` 实现 create/get/list/latest/update_status CRUD
- [x] 6 个单元测试（183 测试通过）

### Gap-5: claim_reviews/answer_reviews 审核表 ✅ 已完成

- [x] Migration 0014: `claim_reviews` 表（verdict, confidence, evidence_references JSONB）
- [x] Migration 0014: `answer_reviews` 表（accuracy/completeness/clarity 三维评分 + revision_instructions）
- [x] `specialized_reviews.rs` 实现 ClaimVerdict/AnswerVerdict 枚举 + CRUD
- [x] 14 个单元测试（197 测试通过）

---

## 测试统计

| 模块 | 测试数 |
|------|--------|
| rag (query analysis, prompts, follow-up) | 14 |
| search (RRF, tsvector, config, metadata filter, stage scores) | 18 |
| retrieval_pipeline (config, assembly, domain profile apply) | 10 |
| reranker (parsing, cross-encoder, mock) | 10 |
| metadata (parsing, frequency, serde) | 8 |
| query_planner (intent strategies, scaling) | 11 |
| evidence (claims, tokenize, jaccard, report, modes) | 21 |
| audit (actions, entity types, serde) | 5 |
| citation (extract, verify) | 8 |
| review (input, report, markdown) | 6 |
| domain_profile (parse, registry, serde) | 13 |
| answer_status (state machine, transitions, lifecycle) | 11 |
| answer_versions (input, serde, status) | 6 |
| retrieval_trace_store (construction, serde, timings) | 6 |
| specialized_reviews (verdicts, serde, validation, input) | 14 |
| embedding/llm/storage/other | 36 |
| **合计** | **197** |
