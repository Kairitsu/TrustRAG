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
    .bind(req.fallback_enabled)
    .bind(req.timeout_secs)
    .bind(req.is_default)
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

    let mut sets = Vec::new();
    let mut binds: Vec<String> = Vec::new();
    let mut idx = 1;

    macro_rules! maybe_set {
        ($field:ident, $col:expr) => {
            if let Some(ref val) = req.$field {
                sets.push(format!("{} = ${}", $col, idx));
                binds.push(val.to_string());
                idx += 1;
            }
        };
    }

    maybe_set!(name, "name");
    maybe_set!(provider, "provider");
    maybe_set!(api_base_url, "api_base_url");
    maybe_set!(api_key, "api_key_enc");
    maybe_set!(model_name, "model_name");

    if let Some(top_n) = req.top_n {
        sets.push(format!("top_n = ${}", idx));
        binds.push(top_n.to_string());
        idx += 1;
    }

    if let Some(initial_recall_k) = req.initial_recall_k {
        sets.push(format!("initial_recall_k = ${}", idx));
        binds.push(initial_recall_k.to_string());
        idx += 1;
    }

    if let Some(fallback_enabled) = req.fallback_enabled {
        sets.push(format!("fallback_enabled = ${}", idx));
        binds.push(fallback_enabled.to_string());
        idx += 1;
    }

    if let Some(timeout_secs) = req.timeout_secs {
        sets.push(format!("timeout_secs = ${}", idx));
        binds.push(timeout_secs.to_string());
        idx += 1;
    }

    if let Some(is_default) = req.is_default {
        sets.push(format!("is_default = ${}", idx));
        binds.push(is_default.to_string());
        idx += 1;
    }

    if sets.is_empty() {
        return Err(AppError::BadRequest("No fields to update".into()));
    }

    #[cfg(sqlite_mode)]
    sets.push(format!("updated_at = strftime('%Y-%m-%dT%H:%M:%fZ', 'now')"));
    #[cfg(feature = "postgres")]
    sets.push("updated_at = now()".to_string());

    let sql = format!(
        "UPDATE rerank_configs SET {} WHERE id = ${}",
        sets.join(", "),
        idx,
    );

    let mut query = sqlx::query(&sql);
    for b in &binds {
        query = query.bind(b);
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
