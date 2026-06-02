use axum::{
    extract::{Multipart, Path, Query, State},
    http::{header, StatusCode},
    response::IntoResponse,
    routing::{get, post},
    Json, Router,
};
use serde::{Deserialize, Serialize};
use uuid::Uuid;

use crate::auth::middleware::AuthUser;
use crate::db::compat;
use crate::error::AppError;
use crate::services::storage::StorageService;

use super::AppState;

const ALLOWED_EXTENSIONS: &[&str] = &["pdf", "docx", "md", "txt", "html"];

#[derive(Serialize)]
pub struct DocumentResponse {
    pub id: Uuid,
    pub workspace_id: Uuid,
    pub title: String,
    pub original_filename: String,
    pub file_type: String,
    pub file_size_bytes: Option<i64>,
    pub page_count: Option<i32>,
    pub language: Option<String>,
    pub tags: Option<serde_json::Value>,
    pub processing_status: String,
    pub processing_error: Option<String>,
    pub chunks_total: Option<i32>,
    pub chunks_done: Option<i32>,
    pub embedding_batches_total: Option<i32>,
    pub embedding_batches_done: Option<i32>,
    pub uploaded_by: Uuid,
    pub created_at: String,
    pub updated_at: String,
}

#[derive(Deserialize)]
pub struct ListDocumentsQuery {
    pub page: Option<i64>,
    pub per_page: Option<i64>,
    pub status: Option<String>,
    pub file_type: Option<String>,
}

#[derive(Serialize)]
pub struct PaginatedDocuments {
    pub items: Vec<DocumentResponse>,
    pub total: i64,
    pub page: i64,
    pub per_page: i64,
}

pub fn router() -> Router<AppState> {
    Router::new()
        .route(
            "/workspaces/{ws_id}/documents",
            get(list_documents).post(upload_document),
        )
        .route(
            "/workspaces/{ws_id}/documents/{doc_id}",
            get(get_document).delete(delete_document).patch(update_document_tags),
        )
        .route(
            "/workspaces/{ws_id}/documents/{doc_id}/download",
            get(download_file),
        )
        .route(
            "/workspaces/{ws_id}/documents/{doc_id}/markdown",
            get(get_markdown),
        )
        .route(
            "/workspaces/{ws_id}/documents/{doc_id}/chunks",
            get(list_chunks),
        )
        .route(
            "/workspaces/{ws_id}/documents/{doc_id}/reprocess",
            post(reprocess_document),
        )
        .route(
            "/workspaces/{ws_id}/documents/graph-stats",
            get(documents_graph_stats),
        )
}

fn extract_extension(filename: &str) -> Option<String> {
    filename
        .rsplit('.')
        .next()
        .map(|ext| ext.to_lowercase())
}

fn validate_file_type(filename: &str) -> Result<String, AppError> {
    let ext = extract_extension(filename)
        .ok_or_else(|| AppError::BadRequest("File must have an extension".into()))?;

    if !ALLOWED_EXTENSIONS.contains(&ext.as_str()) {
        return Err(AppError::BadRequest(format!(
            "Unsupported file type '{}'. Allowed: {}",
            ext,
            ALLOWED_EXTENSIONS.join(", ")
        )));
    }

    Ok(ext)
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

#[derive(sqlx::FromRow)]
struct DocRow {
    id: String,
    workspace_id: String,
    title: String,
    original_filename: String,
    file_type: String,
    file_size_bytes: Option<i64>,
    page_count: Option<i32>,
    language: Option<String>,
    tags_text: Option<String>,
    processing_status: String,
    processing_error: Option<String>,
    chunks_total: Option<i32>,
    chunks_done: Option<i32>,
    embedding_batches_total: Option<i32>,
    embedding_batches_done: Option<i32>,
    uploaded_by: String,
    created_at: String,
    updated_at: String,
}

fn parse_doc_row(r: DocRow) -> Result<DocumentResponse, AppError> {
    let tags_val: Option<serde_json::Value> = r.tags_text.as_ref().and_then(|s| serde_json::from_str(s).ok());
    Ok(DocumentResponse {
        id: compat::parse_uuid(&r.id).map_err(|e| AppError::Internal(e.into()))?,
        workspace_id: compat::parse_uuid(&r.workspace_id).map_err(|e| AppError::Internal(e.into()))?,
        title: r.title,
        original_filename: r.original_filename,
        file_type: r.file_type,
        file_size_bytes: r.file_size_bytes,
        page_count: r.page_count,
        language: r.language,
        tags: tags_val,
        processing_status: r.processing_status,
        processing_error: r.processing_error,
        chunks_total: r.chunks_total,
        chunks_done: r.chunks_done,
        embedding_batches_total: r.embedding_batches_total,
        embedding_batches_done: r.embedding_batches_done,
        uploaded_by: compat::parse_uuid(&r.uploaded_by).map_err(|e| AppError::Internal(e.into()))?,
        created_at: r.created_at,
        updated_at: r.updated_at,
    })
}

const DOC_SELECT: &str = "id, workspace_id, title, original_filename, file_type, file_size_bytes, page_count, language, CAST(tags AS TEXT) AS tags_text, processing_status, processing_error, chunks_total, chunks_done, embedding_batches_total, embedding_batches_done, uploaded_by, CAST(created_at AS TEXT) AS created_at, CAST(updated_at AS TEXT) AS updated_at";

async fn list_documents(
    auth: AuthUser,
    State(state): State<AppState>,
    Path(ws_id): Path<Uuid>,
    Query(params): Query<ListDocumentsQuery>,
) -> Result<Json<PaginatedDocuments>, AppError> {
    check_workspace_access(&state.pool, ws_id, auth.id).await?;

    let page = params.page.unwrap_or(1).max(1);
    let per_page = params.per_page.unwrap_or(20).clamp(1, 100);
    let offset = (page - 1) * per_page;

    let total = sqlx::query_scalar::<_, i64>(
        "SELECT COUNT(*) FROM documents WHERE workspace_id = $1",
    )
    .bind(ws_id.to_string())
    .fetch_one(&state.pool)
    .await?;

    let q = format!(
        "SELECT {} FROM documents WHERE workspace_id = $1 ORDER BY created_at DESC LIMIT $2 OFFSET $3",
        DOC_SELECT
    );

    let rows = sqlx::query_as::<_, DocRow>(&q)
        .bind(ws_id.to_string())
        .bind(per_page)
        .bind(offset)
        .fetch_all(&state.pool)
        .await?;

    let items: Result<Vec<_>, _> = rows.into_iter().map(parse_doc_row).collect();

    Ok(Json(PaginatedDocuments {
        items: items?,
        total,
        page,
        per_page,
    }))
}

async fn upload_document(
    auth: AuthUser,
    State(state): State<AppState>,
    Path(ws_id): Path<Uuid>,
    mut multipart: Multipart,
) -> Result<(StatusCode, Json<DocumentResponse>), AppError> {
    check_workspace_access(&state.pool, ws_id, auth.id).await?;

    let mut file_data: Option<bytes::Bytes> = None;
    let mut file_name: Option<String> = None;
    let mut title: Option<String> = None;
    let mut tags: Option<serde_json::Value> = None;

    while let Some(field) = multipart
        .next_field()
        .await
        .map_err(|e| AppError::BadRequest(format!("Multipart error: {e}")))?
    {
        let field_name = field.name().unwrap_or("").to_string();

        match field_name.as_str() {
            "file" => {
                file_name = field.file_name().map(|s| s.to_string());
                let data = field
                    .bytes()
                    .await
                    .map_err(|e| AppError::BadRequest(format!("Failed to read file: {e}")))?;

                let max_bytes = state.max_upload_size * 1024 * 1024;
                if data.len() as u64 > max_bytes {
                    return Err(AppError::BadRequest(format!(
                        "File too large. Maximum size: {} MB",
                        state.max_upload_size
                    )));
                }

                file_data = Some(data);
            }
            "title" => {
                title = Some(
                    field
                        .text()
                        .await
                        .map_err(|e| AppError::BadRequest(format!("Invalid title: {e}")))?,
                );
            }
            "tags" => {
                let raw = field
                    .text()
                    .await
                    .map_err(|e| AppError::BadRequest(format!("Invalid tags: {e}")))?;
                tags = Some(
                    serde_json::from_str(&raw)
                        .unwrap_or_else(|_| serde_json::json!([])),
                );
            }
            _ => {}
        }
    }

    let file_data =
        file_data.ok_or_else(|| AppError::BadRequest("No file provided".into()))?;
    let original_filename =
        file_name.ok_or_else(|| AppError::BadRequest("File must have a name".into()))?;

    let file_type = validate_file_type(&original_filename)?;
    let file_size = file_data.len() as i64;
    let doc_title = title.unwrap_or_else(|| original_filename.clone());

    let doc_id = Uuid::new_v4();
    let storage_path = StorageService::document_path(&ws_id, &doc_id, &original_filename);

    state
        .storage
        .upload(&storage_path, file_data)
        .await
        .map_err(|e| AppError::Internal(anyhow::anyhow!("Storage upload failed: {e}")))?;

    let tags_str = serde_json::to_string(&tags.unwrap_or_else(|| serde_json::json!([]))).unwrap_or_default();

    let q = format!(
        "INSERT INTO documents (id, workspace_id, title, original_filename, file_type, file_size_bytes, tags, original_file_path, uploaded_by) VALUES ($1, $2, $3, $4, $5, $6, $7, $8, $9) RETURNING {}",
        DOC_SELECT
    );

    let row = sqlx::query_as::<_, DocRow>(&q)
        .bind(doc_id.to_string())
        .bind(ws_id.to_string())
        .bind(&doc_title)
        .bind(&original_filename)
        .bind(&file_type)
        .bind(file_size)
        .bind(&tags_str)
        .bind(&storage_path)
        .bind(auth.id.to_string())
        .fetch_one(&state.pool)
        .await?;

    let pool = state.pool.clone();
    let storage = state.storage.clone();
    let doc_processor_url = state.doc_processor_url.clone();
    let embedding_provider = state.embedding_provider.read().await.clone();
    tokio::spawn(async move {
        crate::services::document::process_document(
            pool,
            storage,
            doc_processor_url,
            embedding_provider,
            doc_id,
            ws_id,
        )
        .await;
    });

    Ok((StatusCode::CREATED, Json(parse_doc_row(row)?)))
}

async fn get_document(
    auth: AuthUser,
    State(state): State<AppState>,
    Path((ws_id, doc_id)): Path<(Uuid, Uuid)>,
) -> Result<Json<DocumentResponse>, AppError> {
    check_workspace_access(&state.pool, ws_id, auth.id).await?;

    let q = format!(
        "SELECT {} FROM documents WHERE id = $1 AND workspace_id = $2",
        DOC_SELECT
    );

    let row = sqlx::query_as::<_, DocRow>(&q)
        .bind(doc_id.to_string())
        .bind(ws_id.to_string())
        .fetch_optional(&state.pool)
        .await?
        .ok_or_else(|| AppError::NotFound("Document not found".into()))?;

    Ok(Json(parse_doc_row(row)?))
}

async fn delete_document(
    auth: AuthUser,
    State(state): State<AppState>,
    Path((ws_id, doc_id)): Path<(Uuid, Uuid)>,
) -> Result<StatusCode, AppError> {
    check_workspace_access(&state.pool, ws_id, auth.id).await?;

    let _doc = sqlx::query_as::<_, (String,)>(
        "SELECT original_file_path FROM documents WHERE id = $1 AND workspace_id = $2",
    )
    .bind(doc_id.to_string())
    .bind(ws_id.to_string())
    .fetch_optional(&state.pool)
    .await?
    .ok_or_else(|| AppError::NotFound("Document not found".into()))?;

    let dir_prefix = format!("workspaces/{}/documents/{}/", ws_id, doc_id);
    if let Err(e) = state.storage.delete_dir(&dir_prefix).await {
        tracing::warn!("Failed to delete storage files for doc {}: {}", doc_id, e);
    }

    sqlx::query("DELETE FROM documents WHERE id = $1 AND workspace_id = $2")
        .bind(doc_id.to_string())
        .bind(ws_id.to_string())
        .execute(&state.pool)
        .await?;

    Ok(StatusCode::NO_CONTENT)
}

async fn download_file(
    auth: AuthUser,
    State(state): State<AppState>,
    Path((ws_id, doc_id)): Path<(Uuid, Uuid)>,
) -> Result<impl IntoResponse, AppError> {
    check_workspace_access(&state.pool, ws_id, auth.id).await?;

    let doc = sqlx::query_as::<_, (String, String)>(
        "SELECT original_file_path, original_filename FROM documents WHERE id = $1 AND workspace_id = $2",
    )
    .bind(doc_id.to_string())
    .bind(ws_id.to_string())
    .fetch_optional(&state.pool)
    .await?
    .ok_or_else(|| AppError::NotFound("Document not found".into()))?;

    let (file_path, filename) = doc;

    let data = state
        .storage
        .download(&file_path)
        .await
        .map_err(|e| AppError::Internal(anyhow::anyhow!("Storage download failed: {e}")))?;

    let content_type = match extract_extension(&filename).as_deref() {
        Some("pdf") => "application/pdf",
        Some("docx") => "application/vnd.openxmlformats-officedocument.wordprocessingml.document",
        Some("md") => "text/markdown",
        Some("txt") => "text/plain",
        Some("html") => "text/html",
        _ => "application/octet-stream",
    };

    let safe_filename = filename.replace('\\', "_").replace('"', "_");
    let disposition = format!("attachment; filename=\"{}\"", safe_filename);

    Ok((
        [
            (header::CONTENT_TYPE, content_type.to_string()),
            (header::CONTENT_DISPOSITION, disposition),
        ],
        data,
    ))
}

async fn reprocess_document(
    auth: AuthUser,
    State(state): State<AppState>,
    Path((ws_id, doc_id)): Path<(Uuid, Uuid)>,
) -> Result<Json<DocumentResponse>, AppError> {
    check_workspace_access(&state.pool, ws_id, auth.id).await?;

    let q = format!(
        "UPDATE documents SET processing_status = 'pending', processing_error = NULL, chunks_total = NULL, chunks_done = NULL, embedding_batches_total = NULL, embedding_batches_done = NULL WHERE id = $1 AND workspace_id = $2 RETURNING {}",
        DOC_SELECT
    );

    let row = sqlx::query_as::<_, DocRow>(&q)
        .bind(doc_id.to_string())
        .bind(ws_id.to_string())
        .fetch_optional(&state.pool)
        .await?
        .ok_or_else(|| AppError::NotFound("Document not found".into()))?;

    let pool = state.pool.clone();
    let storage = state.storage.clone();
    let doc_processor_url = state.doc_processor_url.clone();
    let embedding_provider = state.embedding_provider.read().await.clone();
    tokio::spawn(async move {
        crate::services::document::process_document(
            pool,
            storage,
            doc_processor_url,
            embedding_provider,
            doc_id,
            ws_id,
        )
        .await;
    });

    Ok(Json(parse_doc_row(row)?))
}

#[derive(Serialize)]
pub struct ChunkResponse {
    pub id: Uuid,
    pub document_id: Uuid,
    pub chunk_index: i32,
    pub heading_path: Option<String>,
    pub section_level: Option<i32>,
    pub content: String,
    pub content_tokens: Option<i32>,
    pub page_start: Option<i32>,
    pub page_end: Option<i32>,
    pub paragraph_index: Option<i32>,
    pub char_start: Option<i64>,
    pub char_end: Option<i64>,
    pub content_hash: Option<String>,
    pub created_at: String,
}

#[derive(Deserialize)]
pub struct ListChunksQuery {
    pub page: Option<i64>,
    pub per_page: Option<i64>,
}

#[derive(Serialize)]
pub struct PaginatedChunks {
    pub items: Vec<ChunkResponse>,
    pub total: i64,
    pub page: i64,
    pub per_page: i64,
}

async fn list_chunks(
    auth: AuthUser,
    State(state): State<AppState>,
    Path((ws_id, doc_id)): Path<(Uuid, Uuid)>,
    Query(params): Query<ListChunksQuery>,
) -> Result<Json<PaginatedChunks>, AppError> {
    check_workspace_access(&state.pool, ws_id, auth.id).await?;

    let doc_count: i32 = sqlx::query_scalar(
        "SELECT COUNT(*) FROM documents WHERE id = $1 AND workspace_id = $2",
    )
    .bind(doc_id.to_string())
    .bind(ws_id.to_string())
    .fetch_one(&state.pool)
    .await?;
    if doc_count == 0 {
        return Err(AppError::NotFound("Document not found".into()));
    }

    let page = params.page.unwrap_or(1).max(1);
    let per_page = params.per_page.unwrap_or(50).clamp(1, 200);
    let offset = (page - 1) * per_page;

    let total = sqlx::query_scalar::<_, i64>(
        "SELECT COUNT(*) FROM document_chunks WHERE document_id = $1",
    )
    .bind(doc_id.to_string())
    .fetch_one(&state.pool)
    .await?;

    let rows = sqlx::query_as::<_, (String, String, i32, Option<String>, Option<i32>, String, Option<i32>, Option<i32>, Option<i32>, Option<i32>, Option<i64>, Option<i64>, Option<String>, String)>(
        r#"
        SELECT id, document_id, chunk_index, heading_path, section_level,
               content, content_tokens, page_start, page_end,
               paragraph_index, char_start, char_end, content_hash, CAST(created_at AS TEXT)
        FROM document_chunks
        WHERE document_id = $1
        ORDER BY chunk_index ASC
        LIMIT $2 OFFSET $3
        "#,
    )
    .bind(doc_id.to_string())
    .bind(per_page)
    .bind(offset)
    .fetch_all(&state.pool)
    .await?;

    let mut items = Vec::with_capacity(rows.len());
    for r in rows {
        items.push(ChunkResponse {
            id: compat::parse_uuid(&r.0).map_err(|e| AppError::Internal(e.into()))?,
            document_id: compat::parse_uuid(&r.1).map_err(|e| AppError::Internal(e.into()))?,
            chunk_index: r.2,
            heading_path: r.3,
            section_level: r.4,
            content: r.5,
            content_tokens: r.6,
            page_start: r.7,
            page_end: r.8,
            paragraph_index: r.9,
            char_start: r.10,
            char_end: r.11,
            content_hash: r.12,
            created_at: r.13,
        });
    }

    Ok(Json(PaginatedChunks {
        items,
        total,
        page,
        per_page,
    }))
}

async fn get_markdown(
    auth: AuthUser,
    State(state): State<AppState>,
    Path((ws_id, doc_id)): Path<(Uuid, Uuid)>,
) -> Result<impl IntoResponse, AppError> {
    check_workspace_access(&state.pool, ws_id, auth.id).await?;

    let doc = sqlx::query_as::<_, (Option<String>, String)>(
        "SELECT markdown_file_path, title FROM documents WHERE id = $1 AND workspace_id = $2",
    )
    .bind(doc_id.to_string())
    .bind(ws_id.to_string())
    .fetch_optional(&state.pool)
    .await?
    .ok_or_else(|| AppError::NotFound("Document not found".into()))?;

    let (md_path, title) = doc;
    let md_path = md_path.ok_or_else(|| {
        AppError::NotFound("Markdown version not available yet (document may still be processing)".into())
    })?;

    let data = state
        .storage
        .download(&md_path)
        .await
        .map_err(|e| AppError::Internal(anyhow::anyhow!("Storage download failed: {e}")))?;

    let filename = format!("{}.md", title.replace('/', "_").replace('\\', "_").replace('"', "_"));
    Ok((
        [
            (header::CONTENT_TYPE, "text/markdown; charset=utf-8".to_string()),
            (
                header::CONTENT_DISPOSITION,
                format!("inline; filename=\"{}\"", filename),
            ),
        ],
        data,
    ))
}

#[derive(Deserialize)]
struct UpdateDocumentBody {
    tags: Option<serde_json::Value>,
}

async fn update_document_tags(
    auth: AuthUser,
    State(state): State<AppState>,
    Path((ws_id, doc_id)): Path<(Uuid, Uuid)>,
    Json(body): Json<UpdateDocumentBody>,
) -> Result<Json<DocumentResponse>, AppError> {
    check_workspace_access(&state.pool, ws_id, auth.id).await?;

    let tags = body.tags.unwrap_or(serde_json::json!([]));
    let tags_str = serde_json::to_string(&tags).unwrap_or_else(|_| "[]".to_string());

    let q = format!(
        "UPDATE documents SET tags = $1, updated_at = {} WHERE id = $2 AND workspace_id = $3 RETURNING {}",
        crate::db::compat::current_timestamp_sql(),
        DOC_SELECT
    );

    let row = sqlx::query_as::<_, DocRow>(&q)
        .bind(&tags_str)
        .bind(doc_id.to_string())
        .bind(ws_id.to_string())
        .fetch_optional(&state.pool)
        .await?
        .ok_or_else(|| AppError::NotFound("Document not found".into()))?;

    Ok(Json(parse_doc_row(row)?))
}

#[derive(Serialize)]
struct GraphStatItem {
    document_id: String,
    entities_count: i64,
    relations_count: i64,
}

async fn documents_graph_stats(
    auth: AuthUser,
    State(state): State<AppState>,
    Path(ws_id): Path<Uuid>,
) -> Result<Json<Vec<GraphStatItem>>, AppError> {
    check_workspace_access(&state.pool, ws_id, auth.id).await?;

    let rows = sqlx::query_as::<_, (String, i64)>(
        "SELECT document_id, COUNT(*) FROM entities WHERE workspace_id = $1 AND document_id IS NOT NULL GROUP BY document_id",
    )
    .bind(ws_id.to_string())
    .fetch_all(&state.pool)
    .await?;

    let rel_rows = sqlx::query_as::<_, (String, i64)>(
        r#"SELECT e.document_id, COUNT(*)
           FROM entity_relations r
           JOIN entities e ON e.id = r.source_entity_id
           WHERE r.workspace_id = $1 AND e.document_id IS NOT NULL
           GROUP BY e.document_id"#,
    )
    .bind(ws_id.to_string())
    .fetch_all(&state.pool)
    .await?;

    let mut rel_map: std::collections::HashMap<String, i64> = std::collections::HashMap::new();
    for (doc_id, cnt) in rel_rows {
        rel_map.insert(doc_id, cnt);
    }

    let items = rows
        .into_iter()
        .map(|(doc_id, ent_cnt)| {
            let rel_cnt = rel_map.get(&doc_id).copied().unwrap_or(0);
            GraphStatItem {
                document_id: doc_id,
                entities_count: ent_cnt,
                relations_count: rel_cnt,
            }
        })
        .collect();

    Ok(Json(items))
}
