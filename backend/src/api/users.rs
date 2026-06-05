use axum::{extract::State, routing::{get, post, put}, Json, Router};
use serde::{Deserialize, Serialize};
use uuid::Uuid;

use argon2::{
    password_hash::{rand_core::OsRng, PasswordHash, PasswordHasher, PasswordVerifier, SaltString},
    Argon2,
};

use crate::auth::jwt::create_token;
use crate::auth::middleware::AuthUser;
use crate::error::AppError;

use super::AppState;

#[derive(Deserialize)]
pub struct RegisterRequest {
    pub email: String,
    pub password: String,
    pub display_name: String,
}

#[derive(Deserialize)]
pub struct LoginRequest {
    pub email: String,
    pub password: String,
}

#[derive(Serialize)]
pub struct AuthResponse {
    pub access_token: String,
    pub expires_in: i64,
    pub user: UserResponse,
}

#[derive(Serialize)]
pub struct UserResponse {
    pub id: Uuid,
    pub email: String,
    pub display_name: String,
    pub role: String,
}

#[derive(Deserialize)]
pub struct UpdateProfileRequest {
    pub display_name: Option<String>,
}

#[derive(Deserialize)]
pub struct ChangePasswordRequest {
    pub current_password: String,
    pub new_password: String,
}

#[derive(Deserialize)]
pub struct DeleteAccountRequest {
    pub password: String,
    pub confirm_email: String,
}

pub fn router() -> Router<AppState> {
    Router::new()
        .route("/auth/register", post(register))
        .route("/auth/login", post(login))
        .route(
            "/auth/me",
            get(me).put(update_profile).delete(delete_account),
        )
        .route("/auth/me/password", put(change_password))
}

async fn register(
    State(state): State<AppState>,
    Json(req): Json<RegisterRequest>,
) -> Result<(axum::http::StatusCode, Json<AuthResponse>), AppError> {
    let email = req.email.trim().to_lowercase();
    let display_name = req.display_name.trim().to_string();
    if email.is_empty() || !email.contains('@') || !email.contains('.') || req.password.len() < 8 {
        return Err(AppError::BadRequest(
            "Valid email required and password must be at least 8 characters".into(),
        ));
    }
    if display_name.is_empty() {
        return Err(AppError::BadRequest("Display name is required".into()));
    }

    let existing = sqlx::query_scalar::<_, i64>("SELECT COUNT(*) FROM users WHERE email = $1")
        .bind(&email)
        .fetch_one(&state.pool)
        .await?;

    if existing > 0 {
        return Err(AppError::Conflict("Email already registered".into()));
    }

    let salt = SaltString::generate(&mut OsRng);
    let password_hash = Argon2::default()
        .hash_password(req.password.as_bytes(), &salt)
        .map_err(|e| AppError::Internal(anyhow::anyhow!("Hash error: {e}")))?
        .to_string();

    let row = sqlx::query_as::<_, (String, String, String, String)>(
        "INSERT INTO users (email, password_hash, display_name) VALUES ($1, $2, $3) RETURNING id, email, display_name, role",
    )
    .bind(&email)
    .bind(&password_hash)
    .bind(&display_name)
    .fetch_one(&state.pool)
    .await?;

    let user_id: Uuid = row.0.parse()
        .map_err(|e| AppError::Internal(anyhow::anyhow!("UUID parse error: {e}")))?;

    sqlx::query(
        r#"INSERT INTO workspaces (name, description, owner_id, visibility, type)
           VALUES ('个人空间', NULL, $1, 'private', 'personal')"#,
    )
    .bind(user_id.to_string())
    .execute(&state.pool)
    .await?;

    let expiry_hours: i64 = 168; // 7 days
    let token = create_token(user_id, &row.1, &row.3, &state.jwt_secret, expiry_hours)
        .map_err(|e| AppError::Internal(anyhow::anyhow!("Token error: {e}")))?;

    Ok((
        axum::http::StatusCode::CREATED,
        Json(AuthResponse {
            access_token: token,
            expires_in: expiry_hours * 3600,
            user: UserResponse {
                id: user_id,
                email: row.1,
                display_name: row.2,
                role: row.3,
            },
        }),
    ))
}

async fn login(
    State(state): State<AppState>,
    Json(req): Json<LoginRequest>,
) -> Result<Json<AuthResponse>, AppError> {
    let email = req.email.trim().to_lowercase();
    let row = sqlx::query_as::<_, (String, String, String, String, String)>(
        "SELECT id, email, password_hash, display_name, role FROM users WHERE email = $1 AND status = 'active'",
    )
    .bind(&email)
    .fetch_optional(&state.pool)
    .await?
    .ok_or_else(|| AppError::Auth("Invalid email or password".into()))?;

    let user_id: Uuid = row.0.parse()
        .map_err(|e| AppError::Internal(anyhow::anyhow!("UUID parse error: {e}")))?;
    let (email, stored_hash, display_name, role) = (row.1, row.2, row.3, row.4);

    let parsed_hash = PasswordHash::new(&stored_hash)
        .map_err(|e| AppError::Internal(anyhow::anyhow!("Hash parse error: {e}")))?;

    Argon2::default()
        .verify_password(req.password.as_bytes(), &parsed_hash)
        .map_err(|_| AppError::Auth("Invalid email or password".into()))?;

    sqlx::query("UPDATE users SET last_login_at = strftime('%Y-%m-%dT%H:%M:%fZ', 'now') WHERE id = $1")
        .bind(user_id.to_string())
        .execute(&state.pool)
        .await?;

    let expiry_hours: i64 = 168; // 7 days
    let token = create_token(user_id, &email, &role, &state.jwt_secret, expiry_hours)
        .map_err(|e| AppError::Internal(anyhow::anyhow!("Token error: {e}")))?;

    Ok(Json(AuthResponse {
        access_token: token,
        expires_in: expiry_hours * 3600,
        user: UserResponse {
            id: user_id,
            email,
            display_name,
            role,
        },
    }))
}

async fn me(
    auth: AuthUser,
    State(state): State<AppState>,
) -> Result<Json<UserResponse>, AppError> {
    let row = sqlx::query_as::<_, (String, String, String, String)>(
        "SELECT id, email, display_name, role FROM users WHERE id = $1 AND status = 'active'",
    )
    .bind(auth.id.to_string())
    .fetch_one(&state.pool)
    .await?;

    let user_id: Uuid = row.0.parse()
        .map_err(|e| AppError::Internal(anyhow::anyhow!("UUID parse error: {e}")))?;

    Ok(Json(UserResponse {
        id: user_id,
        email: row.1,
        display_name: row.2,
        role: row.3,
    }))
}

async fn update_profile(
    auth: AuthUser,
    State(state): State<AppState>,
    Json(req): Json<UpdateProfileRequest>,
) -> Result<Json<UserResponse>, AppError> {
    if let Some(name) = &req.display_name {
        let trimmed = name.trim();
        if trimmed.is_empty() {
            return Err(AppError::BadRequest("Display name cannot be empty".into()));
        }
        sqlx::query("UPDATE users SET display_name = $1 WHERE id = $2")
            .bind(trimmed)
            .bind(auth.id.to_string())
            .execute(&state.pool)
            .await?;
    }

    me(auth, State(state)).await
}

async fn change_password(
    auth: AuthUser,
    State(state): State<AppState>,
    Json(req): Json<ChangePasswordRequest>,
) -> Result<axum::http::StatusCode, AppError> {
    if req.new_password.len() < 8 {
        return Err(AppError::BadRequest(
            "Password must be at least 8 characters".into(),
        ));
    }

    let stored_hash = sqlx::query_scalar::<_, String>(
        "SELECT password_hash FROM users WHERE id = $1",
    )
    .bind(auth.id.to_string())
    .fetch_one(&state.pool)
    .await?;

    let parsed_hash = PasswordHash::new(&stored_hash)
        .map_err(|e| AppError::Internal(anyhow::anyhow!("Hash parse error: {e}")))?;

    Argon2::default()
        .verify_password(req.current_password.as_bytes(), &parsed_hash)
        .map_err(|_| AppError::Auth("Current password is incorrect".into()))?;

    let salt = SaltString::generate(&mut OsRng);
    let new_hash = Argon2::default()
        .hash_password(req.new_password.as_bytes(), &salt)
        .map_err(|e| AppError::Internal(anyhow::anyhow!("Hash error: {e}")))?
        .to_string();

    sqlx::query("UPDATE users SET password_hash = $1 WHERE id = $2")
        .bind(&new_hash)
        .bind(auth.id.to_string())
        .execute(&state.pool)
        .await?;

    Ok(axum::http::StatusCode::NO_CONTENT)
}

async fn delete_account(
    auth: AuthUser,
    State(state): State<AppState>,
    Json(req): Json<DeleteAccountRequest>,
) -> Result<axum::http::StatusCode, AppError> {
    let confirm_email = req.confirm_email.trim().to_lowercase();

    let row = sqlx::query_as::<_, (String, String, String)>(
        "SELECT email, password_hash, status FROM users WHERE id = $1",
    )
    .bind(auth.id.to_string())
    .fetch_optional(&state.pool)
    .await?
    .ok_or_else(|| AppError::NotFound("User not found".into()))?;

    let (email, stored_hash, status) = row;

    if status != "active" {
        return Err(AppError::Auth("Account is not active".into()));
    }

    if confirm_email != email.trim().to_lowercase() {
        return Err(AppError::BadRequest("Email confirmation does not match".into()));
    }

    let parsed_hash = PasswordHash::new(&stored_hash)
        .map_err(|e| AppError::Internal(anyhow::anyhow!("Hash parse error: {e}")))?;

    Argon2::default()
        .verify_password(req.password.as_bytes(), &parsed_hash)
        .map_err(|_| AppError::Auth("Invalid email or password".into()))?;

    crate::services::account_deletion::delete_user_account(
        &state.pool,
        &state.storage,
        auth.id,
    )
    .await?;

    Ok(axum::http::StatusCode::NO_CONTENT)
}
