use axum::{
    extract::State,
    routing::{get, post},
    Json, Router,
};
use serde::Serialize;

use crate::auth::middleware::AuthUser;
use crate::error::AppError;

use super::AppState;

pub fn router() -> Router<AppState> {
    Router::new()
        .route("/system/db-info", get(db_info))
        .route("/system/backup-db", post(backup_db))
        .route("/system/reset-db", post(reset_db))
        .route("/system/validate-token", get(validate_token))
}

#[derive(Serialize)]
struct DbInfo {
    schema_version: i32,
    current_version: i32,
    needs_migration: bool,
    db_path: String,
}

async fn db_info(
    State(state): State<AppState>,
    _auth: AuthUser,
) -> Result<Json<DbInfo>, AppError> {
    let version = crate::db::get_schema_version(&state.pool).await
        .map_err(|e| AppError::Internal(e))?;

    let current = crate::db::CURRENT_SCHEMA_VERSION;

    let db_path = std::env::var("TRUSTRAG__DATABASE_URL")
        .unwrap_or_else(|_| "unknown".into());

    Ok(Json(DbInfo {
        schema_version: version,
        current_version: current,
        needs_migration: version < current,
        db_path,
    }))
}

#[derive(Serialize)]
struct BackupResult {
    success: bool,
    backup_path: Option<String>,
    message: String,
}

async fn backup_db(
    State(_state): State<AppState>,
    _auth: AuthUser,
) -> Result<Json<BackupResult>, AppError> {
    let data_dir = crate::config::AppConfig::load()
        .map(|c| c.data_dir)
        .unwrap_or_else(|_| ".".into());

    match crate::db::backup_database(&data_dir).await {
        Ok(path) => Ok(Json(BackupResult {
            success: true,
            backup_path: Some(path.clone()),
            message: format!("数据库已备份到: {}", path),
        })),
        Err(e) => Ok(Json(BackupResult {
            success: false,
            backup_path: None,
            message: format!("备份失败: {}", e),
        })),
    }
}

#[derive(Serialize)]
struct ResetResult {
    success: bool,
    message: String,
}

async fn reset_db(
    State(state): State<AppState>,
    _auth: AuthUser,
) -> Result<Json<ResetResult>, AppError> {
    let data_dir = crate::config::AppConfig::load()
        .map(|c| c.data_dir)
        .unwrap_or_else(|_| ".".into());

    match crate::db::backup_database(&data_dir).await {
        Ok(backup_path) => {
            tracing::info!(backup = %backup_path, "Database backed up before reset");
        }
        Err(e) => {
            tracing::warn!(error = %e, "Could not backup before reset, proceeding anyway");
        }
    }

    let tables = vec![
        "review_comments", "source_reviews", "review_tasks",
        "answer_reviews", "claim_reviews", "answer_versions",
        "retrieval_traces", "audit_trail", "document_metadata",
        "entity_relations", "entities",
        "review_records", "citations", "messages", "conversations",
        "embedding_configs", "model_configs",
        "document_chunks", "documents",
        "workspace_members", "workspaces", "users",
    ];

    for table in &tables {
        let sql = format!("DELETE FROM {}", table);
        match sqlx::query(&sql).execute(&state.pool).await {
            Ok(_) => tracing::debug!(table = table, "Table cleared"),
            Err(e) => tracing::warn!(table = table, error = %e, "Failed to clear table"),
        }
    }

    Ok(Json(ResetResult {
        success: true,
        message: "本地数据已重置，请重新注册账号".into(),
    }))
}

#[derive(Serialize)]
struct TokenValidation {
    valid: bool,
    user_exists: bool,
    message: String,
}

async fn validate_token(
    State(state): State<AppState>,
    auth: AuthUser,
) -> Result<Json<TokenValidation>, AppError> {
    let user_id = auth.id.to_string();
    let exists = crate::db::validate_token_user(&state.pool, &user_id).await
        .unwrap_or(false);

    if exists {
        Ok(Json(TokenValidation {
            valid: true,
            user_exists: true,
            message: "Token 有效且用户存在".into(),
        }))
    } else {
        Ok(Json(TokenValidation {
            valid: true,
            user_exists: false,
            message: "Token 有效但当前数据库中不存在对应用户，请重新登录".into(),
        }))
    }
}
