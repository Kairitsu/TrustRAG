use serde::{Deserialize, Serialize};
use uuid::Uuid;

use crate::db::DbPool;
use crate::services::search::{self, SearchConfig, SearchMode, SearchResult};
use crate::services::reranker::{self, ReRankConfig, RerankerProvider};
use crate::traits::embedding_provider::EmbeddingProvider;
use crate::traits::llm_provider::LlmProvider;

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct RetrievalPipelineConfig {
    pub dense_top_k: usize,
    pub sparse_top_k: usize,
    pub fusion_top_k: usize,
    pub final_top_k: usize,
    pub max_context_chars: usize,
    pub min_score: f64,
    pub search_mode: SearchMode,
    pub enable_query_expansion: bool,
    pub enable_rerank: bool,
    pub enable_trace: bool,
    pub rerank: ReRankConfig,
    pub rrf_k: f64,
}

impl Default for RetrievalPipelineConfig {
    fn default() -> Self {
        Self {
            dense_top_k: 20,
            sparse_top_k: 20,
            fusion_top_k: 20,
            final_top_k: 10,
            max_context_chars: 12000,
            min_score: 0.3,
            search_mode: SearchMode::Hybrid,
            enable_query_expansion: false,
            enable_rerank: false,
            enable_trace: false,
            rerank: ReRankConfig::default(),
            rrf_k: 60.0,
        }
    }
}

impl RetrievalPipelineConfig {
    pub fn to_search_config(&self) -> SearchConfig {
        let retrieval_k = match self.search_mode {
            SearchMode::Hybrid => self.fusion_top_k * 2,
            _ => self.final_top_k,
        };
        SearchConfig {
            mode: self.search_mode.clone(),
            top_k: retrieval_k,
            min_score: self.min_score,
            use_mmr: false,
            mmr_lambda: 0.7,
            rrf_k: self.rrf_k,
        }
    }
}

#[derive(Debug, Clone, Serialize)]
pub struct AssembledSource {
    pub index: usize,
    pub chunk_id: Uuid,
    pub document_id: Uuid,
    pub heading_path: Option<String>,
    pub page_start: Option<i32>,
    pub page_end: Option<i32>,
    pub content: String,
    pub score: f64,
}

#[derive(Debug, Clone, Serialize)]
pub struct RetrievalPipelineOutput {
    pub context: String,
    pub sources: Vec<AssembledSource>,
    pub trace: Option<RetrievalTrace>,
}

#[derive(Debug, Clone, Serialize)]
pub struct ScoredChunkRef {
    pub chunk_id: Uuid,
    pub document_id: Uuid,
    pub score: f64,
    pub rank: usize,
}

#[derive(Debug, Clone, Serialize)]
pub struct RetrievalTimings {
    pub query_expansion_ms: u64,
    pub search_ms: u64,
    pub rerank_ms: u64,
    pub context_assembly_ms: u64,
    pub total_ms: u64,
}

#[derive(Debug, Clone, Serialize)]
pub struct RetrievalTrace {
    pub original_query: String,
    pub rewritten_query: String,
    pub expanded_queries: Vec<String>,
    pub search_results_count: usize,
    pub reranked_results_count: usize,
    pub final_sources_count: usize,
    pub search_results: Vec<ScoredChunkRef>,
    pub reranked_results: Vec<ScoredChunkRef>,
    pub timings: RetrievalTimings,
}

/// Query expansion: generate alternative search queries via LLM
async fn expand_query(
    query: &str,
    llm_provider: &dyn LlmProvider,
) -> Vec<String> {
    use crate::traits::llm_provider::{LlmMessage, LlmRequest};

    let prompt = format!(
        "Given the user query below, generate 2 alternative search queries that capture \
         different aspects or phrasings of the same information need. Return ONLY a JSON \
         array of strings, no explanation.\n\nUser query: {}\n\nAlternative queries:",
        query
    );

    let req = LlmRequest {
        messages: vec![
            LlmMessage {
                role: "system".to_string(),
                content: "You are a search query expansion assistant. Output only a JSON array of strings.".to_string(),
            },
            LlmMessage {
                role: "user".to_string(),
                content: prompt,
            },
        ],
        temperature: 0.3,
        max_tokens: 200,
        stream: false,
    };

    match llm_provider.generate(&req).await {
        Ok(resp) => {
            let content = resp.content.trim().to_string();
            let json_str = if let Some(start) = content.find('[') {
                if let Some(end) = content.rfind(']') {
                    &content[start..=end]
                } else {
                    &content
                }
            } else {
                &content
            };

            match serde_json::from_str::<Vec<String>>(json_str) {
                Ok(queries) => {
                    tracing::info!(original = query, expanded = ?queries, "Query expansion succeeded");
                    queries.into_iter().take(3).collect()
                }
                Err(_) => {
                    tracing::warn!("Failed to parse query expansion response: {}", content);
                    vec![]
                }
            }
        }
        Err(e) => {
            tracing::warn!("Query expansion LLM call failed: {}", e);
            vec![]
        }
    }
}

/// Search with optional query expansion: primary search + deduplicated expanded searches
async fn search_with_expansion(
    pool: &DbPool,
    embedding_provider: &dyn EmbeddingProvider,
    llm_provider: &dyn LlmProvider,
    workspace_id: Uuid,
    query: &str,
    search_config: &SearchConfig,
    document_scope: Option<&[Uuid]>,
    expand: bool,
) -> anyhow::Result<(Vec<SearchResult>, Vec<String>)> {
    let primary = search::hybrid_search(
        pool, embedding_provider, workspace_id, query, search_config, document_scope,
    ).await?;

    if !expand {
        return Ok((primary.results, vec![]));
    }

    let expanded_queries = expand_query(query, llm_provider).await;
    if expanded_queries.is_empty() {
        return Ok((primary.results, vec![]));
    }

    let mut all_results = primary.results;
    let mut seen_ids: std::collections::HashSet<Uuid> = all_results.iter().map(|r| r.chunk_id).collect();

    for eq in &expanded_queries {
        match search::hybrid_search(
            pool, embedding_provider, workspace_id, eq, search_config, document_scope,
        ).await {
            Ok(resp) => {
                for r in resp.results {
                    if seen_ids.insert(r.chunk_id) {
                        all_results.push(r);
                    }
                }
            }
            Err(e) => {
                tracing::warn!("Expanded query search failed for '{}': {}", eq, e);
            }
        }
    }

    all_results.sort_by(|a, b| b.relevance_score.partial_cmp(&a.relevance_score).unwrap_or(std::cmp::Ordering::Equal));

    Ok((all_results, expanded_queries))
}

/// Assemble context string and source list from ranked search results
pub fn assemble_context(
    results: &[SearchResult],
    max_context_chars: usize,
) -> (String, Vec<AssembledSource>) {
    let mut sources = Vec::new();
    let mut context_parts = Vec::new();
    let mut total_chars = 0;

    for (i, result) in results.iter().enumerate() {
        let source_header = format!(
            "[Source {}{}{}]",
            i + 1,
            result
                .heading_path
                .as_ref()
                .map(|h| format!(" | {}", h))
                .unwrap_or_default(),
            result
                .page_start
                .map(|p| format!(" | p.{}", p))
                .unwrap_or_default(),
        );

        let entry = format!("{}\n{}", source_header, result.content);
        if total_chars + entry.len() > max_context_chars {
            break;
        }
        total_chars += entry.len();

        sources.push(AssembledSource {
            index: i + 1,
            chunk_id: result.chunk_id,
            document_id: result.document_id,
            heading_path: result.heading_path.clone(),
            page_start: result.page_start,
            page_end: result.page_end,
            content: result.content.clone(),
            score: result.relevance_score,
        });

        context_parts.push(entry);
    }

    (context_parts.join("\n\n"), sources)
}

fn results_to_refs(results: &[SearchResult]) -> Vec<ScoredChunkRef> {
    results.iter().enumerate().map(|(i, r)| ScoredChunkRef {
        chunk_id: r.chunk_id,
        document_id: r.document_id,
        score: r.relevance_score,
        rank: i + 1,
    }).collect()
}

/// The unified retrieval pipeline used by both streaming and non-streaming RAG paths.
pub async fn run(
    pool: &DbPool,
    embedding_provider: &dyn EmbeddingProvider,
    llm_provider: &dyn LlmProvider,
    workspace_id: Uuid,
    query: &str,
    document_scope: Option<&[Uuid]>,
    config: &RetrievalPipelineConfig,
) -> anyhow::Result<RetrievalPipelineOutput> {
    run_with_reranker(pool, embedding_provider, llm_provider, workspace_id, query, document_scope, config, None).await
}

pub async fn run_with_reranker(
    pool: &DbPool,
    embedding_provider: &dyn EmbeddingProvider,
    llm_provider: &dyn LlmProvider,
    workspace_id: Uuid,
    query: &str,
    document_scope: Option<&[Uuid]>,
    config: &RetrievalPipelineConfig,
    reranker_provider: Option<&dyn RerankerProvider>,
) -> anyhow::Result<RetrievalPipelineOutput> {
    let pipeline_start = std::time::Instant::now();

    let search_config = config.to_search_config();

    // Step 1: Search with optional expansion
    let expansion_start = std::time::Instant::now();
    let (raw_results, expanded_queries) = search_with_expansion(
        pool,
        embedding_provider,
        llm_provider,
        workspace_id,
        query,
        &search_config,
        document_scope,
        config.enable_query_expansion,
    ).await?;
    let expansion_ms = expansion_start.elapsed().as_millis() as u64;

    let search_refs = if config.enable_trace { results_to_refs(&raw_results) } else { vec![] };

    // Step 2: Rerank
    let rerank_start = std::time::Instant::now();
    let reranked = if config.enable_rerank {
        reranker::rerank_with_provider(
            raw_results,
            query,
            &config.rerank,
            llm_provider,
            reranker_provider,
        ).await?
    } else {
        let mut r = raw_results;
        r.truncate(config.final_top_k);
        r
    };
    let rerank_ms = rerank_start.elapsed().as_millis() as u64;

    let reranked_refs = if config.enable_trace { results_to_refs(&reranked) } else { vec![] };

    // Step 3: Assemble context
    let assembly_start = std::time::Instant::now();
    let (context, sources) = assemble_context(&reranked, config.max_context_chars);
    let assembly_ms = assembly_start.elapsed().as_millis() as u64;

    let total_ms = pipeline_start.elapsed().as_millis() as u64;

    tracing::info!(
        query_len = query.len(),
        search_results = search_refs.len().max(reranked.len()),
        reranked_count = reranked_refs.len().max(reranked.len()),
        final_sources = sources.len(),
        total_ms = total_ms,
        "Retrieval pipeline completed"
    );

    let trace = if config.enable_trace {
        Some(RetrievalTrace {
            original_query: query.to_string(),
            rewritten_query: query.to_string(),
            expanded_queries,
            search_results_count: search_refs.len(),
            reranked_results_count: reranked_refs.len(),
            final_sources_count: sources.len(),
            search_results: search_refs,
            reranked_results: reranked_refs,
            timings: RetrievalTimings {
                query_expansion_ms: expansion_ms,
                search_ms: expansion_ms,
                rerank_ms,
                context_assembly_ms: assembly_ms,
                total_ms,
            },
        })
    } else {
        None
    };

    Ok(RetrievalPipelineOutput {
        context,
        sources,
        trace,
    })
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn test_default_config() {
        let config = RetrievalPipelineConfig::default();
        assert_eq!(config.dense_top_k, 20);
        assert_eq!(config.max_context_chars, 12000);
        assert!(!config.enable_rerank);
        assert!(!config.enable_query_expansion);
        assert!(!config.enable_trace);
    }

    #[test]
    fn test_config_to_search_config() {
        let config = RetrievalPipelineConfig::default();
        let sc = config.to_search_config();
        assert_eq!(sc.mode, SearchMode::Hybrid);
        assert_eq!(sc.top_k, 40); // fusion_top_k * 2 for hybrid
    }

    #[test]
    fn test_assemble_context_basic() {
        let results = vec![
            SearchResult {
                chunk_id: Uuid::new_v4(),
                document_id: Uuid::new_v4(),
                content: "Test content one".to_string(),
                heading_path: Some("Ch1 > Intro".to_string()),
                page_start: Some(1),
                page_end: Some(1),
                relevance_score: 0.95,
                ..Default::default()
            },
            SearchResult {
                chunk_id: Uuid::new_v4(),
                document_id: Uuid::new_v4(),
                content: "Test content two".to_string(),
                relevance_score: 0.85,
                ..Default::default()
            },
        ];

        let (context, sources) = assemble_context(&results, 10000);
        assert_eq!(sources.len(), 2);
        assert!(context.contains("[Source 1"));
        assert!(context.contains("[Source 2"));
        assert_eq!(sources[0].index, 1);
        assert_eq!(sources[1].index, 2);
    }

    #[test]
    fn test_assemble_context_budget() {
        let results: Vec<SearchResult> = (0..100)
            .map(|i| SearchResult {
                chunk_id: Uuid::new_v4(),
                document_id: Uuid::new_v4(),
                content: format!("Chunk {} with content repeated many times to fill space", i),
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
    fn test_assemble_context_empty() {
        let (context, sources) = assemble_context(&[], 10000);
        assert!(context.is_empty());
        assert!(sources.is_empty());
    }

    #[test]
    fn test_results_to_refs() {
        let results = vec![
            SearchResult {
                chunk_id: Uuid::new_v4(),
                document_id: Uuid::new_v4(),
                content: "test".to_string(),
                relevance_score: 0.9,
                ..Default::default()
            },
        ];
        let refs = results_to_refs(&results);
        assert_eq!(refs.len(), 1);
        assert_eq!(refs[0].rank, 1);
        assert!((refs[0].score - 0.9).abs() < 1e-10);
    }
}
