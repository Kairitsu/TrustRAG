-- TrustRAG SQLite Schema (desktop mode)
-- Equivalent to PostgreSQL migrations 0001-0006

CREATE TABLE IF NOT EXISTS users (
    id              TEXT PRIMARY KEY DEFAULT (lower(hex(randomblob(4)) || '-' || hex(randomblob(2)) || '-4' || substr(hex(randomblob(2)),2) || '-' || substr('89ab',abs(random()) % 4 + 1, 1) || substr(hex(randomblob(2)),2) || '-' || hex(randomblob(6)))),
    email           TEXT NOT NULL UNIQUE,
    password_hash   TEXT NOT NULL,
    display_name    TEXT NOT NULL,
    role            TEXT NOT NULL DEFAULT 'user' CHECK (role IN ('admin', 'reviewer', 'user')),
    status          TEXT NOT NULL DEFAULT 'active' CHECK (status IN ('active', 'suspended', 'deleted')),
    created_at      TEXT NOT NULL DEFAULT (strftime('%Y-%m-%dT%H:%M:%fZ', 'now')),
    updated_at      TEXT NOT NULL DEFAULT (strftime('%Y-%m-%dT%H:%M:%fZ', 'now')),
    last_login_at   TEXT
);

CREATE INDEX IF NOT EXISTS idx_users_email ON users (email);
CREATE INDEX IF NOT EXISTS idx_users_status ON users (status);

CREATE TABLE IF NOT EXISTS workspaces (
    id              TEXT PRIMARY KEY DEFAULT (lower(hex(randomblob(4)) || '-' || hex(randomblob(2)) || '-4' || substr(hex(randomblob(2)),2) || '-' || substr('89ab',abs(random()) % 4 + 1, 1) || substr(hex(randomblob(2)),2) || '-' || hex(randomblob(6)))),
    name            TEXT NOT NULL,
    description     TEXT,
    owner_id        TEXT NOT NULL REFERENCES users(id) ON DELETE CASCADE,
    visibility      TEXT NOT NULL DEFAULT 'private' CHECK (visibility IN ('private', 'shared', 'public')),
    type            TEXT NOT NULL DEFAULT 'personal',
    invite_code     TEXT UNIQUE,
    domain_profile  TEXT DEFAULT '{}',
    created_at      TEXT NOT NULL DEFAULT (strftime('%Y-%m-%dT%H:%M:%fZ', 'now')),
    updated_at      TEXT NOT NULL DEFAULT (strftime('%Y-%m-%dT%H:%M:%fZ', 'now'))
);

CREATE INDEX IF NOT EXISTS idx_workspaces_owner ON workspaces (owner_id);
CREATE INDEX IF NOT EXISTS idx_workspaces_type ON workspaces(type);

CREATE TABLE IF NOT EXISTS workspace_members (
    id              TEXT PRIMARY KEY DEFAULT (lower(hex(randomblob(4)) || '-' || hex(randomblob(2)) || '-4' || substr(hex(randomblob(2)),2) || '-' || substr('89ab',abs(random()) % 4 + 1, 1) || substr(hex(randomblob(2)),2) || '-' || hex(randomblob(6)))),
    workspace_id    TEXT NOT NULL REFERENCES workspaces(id) ON DELETE CASCADE,
    user_id         TEXT NOT NULL REFERENCES users(id) ON DELETE CASCADE,
    role            TEXT NOT NULL DEFAULT 'viewer' CHECK (role IN ('owner', 'admin', 'editor', 'viewer')),
    invited_by      TEXT REFERENCES users(id),
    created_at      TEXT NOT NULL DEFAULT (strftime('%Y-%m-%dT%H:%M:%fZ', 'now')),
    UNIQUE (workspace_id, user_id)
);

CREATE INDEX IF NOT EXISTS idx_workspace_members_workspace ON workspace_members(workspace_id);
CREATE INDEX IF NOT EXISTS idx_workspace_members_user ON workspace_members(user_id);

CREATE TABLE IF NOT EXISTS documents (
    id                  TEXT PRIMARY KEY DEFAULT (lower(hex(randomblob(4)) || '-' || hex(randomblob(2)) || '-4' || substr(hex(randomblob(2)),2) || '-' || substr('89ab',abs(random()) % 4 + 1, 1) || substr(hex(randomblob(2)),2) || '-' || hex(randomblob(6)))),
    workspace_id        TEXT NOT NULL REFERENCES workspaces(id) ON DELETE CASCADE,
    title               TEXT NOT NULL,
    original_filename   TEXT NOT NULL,
    file_type           TEXT NOT NULL CHECK (file_type IN ('pdf', 'docx', 'md', 'txt', 'html')),
    file_size_bytes     INTEGER,
    page_count          INTEGER,
    language            TEXT,
    tags                TEXT DEFAULT '[]',
    original_file_path  TEXT NOT NULL,
    markdown_file_path  TEXT,
    processing_status   TEXT NOT NULL DEFAULT 'pending' CHECK (processing_status IN ('pending', 'processing', 'chunking', 'embedding', 'ready', 'failed', 'embedding_failed')),
    processing_error    TEXT,
    uploaded_by         TEXT NOT NULL REFERENCES users(id),
    metadata            TEXT DEFAULT '{}',
    created_at          TEXT NOT NULL DEFAULT (strftime('%Y-%m-%dT%H:%M:%fZ', 'now')),
    updated_at          TEXT NOT NULL DEFAULT (strftime('%Y-%m-%dT%H:%M:%fZ', 'now'))
);

CREATE INDEX IF NOT EXISTS idx_documents_workspace ON documents (workspace_id);
CREATE INDEX IF NOT EXISTS idx_documents_status ON documents (processing_status);
CREATE INDEX IF NOT EXISTS idx_documents_uploaded_by ON documents (uploaded_by);
CREATE INDEX IF NOT EXISTS idx_documents_workspace_created ON documents (workspace_id, created_at);

CREATE TABLE IF NOT EXISTS document_chunks (
    id              TEXT PRIMARY KEY DEFAULT (lower(hex(randomblob(4)) || '-' || hex(randomblob(2)) || '-4' || substr(hex(randomblob(2)),2) || '-' || substr('89ab',abs(random()) % 4 + 1, 1) || substr(hex(randomblob(2)),2) || '-' || hex(randomblob(6)))),
    document_id     TEXT NOT NULL REFERENCES documents(id) ON DELETE CASCADE,
    chunk_index     INTEGER NOT NULL,
    heading_path    TEXT,
    section_level   INTEGER,
    content         TEXT NOT NULL,
    content_tokens  INTEGER,
    page_start      INTEGER,
    page_end        INTEGER,
    paragraph_index INTEGER,
    char_start      INTEGER,
    char_end        INTEGER,
    embedding       BLOB,
    content_hash    TEXT,
    created_at      TEXT NOT NULL DEFAULT (strftime('%Y-%m-%dT%H:%M:%fZ', 'now')),
    UNIQUE (document_id, chunk_index)
);

CREATE INDEX IF NOT EXISTS idx_chunks_document ON document_chunks (document_id);
CREATE INDEX IF NOT EXISTS idx_chunks_doc_embedding ON document_chunks (document_id) WHERE embedding IS NOT NULL;

-- FTS5 virtual table for full-text search
CREATE VIRTUAL TABLE IF NOT EXISTS chunks_fts USING fts5(
    content,
    chunk_id UNINDEXED,
    content='document_chunks',
    content_rowid='rowid'
);

-- Triggers to keep FTS5 in sync
CREATE TRIGGER IF NOT EXISTS chunks_fts_insert AFTER INSERT ON document_chunks BEGIN
    INSERT INTO chunks_fts(rowid, content, chunk_id) VALUES (new.rowid, new.content, new.id);
END;

CREATE TRIGGER IF NOT EXISTS chunks_fts_delete AFTER DELETE ON document_chunks BEGIN
    INSERT INTO chunks_fts(chunks_fts, rowid, content, chunk_id) VALUES ('delete', old.rowid, old.content, old.id);
END;

CREATE TRIGGER IF NOT EXISTS chunks_fts_update AFTER UPDATE OF content ON document_chunks BEGIN
    INSERT INTO chunks_fts(chunks_fts, rowid, content, chunk_id) VALUES ('delete', old.rowid, old.content, old.id);
    INSERT INTO chunks_fts(rowid, content, chunk_id) VALUES (new.rowid, new.content, new.id);
END;

CREATE TABLE IF NOT EXISTS model_configs (
    id              TEXT PRIMARY KEY DEFAULT (lower(hex(randomblob(4)) || '-' || hex(randomblob(2)) || '-4' || substr(hex(randomblob(2)),2) || '-' || substr('89ab',abs(random()) % 4 + 1, 1) || substr(hex(randomblob(2)),2) || '-' || hex(randomblob(6)))),
    workspace_id    TEXT REFERENCES workspaces(id) ON DELETE CASCADE,
    user_id         TEXT NOT NULL REFERENCES users(id) ON DELETE CASCADE,
    name            TEXT NOT NULL,
    provider        TEXT NOT NULL CHECK (provider IN ('openai', 'anthropic', 'ollama', 'custom')),
    api_base_url    TEXT NOT NULL,
    api_key_enc     TEXT,
    model_name      TEXT NOT NULL,
    temperature     REAL DEFAULT 0.1,
    max_tokens      INTEGER DEFAULT 4096,
    is_default      INTEGER DEFAULT 0,
    created_at      TEXT NOT NULL DEFAULT (strftime('%Y-%m-%dT%H:%M:%fZ', 'now')),
    updated_at      TEXT NOT NULL DEFAULT (strftime('%Y-%m-%dT%H:%M:%fZ', 'now'))
);

CREATE INDEX IF NOT EXISTS idx_model_configs_user ON model_configs (user_id);

CREATE TABLE IF NOT EXISTS embedding_configs (
    id              TEXT PRIMARY KEY DEFAULT (lower(hex(randomblob(4)) || '-' || hex(randomblob(2)) || '-4' || substr(hex(randomblob(2)),2) || '-' || substr('89ab',abs(random()) % 4 + 1, 1) || substr(hex(randomblob(2)),2) || '-' || hex(randomblob(6)))),
    workspace_id    TEXT REFERENCES workspaces(id) ON DELETE CASCADE,
    user_id         TEXT NOT NULL REFERENCES users(id) ON DELETE CASCADE,
    name            TEXT NOT NULL,
    provider        TEXT NOT NULL CHECK (provider IN ('openai', 'ollama', 'local', 'custom')),
    api_base_url    TEXT,
    api_key_enc     TEXT,
    model_name      TEXT NOT NULL,
    dimensions      INTEGER NOT NULL DEFAULT 1536,
    batch_size      INTEGER NOT NULL DEFAULT 10,
    is_default      INTEGER DEFAULT 0,
    created_at      TEXT NOT NULL DEFAULT (strftime('%Y-%m-%dT%H:%M:%fZ', 'now')),
    updated_at      TEXT NOT NULL DEFAULT (strftime('%Y-%m-%dT%H:%M:%fZ', 'now'))
);

CREATE TABLE IF NOT EXISTS conversations (
    id              TEXT PRIMARY KEY DEFAULT (lower(hex(randomblob(4)) || '-' || hex(randomblob(2)) || '-4' || substr(hex(randomblob(2)),2) || '-' || substr('89ab',abs(random()) % 4 + 1, 1) || substr(hex(randomblob(2)),2) || '-' || hex(randomblob(6)))),
    workspace_id    TEXT NOT NULL REFERENCES workspaces(id) ON DELETE CASCADE,
    user_id         TEXT NOT NULL REFERENCES users(id) ON DELETE CASCADE,
    title           TEXT,
    model_config_id TEXT REFERENCES model_configs(id) ON DELETE SET NULL,
    document_scope  TEXT DEFAULT '[]',
    created_at      TEXT NOT NULL DEFAULT (strftime('%Y-%m-%dT%H:%M:%fZ', 'now')),
    updated_at      TEXT NOT NULL DEFAULT (strftime('%Y-%m-%dT%H:%M:%fZ', 'now'))
);

CREATE INDEX IF NOT EXISTS idx_conversations_workspace ON conversations (workspace_id);
CREATE INDEX IF NOT EXISTS idx_conversations_user ON conversations (user_id);
CREATE INDEX IF NOT EXISTS idx_conversations_workspace_updated ON conversations (workspace_id, updated_at);

CREATE TABLE IF NOT EXISTS messages (
    id                  TEXT PRIMARY KEY DEFAULT (lower(hex(randomblob(4)) || '-' || hex(randomblob(2)) || '-4' || substr(hex(randomblob(2)),2) || '-' || substr('89ab',abs(random()) % 4 + 1, 1) || substr(hex(randomblob(2)),2) || '-' || hex(randomblob(6)))),
    conversation_id     TEXT NOT NULL REFERENCES conversations(id) ON DELETE CASCADE,
    role                TEXT NOT NULL CHECK (role IN ('user', 'assistant', 'system')),
    content             TEXT NOT NULL,
    model_name          TEXT,
    prompt_tokens       INTEGER,
    completion_tokens   INTEGER,
    latency_ms          INTEGER,
    evidence_report     TEXT,
    answer_status       TEXT DEFAULT 'draft',
    created_at          TEXT NOT NULL DEFAULT (strftime('%Y-%m-%dT%H:%M:%fZ', 'now'))
);

CREATE INDEX IF NOT EXISTS idx_messages_conversation ON messages (conversation_id, created_at);
CREATE INDEX IF NOT EXISTS idx_messages_conv_created ON messages (conversation_id, created_at);

CREATE TABLE IF NOT EXISTS citations (
    id              TEXT PRIMARY KEY DEFAULT (lower(hex(randomblob(4)) || '-' || hex(randomblob(2)) || '-4' || substr(hex(randomblob(2)),2) || '-' || substr('89ab',abs(random()) % 4 + 1, 1) || substr(hex(randomblob(2)),2) || '-' || hex(randomblob(6)))),
    message_id      TEXT NOT NULL REFERENCES messages(id) ON DELETE CASCADE,
    document_id     TEXT NOT NULL REFERENCES documents(id) ON DELETE CASCADE,
    chunk_id        TEXT NOT NULL REFERENCES document_chunks(id) ON DELETE CASCADE,
    citation_index  INTEGER NOT NULL,
    quoted_text     TEXT,
    page_number     INTEGER,
    heading_path    TEXT,
    paragraph_index INTEGER,
    char_start      INTEGER,
    char_end        INTEGER,
    relevance_score REAL,
    verified        INTEGER DEFAULT 0,
    created_at      TEXT NOT NULL DEFAULT (strftime('%Y-%m-%dT%H:%M:%fZ', 'now'))
);

CREATE INDEX IF NOT EXISTS idx_citations_message ON citations (message_id);
CREATE INDEX IF NOT EXISTS idx_citations_document ON citations (document_id);
CREATE INDEX IF NOT EXISTS idx_citations_chunk ON citations (chunk_id);

CREATE TABLE IF NOT EXISTS review_records (
    id              TEXT PRIMARY KEY DEFAULT (lower(hex(randomblob(4)) || '-' || hex(randomblob(2)) || '-4' || substr(hex(randomblob(2)),2) || '-' || substr('89ab',abs(random()) % 4 + 1, 1) || substr(hex(randomblob(2)),2) || '-' || hex(randomblob(6)))),
    citation_id     TEXT NOT NULL REFERENCES citations(id) ON DELETE CASCADE,
    reviewer_id     TEXT NOT NULL REFERENCES users(id) ON DELETE CASCADE,
    status          TEXT NOT NULL CHECK (status IN ('approved', 'rejected', 'flagged', 'pending')),
    comment         TEXT,
    corrected_text  TEXT,
    created_at      TEXT NOT NULL DEFAULT (strftime('%Y-%m-%dT%H:%M:%fZ', 'now')),
    updated_at      TEXT NOT NULL DEFAULT (strftime('%Y-%m-%dT%H:%M:%fZ', 'now'))
);

CREATE INDEX IF NOT EXISTS idx_reviews_citation ON review_records (citation_id);
CREATE INDEX IF NOT EXISTS idx_reviews_reviewer ON review_records (reviewer_id);
CREATE INDEX IF NOT EXISTS idx_reviews_citation_created ON review_records (citation_id, created_at);

CREATE TABLE IF NOT EXISTS entities (
    id              TEXT PRIMARY KEY DEFAULT (lower(hex(randomblob(4)) || '-' || hex(randomblob(2)) || '-4' || substr(hex(randomblob(2)),2) || '-' || substr('89ab',abs(random()) % 4 + 1, 1) || substr(hex(randomblob(2)),2) || '-' || hex(randomblob(6)))),
    workspace_id    TEXT NOT NULL REFERENCES workspaces(id) ON DELETE CASCADE,
    name            TEXT NOT NULL,
    entity_type     TEXT NOT NULL DEFAULT 'concept',
    document_id     TEXT REFERENCES documents(id) ON DELETE SET NULL,
    chunk_id        TEXT REFERENCES document_chunks(id) ON DELETE SET NULL,
    metadata        TEXT DEFAULT '{}',
    created_at      TEXT NOT NULL DEFAULT (strftime('%Y-%m-%dT%H:%M:%fZ', 'now'))
);

CREATE TABLE IF NOT EXISTS entity_relations (
    id                  TEXT PRIMARY KEY DEFAULT (lower(hex(randomblob(4)) || '-' || hex(randomblob(2)) || '-4' || substr(hex(randomblob(2)),2) || '-' || substr('89ab',abs(random()) % 4 + 1, 1) || substr(hex(randomblob(2)),2) || '-' || hex(randomblob(6)))),
    workspace_id        TEXT NOT NULL REFERENCES workspaces(id) ON DELETE CASCADE,
    source_entity_id    TEXT NOT NULL REFERENCES entities(id) ON DELETE CASCADE,
    target_entity_id    TEXT NOT NULL REFERENCES entities(id) ON DELETE CASCADE,
    relation_type       TEXT NOT NULL DEFAULT 'related_to',
    weight              REAL NOT NULL DEFAULT 1.0,
    metadata            TEXT DEFAULT '{}',
    created_at          TEXT NOT NULL DEFAULT (strftime('%Y-%m-%dT%H:%M:%fZ', 'now'))
);

CREATE INDEX IF NOT EXISTS idx_entities_workspace ON entities(workspace_id);
CREATE INDEX IF NOT EXISTS idx_entities_name ON entities(workspace_id, name);
CREATE INDEX IF NOT EXISTS idx_entity_relations_source ON entity_relations(source_entity_id);
CREATE INDEX IF NOT EXISTS idx_entity_relations_target ON entity_relations(target_entity_id);
CREATE INDEX IF NOT EXISTS idx_entity_relations_workspace ON entity_relations(workspace_id);

-- ============================================================
-- Equivalent of migrations 0007-0009: already inlined into
-- CREATE TABLE statements above (type, invite_code, domain_profile
-- on workspaces; metadata on documents).
-- Equivalent of migration 0008 (FTS5): already set up above.
-- ============================================================

-- ============================================================
-- Equivalent of migration 0010: audit trail
-- ============================================================

CREATE TABLE IF NOT EXISTS audit_trail (
    id              TEXT PRIMARY KEY DEFAULT (lower(hex(randomblob(4)) || '-' || hex(randomblob(2)) || '-4' || substr(hex(randomblob(2)),2) || '-' || substr('89ab',abs(random()) % 4 + 1, 1) || substr(hex(randomblob(2)),2) || '-' || hex(randomblob(6)))),
    workspace_id    TEXT REFERENCES workspaces(id) ON DELETE CASCADE,
    user_id         TEXT REFERENCES users(id) ON DELETE SET NULL,
    action          TEXT NOT NULL,
    entity_type     TEXT NOT NULL,
    entity_id       TEXT,
    details         TEXT DEFAULT '{}',
    ip_address      TEXT,
    created_at      TEXT NOT NULL DEFAULT (strftime('%Y-%m-%dT%H:%M:%fZ', 'now'))
);

CREATE INDEX IF NOT EXISTS idx_audit_workspace_time ON audit_trail (workspace_id, created_at);
CREATE INDEX IF NOT EXISTS idx_audit_user_time ON audit_trail (user_id, created_at);
CREATE INDEX IF NOT EXISTS idx_audit_action ON audit_trail (action, created_at);
CREATE INDEX IF NOT EXISTS idx_audit_entity ON audit_trail (entity_type, entity_id);

-- evidence_report and answer_status columns on messages are inlined above.

CREATE INDEX IF NOT EXISTS idx_messages_answer_status ON messages (answer_status);

-- ============================================================
-- Equivalent of migration 0012: retrieval traces
-- ============================================================

CREATE TABLE IF NOT EXISTS retrieval_traces (
    id                      TEXT PRIMARY KEY DEFAULT (lower(hex(randomblob(4)) || '-' || hex(randomblob(2)) || '-4' || substr(hex(randomblob(2)),2) || '-' || substr('89ab',abs(random()) % 4 + 1, 1) || substr(hex(randomblob(2)),2) || '-' || hex(randomblob(6)))),
    workspace_id            TEXT NOT NULL REFERENCES workspaces(id) ON DELETE CASCADE,
    message_id              TEXT REFERENCES messages(id) ON DELETE SET NULL,
    original_query          TEXT NOT NULL,
    rewritten_query         TEXT NOT NULL DEFAULT '',
    expanded_queries        TEXT NOT NULL DEFAULT '[]',
    search_results_count    INTEGER NOT NULL DEFAULT 0,
    reranked_results_count  INTEGER NOT NULL DEFAULT 0,
    final_sources_count     INTEGER NOT NULL DEFAULT 0,
    search_results          TEXT NOT NULL DEFAULT '[]',
    reranked_results        TEXT NOT NULL DEFAULT '[]',
    timings                 TEXT NOT NULL DEFAULT '{}',
    domain_profile          TEXT,
    created_at              TEXT NOT NULL DEFAULT (strftime('%Y-%m-%dT%H:%M:%fZ', 'now'))
);

CREATE INDEX IF NOT EXISTS idx_retrieval_traces_workspace ON retrieval_traces (workspace_id);
CREATE INDEX IF NOT EXISTS idx_retrieval_traces_message ON retrieval_traces (message_id);
CREATE INDEX IF NOT EXISTS idx_retrieval_traces_created ON retrieval_traces (created_at);

-- ============================================================
-- Equivalent of migration 0013: answer versions
-- ============================================================

CREATE TABLE IF NOT EXISTS answer_versions (
    id                  TEXT PRIMARY KEY DEFAULT (lower(hex(randomblob(4)) || '-' || hex(randomblob(2)) || '-4' || substr(hex(randomblob(2)),2) || '-' || substr('89ab',abs(random()) % 4 + 1, 1) || substr(hex(randomblob(2)),2) || '-' || hex(randomblob(6)))),
    message_id          TEXT NOT NULL REFERENCES messages(id) ON DELETE CASCADE,
    version_number      INTEGER NOT NULL DEFAULT 1,
    content             TEXT NOT NULL,
    answer_status       TEXT NOT NULL DEFAULT 'draft',
    retrieval_trace_id  TEXT REFERENCES retrieval_traces(id) ON DELETE SET NULL,
    reviewer_id         TEXT REFERENCES users(id) ON DELETE SET NULL,
    review_comment      TEXT,
    created_at          TEXT NOT NULL DEFAULT (strftime('%Y-%m-%dT%H:%M:%fZ', 'now')),
    UNIQUE (message_id, version_number)
);

CREATE INDEX IF NOT EXISTS idx_answer_versions_message ON answer_versions (message_id, version_number);
CREATE INDEX IF NOT EXISTS idx_answer_versions_status ON answer_versions (answer_status);

-- ============================================================
-- Equivalent of migration 0014: claim & answer reviews
-- ============================================================

CREATE TABLE IF NOT EXISTS claim_reviews (
    id                      TEXT PRIMARY KEY DEFAULT (lower(hex(randomblob(4)) || '-' || hex(randomblob(2)) || '-4' || substr(hex(randomblob(2)),2) || '-' || substr('89ab',abs(random()) % 4 + 1, 1) || substr(hex(randomblob(2)),2) || '-' || hex(randomblob(6)))),
    claim_id                TEXT NOT NULL,
    message_id              TEXT NOT NULL REFERENCES messages(id) ON DELETE CASCADE,
    reviewer_id             TEXT NOT NULL REFERENCES users(id) ON DELETE CASCADE,
    verdict                 TEXT NOT NULL CHECK (verdict IN ('supported', 'unsupported', 'partially_supported', 'unverifiable')),
    confidence              REAL CHECK (confidence >= 0.0 AND confidence <= 1.0),
    comment                 TEXT,
    evidence_references     TEXT NOT NULL DEFAULT '[]',
    created_at              TEXT NOT NULL DEFAULT (strftime('%Y-%m-%dT%H:%M:%fZ', 'now'))
);

CREATE INDEX IF NOT EXISTS idx_claim_reviews_claim ON claim_reviews (claim_id);
CREATE INDEX IF NOT EXISTS idx_claim_reviews_message ON claim_reviews (message_id);
CREATE INDEX IF NOT EXISTS idx_claim_reviews_reviewer ON claim_reviews (reviewer_id);

CREATE TABLE IF NOT EXISTS answer_reviews (
    id                      TEXT PRIMARY KEY DEFAULT (lower(hex(randomblob(4)) || '-' || hex(randomblob(2)) || '-4' || substr(hex(randomblob(2)),2) || '-' || substr('89ab',abs(random()) % 4 + 1, 1) || substr(hex(randomblob(2)),2) || '-' || hex(randomblob(6)))),
    message_id              TEXT NOT NULL REFERENCES messages(id) ON DELETE CASCADE,
    answer_version_id       TEXT REFERENCES answer_versions(id) ON DELETE SET NULL,
    reviewer_id             TEXT NOT NULL REFERENCES users(id) ON DELETE CASCADE,
    overall_verdict         TEXT NOT NULL CHECK (overall_verdict IN ('approved', 'rejected', 'needs_revision', 'escalated')),
    accuracy_score          REAL CHECK (accuracy_score >= 0.0 AND accuracy_score <= 1.0),
    completeness_score      REAL CHECK (completeness_score >= 0.0 AND completeness_score <= 1.0),
    clarity_score           REAL CHECK (clarity_score >= 0.0 AND clarity_score <= 1.0),
    comment                 TEXT,
    revision_instructions   TEXT,
    created_at              TEXT NOT NULL DEFAULT (strftime('%Y-%m-%dT%H:%M:%fZ', 'now'))
);

CREATE INDEX IF NOT EXISTS idx_answer_reviews_message ON answer_reviews (message_id);
CREATE INDEX IF NOT EXISTS idx_answer_reviews_version ON answer_reviews (answer_version_id);
CREATE INDEX IF NOT EXISTS idx_answer_reviews_reviewer ON answer_reviews (reviewer_id);
CREATE INDEX IF NOT EXISTS idx_answer_reviews_verdict ON answer_reviews (overall_verdict);

-- ============================================================
-- Equivalent of migration 0015: fuzzy search (pg_trgm)
-- ============================================================

-- pg_trgm extension is PostgreSQL-specific.
-- SQLite fuzzy search falls back to FTS5 MATCH in the application layer.
-- No additional schema changes needed.

-- ============================================================
-- Equivalent of migration 0016: document_metadata table
-- ============================================================

CREATE TABLE IF NOT EXISTS document_metadata (
    id              TEXT PRIMARY KEY DEFAULT (lower(hex(randomblob(4)) || '-' || hex(randomblob(2)) || '-4' || substr(hex(randomblob(2)),2) || '-' || substr('89ab',abs(random()) % 4 + 1, 1) || substr(hex(randomblob(2)),2) || '-' || hex(randomblob(6)))),
    document_id     TEXT NOT NULL REFERENCES documents(id) ON DELETE CASCADE,
    workspace_id    TEXT NOT NULL,

    domain          TEXT,
    sub_domain      TEXT,
    document_type   TEXT,
    language        TEXT,

    authority       TEXT,
    author          TEXT,
    publisher       TEXT,
    source_url      TEXT,

    publish_date    TEXT,
    effective_date  TEXT,
    expiry_date     TEXT,
    fiscal_year     INTEGER,

    jurisdiction    TEXT,
    regulation_id   TEXT,
    case_number     TEXT,

    ticker_symbol   TEXT,
    report_type     TEXT,
    currency        TEXT,

    doi             TEXT,
    pmid            TEXT,
    clinical_trial_id TEXT,

    confidence_score REAL DEFAULT 0.0,
    is_verified     INTEGER DEFAULT 0,
    verified_by     TEXT,
    verified_at     TEXT,

    tags            TEXT DEFAULT '[]',
    extra           TEXT DEFAULT '{}',

    created_at      TEXT NOT NULL DEFAULT (strftime('%Y-%m-%dT%H:%M:%fZ', 'now')),
    updated_at      TEXT NOT NULL DEFAULT (strftime('%Y-%m-%dT%H:%M:%fZ', 'now')),

    UNIQUE (document_id)
);

CREATE INDEX IF NOT EXISTS idx_doc_meta_workspace ON document_metadata(workspace_id);
CREATE INDEX IF NOT EXISTS idx_doc_meta_domain ON document_metadata(domain);
CREATE INDEX IF NOT EXISTS idx_doc_meta_language ON document_metadata(language);
CREATE INDEX IF NOT EXISTS idx_doc_meta_authority ON document_metadata(authority);
CREATE INDEX IF NOT EXISTS idx_doc_meta_jurisdiction ON document_metadata(jurisdiction);
CREATE INDEX IF NOT EXISTS idx_doc_meta_fiscal_year ON document_metadata(fiscal_year);
CREATE INDEX IF NOT EXISTS idx_doc_meta_document_type ON document_metadata(document_type);

-- ============================================================
-- Equivalent of migration 0017: review workflow tables
-- ============================================================

CREATE TABLE IF NOT EXISTS review_tasks (
    id              TEXT PRIMARY KEY DEFAULT (lower(hex(randomblob(4)) || '-' || hex(randomblob(2)) || '-4' || substr(hex(randomblob(2)),2) || '-' || substr('89ab',abs(random()) % 4 + 1, 1) || substr(hex(randomblob(2)),2) || '-' || hex(randomblob(6)))),
    workspace_id    TEXT NOT NULL,
    message_id      TEXT,
    answer_version_id TEXT,
    title           TEXT NOT NULL,
    description     TEXT,
    task_type       TEXT NOT NULL DEFAULT 'general',
    priority        INTEGER NOT NULL DEFAULT 3,
    status          TEXT NOT NULL DEFAULT 'open',
    assigned_to     TEXT,
    created_by      TEXT,
    due_date        TEXT,
    completed_at    TEXT,
    tags            TEXT DEFAULT '[]',
    metadata        TEXT DEFAULT '{}',
    created_at      TEXT NOT NULL DEFAULT (strftime('%Y-%m-%dT%H:%M:%fZ', 'now')),
    updated_at      TEXT NOT NULL DEFAULT (strftime('%Y-%m-%dT%H:%M:%fZ', 'now'))
);

CREATE INDEX IF NOT EXISTS idx_review_tasks_workspace ON review_tasks(workspace_id);
CREATE INDEX IF NOT EXISTS idx_review_tasks_status ON review_tasks(status);
CREATE INDEX IF NOT EXISTS idx_review_tasks_assigned ON review_tasks(assigned_to);
CREATE INDEX IF NOT EXISTS idx_review_tasks_message ON review_tasks(message_id);
CREATE INDEX IF NOT EXISTS idx_review_tasks_priority ON review_tasks(priority);

CREATE TABLE IF NOT EXISTS review_comments (
    id                  TEXT PRIMARY KEY DEFAULT (lower(hex(randomblob(4)) || '-' || hex(randomblob(2)) || '-4' || substr(hex(randomblob(2)),2) || '-' || substr('89ab',abs(random()) % 4 + 1, 1) || substr(hex(randomblob(2)),2) || '-' || hex(randomblob(6)))),
    review_task_id      TEXT NOT NULL REFERENCES review_tasks(id) ON DELETE CASCADE,
    parent_comment_id   TEXT REFERENCES review_comments(id) ON DELETE SET NULL,
    author_id           TEXT,
    content             TEXT NOT NULL,
    comment_type        TEXT NOT NULL DEFAULT 'comment',
    resolved            INTEGER NOT NULL DEFAULT 0,
    resolved_at         TEXT,
    resolved_by         TEXT,
    metadata            TEXT DEFAULT '{}',
    created_at          TEXT NOT NULL DEFAULT (strftime('%Y-%m-%dT%H:%M:%fZ', 'now')),
    updated_at          TEXT NOT NULL DEFAULT (strftime('%Y-%m-%dT%H:%M:%fZ', 'now'))
);

CREATE INDEX IF NOT EXISTS idx_review_comments_task ON review_comments(review_task_id);
CREATE INDEX IF NOT EXISTS idx_review_comments_parent ON review_comments(parent_comment_id);
CREATE INDEX IF NOT EXISTS idx_review_comments_author ON review_comments(author_id);

CREATE TABLE IF NOT EXISTS source_reviews (
    id              TEXT PRIMARY KEY DEFAULT (lower(hex(randomblob(4)) || '-' || hex(randomblob(2)) || '-4' || substr(hex(randomblob(2)),2) || '-' || substr('89ab',abs(random()) % 4 + 1, 1) || substr(hex(randomblob(2)),2) || '-' || hex(randomblob(6)))),
    workspace_id    TEXT NOT NULL,
    document_id     TEXT NOT NULL,
    chunk_id        TEXT,
    review_task_id  TEXT REFERENCES review_tasks(id) ON DELETE SET NULL,
    reviewer_id     TEXT,
    verdict         TEXT NOT NULL DEFAULT 'pending',
    relevance_score REAL,
    accuracy_score  REAL,
    freshness_score REAL,
    authority_score REAL,
    overall_score   REAL,
    notes           TEXT,
    is_trusted      INTEGER DEFAULT NULL,
    flagged_issues  TEXT DEFAULT '[]',
    metadata        TEXT DEFAULT '{}',
    created_at      TEXT NOT NULL DEFAULT (strftime('%Y-%m-%dT%H:%M:%fZ', 'now')),
    updated_at      TEXT NOT NULL DEFAULT (strftime('%Y-%m-%dT%H:%M:%fZ', 'now'))
);

CREATE INDEX IF NOT EXISTS idx_source_reviews_workspace ON source_reviews(workspace_id);
CREATE INDEX IF NOT EXISTS idx_source_reviews_document ON source_reviews(document_id);
CREATE INDEX IF NOT EXISTS idx_source_reviews_task ON source_reviews(review_task_id);
CREATE INDEX IF NOT EXISTS idx_source_reviews_verdict ON source_reviews(verdict);
