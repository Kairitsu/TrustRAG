-- Auto-extracted document metadata (keywords, topics, entity types, etc.)
ALTER TABLE documents
    ADD COLUMN IF NOT EXISTS metadata JSONB DEFAULT '{}'::jsonb;

-- Workspace-level domain profile (aggregated from document metadata)
ALTER TABLE workspaces
    ADD COLUMN IF NOT EXISTS domain_profile JSONB DEFAULT '{}'::jsonb;

-- GIN index for metadata queries
CREATE INDEX IF NOT EXISTS idx_documents_metadata ON documents USING gin (metadata jsonb_path_ops);
