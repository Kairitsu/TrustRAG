use anyhow::Result;
use serde::{Deserialize, Serialize};

use crate::services::endpoint_resolver::{resolve_stored_endpoint, ModelType, ResolvedEndpoint};
use crate::services::search::SearchResult;
use crate::traits::llm_provider::{LlmMessage, LlmProvider, LlmRequest};

// ── Provider trait ──

/// Abstraction for external reranking services (Jina, Cohere, local cross-encoder, etc.)
#[async_trait::async_trait]
pub trait RerankerProvider: Send + Sync {
    /// Score each (query, document) pair. Returns scores in the same order as `documents`.
    async fn score(&self, query: &str, documents: &[&str]) -> Result<Vec<f64>>;
    fn name(&self) -> &str;
}

// ── Config ──

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct ReRankConfig {
    pub enabled: bool,
    pub top_n: usize,
    pub method: ReRankMethod,
}

#[derive(Debug, Clone, Serialize, Deserialize, PartialEq)]
#[serde(rename_all = "snake_case")]
pub enum ReRankMethod {
    LlmScoring,
    CrossEncoder,
    CrossEncoderHttp,
    LocalFastEmbed,
    ExternalApi,
}

impl Default for ReRankConfig {
    fn default() -> Self {
        Self {
            enabled: false,
            top_n: 5,
            method: ReRankMethod::LlmScoring,
        }
    }
}

// ── Public entry point ──

/// Rerank search results. If `reranker_provider` is Some and method is CrossEncoder,
/// uses the external provider; otherwise falls back to LLM scoring.
pub async fn rerank(
    results: Vec<SearchResult>,
    query: &str,
    config: &ReRankConfig,
    llm_provider: &dyn LlmProvider,
) -> Result<Vec<SearchResult>> {
    rerank_with_provider(results, query, config, llm_provider, None).await
}

pub async fn rerank_with_provider(
    results: Vec<SearchResult>,
    query: &str,
    config: &ReRankConfig,
    llm_provider: &dyn LlmProvider,
    reranker_provider: Option<&dyn RerankerProvider>,
) -> Result<Vec<SearchResult>> {
    if !config.enabled || results.is_empty() {
        return Ok(results);
    }

    match config.method {
        ReRankMethod::LlmScoring => llm_rerank(results, query, config.top_n, llm_provider).await,
        ReRankMethod::CrossEncoder | ReRankMethod::CrossEncoderHttp | ReRankMethod::LocalFastEmbed | ReRankMethod::ExternalApi => {
            if let Some(provider) = reranker_provider {
                cross_encoder_rerank(results, query, config.top_n, provider).await
            } else {
                tracing::warn!(
                    method = ?config.method,
                    "Reranker provider requested but not configured, falling back to LLM scoring"
                );
                llm_rerank(results, query, config.top_n, llm_provider).await
            }
        }
    }
}

async fn llm_rerank(
    results: Vec<SearchResult>,
    query: &str,
    top_n: usize,
    llm_provider: &dyn LlmProvider,
) -> Result<Vec<SearchResult>> {
    let candidates: Vec<_> = results.iter().take(20).collect();
    if candidates.is_empty() {
        return Ok(results);
    }

    let mut passages = String::new();
    for (i, r) in candidates.iter().enumerate() {
        let snippet: String = r.content.chars().take(300).collect();
        passages.push_str(&format!("[{}] {}\n\n", i, snippet.replace('\n', " ")));
    }

    let system_prompt = "You are a relevance ranking assistant. Given a query and passages, \
        rank the passages by relevance to the query. Return ONLY a JSON array of passage \
        indices in descending order of relevance, e.g. [3, 0, 5, 1, 2]. No explanation.";

    let user_prompt = format!(
        "Query: {}\n\nPassages:\n{}\n\nReturn the indices ranked by relevance (most relevant first), as a JSON array:",
        query, passages
    );

    let req = LlmRequest {
        messages: vec![
            LlmMessage {
                role: "system".to_string(),
                content: system_prompt.to_string(),
            },
            LlmMessage {
                role: "user".to_string(),
                content: user_prompt,
            },
        ],
        temperature: 0.0,
        max_tokens: 200,
        stream: false,
    };

    let resp = llm_provider.generate(&req).await;

    match resp {
        Ok(response) => {
            let ranked_indices = parse_ranking_response(&response.content, candidates.len());

            let mut reranked: Vec<SearchResult> = Vec::new();
            let mut used = std::collections::HashSet::new();

            for idx in ranked_indices {
                if idx < candidates.len() && !used.contains(&idx) {
                    let mut result = candidates[idx].clone();
                    result.relevance_score = 1.0 - (reranked.len() as f64 / candidates.len() as f64);
                    reranked.push(result);
                    used.insert(idx);
                }
            }

            for (i, r) in candidates.iter().enumerate() {
                if !used.contains(&i) {
                    reranked.push((*r).clone());
                }
            }

            reranked.truncate(top_n);

            tracing::info!(
                query_len = query.len(),
                candidates = candidates.len(),
                reranked = reranked.len(),
                "LLM re-ranking completed"
            );

            Ok(reranked)
        }
        Err(e) => {
            tracing::warn!("LLM re-ranking failed, returning original order: {}", e);
            let mut fallback = results;
            fallback.truncate(top_n);
            Ok(fallback)
        }
    }
}

async fn cross_encoder_rerank(
    results: Vec<SearchResult>,
    query: &str,
    top_n: usize,
    provider: &dyn RerankerProvider,
) -> Result<Vec<SearchResult>> {
    let candidates: Vec<_> = results.iter().take(20).collect();
    if candidates.is_empty() {
        return Ok(results);
    }

    let docs: Vec<&str> = candidates.iter().map(|r| r.content.as_str()).collect();

    match provider.score(query, &docs).await {
        Ok(scores) => {
            let mut scored: Vec<(usize, f64)> = scores.into_iter().enumerate().collect();
            scored.sort_by(|a, b| b.1.partial_cmp(&a.1).unwrap_or(std::cmp::Ordering::Equal));

            let reranked: Vec<SearchResult> = scored
                .into_iter()
                .take(top_n)
                .map(|(idx, score)| {
                    let mut result = candidates[idx].clone();
                    result.rerank_score = Some(score);
                    result.relevance_score = score;
                    result
                })
                .collect();

            tracing::info!(
                provider = provider.name(),
                query_len = query.len(),
                candidates = candidates.len(),
                reranked = reranked.len(),
                "Cross-encoder re-ranking completed"
            );

            Ok(reranked)
        }
        Err(e) => {
            tracing::warn!(
                provider = provider.name(),
                error = %e,
                "Cross-encoder re-ranking failed, returning original order"
            );
            let mut fallback = results;
            fallback.truncate(top_n);
            Ok(fallback)
        }
    }
}

// ── HTTP-based reranker (Jina / Cohere compatible) ──

/// Generic HTTP reranker that works with Jina Reranker API and Cohere Rerank API.
pub struct HttpRerankerProvider {
    client: reqwest::Client,
    api_url: String,
    api_key: String,
    model: String,
    provider_name: String,
}

pub fn build_http_reranker(
    provider: &str,
    api_base_url: &str,
    endpoint_mode: Option<&str>,
    api_key: String,
    model: String,
    timeout_secs: u64,
) -> (ResolvedEndpoint, HttpRerankerProvider) {
    let resolved = resolve_stored_endpoint(
        ModelType::Rerank,
        provider,
        endpoint_mode,
        api_base_url,
        &model,
    );
    let reranker = HttpRerankerProvider::with_timeout(
        resolved.final_url.clone(),
        api_key,
        model,
        provider.to_string(),
        timeout_secs,
    );
    (resolved, reranker)
}

impl HttpRerankerProvider {
    pub fn new(api_url: String, api_key: String, model: String, provider_name: String) -> Self {
        Self::with_timeout(api_url, api_key, model, provider_name, 30)
    }

    pub fn api_url(&self) -> &str {
        &self.api_url
    }

    pub fn with_timeout(api_url: String, api_key: String, model: String, provider_name: String, timeout_secs: u64) -> Self {
        let client = reqwest::Client::builder()
            .timeout(std::time::Duration::from_secs(timeout_secs))
            .build()
            .unwrap_or_else(|_| reqwest::Client::new());
        Self {
            client,
            api_url,
            api_key,
            model,
            provider_name,
        }
    }
}

#[derive(Serialize)]
struct RerankRequest {
    model: String,
    query: String,
    documents: Vec<String>,
    top_n: Option<usize>,
}

#[derive(Deserialize)]
struct RerankResponse {
    results: Vec<RerankResult>,
}

#[derive(Deserialize)]
struct RerankResult {
    index: usize,
    relevance_score: f64,
}

#[async_trait::async_trait]
impl RerankerProvider for HttpRerankerProvider {
    async fn score(&self, query: &str, documents: &[&str]) -> Result<Vec<f64>> {
        let body = RerankRequest {
            model: self.model.clone(),
            query: query.to_string(),
            documents: documents.iter().map(|d| d.to_string()).collect(),
            top_n: None,
        };

        let resp = self.client
            .post(&self.api_url)
            .bearer_auth(&self.api_key)
            .json(&body)
            .send()
            .await?;

        if !resp.status().is_success() {
            let status = resp.status();
            let text = resp.text().await.unwrap_or_default();
            anyhow::bail!("Reranker API error {}: {}", status, text);
        }

        let rerank_resp: RerankResponse = resp.json().await?;

        let mut scores = vec![0.0f64; documents.len()];
        for r in rerank_resp.results {
            if r.index < scores.len() {
                scores[r.index] = r.relevance_score;
            }
        }

        Ok(scores)
    }

    fn name(&self) -> &str {
        &self.provider_name
    }
}

fn parse_ranking_response(content: &str, max_idx: usize) -> Vec<usize> {
    let trimmed = content.trim();

    let json_str = if let Some(start) = trimmed.find('[') {
        if let Some(end) = trimmed.rfind(']') {
            &trimmed[start..=end]
        } else {
            trimmed
        }
    } else {
        trimmed
    };

    if let Ok(indices) = serde_json::from_str::<Vec<usize>>(json_str) {
        return indices.into_iter().filter(|i| *i < max_idx).collect();
    }

    let mut indices: Vec<usize> = Vec::new();
    for part in trimmed.split(|c: char| !c.is_ascii_digit()) {
        if let Ok(n) = part.parse::<usize>() {
            if n < max_idx {
                indices.push(n);
            }
        }
    }
    indices
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn test_parse_ranking_json_array() {
        let result = parse_ranking_response("[3, 0, 5, 1, 2]", 6);
        assert_eq!(result, vec![3, 0, 5, 1, 2]);
    }

    #[test]
    fn test_parse_ranking_with_text() {
        let result = parse_ranking_response("The ranking is: [2, 0, 1]", 3);
        assert_eq!(result, vec![2, 0, 1]);
    }

    #[test]
    fn test_parse_ranking_filters_out_of_range() {
        let result = parse_ranking_response("[0, 1, 10, 2]", 3);
        assert_eq!(result, vec![0, 1, 2]);
    }

    #[test]
    fn test_parse_ranking_fallback_numbers() {
        let result = parse_ranking_response("3, 1, 0, 2", 4);
        assert_eq!(result, vec![3, 1, 0, 2]);
    }

    #[test]
    fn test_default_config_disabled() {
        let config = ReRankConfig::default();
        assert!(!config.enabled);
        assert_eq!(config.top_n, 5);
    }

    #[test]
    fn test_rerank_method_serde_roundtrip() {
        let methods = vec![
            ReRankMethod::LlmScoring,
            ReRankMethod::CrossEncoder,
            ReRankMethod::CrossEncoderHttp,
            ReRankMethod::LocalFastEmbed,
            ReRankMethod::ExternalApi,
        ];
        for method in methods {
            let json = serde_json::to_string(&method).unwrap();
            let deserialized: ReRankMethod = serde_json::from_str(&json).unwrap();
            assert_eq!(method, deserialized);
        }
    }

    #[test]
    fn test_rerank_method_cross_encoder_http_json() {
        let method = ReRankMethod::CrossEncoderHttp;
        let json = serde_json::to_string(&method).unwrap();
        assert_eq!(json, "\"cross_encoder_http\"");
    }

    #[test]
    fn test_rerank_method_local_fast_embed_json() {
        let method = ReRankMethod::LocalFastEmbed;
        let json = serde_json::to_string(&method).unwrap();
        assert_eq!(json, "\"local_fast_embed\"");
    }

    #[test]
    fn test_rerank_method_external_api_json() {
        let method = ReRankMethod::ExternalApi;
        let json = serde_json::to_string(&method).unwrap();
        assert_eq!(json, "\"external_api\"");
    }

    #[test]
    fn test_rerank_config_with_new_methods() {
        let config = ReRankConfig {
            enabled: true,
            top_n: 10,
            method: ReRankMethod::CrossEncoderHttp,
        };
        let json = serde_json::to_string(&config).unwrap();
        let back: ReRankConfig = serde_json::from_str(&json).unwrap();
        assert_eq!(back.method, ReRankMethod::CrossEncoderHttp);
        assert_eq!(back.top_n, 10);
    }

    #[test]
    fn test_cross_encoder_config() {
        let config = ReRankConfig {
            enabled: true,
            top_n: 3,
            method: ReRankMethod::CrossEncoder,
        };
        assert!(config.enabled);
        assert_eq!(config.method, ReRankMethod::CrossEncoder);
    }

    struct MockRerankerProvider {
        scores: Vec<f64>,
    }

    #[async_trait::async_trait]
    impl RerankerProvider for MockRerankerProvider {
        async fn score(&self, _query: &str, _documents: &[&str]) -> Result<Vec<f64>> {
            Ok(self.scores.clone())
        }
        fn name(&self) -> &str {
            "mock"
        }
    }

    #[tokio::test]
    async fn test_cross_encoder_rerank_basic() {
        let results = vec![
            SearchResult {
                chunk_id: uuid::Uuid::new_v4(),
                document_id: uuid::Uuid::new_v4(),
                content: "Low relevance doc".to_string(),
                relevance_score: 0.5,
                ..Default::default()
            },
            SearchResult {
                chunk_id: uuid::Uuid::new_v4(),
                document_id: uuid::Uuid::new_v4(),
                content: "High relevance doc".to_string(),
                relevance_score: 0.3,
                ..Default::default()
            },
        ];

        let provider = MockRerankerProvider {
            scores: vec![0.2, 0.9],
        };

        let reranked = cross_encoder_rerank(results, "test query", 2, &provider).await.unwrap();
        assert_eq!(reranked.len(), 2);
        assert_eq!(reranked[0].content, "High relevance doc");
        assert!((reranked[0].relevance_score - 0.9).abs() < 1e-10);
    }

    #[tokio::test]
    async fn test_cross_encoder_rerank_respects_top_n() {
        let results: Vec<SearchResult> = (0..5)
            .map(|i| SearchResult {
                chunk_id: uuid::Uuid::new_v4(),
                document_id: uuid::Uuid::new_v4(),
                content: format!("doc {}", i),
                relevance_score: 0.5,
                ..Default::default()
            })
            .collect();

        let provider = MockRerankerProvider {
            scores: vec![0.1, 0.9, 0.5, 0.3, 0.7],
        };

        let reranked = cross_encoder_rerank(results, "query", 3, &provider).await.unwrap();
        assert_eq!(reranked.len(), 3);
        assert_eq!(reranked[0].content, "doc 1");
        assert_eq!(reranked[1].content, "doc 4");
        assert_eq!(reranked[2].content, "doc 2");
    }

    struct FailingRerankerProvider;

    #[async_trait::async_trait]
    impl RerankerProvider for FailingRerankerProvider {
        async fn score(&self, _query: &str, _documents: &[&str]) -> Result<Vec<f64>> {
            anyhow::bail!("API connection failed")
        }
        fn name(&self) -> &str {
            "failing"
        }
    }

    #[tokio::test]
    async fn test_cross_encoder_fallback_on_error() {
        let results = vec![
            SearchResult {
                chunk_id: uuid::Uuid::new_v4(),
                document_id: uuid::Uuid::new_v4(),
                content: "only doc".to_string(),
                relevance_score: 0.8,
                ..Default::default()
            },
        ];

        let provider = FailingRerankerProvider;
        let reranked = cross_encoder_rerank(results, "query", 5, &provider).await.unwrap();
        assert_eq!(reranked.len(), 1);
        assert_eq!(reranked[0].content, "only doc");
    }
}
