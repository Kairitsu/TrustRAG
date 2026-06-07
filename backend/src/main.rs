use axum::{extract::DefaultBodyLimit, Router, routing::get};
use tower_http::{cors::CorsLayer, trace::TraceLayer};
use tracing_subscriber::{layer::SubscriberExt, util::SubscriberInitExt};

mod config;
mod error;
mod auth;
mod api;
mod db;
mod metrics;
mod services;
mod traits;

use api::AppState;
use auth::middleware::JwtSecret;
use services::storage::StorageService;

fn init_logging() {
    let env_filter = tracing_subscriber::EnvFilter::try_from_default_env()
        .unwrap_or_else(|_| "trustrag_backend=debug,tower_http=info,sqlx=warn".into());

    let log_format = std::env::var("LOG_FORMAT").unwrap_or_default();

    if log_format == "json" {
        tracing_subscriber::registry()
            .with(env_filter)
            .with(tracing_subscriber::fmt::layer().json().with_target(true).with_thread_ids(true))
            .init();
    } else {
        tracing_subscriber::registry()
            .with(env_filter)
            .with(tracing_subscriber::fmt::layer().with_target(true))
            .init();
    }
}

#[cfg(sqlite_mode)]
async fn ensure_data_dir(config: &config::AppConfig) -> anyhow::Result<()> {
    std::fs::create_dir_all(&config.data_dir)?;
    tracing::info!(data_dir = %config.data_dir, "Data directory ready");
    Ok(())
}

#[cfg(sqlite_mode)]
async fn run_sqlite_migrations(pool: &sqlx::SqlitePool) -> anyhow::Result<()> {
    db::run_migrations(pool).await?;
    Ok(())
}

async fn recover_stale_documents(state: &AppState) {
    let rows = sqlx::query_as::<_, (String, String)>(
        "SELECT id, workspace_id FROM documents WHERE processing_status IN ('processing', 'chunking', 'embedding')"
    )
    .fetch_all(&state.pool)
    .await;

    match rows {
        Ok(stale) => {
            if stale.is_empty() {
                tracing::info!("No stale documents to recover");
                return;
            }
            tracing::info!(count = stale.len(), "Recovering stale documents");
            for (doc_id_str, ws_id_str) in stale {
                let doc_id = match uuid::Uuid::parse_str(&doc_id_str) {
                    Ok(id) => id,
                    Err(_) => continue,
                };
                let ws_id = match uuid::Uuid::parse_str(&ws_id_str) {
                    Ok(id) => id,
                    Err(_) => continue,
                };
                let pool = state.pool.clone();
                let storage = state.storage.clone();
                let doc_processor_url = state.doc_processor_url.clone();
                let embedding_provider = state.embedding_provider.read().await.clone();
                let semaphore = state.doc_processing_semaphore.clone();
                tokio::spawn(async move {
                    services::document::process_document(
                        pool, storage, doc_processor_url, embedding_provider,
                        doc_id, ws_id, Some(semaphore),
                    ).await;
                });
            }
        }
        Err(e) => {
            tracing::warn!(error = %e, "Failed to query stale documents for recovery");
        }
    }
}

#[tokio::main]
async fn main() -> anyhow::Result<()> {
    init_logging();

    tracing::info!(
        version = env!("CARGO_PKG_VERSION"),
        "TrustRAG backend starting"
    );

    let config = config::AppConfig::load()?;
    tracing::info!(listen_addr = %config.listen_addr, "Configuration loaded");

    #[cfg(sqlite_mode)]
    ensure_data_dir(&config).await?;

    let pool = db::create_pool(&config.database_url).await?;
    tracing::info!("Database connection pool established");

    #[cfg(feature = "postgres")]
    {
        sqlx::migrate!("./migrations").run(&pool).await?;
        tracing::info!("Database migrations completed");
    }

    #[cfg(sqlite_mode)]
    run_sqlite_migrations(&pool).await?;

    let storage = StorageService::new(&config)?;
    tracing::info!(bucket = %storage.bucket(), "Storage service initialized");

    let upload_limit = config.max_upload_size_mb * 1024 * 1024;

    let embedding_cache = moka::future::Cache::builder()
        .max_capacity(1000)
        .time_to_live(std::time::Duration::from_secs(600))
        .build();

    let domain_profiles = {
        let profiles_dir = services::domain_profile::default_profiles_dir();
        match services::domain_profile::DomainProfileRegistry::load_from_dir(&profiles_dir) {
            Ok(registry) => std::sync::Arc::new(registry),
            Err(e) => {
                tracing::warn!(error = %e, "Failed to load domain profiles, using empty registry");
                std::sync::Arc::new(services::domain_profile::DomainProfileRegistry::new())
            }
        }
    };

    let doc_concurrency: usize = std::env::var("TRUSTRAG_DOC_CONCURRENCY")
        .ok()
        .and_then(|v| v.parse().ok())
        .unwrap_or(2);
    tracing::info!(doc_concurrency, "Document processing concurrency limit");

    let state = AppState {
        pool: pool.clone(),
        jwt_secret: config.jwt_secret.clone(),
        storage,
        max_upload_size: config.max_upload_size_mb,
        embedding_provider: std::sync::Arc::new(tokio::sync::RwLock::new(None)),
        doc_processor_url: config.doc_processor_url.clone(),
        embedding_cache,
        domain_profiles,
        doc_processing_semaphore: std::sync::Arc::new(tokio::sync::Semaphore::new(doc_concurrency)),
        #[cfg(sqlite_mode)]
        ocr_tasks: api::system::new_ocr_task_store(),
        #[cfg(sqlite_mode)]
        ocr_install_children: api::system::new_child_store(),
    };

    api::embedding_configs::init_embedding_provider(&state).await;

    recover_stale_documents(&state).await;

    let trace_layer = TraceLayer::new_for_http()
        .make_span_with(|request: &axum::http::Request<_>| {
            let request_id = uuid::Uuid::new_v4().to_string();
            tracing::info_span!(
                "http_request",
                method = %request.method(),
                uri = %request.uri(),
                request_id = %request_id,
            )
        })
        .on_response(
            |response: &axum::http::Response<_>, latency: std::time::Duration, _span: &tracing::Span| {
                tracing::info!(
                    http.status = response.status().as_u16(),
                    latency_ms = latency.as_millis() as u64,
                    "Response sent"
                );
            },
        )
        .on_failure(
            |error: tower_http::classify::ServerErrorsFailureClass, latency: std::time::Duration, _span: &tracing::Span| {
                tracing::error!(
                    error = %error,
                    latency_ms = latency.as_millis() as u64,
                    "Request failed"
                );
            },
        );

    let shared_metrics = metrics::create_metrics();
    let metrics_for_layer = shared_metrics.clone();

    let metrics_middleware = tower::ServiceBuilder::new().layer(
        axum::middleware::from_fn(move |req: axum::extract::Request, next: axum::middleware::Next| {
            let m = metrics_for_layer.clone();
            async move {
                let start = std::time::Instant::now();
                let response = next.run(req).await;
                let latency = start.elapsed().as_millis() as u64;
                let is_error = response.status().is_server_error();
                m.record_request(latency, is_error);
                response
            }
        }),
    );

    let app = Router::new()
        .route("/health", get(|| async { "ok" }))
        .route("/metrics", get({
            let m = shared_metrics.clone();
            move || {
                let snap = m.snapshot();
                async move { axum::Json(snap) }
            }
        }))
        .merge(api::users::router())
        .merge(api::workspaces::router())
        .merge(api::documents::router())
        .merge(api::search::router())
        .merge(api::models::router())
        .merge(api::embedding_configs::router())
        .merge(api::rerank_configs::router())
        .merge(api::chat::router())
        .merge(api::citations::router())
        .merge(api::reviews::router())
        .merge(api::knowledge_graph::router())
        .merge(api::workspace_members::router())
        .merge(api::audit::router())
        .merge(api::evidence::router())
        .merge(api::answer_status::router())
        .merge(api::domain_profiles::router())
        .merge(api::retrieval_traces::router());

    #[cfg(sqlite_mode)]
    let app = app.merge(api::system::router());

    let app = app
        .with_state(state)
        .layer(axum::Extension(JwtSecret(config.jwt_secret.clone())))
        .layer(DefaultBodyLimit::max(upload_limit as usize))
        .layer(CorsLayer::permissive())
        .layer(metrics_middleware)
        .layer(trace_layer);

    let listener = tokio::net::TcpListener::bind(&config.listen_addr).await?;
    tracing::info!(
        listen_addr = %config.listen_addr,
        "TrustRAG backend ready and listening"
    );
    axum::serve(listener, app).await?;

    Ok(())
}
