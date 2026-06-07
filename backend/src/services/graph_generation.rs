use anyhow::Result;
use serde::{Deserialize, Serialize};
use std::collections::HashSet;
use std::sync::Arc;
use tokio::sync::RwLock;
use uuid::Uuid;

use crate::db::DbPool;
use crate::traits::llm_provider::LlmProvider;

use super::knowledge_extraction::{self, ExtractionStats};

/// In-memory registry of running task handles for cooperative cancellation.
static RUNNING_TASKS: std::sync::OnceLock<Arc<RwLock<HashSet<String>>>> =
    std::sync::OnceLock::new();

fn running_tasks() -> &'static Arc<RwLock<HashSet<String>>> {
    RUNNING_TASKS.get_or_init(|| Arc::new(RwLock::new(HashSet::new())))
}

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct GenerationJobStatus {
    pub task_id: String,
    pub workspace_id: String,
    pub status: String,
    pub job_type: String,
    pub layer_type: Option<String>,
    pub target_language: Option<String>,
    pub total_documents: i32,
    pub processed_documents: i32,
    pub succeeded_documents: i32,
    pub failed_documents: i32,
    pub entities_created: i32,
    pub relations_created: i32,
    pub relations_llm_returned: i32,
    pub relations_skipped_match: i32,
    pub relations_skipped_duplicate: i32,
    pub relations_db_failed: i32,
    pub chunk_parse_failures: i32,
    pub json_parse_failures: i32,
    pub current_document_id: Option<String>,
    pub current_document_title: Option<String>,
    pub errors: Vec<String>,
    pub warnings: Vec<String>,
    pub started_at: String,
    pub completed_at: Option<String>,
    pub elapsed_ms: Option<i64>,
    pub llm_provider: Option<String>,
    pub llm_model: Option<String>,
    pub cancel_requested: bool,
    pub progress_percent: f64,
}

#[derive(Debug, Clone)]
pub struct CreateJobParams {
    pub workspace_id: Uuid,
    pub user_id: Uuid,
    pub job_type: String,
    pub layer_type: Option<String>,
    pub target_language: String,
    pub total_documents: i32,
    pub document_id: Option<Uuid>,
    pub llm_provider: Option<String>,
    pub llm_model: Option<String>,
}

pub async fn create_job(pool: &DbPool, params: &CreateJobParams) -> Result<String> {
    let task_id = Uuid::new_v4().to_string();
    let started_at = chrono::Utc::now().to_rfc3339();
    let trigger_type = match params.job_type.as_str() {
        "knowledge_single" => "manual_single",
        "document_layer" => "document_layer",
        "semantic_layer" => "semantic_layer",
        _ => "manual_batch",
    };

    sqlx::query(
        "INSERT INTO graph_generation_logs (
            id, workspace_id, user_id, status, trigger_type, job_type, layer_type,
            target_language, document_id, llm_provider, llm_model, total_documents, started_at
        ) VALUES ($1, $2, $3, 'running', $4, $5, $6, $7, $8, $9, $10, $11, $12)",
    )
    .bind(&task_id)
    .bind(params.workspace_id.to_string())
    .bind(params.user_id.to_string())
    .bind(trigger_type)
    .bind(&params.job_type)
    .bind(params.layer_type.as_deref())
    .bind(&params.target_language)
    .bind(params.document_id.map(|d| d.to_string()))
    .bind(params.llm_provider.as_deref())
    .bind(params.llm_model.as_deref())
    .bind(params.total_documents)
    .bind(&started_at)
    .execute(pool)
    .await?;

    {
        let mut tasks = running_tasks().write().await;
        tasks.insert(task_id.clone());
    }

    Ok(task_id)
}

pub async fn register_running_task(task_id: &str) {
    let mut tasks = running_tasks().write().await;
    tasks.insert(task_id.to_string());
}

pub async fn unregister_running_task(task_id: &str) {
    let mut tasks = running_tasks().write().await;
    tasks.remove(task_id);
}

pub async fn is_cancel_requested(pool: &DbPool, task_id: &str) -> Result<bool> {
    let row: Option<(i32,)> = sqlx::query_as(
        "SELECT cancel_requested FROM graph_generation_logs WHERE id = $1",
    )
    .bind(task_id)
    .fetch_optional(pool)
    .await?;
    Ok(row.map(|r| r.0 != 0).unwrap_or(false))
}

pub async fn request_cancel(pool: &DbPool, workspace_id: Uuid, task_id: &str) -> Result<bool> {
    let result = sqlx::query(
        "UPDATE graph_generation_logs SET cancel_requested = 1, status = 'cancelling'
         WHERE id = $1 AND workspace_id = $2 AND status IN ('running', 'cancelling')",
    )
    .bind(task_id)
    .bind(workspace_id.to_string())
    .execute(pool)
    .await?;

    Ok(result.rows_affected() > 0)
}

pub async fn get_job_status(
    pool: &DbPool,
    workspace_id: Uuid,
    task_id: &str,
) -> Result<Option<GenerationJobStatus>> {
    let row = sqlx::query_as::<_, JobRow>(
        "SELECT id, workspace_id, status, job_type, layer_type, target_language,
                total_documents, processed_documents, succeeded_documents, failed_documents,
                entities_created, relations_created, relations_llm_returned,
                relations_skipped_match, relations_skipped_duplicate, relations_db_failed,
                chunk_parse_failures, json_parse_failures,
                CAST(current_document_id AS TEXT), current_document_title,
                errors, warnings, CAST(started_at AS TEXT), CAST(completed_at AS TEXT),
                elapsed_ms, llm_provider, llm_model, cancel_requested
         FROM graph_generation_logs
         WHERE id = $1 AND workspace_id = $2",
    )
    .bind(task_id)
    .bind(workspace_id.to_string())
    .fetch_optional(pool)
    .await?;

    Ok(row.map(|r| r.into_status()))
}

pub async fn get_active_job(
    pool: &DbPool,
    workspace_id: Uuid,
) -> Result<Option<GenerationJobStatus>> {
    let row = sqlx::query_as::<_, JobRow>(
        "SELECT id, workspace_id, status, job_type, layer_type, target_language,
                total_documents, processed_documents, succeeded_documents, failed_documents,
                entities_created, relations_created, relations_llm_returned,
                relations_skipped_match, relations_skipped_duplicate, relations_db_failed,
                chunk_parse_failures, json_parse_failures,
                CAST(current_document_id AS TEXT), current_document_title,
                errors, warnings, CAST(started_at AS TEXT), CAST(completed_at AS TEXT),
                elapsed_ms, llm_provider, llm_model, cancel_requested
         FROM graph_generation_logs
         WHERE workspace_id = $1 AND status IN ('running', 'cancelling')
         ORDER BY started_at DESC LIMIT 1",
    )
    .bind(workspace_id.to_string())
    .fetch_optional(pool)
    .await?;

    Ok(row.map(|r| r.into_status()))
}

#[derive(sqlx::FromRow)]
struct JobRow {
    id: String,
    workspace_id: String,
    status: String,
    job_type: Option<String>,
    layer_type: Option<String>,
    target_language: Option<String>,
    total_documents: i32,
    processed_documents: i32,
    succeeded_documents: Option<i32>,
    failed_documents: Option<i32>,
    entities_created: i32,
    relations_created: i32,
    relations_llm_returned: Option<i32>,
    relations_skipped_match: Option<i32>,
    relations_skipped_duplicate: Option<i32>,
    relations_db_failed: Option<i32>,
    chunk_parse_failures: Option<i32>,
    json_parse_failures: Option<i32>,
    current_document_id: Option<String>,
    current_document_title: Option<String>,
    errors: String,
    warnings: Option<String>,
    started_at: String,
    completed_at: Option<String>,
    elapsed_ms: Option<i64>,
    llm_provider: Option<String>,
    llm_model: Option<String>,
    cancel_requested: Option<i32>,
}

impl JobRow {
    fn into_status(self) -> GenerationJobStatus {
        let errors: Vec<String> = serde_json::from_str(&self.errors).unwrap_or_default();
        let warnings: Vec<String> = self
            .warnings
            .as_deref()
            .and_then(|w| serde_json::from_str(w).ok())
            .unwrap_or_default();
        let total = self.total_documents.max(1);
        let progress_percent = if self.status == "completed" || self.status == "failed" || self.status == "cancelled" {
            100.0
        } else {
            (self.processed_documents as f64 / total as f64 * 100.0).clamp(0.0, 99.9)
        };

        GenerationJobStatus {
            task_id: self.id,
            workspace_id: self.workspace_id,
            status: self.status,
            job_type: self.job_type.unwrap_or_else(|| "knowledge_batch".into()),
            layer_type: self.layer_type,
            target_language: self.target_language,
            total_documents: self.total_documents,
            processed_documents: self.processed_documents,
            succeeded_documents: self.succeeded_documents.unwrap_or(0),
            failed_documents: self.failed_documents.unwrap_or(0),
            entities_created: self.entities_created,
            relations_created: self.relations_created,
            relations_llm_returned: self.relations_llm_returned.unwrap_or(0),
            relations_skipped_match: self.relations_skipped_match.unwrap_or(0),
            relations_skipped_duplicate: self.relations_skipped_duplicate.unwrap_or(0),
            relations_db_failed: self.relations_db_failed.unwrap_or(0),
            chunk_parse_failures: self.chunk_parse_failures.unwrap_or(0),
            json_parse_failures: self.json_parse_failures.unwrap_or(0),
            current_document_id: self.current_document_id,
            current_document_title: self.current_document_title,
            errors,
            warnings,
            started_at: self.started_at,
            completed_at: self.completed_at,
            elapsed_ms: self.elapsed_ms,
            llm_provider: self.llm_provider,
            llm_model: self.llm_model,
            cancel_requested: self.cancel_requested.unwrap_or(0) != 0,
            progress_percent,
        }
    }
}

pub async fn update_job_progress(pool: &DbPool, task_id: &str, update: &JobProgressUpdate) -> Result<()> {
    sqlx::query(
        "UPDATE graph_generation_logs SET
            processed_documents = COALESCE($1, processed_documents),
            succeeded_documents = COALESCE($2, succeeded_documents),
            failed_documents = COALESCE($3, failed_documents),
            entities_created = COALESCE($4, entities_created),
            relations_created = COALESCE($5, relations_created),
            relations_llm_returned = COALESCE($6, relations_llm_returned),
            relations_skipped_match = COALESCE($7, relations_skipped_match),
            relations_skipped_duplicate = COALESCE($8, relations_skipped_duplicate),
            relations_db_failed = COALESCE($9, relations_db_failed),
            chunk_parse_failures = COALESCE($10, chunk_parse_failures),
            json_parse_failures = COALESCE($11, json_parse_failures),
            current_document_id = COALESCE($12, current_document_id),
            current_document_title = COALESCE($13, current_document_title),
            errors = COALESCE($14, errors),
            warnings = COALESCE($15, warnings),
            status = COALESCE($16, status)
         WHERE id = $17",
    )
    .bind(update.processed_documents)
    .bind(update.succeeded_documents)
    .bind(update.failed_documents)
    .bind(update.entities_created)
    .bind(update.relations_created)
    .bind(update.relations_llm_returned)
    .bind(update.relations_skipped_match)
    .bind(update.relations_skipped_duplicate)
    .bind(update.relations_db_failed)
    .bind(update.chunk_parse_failures)
    .bind(update.json_parse_failures)
    .bind(update.current_document_id.as_deref())
    .bind(update.current_document_title.as_deref())
    .bind(update.errors.as_deref().map(|e| serde_json::to_string(e).unwrap_or_else(|_| "[]".into())))
    .bind(update.warnings.as_deref().map(|w| serde_json::to_string(w).unwrap_or_else(|_| "[]".into())))
    .bind(update.status.as_deref())
    .bind(task_id)
    .execute(pool)
    .await?;
    Ok(())
}

#[derive(Debug, Default)]
pub struct JobProgressUpdate {
    pub processed_documents: Option<i32>,
    pub succeeded_documents: Option<i32>,
    pub failed_documents: Option<i32>,
    pub entities_created: Option<i32>,
    pub relations_created: Option<i32>,
    pub relations_llm_returned: Option<i32>,
    pub relations_skipped_match: Option<i32>,
    pub relations_skipped_duplicate: Option<i32>,
    pub relations_db_failed: Option<i32>,
    pub chunk_parse_failures: Option<i32>,
    pub json_parse_failures: Option<i32>,
    pub current_document_id: Option<String>,
    pub current_document_title: Option<String>,
    pub errors: Option<Vec<String>>,
    pub warnings: Option<Vec<String>>,
    pub status: Option<String>,
}

pub async fn complete_job(
    pool: &DbPool,
    task_id: &str,
    status: &str,
    started_at: chrono::DateTime<chrono::Utc>,
    final_update: &JobProgressUpdate,
) -> Result<()> {
    let completed_at = chrono::Utc::now().to_rfc3339();
    let elapsed_ms = (chrono::Utc::now() - started_at).num_milliseconds();

    sqlx::query(
        "UPDATE graph_generation_logs SET
            status = $1,
            completed_at = $2,
            elapsed_ms = $3,
            processed_documents = COALESCE($4, processed_documents),
            succeeded_documents = COALESCE($5, succeeded_documents),
            failed_documents = COALESCE($6, failed_documents),
            entities_created = COALESCE($7, entities_created),
            relations_created = COALESCE($8, relations_created),
            relations_llm_returned = COALESCE($9, relations_llm_returned),
            relations_skipped_match = COALESCE($10, relations_skipped_match),
            relations_skipped_duplicate = COALESCE($11, relations_skipped_duplicate),
            relations_db_failed = COALESCE($12, relations_db_failed),
            chunk_parse_failures = COALESCE($13, chunk_parse_failures),
            json_parse_failures = COALESCE($14, json_parse_failures),
            errors = COALESCE($15, errors),
            warnings = COALESCE($16, warnings),
            current_document_id = NULL,
            current_document_title = NULL
         WHERE id = $17",
    )
    .bind(status)
    .bind(&completed_at)
    .bind(elapsed_ms)
    .bind(final_update.processed_documents)
    .bind(final_update.succeeded_documents)
    .bind(final_update.failed_documents)
    .bind(final_update.entities_created)
    .bind(final_update.relations_created)
    .bind(final_update.relations_llm_returned)
    .bind(final_update.relations_skipped_match)
    .bind(final_update.relations_skipped_duplicate)
    .bind(final_update.relations_db_failed)
    .bind(final_update.chunk_parse_failures)
    .bind(final_update.json_parse_failures)
    .bind(final_update.errors.as_deref().map(|e| serde_json::to_string(e).unwrap_or_else(|_| "[]".into())))
    .bind(final_update.warnings.as_deref().map(|w| serde_json::to_string(w).unwrap_or_else(|_| "[]".into())))
    .bind(task_id)
    .execute(pool)
    .await?;

    unregister_running_task(task_id).await;
    Ok(())
}

/// Run batch knowledge extraction as a background job.
pub async fn run_knowledge_batch_job(
    pool: DbPool,
    task_id: String,
    workspace_id: Uuid,
    doc_ids: Vec<(String, String)>,
    target_language: String,
    llm_provider: Arc<dyn LlmProvider>,
    started_at: chrono::DateTime<chrono::Utc>,
) {
    let mut stats = ExtractionStats::default();
    let mut errors = Vec::new();
    let mut warnings = Vec::new();
    let total = doc_ids.len() as i32;
    let mut processed = 0i32;
    let mut succeeded = 0i32;
    let mut failed = 0i32;

    for (doc_id_str, doc_title) in &doc_ids {
        if is_cancel_requested(&pool, &task_id).await.unwrap_or(false) {
            let _ = complete_job(
                &pool,
                &task_id,
                "cancelled",
                started_at,
                &JobProgressUpdate {
                    processed_documents: Some(processed),
                    succeeded_documents: Some(succeeded),
                    failed_documents: Some(failed),
                    entities_created: Some(stats.entities_created as i32),
                    relations_created: Some(stats.relations_created as i32),
                    relations_llm_returned: Some(stats.relations_llm_returned as i32),
                    relations_skipped_match: Some(stats.relations_skipped_match as i32),
                    relations_skipped_duplicate: Some(stats.relations_skipped_duplicate as i32),
                    relations_db_failed: Some(stats.relations_db_failed as i32),
                    chunk_parse_failures: Some(stats.chunk_parse_failures as i32),
                    json_parse_failures: Some(stats.json_parse_failures as i32),
                    errors: Some(errors.clone()),
                    warnings: Some(warnings.clone()),
                    ..Default::default()
                },
            )
            .await;
            return;
        }

        let doc_id: Uuid = doc_id_str.parse().unwrap_or_default();
        let _ = update_job_progress(
            &pool,
            &task_id,
            &JobProgressUpdate {
                current_document_id: Some(doc_id_str.clone()),
                current_document_title: Some(doc_title.clone()),
                ..Default::default()
            },
        )
        .await;

        match knowledge_extraction::extract_for_document(
            &pool,
            llm_provider.as_ref(),
            workspace_id,
            doc_id,
            &target_language,
        )
        .await
        {
            Ok(chunk_stats) => {
                stats.merge(&chunk_stats);
                succeeded += 1;
            }
            Err(e) => {
                let msg = format!("doc {} ({}): {}", doc_id, doc_title, e);
                tracing::warn!(document_id = %doc_id, error = %e, "Failed to extract for document");
                errors.push(msg);
                failed += 1;
            }
        }

        processed += 1;
        warnings.extend(stats.warnings.clone());

        let _ = update_job_progress(
            &pool,
            &task_id,
            &JobProgressUpdate {
                processed_documents: Some(processed),
                succeeded_documents: Some(succeeded),
                failed_documents: Some(failed),
                entities_created: Some(stats.entities_created as i32),
                relations_created: Some(stats.relations_created as i32),
                relations_llm_returned: Some(stats.relations_llm_returned as i32),
                relations_skipped_match: Some(stats.relations_skipped_match as i32),
                relations_skipped_duplicate: Some(stats.relations_skipped_duplicate as i32),
                relations_db_failed: Some(stats.relations_db_failed as i32),
                chunk_parse_failures: Some(stats.chunk_parse_failures as i32),
                json_parse_failures: Some(stats.json_parse_failures as i32),
                errors: Some(errors.clone()),
                warnings: Some(warnings.clone()),
                ..Default::default()
            },
        )
        .await;
    }

    let final_status = if failed > 0 && succeeded == 0 {
        "failed"
    } else {
        "completed"
    };

    let _ = complete_job(
        &pool,
        &task_id,
        final_status,
        started_at,
        &JobProgressUpdate {
            processed_documents: Some(processed),
            succeeded_documents: Some(succeeded),
            failed_documents: Some(failed),
            entities_created: Some(stats.entities_created as i32),
            relations_created: Some(stats.relations_created as i32),
            relations_llm_returned: Some(stats.relations_llm_returned as i32),
            relations_skipped_match: Some(stats.relations_skipped_match as i32),
            relations_skipped_duplicate: Some(stats.relations_skipped_duplicate as i32),
            relations_db_failed: Some(stats.relations_db_failed as i32),
            chunk_parse_failures: Some(stats.chunk_parse_failures as i32),
            json_parse_failures: Some(stats.json_parse_failures as i32),
            errors: Some(errors),
            warnings: Some(warnings),
            ..Default::default()
        },
    )
    .await;

    tracing::info!(
        task_id = %task_id,
        workspace_id = %workspace_id,
        docs = total,
        entities = stats.entities_created,
        relations = stats.relations_created,
        "Knowledge graph batch generation completed"
    );
}

pub async fn run_layer_job(
    pool: DbPool,
    task_id: String,
    workspace_id: Uuid,
    layer_type: &str,
    started_at: chrono::DateTime<chrono::Utc>,
) {
    let result = match layer_type {
        "document" => knowledge_extraction::build_document_layer(&pool, workspace_id).await,
        "semantic" => knowledge_extraction::build_semantic_layer(&pool, workspace_id).await,
        _ => Err(anyhow::anyhow!("Unknown layer type: {}", layer_type)),
    };

    match result {
        Ok((entities, relations)) => {
            let _ = complete_job(
                &pool,
                &task_id,
                "completed",
                started_at,
                &JobProgressUpdate {
                    processed_documents: Some(1),
                    succeeded_documents: Some(1),
                    entities_created: Some(entities as i32),
                    relations_created: Some(relations as i32),
                    ..Default::default()
                },
            )
            .await;
        }
        Err(e) => {
            let _ = complete_job(
                &pool,
                &task_id,
                "failed",
                started_at,
                &JobProgressUpdate {
                    errors: Some(vec![e.to_string()]),
                    ..Default::default()
                },
            )
            .await;
        }
    }
}