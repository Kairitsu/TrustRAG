use sqlx::sqlite::{SqliteConnectOptions, SqlitePoolOptions};
use sqlx::{Executor, Row, SqlitePool};
use std::str::FromStr;
use std::time::Duration;

pub const CURRENT_SCHEMA_VERSION: i32 = 5;

pub async fn create_pool(database_url: &str) -> anyhow::Result<SqlitePool> {
    let options = SqliteConnectOptions::from_str(database_url)?
        .create_if_missing(true)
        .journal_mode(sqlx::sqlite::SqliteJournalMode::Wal)
        .synchronous(sqlx::sqlite::SqliteSynchronous::Normal)
        .busy_timeout(Duration::from_secs(30));

    let pool = SqlitePoolOptions::new()
        .max_connections(5)
        .acquire_timeout(Duration::from_secs(10))
        .connect_with(options)
        .await?;

    sqlx::query("PRAGMA foreign_keys = ON")
        .execute(&pool)
        .await?;

    Ok(pool)
}

pub async fn get_schema_version(pool: &SqlitePool) -> anyhow::Result<i32> {
    let row = sqlx::query("PRAGMA user_version")
        .fetch_one(pool)
        .await?;
    let version: i32 = row.try_get(0)?;
    Ok(version)
}

pub async fn set_schema_version(pool: &SqlitePool, version: i32) -> anyhow::Result<()> {
    pool.execute(sqlx::raw_sql(&format!("PRAGMA user_version = {}", version)))
        .await?;
    Ok(())
}

pub async fn run_migrations(pool: &SqlitePool) -> anyhow::Result<()> {
    let current = get_schema_version(pool).await?;
    tracing::info!(current_version = current, target_version = CURRENT_SCHEMA_VERSION, "Checking SQLite schema version");

    if current == 0 {
        let has_tables = sqlx::query("SELECT name FROM sqlite_master WHERE type='table' AND name='users'")
            .fetch_optional(pool)
            .await?;

        if has_tables.is_some() {
            tracing::info!("Existing database without version tracking detected, running incremental migrations from v1");
            migrate_v1_to_v2(pool).await?;
            set_schema_version(pool, CURRENT_SCHEMA_VERSION).await?;
        } else {
            let sql = include_str!("../../migrations_sqlite/init.sql");
            pool.execute(sqlx::raw_sql(sql)).await?;
            set_schema_version(pool, CURRENT_SCHEMA_VERSION).await?;
            tracing::info!(version = CURRENT_SCHEMA_VERSION, "Fresh SQLite database initialized");
        }
    } else if current < CURRENT_SCHEMA_VERSION {
        for v in current..CURRENT_SCHEMA_VERSION {
            match v {
                1 => migrate_v1_to_v2(pool).await?,
                2 => migrate_v2_to_v3(pool).await?,
                3 => migrate_v3_to_v4(pool).await?,
                4 => migrate_v4_to_v5(pool).await?,
                _ => tracing::warn!(version = v, "No migration handler for this version step"),
            }
        }
        set_schema_version(pool, CURRENT_SCHEMA_VERSION).await?;
        tracing::info!(from = current, to = CURRENT_SCHEMA_VERSION, "SQLite schema migrated");
    } else {
        tracing::info!(version = current, "SQLite schema is up to date");
    }

    Ok(())
}

async fn migrate_v1_to_v2(pool: &SqlitePool) -> anyhow::Result<()> {
    tracing::info!("Running migration v1 -> v2");

    let stmts = vec![
        "ALTER TABLE embedding_configs ADD COLUMN batch_size INTEGER NOT NULL DEFAULT 10",
    ];

    for stmt in stmts {
        match pool.execute(sqlx::raw_sql(stmt)).await {
            Ok(_) => tracing::debug!(stmt = stmt, "Migration statement executed"),
            Err(e) => {
                let err_str = e.to_string();
                if err_str.contains("duplicate column") || err_str.contains("already exists") {
                    tracing::debug!(stmt = stmt, "Column already exists, skipping");
                } else {
                    tracing::warn!(stmt = stmt, error = %e, "Migration statement failed (non-fatal)");
                }
            }
        }
    }

    let check = sqlx::query(
        "SELECT sql FROM sqlite_master WHERE type='table' AND name='documents'"
    )
    .fetch_optional(pool)
    .await?;

    if let Some(row) = check {
        let create_sql: String = row.try_get(0)?;
        if !create_sql.contains("embedding_failed") {
            tracing::info!("Updating documents processing_status CHECK constraint for embedding_failed");
            tracing::warn!("SQLite does not support ALTER CHECK constraint; \
                           embedding_failed status will be handled at the application level");
        }
    }

    Ok(())
}

async fn migrate_v2_to_v3(pool: &SqlitePool) -> anyhow::Result<()> {
    tracing::info!("Running migration v2 -> v3: add rerank_configs table");

    let sql = r#"
        CREATE TABLE IF NOT EXISTS rerank_configs (
            id              TEXT PRIMARY KEY DEFAULT (lower(hex(randomblob(4)) || '-' || hex(randomblob(2)) || '-4' || substr(hex(randomblob(2)),2) || '-' || substr('89ab',abs(random()) % 4 + 1, 1) || substr(hex(randomblob(2)),2) || '-' || hex(randomblob(6)))),
            workspace_id    TEXT REFERENCES workspaces(id) ON DELETE CASCADE,
            user_id         TEXT NOT NULL REFERENCES users(id) ON DELETE CASCADE,
            name            TEXT NOT NULL,
            provider        TEXT NOT NULL CHECK (provider IN ('jina', 'cohere', 'openai', 'custom')),
            api_base_url    TEXT NOT NULL,
            api_key_enc     TEXT,
            model_name      TEXT NOT NULL,
            top_n           INTEGER NOT NULL DEFAULT 5,
            is_default      INTEGER DEFAULT 0,
            created_at      TEXT NOT NULL DEFAULT (strftime('%Y-%m-%dT%H:%M:%fZ', 'now')),
            updated_at      TEXT NOT NULL DEFAULT (strftime('%Y-%m-%dT%H:%M:%fZ', 'now'))
        )
    "#;

    pool.execute(sqlx::raw_sql(sql)).await?;

    let idx_stmts = vec![
        "CREATE INDEX IF NOT EXISTS idx_rerank_configs_user ON rerank_configs (user_id)",
        "CREATE INDEX IF NOT EXISTS idx_rerank_configs_workspace ON rerank_configs (workspace_id)",
    ];
    for stmt in idx_stmts {
        let _ = pool.execute(sqlx::raw_sql(stmt)).await;
    }

    Ok(())
}

async fn migrate_v3_to_v4(pool: &SqlitePool) -> anyhow::Result<()> {
    tracing::info!("Running migration v3 -> v4: add rerank extra params");

    let stmts = vec![
        "ALTER TABLE rerank_configs ADD COLUMN initial_recall_k INTEGER NOT NULL DEFAULT 30",
        "ALTER TABLE rerank_configs ADD COLUMN fallback_enabled INTEGER NOT NULL DEFAULT 1",
    ];

    for stmt in stmts {
        match pool.execute(sqlx::raw_sql(stmt)).await {
            Ok(_) => tracing::debug!(stmt = stmt, "Migration statement executed"),
            Err(e) => {
                let err_str = e.to_string();
                if err_str.contains("duplicate column") || err_str.contains("already exists") {
                    tracing::debug!(stmt = stmt, "Column already exists, skipping");
                } else {
                    tracing::warn!(stmt = stmt, error = %e, "Migration statement failed (non-fatal)");
                }
            }
        }
    }

    Ok(())
}

async fn migrate_v4_to_v5(pool: &SqlitePool) -> anyhow::Result<()> {
    tracing::info!("Running migration v4 -> v5: add rerank timeout_secs");

    let stmt = "ALTER TABLE rerank_configs ADD COLUMN timeout_secs INTEGER NOT NULL DEFAULT 30";
    match pool.execute(sqlx::raw_sql(stmt)).await {
        Ok(_) => tracing::debug!(stmt = stmt, "Migration statement executed"),
        Err(e) => {
            let err_str = e.to_string();
            if err_str.contains("duplicate column") || err_str.contains("already exists") {
                tracing::debug!(stmt = stmt, "Column already exists, skipping");
            } else {
                tracing::warn!(stmt = stmt, error = %e, "Migration statement failed (non-fatal)");
            }
        }
    }

    Ok(())
}

pub async fn validate_token_user(pool: &SqlitePool, user_id: &str) -> anyhow::Result<bool> {
    let row = sqlx::query("SELECT COUNT(*) as cnt FROM users WHERE id = $1 AND status = 'active'")
        .bind(user_id)
        .fetch_one(pool)
        .await?;
    let count: i32 = row.try_get(0)?;
    Ok(count > 0)
}

pub async fn backup_database(data_dir: &str) -> anyhow::Result<String> {
    let db_path = format!("{}/trustrag.db", data_dir);
    let timestamp = chrono::Utc::now().format("%Y%m%d_%H%M%S");
    let backup_path = format!("{}/trustrag_backup_{}.db", data_dir, timestamp);

    if std::path::Path::new(&db_path).exists() {
        std::fs::copy(&db_path, &backup_path)?;
        tracing::info!(backup = %backup_path, "Database backed up");
        Ok(backup_path)
    } else {
        anyhow::bail!("Database file not found at {}", db_path)
    }
}
