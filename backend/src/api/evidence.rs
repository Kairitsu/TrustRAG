use axum::{
    extract::{Path, State},
    routing::get,
    Json, Router,
};
use uuid::Uuid;

use crate::auth::middleware::AuthUser;
use crate::error::AppError;

use super::AppState;

async fn get_evidence_report(
    State(state): State<AppState>,
    _user: AuthUser,
    Path(message_id): Path<String>,
) -> Result<Json<serde_json::Value>, AppError> {
    let msg_id = Uuid::parse_str(&message_id)
        .map_err(|_| AppError::BadRequest("Invalid message ID".into()))?;

    let row: Option<(Option<serde_json::Value>,)> = sqlx::query_as(
        "SELECT evidence_report FROM messages WHERE id = $1"
    )
    .bind(msg_id.to_string())
    .fetch_optional(&state.pool)
    .await
    .map_err(|e| AppError::Internal(e.into()))?;

    match row {
        Some((Some(report),)) => Ok(Json(report)),
        Some((None,)) => Ok(Json(serde_json::json!({"status": "no_report"}))),
        None => Err(AppError::NotFound("Message not found".into())),
    }
}

pub fn router() -> Router<AppState> {
    Router::new()
        .route("/messages/{message_id}/evidence", get(get_evidence_report))
}
