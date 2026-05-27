-- Add batch_size column to embedding_configs table.
-- Defaults to 10 to be compatible with most OpenAI-compatible APIs.
ALTER TABLE embedding_configs ADD COLUMN IF NOT EXISTS batch_size INTEGER NOT NULL DEFAULT 10;

-- Add 'embedding_failed' to documents.processing_status CHECK constraint.
-- This allows distinguishing "parse/chunk succeeded but embedding failed" from general failure.
ALTER TABLE documents DROP CONSTRAINT IF EXISTS documents_processing_status_check;
ALTER TABLE documents ADD CONSTRAINT documents_processing_status_check
    CHECK (processing_status IN (
        'pending', 'processing', 'chunking',
        'embedding', 'ready', 'failed', 'embedding_failed'
    ));
