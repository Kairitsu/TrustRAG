use axum::{
    extract::{Path, State},
    http::StatusCode,
    routing::{get, post, put, delete},
    Json, Router,
};
use serde::{Deserialize, Serialize};
use uuid::Uuid;

use crate::auth::middleware::AuthUser;
use crate::error::AppError;
use crate::services::reranker::RerankerProvider;

use super::AppState;

pub fn router() -> Router<AppState> {
    Router::new()
        .route("/rerank-configs", get(list_configs).post(create_config))
        .route(
            "/rerank-configs/{id}",
            put(update_config).delete(delete_config),
        )
        .route("/rerank-configs/{id}/test", post(test_connection))
        .route("/rerank-configs/{id}/default", put(set_default))
}

#[derive(Deserialize)]
pub struct CreateRerankConfigRequest {
    pub name: String,
    pub provider: String,
    pub api_base_url: String,
    #[serde(default)]
    pub api_key: Option<String>,
    pub model_name: String,
    #[serde(default = "default_top_n")]
    pub top_n: i32,
    #[serde(default = "default_initial_recall_k")]
    pub initial_recall_k: i32,
    #[serde(default = "default_fallback_enabled")]
    pub fallback_enabled: bool,
    #[serde(default = "default_timeout_secs")]
    pub timeout_secs: i32,
    #[serde(default)]
    pub is_default: bool,
    #[serde(default)]
    pub workspace_id: Option<Uuid>,
}

fn default_top_n() -> i32 { 5 }
fn default_initial_recall_k() -> i32 { 30 }
fn default_fallback_enabled() -> bool { true }
fn default_timeout_secs() -> i32 { 30 }

#[derive(Deserialize)]
pub struct UpdateRerankConfigRequest {
    pub name: Option<String>,
    pub provider: Option<String>,
    pub api_base_url: Option<String>,
    pub api_key: Option<String>,
    pub model_name: Option<String>,
    pub top_n: Option<i32>,
    pub initial_recall_k: Option<i32>,
    pub fallback_enabled: Option<bool>,
    pub timeout_secs: Option<i32>,
    pub is_default: Option<bool>,
}

#[derive(Serialize)]
pub struct RerankConfigResponse {
    pub id: String,
    pub workspace_id: Option<String>,
    pub user_id: String,
    pub name: String,
    pub provider: String,
    pub api_base_url: String,
    pub has_api_key: bool,
    pub model_name: String,
    pub top_n: i32,
    pub initial_recall_k: i32,
    pub fallback_enabled: bool,
    pub timeout_secs: i32,
    pub is_default: bool,
    pub created_at: String,
    pub updated_at: String,
}

const RERANK_SELECT: &str = "id, workspace_id, user_id, name, provider, api_base_url, api_key_enc, model_name, top_n, initial_recall_k, fallback_enabled, timeout_secs, is_default, CAST(created_at AS TEXT), CAST(updated_at AS TEXT)";

type RerankRow = (String, Option<String>, String, String, String, String, Option<String>, String, i32, i32, bool, i32, bool, String, String);

fn row_to_response(r: RerankRow) -> RerankConfigResponse {
    RerankConfigResponse {
        id: r.0,
        workspace_id: r.1,
        user_id: r.2,
        name: r.3,
        provider: r.4,
        api_base_url: r.5,
        has_api_key: r.6.is_some(),
        model_name: r.7,
        top_n: r.8,
        initial_recall_k: r.9,
        fallback_enabled: r.10,
        timeout_secs: r.11,
        is_default: r.12,
        created_at: r.13,
        updated_at: r.14,
    }
}

async fn list_configs(
    State(state): State<AppState>,
    auth: AuthUser,
) -> Result<Json<Vec<RerankConfigResponse>>, AppError> {
    let sql = format!(
        "SELECT {} FROM rerank_configs WHERE user_id = $1 ORDER BY created_at DESC",
        RERANK_SELECT
    );
    let rows = sqlx::query_as::<_, RerankRow>(&sql)
        .bind(auth.id.to_string())
        .fetch_all(&state.pool)
        .await?;

    Ok(Json(rows.into_iter().map(row_to_response).collect()))
}

async fn create_config(
    State(state): State<AppState>,
    auth: AuthUser,
    Json(req): Json<CreateRerankConfigRequest>,
) -> Result<(StatusCode, Json<RerankConfigResponse>), AppError> {
    let id = Uuid::new_v4();

    if req.is_default {
        sqlx::query("UPDATE rerank_configs SET is_default = false WHERE user_id = $1")
            .bind(auth.id.to_string())
            .execute(&state.pool)
            .await?;
    }

    let ws_id = req.workspace_id.map(|w| w.to_string());

    sqlx::query(
        "INSERT INTO rerank_configs (id, workspace_id, user_id, name, provider, api_base_url, api_key_enc, model_name, top_n, initial_recall_k, fallback_enabled, timeout_secs, is_default)
         VALUES ($1, $2, $3, $4, $5, $6, $7, $8, $9, $10, $11, $12, $13)",
    )
    .bind(id.to_string())
    .bind(&ws_id)
    .bind(auth.id.to_string())
    .bind(&req.name)
    .bind(&req.provider)
    .bind(&req.api_base_url)
    .bind(&req.api_key)
    .bind(&req.model_name)
    .bind(req.top_n)
    .bind(req.initial_recall_k)
    .bind(req.fallback_enabled as i32)
    .bind(req.timeout_secs)
    .bind(req.is_default as i32)
    .execute(&state.pool)
    .await?;

    let sql = format!("SELECT {} FROM rerank_configs WHERE id = $1", RERANK_SELECT);
    let row = sqlx::query_as::<_, RerankRow>(&sql)
        .bind(id.to_string())
        .fetch_one(&state.pool)
        .await?;

    Ok((StatusCode::CREATED, Json(row_to_response(row))))
}

async fn update_config(
    State(state): State<AppState>,
    auth: AuthUser,
    Path(id): Path<Uuid>,
    Json(req): Json<UpdateRerankConfigRequest>,
) -> Result<Json<RerankConfigResponse>, AppError> {
    let existing = sqlx::query_as::<_, (String,)>(
        "SELECT user_id FROM rerank_configs WHERE id = $1",
    )
    .bind(id.to_string())
    .fetch_optional(&state.pool)
    .await?;

    match existing {
        None => return Err(AppError::NotFound("Rerank config not found".into())),
        Some((uid,)) if uid != auth.id.to_string() => {
            return Err(AppError::Forbidden("Not your config".into()));
        }
        _ => {}
    }

    if req.is_default == Some(true) {
        sqlx::query("UPDATE rerank_configs SET is_default = false WHERE user_id = $1")
            .bind(auth.id.to_string())
            .execute(&state.pool)
            .await?;
    }

    let mut set_clauses = Vec::new();

    if req.name.is_some() { set_clauses.push("name"); }
    if req.provider.is_some() { set_clauses.push("provider"); }
    if req.api_base_url.is_some() { set_clauses.push("api_base_url"); }
    if req.api_key.is_some() { set_clauses.push("api_key_enc"); }
    if req.model_name.is_some() { set_clauses.push("model_name"); }
    if req.top_n.is_some() { set_clauses.push("top_n"); }
    if req.initial_recall_k.is_some() { set_clauses.push("initial_recall_k"); }
    if req.fallback_enabled.is_some() { set_clauses.push("fallback_enabled"); }
    if req.timeout_secs.is_some() { set_clauses.push("timeout_secs"); }
    if req.is_default.is_some() { set_clauses.push("is_default"); }

    if set_clauses.is_empty() {
        return Err(AppError::BadRequest("No fields to update".into()));
    }

    let mut sets: Vec<String> = set_clauses.iter().enumerate()
        .map(|(i, col)| format!("{} = ${}", col, i + 1))
        .collect();

    sets.push("updated_at = strftime('%Y-%m-%dT%H:%M:%fZ', 'now')".to_string());

    let param_idx = set_clauses.len() + 1;
    let sql = format!(
        "UPDATE rerank_configs SET {} WHERE id = ${}",
        sets.join(", "),
        param_idx,
    );

    let mut query = sqlx::query(&sql);

    for col in &set_clauses {
        match *col {
            "name" => { query = query.bind(req.name.as_deref().unwrap_or_default()); }
            "provider" => { query = query.bind(req.provider.as_deref().unwrap_or_default()); }
            "api_base_url" => { query = query.bind(req.api_base_url.as_deref().unwrap_or_default()); }
            "api_key_enc" => { query = query.bind(req.api_key.as_deref().unwrap_or_default()); }
            "model_name" => { query = query.bind(req.model_name.as_deref().unwrap_or_default()); }
            "top_n" => { query = query.bind(req.top_n.unwrap_or(5)); }
            "initial_recall_k" => { query = query.bind(req.initial_recall_k.unwrap_or(30)); }
            "fallback_enabled" => { query = query.bind(req.fallback_enabled.unwrap_or(true) as i32); }
            "timeout_secs" => { query = query.bind(req.timeout_secs.unwrap_or(30)); }
            "is_default" => { query = query.bind(req.is_default.unwrap_or(false) as i32); }
            _ => {}
        }
    }

    query = query.bind(id.to_string());
    query.execute(&state.pool).await?;

    let select_sql = format!("SELECT {} FROM rerank_configs WHERE id = $1", RERANK_SELECT);
    let row = sqlx::query_as::<_, RerankRow>(&select_sql)
        .bind(id.to_string())
        .fetch_one(&state.pool)
        .await?;

    Ok(Json(row_to_response(row)))
}

async fn delete_config(
    State(state): State<AppState>,
    auth: AuthUser,
    Path(id): Path<Uuid>,
) -> Result<StatusCode, AppError> {
    let result = sqlx::query("DELETE FROM rerank_configs WHERE id = $1 AND user_id = $2")
        .bind(id.to_string())
        .bind(auth.id.to_string())
        .execute(&state.pool)
        .await?;

    if result.rows_affected() == 0 {
        return Err(AppError::NotFound("Rerank config not found".into()));
    }
    Ok(StatusCode::NO_CONTENT)
}

async fn test_connection(
    State(_state): State<AppState>,
    auth: AuthUser,
    Path(id): Path<Uuid>,
) -> Result<Json<serde_json::Value>, AppError> {
    let row = sqlx::query_as::<_, (String, String, Option<String>, String, i32)>(
        "SELECT provider, api_base_url, api_key_enc, model_name, timeout_secs FROM rerank_configs WHERE id = $1 AND user_id = $2",
    )
    .bind(id.to_string())
    .bind(auth.id.to_string())
    .fetch_optional(&_state.pool)
    .await?;

    let (provider, api_base_url, api_key, model_name, timeout_secs) = match row {
        Some(r) => r,
        None => return Err(AppError::NotFound("Rerank config not found".into())),
    };

    let reranker = crate::services::reranker::HttpRerankerProvider::with_timeout(
        format!("{}/rerank", api_base_url.trim_end_matches('/')),
        api_key.unwrap_or_default(),
        model_name.clone(),
        provider.clone(),
        timeout_secs as u64,
    );

    let test_docs = &["The capital of France is Paris.", "Machine learning is a subset of AI."];
    match reranker.score("What is the capital of France?", test_docs).await {
        Ok(scores) => Ok(Json(serde_json::json!({
            "success": true,
            "provider": provider,
            "model": model_name,
            "scores": scores,
            "message": "连接成功"
        }))),
        Err(e) => Ok(Json(serde_json::json!({
            "success": false,
            "provider": provider,
            "model": model_name,
            "error": e.to_string(),
            "message": format!("连接失败: {}", e)
        }))),
    }
}

async fn set_default(
    State(state): State<AppState>,
    auth: AuthUser,
    Path(id): Path<Uuid>,
) -> Result<Json<serde_json::Value>, AppError> {
    let exists = sqlx::query_as::<_, (String,)>(
        "SELECT user_id FROM rerank_configs WHERE id = $1 AND user_id = $2",
    )
    .bind(id.to_string())
    .bind(auth.id.to_string())
    .fetch_optional(&state.pool)
    .await?;

    if exists.is_none() {
        return Err(AppError::NotFound("Rerank config not found".into()));
    }

    sqlx::query("UPDATE rerank_configs SET is_default = false WHERE user_id = $1")
        .bind(auth.id.to_string())
        .execute(&state.pool)
        .await?;

    sqlx::query("UPDATE rerank_configs SET is_default = true WHERE id = $1")
        .bind(id.to_string())
        .execute(&state.pool)
        .await?;

    Ok(Json(serde_json::json!({
        "success": true,
        "message": "已设为默认重排模型"
    })))
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn create_request_deserialization() {
        let json_str = r#"{
            "name": "Test Reranker",
            "provider": "jina",
            "api_base_url": "https://api.jina.ai/v1",
            "model_name": "jina-reranker-v2-base-multilingual",
            "api_key": "test-key"
        }"#;
        let req: CreateRerankConfigRequest = serde_json::from_str(json_str).unwrap();
        assert_eq!(req.name, "Test Reranker");
        assert_eq!(req.provider, "jina");
        assert_eq!(req.top_n, 5);
        assert_eq!(req.initial_recall_k, 30);
        assert!(req.fallback_enabled);
        assert_eq!(req.timeout_secs, 30);
        assert!(!req.is_default);
    }

    #[test]
    fn create_request_with_all_fields() {
        let json_str = r#"{
            "name": "Full Config",
            "provider": "cohere",
            "api_base_url": "https://api.cohere.ai",
            "model_name": "rerank-v3.5",
            "top_n": 10,
            "initial_recall_k": 50,
            "fallback_enabled": false,
            "timeout_secs": 60,
            "is_default": true
        }"#;
        let req: CreateRerankConfigRequest = serde_json::from_str(json_str).unwrap();
        assert_eq!(req.top_n, 10);
        assert_eq!(req.initial_recall_k, 50);
        assert!(!req.fallback_enabled);
        assert_eq!(req.timeout_secs, 60);
        assert!(req.is_default);
    }

    #[test]
    fn update_request_partial() {
        let json_str = r#"{"name": "Updated Name"}"#;
        let req: UpdateRerankConfigRequest = serde_json::from_str(json_str).unwrap();
        assert_eq!(req.name, Some("Updated Name".to_string()));
        assert!(req.provider.is_none());
        assert!(req.top_n.is_none());
        assert!(req.fallback_enabled.is_none());
        assert!(req.is_default.is_none());
    }

    #[test]
    fn update_request_with_bool_fields() {
        let json_str = r#"{
            "fallback_enabled": false,
            "is_default": true,
            "top_n": 8,
            "timeout_secs": 45
        }"#;
        let req: UpdateRerankConfigRequest = serde_json::from_str(json_str).unwrap();
        assert_eq!(req.fallback_enabled, Some(false));
        assert_eq!(req.is_default, Some(true));
        assert_eq!(req.top_n, Some(8));
        assert_eq!(req.timeout_secs, Some(45));
    }

    #[test]
    fn response_serialization() {
        let resp = RerankConfigResponse {
            id: "test-id".into(),
            workspace_id: None,
            user_id: "user-1".into(),
            name: "Test".into(),
            provider: "jina".into(),
            api_base_url: "https://api.jina.ai".into(),
            has_api_key: true,
            model_name: "reranker-v2".into(),
            top_n: 5,
            initial_recall_k: 30,
            fallback_enabled: true,
            timeout_secs: 30,
            is_default: false,
            created_at: "2026-01-01T00:00:00Z".into(),
            updated_at: "2026-01-01T00:00:00Z".into(),
        };
        let json = serde_json::to_value(&resp).unwrap();
        assert_eq!(json["id"], "test-id");
        assert_eq!(json["has_api_key"], true);
        assert_eq!(json["fallback_enabled"], true);
        assert_eq!(json["top_n"], 5);
    }

    #[test]
    fn row_to_response_conversion() {
        let row: RerankRow = (
            "id-1".into(),
            Some("ws-1".into()),
            "user-1".into(),
            "Test Config".into(),
            "jina".into(),
            "https://api.jina.ai".into(),
            Some("encrypted-key".into()),
            "reranker-v2".into(),
            5,
            30,
            true,
            30,
            false,
            "2026-01-01T00:00:00Z".into(),
            "2026-01-01T00:00:00Z".into(),
        );
        let resp = row_to_response(row);
        assert_eq!(resp.id, "id-1");
        assert_eq!(resp.workspace_id, Some("ws-1".into()));
        assert!(resp.has_api_key);
        assert_eq!(resp.top_n, 5);
        assert!(resp.fallback_enabled);
    }

    #[test]
    fn row_to_response_no_api_key() {
        let row: RerankRow = (
            "id-2".into(),
            None,
            "user-1".into(),
            "No Key".into(),
            "custom".into(),
            "http://localhost:8080".into(),
            None,
            "model-x".into(),
            3,
            20,
            false,
            15,
            true,
            "2026-01-01T00:00:00Z".into(),
            "2026-01-01T00:00:00Z".into(),
        );
        let resp = row_to_response(row);
        assert!(!resp.has_api_key);
        assert_eq!(resp.workspace_id, None);
        assert!(!resp.fallback_enabled);
        assert!(resp.is_default);
    }
}
