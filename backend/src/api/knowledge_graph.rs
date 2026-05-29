use axum::{
    extract::{Path, State},
    routing::{get, post, delete},
    Json, Router,
};
use serde::{Deserialize, Serialize};
use std::collections::HashMap;
use std::sync::{Arc, OnceLock};
use tokio::sync::RwLock;
use uuid::Uuid;

use crate::auth::middleware::AuthUser;
use crate::error::AppError;
use crate::services::knowledge_extraction;
use crate::services::llm::OpenAILlmProvider;

use super::AppState;

#[derive(Debug, Clone, Serialize)]
pub struct GenerationTask {
    pub task_id: String,
    pub workspace_id: String,
    pub status: String,
    pub total_documents: usize,
    pub processed_documents: usize,
    pub entities_created: usize,
    pub relations_created: usize,
    pub errors: Vec<String>,
    pub started_at: String,
    pub completed_at: Option<String>,
}

fn generation_tasks() -> &'static Arc<RwLock<HashMap<String, GenerationTask>>> {
    static TASKS: OnceLock<Arc<RwLock<HashMap<String, GenerationTask>>>> = OnceLock::new();
    TASKS.get_or_init(|| Arc::new(RwLock::new(HashMap::new())))
}

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
            "/workspaces/{ws_id}/knowledge-graph/generation-status/{task_id}",
            get(generation_status),
        )
        .route(
            "/workspaces/{ws_id}/knowledge-graph/reset",
            delete(reset_graph),
        )
        .route(
            "/workspaces/{ws_id}/knowledge-graph/stats",
            get(graph_stats),
        )
        .route(
            "/workspaces/{ws_id}/knowledge-graph/generation-history",
            get(generation_history),
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
    metadata: serde_json::Value,
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
    #[serde(skip_serializing_if = "Option::is_none")]
    description: Option<String>,
    #[serde(skip_serializing_if = "Option::is_none")]
    source_document_id: Option<String>,
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

    let relation_rows = sqlx::query_as::<_, (String, String, String, String, f64, Option<String>)>(
        "SELECT id, source_entity_id, target_entity_id, relation_type, weight, CAST(metadata AS TEXT)
         FROM entity_relations WHERE workspace_id = $1",
    )
    .bind(ws_id.to_string())
    .fetch_all(&state.pool)
    .await?;

    let relations: Vec<RelationRow> = relation_rows.into_iter().map(|r| {
        let metadata: serde_json::Value = r.5.as_deref()
            .and_then(|s| serde_json::from_str(s).ok())
            .unwrap_or(serde_json::json!({}));
        RelationRow {
            id: r.0.parse().unwrap_or_default(),
            source_entity_id: r.1.parse().unwrap_or_default(),
            target_entity_id: r.2.parse().unwrap_or_default(),
            relation_type: r.3,
            weight: r.4,
            metadata,
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
        .map(|r| {
            let description = r.metadata.get("description")
                .and_then(|v| v.as_str())
                .filter(|s| !s.is_empty())
                .map(|s| s.to_string());
            let source_document_id = r.metadata.get("source_document_id")
                .and_then(|v| v.as_str())
                .filter(|s| !s.is_empty())
                .map(|s| s.to_string());
            GraphEdge {
                source: r.source_entity_id.to_string(),
                target: r.target_entity_id.to_string(),
                relation: r.relation_type.clone(),
                weight: r.weight,
                description,
                source_document_id,
            }
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

#[derive(Serialize)]
struct AsyncGenerateResponse {
    task_id: String,
    status: String,
    total_documents: usize,
    message: String,
}

async fn generate_for_all_documents(
    State(state): State<AppState>,
    auth: AuthUser,
    Path(ws_id): Path<Uuid>,
) -> Result<Json<AsyncGenerateResponse>, AppError> {
    check_workspace_access(&state.pool, ws_id, auth.id).await?;

    let llm = load_default_llm(&state.pool, auth.id, &state.jwt_secret).await?;

    let doc_ids = sqlx::query_as::<_, (String,)>(
        "SELECT id FROM documents WHERE workspace_id = $1 AND processing_status = 'completed'"
    )
    .bind(ws_id.to_string())
    .fetch_all(&state.pool)
    .await?;

    if doc_ids.is_empty() {
        return Ok(Json(AsyncGenerateResponse {
            task_id: String::new(),
            status: "completed".into(),
            total_documents: 0,
            message: "No completed documents found in this workspace".into(),
        }));
    }

    let task_id = Uuid::new_v4().to_string();
    let now = chrono::Utc::now().to_rfc3339();
    let total = doc_ids.len();

    let task = GenerationTask {
        task_id: task_id.clone(),
        workspace_id: ws_id.to_string(),
        status: "running".into(),
        total_documents: total,
        processed_documents: 0,
        entities_created: 0,
        relations_created: 0,
        errors: Vec::new(),
        started_at: now.clone(),
        completed_at: None,
    };

    {
        let mut tasks = generation_tasks().write().await;
        tasks.insert(task_id.clone(), task);
    }

    let _ = sqlx::query(
        "INSERT INTO graph_generation_logs (id, workspace_id, user_id, status, total_documents, started_at) \
         VALUES ($1, $2, $3, 'running', $4, $5)"
    )
    .bind(&task_id)
    .bind(ws_id.to_string())
    .bind(auth.id.to_string())
    .bind(total as i32)
    .bind(&now)
    .execute(&state.pool)
    .await;

    let pool = state.pool.clone();
    let bg_task_id = task_id.clone();

    tokio::spawn(async move {
        let mut total_entities = 0usize;
        let mut total_relations = 0usize;
        let mut errors = Vec::new();
        let mut processed = 0usize;

        for (doc_id_str,) in &doc_ids {
            let doc_id: Uuid = doc_id_str.parse().unwrap_or_default();
            match knowledge_extraction::extract_for_document(&pool, &llm, ws_id, doc_id).await {
                Ok((e, r)) => {
                    total_entities += e;
                    total_relations += r;
                }
                Err(e) => {
                    let msg = format!("doc {}: {}", doc_id, e);
                    tracing::warn!(document_id = %doc_id, error = %e, "Failed to extract for document");
                    errors.push(msg);
                }
            }
            processed += 1;

            let mut tasks = generation_tasks().write().await;
            if let Some(t) = tasks.get_mut(&bg_task_id) {
                t.processed_documents = processed;
                t.entities_created = total_entities;
                t.relations_created = total_relations;
                t.errors = errors.clone();
            }
        }

        let completed_at = chrono::Utc::now().to_rfc3339();
        let errors_json = serde_json::to_string(&errors).unwrap_or_else(|_| "[]".to_string());

        let mut tasks = generation_tasks().write().await;
        if let Some(t) = tasks.get_mut(&bg_task_id) {
            t.status = "completed".into();
            t.completed_at = Some(completed_at.clone());
        }

        let _ = sqlx::query(
            "UPDATE graph_generation_logs SET \
             status = 'completed', processed_documents = $1, entities_created = $2, \
             relations_created = $3, errors = $4, completed_at = $5 \
             WHERE id = $6"
        )
        .bind(processed as i32)
        .bind(total_entities as i32)
        .bind(total_relations as i32)
        .bind(&errors_json)
        .bind(&completed_at)
        .bind(&bg_task_id)
        .execute(&pool)
        .await;

        tracing::info!(
            task_id = %bg_task_id,
            workspace_id = %ws_id,
            docs = total,
            entities = total_entities,
            relations = total_relations,
            "Background knowledge graph generation completed"
        );
    });

    Ok(Json(AsyncGenerateResponse {
        task_id,
        status: "running".into(),
        total_documents: total,
        message: format!("Generation started for {} documents. Poll the status endpoint for progress.", total),
    }))
}

async fn generation_status(
    State(state): State<AppState>,
    auth: AuthUser,
    Path((ws_id, task_id)): Path<(Uuid, String)>,
) -> Result<Json<GenerationTask>, AppError> {
    check_workspace_access(&state.pool, ws_id, auth.id).await?;

    let tasks = generation_tasks().read().await;
    let task = tasks.get(&task_id)
        .ok_or_else(|| AppError::NotFound("Generation task not found".into()))?;

    if task.workspace_id != ws_id.to_string() {
        return Err(AppError::NotFound("Generation task not found".into()));
    }

    Ok(Json(task.clone()))
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

#[derive(Serialize)]
struct GenerationLogEntry {
    id: String,
    status: String,
    total_documents: i32,
    processed_documents: i32,
    entities_created: i32,
    relations_created: i32,
    errors: Vec<String>,
    started_at: String,
    completed_at: Option<String>,
}

async fn generation_history(
    State(state): State<AppState>,
    auth: AuthUser,
    Path(ws_id): Path<Uuid>,
) -> Result<Json<Vec<GenerationLogEntry>>, AppError> {
    check_workspace_access(&state.pool, ws_id, auth.id).await?;

    let rows = sqlx::query_as::<_, (String, String, i32, i32, i32, i32, String, String, Option<String>)>(
        "SELECT id, status, total_documents, processed_documents, entities_created, \
         relations_created, errors, CAST(started_at AS TEXT), CAST(completed_at AS TEXT) \
         FROM graph_generation_logs WHERE workspace_id = $1 \
         ORDER BY started_at DESC LIMIT 20"
    )
    .bind(ws_id.to_string())
    .fetch_all(&state.pool)
    .await?;

    let entries: Vec<GenerationLogEntry> = rows.into_iter().map(|r| {
        let errors: Vec<String> = serde_json::from_str(&r.6).unwrap_or_default();
        GenerationLogEntry {
            id: r.0,
            status: r.1,
            total_documents: r.2,
            processed_documents: r.3,
            entities_created: r.4,
            relations_created: r.5,
            errors,
            started_at: r.7,
            completed_at: r.8,
        }
    }).collect();

    Ok(Json(entries))
}
