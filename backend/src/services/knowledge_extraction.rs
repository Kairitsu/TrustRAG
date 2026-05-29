use anyhow::Result;
use serde::{Deserialize, Serialize};
use uuid::Uuid;

use crate::db::DbPool;
use crate::traits::llm_provider::{LlmMessage, LlmProvider, LlmRequest};

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct ExtractedEntity {
    pub name: String,
    pub entity_type: String,
    #[serde(default)]
    pub description: String,
}

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct ExtractedRelation {
    pub source: String,
    pub target: String,
    pub relation_type: String,
    #[serde(default = "default_confidence")]
    pub confidence: f64,
    #[serde(default)]
    pub description: String,
}

fn default_confidence() -> f64 {
    0.8
}

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct ExtractionResult {
    pub entities: Vec<ExtractedEntity>,
    pub relations: Vec<ExtractedRelation>,
}

const EXTRACTION_SYSTEM_PROMPT: &str = r#"You are a knowledge graph extraction assistant. Given a text passage, extract entities and relationships.

Output ONLY a JSON object with this exact structure:
{
  "entities": [
    {"name": "Entity Name", "entity_type": "person|organization|concept|technology|location|event|other", "description": "brief description"}
  ],
  "relations": [
    {"source": "Entity A", "target": "Entity B", "relation_type": "uses|part_of|related_to|causes|depends_on|created_by|belongs_to|similar_to", "confidence": 0.85, "description": "brief description of relationship"}
  ]
}

Rules:
1. Extract only significant entities (not common words)
2. Normalize entity names (consistent casing, no duplicates)
3. Each relation must reference entities from the entities list
4. Keep entity_type to the predefined categories
5. Maximum 15 entities and 20 relations per passage
6. confidence is a float 0.0-1.0 indicating how confident you are about the relationship
7. Output ONLY the JSON, no explanation"#;

pub async fn extract_from_text(
    llm_provider: &dyn LlmProvider,
    text: &str,
) -> Result<ExtractionResult> {
    let truncated: String = text.chars().take(3000).collect();

    let req = LlmRequest {
        messages: vec![
            LlmMessage {
                role: "system".to_string(),
                content: EXTRACTION_SYSTEM_PROMPT.to_string(),
            },
            LlmMessage {
                role: "user".to_string(),
                content: format!("Extract entities and relationships from this text:\n\n{}", truncated),
            },
        ],
        temperature: 0.1,
        max_tokens: 2000,
        stream: false,
    };

    let resp = llm_provider.generate(&req).await?;
    let content = resp.content.trim();

    let json_str = if let Some(start) = content.find('{') {
        if let Some(end) = content.rfind('}') {
            &content[start..=end]
        } else {
            content
        }
    } else {
        content
    };

    let result: ExtractionResult = serde_json::from_str(json_str)
        .map_err(|e| anyhow::anyhow!("Failed to parse extraction result: {}. Raw: {}", e, &json_str[..json_str.len().min(200)]))?;

    Ok(result)
}

pub async fn store_extraction(
    pool: &DbPool,
    workspace_id: Uuid,
    document_id: Uuid,
    chunk_id: Option<Uuid>,
    result: &ExtractionResult,
) -> Result<(usize, usize)> {
    let mut entity_count = 0;
    let mut relation_count = 0;

    let mut entity_ids: std::collections::HashMap<String, String> = std::collections::HashMap::new();

    for entity in &result.entities {
        let name_lower = entity.name.to_lowercase();

        let existing: Option<(String,)> = sqlx::query_as(
            "SELECT id FROM entities WHERE workspace_id = $1 AND LOWER(name) = $2"
        )
        .bind(workspace_id.to_string())
        .bind(&name_lower)
        .fetch_optional(pool)
        .await?;

        let entity_id = if let Some((id,)) = existing {
            id
        } else {
            let metadata = serde_json::json!({
                "description": entity.description,
                "source_document_id": document_id.to_string(),
            });

            let row: (String,) = sqlx::query_as(
                "INSERT INTO entities (workspace_id, name, entity_type, document_id, chunk_id, metadata) \
                 VALUES ($1, $2, $3, $4, $5, $6) RETURNING id"
            )
            .bind(workspace_id.to_string())
            .bind(&entity.name)
            .bind(&entity.entity_type)
            .bind(document_id.to_string())
            .bind(chunk_id.map(|c| c.to_string()))
            .bind(metadata.to_string())
            .fetch_one(pool)
            .await?;

            entity_count += 1;
            row.0
        };

        entity_ids.insert(name_lower, entity_id);
    }

    for relation in &result.relations {
        let source_id = entity_ids.get(&relation.source.to_lowercase());
        let target_id = entity_ids.get(&relation.target.to_lowercase());

        if let (Some(src), Some(tgt)) = (source_id, target_id) {
            let existing: Option<(String,)> = sqlx::query_as(
                "SELECT id FROM entity_relations \
                 WHERE workspace_id = $1 AND source_entity_id = $2 AND target_entity_id = $3 AND relation_type = $4"
            )
            .bind(workspace_id.to_string())
            .bind(src)
            .bind(tgt)
            .bind(&relation.relation_type)
            .fetch_optional(pool)
            .await?;

            if existing.is_none() {
                let metadata = serde_json::json!({
                    "description": relation.description,
                    "source_document_id": document_id.to_string(),
                });

                let weight = relation.confidence.clamp(0.0, 1.0);
                sqlx::query(
                    "INSERT INTO entity_relations (workspace_id, source_entity_id, target_entity_id, relation_type, weight, metadata) \
                     VALUES ($1, $2, $3, $4, $5, $6)"
                )
                .bind(workspace_id.to_string())
                .bind(src)
                .bind(tgt)
                .bind(&relation.relation_type)
                .bind(weight)
                .bind(metadata.to_string())
                .execute(pool)
                .await?;

                relation_count += 1;
            }
        }
    }

    Ok((entity_count, relation_count))
}

pub async fn extract_for_document(
    pool: &DbPool,
    llm_provider: &dyn LlmProvider,
    workspace_id: Uuid,
    document_id: Uuid,
) -> Result<(usize, usize)> {
    let chunks = sqlx::query_as::<_, (String, String)>(
        "SELECT id, content FROM document_chunks WHERE document_id = $1 ORDER BY chunk_index ASC LIMIT 30"
    )
    .bind(document_id.to_string())
    .fetch_all(pool)
    .await?;

    if chunks.is_empty() {
        anyhow::bail!("No chunks found for document {}", document_id);
    }

    let mut total_entities = 0;
    let mut total_relations = 0;

    for (chunk_id_str, content) in &chunks {
        if content.trim().len() < 50 {
            continue;
        }

        let chunk_id: Uuid = chunk_id_str.parse().unwrap_or_default();

        match extract_from_text(llm_provider, content).await {
            Ok(result) => {
                match store_extraction(pool, workspace_id, document_id, Some(chunk_id), &result).await {
                    Ok((e, r)) => {
                        total_entities += e;
                        total_relations += r;
                        tracing::debug!(
                            chunk_id = %chunk_id,
                            entities = e,
                            relations = r,
                            "Extracted knowledge from chunk"
                        );
                    }
                    Err(e) => {
                        tracing::warn!(chunk_id = %chunk_id, error = %e, "Failed to store extraction");
                    }
                }
            }
            Err(e) => {
                tracing::warn!(chunk_id = %chunk_id, error = %e, "Failed to extract from chunk");
            }
        }
    }

    tracing::info!(
        document_id = %document_id,
        total_entities = total_entities,
        total_relations = total_relations,
        chunks_processed = chunks.len(),
        "Knowledge extraction completed for document"
    );

    Ok((total_entities, total_relations))
}

pub async fn reset_workspace_graph(
    pool: &DbPool,
    workspace_id: Uuid,
) -> Result<(usize, usize)> {
    let relations_deleted = sqlx::query(
        "DELETE FROM entity_relations WHERE workspace_id = $1"
    )
    .bind(workspace_id.to_string())
    .execute(pool)
    .await?
    .rows_affected() as usize;

    let entities_deleted = sqlx::query(
        "DELETE FROM entities WHERE workspace_id = $1"
    )
    .bind(workspace_id.to_string())
    .execute(pool)
    .await?
    .rows_affected() as usize;

    tracing::info!(
        workspace_id = %workspace_id,
        entities = entities_deleted,
        relations = relations_deleted,
        "Knowledge graph reset"
    );

    Ok((entities_deleted, relations_deleted))
}

/// Build the document network layer: creates document nodes and co-location relations
pub async fn build_document_layer(
    pool: &DbPool,
    workspace_id: Uuid,
) -> Result<(usize, usize)> {
    let mut entity_count = 0usize;
    let mut relation_count = 0usize;

    let docs = sqlx::query_as::<_, (String, String, Option<String>)>(
        "SELECT id, title, folder FROM documents WHERE workspace_id = $1 AND status = 'completed'"
    )
    .bind(workspace_id.to_string())
    .fetch_all(pool)
    .await?;

    let mut doc_entity_ids: std::collections::HashMap<String, String> = std::collections::HashMap::new();

    for (doc_id, title, folder) in &docs {
        let existing: Option<(String,)> = sqlx::query_as(
            "SELECT id FROM entities WHERE workspace_id = $1 AND document_id = $2 AND graph_layer = 'document' AND entity_type = 'document'"
        )
        .bind(workspace_id.to_string())
        .bind(doc_id)
        .fetch_optional(pool)
        .await?;

        let entity_id = if let Some((id,)) = existing {
            id
        } else {
            let metadata = serde_json::json!({
                "source_document_id": doc_id,
                "folder": folder.as_deref().unwrap_or(""),
                "created_by": "auto_document_layer",
            });
            let row: (String,) = sqlx::query_as(
                "INSERT INTO entities (workspace_id, name, entity_type, document_id, graph_layer, metadata) \
                 VALUES ($1, $2, 'document', $3, 'document', $4) RETURNING id"
            )
            .bind(workspace_id.to_string())
            .bind(title)
            .bind(doc_id)
            .bind(metadata.to_string())
            .fetch_one(pool)
            .await?;
            entity_count += 1;
            row.0
        };

        doc_entity_ids.insert(doc_id.clone(), entity_id);
    }

    let mut folder_groups: std::collections::HashMap<String, Vec<String>> = std::collections::HashMap::new();
    for (doc_id, _, folder) in &docs {
        let folder_key = folder.as_deref().unwrap_or("__root__").to_string();
        folder_groups.entry(folder_key).or_default().push(doc_id.clone());
    }

    for (_folder, doc_ids_in_folder) in &folder_groups {
        if doc_ids_in_folder.len() < 2 { continue; }
        for i in 0..doc_ids_in_folder.len() {
            for j in (i+1)..doc_ids_in_folder.len() {
                let src_eid = doc_entity_ids.get(&doc_ids_in_folder[i]);
                let tgt_eid = doc_entity_ids.get(&doc_ids_in_folder[j]);
                if let (Some(src), Some(tgt)) = (src_eid, tgt_eid) {
                    let existing: Option<(String,)> = sqlx::query_as(
                        "SELECT id FROM entity_relations \
                         WHERE workspace_id = $1 AND source_entity_id = $2 AND target_entity_id = $3 AND graph_layer = 'document'"
                    )
                    .bind(workspace_id.to_string())
                    .bind(src)
                    .bind(tgt)
                    .fetch_optional(pool)
                    .await?;

                    if existing.is_none() {
                        sqlx::query(
                            "INSERT INTO entity_relations (workspace_id, source_entity_id, target_entity_id, relation_type, weight, graph_layer, metadata) \
                             VALUES ($1, $2, $3, 'co_located', 0.5, 'document', '{}')"
                        )
                        .bind(workspace_id.to_string())
                        .bind(src)
                        .bind(tgt)
                        .execute(pool)
                        .await?;
                        relation_count += 1;
                    }
                }
            }
        }
    }

    tracing::info!(
        workspace_id = %workspace_id,
        entities = entity_count,
        relations = relation_count,
        "Document network layer built"
    );

    Ok((entity_count, relation_count))
}

/// Build the semantic layer: links documents/entities that share chunk-level embedding similarity.
/// Uses a lightweight approach: finds entities that appear in overlapping chunks across documents.
pub async fn build_semantic_layer(
    pool: &DbPool,
    workspace_id: Uuid,
) -> Result<(usize, usize)> {
    let mut entity_count = 0usize;
    let mut relation_count = 0usize;

    // Find pairs of knowledge-layer entities that co-occur in the same document
    let cooccurrence_rows = sqlx::query_as::<_, (String, String, String, String, i32)>(
        "SELECT e1.id, e1.name, e2.id, e2.name, COUNT(*) as shared_docs \
         FROM entities e1 \
         JOIN entities e2 ON e1.workspace_id = e2.workspace_id AND e1.id < e2.id \
         WHERE e1.workspace_id = $1 \
           AND e1.graph_layer = 'knowledge' AND e2.graph_layer = 'knowledge' \
           AND e1.document_id IS NOT NULL AND e2.document_id IS NOT NULL \
           AND e1.document_id = e2.document_id \
         GROUP BY e1.id, e2.id \
         HAVING COUNT(*) >= 1 \
         LIMIT 200"
    )
    .bind(workspace_id.to_string())
    .fetch_all(pool)
    .await?;

    for (e1_id, _e1_name, e2_id, _e2_name, shared_count) in &cooccurrence_rows {
        let existing: Option<(String,)> = sqlx::query_as(
            "SELECT id FROM entity_relations \
             WHERE workspace_id = $1 AND source_entity_id = $2 AND target_entity_id = $3 AND graph_layer = 'semantic'"
        )
        .bind(workspace_id.to_string())
        .bind(e1_id)
        .bind(e2_id)
        .fetch_optional(pool)
        .await?;

        if existing.is_none() {
            let weight = (*shared_count as f64 / 5.0).clamp(0.3, 1.0);
            let metadata = serde_json::json!({
                "shared_documents": shared_count,
                "created_by": "auto_semantic_layer",
            });
            sqlx::query(
                "INSERT INTO entity_relations (workspace_id, source_entity_id, target_entity_id, relation_type, weight, graph_layer, metadata) \
                 VALUES ($1, $2, $3, 'semantically_similar', $4, 'semantic', $5)"
            )
            .bind(workspace_id.to_string())
            .bind(e1_id)
            .bind(e2_id)
            .bind(weight)
            .bind(metadata.to_string())
            .execute(pool)
            .await?;
            relation_count += 1;
        }
    }

    // Also create cross-document semantic links between documents that share entities
    let cross_doc_rows = sqlx::query_as::<_, (String, String, i32)>(
        "SELECT DISTINCT e1.document_id, e2.document_id, COUNT(DISTINCT e1.name) as shared_entities \
         FROM entities e1 \
         JOIN entities e2 ON e1.workspace_id = e2.workspace_id \
            AND LOWER(e1.name) = LOWER(e2.name) AND e1.document_id < e2.document_id \
         WHERE e1.workspace_id = $1 \
           AND e1.graph_layer = 'knowledge' AND e2.graph_layer = 'knowledge' \
           AND e1.document_id IS NOT NULL AND e2.document_id IS NOT NULL \
         GROUP BY e1.document_id, e2.document_id \
         HAVING COUNT(DISTINCT e1.name) >= 2 \
         LIMIT 100"
    )
    .bind(workspace_id.to_string())
    .fetch_all(pool)
    .await?;

    for (doc1_id, doc2_id, shared_entities) in &cross_doc_rows {
        // Find document-layer entity IDs for these docs
        let doc1_eid: Option<(String,)> = sqlx::query_as(
            "SELECT id FROM entities WHERE workspace_id = $1 AND document_id = $2 AND graph_layer = 'document' AND entity_type = 'document'"
        )
        .bind(workspace_id.to_string())
        .bind(doc1_id)
        .fetch_optional(pool)
        .await?;

        let doc2_eid: Option<(String,)> = sqlx::query_as(
            "SELECT id FROM entities WHERE workspace_id = $1 AND document_id = $2 AND graph_layer = 'document' AND entity_type = 'document'"
        )
        .bind(workspace_id.to_string())
        .bind(doc2_id)
        .fetch_optional(pool)
        .await?;

        if let (Some((src,)), Some((tgt,))) = (doc1_eid, doc2_eid) {
            let existing: Option<(String,)> = sqlx::query_as(
                "SELECT id FROM entity_relations \
                 WHERE workspace_id = $1 AND source_entity_id = $2 AND target_entity_id = $3 AND graph_layer = 'semantic'"
            )
            .bind(workspace_id.to_string())
            .bind(&src)
            .bind(&tgt)
            .fetch_optional(pool)
            .await?;

            if existing.is_none() {
                let weight = (*shared_entities as f64 / 10.0).clamp(0.3, 1.0);
                let metadata = serde_json::json!({
                    "shared_entities": shared_entities,
                    "created_by": "auto_semantic_layer",
                });
                sqlx::query(
                    "INSERT INTO entity_relations (workspace_id, source_entity_id, target_entity_id, relation_type, weight, graph_layer, metadata) \
                     VALUES ($1, $2, $3, 'related_to', $4, 'semantic', $5)"
                )
                .bind(workspace_id.to_string())
                .bind(&src)
                .bind(&tgt)
                .bind(weight)
                .bind(metadata.to_string())
                .execute(pool)
                .await?;
                relation_count += 1;
            }
        }
    }

    tracing::info!(
        workspace_id = %workspace_id,
        entities = entity_count,
        relations = relation_count,
        "Semantic graph layer built"
    );

    Ok((entity_count, relation_count))
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn test_parse_extraction_result() {
        let json = r#"{
            "entities": [
                {"name": "Rust", "entity_type": "technology", "description": "Programming language"},
                {"name": "Axum", "entity_type": "technology", "description": "Web framework"}
            ],
            "relations": [
                {"source": "Axum", "target": "Rust", "relation_type": "part_of", "description": "Axum is built with Rust"}
            ]
        }"#;

        let result: ExtractionResult = serde_json::from_str(json).unwrap();
        assert_eq!(result.entities.len(), 2);
        assert_eq!(result.relations.len(), 1);
        assert_eq!(result.entities[0].name, "Rust");
        assert_eq!(result.relations[0].relation_type, "part_of");
    }

    #[test]
    fn test_parse_extraction_empty() {
        let json = r#"{"entities": [], "relations": []}"#;
        let result: ExtractionResult = serde_json::from_str(json).unwrap();
        assert!(result.entities.is_empty());
        assert!(result.relations.is_empty());
    }

    #[test]
    fn test_parse_extraction_missing_optional_fields() {
        let json = r#"{
            "entities": [
                {"name": "Test", "entity_type": "concept"}
            ],
            "relations": [
                {"source": "A", "target": "B", "relation_type": "related_to"}
            ]
        }"#;

        let result: ExtractionResult = serde_json::from_str(json).unwrap();
        assert_eq!(result.entities[0].description, "");
        assert_eq!(result.relations[0].description, "");
        assert!((result.relations[0].confidence - 0.8).abs() < 0.001);
    }

    #[test]
    fn test_parse_extraction_with_confidence() {
        let json = r#"{
            "entities": [
                {"name": "Rust", "entity_type": "technology", "description": "A language"}
            ],
            "relations": [
                {"source": "Rust", "target": "Rust", "relation_type": "related_to", "confidence": 0.95, "description": "self-ref"}
            ]
        }"#;

        let result: ExtractionResult = serde_json::from_str(json).unwrap();
        assert!((result.relations[0].confidence - 0.95).abs() < 0.001);
    }

    #[test]
    fn test_entity_type_values() {
        let types = ["person", "organization", "concept", "technology", "location", "event", "other"];
        for t in types {
            let json = format!(r#"{{"name": "test", "entity_type": "{}", "description": ""}}"#, t);
            let entity: ExtractedEntity = serde_json::from_str(&json).unwrap();
            assert_eq!(entity.entity_type, t);
        }
    }

    #[test]
    fn test_relation_type_values() {
        let types = ["uses", "part_of", "related_to", "causes", "depends_on", "created_by", "belongs_to", "similar_to"];
        for t in types {
            let json = format!(r#"{{"source": "A", "target": "B", "relation_type": "{}", "description": ""}}"#, t);
            let relation: ExtractedRelation = serde_json::from_str(&json).unwrap();
            assert_eq!(relation.relation_type, t);
        }
    }
}
