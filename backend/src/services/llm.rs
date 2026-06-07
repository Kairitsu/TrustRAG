use async_trait::async_trait;
use serde::{Deserialize, Serialize};
use tokio::sync::mpsc;

use crate::services::endpoint_resolver::{
    resolve_stored_endpoint, EndpointMode, ModelType, ResolvedEndpoint,
};
use crate::traits::llm_provider::{LlmMessage, LlmProvider, LlmRequest, LlmResponse, StreamEvent};

/// OpenAI-compatible LLM provider (works with OpenAI, Ollama, vLLM, etc.)
pub struct OpenAILlmProvider {
    client: reqwest::Client,
    chat_completions_url: String,
    api_key: Option<String>,
    model: String,
}

impl OpenAILlmProvider {
    pub fn from_resolved(resolved: &ResolvedEndpoint, api_key: Option<&str>, model: &str) -> Self {
        Self {
            client: reqwest::Client::new(),
            chat_completions_url: resolved.final_url.clone(),
            api_key: api_key.map(|s| s.to_string()),
            model: model.to_string(),
        }
    }

    pub fn new(
        provider: &str,
        api_base_url: &str,
        endpoint_mode: Option<&str>,
        api_key: Option<&str>,
        model: &str,
    ) -> Self {
        let resolved = resolve_stored_endpoint(
            ModelType::Llm,
            provider,
            endpoint_mode,
            api_base_url,
            model,
        );
        Self::from_resolved(&resolved, api_key, model)
    }

    pub fn resolved_url(&self) -> &str {
        &self.chat_completions_url
    }
}

// ── OpenAI API types ──

#[derive(Serialize)]
struct ChatRequest {
    model: String,
    messages: Vec<ChatMessage>,
    temperature: f32,
    max_tokens: u32,
    stream: bool,
}

#[derive(Serialize)]
struct ChatMessage {
    role: String,
    content: String,
}

#[derive(Deserialize)]
struct ChatResponse {
    choices: Vec<ChatChoice>,
    usage: Option<Usage>,
    model: String,
}

#[derive(Deserialize)]
struct ChatChoice {
    message: Option<ChoiceMessage>,
    delta: Option<ChoiceDelta>,
    finish_reason: Option<String>,
}

#[derive(Deserialize)]
struct ChoiceMessage {
    content: Option<String>,
}

#[derive(Deserialize)]
struct ChoiceDelta {
    content: Option<String>,
}

#[derive(Deserialize)]
struct Usage {
    prompt_tokens: u32,
    completion_tokens: u32,
}

#[derive(Deserialize)]
struct StreamChunk {
    choices: Vec<ChatChoice>,
    model: Option<String>,
    usage: Option<Usage>,
}

impl From<&LlmMessage> for ChatMessage {
    fn from(msg: &LlmMessage) -> Self {
        ChatMessage {
            role: msg.role.clone(),
            content: msg.content.clone(),
        }
    }
}

#[async_trait]
impl LlmProvider for OpenAILlmProvider {
    async fn generate(&self, request: &LlmRequest) -> anyhow::Result<LlmResponse> {
        let body = ChatRequest {
            model: self.model.clone(),
            messages: request.messages.iter().map(ChatMessage::from).collect(),
            temperature: request.temperature,
            max_tokens: request.max_tokens,
            stream: false,
        };

        let mut req = self.client.post(&self.chat_completions_url).json(&body);
        if let Some(key) = &self.api_key {
            req = req.bearer_auth(key);
        }

        let resp = req
            .timeout(std::time::Duration::from_secs(120))
            .send()
            .await?;

        if !resp.status().is_success() {
            let status = resp.status();
            let text = resp.text().await.unwrap_or_default();
            anyhow::bail!("LLM API error ({}): {}", status, text);
        }

        let chat_resp: ChatResponse = resp.json().await?;
        let content = chat_resp
            .choices
            .first()
            .and_then(|c| c.message.as_ref())
            .and_then(|m| m.content.clone())
            .unwrap_or_default();

        let usage = chat_resp.usage.unwrap_or(Usage {
            prompt_tokens: 0,
            completion_tokens: 0,
        });

        Ok(LlmResponse {
            content,
            prompt_tokens: usage.prompt_tokens,
            completion_tokens: usage.completion_tokens,
            model: chat_resp.model,
        })
    }

    async fn stream(
        &self,
        request: &LlmRequest,
        tx: mpsc::Sender<StreamEvent>,
    ) -> anyhow::Result<()> {
        let body = ChatRequest {
            model: self.model.clone(),
            messages: request.messages.iter().map(ChatMessage::from).collect(),
            temperature: request.temperature,
            max_tokens: request.max_tokens,
            stream: true,
        };

        let mut req = self.client.post(&self.chat_completions_url).json(&body);
        if let Some(key) = &self.api_key {
            req = req.bearer_auth(key);
        }

        let resp = req
            .timeout(std::time::Duration::from_secs(300))
            .send()
            .await?;

        if !resp.status().is_success() {
            let status = resp.status();
            let text = resp.text().await.unwrap_or_default();
            let _ = tx.send(StreamEvent::Error(format!("LLM API error ({}): {}", status, text))).await;
            return Ok(());
        }

        use futures_util::StreamExt;
        let mut stream = resp.bytes_stream();
        let mut buffer = String::new();
        let mut full_content = String::new();
        let mut model_name = self.model.clone();
        let mut total_usage: Option<Usage> = None;

        while let Some(chunk_result) = stream.next().await {
            let chunk = match chunk_result {
                Ok(c) => c,
                Err(e) => {
                    let _ = tx.send(StreamEvent::Error(e.to_string())).await;
                    return Ok(());
                }
            };

            buffer.push_str(&String::from_utf8_lossy(&chunk));

            while let Some(line_end) = buffer.find('\n') {
                let line = buffer[..line_end].trim().to_string();
                buffer = buffer[line_end + 1..].to_string();

                if line.is_empty() || !line.starts_with("data: ") {
                    continue;
                }

                let data = &line[6..];
                if data == "[DONE]" {
                    let _ = tx
                        .send(StreamEvent::Done(LlmResponse {
                            content: full_content.clone(),
                            prompt_tokens: total_usage.as_ref().map_or(0, |u| u.prompt_tokens),
                            completion_tokens: total_usage
                                .as_ref()
                                .map_or(0, |u| u.completion_tokens),
                            model: model_name.clone(),
                        }))
                        .await;
                    return Ok(());
                }

                if let Ok(chunk) = serde_json::from_str::<StreamChunk>(data) {
                    if let Some(m) = &chunk.model {
                        model_name = m.clone();
                    }
                    if let Some(u) = chunk.usage {
                        total_usage = Some(u);
                    }
                    if let Some(choice) = chunk.choices.first() {
                        if let Some(delta) = &choice.delta {
                            if let Some(content) = &delta.content {
                                full_content.push_str(content);
                                if tx.send(StreamEvent::Delta(content.clone())).await.is_err() {
                                    return Ok(());
                                }
                            }
                        }
                        if choice.finish_reason.is_some() && choice.finish_reason.as_deref() != Some("") {
                            let _ = tx
                                .send(StreamEvent::Done(LlmResponse {
                                    content: full_content.clone(),
                                    prompt_tokens: total_usage.as_ref().map_or(0, |u| u.prompt_tokens),
                                    completion_tokens: total_usage
                                        .as_ref()
                                        .map_or(0, |u| u.completion_tokens),
                                    model: model_name.clone(),
                                }))
                                .await;
                            return Ok(());
                        }
                    }
                }
            }
        }

        // Stream ended without [DONE]
        let _ = tx
            .send(StreamEvent::Done(LlmResponse {
                content: full_content,
                prompt_tokens: total_usage.as_ref().map_or(0, |u| u.prompt_tokens),
                completion_tokens: total_usage.as_ref().map_or(0, |u| u.completion_tokens),
                model: model_name,
            }))
            .await;

        Ok(())
    }

    fn model_name(&self) -> &str {
        &self.model
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn test_provider_creation() {
        let provider = OpenAILlmProvider::new(
            "ollama",
            "http://localhost:11434/v1",
            Some(EndpointMode::BaseUrl.as_str()),
            None,
            "qwen2.5:72b",
        );
        assert_eq!(provider.model_name(), "qwen2.5:72b");
        assert_eq!(
            provider.resolved_url(),
            "http://localhost:11434/v1/chat/completions"
        );
        assert!(provider.api_key.is_none());
    }

    #[test]
    fn test_provider_with_api_key() {
        let provider = OpenAILlmProvider::new(
            "openai",
            "https://api.openai.com/v1/",
            Some(EndpointMode::BaseUrl.as_str()),
            Some("sk-test"),
            "gpt-4o",
        );
        assert_eq!(
            provider.resolved_url(),
            "https://api.openai.com/v1/chat/completions"
        );
        assert_eq!(provider.api_key.as_deref(), Some("sk-test"));
    }

    #[test]
    fn test_provider_full_endpoint() {
        let provider = OpenAILlmProvider::new(
            "custom",
            "https://example.com/v1/chat/completions",
            Some(EndpointMode::FullEndpoint.as_str()),
            None,
            "gpt-4o",
        );
        assert_eq!(
            provider.resolved_url(),
            "https://example.com/v1/chat/completions"
        );
    }

    #[test]
    fn test_chat_message_from_llm_message() {
        let msg = LlmMessage {
            role: "user".to_string(),
            content: "Hello".to_string(),
        };
        let chat_msg = ChatMessage::from(&msg);
        assert_eq!(chat_msg.role, "user");
        assert_eq!(chat_msg.content, "Hello");
    }

    #[test]
    fn test_llm_request_construction() {
        let req = LlmRequest {
            messages: vec![
                LlmMessage { role: "system".into(), content: "You are a helpful assistant.".into() },
                LlmMessage { role: "user".into(), content: "What is RAG?".into() },
            ],
            temperature: 0.1,
            max_tokens: 4096,
            stream: false,
        };
        assert_eq!(req.messages.len(), 2);
        assert_eq!(req.temperature, 0.1);
    }
}
