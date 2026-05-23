# Issue #8 & #9 开发计划 TODO List

> 创建时间: 2026-05-23
> 关联 Issue: [#8](https://github.com/XimilalaXiang/TrustRAG/issues/8) [#9](https://github.com/XimilalaXiang/TrustRAG/issues/9)

## 执行顺序

1. Issue #8 Phase A+B (用户体验改善，复杂度低)
2. Issue #9 Phase 1+2+3 (核心检索架构升级)
3. Issue #8 Phase C (服务器配置)
4. Issue #9 Phase 4-8 (进阶功能)

---

## Issue #8: 个人空间与团队空间边界不清

### Phase A: 前端空间隔离 (优先级: 高)

- [ ] A1. 梳理 workspace_provider.dart 中个人/团队空间的数据流，确认耦合点
- [ ] A2. 实现本地个人空间模式：后端不可达时使用本地 SQLite 存储个人数据
- [ ] A3. dashboard_page.dart 中分离"个人空间"和"团队空间"的 UI 入口，添加清晰视觉区分
- [ ] A4. 个人空间默认不依赖远程后端接口

### Phase B: 错误处理与提示优化 (优先级: 高)

- [ ] B1. 替换 DioException 原始错误为用户友好的错误提示（多语言）
- [ ] B2. 工作区加载失败时显示重试按钮和离线提示
- [ ] B3. 后端 500 错误统一拦截，显示"服务暂时不可用"
- [ ] B4. 网络不可用时自动切换到离线个人空间模式

### Phase C: 服务器配置 (优先级: 中)

- [ ] C1. 设置页面添加"服务器地址"配置项
- [ ] C2. 内置默认官方服务器地址（预留）
- [ ] C3. 添加服务器连接状态指示器
- [ ] C4. 支持"官方服务 / 自定义服务器"切换开关

---

## Issue #9: 架构升级为生产级人机协同知识工作台

### Phase 1: 统一检索链路 (优先级: 最高)

- [ ] 1.1 新增 backend/src/services/retrieval_pipeline.rs
- [ ] 1.2 定义 RetrievalPipelineConfig 结构体
- [ ] 1.3 定义 RetrievalPipelineOutput 结构体
- [ ] 1.4 从 rag.rs 提取 search_with_expansion + rerank + assemble_context 到 pipeline
- [ ] 1.5 run_rag_pipeline 和 run_rag_pipeline_stream 共用同一个 Pipeline
- [ ] 1.6 消除 chat.rs build_sse_stream 中重复的检索逻辑
- [ ] 1.7 新增 RetrievalTrace 基础结构体
- [ ] 1.8 Pipeline 生成 trace，config 控制是否返回前端

### Phase 2: 升级检索能力 (优先级: 高)

- [ ] 2.1 PostgreSQL: document_chunks 添加 tsvector 列 + GIN index
- [ ] 2.2 新增迁移 0008_sparse_search_upgrade.sql
- [ ] 2.3 fulltext_search 改为 websearch_to_tsquery + ts_rank_cd
- [ ] 2.4 保留 pg_trgm 作为 fuzzy fallback
- [ ] 2.5 SQLite FTS5 改用 bm25 排序
- [ ] 2.6 扩展 SearchMode: 新增 Sparse 和 Fuzzy
- [ ] 2.7 SearchResult 新增多维分数字段
- [ ] 2.8 修改 RRF fusion 保留各阶段分数
- [ ] 2.9 扩大候选集: dense 50 + sparse 50 + fuzzy 20 -> fusion 50 -> rerank 10
- [ ] 2.10 添加 sparse retrieval 单元测试

### Phase 3: 升级 Reranker (优先级: 高)

- [ ] 3.1 新增 backend/src/traits/reranker_provider.rs
- [ ] 3.2 定义 RerankerProvider trait
- [ ] 3.3 ReRankMethod 扩展: None, LlmScoring, CrossEncoderHttp, ExternalApi
- [ ] 3.4 实现 CrossEncoderHttp reranker (Jina/Cohere/BGE)
- [ ] 3.5 保留 LlmScoring 作为 fallback
- [ ] 3.6 reranker 失败 fallback 到 fusion 排序
- [ ] 3.7 接入 retrieval_pipeline.rs
- [ ] 3.8 添加 reranker fallback 测试

### Phase 4: 自动 Metadata + Domain Profile (优先级: 中)

- [ ] 4.1 新增 metadata_extractor.rs
- [ ] 4.2 新增 document_metadata 表 + 迁移
- [ ] 4.3 实现 metadata 提取流程
- [ ] 4.4 metadata 提取失败不阻塞文档入库
- [ ] 4.5 metadata 带 confidence + extraction_method
- [ ] 4.6 新增 configs/domain_profiles/
- [ ] 4.7 实现 general.yaml 默认 Profile
- [ ] 4.8 workspace 表新增 domain_profile 字段
- [ ] 4.9 Domain Profile 影响 metadata extraction 和 retrieval 参数
- [ ] 4.10 metadata 接入 retrieval filtering + ranking boost

### Phase 5: Query Planner (优先级: 中)

- [ ] 5.1 新增 query_planner.rs
- [ ] 5.2 定义 QueryPlan 结构体
- [ ] 5.3 定义 MetadataFilter 结构体
- [ ] 5.4 实现 rule-based planner
- [ ] 5.5 LLM planner + fallback
- [ ] 5.6 接入 Domain Profile
- [ ] 5.7 写入 RetrievalTrace
- [ ] 5.8 接入 retrieval_pipeline.rs

### Phase 6: Claim-level Evidence Verification (优先级: 中)

- [ ] 6.1 新增 claim_verifier.rs
- [ ] 6.2 定义 ClaimCheck + ClaimStatus
- [ ] 6.3 支持 off / warn / strict 模式
- [ ] 6.4 warn: 返回答案 + verification_warnings
- [ ] 6.5 strict: unsupported claim 触发 revision
- [ ] 6.6 写入 RetrievalTrace
- [ ] 6.7 新增 SSE event: verification_warning

### Phase 7: Human Review + Audit Trail (优先级: 低)

- [ ] 7.1 扩展 review 相关数据库表
- [ ] 7.2 新增 answer_versions 表
- [ ] 7.3 新增 audit_logs 表
- [ ] 7.4 新增 retrieval_traces 数据库表
- [ ] 7.5 扩展 review API
- [ ] 7.6 支持多人协作审核流程

### Phase 8: API/UI/测试更新 (优先级: 低)

- [ ] 8.1 Chat API 新增 verification_warnings, retrieval_trace_id, answer_status
- [ ] 8.2 SSE 新增事件
- [ ] 8.3 新增 debug endpoint
- [ ] 8.4 前端 Flutter 适配
- [ ] 8.5 集成测试
- [ ] 8.6 更新文档
