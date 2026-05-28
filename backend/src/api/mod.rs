use std::sync::Arc;

use moka::future::Cache;
use tokio::sync::RwLock;

use crate::db::DbPool;
use crate::services::domain_profile::DomainProfileRegistry;
use crate::services::storage::StorageService;
use crate::traits::embedding_provider::EmbeddingProvider;

pub mod answer_status;
pub mod audit;
pub mod domain_profiles;
pub mod users;
pub mod workspaces;
pub mod documents;
pub mod evidence;
pub mod search;
pub mod models;
pub mod chat;
pub mod citations;
pub mod retrieval_traces;
pub mod reviews;
pub mod embedding_configs;
pub mod rerank_configs;
pub mod knowledge_graph;
pub mod workspace_members;
#[cfg(sqlite_mode)]
pub mod system;

#[derive(Clone)]
pub struct AppState {
    pub pool: DbPool,
    pub jwt_secret: String,
    pub storage: StorageService,
    pub max_upload_size: u64,
    pub embedding_provider: Arc<RwLock<Option<Arc<dyn EmbeddingProvider>>>>,
    pub doc_processor_url: String,
    pub embedding_cache: Cache<String, Vec<f32>>,
    pub domain_profiles: Arc<DomainProfileRegistry>,
}
