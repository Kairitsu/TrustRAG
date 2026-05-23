use serde::{Deserialize, Serialize};
use uuid::Uuid;

use crate::db::DbPool;
use crate::services::search::SearchMode;
pub use crate::services::retrieval_pipeline::AssembledSource;
use crate::services::retrieval_pipeline::{self, RetrievalPipelineConfig};
use crate::traits::embedding_provider::EmbeddingProvider;
use crate::traits::llm_provider::{LlmMessage, LlmProvider, LlmRequest, LlmResponse, StreamEvent};
use tokio::sync::mpsc;

// ── Query Analysis (rule-based MVP) ──

#[derive(Debug, Clone, PartialEq, Serialize, Deserialize)]
pub enum QueryIntent {
    Factual,
    Exploratory,
    Comparison,
    Summary,
    Chitchat,
}

#[derive(Debug, Clone)]
pub struct QueryAnalysis {
    pub intent: QueryIntent,
    pub needs_retrieval: bool,
    pub rewritten_query: String,
}

pub fn analyze_query(query: &str, history: &[LlmMessage]) -> QueryAnalysis {
    let lower = query.to_lowercase();

    let chitchat_patterns = ["你好", "hello", "hi", "hey", "谢谢", "thanks", "再见", "bye"];
    if chitchat_patterns.iter().any(|p| lower == *p) {
        return QueryAnalysis {
            intent: QueryIntent::Chitchat,
            needs_retrieval: false,
            rewritten_query: query.to_string(),
        };
    }

    let intent = if lower.contains("对比") || lower.contains("比较") || lower.contains("区别")
        || lower.contains("vs") || (lower.contains("和") && lower.contains("哪个"))
    {
        QueryIntent::Comparison
    } else if lower.contains("总结") || lower.contains("概述") || lower.contains("摘要")
        || lower.contains("summarize") || lower.contains("overview")
    {
        QueryIntent::Summary
    } else if lower.contains("如何") || lower.contains("为什么") || lower.contains("怎么")
        || lower.contains("explain") || lower.contains("how")
    {
        QueryIntent::Exploratory
    } else {
        QueryIntent::Factual
    };

    let rewritten = if !history.is_empty() {
        let last_msgs: Vec<&str> = history
            .iter()
            .rev()
            .take(4)
            .filter(|m| m.role == "user" || m.role == "assistant")
            .map(|m| m.content.as_str())
            .collect();

        if last_msgs.is_empty() {
            query.to_string()
        } else {
            format!(
                "Based on previous discussion about {}. Current question: {}",
                last_msgs.join("; "),
                query
            )
        }
    } else {
        query.to_string()
    };

    QueryAnalysis {
        intent,
        needs_retrieval: true,
        rewritten_query: rewritten,
    }
}

// ── Prompt Engineering ──

const SYSTEM_PROMPT_ZH: &str = r#"你是 TrustRAG 知识助手。你的回答必须严格基于提供的参考资料。

规则：
1. 只使用参考资料中的信息回答问题
2. 每个事实性陈述必须附上引用标记 [1], [2] 等
3. 引用编号对应参考资料的 Source 编号
4. 如果参考资料中没有相关信息，明确说"根据提供的资料，我无法回答这个问题"
5. 不要编造、推测或使用参考资料以外的知识
6. 如果不确定某个信息是否准确，用"根据资料 [X] 的描述"等限定语
7. 每个句子最多引用 3 个来源"#;

const SYSTEM_PROMPT_EN: &str = r#"You are TrustRAG Knowledge Assistant. Your answers must be strictly based on the provided reference materials.

Rules:
1. Only use information from the reference materials to answer questions
2. Every factual statement must include a citation marker [1], [2], etc.
3. Citation numbers correspond to the Source numbers in the reference materials
4. If the reference materials don't contain relevant information, explicitly state "Based on the provided materials, I cannot answer this question"
5. Do not fabricate, speculate, or use knowledge outside the reference materials
6. If uncertain about accuracy, use qualifiers like "According to Source [X]"
7. Each sentence should cite at most 3 sources"#;

pub fn build_prompt(
    query: &str,
    context: &str,
    history: &[LlmMessage],
    language: &str,
) -> Vec<LlmMessage> {
    let system_prompt = if language.starts_with("zh") || language == "chinese" {
        SYSTEM_PROMPT_ZH
    } else {
        SYSTEM_PROMPT_EN
    };

    let mut messages = vec![LlmMessage {
        role: "system".to_string(),
        content: system_prompt.to_string(),
    }];

    let history_limit = history.len().min(6);
    for msg in &history[history.len().saturating_sub(history_limit)..] {
        messages.push(msg.clone());
    }

    let user_content = format!(
        "参考资料：\n{}\n\n用户问题：{}",
        context, query
    );

    messages.push(LlmMessage {
        role: "user".to_string(),
        content: user_content,
    });

    messages
}

pub fn build_chitchat_prompt(query: &str, history: &[LlmMessage]) -> Vec<LlmMessage> {
    let mut messages = vec![LlmMessage {
        role: "system".to_string(),
        content: "你是 TrustRAG 知识助手。请友好地回复用户。如果用户有文档相关问题，请提示他们可以上传文档后进行提问。".to_string(),
    }];

    let history_limit = history.len().min(4);
    for msg in &history[history.len().saturating_sub(history_limit)..] {
        messages.push(msg.clone());
    }

    messages.push(LlmMessage {
        role: "user".to_string(),
        content: query.to_string(),
    });

    messages
}

// ── Full RAG Pipeline ──

#[derive(Debug, Clone)]
pub struct RagConfig {
    pub max_context_chars: usize,
    pub search_top_k: usize,
    pub search_min_score: f64,
    pub search_mode: SearchMode,
    pub temperature: f32,
    pub max_tokens: u32,
    pub language: String,
    pub rerank: crate::services::reranker::ReRankConfig,
    pub query_expansion: bool,
}

impl Default for RagConfig {
    fn default() -> Self {
        Self {
            max_context_chars: 12000,
            search_top_k: 10,
            search_min_score: 0.3,
            search_mode: SearchMode::Hybrid,
            temperature: 0.1,
            max_tokens: 4096,
            language: "zh".to_string(),
            rerank: crate::services::reranker::ReRankConfig::default(),
            query_expansion: false,
        }
    }
}

impl RagConfig {
    pub fn to_pipeline_config(&self) -> RetrievalPipelineConfig {
        RetrievalPipelineConfig {
            dense_top_k: self.search_top_k * 2,
            sparse_top_k: self.search_top_k * 2,
            fusion_top_k: self.search_top_k * 2,
            final_top_k: self.search_top_k,
            max_context_chars: self.max_context_chars,
            min_score: self.search_min_score,
            search_mode: self.search_mode.clone(),
            enable_query_expansion: self.query_expansion,
            enable_rerank: self.rerank.enabled,
            enable_trace: false,
            rerank: self.rerank.clone(),
            rrf_k: 60.0,
        }
    }
}

#[derive(Debug, Serialize)]
pub struct RagResponse {
    pub answer: String,
    pub sources: Vec<AssembledSource>,
    pub prompt_tokens: u32,
    pub completion_tokens: u32,
    pub model: String,
    pub intent: QueryIntent,
}

/// Non-streaming RAG pipeline (uses unified retrieval_pipeline)
pub async fn run_rag_pipeline(
    pool: &DbPool,
    embedding_provider: &dyn EmbeddingProvider,
    llm_provider: &dyn LlmProvider,
    workspace_id: Uuid,
    query: &str,
    history: &[LlmMessage],
    document_scope: &[Uuid],
    config: &RagConfig,
) -> anyhow::Result<RagResponse> {
    let analysis = analyze_query(query, history);

    if !analysis.needs_retrieval {
        let messages = build_chitchat_prompt(query, history);
        let llm_req = LlmRequest {
            messages,
            temperature: config.temperature.max(0.5),
            max_tokens: config.max_tokens,
            stream: false,
        };
        let resp = llm_provider.generate(&llm_req).await?;
        return Ok(RagResponse {
            answer: resp.content,
            sources: vec![],
            prompt_tokens: resp.prompt_tokens,
            completion_tokens: resp.completion_tokens,
            model: resp.model,
            intent: analysis.intent,
        });
    }

    let pipeline_config = config.to_pipeline_config();
    let pipeline_output = retrieval_pipeline::run(
        pool,
        embedding_provider,
        llm_provider,
        workspace_id,
        &analysis.rewritten_query,
        if document_scope.is_empty() { None } else { Some(document_scope) },
        &pipeline_config,
    ).await?;

    if pipeline_output.sources.is_empty() {
        return Ok(RagResponse {
            answer: "根据提供的资料，我无法找到与您问题相关的信息。请尝试上传更多文档或调整问题。".to_string(),
            sources: vec![],
            prompt_tokens: 0,
            completion_tokens: 0,
            model: llm_provider.model_name().to_string(),
            intent: analysis.intent,
        });
    }

    let messages = build_prompt(query, &pipeline_output.context, history, &config.language);

    let llm_req = LlmRequest {
        messages,
        temperature: config.temperature,
        max_tokens: config.max_tokens,
        stream: false,
    };

    let resp = llm_provider.generate(&llm_req).await?;

    Ok(RagResponse {
        answer: resp.content,
        sources: pipeline_output.sources,
        prompt_tokens: resp.prompt_tokens,
        completion_tokens: resp.completion_tokens,
        model: resp.model,
        intent: analysis.intent,
    })
}

/// Streaming RAG pipeline - uses unified retrieval_pipeline, then streams LLM output
pub async fn run_rag_pipeline_stream(
    pool: &DbPool,
    embedding_provider: &dyn EmbeddingProvider,
    llm_provider: &dyn LlmProvider,
    workspace_id: Uuid,
    query: &str,
    history: &[LlmMessage],
    document_scope: &[Uuid],
    config: &RagConfig,
    tx: mpsc::Sender<StreamEvent>,
) -> anyhow::Result<Vec<AssembledSource>> {
    let analysis = analyze_query(query, history);

    if !analysis.needs_retrieval {
        let messages = build_chitchat_prompt(query, history);
        let llm_req = LlmRequest {
            messages,
            temperature: config.temperature.max(0.5),
            max_tokens: config.max_tokens,
            stream: true,
        };
        llm_provider.stream(&llm_req, tx).await?;
        return Ok(vec![]);
    }

    let pipeline_config = config.to_pipeline_config();
    let pipeline_output = retrieval_pipeline::run(
        pool,
        embedding_provider,
        llm_provider,
        workspace_id,
        &analysis.rewritten_query,
        if document_scope.is_empty() { None } else { Some(document_scope) },
        &pipeline_config,
    ).await?;

    if pipeline_output.sources.is_empty() {
        let _ = tx.send(StreamEvent::Delta(
            "根据提供的资料，我无法找到与您问题相关的信息。请尝试上传更多文档或调整问题。".to_string(),
        )).await;
        let _ = tx.send(StreamEvent::Done(LlmResponse {
            content: "根据提供的资料，我无法找到与您问题相关的信息。".to_string(),
            prompt_tokens: 0,
            completion_tokens: 0,
            model: llm_provider.model_name().to_string(),
        })).await;
        return Ok(vec![]);
    }

    let messages = build_prompt(query, &pipeline_output.context, history, &config.language);

    let llm_req = LlmRequest {
        messages,
        temperature: config.temperature,
        max_tokens: config.max_tokens,
        stream: true,
    };

    let sources = pipeline_output.sources;
    llm_provider.stream(&llm_req, tx).await?;

    Ok(sources)
}

#[cfg(test)]
mod tests {
    use super::*;
    use crate::services::retrieval_pipeline::assemble_context;
    use crate::services::search::SearchResult;

    #[test]
    fn test_analyze_chitchat() {
        let analysis = analyze_query("你好", &[]);
        assert_eq!(analysis.intent, QueryIntent::Chitchat);
        assert!(!analysis.needs_retrieval);
    }

    #[test]
    fn test_analyze_factual() {
        let analysis = analyze_query("什么是向量数据库？", &[]);
        assert_eq!(analysis.intent, QueryIntent::Factual);
        assert!(analysis.needs_retrieval);
    }

    #[test]
    fn test_analyze_comparison() {
        let analysis = analyze_query("对比 Rust 和 Go 的性能", &[]);
        assert_eq!(analysis.intent, QueryIntent::Comparison);
        assert!(analysis.needs_retrieval);
    }

    #[test]
    fn test_analyze_summary() {
        let analysis = analyze_query("请总结这篇文档的核心观点", &[]);
        assert_eq!(analysis.intent, QueryIntent::Summary);
        assert!(analysis.needs_retrieval);
    }

    #[test]
    fn test_analyze_exploratory() {
        let analysis = analyze_query("如何配置 Kubernetes 集群？", &[]);
        assert_eq!(analysis.intent, QueryIntent::Exploratory);
        assert!(analysis.needs_retrieval);
    }

    #[test]
    fn test_analyze_with_history_context() {
        let history = vec![
            LlmMessage { role: "user".into(), content: "What is RAG?".into() },
            LlmMessage { role: "assistant".into(), content: "RAG stands for...".into() },
        ];
        let analysis = analyze_query("How does it work?", &history);
        assert!(analysis.rewritten_query.contains("previous discussion"));
    }

    #[test]
    fn test_assemble_context_basic() {
        let results = vec![
            SearchResult {
                chunk_id: Uuid::new_v4(),
                document_id: Uuid::new_v4(),
                content: "Hello world content".to_string(),
                heading_path: Some("Ch1 > Intro".to_string()),
                page_start: Some(1),
                page_end: Some(1),
                relevance_score: 0.95,
                ..Default::default()
            },
            SearchResult {
                chunk_id: Uuid::new_v4(),
                document_id: Uuid::new_v4(),
                content: "Second chunk content".to_string(),
                relevance_score: 0.85,
                ..Default::default()
            },
        ];

        let (context, sources) = assemble_context(&results, 10000);
        assert_eq!(sources.len(), 2);
        assert!(context.contains("[Source 1"));
        assert!(context.contains("[Source 2"));
        assert!(context.contains("Hello world content"));
        assert_eq!(sources[0].index, 1);
        assert_eq!(sources[1].index, 2);
    }

    #[test]
    fn test_assemble_context_token_budget() {
        let results: Vec<SearchResult> = (0..100)
            .map(|i| SearchResult {
                chunk_id: Uuid::new_v4(),
                document_id: Uuid::new_v4(),
                content: format!("Chunk {} with some content repeated many times to fill space", i),
                page_start: Some(i),
                page_end: Some(i),
                relevance_score: 1.0 - (i as f64 * 0.01),
                ..Default::default()
            })
            .collect();

        let (context, sources) = assemble_context(&results, 500);
        assert!(context.len() <= 600);
        assert!(sources.len() < 100);
    }

    #[test]
    fn test_build_prompt_chinese() {
        let messages = build_prompt("什么是RAG？", "一些上下文内容", &[], "zh");
        assert_eq!(messages[0].role, "system");
        assert!(messages[0].content.contains("TrustRAG"));
        assert_eq!(messages.last().unwrap().role, "user");
        assert!(messages.last().unwrap().content.contains("什么是RAG？"));
    }

    #[test]
    fn test_build_prompt_english() {
        let messages = build_prompt("What is RAG?", "some context", &[], "en");
        assert!(messages[0].content.contains("reference materials"));
    }

    #[test]
    fn test_build_chitchat_prompt() {
        let messages = build_chitchat_prompt("你好", &[]);
        assert_eq!(messages.len(), 2);
        assert_eq!(messages[0].role, "system");
        assert_eq!(messages[1].content, "你好");
    }

    #[test]
    fn test_rag_config_defaults() {
        let config = RagConfig::default();
        assert_eq!(config.max_context_chars, 12000);
        assert_eq!(config.search_top_k, 10);
        assert_eq!(config.temperature, 0.1);
        assert_eq!(config.language, "zh");
    }

    #[test]
    fn test_parse_follow_up_questions() {
        let raw = r#"["What about X?", "How does Y work?", "Can you compare Z?"]"#;
        let parsed = parse_follow_up_questions(raw);
        assert_eq!(parsed.len(), 3);
        assert_eq!(parsed[0], "What about X?");
    }

    #[test]
    fn test_parse_follow_up_questions_fallback() {
        let raw = "1. Question one?\n2. Question two?";
        let parsed = parse_follow_up_questions(raw);
        assert_eq!(parsed.len(), 2);
    }
}

pub async fn generate_follow_up_questions(
    llm: &dyn LlmProvider,
    query: &str,
    answer: &str,
) -> Vec<String> {
    let prompt = format!(
        "Based on the following Q&A, generate exactly 3 short follow-up questions the user might ask next.\n\
        Return as a JSON array of strings. Example: [\"question1\", \"question2\", \"question3\"]\n\n\
        User question: {query}\n\
        Answer (abbreviated): {abbreviated}\n\n\
        JSON array:",
        query = query,
        abbreviated = {
            let truncated: String = answer.chars().take(500).collect();
            truncated
        },
    );

    let req = LlmRequest {
        messages: vec![LlmMessage {
            role: "user".to_string(),
            content: prompt,
        }],
        temperature: 0.7,
        max_tokens: 200,
        stream: false,
    };

    match llm.generate(&req).await {
        Ok(resp) => parse_follow_up_questions(&resp.content),
        Err(e) => {
            tracing::warn!("Failed to generate follow-up questions: {e}");
            vec![]
        }
    }
}

pub fn parse_follow_up_questions(text: &str) -> Vec<String> {
    if let Ok(arr) = serde_json::from_str::<Vec<String>>(text) {
        return arr.into_iter().take(3).collect();
    }

    let trimmed = text.trim();
    if let Some(start) = trimmed.find('[') {
        if let Some(end) = trimmed.rfind(']') {
            if let Ok(arr) = serde_json::from_str::<Vec<String>>(&trimmed[start..=end]) {
                return arr.into_iter().take(3).collect();
            }
        }
    }

    let lines: Vec<String> = trimmed
        .lines()
        .filter_map(|l| {
            let l = l.trim();
            let stripped = l
                .trim_start_matches(|c: char| c.is_ascii_digit() || c == '.' || c == '-' || c == '*' || c == ' ');
            let stripped = stripped.trim().trim_matches('"').trim();
            if stripped.len() > 5 { Some(stripped.to_string()) } else { None }
        })
        .take(3)
        .collect();

    lines
}
