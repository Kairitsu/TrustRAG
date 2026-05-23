-- Claim-level reviews: per-claim verification by reviewers
CREATE TABLE IF NOT EXISTS claim_reviews (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    claim_id UUID NOT NULL,
    message_id UUID NOT NULL REFERENCES messages(id) ON DELETE CASCADE,
    reviewer_id UUID NOT NULL REFERENCES users(id) ON DELETE CASCADE,
    verdict VARCHAR(20) NOT NULL
        CHECK (verdict IN ('supported', 'unsupported', 'partially_supported', 'unverifiable')),
    confidence DOUBLE PRECISION CHECK (confidence >= 0.0 AND confidence <= 1.0),
    comment TEXT,
    evidence_references JSONB NOT NULL DEFAULT '[]',
    created_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

CREATE INDEX IF NOT EXISTS idx_claim_reviews_claim ON claim_reviews (claim_id);
CREATE INDEX IF NOT EXISTS idx_claim_reviews_message ON claim_reviews (message_id);
CREATE INDEX IF NOT EXISTS idx_claim_reviews_reviewer ON claim_reviews (reviewer_id);

-- Answer-level reviews: holistic assessment of entire AI answers
CREATE TABLE IF NOT EXISTS answer_reviews (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    message_id UUID NOT NULL REFERENCES messages(id) ON DELETE CASCADE,
    answer_version_id UUID REFERENCES answer_versions(id) ON DELETE SET NULL,
    reviewer_id UUID NOT NULL REFERENCES users(id) ON DELETE CASCADE,
    overall_verdict VARCHAR(20) NOT NULL
        CHECK (overall_verdict IN ('approved', 'rejected', 'needs_revision', 'escalated')),
    accuracy_score DOUBLE PRECISION CHECK (accuracy_score >= 0.0 AND accuracy_score <= 1.0),
    completeness_score DOUBLE PRECISION CHECK (completeness_score >= 0.0 AND completeness_score <= 1.0),
    clarity_score DOUBLE PRECISION CHECK (clarity_score >= 0.0 AND clarity_score <= 1.0),
    comment TEXT,
    revision_instructions TEXT,
    created_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

CREATE INDEX IF NOT EXISTS idx_answer_reviews_message ON answer_reviews (message_id);
CREATE INDEX IF NOT EXISTS idx_answer_reviews_version ON answer_reviews (answer_version_id);
CREATE INDEX IF NOT EXISTS idx_answer_reviews_reviewer ON answer_reviews (reviewer_id);
CREATE INDEX IF NOT EXISTS idx_answer_reviews_verdict ON answer_reviews (overall_verdict);
