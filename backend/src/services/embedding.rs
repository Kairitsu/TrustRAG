use async_openai::{
    config::OpenAIConfig,
    types::{CreateEmbeddingRequest, EmbeddingInput},
    Client,
};
use async_trait::async_trait;
use uuid::Uuid;

use crate::db::DbPool;
use crate::traits::embedding_provider::EmbeddingProvider;

/// Ensure api_base ends with /v1 for OpenAI-compatible APIs.
/// async_openai appends /embeddings (etc.) to the base, so it must end with /v1.
pub fn normalize_api_base(url: &str) -> String {
    let trimmed = url.trim_end_matches('/');
    if trimmed.ends_with("/v1") {
        trimmed.to_string()
    } else {
        format!("{}/v1", trimmed)
    }
}

pub const DEFAULT_EMBEDDING_BATCH_SIZE: usize = 10;

pub struct OpenAIEmbeddingProvider {
    client: Client<OpenAIConfig>,
    model: String,
    dimensions: usize,
    batch_size: usize,
}

impl OpenAIEmbeddingProvider {
    pub fn new(api_base_url: &str, api_key: Option<&str>, model: &str, dimensions: usize) -> Self {
        Self::with_batch_size(api_base_url, api_key, model, dimensions, DEFAULT_EMBEDDING_BATCH_SIZE)
    }

    pub fn with_batch_size(
        api_base_url: &str,
        api_key: Option<&str>,
        model: &str,
        dimensions: usize,
        batch_size: usize,
    ) -> Self {
        let base = normalize_api_base(api_base_url);
        let mut config = OpenAIConfig::new().with_api_base(&base);
        if let Some(key) = api_key {
            config = config.with_api_key(key);
        }

        Self {
            client: Client::with_config(config),
            model: model.to_string(),
            dimensions,
            batch_size: batch_size.clamp(1, 2048),
        }
    }
}

#[async_trait]
impl EmbeddingProvider for OpenAIEmbeddingProvider {
    async fn embed_texts(&self, texts: &[String]) -> anyhow::Result<Vec<Vec<f32>>> {
        if texts.is_empty() {
            return Ok(vec![]);
        }

        let batch_size = self.batch_size;
        let mut all_embeddings = Vec::with_capacity(texts.len());

        for batch in texts.chunks(batch_size) {
            let input = EmbeddingInput::StringArray(batch.to_vec());
            let request = CreateEmbeddingRequest {
                model: self.model.clone(),
                input,
                encoding_format: None,
                user: None,
                dimensions: Some(self.dimensions as u32),
            };

            let response = self.client.embeddings().create(request).await?;
            let mut batch_embeddings: Vec<(usize, Vec<f32>)> = response
                .data
                .into_iter()
                .map(|e| (e.index as usize, e.embedding))
                .collect();

            batch_embeddings.sort_by_key(|(idx, _)| *idx);
            all_embeddings.extend(batch_embeddings.into_iter().map(|(_, emb)| emb));
        }

        Ok(all_embeddings)
    }

    fn dimensions(&self) -> usize {
        self.dimensions
    }

    fn model_name(&self) -> &str {
        &self.model
    }
}

pub struct OllamaEmbeddingProvider {
    client: reqwest::Client,
    base_url: String,
    model: String,
    dimensions: usize,
}

impl OllamaEmbeddingProvider {
    pub fn new(base_url: &str, model: &str, dimensions: usize) -> Self {
        Self {
            client: reqwest::Client::new(),
            base_url: base_url.trim_end_matches('/').to_string(),
            model: model.to_string(),
            dimensions,
        }
    }
}

#[async_trait]
impl EmbeddingProvider for OllamaEmbeddingProvider {
    async fn embed_texts(&self, texts: &[String]) -> anyhow::Result<Vec<Vec<f32>>> {
        if texts.is_empty() {
            return Ok(vec![]);
        }

        let mut all_embeddings = Vec::with_capacity(texts.len());

        for text in texts {
            let resp = self.client
                .post(format!("{}/api/embed", self.base_url))
                .json(&serde_json::json!({
                    "model": self.model,
                    "input": text,
                }))
                .timeout(std::time::Duration::from_secs(30))
                .send()
                .await?;

            let body: serde_json::Value = resp.json().await?;

            if let Some(embeddings) = body["embeddings"].as_array() {
                if let Some(first) = embeddings.first() {
                    let emb: Vec<f32> = first
                        .as_array()
                        .unwrap_or(&vec![])
                        .iter()
                        .filter_map(|v| v.as_f64().map(|f| f as f32))
                        .collect();
                    all_embeddings.push(emb);
                } else {
                    anyhow::bail!("Empty embeddings in Ollama response");
                }
            } else {
                anyhow::bail!("Unexpected Ollama embed response format");
            }
        }

        Ok(all_embeddings)
    }

    fn dimensions(&self) -> usize {
        self.dimensions
    }

    fn model_name(&self) -> &str {
        &self.model
    }
}

/// Write chunk embeddings to the database.
/// On postgres: uses pgvector column. On sqlite (desktop): stores as BLOB.
pub async fn store_chunk_embeddings(
    pool: &DbPool,
    chunk_ids: &[Uuid],
    embeddings: &[Vec<f32>],
) -> anyhow::Result<()> {
    if chunk_ids.len() != embeddings.len() {
        anyhow::bail!(
            "chunk_ids ({}) and embeddings ({}) length mismatch",
            chunk_ids.len(),
            embeddings.len()
        );
    }

    if chunk_ids.is_empty() {
        return Ok(());
    }

    #[cfg(feature = "postgres")]
    {
        let batch_size = 50;
        for batch_start in (0..chunk_ids.len()).step_by(batch_size) {
            let batch_end = (batch_start + batch_size).min(chunk_ids.len());
            let batch_ids = &chunk_ids[batch_start..batch_end];
            let batch_embeddings = &embeddings[batch_start..batch_end];

            let mut query = String::from(
                "UPDATE document_chunks SET embedding = v.emb::vector FROM (VALUES "
            );

            for (i, (chunk_id, embedding)) in batch_ids.iter().zip(batch_embeddings.iter()).enumerate() {
                if i > 0 {
                    query.push_str(", ");
                }
                let embedding_str = format!(
                    "[{}]",
                    embedding.iter().map(|v| v.to_string()).collect::<Vec<_>>().join(",")
                );
                query.push_str(&format!("('{}'::uuid, '{}')", chunk_id, embedding_str));
            }

            query.push_str(") AS v(id, emb) WHERE document_chunks.id = v.id");

            sqlx::query(&query).execute(pool).await?;
        }
    }

    #[cfg(sqlite_mode)]
    {
        for (chunk_id, embedding) in chunk_ids.iter().zip(embeddings.iter()) {
            let blob = embedding_to_blob(embedding);
            sqlx::query("UPDATE document_chunks SET embedding = ?1 WHERE id = ?2")
                .bind(&blob)
                .bind(chunk_id.to_string())
                .execute(pool)
                .await?;
        }
    }

    Ok(())
}

#[cfg(sqlite_mode)]
fn embedding_to_blob(embedding: &[f32]) -> Vec<u8> {
    embedding.iter().flat_map(|f| f.to_le_bytes()).collect()
}

#[cfg(sqlite_mode)]
pub fn blob_to_embedding(blob: &[u8]) -> Vec<f32> {
    blob.chunks_exact(4)
        .map(|chunk| f32::from_le_bytes([chunk[0], chunk[1], chunk[2], chunk[3]]))
        .collect()
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn test_embedding_str_format() {
        let embedding = vec![0.1_f32, 0.2, 0.3];
        let embedding_str = format!(
            "[{}]",
            embedding
                .iter()
                .map(|v| v.to_string())
                .collect::<Vec<_>>()
                .join(",")
        );
        assert_eq!(embedding_str, "[0.1,0.2,0.3]");
    }

    #[test]
    fn test_provider_new() {
        let provider = OpenAIEmbeddingProvider::new(
            "http://localhost:11434/v1",
            None,
            "nomic-embed-text",
            768,
        );
        assert_eq!(provider.dimensions(), 768);
        assert_eq!(provider.model_name(), "nomic-embed-text");
        assert_eq!(provider.batch_size, DEFAULT_EMBEDDING_BATCH_SIZE);
    }

    #[test]
    fn test_provider_with_custom_batch_size() {
        let provider = OpenAIEmbeddingProvider::with_batch_size(
            "http://localhost:11434/v1",
            None,
            "nomic-embed-text",
            768,
            5,
        );
        assert_eq!(provider.batch_size, 5);

        let clamped = OpenAIEmbeddingProvider::with_batch_size(
            "http://localhost:11434/v1",
            None,
            "nomic-embed-text",
            768,
            0,
        );
        assert_eq!(clamped.batch_size, 1);

        let clamped_high = OpenAIEmbeddingProvider::with_batch_size(
            "http://localhost:11434/v1",
            None,
            "nomic-embed-text",
            768,
            9999,
        );
        assert_eq!(clamped_high.batch_size, 2048);
    }

    #[test]
    fn test_ollama_provider_new() {
        let provider = OllamaEmbeddingProvider::new(
            "http://localhost:11434",
            "nomic-embed-text",
            768,
        );
        assert_eq!(provider.dimensions(), 768);
        assert_eq!(provider.model_name(), "nomic-embed-text");
        assert_eq!(provider.base_url, "http://localhost:11434");
    }

    #[test]
    fn test_normalize_api_base() {
        assert_eq!(normalize_api_base("https://api.openai.com/v1"), "https://api.openai.com/v1");
        assert_eq!(normalize_api_base("https://api.openai.com/v1/"), "https://api.openai.com/v1");
        assert_eq!(normalize_api_base("https://ai-gateway.vercel.sh"), "https://ai-gateway.vercel.sh/v1");
        assert_eq!(normalize_api_base("https://ai-gateway.vercel.sh/"), "https://ai-gateway.vercel.sh/v1");
        assert_eq!(normalize_api_base("http://localhost:11434"), "http://localhost:11434/v1");
    }
}
