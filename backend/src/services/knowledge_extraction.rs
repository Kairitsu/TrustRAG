use anyhow::Result;
use serde::{Deserialize, Serialize};
use std::collections::HashMap;
use uuid::Uuid;

use crate::db::DbPool;
use crate::traits::llm_provider::{LlmMessage, LlmProvider, LlmRequest};

#[derive(Debug, Clone, Default, Serialize)]
pub struct ExtractionStats {
    pub entities_created: usize,
    pub relations_created: usize,
    pub relations_llm_returned: usize,
    pub relations_skipped_match: usize,
    pub relations_skipped_duplicate: usize,
    pub relations_db_failed: usize,
    pub chunk_parse_failures: usize,
    pub json_parse_failures: usize,
    pub warnings: Vec<String>,
}

impl ExtractionStats {
    pub fn merge(&mut self, other: &ExtractionStats) {
        self.entities_created += other.entities_created;
        self.relations_created += other.relations_created;
        self.relations_llm_returned += other.relations_llm_returned;
        self.relations_skipped_match += other.relations_skipped_match;
        self.relations_skipped_duplicate += other.relations_skipped_duplicate;
        self.relations_db_failed += other.relations_db_failed;
        self.chunk_parse_failures += other.chunk_parse_failures;
        self.json_parse_failures += other.json_parse_failures;
        self.warnings.extend(other.warnings.clone());
    }
}

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct ExtractedEntity {
    pub entity_key: String,
    pub original_name: String,
    pub display_name: String,
    pub entity_type: String,
    #[serde(default)]
    pub original_language: String,
    #[serde(default)]
    pub description: String,
    #[serde(default)]
    pub aliases: Vec<String>,
}

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct ExtractedRelation {
    pub source_key: String,
    pub target_key: String,
    pub relation_type: String,
    #[serde(default = "default_confidence")]
    pub confidence: f64,
    #[serde(default)]
    pub description: String,
    #[serde(default)]
    pub evidence_text: String,
}

fn default_confidence() -> f64 {
    0.8
}

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct ExtractionResult {
    pub entities: Vec<ExtractedEntity>,
    pub relations: Vec<ExtractedRelation>,
}

const ENTITY_TYPES: &str = "regulator|law|jurisdiction|stablecoin|issuer|exchange|bank|license|reserve_asset|requirement|prohibition|risk|reporting_obligation|consumer_protection|aml_cft_rule|sanction|supervision_measure|document|event|other";

const RELATION_TYPES: &str = "regulates|requires|prohibits|issued_by|supervised_by|applies_to|defines|exempts|reports_to|licensed_by|backed_by|must_disclose|must_hold|must_register|enforced_by|related_to|part_of|conflicts_with|similar_to";

fn build_extraction_prompt(target_language: &str) -> String {
    format!(
        r#"You are a knowledge graph extraction assistant specialized in stablecoin and digital asset regulation documents worldwide.

Given a regulatory text passage, extract entities and relationships relevant to stablecoin supervision, licensing, reserves, AML/CFT, consumer protection, and cross-border compliance.

Output ONLY a JSON object with this exact structure:
{{
  "entities": [
    {{
      "entity_key": "unique_snake_case_key",
      "original_name": "name as it appears in source text",
      "display_name": "localized display name in {lang}",
      "entity_type": "{entity_types}",
      "original_language": "detected ISO-like language code (e.g. en, zh, ko, pt)",
      "description": "brief description in {lang}",
      "aliases": ["abbreviation", "translation", "alternate spelling"]
    }}
  ],
  "relations": [
    {{
      "source_key": "entity_key of source",
      "target_key": "entity_key of target",
      "relation_type": "{relation_types}",
      "confidence": 0.85,
      "description": "relationship explanation in {lang}",
      "evidence_text": "short quote from passage supporting this relation"
    }}
  ]
}}

Rules:
1. Extract regulators, laws, jurisdictions, stablecoin types, issuers, exchanges, banks, licenses, reserve assets, disclosure/redemption/AML requirements, prohibitions, risks, sanctions, supervision measures, and key regulatory events.
2. Each entity MUST have a unique entity_key (lowercase snake_case, ASCII). Relations MUST reference source_key/target_key from the entities list — never use free-text names for relation endpoints.
3. original_name MUST preserve the exact text from the source document. display_name MUST be in {lang} for user interface display.
4. Do NOT overwrite or omit original_name. Provide aliases for abbreviations and cross-language names (e.g. SEC, Securities and Exchange Commission).
5. Maximum 20 entities and 25 relations per passage. confidence is 0.0-1.0.
6. Every relation must include evidence_text from the passage.
7. Output ONLY valid JSON, no markdown or explanation."#,
        lang = target_language,
        entity_types = ENTITY_TYPES,
        relation_types = RELATION_TYPES,
    )
}

pub fn normalize_key(s: &str) -> String {
    let lower = s.to_lowercase();
    let mut result = String::new();
    let mut last_underscore = false;
    for ch in lower.chars() {
        if ch.is_ascii_alphanumeric() {
            result.push(ch);
            last_underscore = false;
        } else if !last_underscore {
            result.push('_');
            last_underscore = true;
        }
    }
    result.trim_matches('_').to_string()
}

pub async fn extract_from_text(
    llm_provider: &dyn LlmProvider,
    text: &str,
    target_language: &str,
) -> Result<ExtractionResult> {
    let truncated: String = text.chars().take(4000).collect();
    let system_prompt = build_extraction_prompt(target_language);

    let req = LlmRequest {
        messages: vec![
            LlmMessage {
                role: "system".to_string(),
                content: system_prompt,
            },
            LlmMessage {
                role: "user".to_string(),
                content: format!(
                    "Target display language: {}\n\nExtract entities and relationships from this regulatory text:\n\n{}",
                    target_language, truncated
                ),
            },
        ],
        temperature: 0.1,
        max_tokens: 4000,
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

    let mut result: ExtractionResult = serde_json::from_str(json_str)
        .map_err(|e| anyhow::anyhow!("Failed to parse extraction result: {}. Raw: {}", e, &json_str[..json_str.len().min(200)]))?;

    for entity in &mut result.entities {
        if entity.entity_key.is_empty() {
            entity.entity_key = normalize_key(&entity.original_name);
        }
        if entity.display_name.is_empty() {
            entity.display_name = entity.original_name.clone();
        }
        if entity.original_name.is_empty() {
            entity.original_name = entity.display_name.clone();
        }
    }

    Ok(result)
}

struct EntityIndex {
    by_key: HashMap<String, String>,
    by_normalized_name: HashMap<String, String>,
}

impl EntityIndex {
    fn new() -> Self {
        Self {
            by_key: HashMap::new(),
            by_normalized_name: HashMap::new(),
        }
    }

    fn insert(&mut self, entity_id: String, key: &str, original: &str, display: &str, aliases: &[String]) {
        if !key.is_empty() {
            self.by_key.insert(key.to_string(), entity_id.clone());
        }
        self.by_normalized_name.insert(normalize_key(original), entity_id.clone());
        if display != original {
            self.by_normalized_name.insert(normalize_key(display), entity_id.clone());
        }
        for alias in aliases {
            self.by_normalized_name.insert(normalize_key(alias), entity_id.clone());
        }
    }

    fn lookup(&self, key: &str) -> Option<&String> {
        self.by_key.get(key).or_else(|| self.by_normalized_name.get(&normalize_key(key)))
    }
}

pub async fn store_extraction(
    pool: &DbPool,
    workspace_id: Uuid,
    document_id: Uuid,
    chunk_id: Option<Uuid>,
    result: &ExtractionResult,
    stats: &mut ExtractionStats,
) -> Result<()> {
    let mut index = EntityIndex::new();

    for entity in &result.entities {
        let key = if entity.entity_key.is_empty() {
            normalize_key(&entity.original_name)
        } else {
            entity.entity_key.clone()
        };

        let existing: Option<(String,)> = sqlx::query_as(
            "SELECT id FROM entities WHERE workspace_id = $1 AND entity_key = $2 LIMIT 1",
        )
        .bind(workspace_id.to_string())
        .bind(&key)
        .fetch_optional(pool)
        .await?;

        let entity_id = if let Some((id,)) = existing {
            id
        } else {
            let aliases_json = serde_json::to_string(&entity.aliases).unwrap_or_else(|_| "[]".into());
            let metadata = serde_json::json!({
                "description": entity.description,
                "source_document_id": document_id.to_string(),
                "aliases": entity.aliases,
            });

            let row: (String,) = sqlx::query_as(
                "INSERT INTO entities (
                    workspace_id, name, entity_type, document_id, chunk_id, graph_layer,
                    entity_key, original_name, display_name, original_language, aliases, metadata
                ) VALUES ($1, $2, $3, $4, $5, 'knowledge', $6, $7, $8, $9, $10, $11)
                RETURNING id",
            )
            .bind(workspace_id.to_string())
            .bind(&entity.display_name)
            .bind(&entity.entity_type)
            .bind(document_id.to_string())
            .bind(chunk_id.map(|c| c.to_string()))
            .bind(&key)
            .bind(&entity.original_name)
            .bind(&entity.display_name)
            .bind(&entity.original_language)
            .bind(&aliases_json)
            .bind(metadata.to_string())
            .fetch_one(pool)
            .await?;

            stats.entities_created += 1;
            row.0
        };

        index.insert(entity_id, &key, &entity.original_name, &entity.display_name, &entity.aliases);
    }

    stats.relations_llm_returned += result.relations.len();

    for relation in &result.relations {
        let source_id = index.lookup(&relation.source_key);
        let target_id = index.lookup(&relation.target_key);

        if source_id.is_none() || target_id.is_none() {
            stats.relations_skipped_match += 1;
            let warning = format!(
                "Relation skipped (endpoint match failed): {} --[{}]--> {} (source_key={}, target_key={})",
                relation.source_key, relation.relation_type, relation.target_key,
                relation.source_key, relation.target_key
            );
            tracing::warn!(%warning);
            stats.warnings.push(warning);
            continue;
        }

        let src = source_id.unwrap();
        let tgt = target_id.unwrap();

        let existing: Option<(String,)> = sqlx::query_as(
            "SELECT id FROM entity_relations \
             WHERE workspace_id = $1 AND source_entity_id = $2 AND target_entity_id = $3 AND relation_type = $4",
        )
        .bind(workspace_id.to_string())
        .bind(src)
        .bind(tgt)
        .bind(&relation.relation_type)
        .fetch_optional(pool)
        .await?;

        if existing.is_some() {
            stats.relations_skipped_duplicate += 1;
            continue;
        }

        let metadata = serde_json::json!({
            "description": relation.description,
            "evidence_text": relation.evidence_text,
            "source_document_id": document_id.to_string(),
            "source_chunk_id": chunk_id.map(|c| c.to_string()),
        });

        let weight = relation.confidence.clamp(0.0, 1.0);
        let insert_result = sqlx::query(
            "INSERT INTO entity_relations (workspace_id, source_entity_id, target_entity_id, relation_type, weight, graph_layer, metadata) \
             VALUES ($1, $2, $3, $4, $5, 'knowledge', $6)",
        )
        .bind(workspace_id.to_string())
        .bind(src)
        .bind(tgt)
        .bind(&relation.relation_type)
        .bind(weight)
        .bind(metadata.to_string())
        .execute(pool)
        .await;

        match insert_result {
            Ok(_) => stats.relations_created += 1,
            Err(e) => {
                stats.relations_db_failed += 1;
                let warning = format!("Relation DB insert failed: {} --[{}]--> {}: {}", relation.source_key, relation.relation_type, relation.target_key, e);
                tracing::warn!(%warning);
                stats.warnings.push(warning);
            }
        }
    }

    Ok(())
}

pub async fn extract_for_document(
    pool: &DbPool,
    llm_provider: &dyn LlmProvider,
    workspace_id: Uuid,
    document_id: Uuid,
    target_language: &str,
) -> Result<ExtractionStats> {
    let chunks = sqlx::query_as::<_, (String, String)>(
        "SELECT id, content FROM document_chunks WHERE document_id = $1 ORDER BY chunk_index ASC LIMIT 30",
    )
    .bind(document_id.to_string())
    .fetch_all(pool)
    .await?;

    if chunks.is_empty() {
        anyhow::bail!("No chunks found for document {}", document_id);
    }

    let mut stats = ExtractionStats::default();

    for (chunk_id_str, content) in &chunks {
        if content.trim().len() < 50 {
            continue;
        }

        let chunk_id: Uuid = chunk_id_str.parse().unwrap_or_default();

        match extract_from_text(llm_provider, content, target_language).await {
            Ok(result) => {
                if let Err(e) = store_extraction(pool, workspace_id, document_id, Some(chunk_id), &result, &mut stats).await {
                    stats.chunk_parse_failures += 1;
                    tracing::warn!(chunk_id = %chunk_id, error = %e, "Failed to store extraction");
                }
            }
            Err(e) => {
                stats.json_parse_failures += 1;
                tracing::warn!(chunk_id = %chunk_id, error = %e, "Failed to extract from chunk");
            }
        }
    }

    tracing::info!(
        document_id = %document_id,
        entities = stats.entities_created,
        relations = stats.relations_created,
        skipped_match = stats.relations_skipped_match,
        chunks = chunks.len(),
        "Knowledge extraction completed for document"
    );

    Ok(stats)
}

pub async fn reset_workspace_graph(pool: &DbPool, workspace_id: Uuid) -> Result<(usize, usize)> {
    let relations_deleted = sqlx::query("DELETE FROM entity_relations WHERE workspace_id = $1")
        .bind(workspace_id.to_string())
        .execute(pool)
        .await?
        .rows_affected() as usize;

    let entities_deleted = sqlx::query("DELETE FROM entities WHERE workspace_id = $1")
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

pub async fn build_document_layer(pool: &DbPool, workspace_id: Uuid) -> Result<(usize, usize)> {
    let mut entity_count = 0usize;
    let mut relation_count = 0usize;

    let docs = sqlx::query_as::<_, (String, String, Option<String>)>(
        "SELECT id, title, folder FROM documents WHERE workspace_id = $1 AND processing_status IN ('ready', 'completed')",
    )
    .bind(workspace_id.to_string())
    .fetch_all(pool)
    .await?;

    let mut doc_entity_ids: HashMap<String, String> = HashMap::new();

    for (doc_id, title, folder) in &docs {
        let existing: Option<(String,)> = sqlx::query_as(
            "SELECT id FROM entities WHERE workspace_id = $1 AND document_id = $2 AND graph_layer = 'document' AND entity_type = 'document'",
        )
        .bind(workspace_id.to_string())
        .bind(doc_id)
        .fetch_optional(pool)
        .await?;

        let entity_id = if let Some((id,)) = existing {
            id
        } else {
            let key = format!("doc_{}", normalize_key(doc_id));
            let metadata = serde_json::json!({
                "source_document_id": doc_id,
                "folder": folder.as_deref().unwrap_or(""),
                "created_by": "auto_document_layer",
            });
            let row: (String,) = sqlx::query_as(
                "INSERT INTO entities (workspace_id, name, entity_type, document_id, graph_layer, entity_key, original_name, display_name, metadata) \
                 VALUES ($1, $2, 'document', $3, 'document', $4, $5, $5, $6) RETURNING id",
            )
            .bind(workspace_id.to_string())
            .bind(title)
            .bind(doc_id)
            .bind(&key)
            .bind(title)
            .bind(metadata.to_string())
            .fetch_one(pool)
            .await?;
            entity_count += 1;
            row.0
        };

        doc_entity_ids.insert(doc_id.clone(), entity_id);
    }

    let mut folder_groups: HashMap<String, Vec<String>> = HashMap::new();
    for (doc_id, _, folder) in &docs {
        let folder_key = folder.as_deref().unwrap_or("__root__").to_string();
        folder_groups.entry(folder_key).or_default().push(doc_id.clone());
    }

    for (_folder, doc_ids_in_folder) in &folder_groups {
        if doc_ids_in_folder.len() < 2 {
            continue;
        }
        for i in 0..doc_ids_in_folder.len() {
            for j in (i + 1)..doc_ids_in_folder.len() {
                let src_eid = doc_entity_ids.get(&doc_ids_in_folder[i]);
                let tgt_eid = doc_entity_ids.get(&doc_ids_in_folder[j]);
                if let (Some(src), Some(tgt)) = (src_eid, tgt_eid) {
                    let existing: Option<(String,)> = sqlx::query_as(
                        "SELECT id FROM entity_relations \
                         WHERE workspace_id = $1 AND source_entity_id = $2 AND target_entity_id = $3 AND graph_layer = 'document'",
                    )
                    .bind(workspace_id.to_string())
                    .bind(src)
                    .bind(tgt)
                    .fetch_optional(pool)
                    .await?;

                    if existing.is_none() {
                        sqlx::query(
                            "INSERT INTO entity_relations (workspace_id, source_entity_id, target_entity_id, relation_type, weight, graph_layer, metadata) \
                             VALUES ($1, $2, $3, 'co_located', 0.5, 'document', '{}')",
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

    // Shared-entity links between documents
    let shared_rows = sqlx::query_as::<_, (String, String, i32)>(
        "SELECT e1.document_id, e2.document_id, COUNT(DISTINCT e1.entity_key) as shared \
         FROM entities e1 \
         JOIN entities e2 ON e1.workspace_id = e2.workspace_id \
            AND e1.entity_key = e2.entity_key AND e1.document_id < e2.document_id \
         WHERE e1.workspace_id = $1 AND e1.graph_layer = 'knowledge' AND e2.graph_layer = 'knowledge' \
           AND e1.document_id IS NOT NULL AND e2.document_id IS NOT NULL \
         GROUP BY e1.document_id, e2.document_id HAVING COUNT(DISTINCT e1.entity_key) >= 2 LIMIT 200",
    )
    .bind(workspace_id.to_string())
    .fetch_all(pool)
    .await
    .unwrap_or_default();

    for (doc1_id, doc2_id, shared) in &shared_rows {
        if let (Some(src), Some(tgt)) = (doc_entity_ids.get(doc1_id), doc_entity_ids.get(doc2_id)) {
            let existing: Option<(String,)> = sqlx::query_as(
                "SELECT id FROM entity_relations \
                 WHERE workspace_id = $1 AND source_entity_id = $2 AND target_entity_id = $3 AND graph_layer = 'document'",
            )
            .bind(workspace_id.to_string())
            .bind(src)
            .bind(tgt)
            .fetch_optional(pool)
            .await?;

            if existing.is_none() {
                let weight = (*shared as f64 / 10.0).clamp(0.3, 1.0);
                let metadata = serde_json::json!({ "shared_entities": shared, "created_by": "auto_document_layer" });
                sqlx::query(
                    "INSERT INTO entity_relations (workspace_id, source_entity_id, target_entity_id, relation_type, weight, graph_layer, metadata) \
                     VALUES ($1, $2, $3, 'shared_entities', $4, 'document', $5)",
                )
                .bind(workspace_id.to_string())
                .bind(src)
                .bind(tgt)
                .bind(weight)
                .bind(metadata.to_string())
                .execute(pool)
                .await?;
                relation_count += 1;
            }
        }
    }

    tracing::info!(workspace_id = %workspace_id, entities = entity_count, relations = relation_count, "Document network layer built");
    Ok((entity_count, relation_count))
}

pub async fn build_semantic_layer(pool: &DbPool, workspace_id: Uuid) -> Result<(usize, usize)> {
    let mut relation_count = 0usize;

    let cooccurrence_rows = sqlx::query_as::<_, (String, String, i32)>(
        "SELECT e1.id, e2.id, COUNT(*) as cooccur \
         FROM entities e1 \
         JOIN entities e2 ON e1.workspace_id = e2.workspace_id AND e1.id < e2.id \
         WHERE e1.workspace_id = $1 \
           AND e1.graph_layer = 'knowledge' AND e2.graph_layer = 'knowledge' \
           AND e1.document_id IS NOT NULL AND e2.document_id IS NOT NULL \
           AND e1.document_id = e2.document_id \
         GROUP BY e1.id, e2.id HAVING COUNT(*) >= 1 LIMIT 300",
    )
    .bind(workspace_id.to_string())
    .fetch_all(pool)
    .await?;

    for (e1_id, e2_id, cooccur) in &cooccurrence_rows {
        let existing: Option<(String,)> = sqlx::query_as(
            "SELECT id FROM entity_relations \
             WHERE workspace_id = $1 AND source_entity_id = $2 AND target_entity_id = $3 AND graph_layer = 'semantic'",
        )
        .bind(workspace_id.to_string())
        .bind(e1_id)
        .bind(e2_id)
        .fetch_optional(pool)
        .await?;

        if existing.is_none() {
            let weight = (*cooccur as f64 / 5.0).clamp(0.3, 1.0);
            let metadata = serde_json::json!({ "cooccurrence": cooccur, "created_by": "auto_semantic_layer" });
            sqlx::query(
                "INSERT INTO entity_relations (workspace_id, source_entity_id, target_entity_id, relation_type, weight, graph_layer, metadata) \
                 VALUES ($1, $2, $3, 'co_occurs', $4, 'semantic', $5)",
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

    let cross_doc_rows = sqlx::query_as::<_, (String, String, i32)>(
        "SELECT DISTINCT e1.document_id, e2.document_id, COUNT(DISTINCT e1.entity_key) as shared_entities \
         FROM entities e1 \
         JOIN entities e2 ON e1.workspace_id = e2.workspace_id \
            AND e1.entity_key = e2.entity_key AND e1.document_id < e2.document_id \
         WHERE e1.workspace_id = $1 \
           AND e1.graph_layer = 'knowledge' AND e2.graph_layer = 'knowledge' \
           AND e1.document_id IS NOT NULL AND e2.document_id IS NOT NULL \
         GROUP BY e1.document_id, e2.document_id HAVING COUNT(DISTINCT e1.entity_key) >= 2 LIMIT 100",
    )
    .bind(workspace_id.to_string())
    .fetch_all(pool)
    .await?;

    for (doc1_id, doc2_id, shared_entities) in &cross_doc_rows {
        let doc1_eid: Option<(String,)> = sqlx::query_as(
            "SELECT id FROM entities WHERE workspace_id = $1 AND document_id = $2 AND graph_layer = 'document' AND entity_type = 'document'",
        )
        .bind(workspace_id.to_string())
        .bind(doc1_id)
        .fetch_optional(pool)
        .await?;

        let doc2_eid: Option<(String,)> = sqlx::query_as(
            "SELECT id FROM entities WHERE workspace_id = $1 AND document_id = $2 AND graph_layer = 'document' AND entity_type = 'document'",
        )
        .bind(workspace_id.to_string())
        .bind(doc2_id)
        .fetch_optional(pool)
        .await?;

        if let (Some((src,)), Some((tgt,))) = (doc1_eid, doc2_eid) {
            let existing: Option<(String,)> = sqlx::query_as(
                "SELECT id FROM entity_relations \
                 WHERE workspace_id = $1 AND source_entity_id = $2 AND target_entity_id = $3 AND graph_layer = 'semantic'",
            )
            .bind(workspace_id.to_string())
            .bind(&src)
            .bind(&tgt)
            .fetch_optional(pool)
            .await?;

            if existing.is_none() {
                let weight = (*shared_entities as f64 / 10.0).clamp(0.3, 1.0);
                let metadata = serde_json::json!({ "shared_entities": shared_entities, "created_by": "auto_semantic_layer" });
                sqlx::query(
                    "INSERT INTO entity_relations (workspace_id, source_entity_id, target_entity_id, relation_type, weight, graph_layer, metadata) \
                     VALUES ($1, $2, $3, 'topic_similar', $4, 'semantic', $5)",
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

    tracing::info!(workspace_id = %workspace_id, relations = relation_count, "Semantic graph layer built");
    Ok((0, relation_count))
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn test_parse_extraction_result_with_keys() {
        let json = r#"{
            "entities": [
                {"entity_key": "sec", "original_name": "SEC", "display_name": "美国证券交易委员会", "entity_type": "regulator", "original_language": "en", "description": "US regulator", "aliases": ["Securities and Exchange Commission"]}
            ],
            "relations": [
                {"source_key": "sec", "target_key": "sec", "relation_type": "supervised_by", "confidence": 0.9, "description": "self", "evidence_text": "SEC oversees"}
            ]
        }"#;

        let result: ExtractionResult = serde_json::from_str(json).unwrap();
        assert_eq!(result.entities.len(), 1);
        assert_eq!(result.entities[0].entity_key, "sec");
        assert_eq!(result.entities[0].display_name, "美国证券交易委员会");
        assert_eq!(result.relations[0].source_key, "sec");
    }

    #[test]
    fn test_normalize_key() {
        assert_eq!(normalize_key("SEC / U.S."), "sec_u_s");
        assert_eq!(normalize_key("MiCA Regulation"), "mica_regulation");
    }

    #[test]
    fn test_parse_extraction_empty() {
        let json = r#"{"entities": [], "relations": []}"#;
        let result: ExtractionResult = serde_json::from_str(json).unwrap();
        assert!(result.entities.is_empty());
        assert!(result.relations.is_empty());
    }

    #[test]
    fn test_entity_type_domain_values() {
        for t in ["regulator", "stablecoin", "aml_cft_rule", "jurisdiction"] {
            let json = format!(
                r#"{{"entity_key":"k","original_name":"X","display_name":"X","entity_type":"{}"}}"#,
                t
            );
            let entity: ExtractedEntity = serde_json::from_str(&json).unwrap();
            assert_eq!(entity.entity_type, t);
        }
    }

    #[test]
    fn test_relation_type_domain_values() {
        for t in ["regulates", "must_disclose", "backed_by"] {
            let json = format!(
                r#"{{"source_key":"a","target_key":"b","relation_type":"{}"}}"#,
                t
            );
            let relation: ExtractedRelation = serde_json::from_str(&json).unwrap();
            assert_eq!(relation.relation_type, t);
        }
    }
}