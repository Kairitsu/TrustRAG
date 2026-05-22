use axum::{
    extract::{Path, State},
    http::StatusCode,
    routing::{get, post, put, delete},
    Json, Router,
};
use serde::{Deserialize, Serialize};
use uuid::Uuid;

use crate::auth::middleware::AuthUser;
use crate::db::compat;
use crate::error::AppError;

use super::workspace_members::require_admin_access;
use super::AppState;

pub fn router() -> Router<AppState> {
    Router::new()
        .route("/model-configs", get(list_configs).post(create_config))
        .route(
            "/model-configs/{id}",
            put(update_config).delete(delete_config),
        )
        .route("/model-configs/{id}/test", post(test_connection))
        .route("/ollama/discover", get(ollama_discover))
        .route("/ollama/models", get(ollama_list_models))
        .route("/huggingface/search", get(hf_search_models))
}

// ── Request / Response types ──

#[derive(Deserialize)]
pub struct CreateConfigRequest {
    pub name: String,
    pub provider: String,
    pub api_base_url: String,
    #[serde(default)]
    pub api_key: Option<String>,
    pub model_name: String,
    #[serde(default = "default_temperature")]
    pub temperature: f32,
    #[serde(default = "default_max_tokens")]
    pub max_tokens: i32,
    #[serde(default)]
    pub is_default: bool,
    #[serde(default)]
    pub workspace_id: Option<Uuid>,
}

fn default_temperature() -> f32 {
    0.1
}
fn default_max_tokens() -> i32 {
    4096
}

#[derive(Deserialize)]
pub struct UpdateConfigRequest {
    pub name: Option<String>,
    pub provider: Option<String>,
    pub api_base_url: Option<String>,
    pub api_key: Option<String>,
    pub model_name: Option<String>,
    pub temperature: Option<f32>,
    pub max_tokens: Option<i32>,
    pub is_default: Option<bool>,
}

#[derive(Serialize)]
pub struct ModelConfigResponse {
    pub id: Uuid,
    pub workspace_id: Option<Uuid>,
    pub user_id: Uuid,
    pub name: String,
    pub provider: String,
    pub api_base_url: String,
    pub has_api_key: bool,
    pub model_name: String,
    pub temperature: Option<f64>,
    pub max_tokens: Option<i32>,
    pub is_default: Option<bool>,
    pub created_at: String,
    pub updated_at: String,
}

type ConfigRow = (String, Option<String>, String, String, String, String, Option<String>, String, Option<f64>, Option<i32>, Option<bool>, String, String);

fn parse_config_row(r: ConfigRow) -> Result<ModelConfigResponse, AppError> {
    Ok(ModelConfigResponse {
        id: compat::parse_uuid(&r.0).map_err(|e| AppError::Internal(e.into()))?,
        workspace_id: r.1.as_deref().and_then(|s| compat::parse_uuid(s).ok()),
        user_id: compat::parse_uuid(&r.2).map_err(|e| AppError::Internal(e.into()))?,
        name: r.3,
        provider: r.4,
        api_base_url: r.5,
        has_api_key: r.6.is_some(),
        model_name: r.7,
        temperature: r.8,
        max_tokens: r.9,
        is_default: r.10,
        created_at: r.11,
        updated_at: r.12,
    })
}

const CONFIG_SELECT: &str = "id, workspace_id, user_id, name, provider, api_base_url, api_key_enc, model_name, temperature, max_tokens, is_default, CAST(created_at AS TEXT), CAST(updated_at AS TEXT)";

#[derive(Serialize)]
pub struct TestConnectionResponse {
    pub success: bool,
    pub message: String,
    pub latency_ms: Option<u64>,
}

// ── Simple XOR-based obfuscation for API keys ──
// Production systems should use AES-256-GCM with a proper KMS.
pub fn encrypt_api_key(key: &str, secret: &str) -> String {
    let secret_bytes = secret.as_bytes();
    let encrypted: Vec<u8> = key
        .as_bytes()
        .iter()
        .enumerate()
        .map(|(i, b)| b ^ secret_bytes[i % secret_bytes.len()])
        .collect();
    hex::encode(encrypted)
}

pub fn decrypt_api_key(enc_hex: &str, secret: &str) -> Option<String> {
    let encrypted = hex::decode(enc_hex).ok()?;
    let secret_bytes = secret.as_bytes();
    let decrypted: Vec<u8> = encrypted
        .iter()
        .enumerate()
        .map(|(i, b)| b ^ secret_bytes[i % secret_bytes.len()])
        .collect();
    String::from_utf8(decrypted).ok()
}

// ── Handlers ──

async fn list_configs(
    State(state): State<AppState>,
    auth: AuthUser,
) -> Result<Json<Vec<ModelConfigResponse>>, AppError> {
    let q = format!(
        "SELECT {} FROM model_configs WHERE user_id = $1 ORDER BY is_default DESC NULLS LAST, created_at DESC",
        CONFIG_SELECT
    );
    let rows = sqlx::query_as::<_, ConfigRow>(&q)
        .bind(auth.id.to_string())
        .fetch_all(&state.pool)
        .await?;

    let configs: Result<Vec<_>, _> = rows.into_iter().map(parse_config_row).collect();
    Ok(Json(configs?))
}

async fn create_config(
    State(state): State<AppState>,
    auth: AuthUser,
    Json(req): Json<CreateConfigRequest>,
) -> Result<(StatusCode, Json<ModelConfigResponse>), AppError> {
    let name = req.name.trim().to_string();
    if name.is_empty() {
        return Err(AppError::BadRequest("Config name is required".into()));
    }
    let model_name = req.model_name.trim().to_string();
    if model_name.is_empty() {
        return Err(AppError::BadRequest("Model name is required".into()));
    }
    let api_base_url = req.api_base_url.trim().to_string();

    let valid_providers = ["openai", "anthropic", "ollama", "custom"];
    if !valid_providers.contains(&req.provider.as_str()) {
        return Err(AppError::BadRequest(format!(
            "Invalid provider '{}'. Must be one of: {}",
            req.provider,
            valid_providers.join(", ")
        )));
    }

    if let Some(ws_id) = req.workspace_id {
        let ws_type: Option<String> = sqlx::query_scalar(
            "SELECT COALESCE(type, 'personal') FROM workspaces WHERE id = $1",
        )
        .bind(ws_id.to_string())
        .fetch_optional(&state.pool)
        .await?;

        if ws_type.as_deref() == Some("team") {
            require_admin_access(&state.pool, ws_id, auth.id).await?;
        }
    }

    let api_key_enc = req
        .api_key
        .as_deref()
        .map(|k| encrypt_api_key(k, &state.jwt_secret));

    if req.is_default {
        sqlx::query("UPDATE model_configs SET is_default = 0 WHERE user_id = $1")
            .bind(auth.id.to_string())
            .execute(&state.pool)
            .await?;
    }

    let q = format!(
        "INSERT INTO model_configs (workspace_id, user_id, name, provider, api_base_url, api_key_enc, model_name, temperature, max_tokens, is_default) VALUES ($1, $2, $3, $4, $5, $6, $7, $8, $9, $10) RETURNING {}",
        CONFIG_SELECT
    );
    let row = sqlx::query_as::<_, ConfigRow>(&q)
        .bind(req.workspace_id.map(|u| u.to_string()))
        .bind(auth.id.to_string())
        .bind(&name)
        .bind(&req.provider)
        .bind(&api_base_url)
        .bind(&api_key_enc)
        .bind(&model_name)
        .bind(req.temperature as f64)
        .bind(req.max_tokens)
        .bind(req.is_default)
        .fetch_one(&state.pool)
        .await?;

    Ok((StatusCode::CREATED, Json(parse_config_row(row)?)))
}

async fn update_config(
    State(state): State<AppState>,
    auth: AuthUser,
    Path(config_id): Path<Uuid>,
    Json(req): Json<UpdateConfigRequest>,
) -> Result<Json<ModelConfigResponse>, AppError> {
    let existing = sqlx::query_scalar::<_, String>(
        "SELECT id FROM model_configs WHERE id = $1 AND user_id = $2",
    )
    .bind(config_id.to_string())
    .bind(auth.id.to_string())
    .fetch_optional(&state.pool)
    .await?;

    if existing.is_none() {
        return Err(AppError::NotFound("Model config not found".into()));
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
        let valid = ["openai", "anthropic", "ollama", "custom"];
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
            "UPDATE model_configs SET is_default = 0 WHERE user_id = $1 AND id != $2",
        )
        .bind(auth.id.to_string())
        .bind(config_id.to_string())
        .execute(&state.pool)
        .await?;
    }

    let q = format!(
        "UPDATE model_configs SET name = COALESCE($1, name), provider = COALESCE($2, provider), api_base_url = COALESCE($3, api_base_url), api_key_enc = COALESCE($4, api_key_enc), model_name = COALESCE($5, model_name), temperature = COALESCE($6, temperature), max_tokens = COALESCE($7, max_tokens), is_default = COALESCE($8, is_default) WHERE id = $9 AND user_id = $10 RETURNING {}",
        CONFIG_SELECT
    );
    let row = sqlx::query_as::<_, ConfigRow>(&q)
        .bind(name)
        .bind(req.provider)
        .bind(api_base_url)
        .bind(api_key_enc)
        .bind(model_name)
        .bind(req.temperature.map(|t| t as f64))
        .bind(req.max_tokens)
        .bind(req.is_default)
        .bind(config_id.to_string())
        .bind(auth.id.to_string())
        .fetch_one(&state.pool)
        .await?;

    Ok(Json(parse_config_row(row)?))
}

async fn delete_config(
    State(state): State<AppState>,
    auth: AuthUser,
    Path(config_id): Path<Uuid>,
) -> Result<StatusCode, AppError> {
    let result = sqlx::query("DELETE FROM model_configs WHERE id = $1 AND user_id = $2")
        .bind(config_id.to_string())
        .bind(auth.id.to_string())
        .execute(&state.pool)
        .await?;

    if result.rows_affected() == 0 {
        return Err(AppError::NotFound("Model config not found".into()));
    }

    Ok(StatusCode::NO_CONTENT)
}

async fn test_connection(
    State(state): State<AppState>,
    auth: AuthUser,
    Path(config_id): Path<Uuid>,
) -> Result<Json<TestConnectionResponse>, AppError> {
    let row = sqlx::query_as::<_, (String, String, Option<String>, String)>(
        "SELECT provider, api_base_url, api_key_enc, model_name
         FROM model_configs
         WHERE id = $1 AND user_id = $2",
    )
    .bind(config_id.to_string())
    .bind(auth.id.to_string())
    .fetch_optional(&state.pool)
    .await?;

    let (provider, api_base_url, api_key_enc, model_name) = match row {
        Some(r) => r,
        None => return Err(AppError::NotFound("Model config not found".into())),
    };

    let api_key = api_key_enc.and_then(|enc| decrypt_api_key(&enc, &state.jwt_secret));

    let start = std::time::Instant::now();
    let result = test_provider_connection(&provider, &api_base_url, api_key.as_deref(), &model_name).await;
    let latency = start.elapsed().as_millis() as u64;

    match result {
        Ok(msg) => Ok(Json(TestConnectionResponse {
            success: true,
            message: msg,
            latency_ms: Some(latency),
        })),
        Err(e) => Ok(Json(TestConnectionResponse {
            success: false,
            message: format!("Connection failed: {}", e),
            latency_ms: Some(latency),
        })),
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn test_encrypt_decrypt_roundtrip() {
        let key = "sk-test-12345-abcdef";
        let secret = "my-jwt-secret";
        let encrypted = encrypt_api_key(key, secret);
        assert_ne!(encrypted, key);
        let decrypted = decrypt_api_key(&encrypted, secret).unwrap();
        assert_eq!(decrypted, key);
    }

    #[test]
    fn test_encrypt_different_secrets_produce_different_results() {
        let key = "sk-test-12345";
        let enc1 = encrypt_api_key(key, "secret-a");
        let enc2 = encrypt_api_key(key, "secret-b");
        assert_ne!(enc1, enc2);
    }

    #[test]
    fn test_decrypt_wrong_secret_fails() {
        let key = "sk-test-12345";
        let encrypted = encrypt_api_key(key, "correct-secret");
        let decrypted = decrypt_api_key(&encrypted, "wrong-secret").unwrap();
        assert_ne!(decrypted, key);
    }

    #[test]
    fn test_encrypt_empty_key() {
        let encrypted = encrypt_api_key("", "secret");
        assert_eq!(encrypted, "");
        let decrypted = decrypt_api_key(&encrypted, "secret").unwrap();
        assert_eq!(decrypted, "");
    }

    #[test]
    fn test_valid_providers() {
        let valid = ["openai", "anthropic", "ollama", "custom"];
        for p in &valid {
            assert!(valid.contains(p));
        }
        assert!(!valid.contains(&"invalid_provider"));
    }

    #[test]
    fn test_encrypt_special_characters() {
        let key = "sk-proj-あいう!@#$%^&*()_+-=[]{}|;':\",./<>?";
        let secret = "secret-with-special-chars!@#$";
        let encrypted = encrypt_api_key(key, secret);
        let decrypted = decrypt_api_key(&encrypted, secret).unwrap();
        assert_eq!(decrypted, key, "Special characters should survive roundtrip");
    }

    #[test]
    fn test_encrypt_long_key() {
        let key = "a".repeat(1000);
        let secret = "short";
        let encrypted = encrypt_api_key(&key, secret);
        let decrypted = decrypt_api_key(&encrypted, secret).unwrap();
        assert_eq!(decrypted, key, "Long keys should survive roundtrip");
    }

    #[test]
    fn test_decrypt_invalid_hex() {
        let result = decrypt_api_key("not-valid-hex-zzzz", "secret");
        assert!(result.is_none(), "Invalid hex should return None");
    }
}

#[derive(Serialize)]
struct OllamaDiscoverResponse {
    available: bool,
    url: String,
    version: Option<String>,
}

async fn ollama_discover(
    _auth: AuthUser,
) -> Json<OllamaDiscoverResponse> {
    let ollama_url =
        std::env::var("OLLAMA_URL").unwrap_or_else(|_| "http://localhost:11434".to_string());

    let client = reqwest::Client::new();
    match client
        .get(&ollama_url)
        .timeout(std::time::Duration::from_secs(3))
        .send()
        .await
    {
        Ok(resp) if resp.status().is_success() => {
            let body = resp.text().await.unwrap_or_default();
            Json(OllamaDiscoverResponse {
                available: true,
                url: ollama_url,
                version: if body.contains("Ollama") {
                    Some(body.trim().to_string())
                } else {
                    None
                },
            })
        }
        _ => Json(OllamaDiscoverResponse {
            available: false,
            url: ollama_url,
            version: None,
        }),
    }
}

#[derive(Serialize)]
struct OllamaModel {
    name: String,
    size: Option<u64>,
    modified_at: Option<String>,
}

#[derive(Serialize)]
struct OllamaModelsResponse {
    models: Vec<OllamaModel>,
}

async fn ollama_list_models(
    _auth: AuthUser,
) -> Result<Json<OllamaModelsResponse>, AppError> {
    let ollama_url =
        std::env::var("OLLAMA_URL").unwrap_or_else(|_| "http://localhost:11434".to_string());

    let client = reqwest::Client::new();
    let resp = client
        .get(format!("{}/api/tags", ollama_url))
        .timeout(std::time::Duration::from_secs(5))
        .send()
        .await
        .map_err(|e| {
            AppError::Internal(anyhow::anyhow!("Failed to connect to Ollama: {}", e))
        })?;

    if !resp.status().is_success() {
        return Err(AppError::Internal(anyhow::anyhow!(
            "Ollama returned status {}",
            resp.status()
        )));
    }

    let body: serde_json::Value = resp.json().await.map_err(|e| {
        AppError::Internal(anyhow::anyhow!("Failed to parse Ollama response: {}", e))
    })?;

    let models = body["models"]
        .as_array()
        .unwrap_or(&vec![])
        .iter()
        .map(|m| OllamaModel {
            name: m["name"].as_str().unwrap_or("").to_string(),
            size: m["size"].as_u64(),
            modified_at: m["modified_at"].as_str().map(|s| s.to_string()),
        })
        .collect();

    Ok(Json(OllamaModelsResponse { models }))
}

#[derive(Deserialize)]
struct HfSearchQuery {
    q: String,
    #[serde(default = "default_hf_limit")]
    limit: usize,
    #[serde(default)]
    filter: Option<String>,
}

fn default_hf_limit() -> usize {
    10
}

#[derive(Serialize)]
struct HfModelResult {
    id: String,
    author: Option<String>,
    downloads: Option<u64>,
    likes: Option<u64>,
    pipeline_tag: Option<String>,
    tags: Vec<String>,
    is_gguf: bool,
}

async fn hf_search_models(
    _auth: AuthUser,
    axum::extract::Query(params): axum::extract::Query<HfSearchQuery>,
) -> Result<Json<Vec<HfModelResult>>, AppError> {
    let client = reqwest::Client::new();
    let filter = params.filter.unwrap_or_else(|| "text-generation".to_string());
    let limit = params.limit.min(50);
    let url = format!(
        "https://huggingface.co/api/models?search={}&filter={}&sort=downloads&direction=-1&limit={}",
        urlencoding::encode(&params.q),
        urlencoding::encode(&filter),
        limit,
    );

    let resp = client
        .get(&url)
        .timeout(std::time::Duration::from_secs(10))
        .send()
        .await
        .map_err(|e| AppError::Internal(anyhow::anyhow!("HuggingFace API error: {}", e)))?;

    let body: Vec<serde_json::Value> = resp.json().await.map_err(|e| {
        AppError::Internal(anyhow::anyhow!("Failed to parse HuggingFace response: {}", e))
    })?;

    let models: Vec<HfModelResult> = body
        .into_iter()
        .map(|m| {
            let tags: Vec<String> = m["tags"]
                .as_array()
                .unwrap_or(&vec![])
                .iter()
                .filter_map(|t| t.as_str().map(|s| s.to_string()))
                .collect();
            let is_gguf = tags.iter().any(|t| t.contains("gguf"));
            HfModelResult {
                id: m["id"].as_str().unwrap_or("").to_string(),
                author: m["author"].as_str().map(|s| s.to_string()),
                downloads: m["downloads"].as_u64(),
                likes: m["likes"].as_u64(),
                pipeline_tag: m["pipeline_tag"].as_str().map(|s| s.to_string()),
                tags,
                is_gguf,
            }
        })
        .collect();

    Ok(Json(models))
}

async fn test_provider_connection(
    provider: &str,
    api_base_url: &str,
    api_key: Option<&str>,
    model_name: &str,
) -> anyhow::Result<String> {
    let client = reqwest::Client::new();
    let base = crate::services::embedding::normalize_api_base(api_base_url);

    let models_url = format!("{}/models", base);
    let mut req = client.get(&models_url);
    if let Some(key) = api_key {
        req = req.bearer_auth(key);
    }

    let resp = req
        .timeout(std::time::Duration::from_secs(10))
        .send()
        .await
        .map_err(|e| anyhow::anyhow!("Failed to connect to {}: {}", base, e))?;

    if !resp.status().is_success() {
        let status = resp.status();
        let body = resp.text().await.unwrap_or_default();
        anyhow::bail!("API returned status {}: {}", status, body);
    }

    let chat_url = format!("{}/chat/completions", base);
    let chat_body = serde_json::json!({
        "model": model_name,
        "messages": [{"role": "user", "content": "Hi"}],
        "max_tokens": 5,
    });

    let mut chat_req = client.post(&chat_url).json(&chat_body);
    if let Some(key) = api_key {
        chat_req = chat_req.bearer_auth(key);
    }

    let chat_resp = chat_req
        .timeout(std::time::Duration::from_secs(30))
        .send()
        .await
        .map_err(|e| anyhow::anyhow!("Chat request failed: {}", e))?;

    if !chat_resp.status().is_success() {
        let status = chat_resp.status();
        let body = chat_resp.text().await.unwrap_or_default();
        anyhow::bail!(
            "Model '{}' chat test failed (status {}): {}",
            model_name,
            status,
            body
        );
    }

    Ok(format!(
        "Connected to {} and model '{}' responded successfully",
        provider, model_name
    ))
}
