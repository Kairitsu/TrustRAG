use axum::{
    extract::{Query, State},
    routing::get,
    Json, Router,
};
use serde::Deserialize;
use uuid::Uuid;

use crate::auth::middleware::AuthUser;
use crate::error::AppError;
use crate::services::audit;

use super::AppState;

#[derive(Deserialize)]
pub struct AuditQuery {
    workspace_id: Option<String>,
    action: Option<String>,
    limit: Option<i64>,
    offset: Option<i64>,
}

async fn list_audit_entries(
    State(state): State<AppState>,
    user: AuthUser,
    Query(params): Query<AuditQuery>,
) -> Result<Json<serde_json::Value>, AppError> {
    let workspace_id = params.workspace_id
        .as_deref()
        .and_then(|s| Uuid::parse_str(s).ok());
    let limit = params.limit.unwrap_or(50).min(200);
    let offset = params.offset.unwrap_or(0);

    let entries = audit::query(
        &state.pool,
        workspace_id,
        Some(user.id),
        params.action.as_deref(),
        limit,
        offset,
    ).await.map_err(|e| AppError::Internal(e))?;

    let count = audit::count(
        &state.pool,
        workspace_id,
        params.action.as_deref(),
    ).await.map_err(|e| AppError::Internal(e))?;

    Ok(Json(serde_json::json!({
        "entries": entries,
        "total": count,
        "limit": limit,
        "offset": offset,
    })))
}

pub fn router() -> Router<AppState> {
    Router::new()
        .route("/", get(list_audit_entries))
}
