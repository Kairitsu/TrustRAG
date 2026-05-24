use anyhow::Result;
use serde::{Deserialize, Serialize};
use sqlx::FromRow;
use uuid::Uuid;

use crate::db::DbPool;
use crate::services::retrieval_pipeline::RetrievalTrace;

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct SaveTraceInput {
    pub workspace_id: Uuid,
    pub message_id: Option<Uuid>,
    pub trace: RetrievalTrace,
    pub domain_profile: Option<String>,
}

#[derive(Debug, Clone, Serialize, Deserialize, FromRow)]
pub struct RetrievalTraceRow {
    pub id: Uuid,
    pub workspace_id: Uuid,
    pub message_id: Option<Uuid>,
    pub original_query: String,
    pub rewritten_query: String,
    pub expanded_queries: serde_json::Value,
    pub search_results_count: i32,
    pub reranked_results_count: i32,
    pub final_sources_count: i32,
    pub search_results: serde_json::Value,
    pub reranked_results: serde_json::Value,
    pub timings: serde_json::Value,
    pub domain_profile: Option<String>,
    pub created_at: chrono::DateTime<chrono::Utc>,
}

#[derive(Debug, Clone, Serialize)]
pub struct RetrievalTraceSummary {
    pub id: Uuid,
    pub workspace_id: Uuid,
    pub message_id: Option<Uuid>,
    pub original_query: String,
    pub search_results_count: i32,
    pub final_sources_count: i32,
    pub total_ms: u64,
    pub domain_profile: Option<String>,
    pub created_at: chrono::DateTime<chrono::Utc>,
}

pub async fn save_trace(pool: &DbPool, input: &SaveTraceInput) -> Result<Uuid> {
    let expanded_queries = serde_json::to_value(&input.trace.expanded_queries)?;
    let search_results = serde_json::to_value(&input.trace.search_results)?;
    let reranked_results = serde_json::to_value(&input.trace.reranked_results)?;
    let timings = serde_json::to_value(&input.trace.timings)?;

    let row: (Uuid,) = sqlx::query_as(
        r#"
        INSERT INTO retrieval_traces
            (workspace_id, message_id, original_query, rewritten_query,
             expanded_queries, search_results_count, reranked_results_count,
             final_sources_count, search_results, reranked_results, timings, domain_profile)
        VALUES ($1, $2, $3, $4, $5, $6, $7, $8, $9, $10, $11, $12)
        RETURNING id
        "#,
    )
    .bind(input.workspace_id)
    .bind(input.message_id)
    .bind(&input.trace.original_query)
    .bind(&input.trace.rewritten_query)
    .bind(&expanded_queries)
    .bind(input.trace.search_results_count as i32)
    .bind(input.trace.reranked_results_count as i32)
    .bind(input.trace.final_sources_count as i32)
    .bind(&search_results)
    .bind(&reranked_results)
    .bind(&timings)
    .bind(&input.domain_profile)
    .fetch_one(pool)
    .await?;

    tracing::info!(
        trace_id = %row.0,
        workspace_id = %input.workspace_id,
        query = %input.trace.original_query,
        "Retrieval trace persisted"
    );

    Ok(row.0)
}

pub async fn get_trace(pool: &DbPool, trace_id: Uuid) -> Result<Option<RetrievalTraceRow>> {
    let row = sqlx::query_as::<_, RetrievalTraceRow>(
        "SELECT * FROM retrieval_traces WHERE id = $1",
    )
    .bind(trace_id)
    .fetch_optional(pool)
    .await?;
    Ok(row)
}

pub async fn list_traces_for_workspace(
    pool: &DbPool,
    workspace_id: Uuid,
    limit: i64,
    offset: i64,
) -> Result<Vec<RetrievalTraceSummary>> {
    let rows = sqlx::query_as::<_, RetrievalTraceRow>(
        r#"
        SELECT * FROM retrieval_traces
        WHERE workspace_id = $1
        ORDER BY created_at DESC
        LIMIT $2 OFFSET $3
        "#,
    )
    .bind(workspace_id)
    .bind(limit)
    .bind(offset)
    .fetch_all(pool)
    .await?;

    let summaries = rows
        .into_iter()
        .map(|r| {
            let total_ms = r
                .timings
                .get("total_ms")
                .and_then(|v| v.as_u64())
                .unwrap_or(0);
            RetrievalTraceSummary {
                id: r.id,
                workspace_id: r.workspace_id,
                message_id: r.message_id,
                original_query: r.original_query,
                search_results_count: r.search_results_count,
                final_sources_count: r.final_sources_count,
                total_ms,
                domain_profile: r.domain_profile,
                created_at: r.created_at,
            }
        })
        .collect();

    Ok(summaries)
}

pub async fn get_trace_for_message(
    pool: &DbPool,
    message_id: Uuid,
) -> Result<Option<RetrievalTraceRow>> {
    let row = sqlx::query_as::<_, RetrievalTraceRow>(
        "SELECT * FROM retrieval_traces WHERE message_id = $1 ORDER BY created_at DESC LIMIT 1",
    )
    .bind(message_id)
    .fetch_optional(pool)
    .await?;
    Ok(row)
}

#[cfg(test)]
mod tests {
    use super::*;
    use crate::services::retrieval_pipeline::{RetrievalTimings, ScoredChunkRef};

    fn make_test_trace() -> RetrievalTrace {
        RetrievalTrace {
            original_query: "test query".to_string(),
            rewritten_query: "test query rewritten".to_string(),
            expanded_queries: vec!["alt query 1".to_string()],
            search_results_count: 5,
            reranked_results_count: 3,
            final_sources_count: 2,
            search_results: vec![ScoredChunkRef {
                chunk_id: Uuid::new_v4(),
                document_id: Uuid::new_v4(),
                score: 0.95,
                rank: 1,
            }],
            reranked_results: vec![ScoredChunkRef {
                chunk_id: Uuid::new_v4(),
                document_id: Uuid::new_v4(),
                score: 0.88,
                rank: 1,
            }],
            timings: RetrievalTimings {
                query_expansion_ms: 100,
                dense_search_ms: 80,
                sparse_search_ms: 60,
                fuzzy_search_ms: 0,
                fusion_ms: 20,
                search_ms: 200,
                rerank_ms: 150,
                context_assembly_ms: 50,
                total_ms: 500,
            },
            dense_results: Vec::new(),
            sparse_results: Vec::new(),
            fuzzy_results: Vec::new(),
            fused_results: Vec::new(),
            query_plan: None,
            claim_checks: Vec::new(),
            final_context: None,
        }
    }

    #[test]
    fn test_save_trace_input_construction() {
        let trace = make_test_trace();
        let input = SaveTraceInput {
            workspace_id: Uuid::new_v4(),
            message_id: Some(Uuid::new_v4()),
            trace: trace.clone(),
            domain_profile: Some("legal".to_string()),
        };
        assert_eq!(input.trace.original_query, "test query");
        assert_eq!(input.domain_profile.as_deref(), Some("legal"));
    }

    #[test]
    fn test_trace_serialization() {
        let trace = make_test_trace();
        let json = serde_json::to_value(&trace).unwrap();
        assert_eq!(json["original_query"], "test query");
        assert_eq!(json["search_results_count"], 5);
        assert!(json["timings"]["total_ms"].as_u64().unwrap() == 500);
    }

    #[test]
    fn test_trace_summary_construction() {
        let summary = RetrievalTraceSummary {
            id: Uuid::new_v4(),
            workspace_id: Uuid::new_v4(),
            message_id: None,
            original_query: "test".to_string(),
            search_results_count: 10,
            final_sources_count: 3,
            total_ms: 250,
            domain_profile: None,
            created_at: chrono::Utc::now(),
        };
        assert_eq!(summary.search_results_count, 10);
        assert_eq!(summary.total_ms, 250);
    }

    #[test]
    fn test_timings_json_roundtrip() {
        let timings = RetrievalTimings {
            query_expansion_ms: 100,
            dense_search_ms: 80,
            sparse_search_ms: 60,
            fuzzy_search_ms: 0,
            fusion_ms: 20,
            search_ms: 200,
            rerank_ms: 150,
            context_assembly_ms: 50,
            total_ms: 500,
        };
        let json = serde_json::to_value(&timings).unwrap();
        assert_eq!(json["total_ms"].as_u64().unwrap(), 500);
        assert_eq!(json["rerank_ms"].as_u64().unwrap(), 150);
        assert_eq!(json["dense_search_ms"].as_u64().unwrap(), 80);
        assert_eq!(json["sparse_search_ms"].as_u64().unwrap(), 60);
        assert_eq!(json["fusion_ms"].as_u64().unwrap(), 20);
    }

    #[test]
    fn test_scored_chunk_ref_serialization() {
        let refs = vec![
            ScoredChunkRef {
                chunk_id: Uuid::new_v4(),
                document_id: Uuid::new_v4(),
                score: 0.95,
                rank: 1,
            },
            ScoredChunkRef {
                chunk_id: Uuid::new_v4(),
                document_id: Uuid::new_v4(),
                score: 0.85,
                rank: 2,
            },
        ];
        let json = serde_json::to_value(&refs).unwrap();
        let arr = json.as_array().unwrap();
        assert_eq!(arr.len(), 2);
        assert_eq!(arr[0]["rank"], 1);
        assert_eq!(arr[1]["rank"], 2);
    }

    #[test]
    fn test_save_trace_input_without_message() {
        let input = SaveTraceInput {
            workspace_id: Uuid::new_v4(),
            message_id: None,
            trace: make_test_trace(),
            domain_profile: None,
        };
        assert!(input.message_id.is_none());
        assert!(input.domain_profile.is_none());
    }
}
