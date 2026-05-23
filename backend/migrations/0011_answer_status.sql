-- Answer versioning: add review status to messages for human-in-the-loop workflow.
-- Status values: draft, needs_review, verified, rejected, published

ALTER TABLE messages
    ADD COLUMN IF NOT EXISTS answer_status VARCHAR(20) DEFAULT 'draft'
        CHECK (answer_status IN ('draft', 'needs_review', 'verified', 'rejected', 'published'));

CREATE INDEX IF NOT EXISTS idx_messages_answer_status
    ON messages (answer_status);
