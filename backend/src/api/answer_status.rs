use axum::{
    extract::{Path, State},
    routing::{get, put},
    Json, Router,
};
use serde::Serialize;
use uuid::Uuid;

use crate::auth::middleware::AuthUser;
use crate::error::AppError;
use crate::services::answer_status::{
    self, AnswerStatus, UpdateAnswerStatusInput,
};

use super::AppState;

#[derive(Serialize)]
struct AnswerStatusResponse {
    message_id: String,
    status: AnswerStatus,
    allowed_transitions: Vec<AnswerStatus>,
}

async fn get_status(
    State(state): State<AppState>,
    _user: AuthUser,
    Path(message_id): Path<String>,
) -> Result<Json<AnswerStatusResponse>, AppError> {
    let msg_id = Uuid::parse_str(&message_id)
        .map_err(|_| AppError::BadRequest("Invalid message ID".into()))?;

    let status = answer_status::get_answer_status(&state.pool, msg_id)
        .await
        .map_err(|e| AppError::Internal(e.into()))?;

    Ok(Json(AnswerStatusResponse {
        message_id,
        status,
        allowed_transitions: status.allowed_transitions(),
    }))
}

async fn update_status(
    State(state): State<AppState>,
    _user: AuthUser,
    Path(message_id): Path<String>,
    Json(input): Json<UpdateAnswerStatusInput>,
) -> Result<Json<AnswerStatusResponse>, AppError> {
    let msg_id = Uuid::parse_str(&message_id)
        .map_err(|_| AppError::BadRequest("Invalid message ID".into()))?;

    let new_status = answer_status::update_answer_status(&state.pool, msg_id, &input.status)
        .await
        .map_err(|e| {
            let msg = e.to_string();
            if msg.contains("Cannot transition") || msg.contains("Invalid answer status") {
                AppError::BadRequest(msg)
            } else if msg.contains("not found") {
                AppError::NotFound(msg)
            } else {
                AppError::Internal(e.into())
            }
        })?;

    Ok(Json(AnswerStatusResponse {
        message_id,
        status: new_status,
        allowed_transitions: new_status.allowed_transitions(),
    }))
}

pub fn router() -> Router<AppState> {
    Router::new()
        .route("/messages/:message_id/status", get(get_status).put(update_status))
}
