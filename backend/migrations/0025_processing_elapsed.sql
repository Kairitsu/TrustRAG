ALTER TABLE documents ADD COLUMN IF NOT EXISTS processing_started_at TIMESTAMPTZ;
ALTER TABLE documents ADD COLUMN IF NOT EXISTS processing_finished_at TIMESTAMPTZ;
ALTER TABLE documents ADD COLUMN IF NOT EXISTS processing_elapsed_ms BIGINT;
