use axum::{
    extract::{Path, State},
    http::StatusCode,
    routing::{get, post},
    Json, Router,
};
use serde::{Deserialize, Serialize};
use std::sync::Arc;
use uuid::Uuid;

use crate::auth::middleware::AuthUser;
use crate::db::compat;
use crate::error::AppError;
use crate::services::embedding::{OpenAIEmbeddingProvider, OllamaEmbeddingProvider};
use crate::traits::embedding_provider::EmbeddingProvider;

use super::AppState;
use super::models::{decrypt_api_key, encrypt_api_key};

pub fn router() -> Router<AppState> {
    Router::new()
        .route("/embedding-configs", get(list_configs).post(create_config))
        .route(
            "/embedding-configs/{id}",
            axum::routing::put(update_config).delete(delete_config),
        )
        .route("/embedding-configs/{id}/test", post(test_connection))
}

#[derive(Deserialize)]
pub struct CreateEmbeddingConfigRequest {
    pub name: String,
    pub provider: String,
    pub api_base_url: String,
    #[serde(default)]
    pub api_key: Option<String>,
    pub model_name: String,
    #[serde(default = "default_dimensions")]
    pub dimensions: i32,
    #[serde(default = "default_batch_size")]
    pub batch_size: i32,
    #[serde(default)]
    pub is_default: bool,
    #[serde(default)]
    pub workspace_id: Option<Uuid>,
}

fn default_dimensions() -> i32 {
    1536
}

fn default_batch_size() -> i32 {
    10
}

#[derive(Deserialize)]
pub struct UpdateEmbeddingConfigRequest {
    pub name: Option<String>,
    pub provider: Option<String>,
    pub api_base_url: Option<String>,
    pub api_key: Option<String>,
    pub model_name: Option<String>,
    pub dimensions: Option<i32>,
    pub batch_size: Option<i32>,
    pub is_default: Option<bool>,
}

#[derive(Serialize)]
pub struct EmbeddingConfigResponse {
    pub id: Uuid,
    pub workspace_id: Option<Uuid>,
    pub user_id: Uuid,
    pub name: String,
    pub provider: String,
    pub api_base_url: Option<String>,
    pub has_api_key: bool,
    pub model_name: String,
    pub dimensions: i32,
    pub batch_size: i32,
    pub is_default: Option<bool>,
    pub created_at: String,
    pub updated_at: String,
}

#[derive(Serialize)]
pub struct TestEmbeddingResponse {
    pub success: bool,
    pub message: String,
    pub latency_ms: Option<u64>,
}

type EmbRow = (String, Option<String>, String, String, String, Option<String>, Option<String>, String, i32, i32, Option<bool>, String, String);

const EMB_SELECT: &str = "id, workspace_id, user_id, name, provider, api_base_url, api_key_enc, model_name, dimensions, batch_size, is_default, CAST(created_at AS TEXT), CAST(updated_at AS TEXT)";

fn parse_emb_row(r: EmbRow) -> Result<EmbeddingConfigResponse, AppError> {
    Ok(EmbeddingConfigResponse {
        id: compat::parse_uuid(&r.0).map_err(|e| AppError::Internal(e.into()))?,
        workspace_id: r.1.as_deref().and_then(|s| compat::parse_uuid(s).ok()),
        user_id: compat::parse_uuid(&r.2).map_err(|e| AppError::Internal(e.into()))?,
        name: r.3,
        provider: r.4,
        api_base_url: r.5,
        has_api_key: r.6.is_some(),
        model_name: r.7,
        dimensions: r.8,
        batch_size: r.9,
        is_default: r.10,
        created_at: r.11,
        updated_at: r.12,
    })
}

async fn list_configs(
    State(state): State<AppState>,
    auth: AuthUser,
) -> Result<Json<Vec<EmbeddingConfigResponse>>, AppError> {
    let q = format!(
        "SELECT {} FROM embedding_configs WHERE user_id = $1 ORDER BY is_default DESC NULLS LAST, created_at DESC",
        EMB_SELECT
    );
    let rows = sqlx::query_as::<_, EmbRow>(&q)
        .bind(auth.id.to_string())
        .fetch_all(&state.pool)
        .await?;

    let configs: Result<Vec<_>, _> = rows.into_iter().map(parse_emb_row).collect();
    Ok(Json(configs?))
}

async fn create_config(
    State(state): State<AppState>,
    auth: AuthUser,
    Json(req): Json<CreateEmbeddingConfigRequest>,
) -> Result<(StatusCode, Json<EmbeddingConfigResponse>), AppError> {
    let name = req.name.trim().to_string();
    if name.is_empty() {
        return Err(AppError::BadRequest("Config name is required".into()));
    }

    let model_name = req.model_name.trim().to_string();
    if model_name.is_empty() {
        return Err(AppError::BadRequest("Model name is required".into()));
    }

    let api_base_url = req.api_base_url.trim().to_string();

    let valid_providers = ["openai", "ollama", "local", "custom"];
    if !valid_providers.contains(&req.provider.as_str()) {
        return Err(AppError::BadRequest(format!(
            "Invalid provider '{}'. Must be one of: {}",
            req.provider,
            valid_providers.join(", ")
        )));
    }

    let api_key_enc = req
        .api_key
        .as_deref()
        .map(|k| encrypt_api_key(k, &state.jwt_secret));

    if req.is_default {
        sqlx::query("UPDATE embedding_configs SET is_default = 0 WHERE user_id = $1")
            .bind(auth.id.to_string())
            .execute(&state.pool)
            .await?;
    }

    let batch_size = req.batch_size.clamp(1, 2048);

    let q = format!(
        "INSERT INTO embedding_configs (workspace_id, user_id, name, provider, api_base_url, api_key_enc, model_name, dimensions, batch_size, is_default) VALUES ($1, $2, $3, $4, $5, $6, $7, $8, $9, $10) RETURNING {}",
        EMB_SELECT
    );
    let row = sqlx::query_as::<_, EmbRow>(&q)
        .bind(req.workspace_id.map(|u| u.to_string()))
        .bind(auth.id.to_string())
        .bind(&name)
        .bind(&req.provider)
        .bind(&api_base_url)
        .bind(&api_key_enc)
        .bind(&model_name)
        .bind(req.dimensions)
        .bind(batch_size)
        .bind(req.is_default)
        .fetch_one(&state.pool)
        .await?;

    let resp = parse_emb_row(row)?;

    if req.is_default {
        reload_embedding_provider(&state).await;
    }

    Ok((StatusCode::CREATED, Json(resp)))
}

async fn update_config(
    State(state): State<AppState>,
    auth: AuthUser,
    Path(config_id): Path<Uuid>,
    Json(req): Json<UpdateEmbeddingConfigRequest>,
) -> Result<Json<EmbeddingConfigResponse>, AppError> {
    let existing = sqlx::query_scalar::<_, String>(
        "SELECT id FROM embedding_configs WHERE id = $1 AND user_id = $2",
    )
    .bind(config_id.to_string())
    .bind(auth.id.to_string())
    .fetch_optional(&state.pool)
    .await?;

    if existing.is_none() {
        return Err(AppError::NotFound("Embedding config not found".into()));
    }

    let name = req.name.map(|n| n.trim().to_string());
    if let Some(ref n) = name {
        if n.is_empty() {
            return Err(AppError::BadRequest("Config name cannot be empty".into()));
        }
    }
    let model_name = req.model_name.map(|n| n.trim().to_string());
    if let Some(ref n) = model_name {
        if n.is_empty() {
            return Err(AppError::BadRequest("Model name cannot be empty".into()));
        }
    }
    let api_base_url = req.api_base_url.map(|u| u.trim().to_string());

    if let Some(provider) = &req.provider {
        let valid = ["openai", "ollama", "local", "custom"];
        if !valid.contains(&provider.as_str()) {
            return Err(AppError::BadRequest(format!(
                "Invalid provider '{}'",
                provider
            )));
        }
    }

    let api_key_enc = req
        .api_key
        .as_deref()
        .map(|k| encrypt_api_key(k, &state.jwt_secret));

    if req.is_default == Some(true) {
        sqlx::query(
            "UPDATE embedding_configs SET is_default = 0 WHERE user_id = $1 AND id != $2",
        )
        .bind(auth.id.to_string())
        .bind(config_id.to_string())
        .execute(&state.pool)
        .await?;
    }

    let batch_size = req.batch_size.map(|b| b.clamp(1, 2048));

    let q = format!(
        "UPDATE embedding_configs SET name = COALESCE($1, name), provider = COALESCE($2, provider), api_base_url = COALESCE($3, api_base_url), api_key_enc = COALESCE($4, api_key_enc), model_name = COALESCE($5, model_name), dimensions = COALESCE($6, dimensions), batch_size = COALESCE($7, batch_size), is_default = COALESCE($8, is_default) WHERE id = $9 AND user_id = $10 RETURNING {}",
        EMB_SELECT
    );
    let row = sqlx::query_as::<_, EmbRow>(&q)
        .bind(name)
        .bind(req.provider)
        .bind(api_base_url)
        .bind(api_key_enc)
        .bind(model_name)
        .bind(req.dimensions)
        .bind(batch_size)
        .bind(req.is_default)
        .bind(config_id.to_string())
        .bind(auth.id.to_string())
        .fetch_one(&state.pool)
        .await?;

    let resp = parse_emb_row(row)?;
    reload_embedding_provider(&state).await;
    Ok(Json(resp))
}

async fn delete_config(
    State(state): State<AppState>,
    auth: AuthUser,
    Path(config_id): Path<Uuid>,
) -> Result<StatusCode, AppError> {
    let was_default: Option<i32> = sqlx::query_scalar(
        "SELECT CASE WHEN is_default = 1 THEN 1 ELSE 0 END FROM embedding_configs WHERE id = $1 AND user_id = $2",
    )
    .bind(config_id.to_string())
    .bind(auth.id.to_string())
    .fetch_optional(&state.pool)
    .await?;

    let result = sqlx::query("DELETE FROM embedding_configs WHERE id = $1 AND user_id = $2")
        .bind(config_id.to_string())
        .bind(auth.id.to_string())
        .execute(&state.pool)
        .await?;

    if result.rows_affected() == 0 {
        return Err(AppError::NotFound("Embedding config not found".into()));
    }

    if was_default == Some(1) {
        reload_embedding_provider(&state).await;
    }

    Ok(StatusCode::NO_CONTENT)
}

async fn test_connection(
    State(state): State<AppState>,
    auth: AuthUser,
    Path(config_id): Path<Uuid>,
) -> Result<Json<TestEmbeddingResponse>, AppError> {
    let row = sqlx::query_as::<_, (String, Option<String>, Option<String>, String, i32, i32)>(
        "SELECT provider, api_base_url, api_key_enc, model_name, dimensions, batch_size
         FROM embedding_configs
         WHERE id = $1 AND user_id = $2",
    )
    .bind(config_id.to_string())
    .bind(auth.id.to_string())
    .fetch_optional(&state.pool)
    .await?;

    let (provider, api_base_url, api_key_enc, model_name, dimensions, batch_size) = match row {
        Some(r) => r,
        None => return Err(AppError::NotFound("Embedding config not found".into())),
    };

    let api_key = api_key_enc.and_then(|enc| decrypt_api_key(&enc, &state.jwt_secret));
    let base_url = api_base_url.unwrap_or_default();

    let start = std::time::Instant::now();

    let emb_provider: Box<dyn EmbeddingProvider> = if provider == "ollama" {
        Box::new(OllamaEmbeddingProvider::new(
            &base_url,
            &model_name,
            dimensions as usize,
        ))
    } else {
        Box::new(OpenAIEmbeddingProvider::with_batch_size(
            &base_url,
            api_key.as_deref(),
            &model_name,
            dimensions as usize,
            batch_size as usize,
        ))
    };

    match emb_provider.embed_texts(&["Hello, this is a test.".to_string()]).await {
        Ok(embeddings) => {
            let latency = start.elapsed().as_millis() as u64;
            if let Some(emb) = embeddings.first() {
                Ok(Json(TestEmbeddingResponse {
                    success: true,
                    message: format!(
                        "Connected to {} model '{}'. Embedding dimension: {} (expected: {})",
                        provider, model_name, emb.len(), dimensions
                    ),
                    latency_ms: Some(latency),
                }))
            } else {
                Ok(Json(TestEmbeddingResponse {
                    success: false,
                    message: "API returned empty embeddings".into(),
                    latency_ms: Some(latency),
                }))
            }
        }
        Err(e) => {
            let latency = start.elapsed().as_millis() as u64;
            Ok(Json(TestEmbeddingResponse {
                success: false,
                message: format!("Connection failed: {}", e),
                latency_ms: Some(latency),
            }))
        }
    }
}

async fn reload_embedding_provider(state: &AppState) {
    let row = sqlx::query_as::<_, (String, Option<String>, Option<String>, String, i32, i32)>(
        "SELECT provider, api_base_url, api_key_enc, model_name, dimensions, batch_size
         FROM embedding_configs
         WHERE is_default = 1
         ORDER BY updated_at DESC
         LIMIT 1",
    )
    .fetch_optional(&state.pool)
    .await;

    match row {
        Ok(Some((provider_type, api_base_url, api_key_enc, model_name, dimensions, batch_size))) => {
            let api_key = api_key_enc.and_then(|enc| decrypt_api_key(&enc, &state.jwt_secret));
            let base_url = api_base_url.unwrap_or_default();
            let provider: Arc<dyn EmbeddingProvider> = if provider_type == "ollama" {
                Arc::new(OllamaEmbeddingProvider::new(
                    &base_url,
                    &model_name,
                    dimensions as usize,
                ))
            } else {
                Arc::new(OpenAIEmbeddingProvider::with_batch_size(
                    &base_url,
                    api_key.as_deref(),
                    &model_name,
                    dimensions as usize,
                    batch_size as usize,
                ))
            };

            let mut guard = state.embedding_provider.write().await;
            *guard = Some(provider);
            tracing::info!(provider = %provider_type, model = %model_name, dimensions, batch_size, "Embedding provider reloaded");
        }
        Ok(None) => {
            let mut guard = state.embedding_provider.write().await;
            *guard = None;
            tracing::info!("No default embedding config found, embedding provider cleared");
        }
        Err(e) => {
            tracing::error!(error = %e, "Failed to reload embedding provider");
        }
    }
}

pub async fn init_embedding_provider(state: &AppState) {
    reload_embedding_provider(state).await;
}
