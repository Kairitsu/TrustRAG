use axum::{
    extract::State,
    routing::get,
    Json, Router,
};
use serde::Serialize;

use crate::api::AppState;

#[derive(Debug, Serialize)]
pub struct DomainProfileSummary {
    pub name: String,
    pub display_name: String,
    pub description: String,
}

#[derive(Debug, Serialize)]
pub struct DomainProfileDetail {
    pub name: String,
    pub display_name: String,
    pub description: String,
    pub search: serde_json::Value,
    pub retrieval: serde_json::Value,
    pub verification: serde_json::Value,
    pub terminology: Vec<String>,
    pub query_expansion_enabled: bool,
}

pub fn router() -> Router<AppState> {
    Router::new()
        .route("/domain-profiles", get(list_profiles))
        .route("/domain-profiles/{name}", get(get_profile))
}

async fn list_profiles(
    State(state): State<AppState>,
) -> Json<Vec<DomainProfileSummary>> {
    let profiles: Vec<DomainProfileSummary> = state
        .domain_profiles
        .list()
        .into_iter()
        .map(|p| DomainProfileSummary {
            name: p.name.clone(),
            display_name: p.display_name.clone(),
            description: p.description.clone(),
        })
        .collect();
    Json(profiles)
}

async fn get_profile(
    State(state): State<AppState>,
    axum::extract::Path(name): axum::extract::Path<String>,
) -> Result<Json<DomainProfileDetail>, axum::http::StatusCode> {
    let profile = state
        .domain_profiles
        .get(&name)
        .ok_or(axum::http::StatusCode::NOT_FOUND)?;

    let detail = DomainProfileDetail {
        name: profile.name.clone(),
        display_name: profile.display_name.clone(),
        description: profile.description.clone(),
        search: serde_json::to_value(&profile.search).unwrap_or_default(),
        retrieval: serde_json::to_value(&profile.retrieval).unwrap_or_default(),
        verification: serde_json::to_value(&profile.verification).unwrap_or_default(),
        terminology: profile.terminology.clone(),
        query_expansion_enabled: profile.query_expansion.enabled,
    };
    Ok(Json(detail))
}
