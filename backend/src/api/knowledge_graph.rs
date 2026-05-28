use axum::{
    extract::{Path, State},
    routing::{get, post, delete},
    Json, Router,
};
use serde::{Deserialize, Serialize};
use uuid::Uuid;

use crate::auth::middleware::AuthUser;
use crate::error::AppError;
use crate::services::knowledge_extraction;
use crate::services::llm::OpenAILlmProvider;

use super::AppState;

pub fn router() -> Router<AppState> {
    Router::new()
        .route("/workspaces/{ws_id}/knowledge-graph", get(get_graph))
        .route(
            "/workspaces/{ws_id}/knowledge-graph/entities",
            get(list_entities),
        )
        .route(
            "/workspaces/{ws_id}/knowledge-graph/generate/{doc_id}",
            post(generate_for_document),
        )
        .route(
            "/workspaces/{ws_id}/knowledge-graph/generate-all",
            post(generate_for_all_documents),
        )
        .route(
            "/workspaces/{ws_id}/knowledge-graph/reset",
            delete(reset_graph),
        )
        .route(
            "/workspaces/{ws_id}/knowledge-graph/stats",
            get(graph_stats),
        )
}

#[derive(Serialize)]
struct EntityRow {
    id: Uuid,
    name: String,
    entity_type: String,
    document_id: Option<Uuid>,
    metadata: serde_json::Value,
    created_at: String,
}

struct RelationRow {
    id: Uuid,
    source_entity_id: Uuid,
    target_entity_id: Uuid,
    relation_type: String,
    weight: f64,
}

#[derive(Serialize)]
struct GraphResponse {
    nodes: Vec<GraphNode>,
    edges: Vec<GraphEdge>,
}

#[derive(Serialize)]
struct GraphNode {
    id: String,
    label: String,
    entity_type: String,
    document_id: Option<Uuid>,
}

#[derive(Serialize)]
struct GraphEdge {
    source: String,
    target: String,
    relation: String,
    weight: f64,
}

async fn check_workspace_access(
    pool: &crate::db::DbPool,
    ws_id: Uuid,
    user_id: Uuid,
) -> Result<(), AppError> {
    let access_count: i32 = sqlx::query_scalar(
        r#"
        SELECT COUNT(*) FROM workspaces
        WHERE id = $1
          AND (owner_id = $2
               OR id IN (SELECT workspace_id FROM workspace_members WHERE user_id = $2)
               OR visibility = 'public')
        "#,
    )
    .bind(ws_id.to_string())
    .bind(user_id.to_string())
    .fetch_one(pool)
    .await?;

    if access_count == 0 {
        return Err(AppError::NotFound("Workspace not found".into()));
    }
    Ok(())
}

async fn get_graph(
    State(state): State<AppState>,
    auth: AuthUser,
    Path(ws_id): Path<Uuid>,
) -> Result<Json<GraphResponse>, AppError> {
    check_workspace_access(&state.pool, ws_id, auth.id).await?;
    tracing::info!(workspace_id = %ws_id, "Fetching knowledge graph");

    let entity_rows = sqlx::query_as::<_, (String, String, String, Option<String>, Option<String>, String)>(
        "SELECT id, name, entity_type, document_id, CAST(metadata AS TEXT), CAST(created_at AS TEXT)
         FROM entities WHERE workspace_id = $1 ORDER BY name",
    )
    .bind(ws_id.to_string())
    .fetch_all(&state.pool)
    .await?;

    let entities: Vec<EntityRow> = entity_rows.into_iter().map(|r| {
        let metadata: serde_json::Value = r.4.as_deref()
            .and_then(|s| serde_json::from_str(s).ok())
            .unwrap_or(serde_json::json!({}));
        EntityRow {
            id: r.0.parse().unwrap_or_default(),
            name: r.1,
            entity_type: r.2,
            document_id: r.3.as_deref().and_then(|s| s.parse().ok()),
            metadata,
            created_at: r.5,
        }
    }).collect();

    let relation_rows = sqlx::query_as::<_, (String, String, String, String, f64)>(
        "SELECT id, source_entity_id, target_entity_id, relation_type, weight
         FROM entity_relations WHERE workspace_id = $1",
    )
    .bind(ws_id.to_string())
    .fetch_all(&state.pool)
    .await?;

    let relations: Vec<RelationRow> = relation_rows.into_iter().map(|r| {
        RelationRow {
            id: r.0.parse().unwrap_or_default(),
            source_entity_id: r.1.parse().unwrap_or_default(),
            target_entity_id: r.2.parse().unwrap_or_default(),
            relation_type: r.3,
            weight: r.4,
        }
    }).collect();

    let nodes: Vec<GraphNode> = entities
        .iter()
        .map(|e| GraphNode {
            id: e.id.to_string(),
            label: e.name.clone(),
            entity_type: e.entity_type.clone(),
            document_id: e.document_id,
        })
        .collect();

    let edges: Vec<GraphEdge> = relations
        .iter()
        .map(|r| GraphEdge {
            source: r.source_entity_id.to_string(),
            target: r.target_entity_id.to_string(),
            relation: r.relation_type.clone(),
            weight: r.weight,
        })
        .collect();

    Ok(Json(GraphResponse { nodes, edges }))
}

async fn list_entities(
    State(state): State<AppState>,
    auth: AuthUser,
    Path(ws_id): Path<Uuid>,
) -> Result<Json<Vec<EntityRow>>, AppError> {
    check_workspace_access(&state.pool, ws_id, auth.id).await?;
    let rows = sqlx::query_as::<_, (String, String, String, Option<String>, Option<String>, String)>(
        "SELECT id, name, entity_type, document_id, CAST(metadata AS TEXT), CAST(created_at AS TEXT)
         FROM entities WHERE workspace_id = $1 ORDER BY created_at DESC LIMIT 200",
    )
    .bind(ws_id.to_string())
    .fetch_all(&state.pool)
    .await?;

    let entities: Vec<EntityRow> = rows.into_iter().map(|r| {
        let metadata: serde_json::Value = r.4.as_deref()
            .and_then(|s| serde_json::from_str(s).ok())
            .unwrap_or(serde_json::json!({}));
        EntityRow {
            id: r.0.parse().unwrap_or_default(),
            name: r.1,
            entity_type: r.2,
            document_id: r.3.as_deref().and_then(|s| s.parse().ok()),
            metadata,
            created_at: r.5,
        }
    }).collect();

    Ok(Json(entities))
}

// ── Knowledge Extraction Endpoints ──

#[derive(Serialize)]
struct GenerateResponse {
    success: bool,
    entities_created: usize,
    relations_created: usize,
    message: String,
}

#[derive(Serialize)]
struct GraphStatsResponse {
    entity_count: i64,
    relation_count: i64,
    entity_types: Vec<TypeCount>,
    relation_types: Vec<TypeCount>,
}

#[derive(Serialize)]
struct TypeCount {
    name: String,
    count: i64,
}

async fn load_default_llm(
    pool: &crate::db::DbPool,
    user_id: Uuid,
    jwt_secret: &str,
) -> Result<OpenAILlmProvider, AppError> {
    let (api_base_url, api_key_enc, model_name) = sqlx::query_as::<_, (String, Option<String>, String)>(
        "SELECT api_base_url, api_key_enc, model_name \
         FROM model_configs WHERE user_id = $1 AND is_default = 1 LIMIT 1",
    )
    .bind(user_id.to_string())
    .fetch_optional(pool)
    .await?
    .ok_or_else(|| AppError::BadRequest("No default LLM model configured. Please configure a model first.".into()))?;

    let api_key = api_key_enc.and_then(|enc| {
        crate::api::models::decrypt_api_key(&enc, jwt_secret)
    });

    Ok(OpenAILlmProvider::new(
        &api_base_url,
        api_key.as_deref(),
        &model_name,
    ))
}

async fn generate_for_document(
    State(state): State<AppState>,
    auth: AuthUser,
    Path((ws_id, doc_id)): Path<(Uuid, Uuid)>,
) -> Result<Json<GenerateResponse>, AppError> {
    check_workspace_access(&state.pool, ws_id, auth.id).await?;

    let llm = load_default_llm(&state.pool, auth.id, &state.jwt_secret).await?;

    let (entities, relations) = knowledge_extraction::extract_for_document(
        &state.pool,
        &llm,
        ws_id,
        doc_id,
    )
    .await
    .map_err(|e| AppError::Internal(anyhow::anyhow!("Knowledge extraction failed: {}", e)))?;

    Ok(Json(GenerateResponse {
        success: true,
        entities_created: entities,
        relations_created: relations,
        message: format!("Extracted {} entities and {} relations", entities, relations),
    }))
}

async fn generate_for_all_documents(
    State(state): State<AppState>,
    auth: AuthUser,
    Path(ws_id): Path<Uuid>,
) -> Result<Json<GenerateResponse>, AppError> {
    check_workspace_access(&state.pool, ws_id, auth.id).await?;

    let llm = load_default_llm(&state.pool, auth.id, &state.jwt_secret).await?;

    let doc_ids = sqlx::query_as::<_, (String,)>(
        "SELECT id FROM documents WHERE workspace_id = $1 AND processing_status = 'completed'"
    )
    .bind(ws_id.to_string())
    .fetch_all(&state.pool)
    .await?;

    if doc_ids.is_empty() {
        return Ok(Json(GenerateResponse {
            success: true,
            entities_created: 0,
            relations_created: 0,
            message: "No completed documents found in this workspace".into(),
        }));
    }

    let mut total_entities = 0;
    let mut total_relations = 0;

    for (doc_id_str,) in &doc_ids {
        let doc_id: Uuid = doc_id_str.parse().unwrap_or_default();
        match knowledge_extraction::extract_for_document(&state.pool, &llm, ws_id, doc_id).await {
            Ok((e, r)) => {
                total_entities += e;
                total_relations += r;
            }
            Err(e) => {
                tracing::warn!(document_id = %doc_id, error = %e, "Failed to extract for document");
            }
        }
    }

    Ok(Json(GenerateResponse {
        success: true,
        entities_created: total_entities,
        relations_created: total_relations,
        message: format!(
            "Processed {} documents: {} entities, {} relations",
            doc_ids.len(),
            total_entities,
            total_relations
        ),
    }))
}

async fn reset_graph(
    State(state): State<AppState>,
    auth: AuthUser,
    Path(ws_id): Path<Uuid>,
) -> Result<Json<GenerateResponse>, AppError> {
    check_workspace_access(&state.pool, ws_id, auth.id).await?;

    let (entities_deleted, relations_deleted) = knowledge_extraction::reset_workspace_graph(
        &state.pool,
        ws_id,
    )
    .await
    .map_err(|e| AppError::Internal(anyhow::anyhow!("Reset failed: {}", e)))?;

    Ok(Json(GenerateResponse {
        success: true,
        entities_created: entities_deleted,
        relations_created: relations_deleted,
        message: format!("Deleted {} entities and {} relations", entities_deleted, relations_deleted),
    }))
}

async fn graph_stats(
    State(state): State<AppState>,
    auth: AuthUser,
    Path(ws_id): Path<Uuid>,
) -> Result<Json<GraphStatsResponse>, AppError> {
    check_workspace_access(&state.pool, ws_id, auth.id).await?;

    let entity_count: i32 = sqlx::query_scalar(
        "SELECT COUNT(*) FROM entities WHERE workspace_id = $1"
    )
    .bind(ws_id.to_string())
    .fetch_one(&state.pool)
    .await?;

    let relation_count: i32 = sqlx::query_scalar(
        "SELECT COUNT(*) FROM entity_relations WHERE workspace_id = $1"
    )
    .bind(ws_id.to_string())
    .fetch_one(&state.pool)
    .await?;

    let et_rows = sqlx::query_as::<_, (String, i32)>(
        "SELECT entity_type, COUNT(*) FROM entities WHERE workspace_id = $1 GROUP BY entity_type ORDER BY COUNT(*) DESC"
    )
    .bind(ws_id.to_string())
    .fetch_all(&state.pool)
    .await?;

    let rt_rows = sqlx::query_as::<_, (String, i32)>(
        "SELECT relation_type, COUNT(*) FROM entity_relations WHERE workspace_id = $1 GROUP BY relation_type ORDER BY COUNT(*) DESC"
    )
    .bind(ws_id.to_string())
    .fetch_all(&state.pool)
    .await?;

    Ok(Json(GraphStatsResponse {
        entity_count: entity_count as i64,
        relation_count: relation_count as i64,
        entity_types: et_rows.into_iter().map(|(name, count)| TypeCount { name, count: count as i64 }).collect(),
        relation_types: rt_rows.into_iter().map(|(name, count)| TypeCount { name, count: count as i64 }).collect(),
    }))
}
