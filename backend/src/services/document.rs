use std::sync::Arc;

use serde::{Deserialize, Serialize};
use uuid::Uuid;

use crate::db::DbPool;
use crate::services::chunking::{chunk_markdown, ChunkConfig};
use crate::services::embedding::store_chunk_embeddings;
use crate::services::storage::StorageService;
use crate::traits::embedding_provider::EmbeddingProvider;

#[derive(Debug, Clone, Deserialize, Serialize)]
pub struct DocProcessorResponse {
    pub markdown: String,
    pub pages: serde_json::Value,
    pub headings: serde_json::Value,
    pub metadata: DocProcessorMetadata,
}

#[derive(Debug, Clone, Deserialize, Serialize)]
pub struct DocProcessorMetadata {
    pub title: Option<String>,
    pub author: Option<String>,
    pub page_count: Option<i32>,
    pub language: Option<String>,
}

/// Update document processing status with optional progress info.
async fn update_status(
    pool: &DbPool,
    doc_id: Uuid,
    status: &str,
    error: Option<&str>,
) -> anyhow::Result<()> {
    sqlx::query(
        &format!(
            "UPDATE documents SET processing_status = $1, processing_error = $2, updated_at = {} WHERE id = $3",
            crate::db::compat::current_timestamp_sql()
        ),
    )
    .bind(status)
    .bind(error)
    .bind(doc_id.to_string())
    .execute(pool)
    .await?;
    Ok(())
}

/// Update chunk/embedding progress counters without changing status.
async fn update_progress(
    pool: &DbPool,
    doc_id: Uuid,
    chunks_total: Option<i32>,
    chunks_done: Option<i32>,
    emb_total: Option<i32>,
    emb_done: Option<i32>,
) -> anyhow::Result<()> {
    sqlx::query(
        &format!(
            "UPDATE documents SET chunks_total = COALESCE($1, chunks_total), chunks_done = COALESCE($2, chunks_done), embedding_batches_total = COALESCE($3, embedding_batches_total), embedding_batches_done = COALESCE($4, embedding_batches_done), updated_at = {} WHERE id = $5",
            crate::db::compat::current_timestamp_sql()
        ),
    )
    .bind(chunks_total)
    .bind(chunks_done)
    .bind(emb_total)
    .bind(emb_done)
    .bind(doc_id.to_string())
    .execute(pool)
    .await?;
    Ok(())
}

/// Full document processing pipeline (async task).
///
/// Steps:
/// 1. Download original file from MinIO
/// 2. Call Python doc-processor to parse
/// 3. Store Markdown in MinIO
/// 4. Chunk the Markdown
/// 5. Insert chunks into DB
/// 6. Generate embeddings
/// 7. Store embeddings in pgvector
/// 8. Update document status to 'ready'
pub async fn process_document(
    pool: DbPool,
    storage: StorageService,
    doc_processor_url: String,
    embedding_provider: Option<Arc<dyn EmbeddingProvider>>,
    doc_id: Uuid,
    workspace_id: Uuid,
) {
    if let Err(e) = process_document_inner(
        &pool,
        &storage,
        &doc_processor_url,
        embedding_provider.as_deref(),
        doc_id,
        workspace_id,
    )
    .await
    {
        let err_msg = e.to_string();
        let status = if err_msg.contains("[embedding]") {
            "embedding_failed"
        } else {
            "failed"
        };
        tracing::error!("Document processing failed for {} (status={}): {}", doc_id, status, err_msg);
        let _ = update_status(&pool, doc_id, status, Some(&err_msg)).await;
    }
}

/// Parse a document, returning (markdown, page_count, language, title).
/// In server mode, calls the external Python doc-processor.
/// In desktop mode, uses built-in Rust parsers.
#[cfg(feature = "postgres")]
async fn parse_document(
    file_bytes: &[u8],
    filename: &str,
    file_type: &str,
    doc_processor_url: &str,
) -> anyhow::Result<(String, Option<i32>, Option<String>, Option<String>)> {
    let parse_url = match file_type {
        "pdf" => format!("{}/api/parse/pdf", doc_processor_url),
        "docx" => format!("{}/api/parse/docx", doc_processor_url),
        "txt" | "md" | "html" => format!("{}/api/parse/txt", doc_processor_url),
        _ => anyhow::bail!("Unsupported file type: {}", file_type),
    };

    let client = reqwest::Client::new();
    let part = reqwest::multipart::Part::bytes(file_bytes.to_vec())
        .file_name(filename.to_string())
        .mime_str("application/octet-stream")?;
    let form = reqwest::multipart::Form::new().part("file", part);

    let response = client
        .post(&parse_url)
        .multipart(form)
        .send()
        .await
        .map_err(|e| anyhow::anyhow!("[doc-processor] request failed: {}", e))?
        .error_for_status()
        .map_err(|e| anyhow::anyhow!("[doc-processor] returned error status: {}", e))?;

    let response_bytes = response
        .bytes()
        .await
        .map_err(|e| anyhow::anyhow!("[doc-processor] failed to read response body: {}", e))?;

    let parse_result: DocProcessorResponse = serde_json::from_slice(&response_bytes)
        .map_err(|e| {
            let preview = String::from_utf8_lossy(
                &response_bytes[..response_bytes.len().min(500)],
            );
            anyhow::anyhow!(
                "[doc-processor] failed to deserialize response: {}. Body preview: {}",
                e, preview
            )
        })?;

    Ok((
        parse_result.markdown,
        parse_result.metadata.page_count,
        parse_result.metadata.language,
        parse_result.metadata.title,
    ))
}

#[cfg(sqlite_mode)]
async fn parse_document(
    file_bytes: &[u8],
    filename: &str,
    file_type: &str,
    _doc_processor_url: &str,
) -> anyhow::Result<(String, Option<i32>, Option<String>, Option<String>)> {
    let result = crate::services::local_doc_processor::parse_local_with_ocr(
        file_bytes, filename, file_type, true, "chi_sim+eng", None,
    ).await?;
    Ok((
        result.markdown,
        result.metadata.page_count,
        result.metadata.language,
        result.metadata.title,
    ))
}

async fn process_document_inner(
    pool: &DbPool,
    storage: &StorageService,
    doc_processor_url: &str,
    embedding_provider: Option<&dyn EmbeddingProvider>,
    doc_id: Uuid,
    workspace_id: Uuid,
) -> anyhow::Result<()> {
    update_status(pool, doc_id, "processing", None).await?;

    let doc = sqlx::query_as::<_, (String, String, String)>(
        "SELECT original_file_path, original_filename, file_type FROM documents WHERE id = $1",
    )
    .bind(doc_id.to_string())
    .fetch_one(pool)
    .await?;

    let (file_path, filename, file_type) = doc;

    let file_bytes = storage.download(&file_path).await?;

    let (markdown, page_count, language, title) = parse_document(
        &file_bytes, &filename, &file_type, doc_processor_url,
    ).await?;

    sqlx::query(
        r#"
        UPDATE documents
        SET page_count = $1, language = $2,
            title = COALESCE($3, title)
        WHERE id = $4
        "#,
    )
    .bind(page_count)
    .bind(&language)
    .bind(&title)
    .bind(doc_id.to_string())
    .execute(pool)
    .await?;

    let md_path = StorageService::markdown_path(&workspace_id, &doc_id);
    storage
        .upload(&md_path, bytes::Bytes::from(markdown.clone()))
        .await?;

    sqlx::query("UPDATE documents SET markdown_file_path = $1 WHERE id = $2")
        .bind(&md_path)
        .bind(doc_id.to_string())
        .execute(pool)
        .await?;

    update_status(pool, doc_id, "chunking", None).await?;
    tracing::info!(doc_id = %doc_id, markdown_len = markdown.len(), "Starting chunking");

    let chunk_config = ChunkConfig::default();
    let chunks = chunk_markdown(&markdown, &chunk_config);
    let chunks_total = chunks.len() as i32;
    tracing::info!(doc_id = %doc_id, chunk_count = chunks_total, "Chunking completed");

    update_progress(pool, doc_id, Some(chunks_total), Some(0), None, None).await?;

    sqlx::query("DELETE FROM document_chunks WHERE document_id = $1")
        .bind(doc_id.to_string())
        .execute(pool)
        .await?;

    let mut chunk_ids = Vec::with_capacity(chunks.len());
    let mut chunk_texts = Vec::with_capacity(chunks.len());

    for (ci, chunk) in chunks.iter().enumerate() {
        let chunk_id = Uuid::new_v4();
        chunk_ids.push(chunk_id);
        chunk_texts.push(chunk.content.clone());

        sqlx::query(
            r#"
            INSERT INTO document_chunks (
                id, document_id, chunk_index, heading_path, content,
                char_start, char_end, content_hash
            ) VALUES ($1, $2, $3, $4, $5, $6, $7, $8)
            "#,
        )
        .bind(chunk_id.to_string())
        .bind(doc_id.to_string())
        .bind(chunk.index as i32)
        .bind(&chunk.heading_path)
        .bind(&chunk.content)
        .bind(chunk.char_start as i64)
        .bind(chunk.char_end as i64)
        .bind(&chunk.content_hash)
        .execute(pool)
        .await?;

        if (ci + 1) % 50 == 0 || ci + 1 == chunks.len() {
            update_progress(pool, doc_id, None, Some((ci + 1) as i32), None, None).await?;
        }
    }

    if let Some(provider) = embedding_provider {
        update_status(pool, doc_id, "embedding", None).await?;
        tracing::info!(
            doc_id = %doc_id,
            chunks = chunk_texts.len(),
            model = %provider.model_name(),
            "Starting embedding generation"
        );

        let embed_batch = 32;
        let total_batches = (chunk_texts.len() + embed_batch - 1) / embed_batch;
        update_progress(pool, doc_id, None, None, Some(total_batches as i32), Some(0)).await?;

        let mut all_embeddings = Vec::with_capacity(chunk_texts.len());

        for (batch_idx, text_batch) in chunk_texts.chunks(embed_batch).enumerate() {
            tracing::debug!(
                doc_id = %doc_id,
                batch = batch_idx + 1,
                total = total_batches,
                "Embedding batch"
            );

            let batch_result = provider
                .embed_texts(text_batch)
                .await
                .map_err(|e| anyhow::anyhow!("[embedding] batch {} failed: {}", batch_idx + 1, e))?;
            all_embeddings.extend(batch_result);

            update_progress(pool, doc_id, None, None, None, Some((batch_idx + 1) as i32)).await?;
        }

        store_chunk_embeddings(pool, &chunk_ids, &all_embeddings)
            .await
            .map_err(|e| anyhow::anyhow!("[embedding] failed to store embeddings: {}", e))?;

        tracing::info!(doc_id = %doc_id, embeddings = all_embeddings.len(), "Embeddings stored");
    }

    update_status(pool, doc_id, "ready", None).await?;
    tracing::info!(doc_id = %doc_id, chunks = chunks.len(), "Document processing complete");

    Ok(())
}
