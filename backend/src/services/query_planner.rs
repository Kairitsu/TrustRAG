use serde::{Deserialize, Serialize};

use crate::services::metadata::DomainProfile;
use crate::services::rag::{QueryAnalysis, QueryIntent};
use crate::services::search::SearchMode;

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
        },

        QueryIntent::Factual => {
            let (top_k, rerank) = scale_for_corpus(corpus_size, 10, 5);
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
}
