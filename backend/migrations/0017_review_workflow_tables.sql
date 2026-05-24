-- review_tasks: trackable review assignments for messages/answers
CREATE TABLE IF NOT EXISTS review_tasks (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    workspace_id UUID NOT NULL,
    message_id UUID,
    answer_version_id UUID,
    title VARCHAR(500) NOT NULL,
    description TEXT,
    task_type VARCHAR(50) NOT NULL DEFAULT 'general',
    priority INTEGER NOT NULL DEFAULT 3,
    status VARCHAR(30) NOT NULL DEFAULT 'open',
    assigned_to UUID,
    created_by UUID,
    due_date TIMESTAMPTZ,
    completed_at TIMESTAMPTZ,
    tags TEXT[] DEFAULT '{}',
    metadata JSONB DEFAULT '{}',
    created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    updated_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

CREATE INDEX idx_review_tasks_workspace ON review_tasks(workspace_id);
CREATE INDEX idx_review_tasks_status ON review_tasks(status);
CREATE INDEX idx_review_tasks_assigned ON review_tasks(assigned_to);
CREATE INDEX idx_review_tasks_message ON review_tasks(message_id);
CREATE INDEX idx_review_tasks_priority ON review_tasks(priority);

-- review_comments: threaded comments on review tasks
CREATE TABLE IF NOT EXISTS review_comments (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    review_task_id UUID NOT NULL REFERENCES review_tasks(id) ON DELETE CASCADE,
    parent_comment_id UUID REFERENCES review_comments(id) ON DELETE SET NULL,
    author_id UUID,
    content TEXT NOT NULL,
    comment_type VARCHAR(30) NOT NULL DEFAULT 'comment',
    resolved BOOLEAN NOT NULL DEFAULT FALSE,
    resolved_at TIMESTAMPTZ,
    resolved_by UUID,
    metadata JSONB DEFAULT '{}',
    created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    updated_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

CREATE INDEX idx_review_comments_task ON review_comments(review_task_id);
CREATE INDEX idx_review_comments_parent ON review_comments(parent_comment_id);
CREATE INDEX idx_review_comments_author ON review_comments(author_id);

-- source_reviews: per-source quality reviews within a retrieval context
CREATE TABLE IF NOT EXISTS source_reviews (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    workspace_id UUID NOT NULL,
    document_id UUID NOT NULL,
    chunk_id UUID,
    review_task_id UUID REFERENCES review_tasks(id) ON DELETE SET NULL,
    reviewer_id UUID,
    verdict VARCHAR(30) NOT NULL DEFAULT 'pending',
    relevance_score DOUBLE PRECISION,
    accuracy_score DOUBLE PRECISION,
    freshness_score DOUBLE PRECISION,
    authority_score DOUBLE PRECISION,
    overall_score DOUBLE PRECISION,
    notes TEXT,
    is_trusted BOOLEAN DEFAULT NULL,
    flagged_issues TEXT[] DEFAULT '{}',
    metadata JSONB DEFAULT '{}',
    created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    updated_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

CREATE INDEX idx_source_reviews_workspace ON source_reviews(workspace_id);
CREATE INDEX idx_source_reviews_document ON source_reviews(document_id);
CREATE INDEX idx_source_reviews_task ON source_reviews(review_task_id);
CREATE INDEX idx_source_reviews_verdict ON source_reviews(verdict);
