ALTER TABLE graph_generation_logs ADD COLUMN IF NOT EXISTS trigger_type TEXT NOT NULL DEFAULT 'manual_batch';
ALTER TABLE graph_generation_logs ADD COLUMN IF NOT EXISTS document_id TEXT REFERENCES documents(id) ON DELETE SET NULL;
ALTER TABLE graph_generation_logs ADD COLUMN IF NOT EXISTS llm_provider TEXT;
ALTER TABLE graph_generation_logs ADD COLUMN IF NOT EXISTS llm_model TEXT;
ALTER TABLE graph_generation_logs ADD COLUMN IF NOT EXISTS elapsed_ms BIGINT;
