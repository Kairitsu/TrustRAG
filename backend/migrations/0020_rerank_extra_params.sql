-- Add extra rerank parameters: initial recall count and fallback toggle
ALTER TABLE rerank_configs ADD COLUMN IF NOT EXISTS initial_recall_k INTEGER NOT NULL DEFAULT 30;
ALTER TABLE rerank_configs ADD COLUMN IF NOT EXISTS fallback_enabled BOOLEAN NOT NULL DEFAULT TRUE;
