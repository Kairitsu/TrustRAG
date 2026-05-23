CREATE TABLE IF NOT EXISTS retrieval_traces (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    workspace_id UUID NOT NULL REFERENCES workspaces(id) ON DELETE CASCADE,
    message_id UUID REFERENCES messages(id) ON DELETE SET NULL,
    original_query TEXT NOT NULL,
    rewritten_query TEXT NOT NULL DEFAULT '',
    expanded_queries JSONB NOT NULL DEFAULT '[]',
    search_results_count INT NOT NULL DEFAULT 0,
    reranked_results_count INT NOT NULL DEFAULT 0,
    final_sources_count INT NOT NULL DEFAULT 0,
    search_results JSONB NOT NULL DEFAULT '[]',
    reranked_results JSONB NOT NULL DEFAULT '[]',
    timings JSONB NOT NULL DEFAULT '{}',
    domain_profile VARCHAR(100),
    created_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

CREATE INDEX IF NOT EXISTS idx_retrieval_traces_workspace ON retrieval_traces (workspace_id);
CREATE INDEX IF NOT EXISTS idx_retrieval_traces_message ON retrieval_traces (message_id);
CREATE INDEX IF NOT EXISTS idx_retrieval_traces_created ON retrieval_traces (created_at DESC);
