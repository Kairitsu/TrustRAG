use axum::{
    extract::{Path, State},
    http::StatusCode,
    routing::get,
    Json, Router,
};
use serde::{Deserialize, Serialize};
use uuid::Uuid;

use crate::auth::middleware::AuthUser;
use crate::db::compat;
use crate::error::AppError;

use super::AppState;

/// Returns the user's role in a workspace, considering both workspace_members
/// table and workspace ownership. Returns None if user has no access.
pub async fn get_user_workspace_role(
    pool: &crate::db::DbPool,
    ws_id: Uuid,
    user_id: Uuid,
) -> Result<Option<String>, AppError> {
    let role = sqlx::query_scalar::<_, String>(
        "SELECT wm.role FROM workspace_members wm WHERE wm.workspace_id = $1 AND wm.user_id = $2",
    )
    .bind(ws_id.to_string())
    .bind(user_id.to_string())
    .fetch_optional(pool)
    .await?;

    if role.is_some() {
        return Ok(role);
    }

    let is_owner: i64 = sqlx::query_scalar(
        "SELECT COUNT(*) FROM workspaces WHERE id = $1 AND owner_id = $2",
    )
    .bind(ws_id.to_string())
    .bind(user_id.to_string())
    .fetch_one(pool)
    .await?;

    if is_owner > 0 {
        return Ok(Some("owner".to_string()));
    }

    Ok(None)
}

/// Check if a user has at least admin-level access (owner or admin) in a workspace.
/// Viewers and editors cannot manage sensitive configs like API keys.
pub async fn require_admin_access(
    pool: &crate::db::DbPool,
    ws_id: Uuid,
    user_id: Uuid,
) -> Result<String, AppError> {
    let role = get_user_workspace_role(pool, ws_id, user_id).await?;
    match role {
        Some(r) if r == "owner" || r == "admin" => Ok(r),
        Some(_) => Err(AppError::Forbidden(
            "Admin or owner access required for this operation".into(),
        )),
        None => Err(AppError::NotFound("Workspace not found or no access".into())),
    }
}

pub fn router() -> Router<AppState> {
    Router::new()
        .route(
            "/workspaces/{ws_id}/members",
            get(list_members).post(add_member),
        )
        .route(
            "/workspaces/{ws_id}/members/{member_id}",
            axum::routing::put(update_member_role).delete(remove_member),
        )
}

#[derive(Serialize)]
struct MemberResponse {
    id: Uuid,
    workspace_id: Uuid,
    user_id: Uuid,
    display_name: String,
    role: String,
    created_at: String,
}

#[derive(Deserialize)]
struct AddMemberRequest {
    email: String,
    role: Option<String>,
}

#[derive(Deserialize)]
struct UpdateRoleRequest {
    role: String,
}

async fn check_owner_or_editor(
    pool: &crate::db::DbPool,
    ws_id: Uuid,
    user_id: Uuid,
) -> Result<String, AppError> {
    let role = sqlx::query_scalar::<_, String>(
        "SELECT wm.role FROM workspace_members wm
         WHERE wm.workspace_id = $1 AND wm.user_id = $2",
    )
    .bind(ws_id.to_string())
    .bind(user_id.to_string())
    .fetch_optional(pool)
    .await?;

    if let Some(ref r) = role {
        if r == "owner" || r == "editor" {
            return Ok(r.clone());
        }
    }

    let creator_count: i32 = sqlx::query_scalar(
        "SELECT COUNT(*) FROM workspaces WHERE id = $1 AND owner_id = $2",
    )
    .bind(ws_id.to_string())
    .bind(user_id.to_string())
    .fetch_one(pool)
    .await?;

    if creator_count > 0 {
        return Ok("owner".to_string());
    }

    Err(AppError::Forbidden(
        "You do not have permission to manage this workspace".into(),
    ))
}

async fn check_workspace_access(
    pool: &crate::db::DbPool,
    ws_id: Uuid,
    user_id: Uuid,
) -> Result<(), AppError> {
    let access_count: i32 = sqlx::query_scalar(
        r#"
        SELECT COUNT(*) FROM workspaces
        WHERE id = $1
          AND (owner_id = $2
               OR id IN (SELECT workspace_id FROM workspace_members WHERE user_id = $2)
               OR visibility = 'public')
        "#,
    )
    .bind(ws_id.to_string())
    .bind(user_id.to_string())
    .fetch_one(pool)
    .await?;

    if access_count == 0 {
        return Err(AppError::NotFound("Workspace not found".into()));
    }
    Ok(())
}

async fn list_members(
    State(state): State<AppState>,
    auth: AuthUser,
    Path(ws_id): Path<Uuid>,
) -> Result<Json<Vec<MemberResponse>>, AppError> {
    check_workspace_access(&state.pool, ws_id, auth.id).await?;
    let rows = sqlx::query_as::<_, (String, String, String, String, String, String)>(
        "SELECT wm.id, wm.workspace_id, wm.user_id, u.display_name, wm.role, CAST(wm.created_at AS TEXT)
         FROM workspace_members wm
         JOIN users u ON wm.user_id = u.id
         WHERE wm.workspace_id = $1
         ORDER BY wm.created_at",
    )
    .bind(ws_id.to_string())
    .fetch_all(&state.pool)
    .await?;

    let mut members = Vec::with_capacity(rows.len());
    for r in rows {
        members.push(MemberResponse {
            id: compat::parse_uuid(&r.0).map_err(|e| AppError::Internal(e.into()))?,
            workspace_id: compat::parse_uuid(&r.1).map_err(|e| AppError::Internal(e.into()))?,
            user_id: compat::parse_uuid(&r.2).map_err(|e| AppError::Internal(e.into()))?,
            display_name: r.3,
            role: r.4,
            created_at: r.5,
        });
    }

    Ok(Json(members))
}

async fn add_member(
    State(state): State<AppState>,
    auth: AuthUser,
    Path(ws_id): Path<Uuid>,
    Json(req): Json<AddMemberRequest>,
) -> Result<(StatusCode, Json<MemberResponse>), AppError> {
    check_owner_or_editor(&state.pool, ws_id, auth.id).await?;

    let email = req.email.trim().to_lowercase();
    if email.is_empty() || !email.contains('@') {
        return Err(AppError::BadRequest("Invalid email address".into()));
    }

    let target_user_id_str = sqlx::query_scalar::<_, String>(
        "SELECT id FROM users WHERE email = $1",
    )
    .bind(&email)
    .fetch_optional(&state.pool)
    .await?
    .ok_or_else(|| AppError::NotFound(format!("User with email '{}' not found", email)))?;

    let target_user_id: Uuid = compat::parse_uuid(&target_user_id_str)
        .map_err(|e| AppError::Internal(e.into()))?;

    let role = req.role.unwrap_or_else(|| "viewer".to_string());
    if !["owner", "editor", "viewer"].contains(&role.as_str()) {
        return Err(AppError::BadRequest(format!("Invalid role: {}", role)));
    }

    tracing::info!(
        workspace_id = %ws_id,
        target_user = %target_user_id,
        role = %role,
        invited_by = %auth.id,
        "Adding workspace member"
    );

    let r = sqlx::query_as::<_, (String, String, String, String, String, String)>(
        "INSERT INTO workspace_members (workspace_id, user_id, role, invited_by)
         VALUES ($1, $2, $3, $4)
         ON CONFLICT (workspace_id, user_id) DO UPDATE SET role = $3
         RETURNING id, workspace_id, user_id,
                   (SELECT display_name FROM users WHERE id = workspace_members.user_id) as display_name,
                   role, CAST(created_at AS TEXT)",
    )
    .bind(ws_id.to_string())
    .bind(target_user_id.to_string())
    .bind(&role)
    .bind(auth.id.to_string())
    .fetch_one(&state.pool)
    .await?;

    Ok((StatusCode::CREATED, Json(MemberResponse {
        id: compat::parse_uuid(&r.0).map_err(|e| AppError::Internal(e.into()))?,
        workspace_id: compat::parse_uuid(&r.1).map_err(|e| AppError::Internal(e.into()))?,
        user_id: compat::parse_uuid(&r.2).map_err(|e| AppError::Internal(e.into()))?,
        display_name: r.3,
        role: r.4,
        created_at: r.5,
    })))
}

async fn update_member_role(
    State(state): State<AppState>,
    auth: AuthUser,
    Path((ws_id, member_id)): Path<(Uuid, Uuid)>,
    Json(req): Json<UpdateRoleRequest>,
) -> Result<Json<serde_json::Value>, AppError> {
    check_owner_or_editor(&state.pool, ws_id, auth.id).await?;

    if !["owner", "editor", "viewer"].contains(&req.role.as_str()) {
        return Err(AppError::BadRequest(format!("Invalid role: {}", req.role)));
    }

    let result = sqlx::query(
        "UPDATE workspace_members SET role = $1 WHERE id = $2 AND workspace_id = $3",
    )
    .bind(&req.role)
    .bind(member_id.to_string())
    .bind(ws_id.to_string())
    .execute(&state.pool)
    .await?;

    if result.rows_affected() == 0 {
        return Err(AppError::NotFound("Member not found".into()));
    }

    Ok(Json(serde_json::json!({"status": "updated"})))
}

async fn remove_member(
    State(state): State<AppState>,
    auth: AuthUser,
    Path((ws_id, member_id)): Path<(Uuid, Uuid)>,
) -> Result<StatusCode, AppError> {
    check_owner_or_editor(&state.pool, ws_id, auth.id).await?;

    let result = sqlx::query(
        "DELETE FROM workspace_members WHERE id = $1 AND workspace_id = $2",
    )
    .bind(member_id.to_string())
    .bind(ws_id.to_string())
    .execute(&state.pool)
    .await?;

    if result.rows_affected() == 0 {
        return Err(AppError::NotFound("Member not found".into()));
    }

    Ok(StatusCode::NO_CONTENT)
}
