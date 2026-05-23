use serde::{Deserialize, Serialize};
use uuid::Uuid;

use crate::db::DbPool;
use crate::traits::embedding_provider::EmbeddingProvider;

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct SearchConfig {
    pub mode: SearchMode,
    pub top_k: usize,
    pub min_score: f64,
    pub use_mmr: bool,
    pub mmr_lambda: f64,
    pub rrf_k: f64,
}

#[derive(Debug, Clone, Serialize, Deserialize, PartialEq)]
#[serde(rename_all = "lowercase")]
pub enum SearchMode {
    Vector,
    Fulltext,
    Sparse,
    Hybrid,
}

impl Default for SearchConfig {
    fn default() -> Self {
        Self {
            mode: SearchMode::Hybrid,
            top_k: 10,
            min_score: 0.3,
            use_mmr: false,
            mmr_lambda: 0.7,
            rrf_k: 60.0,
        }
    }
}

#[derive(Debug, Clone, Serialize, Default)]
pub struct SearchResult {
    pub chunk_id: Uuid,
    pub document_id: Uuid,
    pub content: String,
    pub heading_path: Option<String>,
    pub page_start: Option<i32>,
    pub page_end: Option<i32>,
    pub relevance_score: f64,
    #[serde(skip_serializing_if = "Option::is_none")]
    pub dense_score: Option<f64>,
    #[serde(skip_serializing_if = "Option::is_none")]
    pub sparse_score: Option<f64>,
    #[serde(skip_serializing_if = "Option::is_none")]
    pub fusion_score: Option<f64>,
    #[serde(skip_serializing_if = "Option::is_none")]
    pub rerank_score: Option<f64>,
}

#[derive(Debug, Clone, Serialize)]
pub struct SearchResponse {
    pub results: Vec<SearchResult>,
    pub total: usize,
    pub search_time_ms: u64,
}

pub type SearchRow = (Uuid, Uuid, String, Option<String>, Option<i32>, Option<i32>, f64);

// ============================================================
// PostgreSQL implementation
// ============================================================

#[cfg(feature = "postgres")]
pub async fn vector_search(
    pool: &DbPool,
    workspace_id: Uuid,
    query_embedding: &[f32],
    top_k: usize,
    document_ids: Option<&[Uuid]>,
) -> anyhow::Result<Vec<SearchRow>> {
    let embedding_str = format!(
        "[{}]",
        query_embedding.iter().map(|v| v.to_string()).collect::<Vec<_>>().join(",")
    );

    let rows = if let Some(doc_ids) = document_ids {
        sqlx::query_as::<_, SearchRow>(
            r#"
            SELECT dc.id, dc.document_id, dc.content, dc.heading_path,
                   dc.page_start, dc.page_end,
                   1.0 - (dc.embedding <=> $1::vector) as score
            FROM document_chunks dc
            JOIN documents d ON dc.document_id = d.id
            WHERE d.workspace_id = $2
              AND dc.embedding IS NOT NULL
              AND dc.document_id = ANY($3)
            ORDER BY dc.embedding <=> $1::vector
            LIMIT $4
            "#,
        )
        .bind(&embedding_str)
        .bind(workspace_id)
        .bind(doc_ids)
        .bind(top_k as i64)
        .fetch_all(pool)
        .await?
    } else {
        sqlx::query_as::<_, SearchRow>(
            r#"
            SELECT dc.id, dc.document_id, dc.content, dc.heading_path,
                   dc.page_start, dc.page_end,
                   1.0 - (dc.embedding <=> $1::vector) as score
            FROM document_chunks dc
            JOIN documents d ON dc.document_id = d.id
            WHERE d.workspace_id = $2
              AND dc.embedding IS NOT NULL
            ORDER BY dc.embedding <=> $1::vector
            LIMIT $3
            "#,
        )
        .bind(&embedding_str)
        .bind(workspace_id)
        .bind(top_k as i64)
        .fetch_all(pool)
        .await?
    };

    Ok(rows)
}

#[cfg(feature = "postgres")]
pub async fn fulltext_search(
    pool: &DbPool,
    workspace_id: Uuid,
    query: &str,
    top_k: usize,
    document_ids: Option<&[Uuid]>,
) -> anyhow::Result<Vec<SearchRow>> {
    let rows = if let Some(doc_ids) = document_ids {
        sqlx::query_as::<_, SearchRow>(
            r#"
            SELECT dc.id, dc.document_id, dc.content, dc.heading_path,
                   dc.page_start, dc.page_end,
                   similarity(dc.content, $1)::float8 as score
            FROM document_chunks dc
            JOIN documents d ON dc.document_id = d.id
            WHERE d.workspace_id = $2
              AND dc.document_id = ANY($3)
              AND dc.content % $1
            ORDER BY similarity(dc.content, $1) DESC
            LIMIT $4
            "#,
        )
        .bind(query)
        .bind(workspace_id)
        .bind(doc_ids)
        .bind(top_k as i64)
        .fetch_all(pool)
        .await?
    } else {
        sqlx::query_as::<_, SearchRow>(
            r#"
            SELECT dc.id, dc.document_id, dc.content, dc.heading_path,
                   dc.page_start, dc.page_end,
                   similarity(dc.content, $1)::float8 as score
            FROM document_chunks dc
            JOIN documents d ON dc.document_id = d.id
            WHERE d.workspace_id = $2
              AND dc.content % $1
            ORDER BY similarity(dc.content, $1) DESC
            LIMIT $3
            "#,
        )
        .bind(query)
        .bind(workspace_id)
        .bind(top_k as i64)
        .fetch_all(pool)
        .await?
    };

    Ok(rows)
}

/// tsvector-based sparse search using ts_rank (PostgreSQL only).
/// Uses the `tsv` column populated by migration 0008.
/// Falls back to pg_trgm fulltext_search if the tsv column is empty.
#[cfg(feature = "postgres")]
pub async fn sparse_search(
    pool: &DbPool,
    workspace_id: Uuid,
    query: &str,
    top_k: usize,
    document_ids: Option<&[Uuid]>,
) -> anyhow::Result<Vec<SearchRow>> {
    let tsquery = build_tsquery(query);
    if tsquery.is_empty() {
        return fulltext_search(pool, workspace_id, query, top_k, document_ids).await;
    }

    let rows = if let Some(doc_ids) = document_ids {
        sqlx::query_as::<_, SearchRow>(
            r#"
            SELECT dc.id, dc.document_id, dc.content, dc.heading_path,
                   dc.page_start, dc.page_end,
                   ts_rank_cd(dc.tsv, to_tsquery('simple', $1), 32)::float8 AS score
            FROM document_chunks dc
            JOIN documents d ON dc.document_id = d.id
            WHERE d.workspace_id = $2
              AND dc.document_id = ANY($3)
              AND dc.tsv @@ to_tsquery('simple', $1)
            ORDER BY score DESC
            LIMIT $4
            "#,
        )
        .bind(&tsquery)
        .bind(workspace_id)
        .bind(doc_ids)
        .bind(top_k as i64)
        .fetch_all(pool)
        .await?
    } else {
        sqlx::query_as::<_, SearchRow>(
            r#"
            SELECT dc.id, dc.document_id, dc.content, dc.heading_path,
                   dc.page_start, dc.page_end,
                   ts_rank_cd(dc.tsv, to_tsquery('simple', $1), 32)::float8 AS score
            FROM document_chunks dc
            JOIN documents d ON dc.document_id = d.id
            WHERE d.workspace_id = $2
              AND dc.tsv @@ to_tsquery('simple', $1)
            ORDER BY score DESC
            LIMIT $3
            "#,
        )
        .bind(&tsquery)
        .bind(workspace_id)
        .bind(top_k as i64)
        .fetch_all(pool)
        .await?
    };

    if rows.is_empty() {
        return fulltext_search(pool, workspace_id, query, top_k, document_ids).await;
    }

    Ok(rows)
}

/// Convert a natural-language query into a PostgreSQL tsquery string.
/// Splits on whitespace, filters noise, joins with `|` (OR) for recall.
fn build_tsquery(query: &str) -> String {
    let terms: Vec<String> = query
        .split(|c: char| c.is_whitespace() || "\"*(){}[]|:!?.,;'".contains(c))
        .filter(|w| !w.is_empty() && w.len() > 1)
        .map(|w| w.to_lowercase())
        .collect();
    if terms.is_empty() {
        return String::new();
    }
    terms.join(" | ")
}

// ============================================================
// SQLite (desktop) implementation
// ============================================================

#[cfg(sqlite_mode)]
pub async fn vector_search(
    pool: &DbPool,
    workspace_id: Uuid,
    query_embedding: &[f32],
    top_k: usize,
    document_ids: Option<&[Uuid]>,
) -> anyhow::Result<Vec<SearchRow>> {
    let ws_str = workspace_id.to_string();

    let rows = if let Some(doc_ids) = document_ids {
        let placeholders: Vec<String> = doc_ids.iter().map(|id| format!("'{}'", id)).collect();
        let in_clause = placeholders.join(",");
        let query_str = format!(
            r#"SELECT dc.id, dc.document_id, dc.content, dc.heading_path,
                      dc.page_start, dc.page_end, dc.embedding
               FROM document_chunks dc
               JOIN documents d ON dc.document_id = d.id
               WHERE d.workspace_id = ?1
                 AND dc.embedding IS NOT NULL
                 AND dc.document_id IN ({})
            "#,
            in_clause
        );
        sqlx::query_as::<_, (String, String, String, Option<String>, Option<i32>, Option<i32>, Vec<u8>)>(
            &query_str,
        )
        .bind(&ws_str)
        .fetch_all(pool)
        .await?
    } else {
        sqlx::query_as::<_, (String, String, String, Option<String>, Option<i32>, Option<i32>, Vec<u8>)>(
            r#"SELECT dc.id, dc.document_id, dc.content, dc.heading_path,
                      dc.page_start, dc.page_end, dc.embedding
               FROM document_chunks dc
               JOIN documents d ON dc.document_id = d.id
               WHERE d.workspace_id = ?1
                 AND dc.embedding IS NOT NULL
            "#,
        )
        .bind(&ws_str)
        .fetch_all(pool)
        .await?
    };

    let mut scored: Vec<SearchRow> = rows
        .into_iter()
        .filter_map(|(id, doc_id, content, heading, ps, pe, emb_blob)| {
            let chunk_id = Uuid::parse_str(&id).ok()?;
            let document_id = Uuid::parse_str(&doc_id).ok()?;
            let stored_emb = crate::services::embedding::blob_to_embedding(&emb_blob);
            let score = cosine_similarity(query_embedding, &stored_emb);
            Some((chunk_id, document_id, content, heading, ps, pe, score))
        })
        .collect();

    scored.sort_by(|a, b| b.6.partial_cmp(&a.6).unwrap_or(std::cmp::Ordering::Equal));
    scored.truncate(top_k);

    Ok(scored)
}

#[cfg(sqlite_mode)]
fn cosine_similarity(a: &[f32], b: &[f32]) -> f64 {
    if a.len() != b.len() || a.is_empty() {
        return 0.0;
    }
    let mut dot = 0.0f64;
    let mut norm_a = 0.0f64;
    let mut norm_b = 0.0f64;
    for (x, y) in a.iter().zip(b.iter()) {
        let x = *x as f64;
        let y = *y as f64;
        dot += x * y;
        norm_a += x * x;
        norm_b += y * y;
    }
    let denom = norm_a.sqrt() * norm_b.sqrt();
    if denom == 0.0 { 0.0 } else { dot / denom }
}

#[cfg(sqlite_mode)]
pub async fn fulltext_search(
    pool: &DbPool,
    workspace_id: Uuid,
    query: &str,
    top_k: usize,
    document_ids: Option<&[Uuid]>,
) -> anyhow::Result<Vec<SearchRow>> {
    let ws_str = workspace_id.to_string();
    let sanitized: String = query.chars()
        .map(|c| if "\"*(){}[]|:!?.,;".contains(c) { ' ' } else { c })
        .collect();
    let words: Vec<&str> = sanitized.split_whitespace()
        .filter(|w| !w.is_empty() && *w != "OR" && *w != "AND" && *w != "NOT" && *w != "NEAR")
        .collect();
    if words.is_empty() {
        return Ok(vec![]);
    }
    let fts_query = words.iter()
        .map(|w| format!("\"{}\"", w))
        .collect::<Vec<_>>()
        .join(" OR ");

    let base_query = if let Some(doc_ids) = document_ids {
        let placeholders: Vec<String> = doc_ids.iter().map(|id| format!("'{}'", id)).collect();
        let in_clause = placeholders.join(",");
        format!(
            r#"SELECT dc.id, dc.document_id, dc.content, dc.heading_path,
                      dc.page_start, dc.page_end,
                      CAST(rank AS REAL) as score
               FROM document_chunks dc
               JOIN documents d ON dc.document_id = d.id
               JOIN chunks_fts ON chunks_fts.chunk_id = dc.id
               WHERE d.workspace_id = ?1
                 AND dc.document_id IN ({})
                 AND chunks_fts MATCH ?2
               ORDER BY rank
               LIMIT ?3
            "#,
            in_clause
        )
    } else {
        r#"SELECT dc.id, dc.document_id, dc.content, dc.heading_path,
                  dc.page_start, dc.page_end,
                  CAST(rank AS REAL) as score
           FROM document_chunks dc
           JOIN documents d ON dc.document_id = d.id
           JOIN chunks_fts ON chunks_fts.chunk_id = dc.id
           WHERE d.workspace_id = ?1
             AND chunks_fts MATCH ?2
           ORDER BY rank
           LIMIT ?3
        "#.to_string()
    };

    let raw_rows = sqlx::query_as::<_, (String, String, String, Option<String>, Option<i32>, Option<i32>, f64)>(
        &base_query,
    )
    .bind(&ws_str)
    .bind(&fts_query)
    .bind(top_k as i64)
    .fetch_all(pool)
    .await?;

    let rows: Vec<SearchRow> = raw_rows
        .into_iter()
        .filter_map(|(id, doc_id, content, heading, ps, pe, score)| {
            let chunk_id = Uuid::parse_str(&id).ok()?;
            let document_id = Uuid::parse_str(&doc_id).ok()?;
            Some((chunk_id, document_id, content, heading, ps, pe, score.abs()))
        })
        .collect();

    Ok(rows)
}

// ============================================================
// Shared logic
// ============================================================

pub fn rrf_fusion(
    vector_results: &[SearchRow],
    fulltext_results: &[SearchRow],
    k: f64,
    top_k: usize,
) -> Vec<SearchResult> {
    use std::collections::HashMap;

    struct FusionEntry {
        fusion_score: f64,
        dense_score: Option<f64>,
        sparse_score: Option<f64>,
        doc_id: Uuid,
        content: String,
        heading: Option<String>,
        page_start: Option<i32>,
        page_end: Option<i32>,
    }

    let mut entries: HashMap<Uuid, FusionEntry> = HashMap::new();

    for (rank, row) in vector_results.iter().enumerate() {
        let rrf_score = 1.0 / (k + rank as f64 + 1.0);
        let entry = entries.entry(row.0).or_insert(FusionEntry {
            fusion_score: 0.0,
            dense_score: None,
            sparse_score: None,
            doc_id: row.1,
            content: row.2.clone(),
            heading: row.3.clone(),
            page_start: row.4,
            page_end: row.5,
        });
        entry.fusion_score += rrf_score;
        entry.dense_score = Some(row.6);
    }

    for (rank, row) in fulltext_results.iter().enumerate() {
        let rrf_score = 1.0 / (k + rank as f64 + 1.0);
        let entry = entries.entry(row.0).or_insert(FusionEntry {
            fusion_score: 0.0,
            dense_score: None,
            sparse_score: None,
            doc_id: row.1,
            content: row.2.clone(),
            heading: row.3.clone(),
            page_start: row.4,
            page_end: row.5,
        });
        entry.fusion_score += rrf_score;
        entry.sparse_score = Some(row.6);
    }

    let mut results: Vec<SearchResult> = entries
        .into_iter()
        .map(|(chunk_id, e)| SearchResult {
            chunk_id,
            document_id: e.doc_id,
            content: e.content,
            heading_path: e.heading,
            page_start: e.page_start,
            page_end: e.page_end,
            relevance_score: e.fusion_score,
            dense_score: e.dense_score,
            sparse_score: e.sparse_score,
            fusion_score: Some(e.fusion_score),
            rerank_score: None,
        })
        .collect();

    results.sort_by(|a, b| b.relevance_score.partial_cmp(&a.relevance_score).unwrap_or(std::cmp::Ordering::Equal));
    results.truncate(top_k);
    results
}

pub async fn hybrid_search(
    pool: &DbPool,
    embedding_provider: &dyn EmbeddingProvider,
    workspace_id: Uuid,
    query: &str,
    config: &SearchConfig,
    document_ids: Option<&[Uuid]>,
) -> anyhow::Result<SearchResponse> {
    let start = std::time::Instant::now();
    let retrieval_k = config.top_k * 2;

    let rows_to_results = |rows: Vec<SearchRow>, score_type: &str| -> Vec<SearchResult> {
        rows.into_iter()
            .map(|r| {
                let score = r.6;
                let (dense, sparse) = match score_type {
                    "dense" => (Some(score), None),
                    "sparse" => (None, Some(score)),
                    _ => (None, None),
                };
                SearchResult {
                    chunk_id: r.0,
                    document_id: r.1,
                    content: r.2,
                    heading_path: r.3,
                    page_start: r.4,
                    page_end: r.5,
                    relevance_score: score,
                    dense_score: dense,
                    sparse_score: sparse,
                    fusion_score: None,
                    rerank_score: None,
                }
            })
            .collect()
    };

    let results = match config.mode {
        SearchMode::Vector => {
            let embeddings = embedding_provider.embed_texts(&[query.to_string()]).await?;
            let query_emb = embeddings.into_iter().next().ok_or_else(|| anyhow::anyhow!("No embedding returned"))?;
            let vector_rows = vector_search(pool, workspace_id, &query_emb, config.top_k, document_ids).await?;
            rows_to_results(vector_rows, "dense")
        }
        SearchMode::Fulltext => {
            let ft_rows = fulltext_search(pool, workspace_id, query, config.top_k, document_ids).await?;
            rows_to_results(ft_rows, "sparse")
        }
        #[cfg(feature = "postgres")]
        SearchMode::Sparse => {
            let sp_rows = sparse_search(pool, workspace_id, query, config.top_k, document_ids).await?;
            rows_to_results(sp_rows, "sparse")
        }
        #[cfg(not(feature = "postgres"))]
        SearchMode::Sparse => {
            let ft_rows = fulltext_search(pool, workspace_id, query, config.top_k, document_ids).await?;
            rows_to_results(ft_rows, "sparse")
        }
        SearchMode::Hybrid => {
            let embeddings = embedding_provider.embed_texts(&[query.to_string()]).await?;
            let query_emb = embeddings.into_iter().next().ok_or_else(|| anyhow::anyhow!("No embedding returned"))?;

            #[cfg(feature = "postgres")]
            let (vector_rows, ft_rows) = tokio::try_join!(
                vector_search(pool, workspace_id, &query_emb, retrieval_k, document_ids),
                sparse_search(pool, workspace_id, query, retrieval_k, document_ids),
            )?;

            #[cfg(not(feature = "postgres"))]
            let (vector_rows, ft_rows) = tokio::try_join!(
                vector_search(pool, workspace_id, &query_emb, retrieval_k, document_ids),
                fulltext_search(pool, workspace_id, query, retrieval_k, document_ids),
            )?;

            rrf_fusion(&vector_rows, &ft_rows, config.rrf_k, config.top_k)
        }
    };

    let effective_min_score = if config.mode == SearchMode::Hybrid {
        0.0
    } else {
        config.min_score
    };

    let filtered: Vec<SearchResult> = results
        .into_iter()
        .filter(|r| r.relevance_score >= effective_min_score)
        .collect();

    let total = filtered.len();
    let elapsed = start.elapsed().as_millis() as u64;

    tracing::info!(
        mode = ?config.mode,
        query_len = query.len(),
        pre_filter_count = total,
        elapsed_ms = elapsed,
        "Search completed"
    );

    Ok(SearchResponse {
        results: filtered,
        total,
        search_time_ms: elapsed,
    })
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn test_rrf_fusion_basic() {
        let vector_results = vec![
            (Uuid::new_v4(), Uuid::new_v4(), "chunk A".into(), Some("heading".into()), Some(1), Some(1), 0.9),
            (Uuid::new_v4(), Uuid::new_v4(), "chunk B".into(), None, Some(2), Some(2), 0.8),
        ];
        let fulltext_results = vec![
            (vector_results[1].0, vector_results[1].1, "chunk B".into(), None, Some(2), Some(2), 0.7),
            (Uuid::new_v4(), Uuid::new_v4(), "chunk C".into(), None, Some(3), Some(3), 0.6),
        ];

        let results = rrf_fusion(&vector_results, &fulltext_results, 60.0, 10);

        assert_eq!(results.len(), 3);
        let b_result = results.iter().find(|r| r.content == "chunk B").unwrap();
        let a_result = results.iter().find(|r| r.content == "chunk A").unwrap();
        assert!(b_result.relevance_score > a_result.relevance_score,
            "chunk B should rank higher due to appearing in both lists");
    }

    #[test]
    fn test_rrf_fusion_top_k_limit() {
        let vector_results: Vec<_> = (0..5)
            .map(|i| (Uuid::new_v4(), Uuid::new_v4(), format!("v{}", i), None, None, None, 0.9 - i as f64 * 0.1))
            .collect();
        let fulltext_results: Vec<_> = (0..5)
            .map(|i| (Uuid::new_v4(), Uuid::new_v4(), format!("f{}", i), None, None, None, 0.9 - i as f64 * 0.1))
            .collect();

        let results = rrf_fusion(&vector_results, &fulltext_results, 60.0, 3);
        assert_eq!(results.len(), 3);
    }

    #[test]
    fn test_search_config_default() {
        let config = SearchConfig::default();
        assert_eq!(config.mode, SearchMode::Hybrid);
        assert_eq!(config.top_k, 10);
    }

    #[test]
    fn test_rrf_fusion_empty_inputs() {
        let results = rrf_fusion(&[], &[], 60.0, 10);
        assert!(results.is_empty());
    }

    #[test]
    fn test_rrf_fusion_one_side_empty() {
        let vector_results = vec![
            (Uuid::new_v4(), Uuid::new_v4(), "only in vector".into(), None, None, None, 0.9),
        ];
        let results = rrf_fusion(&vector_results, &[], 60.0, 10);
        assert_eq!(results.len(), 1);
        assert_eq!(results[0].content, "only in vector");
        let expected_score = 1.0 / (60.0 + 0.0 + 1.0);
        assert!((results[0].relevance_score - expected_score).abs() < 1e-10);
    }

    #[test]
    fn test_rrf_fusion_score_math_correctness() {
        let id = Uuid::new_v4();
        let doc_id = Uuid::new_v4();
        let vector_results = vec![
            (id, doc_id, "shared".into(), None, None, None, 0.9),
        ];
        let fulltext_results = vec![
            (id, doc_id, "shared".into(), None, None, None, 0.8),
        ];

        let results = rrf_fusion(&vector_results, &fulltext_results, 60.0, 10);
        assert_eq!(results.len(), 1);
        let expected = 1.0 / 61.0 + 1.0 / 61.0;
        assert!((results[0].relevance_score - expected).abs() < 1e-10,
            "Score should be sum of both RRF contributions: expected {expected}, got {}",
            results[0].relevance_score);
    }

    #[test]
    fn test_rrf_fusion_ranking_stability() {
        let ids: Vec<_> = (0..5).map(|_| Uuid::new_v4()).collect();
        let doc_id = Uuid::new_v4();

        let vector_results: Vec<_> = ids.iter()
            .enumerate()
            .map(|(i, &id)| (id, doc_id, format!("chunk_{}", i), None, None, None, 0.0))
            .collect();

        let results = rrf_fusion(&vector_results, &[], 60.0, 5);
        for i in 0..results.len() - 1 {
            assert!(results[i].relevance_score >= results[i + 1].relevance_score,
                "Results should be sorted by descending score");
        }
    }

    #[test]
    fn test_build_tsquery_basic() {
        let q = build_tsquery("向量数据库 性能优化");
        assert!(q.contains("向量数据库"));
        assert!(q.contains("性能优化"));
        assert!(q.contains(" | "));
    }

    #[test]
    fn test_build_tsquery_filters_short_tokens() {
        let q = build_tsquery("a b cd ef");
        assert!(!q.contains(" a "));
        assert!(!q.contains(" b "));
        assert!(q.contains("cd"));
        assert!(q.contains("ef"));
    }

    #[test]
    fn test_build_tsquery_empty() {
        assert!(build_tsquery("").is_empty());
        assert!(build_tsquery("  ").is_empty());
        assert!(build_tsquery("a b").is_empty());
    }

    #[test]
    fn test_build_tsquery_strips_special_chars() {
        let q = build_tsquery("hello:world! (test)");
        assert!(q.contains("hello"));
        assert!(q.contains("world"));
        assert!(q.contains("test"));
        assert!(!q.contains(":"));
        assert!(!q.contains("!"));
    }

    #[test]
    fn test_search_mode_sparse_variant() {
        let config = SearchConfig {
            mode: SearchMode::Sparse,
            ..SearchConfig::default()
        };
        assert_eq!(config.mode, SearchMode::Sparse);
    }

    #[test]
    fn test_search_mode_serde_roundtrip() {
        let modes = vec![
            SearchMode::Vector,
            SearchMode::Fulltext,
            SearchMode::Sparse,
            SearchMode::Hybrid,
        ];
        for mode in modes {
            let json = serde_json::to_string(&mode).unwrap();
            let deserialized: SearchMode = serde_json::from_str(&json).unwrap();
            assert_eq!(mode, deserialized);
        }
    }

    #[test]
    fn test_rrf_fusion_captures_stage_scores() {
        let id = Uuid::new_v4();
        let doc_id = Uuid::new_v4();
        let vector_results = vec![
            (id, doc_id, "shared".into(), None, None, None, 0.95),
        ];
        let fulltext_results = vec![
            (id, doc_id, "shared".into(), None, None, None, 0.72),
        ];

        let results = rrf_fusion(&vector_results, &fulltext_results, 60.0, 10);
        assert_eq!(results.len(), 1);
        let r = &results[0];
        assert_eq!(r.dense_score, Some(0.95));
        assert_eq!(r.sparse_score, Some(0.72));
        assert!(r.fusion_score.is_some());
        assert!(r.fusion_score.unwrap() > 0.0);
        assert!(r.rerank_score.is_none());
    }

    #[test]
    fn test_rrf_fusion_vector_only_scores() {
        let results = rrf_fusion(
            &[(Uuid::new_v4(), Uuid::new_v4(), "v".into(), None, None, None, 0.9)],
            &[],
            60.0,
            10,
        );
        assert_eq!(results.len(), 1);
        assert_eq!(results[0].dense_score, Some(0.9));
        assert!(results[0].sparse_score.is_none());
        assert!(results[0].fusion_score.is_some());
    }

    #[test]
    fn test_search_result_serialization_omits_none_scores() {
        let result = SearchResult {
            chunk_id: Uuid::new_v4(),
            document_id: Uuid::new_v4(),
            content: "test".to_string(),
            relevance_score: 0.8,
            ..Default::default()
        };
        let json = serde_json::to_string(&result).unwrap();
        assert!(!json.contains("dense_score"));
        assert!(!json.contains("sparse_score"));
        assert!(!json.contains("fusion_score"));
        assert!(!json.contains("rerank_score"));

        let result_with_scores = SearchResult {
            dense_score: Some(0.9),
            fusion_score: Some(0.85),
            ..result
        };
        let json2 = serde_json::to_string(&result_with_scores).unwrap();
        assert!(json2.contains("dense_score"));
        assert!(json2.contains("fusion_score"));
        assert!(!json2.contains("sparse_score"));
        assert!(!json2.contains("rerank_score"));
    }
}
