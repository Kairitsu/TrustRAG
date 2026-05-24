use serde::{Deserialize, Serialize};

use crate::services::metadata::DomainProfile;
use crate::services::rag::{QueryAnalysis, QueryIntent};
use crate::services::search::{MetadataFilter, SearchMode};

/// High-level retrieval strategy that governs how search modes are combined.
#[derive(Debug, Clone, Serialize, Deserialize, PartialEq)]
#[serde(rename_all = "snake_case")]
pub enum RetrievalStrategy {
    SingleMode,
    HybridFusion,
    CascadeFallback,
    MultiQueryMerge,
}

impl Default for RetrievalStrategy {
    fn default() -> Self {
        Self::HybridFusion
    }
}

/// The output of the query planner: a strategy for how to retrieve information.
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct QueryPlan {
    pub search_mode: SearchMode,
    pub search_top_k: usize,
    pub final_top_k: usize,
    pub enable_query_expansion: bool,
    pub enable_rerank: bool,
    pub rerank_top_n: usize,
    pub max_context_chars: usize,
    pub confidence: f64,
    pub reasoning: String,

    #[serde(default)]
    pub retrieval_strategy: RetrievalStrategy,
    #[serde(default)]
    pub metadata_filters: MetadataFilter,
    #[serde(default, skip_serializing_if = "Vec::is_empty")]
    pub query_variants: Vec<String>,
    #[serde(default, skip_serializing_if = "Vec::is_empty")]
    pub preferred_document_types: Vec<String>,
}

impl Default for QueryPlan {
    fn default() -> Self {
        Self {
            search_mode: SearchMode::Hybrid,
            search_top_k: 10,
            final_top_k: 5,
            enable_query_expansion: true,
            enable_rerank: false,
            rerank_top_n: 5,
            max_context_chars: 6000,
            confidence: 0.5,
            reasoning: "default plan".to_string(),
            retrieval_strategy: RetrievalStrategy::default(),
            metadata_filters: MetadataFilter::default(),
            query_variants: Vec::new(),
            preferred_document_types: Vec::new(),
        }
    }
}

/// Plan the optimal retrieval strategy based on query analysis and workspace context.
pub fn plan(
    analysis: &QueryAnalysis,
    domain_profile: Option<&DomainProfile>,
    total_chunks: Option<usize>,
) -> QueryPlan {
    let corpus_size = total_chunks.unwrap_or(0);
    let has_domain_profile = domain_profile.is_some();

    let defaults = || -> (RetrievalStrategy, MetadataFilter, Vec<String>, Vec<String>) {
        (RetrievalStrategy::HybridFusion, MetadataFilter::default(), Vec::new(), Vec::new())
    };

    match analysis.intent {
        QueryIntent::Chitchat => QueryPlan {
            search_mode: SearchMode::Vector,
            search_top_k: 0,
            final_top_k: 0,
            enable_query_expansion: false,
            enable_rerank: false,
            rerank_top_n: 0,
            max_context_chars: 0,
            confidence: 1.0,
            reasoning: "Chitchat query, no retrieval needed".to_string(),
            retrieval_strategy: RetrievalStrategy::SingleMode,
            ..Default::default()
        },

        QueryIntent::Factual => {
            let (top_k, rerank) = scale_for_corpus(corpus_size, 10, 5);
            let (strategy, filters, variants, doc_types) = defaults();
            QueryPlan {
                search_mode: SearchMode::Hybrid,
                search_top_k: top_k,
                final_top_k: 5,
                enable_query_expansion: false,
                enable_rerank: rerank || has_domain_profile,
                rerank_top_n: 5,
                max_context_chars: 4000,
                confidence: 0.8,
                reasoning: "Factual query: hybrid search, focused context".to_string(),
                retrieval_strategy: strategy,
                metadata_filters: filters,
                query_variants: variants,
                preferred_document_types: doc_types,
            }
        }

        QueryIntent::Exploratory => {
            let (top_k, rerank) = scale_for_corpus(corpus_size, 15, 8);
            QueryPlan {
                search_mode: SearchMode::Hybrid,
                search_top_k: top_k,
                final_top_k: 8,
                enable_query_expansion: true,
                enable_rerank: rerank,
                rerank_top_n: 8,
                max_context_chars: 8000,
                confidence: 0.7,
                reasoning: "Exploratory query: broader retrieval with query expansion".to_string(),
                retrieval_strategy: RetrievalStrategy::MultiQueryMerge,
                ..Default::default()
            }
        }

        QueryIntent::Comparison => {
            let (top_k, rerank) = scale_for_corpus(corpus_size, 20, 10);
            QueryPlan {
                search_mode: SearchMode::Hybrid,
                search_top_k: top_k,
                final_top_k: 10,
                enable_query_expansion: true,
                enable_rerank: rerank,
                rerank_top_n: 10,
                max_context_chars: 10000,
                confidence: 0.7,
                reasoning: "Comparison query: wide retrieval to cover multiple aspects".to_string(),
                retrieval_strategy: RetrievalStrategy::CascadeFallback,
                ..Default::default()
            }
        }

        QueryIntent::Summary => {
            let (top_k, _) = scale_for_corpus(corpus_size, 20, 10);
            QueryPlan {
                search_mode: SearchMode::Hybrid,
                search_top_k: top_k,
                final_top_k: 10,
                enable_query_expansion: false,
                enable_rerank: true,
                rerank_top_n: 10,
                max_context_chars: 12000,
                confidence: 0.6,
                reasoning: "Summary query: collect many sources, rerank for coverage".to_string(),
                retrieval_strategy: RetrievalStrategy::HybridFusion,
                ..Default::default()
            }
        }
    }
}

/// Scale search parameters based on corpus size.
/// Returns (search_top_k, should_enable_rerank).
fn scale_for_corpus(corpus_size: usize, base_top_k: usize, _base_final: usize) -> (usize, bool) {
    if corpus_size == 0 {
        return (base_top_k, false);
    }

    let top_k = if corpus_size < 50 {
        base_top_k.min(corpus_size)
    } else if corpus_size < 500 {
        base_top_k
    } else {
        (base_top_k as f64 * 1.5) as usize
    };

    let rerank = corpus_size > 100;

    (top_k, rerank)
}

#[cfg(test)]
mod tests {
    use super::*;
    use crate::services::rag::QueryAnalysis;

    fn make_analysis(intent: QueryIntent) -> QueryAnalysis {
        QueryAnalysis {
            intent,
            needs_retrieval: true,
            rewritten_query: "test query".to_string(),
        }
    }

    #[test]
    fn test_chitchat_plan_no_retrieval() {
        let analysis = QueryAnalysis {
            intent: QueryIntent::Chitchat,
            needs_retrieval: false,
            rewritten_query: "hi".to_string(),
        };
        let plan = plan(&analysis, None, None);
        assert_eq!(plan.search_top_k, 0);
        assert!(!plan.enable_query_expansion);
        assert!(!plan.enable_rerank);
        assert_eq!(plan.confidence, 1.0);
    }

    #[test]
    fn test_factual_plan() {
        let analysis = make_analysis(QueryIntent::Factual);
        let plan = plan(&analysis, None, Some(200));
        assert_eq!(plan.search_mode, SearchMode::Hybrid);
        assert!(!plan.enable_query_expansion);
        assert!(plan.search_top_k <= 15);
    }

    #[test]
    fn test_exploratory_plan_enables_expansion() {
        let analysis = make_analysis(QueryIntent::Exploratory);
        let plan = plan(&analysis, None, None);
        assert!(plan.enable_query_expansion);
        assert!(plan.search_top_k >= 10);
    }

    #[test]
    fn test_comparison_plan_wide_retrieval() {
        let analysis = make_analysis(QueryIntent::Comparison);
        let plan = plan(&analysis, None, None);
        assert!(plan.search_top_k >= 15);
        assert!(plan.final_top_k >= 8);
    }

    #[test]
    fn test_summary_plan_reranks() {
        let analysis = make_analysis(QueryIntent::Summary);
        let plan = plan(&analysis, None, None);
        assert!(plan.enable_rerank);
        assert!(plan.max_context_chars >= 10000);
    }

    #[test]
    fn test_large_corpus_enables_rerank() {
        let analysis = make_analysis(QueryIntent::Factual);
        let plan = plan(&analysis, None, Some(500));
        assert!(plan.enable_rerank);
    }

    #[test]
    fn test_small_corpus_caps_top_k() {
        let analysis = make_analysis(QueryIntent::Factual);
        let plan = plan(&analysis, None, Some(5));
        assert!(plan.search_top_k <= 5);
    }

    #[test]
    fn test_domain_profile_enables_rerank_for_factual() {
        let profile = DomainProfile {
            primary_domain: Some("tech".to_string()),
            ..DomainProfile::default()
        };
        let analysis = make_analysis(QueryIntent::Factual);
        let plan = plan(&analysis, Some(&profile), Some(50));
        assert!(plan.enable_rerank);
    }

    #[test]
    fn test_scale_for_corpus_zero() {
        let (top_k, rerank) = scale_for_corpus(0, 10, 5);
        assert_eq!(top_k, 10);
        assert!(!rerank);
    }

    #[test]
    fn test_scale_for_corpus_large() {
        let (top_k, rerank) = scale_for_corpus(1000, 10, 5);
        assert!(top_k > 10);
        assert!(rerank);
    }

    #[test]
    fn test_plan_serde_roundtrip() {
        let plan = QueryPlan::default();
        let json = serde_json::to_string(&plan).unwrap();
        let deserialized: QueryPlan = serde_json::from_str(&json).unwrap();
        assert_eq!(deserialized.search_mode, plan.search_mode);
        assert_eq!(deserialized.confidence, plan.confidence);
    }

    #[test]
    fn test_retrieval_strategy_serde() {
        let strategies = vec![
            (RetrievalStrategy::SingleMode, "\"single_mode\""),
            (RetrievalStrategy::HybridFusion, "\"hybrid_fusion\""),
            (RetrievalStrategy::CascadeFallback, "\"cascade_fallback\""),
            (RetrievalStrategy::MultiQueryMerge, "\"multi_query_merge\""),
        ];
        for (s, expected) in strategies {
            let json = serde_json::to_string(&s).unwrap();
            assert_eq!(json, expected);
            let back: RetrievalStrategy = serde_json::from_str(&json).unwrap();
            assert_eq!(back, s);
        }
    }

    #[test]
    fn test_default_plan_has_extended_fields() {
        let plan = QueryPlan::default();
        assert_eq!(plan.retrieval_strategy, RetrievalStrategy::HybridFusion);
        assert!(plan.metadata_filters.is_empty());
        assert!(plan.query_variants.is_empty());
        assert!(plan.preferred_document_types.is_empty());
    }

    #[test]
    fn test_chitchat_uses_single_mode_strategy() {
        let analysis = QueryAnalysis {
            intent: QueryIntent::Chitchat,
            needs_retrieval: false,
            rewritten_query: "hi".to_string(),
        };
        let plan = plan(&analysis, None, None);
        assert_eq!(plan.retrieval_strategy, RetrievalStrategy::SingleMode);
    }

    #[test]
    fn test_exploratory_uses_multi_query_merge() {
        let analysis = make_analysis(QueryIntent::Exploratory);
        let plan = plan(&analysis, None, None);
        assert_eq!(plan.retrieval_strategy, RetrievalStrategy::MultiQueryMerge);
    }

    #[test]
    fn test_comparison_uses_cascade_fallback() {
        let analysis = make_analysis(QueryIntent::Comparison);
        let plan = plan(&analysis, None, None);
        assert_eq!(plan.retrieval_strategy, RetrievalStrategy::CascadeFallback);
    }

    #[test]
    fn test_plan_with_query_variants() {
        let mut plan = QueryPlan::default();
        plan.query_variants = vec!["variant 1".to_string(), "variant 2".to_string()];
        let json = serde_json::to_string(&plan).unwrap();
        assert!(json.contains("query_variants"));
        let back: QueryPlan = serde_json::from_str(&json).unwrap();
        assert_eq!(back.query_variants.len(), 2);
    }

    #[test]
    fn test_plan_with_preferred_document_types() {
        let mut plan = QueryPlan::default();
        plan.preferred_document_types = vec!["pdf".to_string(), "markdown".to_string()];
        let json = serde_json::to_string(&plan).unwrap();
        assert!(json.contains("preferred_document_types"));
        let back: QueryPlan = serde_json::from_str(&json).unwrap();
        assert_eq!(back.preferred_document_types, vec!["pdf", "markdown"]);
    }

    #[test]
    fn test_plan_empty_variants_omitted_in_json() {
        let plan = QueryPlan::default();
        let json = serde_json::to_string(&plan).unwrap();
        assert!(!json.contains("query_variants"));
        assert!(!json.contains("preferred_document_types"));
    }
}
