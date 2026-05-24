use axum::{
    extract::{Path, Query, State},
    http::StatusCode,
    response::Json,
    routing::get,
    Router,
};
use serde::Deserialize;
use uuid::Uuid;

use crate::api::AppState;
use crate::services::retrieval_trace_store;

#[derive(Deserialize)]
pub struct ListParams {
    #[serde(default = "default_limit")]
    pub limit: i64,
    #[serde(default)]
    pub offset: i64,
}

fn default_limit() -> i64 {
    20
}

pub fn router() -> Router<AppState> {
    Router::new()
        .route("/retrieval-traces/{trace_id}", get(get_trace))
        .route(
            "/workspaces/{workspace_id}/retrieval-traces",
            get(list_traces),
        )
        .route(
            "/messages/{message_id}/retrieval-trace",
            get(get_trace_by_message),
        )
}

async fn get_trace(
    State(state): State<AppState>,
    Path(trace_id): Path<Uuid>,
) -> Result<Json<serde_json::Value>, StatusCode> {
    match retrieval_trace_store::get_trace(&state.pool, trace_id).await {
        Ok(Some(row)) => Ok(Json(serde_json::to_value(row).unwrap_or_default())),
        Ok(None) => Err(StatusCode::NOT_FOUND),
        Err(e) => {
            tracing::error!(error = %e, "Failed to get retrieval trace");
            Err(StatusCode::INTERNAL_SERVER_ERROR)
        }
    }
}

async fn list_traces(
    State(state): State<AppState>,
    Path(workspace_id): Path<Uuid>,
    Query(params): Query<ListParams>,
) -> Result<Json<serde_json::Value>, StatusCode> {
    match retrieval_trace_store::list_traces_for_workspace(
        &state.pool,
        workspace_id,
        params.limit.min(100),
        params.offset,
    )
    .await
    {
        Ok(summaries) => Ok(Json(serde_json::to_value(summaries).unwrap_or_default())),
        Err(e) => {
            tracing::error!(error = %e, "Failed to list retrieval traces");
            Err(StatusCode::INTERNAL_SERVER_ERROR)
        }
    }
}

async fn get_trace_by_message(
    State(state): State<AppState>,
    Path(message_id): Path<Uuid>,
) -> Result<Json<serde_json::Value>, StatusCode> {
    match retrieval_trace_store::get_trace_for_message(&state.pool, message_id).await {
        Ok(Some(row)) => Ok(Json(serde_json::to_value(row).unwrap_or_default())),
        Ok(None) => Err(StatusCode::NOT_FOUND),
        Err(e) => {
            tracing::error!(error = %e, "Failed to get retrieval trace by message");
            Err(StatusCode::INTERNAL_SERVER_ERROR)
        }
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn test_list_params_defaults() {
        let params: ListParams = serde_json::from_str("{}").unwrap();
        assert_eq!(params.limit, 20);
        assert_eq!(params.offset, 0);
    }

    #[test]
    fn test_list_params_custom() {
        let params: ListParams = serde_json::from_str(r#"{"limit": 50, "offset": 10}"#).unwrap();
        assert_eq!(params.limit, 50);
        assert_eq!(params.offset, 10);
    }

    #[test]
    fn test_router_creation() {
        let _ = router();
    }
}
