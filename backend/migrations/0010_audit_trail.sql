-- Audit trail for tracking all significant actions in the system
CREATE TABLE IF NOT EXISTS audit_trail (
    id              UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    workspace_id    UUID REFERENCES workspaces(id) ON DELETE CASCADE,
    user_id         UUID REFERENCES users(id) ON DELETE SET NULL,
    action          VARCHAR(100) NOT NULL,
    entity_type     VARCHAR(50) NOT NULL,
    entity_id       UUID,
    details         JSONB DEFAULT '{}'::jsonb,
    ip_address      VARCHAR(45),
    created_at      TIMESTAMPTZ NOT NULL DEFAULT now()
);

CREATE INDEX IF NOT EXISTS idx_audit_workspace_time
    ON audit_trail (workspace_id, created_at DESC);
CREATE INDEX IF NOT EXISTS idx_audit_user_time
    ON audit_trail (user_id, created_at DESC);
CREATE INDEX IF NOT EXISTS idx_audit_action
    ON audit_trail (action, created_at DESC);
CREATE INDEX IF NOT EXISTS idx_audit_entity
    ON audit_trail (entity_type, entity_id);

-- Add evidence_report column to messages for storing verification results
ALTER TABLE messages
    ADD COLUMN IF NOT EXISTS evidence_report JSONB;
