-- Add endpoint_mode to model config tables for unified URL resolution
ALTER TABLE model_configs ADD COLUMN IF NOT EXISTS endpoint_mode VARCHAR(20) NOT NULL DEFAULT 'base_url';
ALTER TABLE embedding_configs ADD COLUMN IF NOT EXISTS endpoint_mode VARCHAR(20) NOT NULL DEFAULT 'base_url';
ALTER TABLE rerank_configs ADD COLUMN IF NOT EXISTS endpoint_mode VARCHAR(20) NOT NULL DEFAULT 'base_url';

-- Migrate legacy configs that already stored full endpoint paths
UPDATE model_configs
SET endpoint_mode = 'full_endpoint'
WHERE endpoint_mode = 'base_url'
  AND (api_base_url LIKE '%/chat/completions' OR api_base_url LIKE '%/chat/completions/');

UPDATE embedding_configs
SET endpoint_mode = 'full_endpoint'
WHERE endpoint_mode = 'base_url'
  AND (api_base_url LIKE '%/embeddings' OR api_base_url LIKE '%/embeddings/');

UPDATE rerank_configs
SET endpoint_mode = 'full_endpoint'
WHERE endpoint_mode = 'base_url'
  AND (api_base_url LIKE '%/rerank' OR api_base_url LIKE '%/reranks'
       OR api_base_url LIKE '%/rerank/' OR api_base_url LIKE '%/reranks/');