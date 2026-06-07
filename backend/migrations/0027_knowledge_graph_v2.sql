-- Knowledge graph v2: entity localization, enhanced generation job tracking

-- Entity localization & stable keys
ALTER TABLE entities ADD COLUMN IF NOT EXISTS entity_key TEXT;
ALTER TABLE entities ADD COLUMN IF NOT EXISTS original_name TEXT;
ALTER TABLE entities ADD COLUMN IF NOT EXISTS display_name TEXT;
ALTER TABLE entities ADD COLUMN IF NOT EXISTS original_language TEXT;
ALTER TABLE entities ADD COLUMN IF NOT EXISTS aliases JSONB DEFAULT '[]';
ALTER TABLE entities ADD COLUMN IF NOT EXISTS graph_layer TEXT NOT NULL DEFAULT 'knowledge';

ALTER TABLE entity_relations ADD COLUMN IF NOT EXISTS graph_layer TEXT NOT NULL DEFAULT 'knowledge';

-- Backfill display/original names from existing data
UPDATE entities SET original_name = name WHERE original_name IS NULL;
UPDATE entities SET display_name = name WHERE display_name IS NULL;
UPDATE entities SET entity_key = LOWER(REGEXP_REPLACE(COALESCE(original_name, name), '[^a-zA-Z0-9]+', '_', 'g'))
  WHERE entity_key IS NULL OR entity_key = '';

CREATE INDEX IF NOT EXISTS idx_entities_entity_key ON entities(workspace_id, entity_key);
CREATE INDEX IF NOT EXISTS idx_entities_display_name ON entities(workspace_id, display_name);
CREATE INDEX IF NOT EXISTS idx_entities_layer ON entities(workspace_id, graph_layer);
CREATE INDEX IF NOT EXISTS idx_entity_relations_layer ON entity_relations(workspace_id, graph_layer);

-- Enhanced generation job tracking (graph_generation_logs serves as job table)
ALTER TABLE graph_generation_logs ADD COLUMN IF NOT EXISTS target_language TEXT DEFAULT 'zh';
ALTER TABLE graph_generation_logs ADD COLUMN IF NOT EXISTS job_type TEXT NOT NULL DEFAULT 'knowledge_batch';
ALTER TABLE graph_generation_logs ADD COLUMN IF NOT EXISTS layer_type TEXT;
ALTER TABLE graph_generation_logs ADD COLUMN IF NOT EXISTS current_document_id UUID REFERENCES documents(id) ON DELETE SET NULL;
ALTER TABLE graph_generation_logs ADD COLUMN IF NOT EXISTS current_document_title TEXT;
ALTER TABLE graph_generation_logs ADD COLUMN IF NOT EXISTS succeeded_documents INTEGER NOT NULL DEFAULT 0;
ALTER TABLE graph_generation_logs ADD COLUMN IF NOT EXISTS failed_documents INTEGER NOT NULL DEFAULT 0;
ALTER TABLE graph_generation_logs ADD COLUMN IF NOT EXISTS relations_llm_returned INTEGER NOT NULL DEFAULT 0;
ALTER TABLE graph_generation_logs ADD COLUMN IF NOT EXISTS relations_skipped_match INTEGER NOT NULL DEFAULT 0;
ALTER TABLE graph_generation_logs ADD COLUMN IF NOT EXISTS relations_skipped_duplicate INTEGER NOT NULL DEFAULT 0;
ALTER TABLE graph_generation_logs ADD COLUMN IF NOT EXISTS relations_db_failed INTEGER NOT NULL DEFAULT 0;
ALTER TABLE graph_generation_logs ADD COLUMN IF NOT EXISTS chunk_parse_failures INTEGER NOT NULL DEFAULT 0;
ALTER TABLE graph_generation_logs ADD COLUMN IF NOT EXISTS json_parse_failures INTEGER NOT NULL DEFAULT 0;
ALTER TABLE graph_generation_logs ADD COLUMN IF NOT EXISTS warnings JSONB NOT NULL DEFAULT '[]';
ALTER TABLE graph_generation_logs ADD COLUMN IF NOT EXISTS cancel_requested BOOLEAN NOT NULL DEFAULT FALSE;

CREATE INDEX IF NOT EXISTS idx_graph_gen_logs_active
  ON graph_generation_logs(workspace_id, status, started_at);