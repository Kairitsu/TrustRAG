use serde::{Deserialize, Serialize};

/// Model category for endpoint resolution.
#[derive(Debug, Clone, Copy, PartialEq, Eq, Serialize, Deserialize)]
#[serde(rename_all = "snake_case")]
pub enum ModelType {
    Llm,
    Embedding,
    Rerank,
}

/// How the user-provided endpoint should be interpreted.
#[derive(Debug, Clone, Copy, PartialEq, Eq, Serialize, Deserialize, Default)]
#[serde(rename_all = "snake_case")]
pub enum EndpointMode {
    #[default]
    BaseUrl,
    FullEndpoint,
}

impl EndpointMode {
    pub fn from_db_value(value: Option<&str>) -> Self {
        match value {
            Some("full_endpoint") => Self::FullEndpoint,
            _ => Self::BaseUrl,
        }
    }

    pub fn as_str(&self) -> &'static str {
        match self {
            Self::BaseUrl => "base_url",
            Self::FullEndpoint => "full_endpoint",
        }
    }
}

/// Request/response format for the resolved endpoint.
#[derive(Debug, Clone, Copy, PartialEq, Eq, Serialize, Deserialize)]
#[serde(rename_all = "snake_case")]
pub enum RequestFormat {
    OpenAiChatCompletions,
    OpenAiEmbeddings,
    OpenAiRerank,
}

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct EndpointDebugInfo {
    pub model_type: String,
    pub provider: String,
    pub endpoint_mode: String,
    pub user_endpoint: String,
    pub appended_path: Option<String>,
    pub normalized_base: Option<String>,
}

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct ResolvedEndpoint {
    pub final_url: String,
    pub request_format: RequestFormat,
    pub debug_info: EndpointDebugInfo,
}

#[derive(Debug, Clone)]
pub struct ResolveInput<'a> {
    pub model_type: ModelType,
    pub provider: &'a str,
    pub endpoint_mode: EndpointMode,
    pub user_endpoint: &'a str,
    pub model_name: &'a str,
}

/// Trim whitespace and trailing slashes from a URL (safe normalization only).
pub fn normalize_user_endpoint(url: &str) -> String {
    url.trim().trim_end_matches('/').to_string()
}

/// Infer endpoint mode from legacy configs that stored a full path in api_base_url.
pub fn infer_endpoint_mode(model_type: ModelType, user_endpoint: &str) -> EndpointMode {
    let normalized = normalize_user_endpoint(user_endpoint);
    let path = url_path(&normalized).to_lowercase();

    let is_full = match model_type {
        ModelType::Llm => path.ends_with("/chat/completions"),
        ModelType::Embedding => path.ends_with("/embeddings"),
        ModelType::Rerank => path.ends_with("/rerank") || path.ends_with("/reranks"),
    };

    if is_full {
        EndpointMode::FullEndpoint
    } else {
        EndpointMode::BaseUrl
    }
}

/// Resolve the stored endpoint_mode, applying legacy path-based migration when unset.
pub fn effective_endpoint_mode(
    model_type: ModelType,
    stored_mode: Option<&str>,
    user_endpoint: &str,
) -> EndpointMode {
    match stored_mode {
        Some(mode) if !mode.is_empty() => EndpointMode::from_db_value(Some(mode)),
        _ => infer_endpoint_mode(model_type, user_endpoint),
    }
}

/// Ensure api_base ends with /v1 for OpenAI-compatible base_url mode.
pub fn normalize_openai_base(url: &str) -> String {
    let trimmed = normalize_user_endpoint(url);
    if trimmed.ends_with("/v1") {
        trimmed
    } else {
        format!("{}/v1", trimmed)
    }
}

fn url_path(url: &str) -> &str {
    match url.find("://") {
        Some(idx) => {
            let rest = &url[idx + 3..];
            rest.find('/').map(|p| &rest[p..]).unwrap_or("/")
        }
        None => url,
    }
}

fn join_url(base: &str, path: &str) -> String {
    let base = normalize_user_endpoint(base);
    let path = path.trim_start_matches('/');
    format!("{}/{}", base, path)
}

/// Provider-specific default path for rerank base_url mode.
pub fn rerank_default_path(provider: &str) -> &'static str {
    match provider.to_lowercase().as_str() {
        "dashscope" => "/reranks",
        "jina" => "/rerank",
        "cohere" => "/rerank",
        "openai" => "/rerank",
        "voyage" => "/rerank",
        _ => "/rerank",
    }
}

fn default_path(model_type: ModelType, provider: &str) -> &'static str {
    match model_type {
        ModelType::Llm => "/chat/completions",
        ModelType::Embedding => "/embeddings",
        ModelType::Rerank => rerank_default_path(provider),
    }
}

fn request_format_for(model_type: ModelType) -> RequestFormat {
    match model_type {
        ModelType::Llm => RequestFormat::OpenAiChatCompletions,
        ModelType::Embedding => RequestFormat::OpenAiEmbeddings,
        ModelType::Rerank => RequestFormat::OpenAiRerank,
    }
}

/// Unified endpoint resolver used by connection tests and runtime calls.
pub fn resolve_endpoint(input: &ResolveInput<'_>) -> ResolvedEndpoint {
    let user_endpoint = normalize_user_endpoint(input.user_endpoint);
    let request_format = request_format_for(input.model_type);

    match input.endpoint_mode {
        EndpointMode::FullEndpoint => ResolvedEndpoint {
            final_url: user_endpoint.clone(),
            request_format,
            debug_info: EndpointDebugInfo {
                model_type: format!("{:?}", input.model_type).to_lowercase(),
                provider: input.provider.to_string(),
                endpoint_mode: EndpointMode::FullEndpoint.as_str().to_string(),
                user_endpoint: user_endpoint.clone(),
                appended_path: None,
                normalized_base: None,
            },
        },
        EndpointMode::BaseUrl => {
            let path = default_path(input.model_type, input.provider);
            let normalized_base = match input.model_type {
                ModelType::Llm | ModelType::Embedding => {
                    Some(normalize_openai_base(&user_endpoint))
                }
                ModelType::Rerank => Some(normalize_openai_base(&user_endpoint)),
            };
            let base = normalized_base.as_deref().unwrap_or(&user_endpoint);
            let final_url = join_url(base, path);

            ResolvedEndpoint {
                final_url,
                request_format,
                debug_info: EndpointDebugInfo {
                    model_type: format!("{:?}", input.model_type).to_lowercase(),
                    provider: input.provider.to_string(),
                    endpoint_mode: EndpointMode::BaseUrl.as_str().to_string(),
                    user_endpoint: user_endpoint.clone(),
                    appended_path: Some(path.to_string()),
                    normalized_base,
                },
            }
        }
    }
}

/// Convenience wrapper that applies legacy migration rules.
pub fn resolve_stored_endpoint(
    model_type: ModelType,
    provider: &str,
    stored_mode: Option<&str>,
    user_endpoint: &str,
    model_name: &str,
) -> ResolvedEndpoint {
    let endpoint_mode = effective_endpoint_mode(model_type, stored_mode, user_endpoint);
    resolve_endpoint(&ResolveInput {
        model_type,
        provider,
        endpoint_mode,
        user_endpoint,
        model_name,
    })
}

/// Redact API keys from error messages and response bodies.
pub fn redact_api_key(text: &str, api_key: Option<&str>) -> String {
    let mut result = text.to_string();
    if let Some(key) = api_key {
        if !key.is_empty() {
            result = result.replace(key, "***");
            if key.len() > 8 {
                let prefix = &key[..4.min(key.len())];
                let suffix = &key[key.len().saturating_sub(4)..];
                if prefix.len() + suffix.len() < key.len() {
                    result = result.replace(&format!("{}{}", prefix, suffix), "***");
                }
            }
        }
    }
    for pattern in ["sk-", "Bearer ", "api_key", "api-key", "authorization"] {
        if result.to_lowercase().contains(pattern) && result.len() > 20 {
            // Best-effort: mask long token-like substrings after Bearer/sk-
            if let Some(idx) = result.find("Bearer ") {
                let after = &result[idx + 7..];
                if let Some(end) = after.find(|c: char| c.is_whitespace() || c == '"' || c == '\'') {
                    let token = &result[idx + 7..idx + 7 + end];
                    if token.len() > 6 {
                        result = result.replace(token, "***");
                    }
                }
            }
        }
    }
    result
}

#[cfg(test)]
mod tests {
    use super::*;

    fn resolve(
        model_type: ModelType,
        provider: &str,
        endpoint_mode: EndpointMode,
        user_endpoint: &str,
    ) -> ResolvedEndpoint {
        resolve_endpoint(&ResolveInput {
            model_type,
            provider,
            endpoint_mode,
            user_endpoint,
            model_name: "test-model",
        })
    }

    #[test]
    fn llm_base_url_appends_chat_completions() {
        let r = resolve(
            ModelType::Llm,
            "openai",
            EndpointMode::BaseUrl,
            "https://example.com/v1",
        );
        assert_eq!(r.final_url, "https://example.com/v1/chat/completions");
    }

    #[test]
    fn llm_full_endpoint_unchanged() {
        let url = "https://example.com/v1/chat/completions";
        let r = resolve(ModelType::Llm, "openai", EndpointMode::FullEndpoint, url);
        assert_eq!(r.final_url, url);
    }

    #[test]
    fn embedding_base_url_appends_embeddings() {
        let r = resolve(
            ModelType::Embedding,
            "openai",
            EndpointMode::BaseUrl,
            "https://example.com/v1",
        );
        assert_eq!(r.final_url, "https://example.com/v1/embeddings");
    }

    #[test]
    fn embedding_full_endpoint_unchanged() {
        let url = "https://example.com/v1/embeddings";
        let r = resolve(ModelType::Embedding, "openai", EndpointMode::FullEndpoint, url);
        assert_eq!(r.final_url, url);
    }

    #[test]
    fn rerank_full_endpoint_dashscope_unchanged() {
        let url = "https://dashscope.aliyuncs.com/compatible-api/v1/reranks";
        let r = resolve(ModelType::Rerank, "dashscope", EndpointMode::FullEndpoint, url);
        assert_eq!(r.final_url, url);
        assert!(!r.final_url.contains("/reranks/rerank"));
    }

    #[test]
    fn rerank_base_url_dashscope_uses_reranks_path() {
        let r = resolve(
            ModelType::Rerank,
            "dashscope",
            EndpointMode::BaseUrl,
            "https://dashscope.aliyuncs.com/compatible-api/v1",
        );
        assert_eq!(
            r.final_url,
            "https://dashscope.aliyuncs.com/compatible-api/v1/reranks"
        );
    }

    #[test]
    fn rerank_base_url_jina_uses_rerank_path() {
        let r = resolve(
            ModelType::Rerank,
            "jina",
            EndpointMode::BaseUrl,
            "https://api.jina.ai/v1",
        );
        assert_eq!(r.final_url, "https://api.jina.ai/v1/rerank");
    }

    #[test]
    fn rerank_full_endpoint_custom_paths_unchanged() {
        for url in [
            "https://example.com/v1/rerank",
            "https://example.com/v1/reranks",
        ] {
            let r = resolve(ModelType::Rerank, "custom", EndpointMode::FullEndpoint, url);
            assert_eq!(r.final_url, url);
            assert!(!r.final_url.ends_with("/rerank/rerank"));
            assert!(!r.final_url.ends_with("/reranks/rerank"));
        }
    }

    #[test]
    fn legacy_migration_reranks_suffix_becomes_full_endpoint() {
        let url = "https://dashscope.aliyuncs.com/compatible-api/v1/reranks";
        let mode = infer_endpoint_mode(ModelType::Rerank, url);
        assert_eq!(mode, EndpointMode::FullEndpoint);

        let r = resolve_stored_endpoint(ModelType::Rerank, "dashscope", None, url, "qwen3-rerank");
        assert_eq!(r.final_url, url);
        assert!(!r.final_url.contains("/reranks/rerank"));
    }

    #[test]
    fn legacy_migration_chat_completions_becomes_full_endpoint() {
        let url = "https://example.com/v1/chat/completions";
        assert_eq!(
            infer_endpoint_mode(ModelType::Llm, url),
            EndpointMode::FullEndpoint
        );
    }

    #[test]
    fn legacy_migration_embeddings_becomes_full_endpoint() {
        let url = "https://example.com/v1/embeddings";
        assert_eq!(
            infer_endpoint_mode(ModelType::Embedding, url),
            EndpointMode::FullEndpoint
        );
    }

    #[test]
    fn full_endpoint_does_not_append_v1() {
        let url = "https://dashscope.aliyuncs.com/compatible-api/v1/reranks";
        let r = resolve(ModelType::Rerank, "custom", EndpointMode::FullEndpoint, url);
        assert_eq!(r.final_url, url);
        assert!(!r.final_url.contains("api-openai"));
    }

    #[test]
    fn redact_api_key_masks_key() {
        let key = "sk-test-secret-key-12345";
        let msg = format!("Auth failed with key {}", key);
        let redacted = redact_api_key(&msg, Some(key));
        assert!(!redacted.contains(key));
        assert!(redacted.contains("***"));
    }

    #[test]
    fn normalize_user_endpoint_trims_slashes_and_spaces() {
        assert_eq!(
            normalize_user_endpoint("  https://example.com/v1/  "),
            "https://example.com/v1"
        );
    }
}