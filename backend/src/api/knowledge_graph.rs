use axum::{
    extract::{Path, Query, State},
    routing::{get, post, delete, put},
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
        .route(
            "/workspaces/{ws_id}/knowledge-graph/entities/new",
            post(create_entity),
        )
        .route(
            "/workspaces/{ws_id}/knowledge-graph/entities/{entity_id}",
            put(update_entity).delete(delete_entity),
        )
        .route(
            "/workspaces/{ws_id}/knowledge-graph/relations/new",
            post(create_relation),
        )
        .route(
            "/workspaces/{ws_id}/knowledge-graph/relations/{relation_id}",
            put(update_relation).delete(delete_relation),
        )
        .route(
            "/workspaces/{ws_id}/knowledge-graph/entities/merge",
            post(merge_entities),
        )
        .route(
            "/workspaces/{ws_id}/knowledge-graph/build-document-layer",
            post(build_document_layer),
        )
        .route(
            "/workspaces/{ws_id}/knowledge-graph/build-semantic-layer",
            post(build_semantic_layer_api),
        )
}

async fn build_document_layer(
    State(state): State<AppState>,
    auth: AuthUser,
    Path(ws_id): Path<Uuid>,
) -> Result<Json<serde_json::Value>, AppError> {
    check_workspace_access(&state.pool, ws_id, auth.id).await?;

    let (entities, relations) = knowledge_extraction::build_document_layer(&state.pool, ws_id).await
        .map_err(AppError::Internal)?;

    Ok(Json(serde_json::json!({
        "success": true,
        "entities_created": entities,
        "relations_created": relations,
        "layer": "document",
    })))
}

async fn build_semantic_layer_api(
    State(state): State<AppState>,
    auth: AuthUser,
    Path(ws_id): Path<Uuid>,
) -> Result<Json<serde_json::Value>, AppError> {
    check_workspace_access(&state.pool, ws_id, auth.id).await?;

    let (entities, relations) = knowledge_extraction::build_semantic_layer(&state.pool, ws_id).await
        .map_err(AppError::Internal)?;

    Ok(Json(serde_json::json!({
        "success": true,
        "entities_created": entities,
        "relations_created": relations,
        "layer": "semantic",
    })))
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
    #[serde(skip_serializing_if = "Option::is_none")]
    graph_layer: Option<String>,
}

#[derive(Serialize)]
struct GraphEdge {
    id: String,
    source: String,
    target: String,
    relation: String,
    weight: f64,
    #[serde(skip_serializing_if = "Option::is_none")]
    description: Option<String>,
    #[serde(skip_serializing_if = "Option::is_none")]
    source_document_id: Option<String>,
    #[serde(skip_serializing_if = "Option::is_none")]
    graph_layer: Option<String>,
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

#[derive(Deserialize)]
struct GraphQuery {
    #[serde(default)]
    layers: Option<String>,
}

async fn get_graph(
    State(state): State<AppState>,
    auth: AuthUser,
    Path(ws_id): Path<Uuid>,
    Query(params): Query<GraphQuery>,
) -> Result<Json<GraphResponse>, AppError> {
    check_workspace_access(&state.pool, ws_id, auth.id).await?;

    let layer_filter: Option<Vec<String>> = params.layers.map(|l| {
        l.split(',').map(|s| s.trim().to_string()).filter(|s| !s.is_empty()).collect()
    });

    tracing::info!(workspace_id = %ws_id, layers = ?layer_filter, "Fetching knowledge graph");

    type EntityTuple = (String, String, String, Option<String>, Option<String>, String, String);
    type RelationTuple = (String, String, String, String, f64, Option<String>, String);

    let entity_rows: Vec<EntityTuple> = if let Some(ref layers) = layer_filter {
        let placeholders: Vec<String> = layers.iter().enumerate()
            .map(|(i, _)| format!("${}", i + 2))
            .collect();
        let sql = format!(
            "SELECT id, name, entity_type, document_id, CAST(metadata AS TEXT), CAST(created_at AS TEXT), graph_layer \
             FROM entities WHERE workspace_id = $1 AND graph_layer IN ({}) ORDER BY name",
            placeholders.join(",")
        );
        let mut query = sqlx::query_as::<_, EntityTuple>(&sql)
            .bind(ws_id.to_string());
        for layer in layers {
            query = query.bind(layer.clone());
        }
        query.fetch_all(&state.pool).await?
    } else {
        sqlx::query_as::<_, EntityTuple>(
            "SELECT id, name, entity_type, document_id, CAST(metadata AS TEXT), CAST(created_at AS TEXT), graph_layer
             FROM entities WHERE workspace_id = $1 ORDER BY name",
        )
        .bind(ws_id.to_string())
        .fetch_all(&state.pool)
        .await?
    };

    let mut entity_layer_map: HashMap<String, String> = HashMap::new();
    let entities: Vec<EntityRow> = entity_rows.into_iter().map(|r| {
        entity_layer_map.insert(r.0.clone(), r.6.clone());
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

    let relation_rows: Vec<RelationTuple> = if let Some(ref layers) = layer_filter {
        let placeholders: Vec<String> = layers.iter().enumerate()
            .map(|(i, _)| format!("${}", i + 2))
            .collect();
        let sql = format!(
            "SELECT id, source_entity_id, target_entity_id, relation_type, weight, CAST(metadata AS TEXT), graph_layer \
             FROM entity_relations WHERE workspace_id = $1 AND graph_layer IN ({})",
            placeholders.join(",")
        );
        let mut query = sqlx::query_as::<_, RelationTuple>(&sql)
            .bind(ws_id.to_string());
        for layer in layers {
            query = query.bind(layer.clone());
        }
        query.fetch_all(&state.pool).await?
    } else {
        sqlx::query_as::<_, RelationTuple>(
            "SELECT id, source_entity_id, target_entity_id, relation_type, weight, CAST(metadata AS TEXT), graph_layer
             FROM entity_relations WHERE workspace_id = $1",
        )
        .bind(ws_id.to_string())
        .fetch_all(&state.pool)
        .await?
    };

    let mut relation_layer_map: HashMap<String, String> = HashMap::new();
    let relations: Vec<RelationRow> = relation_rows.into_iter().map(|r| {
        relation_layer_map.insert(r.0.clone(), r.6.clone());
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
        .map(|e| {
            let layer = entity_layer_map.get(&e.id.to_string()).cloned();
            GraphNode {
                id: e.id.to_string(),
                label: e.name.clone(),
                entity_type: e.entity_type.clone(),
                document_id: e.document_id,
                graph_layer: layer,
            }
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
            let layer = relation_layer_map.get(&r.id.to_string()).cloned();
            GraphEdge {
                id: r.id.to_string(),
                source: r.source_entity_id.to_string(),
                target: r.target_entity_id.to_string(),
                relation: r.relation_type.clone(),
                weight: r.weight,
                description,
                source_document_id,
                graph_layer: layer,
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
    #[serde(skip_serializing_if = "Option::is_none")]
    layer_stats: Option<Vec<LayerStats>>,
}

#[derive(Serialize)]
struct LayerStats {
    layer: String,
    entity_count: i64,
    relation_count: i64,
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

    let entity_layer_rows = sqlx::query_as::<_, (String, i32)>(
        "SELECT graph_layer, COUNT(*) FROM entities WHERE workspace_id = $1 GROUP BY graph_layer"
    )
    .bind(ws_id.to_string())
    .fetch_all(&state.pool)
    .await
    .unwrap_or_default();

    let relation_layer_rows = sqlx::query_as::<_, (String, i32)>(
        "SELECT graph_layer, COUNT(*) FROM entity_relations WHERE workspace_id = $1 GROUP BY graph_layer"
    )
    .bind(ws_id.to_string())
    .fetch_all(&state.pool)
    .await
    .unwrap_or_default();

    let mut layer_map: HashMap<String, (i64, i64)> = HashMap::new();
    for (layer, count) in &entity_layer_rows {
        layer_map.entry(layer.clone()).or_default().0 = *count as i64;
    }
    for (layer, count) in &relation_layer_rows {
        layer_map.entry(layer.clone()).or_default().1 = *count as i64;
    }

    let layer_stats: Vec<LayerStats> = layer_map.into_iter()
        .map(|(layer, (ec, rc))| LayerStats { layer, entity_count: ec, relation_count: rc })
        .collect();

    Ok(Json(GraphStatsResponse {
        entity_count: entity_count as i64,
        relation_count: relation_count as i64,
        entity_types: et_rows.into_iter().map(|(name, count)| TypeCount { name, count: count as i64 }).collect(),
        relation_types: rt_rows.into_iter().map(|(name, count)| TypeCount { name, count: count as i64 }).collect(),
        layer_stats: if layer_stats.is_empty() { None } else { Some(layer_stats) },
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

// ── Entity CRUD ──

#[derive(Deserialize)]
struct CreateEntityRequest {
    name: String,
    entity_type: String,
    #[serde(default)]
    document_id: Option<String>,
    #[serde(default)]
    description: Option<String>,
    #[serde(default = "default_knowledge_layer")]
    graph_layer: String,
}

fn default_knowledge_layer() -> String {
    "knowledge".to_string()
}

#[derive(Deserialize)]
struct UpdateEntityRequest {
    #[serde(default)]
    name: Option<String>,
    #[serde(default)]
    entity_type: Option<String>,
}

async fn create_entity(
    State(state): State<AppState>,
    auth: AuthUser,
    Path(ws_id): Path<Uuid>,
    Json(body): Json<CreateEntityRequest>,
) -> Result<Json<serde_json::Value>, AppError> {
    check_workspace_access(&state.pool, ws_id, auth.id).await?;

    let metadata = serde_json::json!({
        "description": body.description.unwrap_or_default(),
        "created_by": "manual",
    });

    let row: (String,) = sqlx::query_as(
        "INSERT INTO entities (workspace_id, name, entity_type, document_id, graph_layer, metadata) \
         VALUES ($1, $2, $3, $4, $5, $6) RETURNING id"
    )
    .bind(ws_id.to_string())
    .bind(&body.name)
    .bind(&body.entity_type)
    .bind(body.document_id.as_deref())
    .bind(&body.graph_layer)
    .bind(metadata.to_string())
    .fetch_one(&state.pool)
    .await?;

    Ok(Json(serde_json::json!({
        "id": row.0,
        "name": body.name,
        "entity_type": body.entity_type,
    })))
}

async fn update_entity(
    State(state): State<AppState>,
    auth: AuthUser,
    Path((ws_id, entity_id)): Path<(Uuid, String)>,
    Json(body): Json<UpdateEntityRequest>,
) -> Result<Json<serde_json::Value>, AppError> {
    check_workspace_access(&state.pool, ws_id, auth.id).await?;

    let existing: Option<(String,)> = sqlx::query_as(
        "SELECT id FROM entities WHERE id = $1 AND workspace_id = $2"
    )
    .bind(&entity_id)
    .bind(ws_id.to_string())
    .fetch_optional(&state.pool)
    .await?;

    if existing.is_none() {
        return Err(AppError::NotFound("Entity not found".into()));
    }

    if let Some(name) = &body.name {
        sqlx::query("UPDATE entities SET name = $1 WHERE id = $2")
            .bind(name)
            .bind(&entity_id)
            .execute(&state.pool)
            .await?;
    }

    if let Some(entity_type) = &body.entity_type {
        sqlx::query("UPDATE entities SET entity_type = $1 WHERE id = $2")
            .bind(entity_type)
            .bind(&entity_id)
            .execute(&state.pool)
            .await?;
    }

    Ok(Json(serde_json::json!({ "updated": true, "id": entity_id })))
}

async fn delete_entity(
    State(state): State<AppState>,
    auth: AuthUser,
    Path((ws_id, entity_id)): Path<(Uuid, String)>,
) -> Result<Json<serde_json::Value>, AppError> {
    check_workspace_access(&state.pool, ws_id, auth.id).await?;

    let relations_deleted = sqlx::query(
        "DELETE FROM entity_relations WHERE (source_entity_id = $1 OR target_entity_id = $1) AND workspace_id = $2"
    )
    .bind(&entity_id)
    .bind(ws_id.to_string())
    .execute(&state.pool)
    .await?
    .rows_affected();

    let entity_deleted = sqlx::query(
        "DELETE FROM entities WHERE id = $1 AND workspace_id = $2"
    )
    .bind(&entity_id)
    .bind(ws_id.to_string())
    .execute(&state.pool)
    .await?
    .rows_affected();

    if entity_deleted == 0 {
        return Err(AppError::NotFound("Entity not found".into()));
    }

    Ok(Json(serde_json::json!({
        "deleted": true,
        "relations_removed": relations_deleted,
    })))
}

// ── Relation CRUD ──

#[derive(Deserialize)]
struct CreateRelationRequest {
    source_entity_id: String,
    target_entity_id: String,
    relation_type: String,
    #[serde(default = "default_weight")]
    weight: f64,
    #[serde(default)]
    description: Option<String>,
    #[serde(default = "default_knowledge_layer")]
    graph_layer: String,
}

fn default_weight() -> f64 { 1.0 }

#[derive(Deserialize)]
struct UpdateRelationRequest {
    #[serde(default)]
    relation_type: Option<String>,
    #[serde(default)]
    weight: Option<f64>,
    #[serde(default)]
    description: Option<String>,
}

async fn create_relation(
    State(state): State<AppState>,
    auth: AuthUser,
    Path(ws_id): Path<Uuid>,
    Json(body): Json<CreateRelationRequest>,
) -> Result<Json<serde_json::Value>, AppError> {
    check_workspace_access(&state.pool, ws_id, auth.id).await?;

    let src_exists: Option<(String,)> = sqlx::query_as(
        "SELECT id FROM entities WHERE id = $1 AND workspace_id = $2"
    )
    .bind(&body.source_entity_id)
    .bind(ws_id.to_string())
    .fetch_optional(&state.pool)
    .await?;

    let tgt_exists: Option<(String,)> = sqlx::query_as(
        "SELECT id FROM entities WHERE id = $1 AND workspace_id = $2"
    )
    .bind(&body.target_entity_id)
    .bind(ws_id.to_string())
    .fetch_optional(&state.pool)
    .await?;

    if src_exists.is_none() || tgt_exists.is_none() {
        return Err(AppError::BadRequest("Source or target entity not found in this workspace".into()));
    }

    let metadata = serde_json::json!({
        "description": body.description.unwrap_or_default(),
        "created_by": "manual",
    });

    let row: (String,) = sqlx::query_as(
        "INSERT INTO entity_relations (workspace_id, source_entity_id, target_entity_id, relation_type, weight, graph_layer, metadata) \
         VALUES ($1, $2, $3, $4, $5, $6, $7) RETURNING id"
    )
    .bind(ws_id.to_string())
    .bind(&body.source_entity_id)
    .bind(&body.target_entity_id)
    .bind(&body.relation_type)
    .bind(body.weight.clamp(0.0, 1.0))
    .bind(&body.graph_layer)
    .bind(metadata.to_string())
    .fetch_one(&state.pool)
    .await?;

    Ok(Json(serde_json::json!({
        "id": row.0,
        "relation_type": body.relation_type,
    })))
}

async fn update_relation(
    State(state): State<AppState>,
    auth: AuthUser,
    Path((ws_id, relation_id)): Path<(Uuid, String)>,
    Json(body): Json<UpdateRelationRequest>,
) -> Result<Json<serde_json::Value>, AppError> {
    check_workspace_access(&state.pool, ws_id, auth.id).await?;

    let existing: Option<(String,)> = sqlx::query_as(
        "SELECT id FROM entity_relations WHERE id = $1 AND workspace_id = $2"
    )
    .bind(&relation_id)
    .bind(ws_id.to_string())
    .fetch_optional(&state.pool)
    .await?;

    if existing.is_none() {
        return Err(AppError::NotFound("Relation not found".into()));
    }

    if let Some(relation_type) = &body.relation_type {
        sqlx::query("UPDATE entity_relations SET relation_type = $1 WHERE id = $2")
            .bind(relation_type)
            .bind(&relation_id)
            .execute(&state.pool)
            .await?;
    }

    if let Some(weight) = body.weight {
        sqlx::query("UPDATE entity_relations SET weight = $1 WHERE id = $2")
            .bind(weight.clamp(0.0, 1.0))
            .bind(&relation_id)
            .execute(&state.pool)
            .await?;
    }

    if let Some(description) = &body.description {
        let current_meta: Option<(String,)> = sqlx::query_as(
            "SELECT CAST(metadata AS TEXT) FROM entity_relations WHERE id = $1"
        )
        .bind(&relation_id)
        .fetch_optional(&state.pool)
        .await?;

        let mut meta: serde_json::Value = current_meta
            .and_then(|m| serde_json::from_str(&m.0).ok())
            .unwrap_or(serde_json::json!({}));

        if let Some(obj) = meta.as_object_mut() {
            obj.insert("description".to_string(), serde_json::json!(description));
        }

        sqlx::query("UPDATE entity_relations SET metadata = $1 WHERE id = $2")
            .bind(meta.to_string())
            .bind(&relation_id)
            .execute(&state.pool)
            .await?;
    }

    Ok(Json(serde_json::json!({ "updated": true, "id": relation_id })))
}

async fn delete_relation(
    State(state): State<AppState>,
    auth: AuthUser,
    Path((ws_id, relation_id)): Path<(Uuid, String)>,
) -> Result<Json<serde_json::Value>, AppError> {
    check_workspace_access(&state.pool, ws_id, auth.id).await?;

    let deleted = sqlx::query(
        "DELETE FROM entity_relations WHERE id = $1 AND workspace_id = $2"
    )
    .bind(&relation_id)
    .bind(ws_id.to_string())
    .execute(&state.pool)
    .await?
    .rows_affected();

    if deleted == 0 {
        return Err(AppError::NotFound("Relation not found".into()));
    }

    Ok(Json(serde_json::json!({ "deleted": true })))
}

// ── Entity Merge ──

#[derive(Deserialize)]
struct MergeEntitiesRequest {
    keep_entity_id: String,
    merge_entity_ids: Vec<String>,
}

async fn merge_entities(
    State(state): State<AppState>,
    auth: AuthUser,
    Path(ws_id): Path<Uuid>,
    Json(body): Json<MergeEntitiesRequest>,
) -> Result<Json<serde_json::Value>, AppError> {
    check_workspace_access(&state.pool, ws_id, auth.id).await?;

    let keep_exists: Option<(String,)> = sqlx::query_as(
        "SELECT id FROM entities WHERE id = $1 AND workspace_id = $2"
    )
    .bind(&body.keep_entity_id)
    .bind(ws_id.to_string())
    .fetch_optional(&state.pool)
    .await?;

    if keep_exists.is_none() {
        return Err(AppError::BadRequest("Keep entity not found".into()));
    }

    let mut relations_transferred: u64 = 0;
    let mut entities_merged: u64 = 0;

    for merge_id in &body.merge_entity_ids {
        if merge_id == &body.keep_entity_id {
            continue;
        }

        let transferred = sqlx::query(
            "UPDATE entity_relations SET source_entity_id = $1 WHERE source_entity_id = $2 AND workspace_id = $3"
        )
        .bind(&body.keep_entity_id)
        .bind(merge_id)
        .bind(ws_id.to_string())
        .execute(&state.pool)
        .await?
        .rows_affected();
        relations_transferred += transferred;

        let transferred2 = sqlx::query(
            "UPDATE entity_relations SET target_entity_id = $1 WHERE target_entity_id = $2 AND workspace_id = $3"
        )
        .bind(&body.keep_entity_id)
        .bind(merge_id)
        .bind(ws_id.to_string())
        .execute(&state.pool)
        .await?
        .rows_affected();
        relations_transferred += transferred2;

        // Remove self-referencing relations after merge
        sqlx::query(
            "DELETE FROM entity_relations WHERE source_entity_id = $1 AND target_entity_id = $1"
        )
        .bind(&body.keep_entity_id)
        .execute(&state.pool)
        .await?;

        let deleted = sqlx::query(
            "DELETE FROM entities WHERE id = $1 AND workspace_id = $2"
        )
        .bind(merge_id)
        .bind(ws_id.to_string())
        .execute(&state.pool)
        .await?
        .rows_affected();
        entities_merged += deleted;
    }

    Ok(Json(serde_json::json!({
        "merged": true,
        "keep_entity_id": body.keep_entity_id,
        "entities_merged": entities_merged,
        "relations_transferred": relations_transferred,
    })))
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn graph_node_serialization() {
        let doc_id = Uuid::new_v4();
        let node = GraphNode {
            id: "n1".into(),
            label: "Test Entity".into(),
            entity_type: "person".into(),
            document_id: Some(doc_id),
            graph_layer: Some("knowledge".into()),
        };
        let json = serde_json::to_value(&node).unwrap();
        assert_eq!(json["id"], "n1");
        assert_eq!(json["label"], "Test Entity");
        assert_eq!(json["entity_type"], "person");
        assert_eq!(json["document_id"], doc_id.to_string());
        assert_eq!(json["graph_layer"], "knowledge");
    }

    #[test]
    fn graph_node_without_optional_fields() {
        let node = GraphNode {
            id: "n2".into(),
            label: "No Doc".into(),
            entity_type: "concept".into(),
            document_id: None,
            graph_layer: None,
        };
        let json = serde_json::to_value(&node).unwrap();
        assert!(json.get("graph_layer").is_none());
    }

    #[test]
    fn graph_edge_serialization_with_all_fields() {
        let edge = GraphEdge {
            id: "rel-001".into(),
            source: "n1".into(),
            target: "n2".into(),
            relation: "works_at".into(),
            weight: 0.85,
            description: Some("Employment".into()),
            source_document_id: Some("doc-xyz".into()),
            graph_layer: Some("knowledge".into()),
        };
        let json = serde_json::to_value(&edge).unwrap();
        assert_eq!(json["id"], "rel-001");
        assert_eq!(json["source"], "n1");
        assert_eq!(json["target"], "n2");
        assert_eq!(json["relation"], "works_at");
        assert!((json["weight"].as_f64().unwrap() - 0.85).abs() < 0.001);
        assert_eq!(json["description"], "Employment");
        assert_eq!(json["source_document_id"], "doc-xyz");
    }

    #[test]
    fn graph_edge_without_optional_fields() {
        let edge = GraphEdge {
            id: "rel-002".into(),
            source: "a".into(),
            target: "b".into(),
            relation: "related".into(),
            weight: 1.0,
            description: None,
            source_document_id: None,
            graph_layer: None,
        };
        let json = serde_json::to_value(&edge).unwrap();
        assert!(json.get("description").is_none());
        assert!(json.get("source_document_id").is_none());
    }

    #[test]
    fn create_entity_request_deserialization() {
        let json_str = r#"{"name":"TestEntity","entity_type":"person"}"#;
        let req: CreateEntityRequest = serde_json::from_str(json_str).unwrap();
        assert_eq!(req.name, "TestEntity");
        assert_eq!(req.entity_type, "person");
        assert!(req.document_id.is_none());
        assert!(req.description.is_none());
    }

    #[test]
    fn create_entity_request_with_optional_fields() {
        let json_str = r#"{"name":"Test","entity_type":"concept","document_id":"doc-1","description":"A concept"}"#;
        let req: CreateEntityRequest = serde_json::from_str(json_str).unwrap();
        assert_eq!(req.document_id.unwrap(), "doc-1");
        assert_eq!(req.description.unwrap(), "A concept");
    }

    #[test]
    fn update_entity_request_partial_update() {
        let json_str = r#"{"name":"NewName"}"#;
        let req: UpdateEntityRequest = serde_json::from_str(json_str).unwrap();
        assert_eq!(req.name.unwrap(), "NewName");
        assert!(req.entity_type.is_none());
    }

    #[test]
    fn create_relation_request_deserialization() {
        let json_str = r#"{"source_entity_id":"e1","target_entity_id":"e2","relation_type":"mentions","weight":0.75}"#;
        let req: CreateRelationRequest = serde_json::from_str(json_str).unwrap();
        assert_eq!(req.source_entity_id, "e1");
        assert_eq!(req.target_entity_id, "e2");
        assert_eq!(req.relation_type, "mentions");
        assert!((req.weight - 0.75).abs() < 0.001);
        assert!(req.description.is_none());
    }

    #[test]
    fn update_relation_request_deserialization() {
        let json_str = r#"{"relation_type":"related_to","weight":0.9,"description":"Updated desc"}"#;
        let req: UpdateRelationRequest = serde_json::from_str(json_str).unwrap();
        assert_eq!(req.relation_type.unwrap(), "related_to");
        assert!((req.weight.unwrap() - 0.9).abs() < 0.001);
        assert_eq!(req.description.unwrap(), "Updated desc");
    }

    #[test]
    fn merge_entities_request_deserialization() {
        let json_str = r#"{"keep_entity_id":"e1","merge_entity_ids":["e2","e3"]}"#;
        let req: MergeEntitiesRequest = serde_json::from_str(json_str).unwrap();
        assert_eq!(req.keep_entity_id, "e1");
        assert_eq!(req.merge_entity_ids, vec!["e2", "e3"]);
    }

    #[test]
    fn graph_response_structure() {
        let data = GraphResponse {
            nodes: vec![
                GraphNode { id: "n1".into(), label: "A".into(), entity_type: "person".into(), document_id: None, graph_layer: Some("knowledge".into()) },
                GraphNode { id: "n2".into(), label: "B".into(), entity_type: "concept".into(), document_id: None, graph_layer: Some("document".into()) },
            ],
            edges: vec![
                GraphEdge { id: "r1".into(), source: "n1".into(), target: "n2".into(), relation: "related".into(), weight: 0.5, description: None, source_document_id: None, graph_layer: Some("semantic".into()) },
            ],
        };
        let json = serde_json::to_value(&data).unwrap();
        assert_eq!(json["nodes"].as_array().unwrap().len(), 2);
        assert_eq!(json["edges"].as_array().unwrap().len(), 1);
    }
}
