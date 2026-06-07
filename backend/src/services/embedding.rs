use std::sync::Arc;

use async_openai::{
    config::OpenAIConfig,
    types::{CreateEmbeddingRequest, EmbeddingInput},
    Client,
};
use async_trait::async_trait;
use uuid::Uuid;

use crate::db::DbPool;
use crate::services::endpoint_resolver::{
    resolve_stored_endpoint, EndpointMode, ModelType, ResolvedEndpoint,
};
use crate::traits::embedding_provider::EmbeddingProvider;

/// Ensure api_base ends with /v1 for OpenAI-compatible APIs.
/// async_openai appends /embeddings (etc.) to the base, so it must end with /v1.
pub fn normalize_api_base(url: &str) -> String {
    crate::services::endpoint_resolver::normalize_openai_base(url)
}

pub const DEFAULT_EMBEDDING_BATCH_SIZE: usize = 10;

pub struct OpenAIEmbeddingProvider {
    client: Client<OpenAIConfig>,
    model: String,
    dimensions: usize,
    batch_size: usize,
}

impl OpenAIEmbeddingProvider {
    pub fn new(
        provider: &str,
        api_base_url: &str,
        endpoint_mode: Option<&str>,
        api_key: Option<&str>,
        model: &str,
        dimensions: usize,
    ) -> Self {
        Self::with_batch_size(
            provider,
            api_base_url,
            endpoint_mode,
            api_key,
            model,
            dimensions,
            DEFAULT_EMBEDDING_BATCH_SIZE,
        )
    }

    pub fn with_batch_size(
        provider: &str,
        api_base_url: &str,
        endpoint_mode: Option<&str>,
        api_key: Option<&str>,
        model: &str,
        dimensions: usize,
        batch_size: usize,
    ) -> Self {
        let resolved = resolve_stored_endpoint(
            ModelType::Embedding,
            provider,
            endpoint_mode,
            api_base_url,
            model,
        );
        Self::from_resolved(&resolved, api_key, model, dimensions, batch_size)
    }

    fn from_resolved(
        resolved: &ResolvedEndpoint,
        api_key: Option<&str>,
        model: &str,
        dimensions: usize,
        batch_size: usize,
    ) -> Self {
        let base = resolved
            .final_url
            .trim_end_matches("/embeddings")
            .trim_end_matches('/');
        let mut config = OpenAIConfig::new().with_api_base(base);
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

/// Direct HTTP embedding provider for full_endpoint mode.
pub struct HttpEmbeddingProvider {
    client: reqwest::Client,
    embeddings_url: String,
    api_key: Option<String>,
    model: String,
    dimensions: usize,
    batch_size: usize,
}

impl HttpEmbeddingProvider {
    pub fn new(
        provider: &str,
        api_base_url: &str,
        endpoint_mode: Option<&str>,
        api_key: Option<&str>,
        model: &str,
        dimensions: usize,
        batch_size: usize,
    ) -> Self {
        let resolved = resolve_stored_endpoint(
            ModelType::Embedding,
            provider,
            endpoint_mode,
            api_base_url,
            model,
        );
        Self {
            client: reqwest::Client::new(),
            embeddings_url: resolved.final_url,
            api_key: api_key.map(|s| s.to_string()),
            model: model.to_string(),
            dimensions,
            batch_size: batch_size.clamp(1, 2048),
        }
    }

    pub fn resolved_url(&self) -> &str {
        &self.embeddings_url
    }
}

#[async_trait]
impl EmbeddingProvider for HttpEmbeddingProvider {
    async fn embed_texts(&self, texts: &[String]) -> anyhow::Result<Vec<Vec<f32>>> {
        if texts.is_empty() {
            return Ok(vec![]);
        }

        let mut all_embeddings = Vec::with_capacity(texts.len());

        for batch in texts.chunks(self.batch_size) {
            let body = serde_json::json!({
                "model": self.model,
                "input": batch,
                "dimensions": self.dimensions,
            });

            let mut req = self.client.post(&self.embeddings_url).json(&body);
            if let Some(key) = &self.api_key {
                req = req.bearer_auth(key);
            }

            let resp = req
                .timeout(std::time::Duration::from_secs(60))
                .send()
                .await?;

            if !resp.status().is_success() {
                let status = resp.status();
                let text = resp.text().await.unwrap_or_default();
                anyhow::bail!("Embedding API error ({}): {}", status, text);
            }

            let json: serde_json::Value = resp.json().await?;
            let data = json["data"]
                .as_array()
                .ok_or_else(|| anyhow::anyhow!("Missing data array in embedding response"))?;

            let mut batch_embeddings: Vec<(usize, Vec<f32>)> = data
                .iter()
                .filter_map(|item| {
                    let idx = item["index"].as_u64()? as usize;
                    let emb: Vec<f32> = item["embedding"]
                        .as_array()?
                        .iter()
                        .filter_map(|v| v.as_f64().map(|f| f as f32))
                        .collect();
                    Some((idx, emb))
                })
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

pub fn build_embedding_provider(
    provider: &str,
    api_base_url: &str,
    endpoint_mode: Option<&str>,
    api_key: Option<&str>,
    model: &str,
    dimensions: usize,
    batch_size: usize,
) -> Arc<dyn EmbeddingProvider> {
    let mode = crate::services::endpoint_resolver::effective_endpoint_mode(
        ModelType::Embedding,
        endpoint_mode,
        api_base_url,
    );

    if provider == "ollama" {
        return Arc::new(OllamaEmbeddingProvider::new(
            api_base_url,
            model,
            dimensions,
        ));
    }

    if mode == EndpointMode::FullEndpoint {
        Arc::new(HttpEmbeddingProvider::new(
            provider,
            api_base_url,
            endpoint_mode,
            api_key,
            model,
            dimensions,
            batch_size,
        ))
    } else {
        Arc::new(OpenAIEmbeddingProvider::with_batch_size(
            provider,
            api_base_url,
            endpoint_mode,
            api_key,
            model,
            dimensions,
            batch_size,
        ))
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
            "openai",
            "http://localhost:11434/v1",
            Some(EndpointMode::BaseUrl.as_str()),
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
            "openai",
            "http://localhost:11434/v1",
            Some(EndpointMode::BaseUrl.as_str()),
            None,
            "nomic-embed-text",
            768,
            5,
        );
        assert_eq!(provider.batch_size, 5);

        let clamped = OpenAIEmbeddingProvider::with_batch_size(
            "openai",
            "http://localhost:11434/v1",
            Some(EndpointMode::BaseUrl.as_str()),
            None,
            "nomic-embed-text",
            768,
            0,
        );
        assert_eq!(clamped.batch_size, 1);

        let clamped_high = OpenAIEmbeddingProvider::with_batch_size(
            "openai",
            "http://localhost:11434/v1",
            Some(EndpointMode::BaseUrl.as_str()),
            None,
            "nomic-embed-text",
            768,
            9999,
        );
        assert_eq!(clamped_high.batch_size, 2048);
    }

    #[test]
    fn test_http_embedding_provider_full_endpoint() {
        let provider = HttpEmbeddingProvider::new(
            "custom",
            "https://example.com/v1/embeddings",
            Some(EndpointMode::FullEndpoint.as_str()),
            None,
            "text-embedding-3-small",
            1536,
            10,
        );
        assert_eq!(
            provider.resolved_url(),
            "https://example.com/v1/embeddings"
        );
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
