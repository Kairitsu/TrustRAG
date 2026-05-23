CREATE TABLE IF NOT EXISTS answer_versions (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    message_id UUID NOT NULL REFERENCES messages(id) ON DELETE CASCADE,
    version_number INT NOT NULL DEFAULT 1,
    content TEXT NOT NULL,
    answer_status VARCHAR(20) NOT NULL DEFAULT 'draft'
        CHECK (answer_status IN ('draft', 'needs_review', 'verified', 'rejected', 'published')),
    retrieval_trace_id UUID REFERENCES retrieval_traces(id) ON DELETE SET NULL,
    reviewer_id UUID REFERENCES users(id) ON DELETE SET NULL,
    review_comment TEXT,
    created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    UNIQUE (message_id, version_number)
);

CREATE INDEX IF NOT EXISTS idx_answer_versions_message ON answer_versions (message_id, version_number DESC);
CREATE INDEX IF NOT EXISTS idx_answer_versions_status ON answer_versions (answer_status);
