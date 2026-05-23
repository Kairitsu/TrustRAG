use anyhow::Result;
use serde::{Deserialize, Serialize};
use uuid::Uuid;

use crate::db::DbPool;
use crate::traits::llm_provider::{LlmMessage, LlmProvider, LlmRequest};

/// Auto-extracted metadata for a single document.
#[derive(Debug, Clone, Serialize, Deserialize, Default)]
pub struct DocumentMetadata {
    pub keywords: Vec<String>,
    pub topics: Vec<String>,
    pub language: Option<String>,
    pub domain: Option<String>,
    pub entity_types: Vec<String>,
    pub summary: Option<String>,
    #[serde(default)]
    pub custom: serde_json::Value,
}

/// Workspace-level domain profile aggregated from all documents.
#[derive(Debug, Clone, Serialize, Deserialize, Default)]
pub struct DomainProfile {
    pub primary_domain: Option<String>,
    pub sub_domains: Vec<String>,
    pub common_keywords: Vec<String>,
    pub languages: Vec<String>,
    pub document_count: usize,
    #[serde(default)]
    pub custom: serde_json::Value,
}

const METADATA_EXTRACTION_PROMPT: &str = r#"Analyze the following document content and extract structured metadata. Return ONLY valid JSON with these fields:
- "keywords": array of 5-10 important keywords
- "topics": array of 2-5 main topics
- "language": detected language code (e.g. "zh", "en", "ja")
- "domain": primary domain (e.g. "technology", "medicine", "law", "finance", "education")
- "entity_types": array of entity types found (e.g. "person", "organization", "location", "date", "product")
- "summary": one-sentence summary of the document

Return ONLY the JSON object, no explanation."#;

/// Extract metadata from document content using LLM.
pub async fn extract_metadata(
    llm_provider: &dyn LlmProvider,
    content: &str,
) -> Result<DocumentMetadata> {
    let sample: String = content.chars().take(3000).collect();

    let req = LlmRequest {
        messages: vec![
            LlmMessage {
                role: "system".to_string(),
                content: METADATA_EXTRACTION_PROMPT.to_string(),
            },
            LlmMessage {
                role: "user".to_string(),
                content: format!("Document content:\n\n{}", sample),
            },
        ],
        temperature: 0.0,
        max_tokens: 500,
        stream: false,
    };

    let resp = llm_provider.generate(&req).await?;
    parse_metadata_response(&resp.content)
}

fn parse_metadata_response(content: &str) -> Result<DocumentMetadata> {
    let trimmed = content.trim();

    let json_str = if let Some(start) = trimmed.find('{') {
        if let Some(end) = trimmed.rfind('}') {
            &trimmed[start..=end]
        } else {
            trimmed
        }
    } else {
        trimmed
    };

    match serde_json::from_str::<DocumentMetadata>(json_str) {
        Ok(meta) => Ok(meta),
        Err(e) => {
            tracing::warn!(error = %e, "Failed to parse metadata JSON, using defaults");
            Ok(DocumentMetadata::default())
        }
    }
}

/// Save document metadata to the database.
pub async fn save_document_metadata(
    pool: &DbPool,
    document_id: Uuid,
    metadata: &DocumentMetadata,
) -> Result<()> {
    let json = serde_json::to_value(metadata)?;
    sqlx::query("UPDATE documents SET metadata = $1 WHERE id = $2")
        .bind(&json)
        .bind(document_id)
        .execute(pool)
        .await?;
    Ok(())
}

/// Load document metadata from the database.
pub async fn load_document_metadata(
    pool: &DbPool,
    document_id: Uuid,
) -> Result<Option<DocumentMetadata>> {
    let row: Option<(serde_json::Value,)> =
        sqlx::query_as("SELECT metadata FROM documents WHERE id = $1")
            .bind(document_id)
            .fetch_optional(pool)
            .await?;

    match row {
        Some((json,)) => {
            if json.is_null() || json == serde_json::json!({}) {
                return Ok(None);
            }
            Ok(Some(serde_json::from_value(json)?))
        }
        None => Ok(None),
    }
}

/// Aggregate metadata from all documents in a workspace into a domain profile.
pub async fn build_domain_profile(
    pool: &DbPool,
    workspace_id: Uuid,
) -> Result<DomainProfile> {
    let rows: Vec<(serde_json::Value,)> = sqlx::query_as(
        "SELECT metadata FROM documents WHERE workspace_id = $1 AND metadata IS NOT NULL AND metadata != '{}'::jsonb"
    )
    .bind(workspace_id)
    .fetch_all(pool)
    .await?;

    let mut all_keywords: Vec<String> = Vec::new();
    let mut all_topics: Vec<String> = Vec::new();
    let mut all_domains: Vec<String> = Vec::new();
    let mut all_languages: Vec<String> = Vec::new();

    for (json,) in &rows {
        if let Ok(meta) = serde_json::from_value::<DocumentMetadata>(json.clone()) {
            all_keywords.extend(meta.keywords);
            all_topics.extend(meta.topics);
            if let Some(d) = meta.domain {
                all_domains.push(d);
            }
            if let Some(l) = meta.language {
                all_languages.push(l);
            }
        }
    }

    let common_keywords = top_n_by_frequency(&all_keywords, 20);
    let sub_domains = top_n_by_frequency(&all_topics, 10);
    let languages = top_n_by_frequency(&all_languages, 5);
    let primary_domain = top_n_by_frequency(&all_domains, 1).into_iter().next();

    let profile = DomainProfile {
        primary_domain,
        sub_domains,
        common_keywords,
        languages,
        document_count: rows.len(),
        custom: serde_json::Value::Null,
    };

    Ok(profile)
}

/// Save workspace domain profile.
pub async fn save_domain_profile(
    pool: &DbPool,
    workspace_id: Uuid,
    profile: &DomainProfile,
) -> Result<()> {
    let json = serde_json::to_value(profile)?;
    sqlx::query("UPDATE workspaces SET domain_profile = $1 WHERE id = $2")
        .bind(&json)
        .bind(workspace_id)
        .execute(pool)
        .await?;
    Ok(())
}

/// Get the N most frequent strings from a list.
fn top_n_by_frequency(items: &[String], n: usize) -> Vec<String> {
    use std::collections::HashMap;
    let mut counts: HashMap<String, usize> = HashMap::new();
    for item in items {
        let normalized = item.trim().to_lowercase();
        if !normalized.is_empty() {
            *counts.entry(normalized).or_insert(0) += 1;
        }
    }
    let mut sorted: Vec<_> = counts.into_iter().collect();
    sorted.sort_by(|a, b| b.1.cmp(&a.1));
    sorted.into_iter().take(n).map(|(k, _)| k).collect()
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn test_parse_metadata_response_valid() {
        let json = r#"{"keywords":["rust","async"],"topics":["programming"],"language":"en","domain":"technology","entity_types":["product"],"summary":"A guide to Rust."}"#;
        let meta = parse_metadata_response(json).unwrap();
        assert_eq!(meta.keywords, vec!["rust", "async"]);
        assert_eq!(meta.language, Some("en".to_string()));
        assert_eq!(meta.domain, Some("technology".to_string()));
    }

    #[test]
    fn test_parse_metadata_response_with_wrapper() {
        let text = "Here is the metadata:\n```json\n{\"keywords\":[\"test\"],\"topics\":[],\"language\":\"zh\",\"domain\":\"education\",\"entity_types\":[],\"summary\":\"test\"}\n```";
        let meta = parse_metadata_response(text).unwrap();
        assert_eq!(meta.keywords, vec!["test"]);
        assert_eq!(meta.language, Some("zh".to_string()));
    }

    #[test]
    fn test_parse_metadata_response_invalid_returns_default() {
        let meta = parse_metadata_response("not json at all").unwrap();
        assert!(meta.keywords.is_empty());
        assert!(meta.domain.is_none());
    }

    #[test]
    fn test_top_n_by_frequency() {
        let items = vec![
            "rust".to_string(), "go".to_string(), "rust".to_string(),
            "python".to_string(), "rust".to_string(), "go".to_string(),
        ];
        let top = top_n_by_frequency(&items, 2);
        assert_eq!(top[0], "rust");
        assert_eq!(top[1], "go");
    }

    #[test]
    fn test_top_n_by_frequency_empty() {
        let top = top_n_by_frequency(&[], 5);
        assert!(top.is_empty());
    }

    #[test]
    fn test_top_n_normalizes_case() {
        let items = vec!["Rust".to_string(), "rust".to_string(), "RUST".to_string()];
        let top = top_n_by_frequency(&items, 5);
        assert_eq!(top.len(), 1);
        assert_eq!(top[0], "rust");
    }

    #[test]
    fn test_document_metadata_serde_roundtrip() {
        let meta = DocumentMetadata {
            keywords: vec!["ai".to_string(), "ml".to_string()],
            topics: vec!["artificial intelligence".to_string()],
            language: Some("en".to_string()),
            domain: Some("technology".to_string()),
            entity_types: vec!["product".to_string()],
            summary: Some("An AI paper.".to_string()),
            custom: serde_json::json!({"extra": true}),
        };
        let json = serde_json::to_string(&meta).unwrap();
        let deserialized: DocumentMetadata = serde_json::from_str(&json).unwrap();
        assert_eq!(deserialized.keywords, meta.keywords);
        assert_eq!(deserialized.domain, meta.domain);
    }

    #[test]
    fn test_domain_profile_serde_roundtrip() {
        let profile = DomainProfile {
            primary_domain: Some("tech".to_string()),
            sub_domains: vec!["ml".to_string(), "nlp".to_string()],
            common_keywords: vec!["neural".to_string()],
            languages: vec!["en".to_string()],
            document_count: 10,
            custom: serde_json::Value::Null,
        };
        let json = serde_json::to_string(&profile).unwrap();
        let deserialized: DomainProfile = serde_json::from_str(&json).unwrap();
        assert_eq!(deserialized.primary_domain, profile.primary_domain);
        assert_eq!(deserialized.document_count, 10);
    }
}
