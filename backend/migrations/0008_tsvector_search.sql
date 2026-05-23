-- Add tsvector column for proper full-text search (replaces pg_trgm similarity)
-- Supports multi-language: 'simple' config works for CJK + Latin

ALTER TABLE document_chunks
    ADD COLUMN IF NOT EXISTS tsv tsvector;

-- Populate tsvector for existing rows
UPDATE document_chunks
SET tsv = to_tsvector('simple', coalesce(heading_path, '') || ' ' || content)
WHERE tsv IS NULL;

-- GIN index for fast tsvector matching
CREATE INDEX IF NOT EXISTS idx_chunks_tsv ON document_chunks USING gin (tsv);

-- Trigger to auto-update tsvector on INSERT/UPDATE
CREATE OR REPLACE FUNCTION chunks_tsv_trigger() RETURNS trigger AS $$
BEGIN
    NEW.tsv := to_tsvector('simple', coalesce(NEW.heading_path, '') || ' ' || NEW.content);
    RETURN NEW;
END;
$$ LANGUAGE plpgsql;

DROP TRIGGER IF EXISTS trg_chunks_tsv ON document_chunks;
CREATE TRIGGER trg_chunks_tsv
    BEFORE INSERT OR UPDATE OF content, heading_path ON document_chunks
    FOR EACH ROW
    EXECUTE FUNCTION chunks_tsv_trigger();
