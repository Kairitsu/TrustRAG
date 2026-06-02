-- Rerank model configuration table
CREATE TABLE IF NOT EXISTS rerank_configs (
    id              UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    workspace_id    UUID REFERENCES workspaces(id) ON DELETE CASCADE,
    user_id         UUID NOT NULL REFERENCES users(id) ON DELETE CASCADE,
    name            TEXT NOT NULL,
    provider        TEXT NOT NULL CHECK (provider IN ('jina', 'cohere', 'openai', 'custom')),
    api_base_url    TEXT NOT NULL,
    api_key_enc     TEXT,
    model_name      TEXT NOT NULL,
    top_n           INTEGER NOT NULL DEFAULT 5,
    initial_recall_k INTEGER NOT NULL DEFAULT 30,
    fallback_enabled BOOLEAN NOT NULL DEFAULT TRUE,
    timeout_secs    INTEGER NOT NULL DEFAULT 30,
    is_default      BOOLEAN DEFAULT FALSE,
    created_at      TIMESTAMPTZ DEFAULT now(),
    updated_at      TIMESTAMPTZ DEFAULT now()
);

CREATE INDEX IF NOT EXISTS idx_rerank_configs_user ON rerank_configs (user_id);
CREATE INDEX IF NOT EXISTS idx_rerank_configs_workspace ON rerank_configs (workspace_id);
