use sqlx::sqlite::{SqliteConnectOptions, SqlitePoolOptions};
use sqlx::{Executor, Row, SqlitePool};
use std::str::FromStr;
use std::time::Duration;

pub const CURRENT_SCHEMA_VERSION: i32 = 11;

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
                5 => migrate_v5_to_v6(pool).await?,
                6 => migrate_v6_to_v7(pool).await?,
                7 => migrate_v7_to_v8(pool).await?,
                8 => migrate_v8_to_v9(pool).await?,
                9 => migrate_v9_to_v10(pool).await?,
                10 => migrate_v10_to_v11(pool).await?,
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

async fn migrate_v5_to_v6(pool: &SqlitePool) -> anyhow::Result<()> {
    tracing::info!("Running migration v5 -> v6: add workspace rerank_enabled");

    let stmt = "ALTER TABLE workspaces ADD COLUMN rerank_enabled INTEGER NOT NULL DEFAULT 1";
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

async fn migrate_v6_to_v7(pool: &SqlitePool) -> anyhow::Result<()> {
    tracing::info!("Running migration v6 -> v7: add graph_generation_logs table");

    let sql = r#"
        CREATE TABLE IF NOT EXISTS graph_generation_logs (
            id TEXT PRIMARY KEY,
            workspace_id TEXT NOT NULL,
            user_id TEXT NOT NULL,
            status TEXT NOT NULL DEFAULT 'running',
            total_documents INTEGER NOT NULL DEFAULT 0,
            processed_documents INTEGER NOT NULL DEFAULT 0,
            entities_created INTEGER NOT NULL DEFAULT 0,
            relations_created INTEGER NOT NULL DEFAULT 0,
            errors TEXT NOT NULL DEFAULT '[]',
            started_at TEXT NOT NULL DEFAULT (strftime('%Y-%m-%dT%H:%M:%fZ', 'now')),
            completed_at TEXT,
            FOREIGN KEY (workspace_id) REFERENCES workspaces(id)
        )
    "#;

    match pool.execute(sqlx::raw_sql(sql)).await {
        Ok(_) => tracing::debug!("graph_generation_logs table created"),
        Err(e) => {
            let err_str = e.to_string();
            if err_str.contains("already exists") {
                tracing::debug!("graph_generation_logs table already exists, skipping");
            } else {
                tracing::warn!(error = %e, "Failed to create graph_generation_logs table (non-fatal)");
            }
        }
    }

    Ok(())
}

async fn migrate_v8_to_v9(pool: &SqlitePool) -> anyhow::Result<()> {
    tracing::info!("Running migration v8 -> v9: add endpoint_mode columns");

    let add_column_stmts = vec![
        "ALTER TABLE model_configs ADD COLUMN endpoint_mode TEXT NOT NULL DEFAULT 'base_url'",
        "ALTER TABLE embedding_configs ADD COLUMN endpoint_mode TEXT NOT NULL DEFAULT 'base_url'",
        "ALTER TABLE rerank_configs ADD COLUMN endpoint_mode TEXT NOT NULL DEFAULT 'base_url'",
    ];

    for stmt in add_column_stmts {
        match pool.execute(sqlx::raw_sql(stmt)).await {
            Ok(_) => tracing::debug!(stmt, "Migration v8->v9 column added"),
            Err(e) => {
                let err_str = e.to_string();
                if err_str.contains("duplicate column") || err_str.contains("already exists") {
                    tracing::debug!(stmt, "Column already exists, skipping");
                } else {
                    tracing::warn!(error = %e, stmt, "Migration v8->v9 column add failed (non-fatal)");
                }
            }
        }
    }

    let migrate_stmts = vec![
        "UPDATE model_configs SET endpoint_mode = 'full_endpoint' WHERE api_base_url LIKE '%/chat/completions'",
        "UPDATE embedding_configs SET endpoint_mode = 'full_endpoint' WHERE api_base_url LIKE '%/embeddings'",
        "UPDATE rerank_configs SET endpoint_mode = 'full_endpoint' WHERE api_base_url LIKE '%/rerank' OR api_base_url LIKE '%/reranks'",
    ];

    for stmt in migrate_stmts {
        if let Err(e) = pool.execute(sqlx::raw_sql(stmt)).await {
            tracing::warn!(error = %e, stmt, "Migration v8->v9 data migration failed (non-fatal)");
        }
    }

    // Expand rerank provider CHECK to include dashscope (SQLite cannot ALTER CHECK constraints)
    let recreate_rerank = r#"
        CREATE TABLE IF NOT EXISTS rerank_configs_v9 (
            id              TEXT PRIMARY KEY,
            workspace_id    TEXT REFERENCES workspaces(id) ON DELETE CASCADE,
            user_id         TEXT NOT NULL REFERENCES users(id) ON DELETE CASCADE,
            name            TEXT NOT NULL,
            provider        TEXT NOT NULL CHECK (provider IN ('jina', 'cohere', 'openai', 'dashscope', 'custom')),
            api_base_url    TEXT NOT NULL,
            api_key_enc     TEXT,
            model_name      TEXT NOT NULL,
            endpoint_mode   TEXT NOT NULL DEFAULT 'base_url',
            top_n           INTEGER NOT NULL DEFAULT 5,
            initial_recall_k INTEGER NOT NULL DEFAULT 30,
            fallback_enabled INTEGER NOT NULL DEFAULT 1,
            timeout_secs    INTEGER NOT NULL DEFAULT 30,
            is_default      INTEGER DEFAULT 0,
            created_at      TEXT NOT NULL DEFAULT (strftime('%Y-%m-%dT%H:%M:%fZ', 'now')),
            updated_at      TEXT NOT NULL DEFAULT (strftime('%Y-%m-%dT%H:%M:%fZ', 'now'))
        );
        INSERT INTO rerank_configs_v9 (
            id, workspace_id, user_id, name, provider, api_base_url, api_key_enc, model_name,
            endpoint_mode, top_n, initial_recall_k, fallback_enabled, timeout_secs, is_default,
            created_at, updated_at
        )
        SELECT
            id, workspace_id, user_id, name, provider, api_base_url, api_key_enc, model_name,
            COALESCE(endpoint_mode, 'base_url'), top_n, initial_recall_k, fallback_enabled,
            timeout_secs, is_default, created_at, updated_at
        FROM rerank_configs;
        DROP TABLE rerank_configs;
        ALTER TABLE rerank_configs_v9 RENAME TO rerank_configs;
        CREATE INDEX IF NOT EXISTS idx_rerank_configs_user ON rerank_configs (user_id);
        CREATE INDEX IF NOT EXISTS idx_rerank_configs_workspace ON rerank_configs (workspace_id);
    "#;

    if let Err(e) = pool.execute(sqlx::raw_sql(recreate_rerank)).await {
        tracing::warn!(error = %e, "Migration v8->v9 rerank_configs recreation failed (non-fatal)");
    }

    Ok(())
}

async fn migrate_v7_to_v8(pool: &SqlitePool) -> anyhow::Result<()> {
    tracing::info!("Running migration v7 -> v8: add graph_layer to entities and entity_relations");

    let stmts = vec![
        "ALTER TABLE entities ADD COLUMN graph_layer TEXT NOT NULL DEFAULT 'knowledge'",
        "ALTER TABLE entity_relations ADD COLUMN graph_layer TEXT NOT NULL DEFAULT 'knowledge'",
        "CREATE INDEX IF NOT EXISTS idx_entities_layer ON entities(workspace_id, graph_layer)",
        "CREATE INDEX IF NOT EXISTS idx_entity_relations_layer ON entity_relations(workspace_id, graph_layer)",
    ];

    for stmt in stmts {
        match pool.execute(sqlx::raw_sql(stmt)).await {
            Ok(_) => tracing::debug!(stmt, "Migration v7->v8 statement OK"),
            Err(e) => {
                let err_str = e.to_string();
                if err_str.contains("duplicate column") || err_str.contains("already exists") {
                    tracing::debug!(stmt, "Column/index already exists, skipping");
                } else {
                    tracing::warn!(error = %e, stmt, "Migration v7->v8 statement failed (non-fatal)");
                }
            }
        }
    }

    Ok(())
}

async fn migrate_v9_to_v10(pool: &SqlitePool) -> anyhow::Result<()> {
    tracing::info!("Running migration v9 -> v10: knowledge graph v2 columns");

    let entity_cols = vec![
        "ALTER TABLE entities ADD COLUMN entity_key TEXT",
        "ALTER TABLE entities ADD COLUMN original_name TEXT",
        "ALTER TABLE entities ADD COLUMN display_name TEXT",
        "ALTER TABLE entities ADD COLUMN original_language TEXT",
        "ALTER TABLE entities ADD COLUMN aliases TEXT DEFAULT '[]'",
    ];
    for stmt in entity_cols {
        if let Err(e) = pool.execute(sqlx::raw_sql(stmt)).await {
            let err_str = e.to_string();
            if !err_str.contains("duplicate column") && !err_str.contains("already exists") {
                tracing::warn!(error = %e, stmt, "Migration v9->v10 entity column failed (non-fatal)");
            }
        }
    }

    let log_cols = vec![
        "ALTER TABLE graph_generation_logs ADD COLUMN target_language TEXT DEFAULT 'zh'",
        "ALTER TABLE graph_generation_logs ADD COLUMN job_type TEXT NOT NULL DEFAULT 'knowledge_batch'",
        "ALTER TABLE graph_generation_logs ADD COLUMN layer_type TEXT",
        "ALTER TABLE graph_generation_logs ADD COLUMN current_document_id TEXT",
        "ALTER TABLE graph_generation_logs ADD COLUMN current_document_title TEXT",
        "ALTER TABLE graph_generation_logs ADD COLUMN succeeded_documents INTEGER NOT NULL DEFAULT 0",
        "ALTER TABLE graph_generation_logs ADD COLUMN failed_documents INTEGER NOT NULL DEFAULT 0",
        "ALTER TABLE graph_generation_logs ADD COLUMN relations_llm_returned INTEGER NOT NULL DEFAULT 0",
        "ALTER TABLE graph_generation_logs ADD COLUMN relations_skipped_match INTEGER NOT NULL DEFAULT 0",
        "ALTER TABLE graph_generation_logs ADD COLUMN relations_skipped_duplicate INTEGER NOT NULL DEFAULT 0",
        "ALTER TABLE graph_generation_logs ADD COLUMN relations_db_failed INTEGER NOT NULL DEFAULT 0",
        "ALTER TABLE graph_generation_logs ADD COLUMN chunk_parse_failures INTEGER NOT NULL DEFAULT 0",
        "ALTER TABLE graph_generation_logs ADD COLUMN json_parse_failures INTEGER NOT NULL DEFAULT 0",
        "ALTER TABLE graph_generation_logs ADD COLUMN warnings TEXT NOT NULL DEFAULT '[]'",
        "ALTER TABLE graph_generation_logs ADD COLUMN cancel_requested INTEGER NOT NULL DEFAULT 0",
    ];
    for stmt in log_cols {
        if let Err(e) = pool.execute(sqlx::raw_sql(stmt)).await {
            let err_str = e.to_string();
            if !err_str.contains("duplicate column") && !err_str.contains("already exists") {
                tracing::warn!(error = %e, stmt, "Migration v9->v10 log column failed (non-fatal)");
            }
        }
    }

    let index_stmts = vec![
        "CREATE INDEX IF NOT EXISTS idx_entities_entity_key ON entities(workspace_id, entity_key)",
        "CREATE INDEX IF NOT EXISTS idx_entities_display_name ON entities(workspace_id, display_name)",
        "CREATE INDEX IF NOT EXISTS idx_graph_gen_logs_active ON graph_generation_logs(workspace_id, status, started_at)",
    ];
    for stmt in index_stmts {
        let _ = pool.execute(sqlx::raw_sql(stmt)).await;
    }

    let _ = pool.execute(sqlx::raw_sql(
        "UPDATE entities SET original_name = name WHERE original_name IS NULL",
    )).await;
    let _ = pool.execute(sqlx::raw_sql(
        "UPDATE entities SET display_name = name WHERE display_name IS NULL",
    )).await;

    Ok(())
}

/// Rebuilds the chunks_fts virtual table with the correct rowid-based schema.
/// Safe to call multiple times; does not delete document_chunks rows.
async fn rebuild_chunks_fts(pool: &SqlitePool) -> anyhow::Result<()> {
    let trigger_stmts = [
        "DROP TRIGGER IF EXISTS chunks_fts_insert",
        "DROP TRIGGER IF EXISTS chunks_fts_delete",
        "DROP TRIGGER IF EXISTS chunks_fts_update",
    ];
    for stmt in trigger_stmts {
        pool.execute(sqlx::raw_sql(stmt)).await.map_err(|e| {
            tracing::error!(error = %e, stmt, "Failed to drop chunks_fts trigger during FTS rebuild");
            e
        })?;
    }

    pool.execute(sqlx::raw_sql("DROP TABLE IF EXISTS chunks_fts"))
        .await
        .map_err(|e| {
            tracing::error!(error = %e, "Failed to drop chunks_fts table during FTS rebuild");
            e
        })?;

    let create_fts = r#"
        CREATE VIRTUAL TABLE chunks_fts USING fts5(
            content,
            content='document_chunks',
            content_rowid='rowid'
        )
    "#;
    pool.execute(sqlx::raw_sql(create_fts)).await.map_err(|e| {
        tracing::error!(error = %e, "Failed to create chunks_fts with correct schema");
        e
    })?;

    let trigger_sql = r#"
        CREATE TRIGGER chunks_fts_insert AFTER INSERT ON document_chunks BEGIN
            INSERT INTO chunks_fts(rowid, content) VALUES (new.rowid, new.content);
        END;

        CREATE TRIGGER chunks_fts_delete AFTER DELETE ON document_chunks BEGIN
            INSERT INTO chunks_fts(chunks_fts, rowid, content) VALUES ('delete', old.rowid, old.content);
        END;

        CREATE TRIGGER chunks_fts_update AFTER UPDATE OF content ON document_chunks BEGIN
            INSERT INTO chunks_fts(chunks_fts, rowid, content) VALUES ('delete', old.rowid, old.content);
            INSERT INTO chunks_fts(rowid, content) VALUES (new.rowid, new.content);
        END;
    "#;
    pool.execute(sqlx::raw_sql(trigger_sql)).await.map_err(|e| {
        tracing::error!(error = %e, "Failed to recreate chunks_fts triggers");
        e
    })?;

    pool.execute(sqlx::raw_sql(
        "INSERT INTO chunks_fts(rowid, content) SELECT rowid, content FROM document_chunks",
    ))
    .await
    .map_err(|e| {
        tracing::error!(error = %e, "Failed to reindex document_chunks into chunks_fts");
        e
    })?;

    Ok(())
}

async fn migrate_v10_to_v11(pool: &SqlitePool) -> anyhow::Result<()> {
    tracing::info!("Running migration v10 -> v11: rebuild chunks_fts without chunk_id column");

    let chunk_count: i64 = sqlx::query_scalar("SELECT COUNT(*) FROM document_chunks")
        .fetch_one(pool)
        .await
        .unwrap_or(0);

    rebuild_chunks_fts(pool).await.map_err(|e| {
        tracing::error!(
            error = %e,
            document_chunks = chunk_count,
            "Migration v10->v11 failed while rebuilding chunks_fts; \
             document_chunks data is preserved but FTS index may be inconsistent"
        );
        e
    })?;

    tracing::info!(
        document_chunks = chunk_count,
        "Migration v10 -> v11 completed: chunks_fts rebuilt with rowid mapping"
    );
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

#[cfg(test)]
mod tests {
    use super::*;
    use crate::services::search::{fulltext_search, hybrid_search, SearchConfig, SearchMode};
    use sqlx::Row;
    use uuid::Uuid;

    async fn seed_search_fixture(pool: &SqlitePool) -> (Uuid, Uuid, String) {
        let user_id = Uuid::new_v4().to_string();
        let workspace_id = Uuid::new_v4();
        let document_id = Uuid::new_v4();
        let chunk_id = Uuid::new_v4().to_string();

        sqlx::query(
            "INSERT INTO users (id, email, password_hash, display_name) VALUES (?1, ?2, 'hash', 'Tester')",
        )
        .bind(&user_id)
        .bind(format!("{user_id}@example.com"))
        .execute(pool)
        .await
        .unwrap();

        sqlx::query(
            "INSERT INTO workspaces (id, name, owner_id) VALUES (?1, 'WS', ?2)",
        )
        .bind(workspace_id.to_string())
        .bind(&user_id)
        .execute(pool)
        .await
        .unwrap();

        sqlx::query(
            "INSERT INTO documents (id, workspace_id, title, original_filename, file_type, original_file_path, uploaded_by)
             VALUES (?1, ?2, 'Doc', 'doc.txt', 'txt', '/tmp/doc.txt', ?3)",
        )
        .bind(document_id.to_string())
        .bind(workspace_id.to_string())
        .bind(&user_id)
        .execute(pool)
        .await
        .unwrap();

        sqlx::query(
            "INSERT INTO document_chunks (id, document_id, chunk_index, content)
             VALUES (?1, ?2, 0, 'SQLite FTS migration regression uniquekeyword')",
        )
        .bind(&chunk_id)
        .bind(document_id.to_string())
        .execute(pool)
        .await
        .unwrap();

        (workspace_id, document_id, chunk_id)
    }

    #[tokio::test]
    async fn fresh_init_chunks_fts_has_no_chunk_id_column() {
        let pool = create_pool("sqlite::memory:")
            .await
            .expect("create in-memory pool");
        run_migrations(&pool).await.expect("run migrations");

        let row = sqlx::query(
            "SELECT sql FROM sqlite_master WHERE type='table' AND name='chunks_fts'",
        )
        .fetch_one(&pool)
        .await
        .expect("chunks_fts exists");

        let create_sql: String = row.try_get(0).expect("create sql");
        assert!(
            !create_sql.contains("chunk_id"),
            "fresh chunks_fts must not declare chunk_id: {create_sql}"
        );

        let version = get_schema_version(&pool).await.expect("schema version");
        assert_eq!(version, CURRENT_SCHEMA_VERSION);
    }

    #[tokio::test]
    async fn fulltext_search_does_not_reference_missing_chunk_id_column() {
        let pool = create_pool("sqlite::memory:")
            .await
            .expect("create in-memory pool");
        run_migrations(&pool).await.expect("run migrations");
        let (workspace_id, _document_id, chunk_id) = seed_search_fixture(&pool).await;

        let results = fulltext_search(&pool, workspace_id, "uniquekeyword", 5, None)
            .await
            .expect("fulltext_search should succeed");

        assert_eq!(results.len(), 1);
        assert_eq!(results[0].0.to_string(), chunk_id);
    }

    #[tokio::test]
    async fn hybrid_search_fulltext_branch_does_not_error() {
        struct NoopEmbedding;

        #[async_trait::async_trait]
        impl crate::traits::embedding_provider::EmbeddingProvider for NoopEmbedding {
            async fn embed_texts(&self, _texts: &[String]) -> anyhow::Result<Vec<Vec<f32>>> {
                Ok(vec![])
            }

            fn dimensions(&self) -> usize {
                4
            }

            fn model_name(&self) -> &str {
                "noop"
            }
        }

        let pool = create_pool("sqlite::memory:")
            .await
            .expect("create in-memory pool");
        run_migrations(&pool).await.expect("run migrations");
        let (workspace_id, _, _) = seed_search_fixture(&pool).await;

        let config = SearchConfig {
            mode: SearchMode::Fulltext,
            top_k: 5,
            min_score: 0.0,
            ..SearchConfig::default()
        };

        let response = hybrid_search(
            &pool,
            &NoopEmbedding,
            workspace_id,
            "uniquekeyword",
            &config,
            None,
        )
        .await
        .expect("hybrid_search fulltext branch should succeed");

        assert_eq!(response.results.len(), 1);
        assert!(response.results[0].content.contains("uniquekeyword"));
    }

    async fn install_legacy_chunks_fts(pool: &SqlitePool) -> anyhow::Result<()> {
        for stmt in [
            "DROP TRIGGER IF EXISTS chunks_fts_insert",
            "DROP TRIGGER IF EXISTS chunks_fts_delete",
            "DROP TRIGGER IF EXISTS chunks_fts_update",
            "DROP TABLE IF EXISTS chunks_fts",
        ] {
            pool.execute(sqlx::raw_sql(stmt)).await?;
        }

        pool.execute(sqlx::raw_sql(
            r#"
            CREATE VIRTUAL TABLE chunks_fts USING fts5(
                content,
                chunk_id UNINDEXED,
                content='document_chunks',
                content_rowid='rowid'
            );
            CREATE TRIGGER chunks_fts_insert AFTER INSERT ON document_chunks BEGIN
                INSERT INTO chunks_fts(rowid, content, chunk_id) VALUES (new.rowid, new.content, new.id);
            END;
            "#,
        ))
        .await?;

        pool.execute(sqlx::raw_sql(
            "INSERT INTO chunks_fts(rowid, content, chunk_id) SELECT rowid, content, id FROM document_chunks",
        ))
        .await?;

        Ok(())
    }

    #[tokio::test]
    async fn migrate_v8_legacy_chunks_fts_rebuilds_and_preserves_chunks() {
        let pool = create_pool("sqlite::memory:")
            .await
            .expect("create in-memory pool");
        run_migrations(&pool).await.expect("initial migrations");

        let (workspace_id, _document_id, chunk_id) = seed_search_fixture(&pool).await;

        install_legacy_chunks_fts(&pool)
            .await
            .expect("install legacy broken FTS schema");

        let fts_sql_before: String = sqlx::query_scalar(
            "SELECT sql FROM sqlite_master WHERE type='table' AND name='chunks_fts'",
        )
        .fetch_one(&pool)
        .await
        .unwrap();
        assert!(
            fts_sql_before.contains("chunk_id"),
            "fixture should use legacy chunks_fts schema"
        );

        let legacy_join = sqlx::query(
            r#"SELECT dc.id
               FROM document_chunks dc
               JOIN documents d ON dc.document_id = d.id
               JOIN chunks_fts ON chunks_fts.chunk_id = dc.id
               WHERE d.workspace_id = ?1
                 AND chunks_fts MATCH '"uniquekeyword"'
               LIMIT 1"#,
        )
        .bind(workspace_id.to_string())
        .fetch_optional(&pool)
        .await;
        assert!(
            legacy_join.is_err(),
            "legacy chunk_id join should fail against document_chunks schema"
        );

        set_schema_version(&pool, 8).await.expect("simulate v8 user_version");
        run_migrations(&pool).await.expect("migrate legacy db from v8");

        let version = get_schema_version(&pool).await.expect("version");
        assert_eq!(version, CURRENT_SCHEMA_VERSION);

        let chunk_count: i64 = sqlx::query_scalar("SELECT COUNT(*) FROM document_chunks")
            .fetch_one(&pool)
            .await
            .unwrap();
        assert_eq!(chunk_count, 1);

        let fts_sql: String = sqlx::query_scalar(
            "SELECT sql FROM sqlite_master WHERE type='table' AND name='chunks_fts'",
        )
        .fetch_one(&pool)
        .await
        .unwrap();
        assert!(
            !fts_sql.contains("chunk_id"),
            "legacy migration left chunk_id: {fts_sql}"
        );

        let results = fulltext_search(&pool, workspace_id, "uniquekeyword", 5, None)
            .await
            .expect("search after legacy migration");

        assert_eq!(results.len(), 1);
        assert_eq!(results[0].0.to_string(), chunk_id);
        assert!(results[0].2.contains("uniquekeyword"));
    }
}
