ALTER TABLE documents ADD COLUMN IF NOT EXISTS chunks_total INTEGER;
ALTER TABLE documents ADD COLUMN IF NOT EXISTS chunks_done INTEGER;
ALTER TABLE documents ADD COLUMN IF NOT EXISTS embedding_batches_total INTEGER;
ALTER TABLE documents ADD COLUMN IF NOT EXISTS embedding_batches_done INTEGER;
