use uuid::Uuid;

use crate::db::DbPool;
use crate::error::AppError;
use crate::services::storage::StorageService;

/// Permanently deletes a user, owned workspaces, and related server data.
pub async fn delete_user_account(
    pool: &DbPool,
    storage: &StorageService,
    user_id: Uuid,
) -> Result<(), AppError> {
    let user_id_str = user_id.to_string();

    let owned_workspaces: Vec<String> = sqlx::query_scalar::<_, String>(
        "SELECT id FROM workspaces WHERE owner_id = $1",
    )
    .bind(&user_id_str)
    .fetch_all(pool)
    .await?;

    for ws_id in &owned_workspaces {
        let prefix = format!("workspaces/{}/", ws_id);
        storage.delete_dir(&prefix).await.map_err(|e| {
            AppError::Internal(anyhow::anyhow!(
                "Failed to delete storage for workspace {}: {e}",
                ws_id
            ))
        })?;
    }

    let mut tx = pool.begin().await?;

    sqlx::query("UPDATE documents SET uploaded_by = NULL WHERE uploaded_by = $1")
        .bind(&user_id_str)
        .execute(&mut *tx)
        .await?;

    sqlx::query("UPDATE workspace_members SET invited_by = NULL WHERE invited_by = $1")
        .bind(&user_id_str)
        .execute(&mut *tx)
        .await?;

    sqlx::query("DELETE FROM review_comments WHERE author_id = $1")
        .bind(&user_id_str)
        .execute(&mut *tx)
        .await?;

    sqlx::query("UPDATE review_tasks SET assigned_to = NULL WHERE assigned_to = $1")
        .bind(&user_id_str)
        .execute(&mut *tx)
        .await?;

    sqlx::query("UPDATE review_tasks SET created_by = NULL WHERE created_by = $1")
        .bind(&user_id_str)
        .execute(&mut *tx)
        .await?;

    sqlx::query("DELETE FROM graph_generation_logs WHERE user_id = $1")
        .bind(&user_id_str)
        .execute(&mut *tx)
        .await?;

    sqlx::query("DELETE FROM workspaces WHERE owner_id = $1")
        .bind(&user_id_str)
        .execute(&mut *tx)
        .await?;

    sqlx::query("DELETE FROM users WHERE id = $1")
        .bind(&user_id_str)
        .execute(&mut *tx)
        .await?;

    tx.commit().await?;
    Ok(())
}

#[cfg(test)]
mod tests {
    #[test]
    fn workspace_prefix_format() {
        let ws_id = "550e8400-e29b-41d4-a716-446655440000";
        assert_eq!(
            format!("workspaces/{}/", ws_id),
            "workspaces/550e8400-e29b-41d4-a716-446655440000/"
        );
    }
}