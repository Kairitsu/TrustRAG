use axum::{
    extract::{Path, State},
    routing::{get, post, put},
    Json, Router,
};
use rand::Rng;
use serde::{Deserialize, Serialize};
use sqlx::Row;
use uuid::Uuid;

use crate::auth::middleware::AuthUser;
use crate::db::compat;
use crate::error::AppError;

use super::AppState;

#[derive(Serialize)]
pub struct WorkspaceResponse {
    pub id: Uuid,
    pub name: String,
    pub description: Option<String>,
    pub owner_id: Uuid,
    pub visibility: String,
    #[serde(rename = "type")]
    pub ws_type: String,
    pub invite_code: Option<String>,
    pub created_at: String,
    pub updated_at: String,
}

#[derive(Deserialize)]
pub struct CreateWorkspaceRequest {
    pub name: String,
    pub description: Option<String>,
    pub visibility: Option<String>,
    #[serde(rename = "type")]
    pub ws_type: Option<String>,
}

#[derive(Deserialize)]
pub struct UpdateWorkspaceRequest {
    pub name: Option<String>,
    pub description: Option<String>,
    pub visibility: Option<String>,
}

#[derive(Deserialize)]
pub struct JoinWorkspaceRequest {
    pub invite_code: String,
}

fn generate_invite_code() -> String {
    const CHARSET: &[u8] = b"ABCDEFGHJKLMNPQRSTUVWXYZ23456789";
    let mut rng = rand::thread_rng();
    (0..8)
        .map(|_| {
            let idx = rng.gen_range(0..CHARSET.len());
            CHARSET[idx] as char
        })
        .collect()
}

pub fn router() -> Router<AppState> {
    Router::new()
        .route("/workspaces", get(list).post(create))
        .route(
            "/workspaces/{id}",
            get(get_one).put(update).delete(remove),
        )
        .route("/workspaces/join", post(join_workspace))
        .route(
            "/workspaces/{id}/regenerate-invite-code",
            post(regenerate_invite_code),
        )
        .route(
            "/workspaces/{id}/transfer-ownership",
            put(transfer_ownership),
        )
}

async fn list(
    auth: AuthUser,
    State(state): State<AppState>,
) -> Result<Json<Vec<WorkspaceResponse>>, AppError> {
    let rows = sqlx::query_as::<_, (String, String, Option<String>, String, String, String, String, String, Option<String>)>(
        r#"
        SELECT w.id, w.name, w.description, w.owner_id, w.visibility,
               COALESCE(w.type, 'personal') as type, w.invite_code,
               CAST(w.created_at AS TEXT) as created_at, CAST(w.updated_at AS TEXT) as updated_at
        FROM workspaces w
        WHERE w.owner_id = $1
           OR w.id IN (SELECT workspace_id FROM workspace_members WHERE user_id = $1)
        ORDER BY w.updated_at DESC
        "#,
    )
    .bind(auth.id.to_string())
    .fetch_all(&state.pool)
    .await?;

    let mut workspaces = Vec::with_capacity(rows.len());
    for r in rows {
        workspaces.push(WorkspaceResponse {
            id: compat::parse_uuid(&r.0).map_err(|e| AppError::Internal(e.into()))?,
            name: r.1,
            description: r.2,
            owner_id: compat::parse_uuid(&r.3).map_err(|e| AppError::Internal(e.into()))?,
            visibility: r.4,
            ws_type: r.5,
            invite_code: r.6,
            created_at: r.7,
            updated_at: r.8,
        });
    }

    Ok(Json(workspaces))
}

async fn create(
    auth: AuthUser,
    State(state): State<AppState>,
    Json(req): Json<CreateWorkspaceRequest>,
) -> Result<(axum::http::StatusCode, Json<WorkspaceResponse>), AppError> {
    let name = req.name.trim().to_string();
    if name.is_empty() {
        return Err(AppError::BadRequest("Name is required".into()));
    }

    let visibility = req.visibility.unwrap_or_else(|| "private".to_string());
    if !matches!(visibility.as_str(), "private" | "public") {
        return Err(AppError::BadRequest("Visibility must be 'private' or 'public'".into()));
    }

    let ws_type = req.ws_type.unwrap_or_else(|| "personal".to_string());
    if !matches!(ws_type.as_str(), "personal" | "team") {
        return Err(AppError::BadRequest("Type must be 'personal' or 'team'".into()));
    }

    let invite_code: Option<String> = if ws_type == "team" {
        Some(generate_invite_code())
    } else {
        None
    };

    let r = sqlx::query_as::<_, (String, String, Option<String>, String, String, String, Option<String>, String, String)>(
        r#"INSERT INTO workspaces (name, description, owner_id, visibility, type, invite_code)
           VALUES ($1, $2, $3, $4, $5, $6)
           RETURNING id, name, description, owner_id, visibility, COALESCE(type, 'personal'),
                     invite_code, CAST(created_at AS TEXT), CAST(updated_at AS TEXT)"#,
    )
    .bind(&name)
    .bind(&req.description)
    .bind(auth.id.to_string())
    .bind(&visibility)
    .bind(&ws_type)
    .bind(&invite_code)
    .fetch_one(&state.pool)
    .await?;

    let ws_id = compat::parse_uuid(&r.0).map_err(|e| AppError::Internal(e.into()))?;

    if ws_type == "team" {
        sqlx::query(
            "INSERT INTO workspace_members (workspace_id, user_id, role) VALUES ($1, $2, 'owner')
             ON CONFLICT (workspace_id, user_id) DO UPDATE SET role = 'owner'",
        )
        .bind(ws_id.to_string())
        .bind(auth.id.to_string())
        .execute(&state.pool)
        .await?;
    }

    let ws = WorkspaceResponse {
        id: ws_id,
        name: r.1,
        description: r.2,
        owner_id: compat::parse_uuid(&r.3).map_err(|e| AppError::Internal(e.into()))?,
        visibility: r.4,
        ws_type: r.5,
        invite_code: r.6,
        created_at: r.7,
        updated_at: r.8,
    };

    Ok((axum::http::StatusCode::CREATED, Json(ws)))
}

async fn get_one(
    auth: AuthUser,
    State(state): State<AppState>,
    Path(id): Path<Uuid>,
) -> Result<Json<WorkspaceResponse>, AppError> {
    let r = sqlx::query_as::<_, (String, String, Option<String>, String, String, String, Option<String>, String, String)>(
        r#"
        SELECT w.id, w.name, w.description, w.owner_id, w.visibility,
               COALESCE(w.type, 'personal'), w.invite_code,
               CAST(w.created_at AS TEXT), CAST(w.updated_at AS TEXT)
        FROM workspaces w
        WHERE w.id = $1
          AND (w.owner_id = $2
               OR w.id IN (SELECT workspace_id FROM workspace_members WHERE user_id = $2)
               OR w.visibility = 'public')
        "#,
    )
    .bind(id.to_string())
    .bind(auth.id.to_string())
    .fetch_optional(&state.pool)
    .await?
    .ok_or_else(|| AppError::NotFound("Workspace not found".into()))?;

    Ok(Json(WorkspaceResponse {
        id: compat::parse_uuid(&r.0).map_err(|e| AppError::Internal(e.into()))?,
        name: r.1,
        description: r.2,
        owner_id: compat::parse_uuid(&r.3).map_err(|e| AppError::Internal(e.into()))?,
        visibility: r.4,
        ws_type: r.5,
        invite_code: r.6,
        created_at: r.7,
        updated_at: r.8,
    }))
}

async fn update(
    auth: AuthUser,
    State(state): State<AppState>,
    Path(id): Path<Uuid>,
    Json(req): Json<UpdateWorkspaceRequest>,
) -> Result<Json<WorkspaceResponse>, AppError> {
    let existing = sqlx::query_as::<_, (String, Option<String>, String)>(
        "SELECT name, description, visibility FROM workspaces WHERE id = $1 AND owner_id = $2",
    )
    .bind(id.to_string())
    .bind(auth.id.to_string())
    .fetch_optional(&state.pool)
    .await?
    .ok_or_else(|| AppError::NotFound("Workspace not found or not owned by you".into()))?;

    let name = req.name.map(|n| n.trim().to_string()).unwrap_or(existing.0);
    if name.is_empty() {
        return Err(AppError::BadRequest("Name cannot be empty".into()));
    }
    let description = req.description.or(existing.1);
    let visibility = req.visibility.unwrap_or(existing.2);
    if !matches!(visibility.as_str(), "private" | "public") {
        return Err(AppError::BadRequest("Visibility must be 'private' or 'public'".into()));
    }

    let r = sqlx::query_as::<_, (String, String, Option<String>, String, String, String, Option<String>, String, String)>(
        r#"UPDATE workspaces SET name = $1, description = $2, visibility = $3 WHERE id = $4
           RETURNING id, name, description, owner_id, visibility, COALESCE(type, 'personal'),
                     invite_code, CAST(created_at AS TEXT), CAST(updated_at AS TEXT)"#,
    )
    .bind(&name)
    .bind(&description)
    .bind(&visibility)
    .bind(id.to_string())
    .fetch_one(&state.pool)
    .await?;

    Ok(Json(WorkspaceResponse {
        id: compat::parse_uuid(&r.0).map_err(|e| AppError::Internal(e.into()))?,
        name: r.1,
        description: r.2,
        owner_id: compat::parse_uuid(&r.3).map_err(|e| AppError::Internal(e.into()))?,
        visibility: r.4,
        ws_type: r.5,
        invite_code: r.6,
        created_at: r.7,
        updated_at: r.8,
    }))
}

async fn remove(
    auth: AuthUser,
    State(state): State<AppState>,
    Path(id): Path<Uuid>,
) -> Result<axum::http::StatusCode, AppError> {
    let result = sqlx::query("DELETE FROM workspaces WHERE id = $1 AND owner_id = $2")
        .bind(id.to_string())
        .bind(auth.id.to_string())
        .execute(&state.pool)
        .await?;

    if result.rows_affected() == 0 {
        return Err(AppError::NotFound(
            "Workspace not found or not owned by you".into(),
        ));
    }

    Ok(axum::http::StatusCode::NO_CONTENT)
}

async fn join_workspace(
    auth: AuthUser,
    State(state): State<AppState>,
    Json(req): Json<JoinWorkspaceRequest>,
) -> Result<Json<WorkspaceResponse>, AppError> {
    let code = req.invite_code.trim().to_uppercase();
    if code.is_empty() {
        return Err(AppError::BadRequest("Invite code is required".into()));
    }

    let ws = sqlx::query_as::<_, (String, String, Option<String>, String, String, String, Option<String>, String, String)>(
        r#"
        SELECT id, name, description, owner_id, visibility,
               COALESCE(type, 'personal'), invite_code,
               CAST(created_at AS TEXT), CAST(updated_at AS TEXT)
        FROM workspaces
        WHERE invite_code = $1 AND COALESCE(type, 'personal') = 'team'
        "#,
    )
    .bind(&code)
    .fetch_optional(&state.pool)
    .await?
    .ok_or_else(|| AppError::NotFound("Invalid invite code".into()))?;

    let ws_id_str = &ws.0;

    let existing = sqlx::query_scalar::<_, i64>(
        "SELECT COUNT(*) FROM workspace_members WHERE workspace_id = $1 AND user_id = $2",
    )
    .bind(ws_id_str)
    .bind(auth.id.to_string())
    .fetch_one(&state.pool)
    .await?;

    if existing > 0 {
        return Err(AppError::BadRequest("You are already a member of this workspace".into()));
    }

    let owner_id_str = &ws.3;
    if auth.id.to_string() == *owner_id_str {
        return Err(AppError::BadRequest("You are the owner of this workspace".into()));
    }

    sqlx::query(
        "INSERT INTO workspace_members (workspace_id, user_id, role, invited_by) VALUES ($1, $2, 'viewer', $2)",
    )
    .bind(ws_id_str)
    .bind(auth.id.to_string())
    .execute(&state.pool)
    .await?;

    Ok(Json(WorkspaceResponse {
        id: compat::parse_uuid(&ws.0).map_err(|e| AppError::Internal(e.into()))?,
        name: ws.1,
        description: ws.2,
        owner_id: compat::parse_uuid(&ws.3).map_err(|e| AppError::Internal(e.into()))?,
        visibility: ws.4,
        ws_type: ws.5,
        invite_code: ws.6,
        created_at: ws.7,
        updated_at: ws.8,
    }))
}

async fn regenerate_invite_code(
    auth: AuthUser,
    State(state): State<AppState>,
    Path(id): Path<Uuid>,
) -> Result<Json<serde_json::Value>, AppError> {
    let owner_check: i64 = sqlx::query_scalar(
        "SELECT COUNT(*) FROM workspaces WHERE id = $1 AND owner_id = $2 AND COALESCE(type, 'personal') = 'team'",
    )
    .bind(id.to_string())
    .bind(auth.id.to_string())
    .fetch_one(&state.pool)
    .await?;

    if owner_check == 0 {
        return Err(AppError::Forbidden(
            "Only team workspace owner can regenerate invite code".into(),
        ));
    }

    let new_code = generate_invite_code();
    sqlx::query("UPDATE workspaces SET invite_code = $1 WHERE id = $2")
        .bind(&new_code)
        .bind(id.to_string())
        .execute(&state.pool)
        .await?;

    Ok(Json(serde_json::json!({
        "invite_code": new_code
    })))
}

async fn transfer_ownership(
    auth: AuthUser,
    State(state): State<AppState>,
    Path(id): Path<Uuid>,
    Json(req): Json<TransferOwnershipRequest>,
) -> Result<Json<serde_json::Value>, AppError> {
    let owner_check: i64 = sqlx::query_scalar(
        "SELECT COUNT(*) FROM workspaces WHERE id = $1 AND owner_id = $2",
    )
    .bind(id.to_string())
    .bind(auth.id.to_string())
    .fetch_one(&state.pool)
    .await?;

    if owner_check == 0 {
        return Err(AppError::Forbidden(
            "Only the workspace owner can transfer ownership".into(),
        ));
    }

    let new_owner_id = compat::parse_uuid(&req.new_owner_id)
        .map_err(|_| AppError::BadRequest("Invalid new_owner_id".into()))?;

    let member_check: i64 = sqlx::query_scalar(
        "SELECT COUNT(*) FROM workspace_members WHERE workspace_id = $1 AND user_id = $2",
    )
    .bind(id.to_string())
    .bind(new_owner_id.to_string())
    .fetch_one(&state.pool)
    .await?;

    if member_check == 0 {
        return Err(AppError::BadRequest(
            "New owner must be an existing member of the workspace".into(),
        ));
    }

    sqlx::query("UPDATE workspaces SET owner_id = $1 WHERE id = $2")
        .bind(new_owner_id.to_string())
        .bind(id.to_string())
        .execute(&state.pool)
        .await?;

    sqlx::query(
        "UPDATE workspace_members SET role = 'owner' WHERE workspace_id = $1 AND user_id = $2",
    )
    .bind(id.to_string())
    .bind(new_owner_id.to_string())
    .execute(&state.pool)
    .await?;

    sqlx::query(
        "UPDATE workspace_members SET role = 'admin' WHERE workspace_id = $1 AND user_id = $2",
    )
    .bind(id.to_string())
    .bind(auth.id.to_string())
    .execute(&state.pool)
    .await?;

    Ok(Json(serde_json::json!({
        "status": "ownership_transferred",
        "new_owner_id": new_owner_id
    })))
}

#[derive(Deserialize)]
struct TransferOwnershipRequest {
    new_owner_id: String,
}
