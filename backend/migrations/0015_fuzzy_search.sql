-- Enable pg_trgm if not already enabled (idempotent)
CREATE EXTENSION IF NOT EXISTS pg_trgm;

-- Set the word_similarity threshold for the <% operator (default 0.6 may be too strict)
-- This is a session-level setting; applications should also set it at connection time if needed.
-- The GIN index on content using gin_trgm_ops (from 0001) already supports the <% operator.
