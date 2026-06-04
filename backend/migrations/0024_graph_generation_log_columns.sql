CREATE TABLE IF NOT EXISTS graph_generation_logs (
    id TEXT PRIMARY KEY,
    workspace_id UUID NOT NULL REFERENCES workspaces(id),
    user_id UUID NOT NULL,
    status TEXT NOT NULL DEFAULT 'running',
    total_documents INTEGER NOT NULL DEFAULT 0,
    processed_documents INTEGER NOT NULL DEFAULT 0,
    entities_created INTEGER NOT NULL DEFAULT 0,
    relations_created INTEGER NOT NULL DEFAULT 0,
    errors TEXT NOT NULL DEFAULT '[]',
    started_at TIMESTAMPTZ NOT NULL DEFAULT now(),
    completed_at TIMESTAMPTZ,
    trigger_type TEXT NOT NULL DEFAULT 'manual_batch',
    document_id UUID REFERENCES documents(id) ON DELETE SET NULL,
    llm_provider TEXT,
    llm_model TEXT,
    elapsed_ms BIGINT
);
